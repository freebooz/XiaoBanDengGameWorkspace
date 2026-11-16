extends SceneTree
## Four real product shells and real table controls through the local server.
var _apps: Array = []
var _games: Array = []
var _deadline := 0
var _actions := 0

func _initialize() -> void:
	call_deferred("_run")

func _wait(check: Callable, message: String) -> bool:
	while not check.call():
		await process_frame
		if Time.get_ticks_msec() > _deadline:
			push_error(message)
			return false
	return true

func _buttons(parent: Node) -> Array[Button]:
	var result: Array[Button] = []
	for child in parent.get_children():
		if child.is_queued_for_deletion(): continue
		if child is Button: result.append(child)
		result.append_array(_buttons(child))
	return result

func _show(game: Control) -> void:
	for index in range(_games.size()): _apps[index].visible = _games[index] == game

func _press(parent: Node, text: String) -> bool:
	for button in _buttons(parent):
		if button.text == text and not button.disabled:
			button.pressed.emit()
			return true
	push_error("Actual Mahjong button is unavailable: " + text)
	return false

func _all_epoch(epoch: int) -> bool:
	for game in _games:
		if int(game._state.get("epoch", 0)) < epoch: return false
	return true

func _fingerprint(game: Control) -> String:
	return JSON.stringify([game._state.get("epoch", 0), game._state.get("phase", ""), game._options(), game._array("hand")])

func _kind(options: Array, name: String) -> bool:
	return options.any(func(option): return str(option.get("type", "")) == name)

func _capture() -> void:
	if DisplayServer.get_name() == "headless": return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screen-out="):
			for frame in range(16): await process_frame
			root.get_texture().get_image().save_png(arg.trim_prefix("--screen-out="))

func _run() -> void:
	var lobby_design := root.content_scale_size
	_deadline = Time.get_ticks_msec() + 65000
	for index in range(4):
		var app = load("res://scripts/main.gd").new()
		root.add_child(app)
		app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		app.visible = index == 0
		_apps.append(app)
	if not await _wait(func(): return _apps.all(func(app): return app._state == "login" and not app._guest_button.disabled),
		"Guest login controls are not available after the server check"): quit(1); return
	for app in _apps:
		app._guest_button.pressed.emit()
	if not await _wait(func(): return _apps.all(func(app): return app._state == "guest_identity"),
		"Guest identity confirmations are missing"): quit(1); return
	for app in _apps:
		if not _press(app, "进入游戏大厅"): quit(1); return
	if not await _wait(func():
		_games.clear()
		for app in _apps:
			if app._state == "game":
				var game = app._screen.get_child(app._screen.get_child_count()-1)
				game._auto_played = true
				if game._state.get("status", "") == "playing" and game._actions_ready(): _games.append(game)
		return _games.size() == 4, "Four Mahjong clients failed login/match/ready/join"): quit(1); return
	var room := str(_games[0].match_context.room_id)
	var private_ids := {}
	for index in range(4):
		_apps[index]._auto_flow = false
		var game = _games[index]
		if str(game.match_context.room_id) != room or game._state.has("wall"): quit(2); return
		for other in range(index):
			if game._board_viewport.find_world_3d() == _games[other]._board_viewport.find_world_3d(): quit(3); return
		for tile in game._array("hand"):
			if private_ids.has(int(tile.id)): quit(4); return
			private_ids[int(tile.id)] = true
		var chi = game._actions_root.find_child("MahjongAction_chi", true, false)
		if chi == null or not chi.disabled: quit(5); return
	var social = _games[0]
	_show(social)
	social._open_tool("chat")
	await process_frame
	if not _press(social._overlay_root, social.CHAT_TEXTS[0]): quit(6); return
	var sender := int(social._state.your_seat)
	if not await _wait(func():
		for game in _games:
			if not game._social_events.has(sender): return false
		return true, "Mahjong room chat was not broadcast to all four clients"): quit(7); return
	await create_timer(1.05).timeout
	for game in _games: game._social_events.clear()
	social._open_tool("emote")
	await process_frame
	if not _press(social._overlay_root, social.EMOTE_TEXTS[2]): quit(8); return
	if not await _wait(func():
		for game in _games:
			if not game._social_events.has(sender): return false
		return true, "Mahjong emote was not received"): quit(9); return
	for sample_rate in [8000,16000]:
		await create_timer(1.05).timeout
		var pcm := PackedByteArray()
		pcm.resize(sample_rate * 5 * 2)
		pcm.fill(0)
		for game in _games: game._social_events.clear()
		if not social._submit_social({"type":"mahjong_social", "action":"voice", "sample_rate":sample_rate, "duration_ms":5000, "pcm_base64":Marshalls.raw_to_base64(pcm)}): quit(10); return
		if not await _wait(func():
			for game in _games:
				if not game._social_events.has(sender): return false
			return true, "Native maximum Mahjong voice did not reach all four clients"): quit(11); return
		print("MAHJONG_NATIVE_VOICE_OK rate=", sample_rate, " seconds=5 clients=4")
	await _capture()
	for step in range(180):
		if _games[0]._state.get("phase", "") == "finished": break
		var actor
		for game in _games:
			if not game._options().is_empty(): actor = game; break
		if actor == null:
			await process_frame
			continue
		_show(actor)
		var before := _fingerprint(actor)
		var options: Array = actor._options()
		var kind := ""
		if _kind(options, "hu"): kind = "hu"
		elif options.any(func(option): return str(option.get("type", "")).ends_with("_gang")): kind = "gang"
		elif _kind(options, "peng"): kind = "peng"
		elif _kind(options, "pass"): kind = "pass"
		else: kind = "play"
		if kind == "play":
			actor._select_tile(int(actor._array("hand")[0].id))
			if actor._play_button.disabled: quit(12); return
			actor._play_button.pressed.emit()
		else:
			var button = actor._actions_root.find_child("MahjongAction_" + kind, true, false)
			if button == null or button.disabled: quit(13); return
			button.pressed.emit()
			await process_frame
			if kind == "gang" and actor._tool_open == "gang":
				var choices := _buttons(actor._overlay_root).filter(func(choice): return choice.name.begins_with("MahjongGangChoice") and not choice.disabled)
				if choices.is_empty(): quit(14); return
				choices[0].pressed.emit()
		if not await _wait(func(): return _fingerprint(actor) != before, "Real Mahjong action did not update authoritative state: " + kind): quit(15); return
		if not await _wait(func(): return _all_epoch(int(actor._state.get("epoch", 0))), "Mahjong action did not broadcast state"): quit(16); return
		_actions += 1
		if _actions == 18:
			for game in _games:
				if _kind(game._options(), "play"): _show(game); break
			await _capture()
	if not await _wait(func():
		for game in _games:
			if game._state.get("phase", "") != "finished": return false
		return true, "Mahjong match did not reach full settlement"): quit(17); return
	for game in _games:
		_show(game)
		if not _press(game._overlay_root, "返回大厅"): quit(18); return
	await process_frame
	if root.content_scale_size != lobby_design: quit(19); return
	for app in _apps:
		if app._state != "lobby": quit(20); return
		app.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("MAHJONG_REFERENCE_LIVE_FLOW_OK clients=4 room=",room," private_tiles=",private_ids.size()," worlds=4 actual_actions=",_actions," chat=true emote=true maximum_voice=true settlement=true lobby_restored=true")
	quit()
