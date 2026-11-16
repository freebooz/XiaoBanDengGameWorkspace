extends SceneTree
## One real product instance per OS process. Only the test coordinates peers.

var _app: Node
var _peer := -1
var _fixture := ""
var _preview := ""
var _rematch := false
var _resume_session_only := false
var _transport_fault := false
var _custom_rules := false
const CUSTOM_OPTIONS := {
	"version": "1.0.0", "chicken": true, "charge_chicken": false,
	"black_eight": false, "requires_kong_to_claim": true, "rob_kong": false,
}
var _deadline := 0
var _room := ""
var _match_id := ""
var _seat := -1
var _commands := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--server-url="):
			ProjectSettings.set_setting("xiaobandeng/network/default_server_url", argument.trim_prefix("--server-url="))
		if argument.begins_with("--peer="): _peer = int(argument.trim_prefix("--peer="))
		if argument.begins_with("--fixture-dir="): _fixture = argument.trim_prefix("--fixture-dir=")
		if argument.begins_with("--preview-dir="): _preview = argument.trim_prefix("--preview-dir=")
		if argument == "--rematch": _rematch = true
		if argument == "--resume-session-only": _resume_session_only = true
		if argument == "--transport-fault": _transport_fault = true
		if argument == "--custom-rules": _custom_rules = true
	if _peer not in [0, 1, 2, 3] or _fixture.is_empty() or not _uncapped("startup"):
		push_error("四端验证参数错误，或原生客户端仍限制帧率")
		quit(1)
		return
	_deadline = Time.get_ticks_msec() + 100000
	var passed := await _exercise()
	if is_instance_valid(_app):
		_app.queue_free()
		await process_frame
	if passed and not _resume_session_only:
		print("MAHJONG_GUIYANG_PEER_OK index=%d seat=%d room=%s match=%s commands=%d" % [_peer, _seat, _room, _match_id, _commands])
	quit(0 if passed else 1)


func _uncapped(stage: String) -> bool:
	var vsync := DisplayServer.window_get_vsync_mode()
	print("MAHJONG_PEER_LIMITS index=%d pid=%d stage=%s max_fps=%d vsync=%d" % [_peer, OS.get_process_id(), stage, Engine.max_fps, vsync])
	return Engine.max_fps == 0 and (DisplayServer.get_name() == "headless" or vsync == DisplayServer.VSYNC_DISABLED)


func _until(condition: Callable, step: String) -> bool:
	while not condition.call():
		if Time.get_ticks_msec() >= _deadline:
			print("MAHJONG_PEER_STEP index=%d timed_out=%s" % [_peer, step])
			var game = _table()
			var board_state: Dictionary = game._state if is_instance_valid(game) else {}
			push_error("peer %d timed out during %s (lobby=%s/%s board=%s/%s epoch=%s commands=%d)" % [
				_peer, step, _app._state, _app._match.get("status"), board_state.get("phase"),
				board_state.get("turn"), board_state.get("epoch"), _commands])
			return false
		await process_frame
	return true


func _press(button: Button, description: String) -> bool:
	if not _button_ready(button):
		push_error("peer %d cannot press %s" % [_peer, description])
		return false
	button.pressed.emit()
	return true


func _button_ready(button: Button) -> bool:
	return is_instance_valid(button) and not button.disabled and button.is_visible_in_tree()


func _named_button(name: String) -> Button:
	for node in _app.find_children(name, "Button", true, false):
		if node.is_visible_in_tree() and not node.is_queued_for_deletion(): return node
	return null


func _login_button() -> Button:
	for node in _app.find_children("*", "Button", true, false):
		if node.is_visible_in_tree() and (node.name == "MahjongGuestLoginButton" or node.text == "游客登录"):
			return node
	return null


func _is_guiyang(state: Dictionary) -> bool:
	return state.get("rule_set_id") == "guiyang" and state.get("rule_version") == "2.0.0"


func _table() -> Variant:
	if not is_instance_valid(_app): return null
	for child in _app._screen.get_children():
		if not child.is_queued_for_deletion() and child.has_signal("match_finished"): return child
	return null


func _table_playing() -> bool:
	var game = _table()
	return is_instance_valid(game) and game._actions_ready() and game._state.get("status") == "playing"


func _capture(file_name: String) -> bool:
	if _preview.is_empty(): return true
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(_preview.path_join(file_name)) != OK:
		push_error("could not capture native frame %s" % file_name)
		return false
	return true


func _file(name: String) -> String:
	return _fixture.path_join(name + ".json")


func _receipt(name: String, value: Variant) -> bool:
	var path := _file(name)
	var output := FileAccess.open(path + ".writing", FileAccess.WRITE)
	if output == null:
		push_error("could not open peer receipt %s" % path)
		return false
	output.store_string(JSON.stringify(value))
	output.close()
	if DirAccess.rename_absolute(path + ".writing", path) != OK:
		push_error("could not publish peer receipt %s" % path)
		return false
	return true


func _exercise() -> bool:
	if change_scene_to_file("res://scenes/main.tscn") != OK: return false
	await scene_changed
	_app = current_scene
	if _resume_session_only: return await _verify_session_restart()
	if not await _until(func(): return _button_ready(_login_button()), "guest login"): return false
	if _peer == 0 and not await _capture("login.png"): return false
	if not _press(_login_button(), "guest login"): return false
	if not await _until(func(): return _button_ready(_named_button("MahjongGuestEnterLobbyButton")), "guest identity"): return false
	if not _press(_named_button("MahjongGuestEnterLobbyButton"), "confirm guest identity"): return false
	if not await _until(func(): return _app._state == "lobby" and _app._lobby_synced, "lobby subscription"): return false
	if _peer == 0 and not await _verify_quick_cancel(): return false
	if _peer == 0 and not _preview.is_empty() and not await _capture_training_hall(): return false
	if not await _join_room(): return false
	if not await _until(_table_playing, "four-player table"): return false
	if not _verify_deal(1): return false
	if _peer == 0:
		if not await _until(_all_receipts.bind("deal-1"), "four private deals"): return false
		var game = _table()
		if "--verify-report" in OS.get_cmdline_user_args() and not await _verify_live_report(game): return false
		if not _preview.is_empty() and not game._legal_options("play").is_empty():
			game._select_tile(int(game._state.hand[0].id))
		if not await _capture("friend_table.png"): return false
		if _transport_fault and not await _verify_transport_reconnect(): return false
		if not await _resume(): return false
		if not _receipt("resumed", true): return false
	if not await _until(func(): return FileAccess.file_exists(_file("resumed")), "host resume"): return false
	if not await _until(_drive_round, "settlement"): return false
	if not await _verify_settlement(1): return false
	if _rematch: return await _play_rematch()
	return true


func _verify_live_report(game: Node) -> bool:
	var target := (_seat + 1) % 4
	var player_button := _named_button("MahjongSeatModeration%d" % target)
	if not _press(player_button, "open player management"): return false
	var reason := game.find_child("MahjongReportReason", true, false) as OptionButton
	if reason == null: return false
	reason.select(1)
	reason.item_selected.emit(1)
	if not _press(_named_button("MahjongReportSubmit"), "submit test report"): return false
	if not await _until(func(): return game._report_notice == "举报已提交", "durable seat report acknowledgement"): return false
	if not await _capture("moderation_live.png"): return false
	game._close_tool()
	print("MAHJONG_GUIYANG_NATIVE_REPORT_OK room=%s match=%s reporter_seat=%d target_seat=%d" % [_room, _match_id, _seat, target])
	return true


func _verify_quick_cancel() -> bool:
	if not _press(_named_button("MahjongQuickButton"), "start quick matchmaking"): return false
	var cancel_button := "MahjongLeaveButton"
	if not await _until(func():
		return _app._match.get("kind") == "quick" and _app._match.get("status") == "waiting" and _button_ready(_named_button(cancel_button))
	, "waiting for quick matchmaking"): return false
	if not _press(_named_button(cancel_button), "cancel matchmaking"): return false
	return await _until(func(): return _app._match.get("status") == "idle" and _button_ready(_named_button("MahjongQuickButton")), "matchmaking cancelled")


func _verify_session_restart() -> bool:
	if not await _until(func(): return _button_ready(_login_button()), "persisted session sign-in"): return false
	var resume := _login_button()
	if not _button_ready(resume) or resume.text != "继续游戏":
		push_error("peer %d did not offer saved-session continuation" % _peer)
		return false
	if not _press(resume, "continue with the saved session"): return false
	if not await _until(func(): return _button_ready(_named_button("MahjongGuestEnterLobbyButton")), "restored guest identity"): return false
	if not _press(_named_button("MahjongGuestEnterLobbyButton"), "confirm restored guest identity"): return false
	if not await _until(func(): return _app._state == "lobby" and _app._lobby_synced, "persisted session resume"): return false
	var account := str(_app._account.get("account_id", ""))
	if account.is_empty() or _app._match.get("status") != "idle": return false
	if "--verify-history" in OS.get_cmdline_user_args():
		if not await _until(func():
			for round_number in [1, 2]:
				var deal := FileAccess.get_file_as_string(_file("deal-%d-%d" % [round_number, _peer]))
				var parsed: Variant = JSON.parse_string(deal)
				if not parsed is Dictionary: return false
				if not _app._recent.any(func(item): return item.match_id == parsed.get("match_id")): return false
			return true
		, "two previously completed rounds in account history"): return false
		print("MAHJONG_GUIYANG_HISTORY_RESTORED index=%d rounds=2" % _peer)
		if not await _verify_personal_replay(): return false
	if not _receipt("session-%d" % _peer, {"account": account, "pid": OS.get_process_id()}): return false
	print("MAHJONG_GUIYANG_SESSION_OK index=%d pid=%d" % [_peer, OS.get_process_id()])
	return true


func _verify_personal_replay() -> bool:
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(_file("deal-1-%d" % _peer)))
	if not saved is Dictionary: return false
	var id := str(saved.get("match_id", ""))
	if id.is_empty() or not _press(_named_button("MahjongHistoryOpenButton"), "open personal history"): return false
	var row_name := "MahjongHistoryMatch_" + id.validate_node_name()
	if not await _until(func(): return _button_ready(_named_button(row_name)), "open settled match"): return false
	if not _press(_named_button(row_name), "read persisted match detail"): return false
	if not await _until(func(): return _app._history_detail.get("match_id") == id and _app._history_detail.has("breakdown"), "persisted score breakdown"): return false
	if not _press(_named_button("MahjongHistoryReplayButton"), "open persisted replay"): return false
	var next := "MahjongReplayNextButton"
	if not await _until(func(): return _button_ready(_named_button(next)) and not _app._history_replay.get("events", []).is_empty(), "persisted replay"): return false
	if not _press(_named_button(next), "advance the replay"): return false
	if not _button_ready(_named_button("MahjongReplayPreviousButton")): return false
	if not await _capture("personal_history_replay_live.png"): return false
	print("MAHJONG_GUIYANG_NATIVE_REPLAY_OK index=%d match=%s" % [_peer, id])
	return true


func _capture_training_hall() -> bool:
	if not _press(_named_button("MahjongTrainingHallButton"), "open training hall"): return false
	var back := _named_button("MahjongTrainingHallBackButton")
	if not _button_ready(back) or not await _capture("training_hall.png"): return false
	if not _press(back, "return from training hall"): return false
	return _app._state == "lobby" and _app._match.get("status") == "idle"


func _join_room() -> bool:
	if _peer == 0:
		if not await _capture("lobby.png"): return false
		if not _press(_named_button("MahjongOpenJoinButton"), "open room code form"): return false
		if not await _capture("join_room.png"): return false
		if not _press(_named_button("MahjongCloseJoinButton"), "close room code form"): return false
		if not _press(_named_button("MahjongCreateButton"), "open friend room setup"): return false
		if not _press(_named_button("MahjongCreateRuleCard_guiyang_2_0_0"), "select Guiyang 2.0.0"): return false
		if _custom_rules:
			if not await _create_custom_room(): return false
		elif not _press(_named_button("MahjongCustomRulesCreateButton"), "create friend room"):
			return false
		if not await _until(func(): return _app._state == "room" and _app._match.get("kind") == "friend", "create friend room"): return false
		_room = str(_app._match.get("room_id", ""))
		if _room.length() != 4 or not _room.is_valid_int() or not _receipt("room", _room): return false
	else:
		if not await _until(func(): return FileAccess.file_exists(_file("room")), "host invite code"): return false
		_room = str(JSON.parse_string(FileAccess.get_file_as_string(_file("room"))))
		if not _press(_named_button("MahjongOpenJoinButton"), "open room code form"): return false
		var code := _app.find_child("MahjongJoinCode", true, false) as LineEdit
		if not is_instance_valid(code) or not code.is_visible_in_tree(): return false
		code.text = _room
		code.text_changed.emit(_room)
		if not _press(_named_button("MahjongJoinButton"), "join friend room"): return false
	if not await _until(func(): return _app._state == "room" and _app._match.get("status") == "matched" and _app._match.get("player_account_ids", []).size() == 4 and _app._pending_lobby_id.is_empty(), "four distinct humans seated"): return false
	if _app._match.get("room_id") != _room or not _is_guiyang(_app._match): return false
	if not _verify_custom_rules(_app._match, "waiting", 1): return false
	if _peer == 0:
		if not await _until(func(): return int(_app._match.get("ready_players", 0)) == 3, "three guests ready"): return false
		if not await _capture("friend_room.png"): return false
	return _press(_named_button("MahjongReadyButton"), "ready up")


func _create_custom_room() -> bool:
	for name in ["MahjongRuleChargeChicken", "MahjongRuleBlackEight", "MahjongRuleRobKong"]:
		var toggle := _named_button(name) as CheckButton
		if not _button_ready(toggle) or not toggle.button_pressed:
			push_error("expected enabled custom option %s" % name)
			return false
		# BaseButton's regular keyboard input toggles its state and emits toggled.
		toggle.grab_focus()
		var activate := InputEventAction.new()
		activate.action = "ui_accept"
		activate.pressed = true
		Input.parse_input_event(activate)
		activate = activate.duplicate() as InputEventAction
		activate.pressed = false
		Input.parse_input_event(activate)
		await process_frame
		if toggle.button_pressed:
			push_error("custom option %s did not toggle through native input" % name)
			return false
	var chicken := _named_button("MahjongRuleChicken") as CheckButton
	if not is_instance_valid(chicken) or not chicken.button_pressed: return false
	if not await _capture("custom_rules.png"): return false
	return _press(_named_button("MahjongCustomRulesCreateButton"), "create room with customized rules")


func _verify_custom_rules(state: Dictionary, stage: String, round_number: int) -> bool:
	if not _custom_rules: return true
	var rule: Variant = state.get("rule")
	if not rule is Dictionary or not _is_guiyang(rule) or rule.get("options") != CUSTOM_OPTIONS:
		print("MAHJONG_PEER_STEP index=%d custom_rules_mismatch=%s-%d" % [_peer, stage, round_number])
		push_error("server did not return the locked custom options for %s" % stage)
		return false
	return _receipt("custom-%s-%d-%d" % [stage, round_number, _peer], rule.options)


func _verify_deal(round_number: int) -> bool:
	if not _uncapped("table-%d" % round_number):
		push_error("entering the Mahjong table re-enabled a frame limit")
		return false
	var game = _table()
	var state: Dictionary = game._state
	if not _verify_custom_rules(state, "deal", round_number): return false
	_match_id = str(state.get("match_id", ""))
	_seat = int(state.get("your_seat", -1))
	var account := str(_app._account.get("account_id", ""))
	var players := game._array("players") as Array
	if not _same_table(state) or _match_id.is_empty() or _seat not in [0, 1, 2, 3] or players.size() != 4 or players[_seat] != account:
		push_error("invalid initial seat, rules or match metadata for peer %d" % _peer)
		return false
	if state.get("phase") != "turn" or not game._array("discards").is_empty() or int(state.get("remaining", -1)) != 55:
		push_error("peer %d did not receive the untouched 108-tile initial deal" % _peer)
		return false
	var hand := game._array("hand") as Array
	if hand.size() != (14 if _seat == int(state.get("dealer", -1)) else 13): return false
	return _receipt("deal-%d-%d" % [round_number, _peer], {
		"pid": OS.get_process_id(), "room_id": _room, "match_id": _match_id,
		"rule_set_id": state.rule_set_id, "rule_version": state.rule_version,
		"seat": _seat, "dealer": int(state.dealer), "account": account, "players": players,
		"hand_ids": hand.map(func(tile): return int(tile.id)),
	})


func _same_table(state: Dictionary) -> bool:
	return _is_guiyang(state) and state.get("kind") == "friend" and state.get("room_id") == _room and state.get("match_id") == _match_id and not state.has("wall") and not state.has("hands")


func _all_receipts(prefix: String) -> bool:
	for peer in range(4):
		if not FileAccess.file_exists(_file("%s-%d" % [prefix, peer])): return false
	return true


func _resume() -> bool:
	var previous_id: int = _table().get_instance_id()
	if not _press(_named_button("MahjongTool_leave"), "open temporary leave dialog"): return false
	if not _press(_named_button("MahjongLeaveConfirm"), "temporarily leave friend table"): return false
	if not await _until(func(): return _app._state == "lobby" and _app._match.get("status") == "playing", "lobby return after disconnect"): return false
	if not _press(_named_button("MahjongResumeButton"), "resume friend table"): return false
	if not await _until(_table_playing, "resumed table snapshot"): return false
	var game = _table()
	return game.get_instance_id() != previous_id and _same_table(game._state) and int(game._state.get("your_seat", -1)) == _seat


func _verify_transport_reconnect() -> bool:
	var game = _table()
	var hand: Array = game._state.hand.duplicate(true)
	var epoch := int(game._state.get("epoch", -1))
	var tile_id := int(hand[0].id)
	game._select_tile(tile_id)
	if not _button_ready(_named_button("MahjongPlaySelectedTile")):
		push_error("expected the host dealer's discard button to be active before disconnect")
		return false
	var fault_started := Time.get_ticks_msec()
	if not _receipt("disconnect-board", true): return false
	if not await _until(func(): return not game._actions_ready() and not game._snapshot_ready, "loss of live board connection"): return false
	var detected_after := Time.get_ticks_msec() - fault_started
	if _table() != game or _app._state != "game" or not _app._lobby_synced or _button_ready(_named_button("MahjongPlaySelectedTile")):
		push_error("disconnected table must stay open with play disabled and lobby subscribed")
		return false
	if not await _capture("friend_table_disconnected.png"): return false
	if not _receipt("release-board", true): return false
	if not await _until(_table_playing, "automatic board reconnection"): return false
	var restored_after := Time.get_ticks_msec() - fault_started
	if _table() != game or not _same_table(game._state) or int(game._state.your_seat) != _seat or game._state.hand != hand or int(game._state.epoch) != epoch:
		push_error("reconnect did not recover the original table, rule, seat, hand and epoch")
		return false
	game._select_tile(tile_id)
	if not await _capture("friend_table_reconnected.png"): return false
	if not _press(_named_button("MahjongPlaySelectedTile"), "discard after automatic reconnection"): return false
	_commands += 1
	if not await _until(func():
		return game._state.get("discards", []).any(func(item): return int(item.seat) == _seat and int(item.tile.id) == tile_id),
		"authoritative discard after reconnect"): return false
	return _receipt("reconnected-board", {"room_id": _room, "match_id": _match_id, "seat": _seat,
		"epoch": epoch, "hand_size": hand.size(), "detected_ms": detected_after, "restored_ms": restored_after})


func _drive_round() -> bool:
	var game = _table()
	if not is_instance_valid(game): return false
	if game._state.get("phase") == "finished": return true
	if game._pending_action or not game._actions_ready(): return false
	for kind in ["hu", "pass"]:
		if not game._legal_options(kind).is_empty():
			if _press(_named_button("MahjongAction_" + kind), kind): _commands += 1
			return false
	if not game._legal_options("play").is_empty() and not game._array("hand").is_empty():
		game._select_tile(int(game._array("hand")[0].id))
		if _press(_named_button("MahjongPlaySelectedTile"), "discard"): _commands += 1
	return false


func _verify_settlement(round_number: int) -> bool:
	var game = _table()
	var state: Dictionary = game._state
	if not _verify_custom_rules(state, "settlement", round_number): return false
	var panel := game.find_child("MahjongSettlement", true, false) as Control
	var scores := game._array("scores") as Array
	if not _same_table(state) or not is_instance_valid(panel) or not panel.is_visible_in_tree() or scores.size() != 4 or _app._recent.size() != round_number:
		return false
	var result: Dictionary = _app._recent[0]
	if result.get("match_id") != _match_id or result.get("kind") != "friend" or int(result.get("score")) != int(scores[_seat]): return false
	var prefix := "settlement-%d" % round_number
	if not _receipt("%s-%d" % [prefix, _peer], {
		"match_id": _match_id, "room_id": _room, "seat": _seat,
		"scores": scores.map(func(value): return int(value)),
		"winners": game._array("winners").map(func(value): return int(value)),
		"reason": state.get("reason"), "commands": _commands,
	}): return false
	var captured := "captured-%d" % round_number
	if _peer == 0:
		if not await _until(_all_receipts.bind(prefix), "all four settlement snapshots"): return false
		var screenshot := "settlement.png" if round_number == 1 else "settlement_next_round.png"
		return await _capture(screenshot) and _receipt(captured, true)
	return await _until(func(): return FileAccess.file_exists(_file(captured)), "host captured settlement")


func _play_rematch() -> bool:
	var first_match := _match_id
	var first_seat := _seat
	var first_commands := _commands
	if not await _until(func(): return _button_ready(_named_button("MahjongNextRoundButton")), "settlement next-round button"): return false
	if _peer == 0:
		if not await _until(func(): return int(_app._match.get("ready_players", 0)) == 3, "three guests ready from settlement alone"): return false
		if _app._state != "game" or _app._match.get("previous_match_id") != first_match: return false
		if not _verify_custom_rules(_app._match, "waiting", 2): return false
		if not await _capture("settlement_before_last_rematch_click.png"): return false
	var again := _named_button("MahjongNextRoundButton")
	if DisplayServer.get_name() == "headless":
		if not _press(again, "ready for next hand from settlement"): return false
	else:
		if not _button_ready(again): return false
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = again.get_global_transform_with_canvas() * (again.size * 0.5)
		click.pressed = true
		root.push_input(click, true)
		await process_frame
		click.pressed = false
		root.push_input(click, true)
	if not await _until(_table_playing, "round two table"): return false
	if not _verify_deal(2) or _seat != first_seat or _match_id == first_match: return false
	if not await _until(_all_receipts.bind("deal-2"), "round two private deals"): return false
	print("MAHJONG_GUIYANG_REMATCH_READY index=%d room=%s seat=%d" % [_peer, _room, _seat])
	if _peer == 0 and not await _capture("friend_table_next_round.png"): return false
	_commands = 0
	if not await _until(_drive_round, "round two settlement"): return false
	if not await _verify_settlement(2): return false
	_commands += first_commands
	if not await _until(func(): return _button_ready(_named_button("MahjongSettlementLobbyButton")), "settlement leave-room button"): return false
	if not _press(_named_button("MahjongSettlementLobbyButton"), "leave friend room after round two"): return false
	return await _until(func(): return _app._state == "lobby" and _app._match.get("status") == "idle", "return to lobby after leaving the retained room")
