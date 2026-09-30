extends SceneTree
## Verify real imported Blender assets and board picking from both player views.

const OUT := "E:/work/2026/XiaoBanDengGameWorkspace/SourceAssets/Blender/ChineseChess/"

func _initialize() -> void:
	call_deferred("run_review")

func run_review() -> void:
	var screen: Control = load("res://modules/games/chinese_chess/chinese_chess_3d_screen.gd").new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	screen._socket.close()
	screen.set_process(false)
	screen._apply_render_quality(2, false)
	await create_timer(2.0).timeout
	assert(screen._camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "Requested game view must use perspective projection")
	assert(screen._grid_registration_loaded, "Imported model must supply its unwarped grid registration")
	assert(screen._blender_piece_templates.size() == 14, "All 14 Blender masters must load")
	assert(screen._piece_root.get_child_count() == 32, "Opening must contain 32 imported pieces")
	assert(screen.find_child("BlenderRedSandalwoodBoard", true, false) != null, "Latest textured flat board must load")
	assert(verify_board_lacquer(screen.find_child("BlenderRedSandalwoodBoard", true, false)) == 2)
	var lacquer_surfaces := verify_lacquer(screen.find_child("BlenderPieceLibrary", true, false))
	assert(lacquer_surfaces == 28, "Both wood surfaces of all 14 masters must have lacquer")
	for piece in screen._piece_root.get_children():
		assert(piece.has_meta("blender_piece"), "Procedural fallback must not be used")
		assert(piece.is_visible_in_tree(), "Imported piece must be visible")
	var checked := 0
	for side in ["red", "black"]:
		screen._your_color = side
		screen._apply_player_view()
		await create_timer(0.5).timeout
		var corners := []
		for z in [-.226, .226]:
			for x in [-.206, .206]:
				var point: Vector2 = screen._camera.unproject_position(Vector3(x * screen.BLENDER_MODEL_SCALE, screen.BOARD_Y, z * screen.BLENDER_MODEL_SCALE))
				print("CHESS_CORNER side=", side, " point=", point, " viewport=", screen._board_viewport.size)
				assert(Rect2(Vector2.ZERO, Vector2(screen._board_viewport.size)).has_point(point), "All four board corners must remain visible")
				corners.append(point)
		var widths := [corners[0].distance_to(corners[1]), corners[2].distance_to(corners[3])]
		var perspective_ratio: float = maxf(widths[0], widths[1]) / minf(widths[0], widths[1])
		assert(perspective_ratio > 1.04 and perspective_ratio < 1.16, "Duel design uses a shallow, visible perspective")
		assert(is_equal_approx(screen._camera.fov, 35.0))
		print("CHESS_REFERENCE_CAMERA side=", side, " projection=perspective fov=", screen._camera.fov, " front_rear_ratio=", perspective_ratio)
		for y in range(10):
			for x in range(9):
				var pos := Vector2i(x, y)
				var world: Vector3 = screen._board_to_world(pos)
				world.y = screen.BOARD_Y
				var viewport_pos: Vector2 = screen._camera.unproject_position(world)
				var local_pos: Vector2 = viewport_pos * screen._board_view.size / Vector2(screen._board_viewport.size)
				assert(screen._screen_to_board(local_pos) == pos, "Picking must match all engraved intersections")
				checked += 1
		await process_frame
		await RenderingServer.frame_post_draw
		var temporary_path := OUT + "game_render_" + str(Time.get_ticks_usec()) + ".png"
		var saved: Error = root.get_texture().get_image().save_png(temporary_path)
		assert(saved == OK, "Screenshot must save")
		assert(DirAccess.rename_absolute(temporary_path, OUT + "XBD_Game_" + side + "_preview.png") == OK, "Screenshot must replace atomically")
	print("BLENDER_GAME_ASSETS_PASS masters=14 opening=32 board=loaded lacquer_surfaces=", lacquer_surfaces, " intersection_picks=", checked)
	screen._on_action_pressed("菜单")
	await process_frame
	await RenderingServer.frame_post_draw
	var menu_path := OUT + "quality_menu_" + str(Time.get_ticks_usec()) + ".png"
	assert(root.get_texture().get_image().save_png(menu_path) == OK)
	assert(DirAccess.rename_absolute(menu_path, OUT + "XBD_Game_quality_menu.png") == OK)
	screen.queue_free()
	await process_frame
	quit()

func verify_lacquer(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D:
		for index in range(node.mesh.get_surface_count()):
			var mat: Material = node.get_active_material(index)
			if mat is StandardMaterial3D and mat.albedo_texture != null:
				assert(mat.clearcoat_enabled and mat.clearcoat >= 0.54 and mat.clearcoat_roughness <= 0.13)
				assert(mat.normal_enabled and mat.normal_texture != null and mat.normal_scale <= 0.13)
				count += 1
	for child in node.get_children():
		count += verify_lacquer(child)
	return count

func verify_board_lacquer(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D:
		for index in range(node.mesh.get_surface_count()):
			var mat: Material = node.get_active_material(index)
			if mat is StandardMaterial3D and mat.albedo_texture != null:
				assert(mat.clearcoat_enabled and mat.clearcoat >= 0.19 and mat.clearcoat <= 0.21)
				assert(mat.clearcoat_roughness >= 0.23 and mat.clearcoat_roughness <= 0.25)
				count += 1
	for child in node.get_children():
		count += verify_board_lacquer(child)
	return count
