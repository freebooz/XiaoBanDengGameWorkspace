extends SceneTree

class Table:
	extends "res://modules/games/mahjong/guiyang/guiyang_3d_screen.gd"
	var sent: Array = []
	func _connect_socket() -> void: pass
	func _transport_open() -> bool: return true
	func _send(packet: Dictionary) -> void:
		_last_send_error = OK
		if packet.get("type") == "mahjong_action": sent.append(packet)
	func _play_sound(_cue: String = "discard") -> void: pass
	func _play_callout(_cue: String, _tile: Dictionary = {}) -> void: pass

var failed := false
var serial := 0

func _initialize() -> void: call_deferred("_run")

func _check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func _tiles(kinds: Array) -> Array:
	var copies := {}
	var result := []
	for kind in kinds:
		var copy: int = copies.get(kind, 0)
		copies[kind] = copy + 1
		result.append({"id":kind*4+copy+1,"suit":["wan","tong","tiao"][int(kind)/9],"rank":kind%9+1})
	return result

func _packet() -> Dictionary:
	var hand := _tiles([13,13,13,0,1,2,4,6,8,18,20,22,24])
	var incoming := {"id":65,"suit":"tong","rank":8}
	return {"type":"mahjong_state","room_id":"claims","match_id":"claim-round","status":"playing",
		"phase":"reaction","turn":1,"your_seat":0,"players":["a","b","c","d"],
		"hand":hand,"hand_counts":[13,13,13,13],"melds":[[],[],[],[]],"remaining":40,
		"last_discard":incoming,"discards":[{"seat":1,"tile":incoming,"claimed":false}],
		"rule_set_id":"basic_108","rule_version":"1.0.0",
		"options":[{"type":"peng"},{"type":"ming_gang"},{"type":"hu"},{"type":"pass"}]}

func _push(table: Table, packet: Dictionary) -> void:
	serial += 1
	packet.epoch = serial
	table.sent.clear()
	table._clear_pending_command()
	table._handle_packet(JSON.stringify(packet))
	await process_frame

func _reject(table: Table, packet: Dictionary, kinds: Array, label: String) -> void:
	await _push(table, packet)
	for kind in kinds:
		_check(not table._response_buttons[kind].visible, label+": invalid "+kind+" button displayed")
		table._on_response(kind)
	_check(table.sent.is_empty(), label+": invalid action submitted")

func _run() -> void:
	Engine.max_fps = 0
	if DisplayServer.get_name() != "headless": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var table := Table.new()
	table.match_context = {"room_id":"claims","seat_index":0}
	root.add_child(table)
	await process_frame
	table._handle_packet(JSON.stringify({"type":"mahjong_joined","room_id":"claims","match_id":"claim-round","your_seat":0}))
	await _reject(table, _packet(), ["gang","peng","hu"], "eight dots discarded, three five dots held")
	var packet := _packet()
	packet.rule_set_id = "guiyang"
	packet.rule_version = "3.0.0"
	packet.hand = packet.hand.slice(0,10)
	packet.melds[0] = [{"kind":"an_gang","tiles":_tiles([26,26,26,26]),"from_seat":0}]
	await _reject(table, packet, ["hu"], "completed kong does not make a nonwinning hand win")
	packet = _packet()
	packet.phase = "turn"
	packet.turn = 0
	packet.hand.append({"id":101,"suit":"tiao","rank":8})
	packet.drawn_tile_id = 101
	packet.options = [{"type":"play"},{"type":"hu"}]
	await _reject(table, packet, ["hu"], "nonwinning self draw")
	# Four sets and a pair, waiting for eight dots.
	packet = _packet()
	packet.hand = _tiles([0,1,2,3,4,5,9,10,11,18,19,20,16])
	packet.last_discard.id = 66
	packet.options = [{"type":"hu"},{"type":"pass"}]
	await _push(table, packet)
	_check(table._response_buttons.hu.visible, "legal discard win must remain available")
	table._on_response("hu")
	_check(table.sent.size()==1 and table.sent[0].action=="hu", "legal hu must submit")
	packet.discards[0].claimed = true
	await _reject(table, packet, ["hu"], "claimed discard cannot win twice")
	packet.discards[0].claimed = false
	packet.last_discard = {"id":61,"suit":"tong","rank":7}
	packet.discards[0].tile = packet.last_discard
	await _reject(table, packet, ["hu"], "same tenpai hand cannot win on a different tile")
	packet.phase = "turn"
	packet.turn = 0
	packet.hand.append({"id":66,"suit":"tong","rank":8})
	packet.drawn_tile_id = 66
	packet.options = [{"type":"play"},{"type":"hu"}]
	await _push(table, packet)
	_check(table._response_buttons.hu.visible, "legal self draw must remain available")
	packet.erase("drawn_tile_id")
	await _reject(table, packet, ["hu"], "no self draw after pong")
	print("INVALID_CLAIM_SMOKE_OK" if not failed else "INVALID_CLAIM_SMOKE_FAILED")
	table.queue_free()
	await process_frame
	quit(1 if failed else 0)
