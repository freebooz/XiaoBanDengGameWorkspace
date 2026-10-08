extends SceneTree
## Run in the generated Landlord project to validate imported 3D card/table nodes.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var script = load("res://modules/games/landlord/landlord_3d_screen.gd")
	if script == null:
		push_error("Landlord screen failed to load")
		quit(1)
		return
	var screen = script.new()
	screen.training_mode = true
	screen.match_context = {"room_id":"训练", "account_id":"smoke", "seat_index":0}
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.set_process(false)
	await process_frame
	screen._layout_ui()
	var hand: Array = []
	for id in range(20):
		hand.append({"id":id,"rank":int(id/4)+3,"suit":["spade","heart","club","diamond"][id%4]})
	screen._state = {"room_id":"训练", "status":"playing", "phase":"play", "turn":0, "your_seat":0,
		"players":["我","电脑一","电脑二"], "hand_counts":[20,17,17], "hand":hand,
		"bottom":[], "landlord":0, "highest_bid":1, "has_last_play":false, "multiplier":1}
	screen._render()
	var model = screen._cards_root.get_child(0)
	var card = screen._card_model({"id":0,"rank":3,"suit":"spade"}, Vector3.ZERO)
	if model == null or card.find_child("CardFace", true, false) == null or card.find_child("CardBack", true, false) == null:
		push_error("Imported 3D card face/back missing")
		quit(2)
		return
	if screen._hand_nodes.size() != 20:
		push_error("Hand is not modeled in 3D")
		quit(3)
		return
	if screen._board_view.size.x <= screen._board_view.size.y or absf(screen._board_view.size.x / screen._board_view.size.y - float(screen._viewport.size.x) / screen._viewport.size.y) > 0.001:
		push_error("Poker table must retain its landscape render aspect")
		quit(6)
		return
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = screen._camera.unproject_position(screen._hand_nodes[0].global_position) / Vector2(screen._viewport.size) * screen._board_view.size
	screen._on_board_input(click)
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = screen._camera.unproject_position(screen._hand_nodes[19].global_position) / Vector2(screen._viewport.size) * screen._board_view.size
	screen._on_board_input(touch)
	if not screen._selected.has(0) or not screen._selected.has(19):
		push_error("Landscape poker hand must support mouse and touch selection")
		quit(7)
		return
	screen._clear_selection()
	for action in screen._action_layer.get_children():
		if action is Button and not Rect2(Vector2.ZERO, screen.size).encloses(action.get_global_rect()):
			push_error("Poker action extends outside the landscape screen")
			quit(8)
			return
	print("LANDLORD_3D_SMOKE_OK cards=", screen._hand_nodes.size(), " landscape=true aspect=true mouse=true touch=true actions_visible=true")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot-out="):
			for frame in range(24):
				await process_frame
			var image: Image = screen._viewport.get_texture().get_image()
			var destination := arg.trim_prefix("--screenshot-out=")
			if image.save_png(destination) != OK:
				push_error("Unable to save Landlord screenshot")
				quit(4)
				return
			print("LANDLORD_SCREENSHOT=", destination)
		if arg.begins_with("--screen-out="):
			for frame in range(24):
				await process_frame
			var image: Image = root.get_texture().get_image()
			var destination := arg.trim_prefix("--screen-out=")
			if image.save_png(destination) != OK:
				push_error("Unable to save full Landlord screen")
				quit(5)
				return
			print("LANDLORD_FULL_SCREENSHOT=", destination)
	quit()
