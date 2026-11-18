extends SceneTree

class ScreenFixture:
	extends "res://modules/games/mahjong/guiyang/guiyang_3d_screen.gd"
	func _load_quality() -> void:
		super._load_quality()
		_music_enabled = false
		_sound_enabled = false
	func _connect_socket() -> void: pass
	func _transport_open() -> bool: return true

var failures: Array[String] = []

func _initialize() -> void: call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var board := ScreenFixture.new()
	board.preference_file = "user://coach-labels-fixture-%d.cfg" % OS.get_process_id()
	board._load_quality()
	_check(not board._coach_enabled, "The labels must start hidden with no saved preference")
	var old_preferences := ConfigFile.new()
	old_preferences.set_value("assistance", "efficiency", false)
	old_preferences.save(board.preference_file)
	board.match_context = {"room_id":"coach-labels", "seat_index":0, "kind":"friend"}
	root.add_child(board)
	await process_frame
	_check(not board._coach_enabled, "An old preference file without a labels choice must start with hidden labels")
	var hand: Array = []
	for rank in [1,2,3,4,5,6,9]: hand.append({"id":hand.size()+1,"suit":"wan","rank":rank})
	for rank in [7,8,9]: hand.append({"id":hand.size()+1,"suit":"tong","rank":rank})
	for rank in [2,2,5,6]: hand.append({"id":hand.size()+1,"suit":"tiao","rank":rank})
	var packet := {"type":"mahjong_state","room_id":"coach-labels","match_id":"coach-hand","epoch":1,
		"status":"playing","phase":"turn","your_seat":0,"turn":0,"players":["me","p1","p2","p3"],
		"hand":hand,"hand_counts":[14,13,13,13],"melds":[[],[],[],[]],"discards":[],"remaining":55,
		"scores":[0,0,0,0],"options":[{"type":"play"}],"rule_set_id":"guiyang","rule_version":"2.0.0"}
	board._joined = true
	board._handle_packet(JSON.stringify(packet))
	_check(board._coach_results.size() == 14, "Every legal physical discard must get real native analysis")
	_check(board._coach_overlay._badges.is_empty(), "The first confirmed hand must not create labels when disabled")
	_check(board._selected_id == 7, "The recommended discard must still be selected with labels hidden")
	board._set_coach_enabled(true)
	board._load_quality()
	_check(board._coach_enabled, "An explicit choice to show the labels must persist")
	var badge: Control = board._coach_overlay.get_node_or_null("MahjongEfficiencyBadge7")
	_check(badge != null and badge.text == "0·8", "The known hand must display the Rust 0-shanten / 8-unseen-tile result")
	board._select_tile(7)
	if badge != null:
		_check(badge.recommended and badge.selected, "Selection and recommendation must remain distinguishable on the same tile")
	var table_poses := {}
	for model: Node3D in board._pieces_root.get_children():
		table_poses[model] = model.global_transform
	for dimensions in [Vector2i(1440,810), Vector2i(1800,810), Vector2i(1440,900), Vector2i(1440,1080)]:
		root.content_scale_size = Vector2i.ZERO
		root.size = dimensions
		await process_frame
		await process_frame
		board._layout_ui()
		for model: Node3D in table_poses:
			_check(model.global_transform.is_equal_approx(table_poses[model]), "Refitting the camera must leave every tile's pose unchanged")
		for id in board._coach_overlay._badges:
			var item: Control = board._coach_overlay._badges[id]
			var label := Rect2(item.position + item.badge_rect.position, item.badge_rect.size)
			_check(Rect2(Vector2.ZERO, board.size).encloses(label), "Labels must remain in bounds at " + str(dimensions))
			_check(is_equal_approx(label.size.y, 64.0 / 3.0), "Each capsule must be two thirds of the original label height")
			for model in board._hand_models:
				var face: Rect2 = board._projected_tile_rect(model)
				face.position += board._board_view.position
				_check(not label.intersects(face), "Labels cannot cover any tile face")
				if board._frames_player_hand():
					_check(label.position.y >= board._projected_tile_rect(model, &"TileBody").end.y, "All phone capsules must fit below the hand")
	# Incoming visible tiles change the effective count using snapshot events only.
	packet.epoch = 2
	packet.discards = [{"seat":1,"tile":{"id":20,"suit":"tiao","rank":4},"claimed":false}]
	board._handle_packet(JSON.stringify(packet))
	badge = board._coach_overlay.get_node_or_null("MahjongEfficiencyBadge7")
	_check(badge != null and badge.text == "0·7", "A newly public effective tile must update the count on the same state event")
	board._pending_action = true
	board._layout_coach()
	_check(badge.text == "0·7", "Sending a command must retain confirmed values until its snapshot arrives")
	board._pending_action = false
	packet.epoch = 3
	packet.options = []
	packet.turn = 1
	var discarded: Dictionary = packet.hand.pop_at(6)
	packet.discards.append({"seat":0,"tile":discarded,"claimed":false})
	packet.hand_counts[0] = 13
	board._handle_packet(JSON.stringify(packet))
	_check(board._coach_results.size() == 13, "Between turns every tile must retain a whole-hand baseline")
	badge = board._coach_overlay.get_node_or_null("MahjongEfficiencyBadge1")
	_check(badge != null and badge.text == "0·7" and not badge.recommended and "当前整手" in (badge.get_node("Inspect") as Button).tooltip_text,
		"13-tile values must be identified as whole-hand analysis, never a discard recommendation")
	for other in range(1,4):
		packet.epoch += 1
		packet.turn = (other+1)%4
		packet.discards.append({"seat":other,"tile":{"id":20+other,"suit":"tiao","rank":4 if other == 1 else 7},"claimed":false})
		board._handle_packet(JSON.stringify(packet))
		_check(badge.text == "0·%d" % (7-other), "Each other seat's public discard must recompute the 13-tile baseline")
	var old := packet.duplicate(true)
	old.epoch = 2
	old.discards = []
	board._handle_packet(JSON.stringify(old))
	_check(badge.text == "0·4", "A delayed old snapshot must not restore stale effective counts")
	board._joined = false
	board._layout_coach()
	_check(badge.text == "0·4", "A transport interruption must not erase the last confirmed hand values")
	_check("最近一次同步" in (badge.get_node("Inspect") as Button).tooltip_text, "Retained disconnected values must identify their last-snapshot origin")
	board._joined = true
	board._coach = null
	packet.epoch += 1
	board._handle_packet(JSON.stringify(packet))
	badge = board._coach_overlay.get_node_or_null("MahjongEfficiencyBadge1")
	_check(badge != null and badge.text == "—" and "组件未加载" in (badge.get_node("Inspect") as Button).tooltip_text,
		"Missing native analysis must remain unknown with an honest reason")
	board._set_coach_enabled(false)
	board._load_quality()
	_check(not board._coach_enabled, "An explicit choice to hide the new labels must persist")
	board.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty(): print("MAHJONG_COACH_LABELS_OK default_off=true native_14_candidates=true public_tile_event=true four_aspects=true selected_recommended=true persistent_choice=true")
	quit(0 if failures.is_empty() else 1)
