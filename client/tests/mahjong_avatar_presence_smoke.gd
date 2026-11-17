extends SceneTree
## Avatar color follows presence events. No separate green marker remains.

class Fixture:
	extends "res://modules/games/mahjong/guiyang/guiyang_3d_screen.gd"
	func _connect_socket() -> void: pass
	func _transport_open() -> bool: return true
	func _layout_coach() -> void: pass
	func _load_quality() -> void:
		super._load_quality()
		_music_enabled = false
		_sound_enabled = false

var _failures: Array[String] = []
var _epoch := 0
var _output := ""

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
		push_error(message)

func _packet(viewer := 0, turn := 0, phase := "turn") -> Dictionary:
	_epoch += 1
	var hand: Array = []
	for index in range(14 if viewer == turn else 13):
		hand.append({"id":index+1,"suit":["wan","tong","tiao"][index%3],"rank":index%9+1})
	return {"type":"mahjong_state","room_id":"2468","match_id":"avatar-presence","epoch":_epoch,
		"your_seat":viewer,"turn":turn,"dealer":2,"status":"playing","phase":phase,
		"players":["a","b","c","d"],"player_names":["村口阿牛","稻香大叔","乡村老张","板凳阿梅"],
		"connected_seats":[true,false,true,false],"occupied_seats":[true,true,true,true],
		"egg_counts":[0,100,9999,12345678],"hand":hand,"hand_counts":[13,13,13,13],
		"melds":[[],[],[],[]],"discards":[],"remaining":46,
		"options":[{"type":"play"}] if viewer == turn and phase == "turn" else [],
		"rule_set_id":"guiyang","rule_version":"3.0.0","round_limit":8,"completed_rounds":2,
		"server_now_ms":1000,"action_deadline_ms":16000}

func _verify(board, connected: Array) -> void:
	_check(board.find_child("MahjongTurnIndicator",true,false) == null, "Turn dot is removed, not merely hidden")
	_check(board.find_child("MahjongPresenceIndicator",true,false) == null, "Online dot is removed, not merely hidden")
	for seat in range(4):
		var panel: Control = board._seat_panels[board._relative_seat(seat)]
		var avatar := panel.find_child("MahjongSquarePortrait",true,false) as TextureRect
		_check(avatar != null and avatar.is_visible_in_tree(), "Every player retains the real portrait")
		if avatar == null: continue
		_check(avatar.material is ShaderMaterial, "Portrait applies the presence material")
		if avatar.material is ShaderMaterial:
			_check(avatar.material.get_shader_parameter("online") == connected[seat], "Seat %d color reflects connectivity, independent of the turn" % seat)
		_check(avatar.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Portrait does not steal pointer input")
		var balance := panel.get_node("MahjongSeatEggs") as Label
		var egg := panel.get_node("MahjongSeatEggIcon") as TextureRect
		_check(egg.get_global_rect().position.x >= balance.get_global_rect().end.x and panel.get_global_rect().encloses(egg.get_global_rect()), "Egg icon follows the amount without crossing the card boundary")

func _run() -> void:
	Engine.max_fps = 0
	if DisplayServer.get_name() != "headless": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1440,810)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): _output = arg.trim_prefix("--output=")
	var board := Fixture.new()
	board.preserve_window_size = true
	board.match_context = {"room_id":"2468","seat_index":0,"display_name":"村口阿牛"}
	root.add_child(board)
	await process_frame
	var joined := {"type":"mahjong_joined","room_id":"2468","match_id":"avatar-presence","your_seat":0}
	board._handle_packet(JSON.stringify(joined))
	for viewer in range(4):
		for turn in range(4):
			board._handle_packet(JSON.stringify(_packet(viewer,turn)))
			_verify(board,[true,false,true,false])
	for phase in ["reaction","dingque","finished"]:
		board._handle_packet(JSON.stringify(_packet(0,1,phase)))
		_verify(board,[true,false,true,false])
	var packet := _packet(0,2)
	packet.connected_seats = [true,true,true,true]
	board._handle_packet(JSON.stringify(packet))
	_verify(board,[true,true,true,true])
	board._board_lost("测试断线")
	_verify(board,[false,false,false,false])
	board._layout_ui()
	_verify(board,[false,false,false,false])
	board._handle_packet(JSON.stringify(joined))
	_verify(board,[false,false,false,false])
	packet = _packet(0,2)
	board._handle_packet(JSON.stringify(packet))
	_verify(board,[true,false,true,false])
	packet.epoch -= 1
	packet.connected_seats = [false,true,false,true]
	board._handle_packet(JSON.stringify(packet))
	_verify(board,[true,false,true,false])
	board.match_context.spectating = true
	board._handle_packet(JSON.stringify({"type":"mahjong_watch_joined","room_id":"2468"}))
	_verify(board,[false,false,false,false])
	packet = _packet(1,3)
	packet.type = "mahjong_watch_state"
	packet.watch_seat = 1
	board._handle_packet(JSON.stringify(packet))
	_verify(board,[true,false,true,false])
	board.match_context.spectating = false
	board._handle_packet(JSON.stringify(joined))
	for dimensions in [Vector2i(1280,720),Vector2i(1600,720),Vector2i(1280,800),Vector2i(1200,900)]:
		root.size = dimensions
		for frame in range(4): await process_frame
		board._handle_packet(JSON.stringify(_packet(0,0)))
		await process_frame
		_verify(board,[true,false,true,false])
		if not _output.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			_check(root.get_texture().get_image().save_png(_output.path_join("presence_%dx%d.png"%[dimensions.x,dimensions.y])) == OK,"Native presence screenshot saved")
	print("MAHJONG_AVATAR_PRESENCE_" + ("OK" if _failures.is_empty() else "FAILED") + " cases=16 ratios=4 no_dots=true online_color=true offline_gray=true event_snapshot=true reconnect=true spectator=true failures=" + str(_failures.size()))
	board.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)
