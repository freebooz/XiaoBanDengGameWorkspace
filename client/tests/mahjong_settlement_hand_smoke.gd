extends SceneTree

const STRIP_PATH := "res://modules/games/mahjong/guiyang/mahjong_settlement_hand.gd"
const MATERIALS := preload("res://modules/games/mahjong/guiyang/real_tile_materials.gd")
const TABLE_THEME := preload("res://modules/games/mahjong/guiyang/mahjong_table_theme.gd")

var failed := false


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func _settle() -> void:
	for frame in 4:
		await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func _bounds(mesh: MeshInstance3D, camera: Camera3D) -> Rect2:
	var box := mesh.get_aabb()
	var rect := Rect2(camera.unproject_position(mesh.to_global(box.get_endpoint(0))), Vector2.ZERO)
	for corner in range(1, 8):
		rect = rect.expand(camera.unproject_position(mesh.to_global(box.get_endpoint(corner))))
	return rect


func _check_native(strip: Control, viewport: SubViewport) -> void:
	var transform := strip.get_viewport_transform() * strip.get_global_transform()
	var pixels := Vector2i((strip.size * Vector2(transform.x.length(), transform.y.length())).ceil())
	_check(viewport.size == pixels and is_equal_approx(viewport.scaling_3d_scale, 1.0), "Settlement 3D must match its physical display area")
	var surface := viewport.get_parent() as SubViewportContainer
	var display := surface.get_viewport_transform() * surface.get_global_transform()
	_check(display.get_scale().is_equal_approx(Vector2.ONE) and not surface.stretch, "Each displayed texel must occupy one real window pixel")
	_check(viewport.render_target_update_mode in [SubViewport.UPDATE_ONCE, SubViewport.UPDATE_DISABLED], "A resting hand must stop redrawing")
	if DisplayServer.get_name() != "headless":
		_check(viewport.get_texture().get_image().get_size() == pixels, "The GPU readback must match the physical display area")


func _run() -> void:
	Engine.max_fps = 0
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_check(DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED, "Native rendering must run with VSync disabled")
	_check(Engine.max_fps == 0, "Settlement verification must run uncapped")
	if not ResourceLoader.exists(STRIP_PATH):
		_check(false, "Settlement needs a native 3D hand strip")
		quit(1)
		return
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(900, 380)
	var tiles: Array = []
	for i in 14:
		tiles.append({"suit": ["wan", "tong", "tiao"][i % 3], "rank": i % 9 + 1, "group": int(i >= 11)})
	tiles.back().concealed = true
	var mats := MATERIALS.new()
	var table_resin := mats.body()
	var table_color := Color("#3569ab")
	table_resin.set_shader_parameter("blue_color", table_color)
	var strip = load(STRIP_PATH).new()
	strip.size = Vector2(550, 86)
	strip.setup(tiles, mats)
	root.add_child(strip)
	await _settle()
	var viewport := strip.find_child("Native3DViewport", true, false) as SubViewport
	if viewport == null:
		_check(false, "Settlement must use the native-pixel 3D viewport")
		quit(1)
		return
	_check_native(strip, viewport)
	var bodies := viewport.find_children("TileBody", "MeshInstance3D", true, false)
	var faces := viewport.find_children("TileFace", "MeshInstance3D", true, false)
	_check(bodies.size() == 14 and faces.size() == 14, "Every reported tile needs its real model")
	if bodies.size() == 14 and faces.size() == 14:
		var camera := viewport.get_camera_3d()
		var first := _bounds(bodies[0], camera)
		var last := _bounds(bodies[13], camera)
		var gap := _bounds(bodies[11], camera).position.x - _bounds(bodies[10], camera).end.x
		var normal_gap := _bounds(bodies[1], camera).position.x - first.end.x
		_check(first.position.x >= -0.5 and last.end.x <= viewport.size.x + 0.5 and last.end.x - first.position.x > viewport.size.x * 0.9, "Fourteen tiles must fit across the row")
		_check(first.position.y >= -0.5 and first.end.y <= viewport.size.y + 0.5, "The entire tile height must be visible")
		_check(gap > normal_gap + 0.5, "A meld boundary must be distinguishable")
		var live_color: Variant = table_resin.get_shader_parameter("blue_color")
		_check(live_color == table_color, "Settlement changed the live table's color from %s to %s" % [table_color, live_color])
		_check((faces[0] as MeshInstance3D).material_override in [mats.face(tiles[0]), mats.tabletop_face(tiles[0])], "The first tile must show its actual rank and suit")
		_check((faces[13] as MeshInstance3D).material_override == mats.blank_face(), "A masked tile must never bind its rank and suit")
		if DisplayServer.get_name() != "headless":
			var rendered := viewport.get_texture().get_image()
			var back := rendered.get_pixelv(Vector2i(last.get_center()))
			_check(back.a > 0.9 and back.g > back.r and back.g > back.b, "The hidden tile must present its green back")
			var ivory := rendered.get_pixelv(Vector2i(first.position + first.size * Vector2(0.13, 0.35)))
			_check(ivory.r < 0.998 and ivory.r > ivory.b, "The ivory surface must retain its warm tone and highlight detail")
			var contact := rendered.get_pixelv(Vector2i(first.get_center().x, floori(first.end.y) + 2))
			_check(contact.a > 0.02 and contact.a < 0.9, "Contact shading must fade out beneath each tile")
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("--capture="):
					_check(rendered.save_png(arg.trim_prefix("--capture=")) == OK, "Save native settlement strip")
		tiles.pop_back()
		strip.setup(tiles, mats)
		await _settle()
		bodies = viewport.find_children("TileBody", "MeshInstance3D", true, false)
		_check(bodies.size() == 13 and absf(_bounds(bodies[0], camera).size.x - first.size.x) <= 1, "A thirteen-tile hand must keep the same legible tile size")
	strip.hide()
	strip.size = Vector2(270, 50)
	strip.scale = Vector2.ONE * 1.25
	strip.show()
	await _settle()
	for quality in 3:
		TABLE_THEME.configure_viewport(viewport, quality)
		strip.sync_native_size()
		await _settle()
		_check_native(strip, viewport)
	if not bodies.is_empty():
		var narrow_last := _bounds(bodies.back(), viewport.get_camera_3d())
		_check(narrow_last.end.x <= viewport.size.x + 0.5 and narrow_last.end.y <= viewport.size.y + 0.5, "The final tile must fit after the hand narrows")
	strip.setup([], mats)
	await _settle()
	_check(viewport.find_children("TileBody", "MeshInstance3D", true, false).is_empty(), "An empty hand must clear previous models")
	if DisplayServer.get_name() != "headless":
		_check(not viewport.get_texture().get_image().get_used_rect().has_area(), "An empty hand must clear the previous GPU frame")
	strip.queue_free()
	await process_frame
	print("MAHJONG_SETTLEMENT_HAND_FAILED" if failed else "MAHJONG_SETTLEMENT_HAND_OK")
	quit(int(failed))
