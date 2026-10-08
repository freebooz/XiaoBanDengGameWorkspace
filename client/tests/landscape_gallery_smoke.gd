extends SceneTree
## Render each real game screen at landscape device sizes and check actionable bounds.

func _initialize() -> void:
	call_deferred("_run")

func _card(id: int) -> Dictionary:
	var face := id%54
	return {"id":id,"rank":int(face/4)+3 if face<52 else face-36,"suit":["spade","heart","club","diamond"][face%4] if face<52 else "joker"}

func _run() -> void:
	var product = JSON.parse_string(FileAccess.get_file_as_string("res://product.json"))
	var game_id := str(product.game_id)
	var path := ""
	match game_id:
		"chinese_chess": path = "res://modules/games/chinese_chess/chinese_chess_3d_screen.gd"
		"mahjong": path = "res://modules/games/mahjong/guiyang/guiyang_3d_screen.gd"
		"landlord": path = "res://modules/games/landlord/landlord_3d_screen.gd"
		"guandan": path = "res://modules/games/guandan/guandan_3d_screen.gd"
	var script = load(path)
	if script == null or not script.can_instantiate():
		quit(1)
		return
	var screen = script.new()
	screen.training_mode = true
	screen.match_context = {"room_id":"训练","account_id":"landscape-demo","display_name":"江湖棋客","opponent_display_name":"墨韵清风","seat_index":0}
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	await process_frame
	screen.set_process(false)
	if game_id in ["landlord","guandan"]:
		var hand: Array = []
		var ids: Array = range(20) if game_id=="landlord" else [0,54,1,55,4,5,8,9,12,16,20,24,28,32,36,40,44,48,49,50,51,52,53,102,103,106,107]
		for id in ids: hand.append(_card(id))
		screen._state = {"room_id":"训练","status":"playing","phase":"play","turn":0,"your_seat":0,
			"players":["江湖棋客","清风明月","墨韵知音","云水闲客"] if game_id=="guandan" else ["江湖棋客","清风明月","墨韵知音"],
			"hand":hand,"hand_counts":[27,25,27,27] if game_id=="guandan" else [20,17,17],
			"level_rank":5,"team_levels":[5,3],"round":2,"landlord":0,"bottom":[_card(36),_card(40),_card(50)],"highest_bid":3,"multiplier":2,
			"has_last_play":game_id=="guandan","last_play":{"seat":1,"pattern":{"kind":"pair","main":10,"length":2},"cards":[_card(30),_card(84)]}}
		screen._render()
		screen._selected[0] = true
		screen._update_selected()
	await process_frame
	var bounds := Rect2(Vector2.ZERO,screen.size)
	if screen.size.x<=screen.size.y:
		push_error("Battle is still portrait: "+str(screen.size))
		quit(2)
		return
	for button in screen.find_children("*","Button",true,false):
		if button.is_visible_in_tree() and not bounds.encloses(button.get_global_rect().grow(-1)):
			push_error("Battle button is clipped: "+str(button.name)+" "+str(button.get_global_rect()))
			quit(3)
			return
	var board: TextureRect = screen._board_view
	var viewport: SubViewport = screen._viewport if game_id in ["landlord","guandan"] else screen._board_viewport
	if absf(board.size.x/board.size.y-float(viewport.size.x)/viewport.size.y)>0.01:
		push_error("3D viewport is stretched")
		quit(4)
		return
	for frame in range(24): await process_frame
	if DisplayServer.get_name()!="headless":
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--screen-out="):
				if root.get_texture().get_image().save_png(arg.trim_prefix("--screen-out="))!=OK:
					quit(5)
					return
	print("LANDSCAPE_GALLERY_OK game=",game_id," logical=",screen.size," window=",root.size," buttons_visible=true aspect_correct=true")
	quit()
