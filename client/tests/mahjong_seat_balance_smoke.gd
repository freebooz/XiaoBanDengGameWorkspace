extends SceneTree
## Wallet labels must paint actual digits, not merely hold a text property.

class Fixture:
	extends "res://modules/games/mahjong/guiyang/guiyang_3d_screen.gd"
	func _connect_socket() -> void: pass
	func _play_sound(_cue: String = "discard") -> void: pass
	func _play_callout(_cue: String, _tile: Dictionary = {}) -> void: pass

var _failed := false
var _output := ""

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failed = true
		push_error(message)

func _run() -> void:
	Engine.max_fps = 0
	if DisplayServer.get_name() != "headless": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): _output = arg.trim_prefix("--output=")
	var screen := Fixture.new()
	screen.match_context = {"room_id":"8614","seat_index":0}
	root.add_child(screen)
	await process_frame
	screen._handle_packet(JSON.stringify({"type":"mahjong_joined","room_id":"8614","match_id":"wallet-pixels","your_seat":0}))
	screen._handle_packet(JSON.stringify({"type":"mahjong_state","room_id":"8614","match_id":"wallet-pixels","epoch":2,"rule_set_id":"guiyang","rule_version":"2.0.0","status":"playing","phase":"turn","your_seat":0,"turn":0,"dealer":2,"players":["a","b","c","d"],"player_names":["田埂阿牛","河湾阿梅","稻香大叔","村口小张"],"egg_counts":[0,100,9999,12345678],"hand":[],"hand_counts":[0,13,13,13],"melds":[[],[],[],[]],"discards":[],"remaining":53,"options":[],"server_now_ms":1000,"action_deadline_ms":13000}))
	for frame in 6: await process_frame
	var frame_image: Image
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		frame_image = root.get_texture().get_image()
		if not _output.is_empty(): frame_image.save_png(_output.path_join("seat-balances.png"))
	var records: Array[Dictionary] = []
	var expected := ["0","100","9999","12345678"]
	for seat in 4:
		var panel: Control = screen._seat_panels[seat]
		var quantity := panel.get_node("MahjongSeatEggs") as Label
		var nickname := panel.get_node("MahjongSeatNickname") as Label
		var egg_icon := panel.get_node("MahjongSeatEggIcon") as TextureRect
		var font := quantity.get_theme_font("font")
		var font_size := quantity.get_theme_font_size("font_size")
		var measured := Vector2(font.get_string_size(quantity.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x,font.get_height(font_size))
		var rectangle := quantity.get_global_rect()
		_check(quantity.text == expected[seat] and quantity.is_visible_in_tree(),"Seat %d must bind its actual zero/nonzero wallet"%seat)
		_check(rectangle.size.x > 0 and rectangle.size.y > 0 and quantity.get_visible_line_count() >= 1,"Seat %d quantity must have at least one actually visible line"%seat)
		_check(rectangle.size.x >= measured.x and rectangle.size.y >= measured.y,"Seat %d font metrics must fit both dimensions (%s vs %s)"%[seat,measured,rectangle.size])
		_check(panel.get_global_rect().encloses(rectangle),"Seat %d quantity must remain within the card"%seat)
		_check(egg_icon.texture != null and egg_icon.is_visible_in_tree(), "Seat %d must display the egg currency icon" % seat)
		_check(egg_icon.get_global_rect().position.x >= rectangle.end.x and panel.get_global_rect().encloses(egg_icon.get_global_rect()), "Seat %d egg icon must trail the number and stay within the card" % seat)
		_check(egg_icon.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED and egg_icon.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Currency artwork stays proportional and does not block input")
		_check(nickname.get_visible_line_count() >= 1 and nickname.get_theme_font("font").get_height(nickname.get_theme_font_size("font_size")) <= nickname.size.y,"Seat %d nickname must remain readable inside its wood strip"%seat)
		_check(not nickname.get_global_rect().intersects(rectangle),"Seat %d nickname must not overlap the balance area"%seat)
		var painted := -1
		if frame_image != null:
			var scale := Vector2(frame_image.get_size()) / screen.size
			var pixel_rect := Rect2i(rectangle.position*scale,rectangle.size*scale).grow(-2)
			painted = 0
			for y in range(pixel_rect.position.y,pixel_rect.end.y):
				for x in range(pixel_rect.position.x,pixel_rect.end.x):
					var color := frame_image.get_pixel(x,y)
					if color.r > 0.25 and color.r > color.g*1.5 and color.g < 0.36 and color.b < 0.32: painted += 1
			_check(painted >= 12,"Seat %d has no readable red balance glyph pixels (count %d)"%[seat,painted])
		records.append({"seat":seat,"text":quantity.text,"font_size":font_size,"font_metrics":[measured.x,measured.y],"rect":[rectangle.position.x,rectangle.position.y,rectangle.size.x,rectangle.size.y],"visible_lines":quantity.get_visible_line_count(),"red_glyph_pixels":painted})
	if not _output.is_empty():
		var file := FileAccess.open(_output.path_join("seat-balances.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify({"passed":not _failed,"seats":records,"physical_window":DisplayServer.window_get_size(),"logical_viewport":screen.size},"\t"))
	print("SEAT_BALANCE_VISIBILITY="+str(not _failed)+" "+JSON.stringify(records))
	screen.queue_free()
	await process_frame
	quit(1 if _failed else 0)
