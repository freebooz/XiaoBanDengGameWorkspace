extends SceneTree
## Exercise the production finished-round overlay with a private participant snapshot.

class Board extends "res://modules/games/mahjong/guiyang/guiyang_3d_screen.gd":
	func _connect_socket() -> void: pass

var failed := false
var capture_dir := ""

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func _wait_layout() -> void:
	for frame in 7: await process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func _hand(numbers: Array, start: int) -> Array:
	var tiles := []
	for n: int in numbers:
		tiles.append({"id":start+tiles.size(), "suit":["wan","tong","tiao"][floori(n/10.0)], "rank":n%10})
	return tiles

func _packet() -> Dictionary:
	var hands := [
		_hand([1,1,1,5,5,5,12,12,12,27,27,27,29,29],1),
		_hand([2,3,4,6,7,8,14,15,16,22,23,24,28],16),
		_hand([3,4,6,7,9,9,12,13,14,21,22,23,28],30),
		_hand([2,3,4,7,8,9,15,16,17,23,24,25,28],44)]
	return {"type":"mahjong_state","room_id":"3481","match_id":"settlement-fixture","kind":"friend",
		"phase":"finished","status":"finished","epoch":9,"remaining":46,"your_seat":0,"dealer":0,
		"rule_set_id":"guiyang","rule_version":"3.0.0","rule":{"name":"贵阳捉鸡"},
		"players":["a","b","c","d"],"player_names":["稻香阿明","稻香大叔","河湾老张","田埂阿梅"],
		"hand":hands[0],"settlement_hands":hands,"hand_counts":[14,13,13,13],"melds":[[],[],[],[]],
		"winners":[0],"win_from":-1,"win_kind":"zi_mo","scores":[24,-8,-8,-8],
		"egg_deltas":[24,-8,-8,-8],"egg_counts":[524,492,492,492],"round_limit":8,"completed_rounds":2,"can_rematch":true,
		"hu_details":[{"seat":0,"kind":"zi_mo","pattern":"大对子","fan":6,"points":18}],
		"fan_breakdown":[{"seat":0,"items":[{"name":"大对子","fan":5},{"name":"自摸","fan":1}],"total":6}],
		"score_breakdown":{"hu":[18,-6,-6,-6],"gang":[0,0,0,0],"ji":[6,-2,-2,-2]}}

func _click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = point
	root.push_input(move, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)

func _check_caption_pixels(control: Control, frame: Image) -> void:
	var transform := control.get_viewport_transform() * control.get_global_transform()
	var bounds := Rect2i(transform * Rect2(Vector2.ZERO,control.size)).grow(-6).intersection(Rect2i(Vector2i.ZERO,frame.get_size()))
	var light_pixels := 0
	for x in range(bounds.position.x,bounds.end.x):
		for y in range(bounds.position.y,bounds.end.y):
			var ink := frame.get_pixel(x,y)
			if ink.r > 0.88 and ink.g > 0.82 and ink.b > 0.67: light_pixels += 1
	_check(light_pixels > 12,"The utility caption must retain legible glyphs after a portrait resize.")

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir = arg.trim_prefix("--capture-dir=")
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_check(Engine.max_fps == 0 and DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED, "Native settlement verification needs uncapped rendering.")
		print("Settlement render: max_fps=%d vsync=%d" % [Engine.max_fps,DisplayServer.window_get_vsync_mode()])
	root.size = Vector2i(1440,810)
	var board := Board.new()
	board.size = Vector2(1440,810)
	board.preserve_window_size = true
	board.match_context = {"room_id":"3481","display_name":"稻香阿明","kind":"friend","rule_set_id":"guiyang","rule_version":"3.0.0"}
	root.add_child(board)
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board._handle_packet(JSON.stringify({"type":"mahjong_joined","room_id":"3481","your_seat":0}))
	var packet := _packet()
	board._handle_packet(JSON.stringify(packet))
	await _wait_layout()
	var panel := board.find_child("MahjongSettlement", true, false) as Panel
	var share := board.find_child("MahjongSettlementShareButton", true, false) as Button
	_check(is_instance_valid(share), "Finished rounds need the share action.")
	_check(board.find_child("MahjongSettlementRoomButton", true, false) != null, "Retained rooms need a return action separate from readying up.")
	_check(board.find_child("MahjongSettlementFanTotal", true, false) != null, "Missing fan calculation.")
	for seat in 4:
		_check(board.find_child("MahjongSettlementHand%d" % seat, true, false) != null, "Missing seated hand %d" % seat)
	if failed:
		board.queue_free()
		await process_frame
		quit(1)
		return
	for extent in [Vector2i(1672,941),Vector2i(1280,720),Vector2i(1200,540),Vector2i(1280,800),Vector2i(1024,768),Vector2i(390,844),Vector2i(880,580)]:
		root.size = extent
		await _wait_layout()
		_check(board.get_global_rect().grow(2).encloses(panel.get_global_rect()), "Settlement exceeds the visible board at " + str(extent))
		for id in ["MahjongNextRoundButton","MahjongSettlementRoomButton","MahjongSettlementShareButton"]:
			var button := panel.find_child(id, true, false) as Button
			_check(button.is_visible_in_tree() and panel.get_global_rect().grow(1).encloses(button.get_global_rect()), "Unreachable " + id + " at " + str(extent))
		for tool: Button in panel._tools.get_children():
			var caption := tool.get_node("Caption") as Label
			_check(panel.get_global_rect().grow(1).encloses(tool.get_global_rect()) and caption.size.x >= caption.get_minimum_size().x, "Clipped utility button at " + str(extent))
		for card: Panel in [panel._score_card,panel._fan_card]:
			var rows := card.get_child(-1) as VBoxContainer
			_check(card.get_global_rect().grow(1).encloses(rows.get_global_rect()),"A score line overflows its card at " + str(extent))
		if not capture_dir.is_empty() and DisplayServer.get_name() != "headless":
			var rendered := root.get_texture().get_image()
			_check(rendered.get_size() == root.size, "Expected an unscaled native screenshot.")
			_check(rendered.save_png(capture_dir.path_join("settlement-%dx%d.png" % [extent.x,extent.y])) == OK, "Cannot save screenshot")
		if extent.x < extent.y:
			if DisplayServer.get_name() != "headless":
				_check_caption_pixels(panel.find_child("MahjongSettlementDetailsButton",true,false),root.get_texture().get_image())
			panel._scroll.scroll_vertical = roundi(panel._scroll.get_v_scroll_bar().max_value)
			await _wait_layout()
			_check(panel._scroll.get_global_rect().grow(1).encloses(panel._score_card.get_global_rect()),"All four final scores must be reachable by scrolling in portrait.")
			if not capture_dir.is_empty() and DisplayServer.get_name() != "headless":
				root.get_texture().get_image().save_png(capture_dir.path_join("settlement-portrait-scores.png"))
			panel._scroll.scroll_vertical = 0
	var row_one := panel.find_child("MahjongSettlementRow1",true,false) as Button
	_click(row_one)
	await _wait_layout()
	_check("−8" in (panel.find_child("MahjongSettlementFanTotal",true,false) as Label).text or "-8" in (panel.find_child("MahjongSettlementFanTotal",true,false) as Label).text,"Tapping another seat must switch the breakdown.")
	_click(panel.find_child("MahjongSettlementRow0",true,false))
	await _wait_layout()
	var details := panel.find_child("MahjongSettlementDetailsButton", true, false) as Button
	_click(details)
	await _wait_layout()
	var ledger := panel.find_child("MahjongSettlementRoom", true, false) as Label
	_check(ledger.is_visible_in_tree() and "3.0.0" in ledger.text, "A real click must expose the room and rules metadata.")
	packet.egg_counts[0] = 0
	packet.player_names[1] = "田埂上的非常非常长的麻将牌友昵称"
	board._handle_packet(JSON.stringify(packet))
	await _wait_layout()
	panel = board.find_child("MahjongSettlement",true,false) as Panel
	_check(panel.find_child("MahjongSettlementRoom",true,false).is_visible_in_tree(), "A late wallet event must preserve the open details.")
	_click(panel.find_child("MahjongSettlementDetailsClose", true, false))
	await _wait_layout()
	var balance := board.find_child("MahjongSettlementBalance0", true, false) as Label
	_check(balance.text == "0", "Same-epoch wallet refresh must update a zero balance.")
	var fan_total := board.find_child("MahjongSettlementFanTotal", true, false) as Label
	_check("6" in fan_total.text and "番" in fan_total.text, "Use the authoritative total, including the win method only once.")
	packet.erase("settlement_hands")
	packet.erase("fan_breakdown")
	packet.erase("hu_details")
	packet.winners = []
	packet.egg_counts[1] = null
	board._handle_packet(JSON.stringify(packet))
	await _wait_layout()
	_check(board.find_child("MahjongSettlementHand1", true, false) == null, "An older snapshot must never reveal invented opponent tiles.")
	var unknown := board.find_child("MahjongSettlementBalance1", true, false) as Label
	_check(unknown.text == "—", "Unknown balances must remain distinct from zero.")
	_check(board.find_child("MahjongSettlementHand0", true, false) != null, "Private own hand is available on old snapshots.")
	board.queue_free()
	await process_frame
	if not failed: print("MAHJONG_SETTLEMENT_REFERENCE_OK responsive=7 participants=4 private_fallback=true wallet_refresh=true real_click=true")
	quit(1 if failed else 0)
