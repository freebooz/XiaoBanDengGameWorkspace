extends SceneTree
## Product state and command intent; transport is covered by the native loopback test.

class AppFixture:
	extends "res://scripts/main.gd"
	var sent: Array[Dictionary] = []
	var entered: Dictionary = {}
	var quit_requested := false
	var enter_real_board := false
	func _request_health() -> void: _show_login()
	func _send_lobby_packet(packet: Dictionary) -> Error:
		sent.append(packet.duplicate(true))
		return OK
	func _enter_game() -> void:
		if enter_real_board:
			super._enter_game()
			return
		entered = _match.duplicate(true)
		_state = "game"
	func _quit_game() -> void: quit_requested = true
	func _send_egg_request(_request: HTTPRequest, _url: String, _token: String) -> Error: return OK

class SettledBoard:
	extends Control
	var match_context := {"room_id":"0421", "completed_rounds":0}
	func finished_friend_match_id() -> String: return "finished-hand"

var failures := 0

func _initialize() -> void: call_deferred("_run")

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var app := AppFixture.new()
	root.add_child(app)
	if not app.has_method("_on_lobby_state"):
		push_error("麻将大厅没有消费服务端玩法与房间事件")
		quit(1)
		return
	app._account = {"account_id": "host", "display_name": "测试牌友"}
	app._show_lobby()
	_check_coach_setting(app)
	var presets: Array = [
		{"rule_set_id":"guiyang","rule_version":"2.0.0","name":"贵阳捉鸡","summary":"翻鸡","allow_chi":false,"chicken":true,"requires_kong_to_claim":true},
		{"rule_set_id":"basic_108","rule_version":"1.0.0","name":"基础 108","summary":"不翻鸡","allow_chi":false,"chicken":false,"requires_kong_to_claim":false}
	]
	app._on_lobby_action("quick", {})
	_expect(app.sent.is_empty(), "未取得当前大厅快照就提交匹配")
	app._on_lobby_state({"status":"idle"}, presets)
	var default_rule := app._selected_rule.duplicate()
	app._on_lobby_action("create", {"rule_set_id":"basic_108","rule_version":"invalid"})
	_expect(app.sent.is_empty(), "建房不得提交服务端未发布的玩法")
	var choice := {"rule_set_id":"basic_108","rule_version":"1.0.0"}
	app._on_lobby_action("create", choice)
	app._on_lobby_action("create", choice)
	_expect(app.sent.size()==1 and app.sent[0].action=="create" and app.sent[0].rule_set_id=="basic_108" and app.sent[0].rule_version=="1.0.0", "创建未采用已选择玩法或重复提交")
	_expect(app._selected_rule == default_rule, "建房玩法不应改变快速匹配和训练默认玩法")
	var create_id: String = app.sent[0].command_id
	app._on_lobby_result("unrelated", true, "")
	_expect(app._pending_lobby_id==create_id, "无关响应解除提交等待")
	app._on_lobby_result(create_id, true, "")
	app._on_lobby_state({"status":"waiting","kind":"friend","room_id":"0421","rule_set_id":"basic_108","rule_version":"1.0.0","player_account_ids":["host"],"ready_account_ids":[],"ready_players":0,"capacity":4,"start":false,"seat_index":0}, presets)
	_expect(app._state=="room" and app._match.room_id=="0421", "房间事件没有打开实际等候房")
	app._on_lobby_action("ready", {})
	_expect(app.sent.size()==2 and app.sent[1].action=="ready" and app.sent[1].room_id=="0421", "好友房未满座时应该发送准备")
	app._on_lobby_result(str(app.sent[1].command_id), true, "")
	var full: Dictionary = app._match.duplicate(true)
	full["status"]="matched"
	full["player_account_ids"]=["host","friend-a","friend-b","friend-c"]
	full["ready_account_ids"]=["host"]
	full["ready_players"]=1
	app._on_lobby_state(full, presets)
	app._on_lobby_action("unready", {})
	_expect(app.sent.size()==3 and app.sent[2].action=="unready", "满座后仍应允许取消原有准备")
	app._on_lobby_result(str(app.sent[2].command_id), true, "")
	full["ready_account_ids"]=[]
	full["ready_players"]=0
	app._on_lobby_state(full, presets)
	app._on_lobby_action("ready", {})
	_expect(app.sent.size()==4 and app.sent[3].action=="ready" and app.sent[3].room_id=="0421", "满座后准备命令未绑定当前房号")
	app._on_lobby_result(str(app.sent[3].command_id), true, "")
	full["status"]="playing"
	full["start"]=true
	app._on_lobby_state(full, presets)
	_expect(app._state=="game" and app.entered.rule_set_id=="basic_108", "开局没有使用房间锁定的规则")
	app._return_to_lobby()
	_expect(app._state=="lobby" and app._match.room_id=="0421", "暂离后丢失了可恢复的房间")
	app._on_lobby_action("resume", {})
	_expect(app._state=="game", "返回牌桌没有恢复实际房间")
	app._return_to_lobby()
	var board: Node = app._make_game(false, full.duplicate(true))
	var timed_out: Dictionary = full.duplicate(true)
	timed_out.status = "matched"
	timed_out.start = false
	app._on_lobby_state(timed_out, presets)
	_expect(is_instance_valid(board) and board.is_queued_for_deletion() and app._state in ["lobby", "room"] and not app._lobby_message.is_empty(),
		"牌桌完全未连通时，大厅的权威回退必须结束本次入桌")
	_check_rematch(presets)
	await _check_settlement_room_return(presets, false)
	await _check_settlement_room_return(presets, true)
	_check_lobby_recovery(presets)
	_check_egg_balance(presets)
	await _check_navigation(presets)
	app.queue_free()
	await process_frame
	if not OS.has_feature("mobile") and DisplayServer.get_name() != "headless":
		await _check_rematch_window_size(presets, Vector2i(744, 860), true)
		await _check_rematch_window_size(presets, Vector2i(1008, 630), false)
	if failures==0: print("MAHJONG_LOBBY_APP_OK selected_rule=true state_driven=true duplicate_guard=true return_to_room=true rematch_click_ready=true")
	quit(0 if failures==0 else 1)


func _check_coach_setting(app: AppFixture) -> void:
	var previous_file: String = app._audio.preference_file
	app._audio.preference_file = "user://coach-lobby-fixture-%d.cfg" % OS.get_process_id()
	app._open_settings()
	var overlay := app._screen.get_node("MahjongGlobalSettings")
	var toggle := overlay.find_child("MahjongCoachToggle", true, false) as Button
	_expect(toggle != null and not toggle.button_pressed, "大厅设置应默认关闭向听和进张标签")
	if toggle != null:
		toggle.toggled.emit(true)
		var preferences := ConfigFile.new()
		_expect(preferences.load(app._audio.preference_file) == OK, "大厅标签开关应保存设置")
		_expect(toggle.button_pressed and preferences.get_value("assistance", "efficiency_labels", false),
			"大厅开启标签应写入牌桌读取的设置项")
	overlay.free()
	app._audio.preference_file = previous_file


func _check_egg_balance(presets: Array) -> void:
	var app := AppFixture.new()
	root.add_child(app)
	app._account = {"account_id":"host", "display_name":"田埂阿牛"}
	app._show_lobby()
	app._on_lobby_state({"status":"idle"}, presets)
	app._session_token = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
	app._session_server = "https://127.0.0.1"
	app._refresh_eggs()
	var request: HTTPRequest = app._egg_request
	var body := JSON.stringify({"account_id":"host", "asset_id":"xbd_egg", "scope":"family", "amount":100}).to_utf8_buffer()
	request.request_completed.emit(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), body)
	var balance := app.find_child("MahjongEggBalanceButton", true, false) as Button
	_expect(balance.is_visible_in_tree() and balance.text == "鸡蛋 100", "游客鸡蛋余额由服务端返回并投影到大厅")
	app._clear_live_session()
	request.request_completed.emit(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), body)
	_expect(app._egg_balance == -1, "退出账号后迟到的余额回执不能恢复旧账号界面")
	app.queue_free()


func _check_navigation(presets: Array) -> void:
	var app := AppFixture.new()
	root.add_child(app)
	app._account = {"account_id":"host", "display_name":"田埂阿牛", "kind":"named"}
	app._show_lobby()
	app._on_lobby_state({"status":"idle"}, presets)
	var leave_game := app.find_child("MahjongLobbyExitButton", true, false) as Button
	var back := app.find_child("MahjongLobbyBackButton", true, false) as Button
	_expect(leave_game != null and back != null, "大厅缺少返回或退出游戏入口")
	if leave_game != null:
		leave_game.pressed.emit()
		var prompt := app.find_child("MahjongExitGameDialog", true, false) as Control
		_expect(prompt != null and prompt.visible and not app.quit_requested, "大厅退出应先询问玩家")
		if prompt != null:
			(prompt.call("get_cancel_button") as Button).pressed.emit()
			await process_frame
			_expect(not app.quit_requested and (not is_instance_valid(prompt) or not prompt.visible), "取消退出应留在大厅")
			leave_game.pressed.emit()
			prompt = app.find_child("MahjongExitGameDialog", true, false) as Control
			_expect(prompt != null and prompt.visible, "再次退出应创建新的确认弹窗")
			if prompt != null: (prompt.call("get_ok_button") as Button).pressed.emit()
			_expect(app.quit_requested, "确认退出未调用退出游戏")
	app._lobby_view._open_room_page("directory")
	app._on_lobby_state({"status":"waiting", "kind":"friend", "room_id":"7158", "capacity":4,
		"player_account_ids":["host"], "ready_account_ids":[], "ready_players":0}, presets)
	var leave_room := app.find_child("MahjongLeaveButton", true, false) as Button
	leave_room.pressed.emit()
	var release_id: String = app._pending_lobby_id
	app._on_lobby_result(release_id, true, "", "", {"status":"idle"})
	await process_frame
	_expect(not release_id.is_empty() and app._lobby_view._page == "directory", "从公开房间返回后应重新看到房间列表")
	app._lobby_view._on_room_page_action("page_home", {})
	app._lobby_view._set_training_open(true)
	app._on_lobby_action("practice", {})
	if is_instance_valid(app._game):
		app._game.request_return_to_lobby.emit()
		_expect(app._lobby_view._page == "training", "摸打牌桌没有返回训练场")
	else:
		_expect(false, "无法打开摸打练习")
	app._lobby_view._set_training_open(false)
	app._on_lobby_state({"status":"playing", "kind":"friend", "room_id":"7158", "start":true}, presets)
	leave_room = app._lobby_view.find_child("MahjongLeaveButton", true, false) as Button
	leave_room.pressed.emit()
	var resume := app._lobby_view.find_child("MahjongLobbyResumeButton", true, false) as Button
	_expect(is_instance_valid(resume) and resume.is_visible_in_tree() and not resume.disabled and app._match.room_id == "7158",
		"返回大厅后应保留原牌桌入口")
	back = app._lobby_view.find_child("MahjongLobbyBackButton", true, false) as Button
	if back != null:
		back.pressed.emit()
		_expect(app._state == "login" and app._login_identifier != null and app._match.is_empty(), "账号用户从大厅应返回统一账号登录页")
	app.queue_free()


func _check_lobby_recovery(presets: Array) -> void:
	var app := AppFixture.new()
	root.add_child(app)
	app._account = {"account_id":"host", "display_name":"测试牌友"}
	app._show_lobby()
	var idle := {"status":"idle"}
	var matched := {"status":"matched", "kind":"friend", "room_id":"7158", "capacity":4,
		"player_account_ids":["host","a","b","c"], "ready_account_ids":[], "ready_players":0}
	app._on_lobby_state(matched, presets)
	app._on_lobby_action("ready", {})
	var ready_id: String = app.sent[-1].command_id
	var ready := matched.duplicate(true)
	ready.ready_account_ids = ["host"]
	ready.ready_players = 1
	# A push can arrive before the result. The matching result alone must unblock the buttons.
	app._on_lobby_state(ready, presets)
	_expect(app._pending_lobby_id == ready_id, "其他玩家的房间事件不能解除操作等待")
	app._on_lobby_packet(JSON.stringify({"type":"mahjong_lobby_result", "command_id":ready_id, "ok":true, "state":ready}))
	_expect(app._pending_lobby_id.is_empty() and app._match.ready_account_ids == ["host"], "准备回执未立即恢复房间操作")
	app._on_lobby_action("leave", {})
	if app.sent[-1].action != "leave":
		_expect(false, "准备成功后无法点击离开房间")
		app.queue_free()
		return
	app._on_lobby_packet(JSON.stringify({"type":"mahjong_lobby_result", "command_id":app.sent[-1].command_id, "ok":true, "state":idle}))
	_expect(app._state == "lobby" and app._pending_lobby_id.is_empty(), "离开回执未返回大厅")
	var directory := {"type":"mahjong_lobby_state", "state":idle, "presets":presets,
		"room_directory":true, "room_directory_requests":true}
	app._on_lobby_packet(JSON.stringify(directory))
	app._on_lobby_action("refresh_rooms", {})
	var first_request := str(app.sent[-1].get("request_id", ""))
	_expect(not first_request.is_empty(), "刷新未发送房间列表请求编号")
	directory.directory_request_id = first_request
	directory.public_rooms = [{"room_id":"7158", "players":1, "capacity":4, "joinable":true}]
	app._on_lobby_packet(JSON.stringify(directory))
	_expect(app._room_directory_loaded and app._public_rooms.size() == 1, "房间目录未展示收到的快照")
	app._on_lobby_action("refresh_rooms", {})
	_expect(app._public_rooms.is_empty() and not app._room_directory_loaded, "刷新期间旧房间仍可加入")
	app._on_lobby_packet(JSON.stringify(directory))
	_expect(app._public_rooms.is_empty() and not app._room_directory_loaded, "上次刷新响应覆盖了当前目录请求")
	directory.directory_request_id = str(app.sent[-1].get("request_id", ""))
	directory.public_rooms = []
	app._on_lobby_packet(JSON.stringify(directory))
	_expect(app._room_directory_loaded and app._public_rooms.is_empty(), "空列表未删除已关闭房间")
	app.queue_free()


func _check_rematch(presets: Array) -> void:
	var app := AppFixture.new()
	root.add_child(app)
	app._account = {"account_id":"host", "display_name":"测试牌友"}
	app._lobby_synced = true
	var old_hand := {"room_id":"0421", "kind":"friend", "status":"playing", "start":true, "completed_rounds":0}
	var next_hand := {"room_id":"0421", "kind":"friend", "status":"matched", "start":false, "completed_rounds":1,
		"previous_match_id":"finished-hand", "capacity":4, "player_account_ids":["host","a","b","c"], "ready_account_ids":[]}
	_click_rematch(app, old_hand)
	_expect(app.sent.is_empty(), "结算先到时应等待下一局房间快照")
	app._on_lobby_state(next_hand, presets)
	_expect(_sent_ready(app, 1), "点再来一局后应自动为本座位提交准备")
	app._on_lobby_state(next_hand, presets)
	_expect(app.sent.size() == 1, "重复快照不可重复提交准备")
	app._on_lobby_lost("测试连接断开")
	app._on_lobby_state(next_hand, presets)
	_expect(_sent_ready(app, 2), "重连后若服务端尚未确认准备，应恢复续局意图")
	if not app.sent.is_empty():
		app._on_lobby_result(str(app.sent[-1].command_id), true, "")
	var started := next_hand.duplicate(true)
	started.status = "playing"
	started.start = true
	started.ready_account_ids = ["host","a","b","c"]
	app._on_lobby_state(started, presets)
	_expect(app._state == "game" and int(app.entered.get("completed_rounds", 0)) == 1, "四席准备后无需再点击就应进入下一局")

	app.sent.clear()
	_click_rematch(app, next_hand)
	_expect(_sent_ready(app, 1) and app._state == "room", "房间快照先到时，点击应立即提交准备")
	if not app.sent.is_empty():
		app._on_lobby_result(str(app.sent[-1].command_id), false, "准备失败")
	app._on_lobby_state(next_hand, presets)
	_expect(app.sent.size() == 1 and app._lobby_message == "准备失败", "拒绝准备应显示错误并释放操作，不重复发出命令")

	app.sent.clear()
	var other_hand := next_hand.duplicate(true)
	other_hand.previous_match_id = "unrelated-hand"
	_click_rematch(app, other_hand)
	_expect(app.sent.is_empty(), "旧结算不可提交到另一局")
	app.queue_free()


func _check_settlement_room_return(presets: Array, room_arrives_first: bool) -> void:
	var app := AppFixture.new()
	root.add_child(app)
	app._account = {"account_id":"host", "display_name":"测试牌友"}
	app._lobby_synced = true
	var previous := {"room_id":"0421", "kind":"friend", "status":"playing", "start":true, "completed_rounds":0, "seat_index":0}
	var retained := {"room_id":"0421", "kind":"friend", "status":"matched", "start":false, "completed_rounds":1,
		"previous_match_id":"finished-hand", "capacity":4, "player_account_ids":["host","a","b","c"], "ready_account_ids":[]}
	app._match = (retained if room_arrives_first else previous).duplicate(true)
	var board: Control = app._make_game(false, previous.duplicate(true))
	app._auto_flow = true
	board._handle_packet(JSON.stringify({"type":"mahjong_joined", "room_id":"0421", "match_id":"finished-hand", "your_seat":0}))
	board._handle_packet(JSON.stringify({"type":"mahjong_state", "room_id":"0421", "match_id":"finished-hand", "kind":"friend",
		"phase":"finished", "status":"finished", "your_seat":0, "winners":[], "scores":[0,0,0,0], "can_rematch":true}))
	var wait_button := board.find_child("MahjongSettlementRoomButton", true, false) as Button
	_expect(is_instance_valid(wait_button) and not wait_button.disabled, "好友房结算应提供返回房间按钮")
	if not is_instance_valid(wait_button):
		app.queue_free()
		return
	var other_actions: Array[String] = []
	board.request_next_round.connect(func(): other_actions.append("ready"))
	board.request_return_to_lobby.connect(func(): other_actions.append("leave"))
	wait_button.pressed.emit()
	board._return_now(true)
	board._return_now()
	_expect(other_actions.is_empty(), "返回房间后旧结算不能再提交续局或离开")
	if not room_arrives_first:
		_expect(app.sent.is_empty() and app._state == "lobby" and not app._finished_friend_return.is_empty(),
			"旧对局仍在同步时应等待新房间，不发准备或离开命令")
	app._on_lobby_state(retained, presets)
	app._on_lobby_state(retained, presets)
	await process_frame
	_expect(app._state == "room" and app._match.room_id == "0421" and app.sent.is_empty(),
		"返回房间应保留原房间和未准备状态，重复房间通知不提交命令")
	var ready := app._lobby_view.find_child("MahjongReadyButton", true, false) as Button
	_expect(is_instance_valid(ready) and not ready.disabled, "返回房间后本人仍可手动准备")
	if is_instance_valid(ready):
		ready.pressed.emit()
		_expect(_sent_ready(app, 1), "仅在点击房内准备后提交本人的准备命令")
	app.queue_free()


func _check_rematch_window_size(presets: Array, resized: Vector2i, wait_for_other_players: bool) -> void:
	var app := AppFixture.new()
	app.enter_real_board = true
	root.add_child(app)
	app._account = {"account_id":"host", "display_name":"测试牌友"}
	app._lobby_synced = true
	root.size = Vector2i(720, 850)
	await process_frame
	var next_hand := {"room_id":"0421", "kind":"friend", "status":"matched", "start":false, "completed_rounds":1,
		"previous_match_id":"finished-hand", "capacity":4, "player_account_ids":["host","a","b","c"], "ready_account_ids":[]}
	app._match = next_hand.duplicate(true)
	var first: Control = app._make_game(false, {"room_id":"0421", "kind":"friend", "seat_index":0, "completed_rounds":0})
	first._handle_packet(JSON.stringify({"type":"mahjong_joined", "room_id":"0421", "match_id":"finished-hand", "your_seat":0}))
	first._handle_packet(JSON.stringify({"type":"mahjong_state", "room_id":"0421", "match_id":"finished-hand", "kind":"friend",
		"phase":"finished", "status":"finished", "your_seat":0, "winners":[], "scores":[0,0,0,0], "can_rematch":true}))
	root.size = resized
	await process_frame
	_expect(root.size == resized, "用户调整后的桌面窗口未达到 %s" % resized)
	var again := first.find_child("MahjongNextRoundButton", true, false) as Button
	_expect(again != null and not again.disabled, "结算缺少可点击的再来一局按钮")
	if again != null:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = again.get_global_transform_with_canvas() * (again.size * 0.5)
		click.pressed = true
		root.push_input(click, true)
		click.pressed = false
		root.push_input(click, true)
	_expect(app._state == "room" and _sent_ready(app, 1), "从结算点击再来一局后应进入等候房并提交准备")
	if wait_for_other_players:
		await process_frame
		_expect(root.size == resized, "等待下一局时窗口从 %s 变为 %s" % [resized, root.size])
		_expect(root.content_scale_size == Vector2i.ZERO, "等候房应恢复菜单的响应式投影")
		root.size = resized + Vector2i(22, 8)
		resized = root.size
	var started := next_hand.duplicate(true)
	started.status = "playing"
	started.start = true
	started.ready_account_ids = ["host","a","b","c"]
	app._on_lobby_state(started, presets)
	_expect(app._state == "game" and is_instance_valid(app._game) and app._game != first, "已准备的座位应进入新牌桌")
	await process_frame
	_expect(not is_instance_valid(first), "切换后应清理旧牌桌")
	_expect(root.size == resized, "下一局开桌并清理旧牌桌后窗口从 %s 变为 %s" % [resized, root.size])
	_expect(root.content_scale_size == Vector2i(1440, 810), "续局牌桌应恢复对局的投影")
	print("MAHJONG_REMATCH_WINDOW wait=%s expected=%s actual=%s" % [wait_for_other_players, resized, root.size])
	app.queue_free()
	await process_frame


func _click_rematch(app: AppFixture, snapshot: Dictionary) -> void:
	app._match = snapshot.duplicate(true)
	var board := SettledBoard.new()
	app._screen.add_child(board)
	app._game = board
	app._state = "game"
	app._return_from_game(board, true)


func _sent_ready(app: AppFixture, count: int) -> bool:
	return app.sent.size() == count and app.sent[-1].action == "ready" and app.sent[-1].room_id == "0421"
