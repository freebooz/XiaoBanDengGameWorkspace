extends SceneTree
## Native Godot product clients using the freshly built Go HTTP/WebSocket test listener.

var apps: Array = []
var preview_dir := ""
var stop_at := 0

func _initialize() -> void: call_deferred("_run")

func _until(condition: Callable, message: String) -> bool:
	while not condition.call():
		if Time.get_ticks_msec()>=stop_at:
			push_error(message)
			return false
		await process_frame
	return true

func _button(app: Node, name: String) -> Button:
	return app.find_child(name,true,false) as Button

func _press(app: Control, name: String) -> bool:
	var button := _button(app,name)
	if not is_instance_valid(button) or button.disabled:
		push_error("原生按钮不可用: " + name)
		return false
	var was_visible := app.visible
	app.show()
	var available := button.is_visible_in_tree()
	if available: button.pressed.emit()
	app.visible = was_visible
	if not available: push_error("原生按钮不可见: " + name)
	return available

func _table(app: Node) -> Variant:
	for node in app._screen.get_children():
		if not node.is_queued_for_deletion() and node.has_signal("match_finished"): return node
	return null

func _capture(file: String) -> void:
	if preview_dir.is_empty() or DisplayServer.get_name()=="headless": return
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(preview_dir.path_join(file))
	if error!=OK: push_error("截图失败: " + file)

func _leave_board(game: Node) -> bool:
	game._open_tool("leave")
	return _press(game,"MahjongLeaveConfirm")

func _cleanup() -> void:
	for app in apps:
		if is_instance_valid(app): app.queue_free()
	apps.clear()
	await process_frame
	await create_timer(0.15).timeout

func _run() -> void:
	var user_args := OS.get_cmdline_user_args()
	var spectators := user_args.has("--spectators")
	for arg in user_args:
		if arg.begins_with("--server-url="):
			ProjectSettings.set_setting("xiaobandeng/network/default_server_url", arg.trim_prefix("--server-url="))
		if arg.begins_with("--preview-dir="): preview_dir=arg.trim_prefix("--preview-dir=")
	var vsync := DisplayServer.window_get_vsync_mode()
	print("MAHJONG_NATIVE_LIMITS max_fps=",Engine.max_fps," vsync=",vsync)
	if Engine.max_fps!=0 or (DisplayServer.get_name()!="headless" and vsync!=DisplayServer.VSYNC_DISABLED):
		push_error("原生验证未解除帧率限制")
		quit(1)
		return
	stop_at=Time.get_ticks_msec()+85000
	var script = load("res://scripts/main.gd")
	for index in range(5 if spectators else 4):
		var app = script.new()
		app.session_store_path = "user://fixtures/native-%d-%d" % [Time.get_ticks_usec(), index]
		app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(app)
		app.visible=index==0
		apps.append(app)
		app._http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
			if result != HTTPRequest.RESULT_SUCCESS or code >= 400:
				print("MAHJONG_NATIVE_HTTP result=", result, " code=", code))
	var passed := false
	if await _enter_lobbies():
		passed = await _exercise_spectators() if spectators else await _exercise()
	if not passed:
		await _cleanup()
		quit(1)
		return
	await _cleanup()
	if spectators:
		print("MAHJONG_NATIVE_SPECTATORS_OK guests=5 seat_permission=true directory=true waiting=true discard=true read_only=true revoke=true")
	else:
		print("MAHJONG_NATIVE_LOBBY_OK four_clients=true quick_cancel=true rule_lock=true invite=true readiness=true resume=true settlement=true history=true training_bots=true abandon=true")
	quit(0)

func _enter_lobbies() -> bool:
	if not await _until(func(): return apps.all(func(app): return app._state=="login" and not app._guest_button.disabled),"游客入口未就绪"): return false
	for app in apps:
		if not _press(app, "MahjongGuestLoginButton"): return false
	if not await _until(func(): return apps.all(func(app): return app._state=="guest_identity" and not app._lobby_socket.is_processing()),"游客身份确认页未就绪"): return false
	for app in apps:
		if not _press(app, "MahjongGuestEnterLobbyButton"): return false
	return await _until(func(): return apps.all(func(app): return app._state=="lobby" and app._lobby_synced),"大厅没有收到真实初始事件")


func _exercise() -> bool:
	var host = apps[0]
	var lobby_scale := root.content_scale_size
	await _capture("lobby.png")
	if not _press(host,"MahjongQuickButton"): return false
	if not await _until(func(): return host._state=="room" and host._match.get("kind","")=="quick","快速开局没有进入实际队列"): return false
	if not _press(host,"MahjongLeaveButton"): return false
	if not await _until(func(): return host._state=="lobby" and host._match.get("status","")=="idle","取消匹配仍占用房间"): return false
	if not _press(host,"MahjongCreateButton") or not _press(host,"MahjongCreateRuleSelector") or not _press(host,"MahjongCreateRuleCard_basic_108_1_0_0"): return false
	await _capture("create_rules.png")
	if not _press(host,"MahjongCustomRulesCreateButton"): return false
	if not await _until(func(): return host._state=="room" and str(host._match.get("kind",""))=="friend","未创建实际好友房"): return false
	var code := str(host._match.room_id)
	if code.length()!=4: return false
	for index in range(1,4):
		if not _press(apps[index],"MahjongOpenJoinButton"): return false
		var code_field := apps[index].find_child("MahjongJoinCode",true,false) as LineEdit
		var join_panel := apps[index].find_child("MahjongJoinPanel",true,false) as PanelContainer
		if not is_instance_valid(code_field) or not is_instance_valid(join_panel) or not join_panel.visible:
			push_error("加入房间未展开四位房号表单")
			return false
		code_field.text=code
		code_field.text_changed.emit(code)
		if not _press(apps[index],"MahjongJoinButton"): return false
	if not await _until(func(): return apps.all(func(app): return app._state=="room" and app._match.get("player_account_ids",[]).size()==4 and app._match.get("rule_set_id","")=="basic_108"),"好友房四座或锁定规则不同步"): return false
	for index in range(1,4):
		if not _press(apps[index],"MahjongReadyButton"): return false
	if not await _until(func(): return int(host._match.get("ready_players",0))==3,"等候房未收到三位准备事件"): return false
	await _capture("friend_room.png")
	if not _press(host,"MahjongReadyButton"): return false
	if not await _until(func():
		return apps.all(func(app):
			var game = _table(app)
			return is_instance_valid(game) and game._actions_ready() and str(game._state.get("status",""))=="playing"),
		"好友房未进入四张独立真实牌桌"): return false
	var first = _table(host)
	var first_id: int = first.get_instance_id()
	var match_id := str(first._state.get("match_id",""))
	var seen: Dictionary = {}
	for app in apps:
		var game = _table(app)
		if match_id.is_empty() or game._state.match_id!=match_id or game._state.rule_set_id!="basic_108" or game._state.has("wall"): return false
		for tile in game._array("hand"):
			if seen.has(int(tile.id)): return false
			seen[int(tile.id)]=true
	if seen.size()!=53: return false
	await _capture("friend_table.png")
	if not _leave_board(first): return false
	if not await _until(func(): return host._state=="lobby" and host._match.get("status","")=="playing","暂离后无法在大厅恢复原房"): return false
	if not _press(host,"MahjongResumeButton"): return false
	if not await _until(func():
		var board = _table(host)
		return is_instance_valid(board) and board.get_instance_id()!=first_id and board._actions_ready() and str(board._state.get("match_id",""))==match_id,
		"回桌没有恢复原对局"): return false
	if not await _until(func(): return _drive_friend_round(),"好友房未能完成真实摸打及结算"): return false
	for app in apps:
		if app._recent.size()!=1 or app._recent[0].match_id!=match_id or app._recent[0].kind!="friend": return false
		_table(app)._return_now()
	if not await _until(func(): return host._state=="lobby" and host._match.get("status","")=="idle" and root.content_scale_size==lobby_scale,"结算后未回到大厅及原始显示"): return false
	await _capture("recent.png")
	if not _press(host,"MahjongTrainingHallButton") or not _press(host,"MahjongTrainingButton"): return false
	if not await _until(func():
		var game = _table(host)
		return is_instance_valid(game) and game._actions_ready() and game._state.get("status","")=="playing" and game._state.get("kind","")=="training",
		"训练房未接入实际服务端规则"): return false
	var training = _table(host)
	if training.training_mode or training._state.rule_set_id!="guiyang" or int(training._state.get("action_timeout_seconds",0))!=45: return false
	await _capture("training.png")
	var hand: Array = training._array("hand")
	training._select_tile(int(hand[0].id))
	training._on_play()
	if not await _until(func():
		var seat := int(training._state.get("your_seat",0))
		return training._array("discards").any(func(item): return int(item.seat)!=seat),
		"训练机器没有通过权威引擎行动"): return false
	if not _leave_board(training): return false
	if not await _until(func(): return host._state=="lobby" and host._match.get("status","")=="idle","退出训练仍占用房间"): return false
	return host._recent.size()==1

func _exercise_spectators() -> bool:
	var host = apps[0]
	var viewer = apps[4]
	if not _press(host, "MahjongCreateButton"): return false
	var allow := _button(host, "MahjongAllowSpectators")
	if allow == null or not allow.is_visible_in_tree() or allow.button_pressed: return false
	allow.button_pressed = true
	await _capture("spectator_create.png")
	if not _press(host, "MahjongCustomRulesCreateButton"): return false
	if not await _until(func(): return host._state == "room" and host._match.get("allow_spectators", false),
			"创建房间的观战开关未生效"): return false
	var room_id := str(host._match.room_id)
	var consent := _button(host, "MahjongSeatWatchPermission")
	if consent == null or host._match.get("spectator_allowed", false): return false
	if not _press(host, "MahjongSeatWatchPermission"): return false
	if not await _until(func(): return host._match.get("spectator_allowed", false), "未收到座位同意通知"): return false
	await _capture("spectator_seat_permission.png")
	host.hide()
	viewer.show()
	if not _press(viewer, "MahjongRoomListButton"): return false
	var directory_watch := "MahjongDirectoryWatch" + room_id
	if not await _until(func(): return _button(viewer, directory_watch) != null, "房间列表未显示可观战入口"): return false
	await _capture("spectator_directory.png")
	if not _press(viewer, directory_watch): return false
	var field := viewer.find_child("MahjongJoinCode", true, false) as LineEdit
	var seat := viewer.find_child("MahjongWatchSeat", true, false) as OptionButton
	if field == null or field.text != room_id or seat == null or seat.get_selected_id() != 0: return false
	await _capture("spectator_join.png")
	if not _press(viewer, "MahjongWatchRoomButton"): return false
	if not await _until(func():
		var board = _table(viewer)
		return is_instance_valid(board) and board._snapshot_ready and board._state.get("status") == "waiting",
		"观战者未收到等候快照"): return false
	var watching = _table(viewer)
	if viewer._subscribe_lobby() != OK: return false
	if not await _until(func(): return host._match.get("spectator_occupied", false), "座位未收到观战人数"): return false
	for index in range(1, 4):
		var app = apps[index]
		if not _press(app, "MahjongOpenJoinButton"): return false
		var code := app.find_child("MahjongJoinCode", true, false) as LineEdit
		if code == null: return false
		code.text = room_id
		code.text_changed.emit(room_id)
		if not _press(app, "MahjongJoinButton"): return false
	if not await _until(func(): return apps.slice(0, 4).all(func(app): return app._state == "room" and app._match.get("player_account_ids", []).size() == 4),
			"观战连接占用或影响了四个玩家座位"): return false
	for app in apps.slice(0, 4):
		if not _press(app, "MahjongReadyButton"): return false
	if not await _until(func():
		return _table(viewer) == watching and watching._state.get("status") == "playing" and apps.slice(0, 4).all(
			func(app): return is_instance_valid(_table(app)) and _table(app)._actions_ready()),
		"观战者未跟随四位玩家开局"): return false
	if watching._actions_ready() or watching._play_button.visible or watching._own_mic.visible or not watching._hand_ids.is_empty():
		push_error("观战错误显示了出牌、语音或暗手牌")
		return false
	if not watching._remaining_number.text.is_valid_int():
		push_error("观战未显示服务端回合同步的倒计时")
		return false
	for relative in range(4):
		if watching._pieces_root.get_node_or_null("MahjongConcealedHand%d_0" % relative) == null:
			push_error("观战视角未保留第 %d 席扣着的牌" % relative)
			return false
	var dealer = _table(apps[int(watching._state.dealer)])
	var hand: Array = dealer._array("hand")
	if hand.is_empty(): return false
	var tile := int(hand[0].id)
	dealer._select_tile(tile)
	dealer._on_play()
	if not await _until(func():
		return watching._array("discards").any(func(discard: Dictionary): return int(discard.get("tile", {}).get("id", -1)) == tile),
		"观战者未收到首张公开弃牌"): return false
	await _capture("spectator_board.png")
	var host_board = _table(host)
	host_board._open_tool("settings")
	var toggle := _button(host_board, "MahjongTableSpectatorPermission")
	if toggle == null or not toggle.button_pressed or toggle.disabled: return false
	toggle.button_pressed = false
	if not await _until(func():
		return viewer._state == "lobby" and not host_board._state.get("spectator_allowed", true) and not host_board._state.get("spectator_occupied", true),
		"关闭观战后客户端未结束观战或未刷新座位人数"): return false
	return viewer._recent.is_empty() and viewer._match.get("status") == "idle"


func _drive_friend_round() -> bool:
	var finished := 0
	for app in apps:
		var game = _table(app)
		if not is_instance_valid(game): return false
		if game._state.get("phase","")=="finished":
			finished+=1
			continue
		if game._pending_action or not game._actions_ready(): continue
		if not game._legal_options("hu").is_empty():
			game._on_response("hu")
		elif not game._legal_options("pass").is_empty():
			game._on_response("pass")
		elif not game._legal_options("play").is_empty() and not game._array("hand").is_empty():
			game._select_tile(int(game._array("hand")[0].id))
			game._on_play()
	return finished==4
