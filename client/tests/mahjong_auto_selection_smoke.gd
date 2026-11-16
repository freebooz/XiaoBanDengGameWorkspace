extends SceneTree

class Fixture:
	extends "res://modules/games/mahjong/guiyang/guiyang_3d_screen.gd"
	var commands: Array[Dictionary] = []
	var defer_selection := false
	var auto_selections := 0
	func _connect_socket() -> void: pass
	func _transport_open() -> bool: return true
	func _send(packet: Dictionary) -> void:
		_last_send_error = OK
		if packet.get("type") == "mahjong_action": commands.append(packet.duplicate(true))
	func _load_quality() -> void:
		super._load_quality()
		_music_enabled = false
		_sound_enabled = false
	func _apply_coach_auto_selection(source_key: Array, results: Dictionary) -> void:
		if defer_selection: return
		_deliver(source_key, results)
	func _deliver(source_key: Array, results: Dictionary) -> void:
		var before := _coach_auto_selected
		super._apply_coach_auto_selection(source_key, results)
		if not before and _coach_auto_selected: auto_selections += 1

var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _packet() -> Dictionary:
	var hand: Array = []
	for rank in [1,2,3,4,5,6,9]: hand.append({"id":hand.size()+1,"suit":"wan","rank":rank})
	for rank in [7,8,9]: hand.append({"id":hand.size()+1,"suit":"tong","rank":rank})
	for rank in [2,2,5,6]: hand.append({"id":hand.size()+1,"suit":"tiao","rank":rank})
	return {"type":"mahjong_state","room_id":"auto-choice","match_id":"auto-hand","epoch":1,
		"status":"playing","phase":"turn","your_seat":0,"turn":0,"players":["me","p1","p2","p3"],
		"hand":hand,"hand_counts":[14,13,13,13],"melds":[[],[],[],[]],"discards":[],"remaining":55,
		"scores":[0,0,0,0],"options":[{"type":"play"}],"rule_set_id":"guiyang","rule_version":"2.0.0"}

func _run() -> void:
	var board := Fixture.new()
	board.preference_file = "user://auto-selection-fixture.cfg"
	board.match_context = {"room_id":"auto-choice", "seat_index":0, "kind":"friend"}
	root.add_child(board)
	await process_frame
	board._joined = true
	var packet := _packet()
	board._handle_packet(JSON.stringify(packet))
	_check(board._selected_id == 7, "Entering our legal discard window must select the real Rust best discard")
	_check(board.commands.is_empty() and not board._pending_action, "Automatic selection must never submit a play command")
	_check(board.auto_selections == 1, "Initial layout reentry must not select twice")
	var delayed_key: Array = board._coach_key.duplicate(true)
	var delayed_results: Dictionary = board._coach_results.duplicate(true)
	packet.epoch += 1
	packet.discards.append({"seat":1,"tile":{"id":20,"suit":"tiao","rank":4},"claimed":false})
	board._handle_packet(JSON.stringify(packet))
	board._layout_ui()
	_check(board._selected_id == 7 and board.auto_selections == 1, "Public snapshots and resize cannot repeat automatic selection within a window")
	board._select_tile(1)
	packet.epoch += 1
	packet.discards.append({"seat":2,"tile":{"id":21,"suit":"tiao","rank":4},"claimed":false})
	board._handle_packet(JSON.stringify(packet))
	_check(board._selected_id == 1 and board.auto_selections == 1, "Manual selection must beat a later native refresh in the same turn")
	board._joined = false
	board._layout_coach()
	board._joined = true
	board._layout_coach()
	_check(board._selected_id == 1, "Reconnect layout cannot seize a manual choice in the same hand")
	# An intervening reaction closes the old decision even with identical cards.
	packet.epoch += 1
	packet.phase = "reaction"
	packet.options = [{"type":"pass"}]
	board._handle_packet(JSON.stringify(packet))
	board._select_tile(0)
	board._deliver(delayed_key, delayed_results)
	_check(board._selected_id == 0 and board.auto_selections == 1, "No late analysis may select a discard during reactions")
	packet.epoch += 1
	packet.phase = "turn"
	packet.options = [{"type":"play","tile_id":1}]
	board._handle_packet(JSON.stringify(packet))
	_check(board._selected_id == 1 and board.auto_selections == 2, "Re-entering play must select only the server-authorized physical candidate")
	# A genuine new drawn tile resets manual priority for this new decision.
	board._select_tile(2)
	packet.epoch += 1
	packet.options = [{"type":"play"}]
	packet.hand[6].id = 50
	packet["drawn_tile_id"] = 50
	board._handle_packet(JSON.stringify(packet))
	_check(board._selected_id == 50 and board.auto_selections == 3, "New drawn-hand identity must select its newly computed best candidate")
	# Defer selection to exercise the exact result identity guard as if a native
	# calculation completed after a newer snapshot. No guessed results are used.
	board.defer_selection = true
	packet.epoch += 1
	packet.hand[6].id = 51
	packet.drawn_tile_id = 51
	board._handle_packet(JSON.stringify(packet))
	_check(board._selected_id == 0, "Replacing the selected physical tile must drop its old selection")
	board._deliver(delayed_key, delayed_results)
	_check(board._selected_id == 0, "Result from an earlier snapshot must be rejected in a new discard window")
	var current_key: Array = board._coach_key.duplicate(true)
	var current_results: Dictionary = board._coach_results.duplicate(true)
	var invalid := {999:current_results[51].duplicate(true)}
	invalid[1] = current_results[51].duplicate(true)
	invalid[1].analysisMode = "hand"
	board._deliver(current_key, invalid)
	_check(board._selected_id == 0, "Unknown tile IDs and whole-hand baselines cannot become discard selections")
	board._deliver(current_key, current_results)
	_check(board._selected_id == 51 and board.auto_selections == 4, "Only a valid result for the current snapshot may complete deferred selection")
	# If the player chose a tile before that result arrived, preserve their choice.
	packet.epoch += 1
	packet.hand[6].id = 52
	packet.drawn_tile_id = 52
	board._handle_packet(JSON.stringify(packet))
	board._select_tile(3)
	board._deliver(board._coach_key.duplicate(true), board._coach_results)
	_check(board._selected_id == 3 and board.auto_selections == 4, "A manual choice made before analysis completion has priority")
	# Empty/native-unavailable analysis does nothing; restoring native can select
	# the still-current decision when no manual choice was made.
	board.defer_selection = false
	var native: Object = board._coach
	board._coach = null
	packet.epoch += 1
	packet.hand[6].id = 53
	packet.drawn_tile_id = 53
	board._selected_id = 0
	board._handle_packet(JSON.stringify(packet))
	_check(board._selected_id == 0 and board.auto_selections == 4, "Missing native analysis must not guess a preferred tile")
	board._coach = native
	board._layout_coach()
	_check(board._selected_id == 53 and board.auto_selections == 5, "A current valid native result can select after initial unavailability")
	# Selecting automatically is not submitting; the subsequent real tile click
	# uses exactly the ordinary click-confirm and pending-command guard.
	_check(board.commands.is_empty(), "All automatic selections must remain local until player confirmation")
	var index: int = board._hand_ids.find(53)
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = board._projected_tile_rect(board._hand_models[index]).get_center()
	board._on_board_input(click)
	board._on_board_input(click)
	_check(board.commands.size() == 1 and board.commands[0].tile_id == 53 and board._pending_action,
		"Clicking the auto-selected tile must submit once, with repeat blocked while pending")
	board._clear_pending_command()
	packet.epoch += 1
	packet.turn = 1
	packet.hand.remove_at(6)
	packet.options = []
	board._handle_packet(JSON.stringify(packet))
	board._selected_id = 0
	board._deliver(current_key, current_results)
	_check(board._selected_id == 0, "Opponent turn cannot select a discard even if an old result arrives")
	board._set_coach_enabled(false)
	var tied := _packet()
	tied.epoch = packet.epoch + 1
	tied.options = [{"type":"play","tile_id":12},{"type":"play","tile_id":11}]
	board._handle_packet(JSON.stringify(tied))
	_check(board._selected_id == 11, "Equal native rank candidates must choose stable physical ID, independent of option order or hidden labels")
	board._set_coach_enabled(true)
	board.queue_free()
	await process_frame
	if failures.is_empty(): print("MAHJONG_AUTO_SELECTION_OK native_best=true no_auto_submit=true manual_priority=true stable_window=true new_draw=true delayed_result_guard=true legal_id_filter=true click_confirms_once=true")
	quit(0 if failures.is_empty() else 1)
