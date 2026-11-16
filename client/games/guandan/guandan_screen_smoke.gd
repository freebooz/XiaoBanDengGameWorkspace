extends SceneTree
## Validate the actual four-seat screen, duplicate cards, picking and quality levels.

class RenderFixture:
	extends "res://modules/games/guandan/guandan_3d_screen.gd"
	func _actions_ready() -> bool:
		return true

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var script = load("res://modules/games/guandan/guandan_3d_screen.gd")
	if script == null:
		quit(1)
		return
	var screen = RenderFixture.new()
	screen.training_mode = true
	screen.match_context = {"room_id":"训练", "account_id":"smoke", "seat_index":0}
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.set_process(false)
	await process_frame
	screen._layout_ui()
	var hand: Array = []
	for id in [0,54,1,55,6,8,12,16,20,24,28,32,36,40,44,48,49,50,51,52,53,102,103,104,105,106,107]:
		var face: int = id % 54
		hand.append({"id":id,"rank":int(face/4)+3 if face<52 else face-36,"suit":["spade","heart","club","diamond"][face%4] if face<52 else "joker"})
	screen._state = {"room_id":"训练", "status":"playing", "phase":"play", "turn":0, "your_seat":0,
		"players":["我","电脑一","我的搭档","电脑二"], "hand_counts":[27,27,27,27], "hand":hand,
		"level_rank":2,"team_levels":[2,2],"round":1,"has_last_play":false}
	screen._render()
	if screen._hand_nodes.size()!=27 or screen.seat_count!=4 or screen.game_protocol!="guandan" or not screen._viewport.own_world_3d:
		push_error("Incorrect Guandan screen state")
		quit(2)
		return
	var first = screen._hand_nodes[0].find_child("CardFace",true,false)
	var duplicate = screen._hand_nodes[1].find_child("CardFace",true,false)
	if first.mesh != duplicate.mesh or first.material_override != duplicate.material_override:
		push_error("Duplicate faces must share mesh and material")
		quit(3)
		return
	for quality in range(3):
		screen._set_quality(quality)
		if screen._viewport.size != screen.QUALITY_SIZES[quality]:
			quit(4)
			return
	screen._set_quality(1)
	await process_frame
	if screen._board_view.size.x <= screen._board_view.size.y or absf(screen._board_view.size.x / screen._board_view.size.y - float(screen._viewport.size.x) / screen._viewport.size.y) > 0.001:
		push_error("Guandan table must retain its landscape render aspect")
		quit(8)
		return
	var point: Vector2 = screen._camera.unproject_position(screen._hand_nodes[0].global_position)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = point / Vector2(screen._viewport.size) * screen._board_view.size
	screen._on_board_input(click)
	if not screen._selected.has(0) or screen._selected.has(54):
		push_error("Duplicate card instances must be selectable independently")
		quit(5)
		return
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.index = 0
	touch.position = screen._camera.unproject_position(screen._hand_nodes[26].global_position) / Vector2(screen._viewport.size) * screen._board_view.size
	screen._on_board_input(touch)
	if not screen._selected.has(107):
		push_error("Second-row touch selection failed")
		quit(7)
		return
	screen._clear_selection()
	# Dispatch through the real GUI path: a touch also generates an emulated mouse.
	var dispatched := InputEventScreenTouch.new()
	dispatched.index = 1
	dispatched.pressed = true
	dispatched.position = screen._camera.unproject_position(screen._hand_nodes[0].global_position) / Vector2(screen._viewport.size) * screen._board_view.size + screen._board_view.global_position
	Input.parse_input_event(dispatched)
	await process_frame
	if screen._selected.size() != 1 or not screen._selected.has(0):
		push_error("Real GUI touch must toggle a card exactly once")
		quit(10)
		return
	dispatched.pressed = false
	Input.parse_input_event(dispatched)
	await process_frame
	screen._clear_selection()
	for action in screen._action_layer.get_children():
		if action is Button and not Rect2(Vector2.ZERO, screen.size).encloses(action.get_global_rect()):
			push_error("Guandan action extends outside the landscape screen")
			quit(9)
			return
	for frame in range(24): await process_frame
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screen-out="):
			if root.get_texture().get_image().save_png(arg.trim_prefix("--screen-out=")) != OK:
				quit(6)
				return
	print("GUANDAN_3D_SMOKE_OK hand=27 unique_ids=27 shared_duplicate_mesh_material=true mouse=true touch=true gui_touch_once=true quality=3 landscape=true aspect=true actions_visible=true")
	quit()
