extends SceneTree

class OfflineApp:
	extends "res://scripts/main.gd"
	func _request_health() -> void: _show_login()

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition: return
	_failures += 1
	push_error(message)


func _click(control: Control, local_point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = control.get_global_transform_with_canvas() * local_point
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)
	await process_frame


func _press(button: Button) -> void:
	if not is_instance_valid(button) or not button.is_visible_in_tree() or button.disabled:
		_check(false, "The expected action must be visible and enabled")
		return
	if DisplayServer.get_name() == "headless":
		button.pressed.emit()
	else:
		var ancestor := button.get_parent()
		while ancestor != null:
			if ancestor is ScrollContainer:
				ancestor.ensure_control_visible(button)
				await process_frame
			ancestor = ancestor.get_parent()
		await _click(button, button.size * 0.5)


func _check_inventory(board) -> void:
	var wall: Variant = board.get("_training_wall")
	var other_hands: Variant = board.get("_training_other_hands")
	if not wall is Array or not other_hands is Array:
		_check(false, "The declared remaining and concealed counts must come from a physical wall and actual deals")
		return
	var tiles: Array = wall + board._state.hand
	var counts: Array = [board._state.hand.size()]
	for hand: Array in other_hands:
		counts.append(hand.size())
		tiles.append_array(hand)
	for discard: Dictionary in board._state.discards:
		tiles.append(discard.tile)
	_check(counts == board._state.hand_counts and counts.slice(1) == [13,13,13], "The four seat counts must match the real concealed hands")
	_check(wall.size() == board._state.remaining, "Visible remaining count must match the physical wall")
	var identities := {}
	var kinds := {}
	for tile: Dictionary in tiles:
		var kind := "%s:%d" % [tile.suit, tile.rank]
		identities[tile.id] = true
		kinds[kind] = int(kinds.get(kind, 0)) + 1
	_check(tiles.size() == 108 and identities.size() == 108 and not identities.has(0), "Wall, hands and discards must conserve 108 unique physical tiles")
	_check(kinds.size() == 27 and kinds.values().all(func(count: int) -> bool: return count == 4), "Each of the 27 ranks and suits must have exactly four copies")


func _capture(name: String) -> void:
	var directory := OS.get_environment("MAHJONG_PRACTICE_PREVIEW_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var path := directory.path_join("%s_%dx%d.png" % [name, root.size.x, root.size.y])
	_check(root.get_texture().get_image().save_png(path) == OK, "The native screenshot must be saved")


func _check_guided(app: Control) -> void:
	await _press(app.find_child("MahjongGuidedTrainingButton", true, false) as Button)
	for frame in 3: await process_frame
	var guided := app.find_child("MahjongGuidedPage", true, false) as Control
	var back := guided.find_child("MahjongGuidedBackButton", true, false) as Button
	var lesson := guided.find_child("MahjongGuidedLessonTitle", true, false) as Label
	var panel := guided.find_child("MahjongGuidedLessonPanel", true, false) as PanelContainer
	_check(back.is_visible_in_tree() and back.icon != null and back.get_global_rect().get_center().x > guided.get_global_rect().get_center().x, "Teaching must offer its shared back control at the upper right")
	_check(is_instance_valid(lesson) and is_instance_valid(panel) and is_equal_approx(lesson.get_global_rect().get_center().x, panel.get_global_rect().get_center().x), "Teaching must align the shared wood title to the lesson panel")
	var hand_tile := guided.find_child("MahjongGuidedTile3", true, false) as Button
	if root.get_visible_rect().size.y >= 680.0:
		_check(root.get_visible_rect().encloses(hand_tile.get_global_rect()), "The first teaching hand must fit on screens at least 680 pixels high")
	await _capture("guided")
	await _press(hand_tile)
	await _press(guided.find_child("MahjongGuidedDiscardButton", true, false) as Button)
	_check(lesson.text == "碰牌", "The teaching tile and discard controls must advance the lesson")
	await _press(back)
	for frame in 3: await process_frame
	_check(not guided.is_visible_in_tree(), "The teaching back action must restore training hall navigation")


func _run() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var app := OfflineApp.new()
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(app)
	# The test advances multiple discards per frame, outside the audio cadence.
	app._audio.effects_enabled = false
	app._account = {"account_id": "local-test", "display_name": "练习牌友"}
	app._show_lobby()
	for frame in 3: await process_frame
	var hall := app.find_child("MahjongTrainingHallButton", true, false) as Button
	await _press(hall)
	for frame in 3: await process_frame
	await _check_guided(app)
	var practice := app.find_child("MahjongPracticeButton", true, false) as Button
	await _press(practice)
	for frame in 3: await process_frame
	var board = app._game
	if not is_instance_valid(board):
		_check(false, "The lobby training button must open the existing offline 3D board")
		quit(1)
		return
	var network_events: Array[String] = []
	board.match_finished.connect(func(_result): network_events.append("settlement"))
	board.wallet_snapshot_received.connect(func(_snapshot): network_events.append("wallet"))
	board.request_next_round.connect(func(): network_events.append("rematch"))
	_check(board.training_mode and board._transport == null, "Practice must run without a board connection")
	_check(board._state.hand_counts == [14,13,13,13] and board._state.remaining == 55 and board._state.discards.is_empty(), "A new practice round deals 53 of the 108 tiles")
	_check_inventory(board)
	var initial_hand: Array = board._state.hand.duplicate(true)
	var played_id: int = board._hand_ids[0] if board._hand_ids[0] != board._selected_id else board._hand_ids[1]
	var index: int = board._hand_ids.find(played_id)
	if DisplayServer.get_name() == "headless":
		board._select_tile(played_id)
	else:
		await _click(board._board_view, board._projected_tile_rect(board._hand_models[index]).get_center())
	_check(board._selected_id == played_id and board._state.hand == initial_hand, "Selecting a physical tile raises it without discarding or drawing")
	await _press(board._play_button)
	_check(board._state.discards.size() == 1 and board._state.discards[0].tile.id == played_id, "The play button discards only the selected tile")
	for expected_discards in range(2, 56):
		board._send_action("play", board._hand_ids[0])
		_check(board._state.discards.size() == expected_discards and board._state.hand.size() == 14 and board._state.remaining == 55 - expected_discards, "Every discard before the last must draw exactly one tile")
		if expected_discards % 8 == 0: await process_frame
	_check(board._state.phase == "turn" and board._hand_ids.has(board._state.drawn_tile_id), "Drawing the last wall tile must still allow the final discard")
	_check_inventory(board)
	var last_id: int = board._state.drawn_tile_id
	if last_id == board._selected_id: last_id = board._hand_ids[0] if board._hand_ids[0] != board._selected_id else board._hand_ids[1]
	index = board._hand_ids.find(last_id)
	if DisplayServer.get_name() == "headless":
		board._select_tile(last_id)
	else:
		await _click(board._board_view, board._projected_tile_rect(board._hand_models[index]).get_center())
	await _press(board._play_button)
	_check(board._state.phase == "finished" and board._state.remaining == 0 and board._state.hand.size() == 13 and board._state.discards.size() == 56 and board._state.drawn_tile_id == 0, "The final discard must finish without replenishing the hand")
	_check(board._tool_open == "notice" and board._notice_title == "本局结束", "Finishing practice must open the round-ended notice")
	var notice: Control = board._tool_surface
	board._render()
	_check(notice == board._tool_surface, "A repeated finished snapshot must preserve the open notice")
	await _capture("practice_finished_notice")
	await _press(board.find_child("MahjongNoticeConfirm", true, false) as Button)
	board._render()
	var finished: Dictionary = board._state.duplicate(true)
	board._select_tile(board._hand_ids[0])
	board._on_play()
	board._training_play(board._hand_ids[0])
	_check(board._state == finished and not board._play_button.is_visible_in_tree(), "A finished practice round refuses additional discards")
	_check(board._selected_id == 0 and board._tool_open.is_empty(), "A finished practice round refuses selection and keeps the acknowledged notice closed")
	_check_inventory(board)
	var restart := board.find_child("MahjongPracticeRestartButton", true, false) as Button
	_check(is_instance_valid(restart) and restart.is_visible_in_tree() and not restart.disabled, "The finished board must offer a usable restart")
	if is_instance_valid(restart):
		_check(board._usable_modal_area().encloses(restart.get_global_rect()), "The restart must fit inside the safe display area")
		await _capture("practice_finished")
		await _press(restart)
		_check(board._state.phase == "turn" and board._state.discards.is_empty() and board._state.remaining == 55 and board._state.hand != initial_hand and board._state.hand_counts == [14,13,13,13], "Restart must deal a new shuffled round and clear the previous discards")
		_check(not restart.is_visible_in_tree(), "A live round must restore the discard action")
		_check_inventory(board)
		await _capture("practice_restarted")
	_check(network_events.is_empty(), "Practice completion and restart must stay out of settlement, wallet and rematch events")
	app.queue_free()
	await process_frame
	if _failures == 0: print("MAHJONG_PRACTICE_WALL_OK tiles=108 copies=4 reserved=53 drawn=55 discarded=56 restored=55 offline=true guided=true")
	quit(1 if _failures else 0)
