extends SceneTree
## 离线房间夹具只替换网络发送边界；操作、视口、弹窗和设置都运行实际界面。

class OfflineTable:
	extends "res://modules/games/mahjong/guiyang/guiyang_3d_screen.gd"
	var transport_open := true
	var send_error: Error = OK
	var delivered: Array[Dictionary] = []
	func _connect_socket() -> void:
		pass
	func _transport_open() -> bool:
		return transport_open
	func _wire_send(payload: Dictionary) -> Error:
		if send_error == OK:
			delivered.append(payload.duplicate(true))
		return send_error

class VoiceProbe:
	extends Node
	var starts := 0
	var stops := 0
	var last_error := "测试录音已停止"
	func start_recording() -> Error:
		starts += 1
		return OK
	func stop_recording() -> Dictionary:
		stops += 1
		return {}
	func set_playback_enabled(_enabled: bool) -> void:
		pass

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)

func _fixture() -> Dictionary:
	return {"type":"mahjong_state", "room_id":"3131", "status":"playing", "phase":"turn", "turn":0, "your_seat":0, "dealer":0,
		"players":["花开富贵", "老陈", "清风徐来", "小雨"], "hand":[{"id":11,"suit":"wan","rank":2},{"id":12,"suit":"tong","rank":3},{"id":13,"suit":"tiao","rank":4},{"id":14,"suit":"wan","rank":1},{"id":15,"suit":"wan","rank":3},{"id":16,"suit":"wan","rank":5},{"id":17,"suit":"wan","rank":6},{"id":18,"suit":"wan","rank":8},{"id":19,"suit":"wan","rank":9},{"id":20,"suit":"tong","rank":1},{"id":21,"suit":"tong","rank":4},{"id":22,"suit":"tiao","rank":2},{"id":23,"suit":"tiao","rank":5},{"id":24,"suit":"tiao","rank":8}],
		"hand_counts":[14,13,13,13], "scores":[0,0,0,0], "melds":[[],[],[],[]], "discards":[], "remaining":55,
		"options":[{"type":"play"}], "winners":[]}

func _run() -> void:
	var preferences := "user://mahjong_reference_buttons_fixture_%d.cfg" % OS.get_process_id()
	var screen := OfflineTable.new()
	screen.preference_file = preferences
	screen.match_context = {"room_id":"3131", "account_id":"fixture"}
	root.add_child(screen)
	await process_frame
	screen.set_process(false)
	if screen._actions_root.find_child("MahjongAction_chi", true, false) == null:
		push_error("参考图要求的五个常驻响应按钮尚未实现")
		screen.queue_free()
		await process_frame
		quit(1)
		return
	var first := _fixture()
	screen._handle_packet(JSON.stringify(first))
	screen._select_tile(11)
	_check(screen._play_button.disabled, "新连接在入座 ACK 前错误启用打出")
	screen._handle_packet(JSON.stringify({"type":"mahjong_joined", "room_id":"3131", "your_seat":0}))
	_check(screen._play_button.disabled, "入座 ACK 后仍需等待新快照")
	screen._handle_packet(JSON.stringify(first))
	screen._select_tile(11)
	_check(not screen._play_button.disabled, "合法回合选牌后打出仍被禁用")
	var response_visible: bool = screen._response_buttons.values().any(func(button: Button): return button.is_visible_in_tree())
	_check(screen._play_button.is_visible_in_tree() and not response_visible, "只有出牌选项时不得显示任一响应按钮")
	await process_frame
	_check(screen._hand_models.size() == 14, "参考布局未保留十四张实际三维手牌")
	for model in screen._hand_models:
		var face: Rect2 = screen._projected_tile_rect(model)
		face.position += screen._board_view.position
		_check(not face.grow(-2).intersects(screen._actions_root.get_rect()), "响应按钮遮挡了自己的三维牌面")
	if DisplayServer.get_name() != "headless":
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--screen-out="):
				await RenderingServer.frame_post_draw
				var image := root.get_viewport().get_texture().get_image()
				_check(image.save_png(argument.trim_prefix("--screen-out=")) == OK, "无法保存指定的桌面预览")
	for kind in ["chi","peng","gang","hu","pass"]:
		_check(screen.find_child("MahjongAction_" + kind, true, false) != null, "缺少响应动作控件：" + kind)
	var chi := screen._actions_root.find_child("MahjongAction_chi", true, false) as Button
	if chi != null:
		_check(chi.disabled and not chi.is_visible_in_tree(), "贵阳规则不应显示吃牌")
	screen.send_error = ERR_CONNECTION_ERROR
	screen._play_button.pressed.emit()
	_check(screen._selected_id == 11 and not screen._status.text.is_empty(), "发送失败清除了已选牌或未反馈")
	_check(screen.delivered.is_empty(), "失败发送产生了动作")
	screen.send_error = OK
	screen._play_button.pressed.emit()
	_check(screen.delivered.size() == 1 and screen.delivered[0].get("action") == "play" and screen.delivered[0].get("tile_id") == 11, "打出未发送真实所选牌 ID")
	_check(screen._play_button.disabled, "已提交操作在确认前仍可再次出牌")
	screen._select_tile(11)
	screen._on_play()
	_check(screen.delivered.size() == 1 and screen._play_button.disabled, "确认前重新选牌绕过了重复提交限制")
	screen._handle_packet(JSON.stringify({"type":"mahjong_error", "message":"测试拒绝"}))
	_check(not screen._play_button.disabled, "服务器拒绝后未恢复可重试操作")
	screen._on_play()
	_check(screen.delivered.size() == 2, "服务器拒绝后不能重新提交真实动作")
	var reactions := _fixture()
	reactions["phase"] = "reaction"
	reactions["turn"] = 1
	reactions.hand = []
	for kind in [["wan",1],["wan",1],["wan",1],["wan",2],["wan",3],["tong",1],["tong",2],["tong",3],["tiao",1],["tiao",2],["tiao",3],["tong",5],["tong",5]]:
		reactions.hand.append({"id":11+reactions.hand.size(),"suit":kind[0],"rank":kind[1]})
	reactions.hand_counts[0]=13
	reactions.last_discard={"id":90,"suit":"wan","rank":1}
	reactions.discards=[{"seat":1,"tile":reactions.last_discard,"claimed":false}]
	reactions["options"] = [{"type":"ming_gang"},{"type":"peng"},{"type":"hu"},{"type":"pass"}]
	screen._handle_packet(JSON.stringify(reactions))
	await process_frame
	_check(not screen._play_button.is_visible_in_tree() and screen._play_button.disabled, "响应阶段不得显示不合法的打出")
	_check(screen._actions_root.is_visible_in_tree() and not screen._response_buttons["chi"].is_visible_in_tree(), "响应区只显示本次可用动作")
	for kind in ["peng", "gang", "hu", "pass"]:
		_check(screen._response_buttons[kind].is_visible_in_tree(), "缺少服务端给出的响应：" + kind)
	var skip := screen._response_buttons["pass"] as Button
	_check(skip.text == "过" and skip != screen._play_button and skip.is_visible_in_tree(), "跳过响应独立保留，不能冒充打出")
	var before_skip := screen.delivered.size()
	screen._play_button.pressed.emit()
	_check(screen.delivered.size() == before_skip, "响应阶段打出不发送动作")
	skip.pressed.emit()
	_check(screen.delivered.size() == before_skip + 1 and screen.delivered.back().get("action") == "pass", "跳过只提交合法的放弃响应")
	screen._clear_pending_command()
	screen._refresh_connection_actions(false)
	var own_kongs:=_fixture()
	for index in 4: own_kongs.hand[index]={"id":11+index,"suit":"wan","rank":1}
	own_kongs.hand[4]={"id":15,"suit":"tong","rank":3}
	own_kongs.hand.resize(11)
	own_kongs.hand_counts[0]=11
	own_kongs.melds[0]=[{"kind":"peng","tiles":[{"id":51,"suit":"tong","rank":3},{"id":52,"suit":"tong","rank":3},{"id":53,"suit":"tong","rank":3}],"from_seat":1}]
	own_kongs.options=[{"type":"play"},{"type":"an_gang","tile_id":11},{"type":"bu_gang","tile_id":15}]
	screen._handle_packet(JSON.stringify(own_kongs))
	var gang := screen._actions_root.find_child("MahjongAction_gang", true, false) as Button
	if gang != null:
		gang.pressed.emit()
		await process_frame
		var choices := _buttons(screen._overlay_root).filter(func(button): return button.name.begins_with("MahjongGangChoice"))
		_check(choices.size() == 2, "多个合法杠没有供玩家选择")
		if choices.size() == 2:
			screen.send_error = ERR_CONNECTION_ERROR
			choices[1].pressed.emit()
			_check(screen._tool_open == "gang", "杠发送失败关闭了选择弹窗")
			screen.send_error = OK
			choices[1].pressed.emit()
			_check(screen.delivered.back().get("action") == "bu_gang" and screen.delivered.back().get("tile_id") == 15, "杠按钮替换了服务器给出的种类或牌 ID")
			var pending_count := screen.delivered.size()
			screen._send_action("hu")
			_check(screen.delivered.size() == pending_count and screen._response_buttons["hu"].disabled, "等待杠确认期间仍能重复提交响应")
	screen.transport_open = false
	screen._refresh_connection_actions()
	_check(screen._play_button.disabled and _buttons(screen._actions_root).all(func(button): return button.disabled), "断线未立即禁用动作")
	_check(not screen._actions_root.is_visible_in_tree(), "断线后旧动作仍可见")
	var before := screen.delivered.size()
	screen._send_action("hu")
	_check(screen.delivered.size() == before, "断线仍发送了胡牌")
	screen.transport_open = true
	screen._joined = false
	screen._snapshot_ready = false
	screen._handle_packet(JSON.stringify(reactions))
	_check(not screen._actions_ready(), "重连前的状态快照绕过了入座确认")
	screen._handle_packet(JSON.stringify({"type":"mahjong_joined", "room_id":"3131", "your_seat":0}))
	screen._handle_packet(JSON.stringify(reactions))
	screen._open_tool("chat")
	screen._last_social_send = -1000
	screen._send_social_choice("chat", "quick_chat", "hello")
	_check(screen.delivered.back().get("type") == "mahjong_social" and screen.delivered.back().get("quick_chat") == "hello" and not screen.delivered.back().has("seat"), "聊天没有使用规范 ID 或冒用了发送座位")
	screen._handle_packet(JSON.stringify({"type":"mahjong_social", "room_id":"3131", "seat":1, "action":"chat", "text":"大家好，很高兴一起玩！"}))
	_check(screen._social_events.has(1), "服务器聊天未显示牌桌气泡")
	var mute := screen._seat_voice_buttons[1] as Button
	mute.pressed.emit()
	_check(screen._seat_muted(1) and "取消静音" in mute.tooltip_text, "对手麦克风没有切换本地静音")
	_check(not screen._social_events.has(1), "静音时未清除座位现有气泡")
	screen._handle_packet(JSON.stringify({"type":"mahjong_social", "room_id":"3131", "seat":1, "action":"chat", "text":"静音后隐藏"}))
	screen._handle_packet(JSON.stringify({"type":"mahjong_social", "room_id":"3131", "seat":1, "action":"emote", "emote":"smile"}))
	screen._handle_packet(JSON.stringify({"type":"mahjong_social", "room_id":"3131", "seat":1, "action":"voice", "duration_ms":1000}))
	_check(not screen._social_events.has(1), "静音后仍显示该账号的聊天、表情或语音")
	mute.pressed.emit()
	reactions["match_id"] = "moderation-fixture"
	screen._handle_packet(JSON.stringify(reactions))
	await process_frame
	var moderate := screen.find_child("MahjongSeatModeration1", true, false) as Button
	_check(moderate != null, "对手头像没有牌友管理入口")
	if moderate != null:
		moderate.pressed.emit()
		var capture := OS.get_environment("MAHJONG_MODERATION_PREVIEW_DIR")
		if not capture.is_empty() and DisplayServer.get_name() != "headless":
			await process_frame
			await RenderingServer.frame_post_draw
			var output := "moderation_%dx%d.png" % [root.size.x, root.size.y]
			root.get_texture().get_image().save_png(capture.path_join(output))
		var reason := screen.find_child("MahjongReportReason", true, false) as OptionButton
		var report := screen.find_child("MahjongReportSubmit", true, false) as Button
		_check(reason != null and report != null and report.disabled, "必须选择举报原因后提交")
		if reason != null and report != null:
			reason.select(1)
			reason.item_selected.emit(1)
			report.pressed.emit()
			var sent: Dictionary = screen.delivered.back()
			_check(sent.get("type") == "mahjong_report" and sent.get("reason") == "spam" and
				sent.get("target_seat") == 1 and sent.get("match_id") == "moderation-fixture" and
				not str(sent.get("command_id", "")).is_empty(), "举报未按牌桌合同提交")
			screen._handle_packet(JSON.stringify({"type":"mahjong_report_result", "command_id":"stale-id", "ok":true}))
			_check((screen.find_child("MahjongReportSubmit", true, false) as Button).disabled, "过期举报回复错误解锁当前举报")
			screen._handle_packet(JSON.stringify({"type":"mahjong_report_result", "command_id":sent.get("command_id"), "ok":true, "message":"举报已提交"}))
			var feedback := screen.find_child("MahjongReportFeedback", true, false) as Label
			_check(feedback != null and feedback.text == "举报已提交", "没有显示服务器确认的举报结果")
		screen._close_tool()
	screen._social_events.clear()
	screen._handle_packet(JSON.stringify({"type":"mahjong_social", "room_id":"3131", "seat":1, "message_id":"same-seat-budget-id", "action":"chat", "text":"大家好，很高兴一起玩！"}))
	screen._handle_packet(JSON.stringify({"type":"mahjong_social", "room_id":"3131", "seat":2, "message_id":"same-seat-budget-id", "action":"chat", "text":"这手牌打得漂亮！"}))
	_check(screen._social_events.has(1) and screen._social_events.has(2), "不同座位合法使用相同消息 ID 时消息被错误吞掉")
	screen._handle_packet(JSON.stringify({"type":"mahjong_social", "room_id":"3131", "seat":1, "message_id":"same-seat-budget-id", "action":"chat", "text":"谢谢！"}))
	_check(screen._social_events.get(1, {}).get("text") == "大家好，很高兴一起玩！", "相同座位的重复消息 ID 没有被抑制")
	# Keep the desktop fixture reproducible while exercising asymmetric mobile insets.
	screen._safe = Vector4i(24, 14, 6, 4)
	var usable := Rect2(Vector2(24, 14), screen.size - Vector2(30, 18))
	for tool in ["chat", "emote", "gang", "rules", "settings", "leave"]:
		screen._open_tool(tool)
		screen._handle_packet(JSON.stringify(reactions))
		# Containers fit the overlapping title after the modal's minimum size
		# notification; inspect the settled composition, not an intermediate frame.
		for frame in 3: await process_frame
		var panels := screen._overlay_root.get_children().filter(func(node): return node is Panel or node is PanelContainer)
		var dims := screen._overlay_root.get_children().filter(func(node): return node is ColorRect)
		_check(screen._tool_open == tool and panels.size() == 1 and dims.size() == 1, "新状态重复创建或丢失了弹窗：" + tool)
		if panels.size() == 1:
			var panel: Control = panels[0]
			var visual_bounds := panel.get_global_rect()
			var title_name := "MahjongLeaveTitlePlate" if tool == "leave" else "MahjongToolTitlePlate"
			var title := panel.find_child(title_name, true, false) as Control
			if title != null:
				visual_bounds = visual_bounds.merge(title.get_global_rect())
			_check(visual_bounds.get_center().distance_to(usable.get_center()) <= 1.0, "弹窗与标题整体没有在安全区双轴居中：%s visual=%s safe=%s panel=%s title=%s minimum=%s" % [tool, visual_bounds, usable, panel.get_global_rect(), title.get_global_rect() if title != null else Rect2(), title.get_combined_minimum_size() if title != null else Vector2.ZERO])
		screen._close_tool()
	screen._safe = Vector4i.ZERO
	var probe := VoiceProbe.new()
	screen._voice.queue_free()
	screen.add_child(probe)
	screen._voice = probe
	await process_frame
	var stable_mic := screen._own_mic as Button
	var stable_id := stable_mic.get_instance_id()
	var previous_emulation := Input.emulate_mouse_from_touch
	Input.emulate_mouse_from_touch = true
	var hold := InputEventScreenTouch.new()
	hold.index = 0
	hold.pressed = true
	hold.position = stable_mic.get_viewport_transform() * stable_mic.get_global_transform() * (stable_mic.size * 0.5)
	Input.parse_input_event(hold)
	await process_frame
	_check(screen._recording and probe.starts == 1, "真实 GUI 触屏按住自己麦克风未开始录音")
	screen._handle_packet(JSON.stringify(reactions))
	await process_frame
	_check(screen._own_mic.get_instance_id() == stable_id and screen._recording and probe.stops == 0, "快照重建了按住中的自己麦克风或提前停止录音")
	hold.pressed = false
	Input.parse_input_event(hold)
	await process_frame
	_check(not screen._recording and probe.stops == 1, "快照后的实际 GUI 松手没有且仅有一次停止录音")
	hold.pressed = true
	Input.parse_input_event(hold)
	await process_frame
	_check(screen._recording and probe.starts == 2, "完成松手后无法再次按住录音")
	screen.transport_open = false
	screen._refresh_connection_actions()
	_check(not screen._recording and probe.stops == 2, "断线未立即停止正在录音")
	hold.pressed = false
	Input.parse_input_event(hold)
	await process_frame
	_check(probe.stops == 2, "断线后的松手重复停止同一录音")
	Input.emulate_mouse_from_touch = previous_emulation
	screen.transport_open = true
	screen._refresh_connection_actions()
	screen._open_tool("settings")
	screen._set_quality(2)
	screen._toggle_music(true)
	screen._toggle_music(false)
	screen._toggle_sound(false)
	var saved := ConfigFile.new()
	_check(saved.load(screen.preference_file) == OK and saved.get_value("rendering","quality") == 2 and saved.get_value("sound","music") == false and saved.get_value("sound","effects") == false, "画质或声音设置未持久保存")
	var aspect: float = screen._board_view.size.x / screen._board_view.size.y
	_check(absf(aspect - float(screen._board_viewport.size.x)/screen._board_viewport.size.y) < 0.004 and screen._board_viewport.own_world_3d, "画质改变了三维桌面比例或世界隔离")
	screen._close_tool()
	Input.emulate_mouse_from_touch = true
	hold.pressed = true
	Input.parse_input_event(hold)
	await process_frame
	_check(screen._recording and probe.starts == 3, "退出检查前的实际触屏按住没有录音")
	var returned := [false]
	screen.request_return_to_lobby.connect(func(): returned[0] = true)
	screen._request_leave()
	_check(not returned[0] and screen._tool_open == "leave", "退出未等待确认")
	var confirm := screen._overlay_root.find_child("MahjongLeaveConfirm", true, false) as Button
	if confirm != null: confirm.pressed.emit()
	_check(returned[0] and screen._exiting and not screen._actions_ready(), "退出确认没有断开操作并返回大厅")
	_check(not screen._recording and probe.stops == 3, "退出未立即且仅有一次停止正在录音")
	hold.pressed = false
	Input.parse_input_event(hold)
	await process_frame
	_check(probe.stops == 3, "退出后的松手重复停止录音")
	Input.emulate_mouse_from_touch = previous_emulation
	screen.queue_free()
	await process_frame
	# 等待音频线程释放刚停止的音乐播放引用。
	await create_timer(0.12).timeout
	DirAccess.remove_absolute(ProjectSettings.globalize_path(preferences))
	if _failures.is_empty(): print("MAHJONG_REFERENCE_BUTTONS_SMOKE_OK readiness action_payloads gang_selector errors social seat_dedup stable_touch_voice single_modal mute preferences exit")
	quit(0 if _failures.is_empty() else 1)

func _buttons(parent: Node) -> Array[Button]:
	var found: Array[Button] = []
	for child in parent.get_children():
		if child.is_queued_for_deletion(): continue
		if child is Button: found.append(child)
		found.append_array(_buttons(child))
	return found
