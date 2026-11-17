extends SceneTree

class Fixture:
	extends "res://modules/games/mahjong/guiyang/guiyang_3d_screen.gd"
	var commands: Array[Dictionary] = []
	func _connect_socket() -> void: pass
	func _actions_ready() -> bool: return true
	func _send(packet: Dictionary) -> void:
		_last_send_error = OK
		if str(packet.get("type","")) == "mahjong_action": commands.append(packet.duplicate(true))

var _failed := false
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool, message: String) -> void:
	if not ok:
		_failed = true
		push_error(message)

func _tap(screen, index: int) -> void:
	var event := InputEventScreenTouch.new()
	event.pressed = true
	event.position = screen._board_view.get_viewport_transform()*screen._board_view.get_global_transform()*screen._projected_tile_rect(screen._hand_models[index]).get_center()
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func _emulated_mouse(screen, index: int) -> void:
	var event := InputEventMouseButton.new()
	event.device = -1
	event.pressed = true
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = screen._projected_tile_rect(screen._hand_models[index]).get_center()
	screen._on_board_input(event)

func _run() -> void:
	Engine.max_fps=0
	var screen := Fixture.new()
	screen.match_context={"room_id":"tap-fixture","seat_index":0}
	root.add_child(screen)
	await process_frame
	var hand: Array = []
	for i in 14: hand.append({"id":i+1,"suit":["wan","tong","tiao"][i%3],"rank":i%9+1})
	screen._state={"room_id":"tap-fixture","match_id":"double-tap","epoch":1,"your_seat":0,"turn":0,"status":"playing","phase":"turn","hand":hand,"hand_counts":[14,13,13,13],"melds":[[],[],[],[]],"discards":[],"options":[{"type":"play"}],"remaining":55}
	screen._render()
	for frame in 3: await process_frame
	var emulate := Input.emulate_mouse_from_touch
	Input.emulate_mouse_from_touch=true
	await _tap(screen,4)
	_check(screen._selected_id==5 and screen.commands.is_empty(),"First touch only selects and raises the hand")
	_emulated_mouse(screen,4)
	_check(screen.commands.is_empty(),"Emulated mouse after first touch cannot submit")
	await _tap(screen,4)
	_check(screen.commands.size()==1 and screen.commands[0].action=="play" and screen.commands[0].tile_id==5,"Second touch must submit the selected tile exactly once")
	_check(screen._pending_action and screen._selected_id==5,"Pending acknowledgement must preserve selected tile")
	_emulated_mouse(screen,4)
	await _tap(screen,4)
	_check(screen.commands.size()==1,"Pending command and emulated mouse must not duplicate play")
	for phase_case in ["reaction","other-turn","restricted-tile"]:
		screen._clear_pending_command()
		screen.commands.clear()
		screen._state.phase="reaction" if phase_case=="reaction" else "turn"
		screen._state.turn=1 if phase_case=="other-turn" else 0
		screen._state.options=[{"type":"peng"},{"type":"pass"}] if phase_case=="reaction" else [{"type":"play","tile_id":6}] if phase_case=="restricted-tile" else [{"type":"play"}]
		screen._render()
		for frame in 2: await process_frame
		await _tap(screen,4)
		_check(screen.commands.is_empty() and screen._selected_id==5,"Illegal %s second touch must not send or deselect"%phase_case)
	screen._clear_pending_command()
	screen.commands.clear()
	await _tap(screen,5)
	_check(screen._selected_id==6 and screen.commands.is_empty(),"Choosing a different tile must only select it")
	await _tap(screen,5)
	_check(screen.commands.size()==1 and screen.commands[0].tile_id==6,"Server-authorized tile must submit on its second touch")
	await _check_native_resize(screen)
	Input.emulate_mouse_from_touch=emulate
	screen.queue_free()
	await process_frame
	print("MAHJONG_DOUBLE_TAP_OK first_select=true second_play_once=true emulated_mouse=false pending_repeat=false illegal_phase=false restricted_tile=true" if not _failed else "MAHJONG_DOUBLE_TAP_FAILED")
	quit(1 if _failed else 0)


func _check_native_resize(screen: Fixture) -> void:
	var capture := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--viewport-capture="): capture = arg.trim_prefix("--viewport-capture=")
	screen._set_quality(0)
	for dimensions in [Vector2i(1280,720), Vector2i(1920,864), Vector2i(1280,800), Vector2i(1200,900), Vector2i(2560,1440)]:
		# Exercise a scaled canvas as well as the ordinary full-resolution product.
		root.content_scale_size = Vector2i(1440,810) if dimensions.x == 2560 else Vector2i.ZERO
		root.size = dimensions
		for frame in 3: await process_frame
		var canvas_size := root.get_visible_rect().size
		var output := screen._board_view.size * Vector2(root.size) / canvas_size
		var render := Vector2(screen._board_viewport.size)
		_check((output - render).abs().x <= 1.0 and (output - render).abs().y <= 1.0,
			"3D board must redraw at actual output pixels under resize %s (output %s, rendered %s)" % [dimensions, output, render])
		_check(screen._board_viewport.scaling_3d_scale == 1.0, "3D resolution scale must remain native")
		screen._clear_pending_command()
		screen.commands.clear()
		screen._select_tile(0)
		await _tap(screen,5)
		_check(screen._selected_id == 6 and screen.commands.is_empty(), "First native touch must pick the projected tile at %s" % [dimensions])
		await _tap(screen,5)
		_check(screen.commands.size() == 1 and screen.commands[0].tile_id == 6,
			"Second native touch must play the same physical tile at %s" % [dimensions])
		if not capture.is_empty() and dimensions.x == 2560 and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			_check(root.get_texture().get_image().save_png(capture) == OK, "Native board screenshot must save")
