extends SceneTree
## Verify real imported Blender assets and board picking from both player views.

const OUT := "E:/work/2026/XiaoBanDengGameWorkspace/SourceAssets/Blender/ChineseChess/"

func _initialize() -> void:
	call_deferred("run_review")

func run_review() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(2.0).timeout
	var screen: Control = main.get_child(0)
	screen.set_process(false)
	screen._socket.close()
	assert(screen._blender_piece_templates.size() == 14, "All 14 Blender masters must load")
	assert(screen._piece_root.get_child_count() == 32, "Opening must contain 32 imported pieces")
	assert(screen.find_child("BlenderBambooBoard", true, false) != null, "Blender bamboo board must load")
	for piece in screen._piece_root.get_children():
		assert(piece.has_meta("blender_piece"), "Procedural fallback must not be used")
		assert(piece.is_visible_in_tree(), "Imported piece must be visible")
	var checked := 0
	for side in ["red", "black"]:
		screen._your_color = side
		screen._apply_player_view()
		await create_timer(0.5).timeout
		for y in range(10):
			for x in range(9):
				var pos := Vector2i(x, y)
				var world: Vector3 = screen._board_to_world(pos)
				world.y = screen.BOARD_Y
				var viewport_pos: Vector2 = screen._camera.unproject_position(world)
				var local_pos: Vector2 = viewport_pos * screen._board_view.size / Vector2(screen.BOARD_VIEW_SIZE)
				assert(screen._screen_to_board(local_pos) == pos, "Picking must match all engraved intersections")
				checked += 1
		await process_frame
		await RenderingServer.frame_post_draw
		var saved: Error = root.get_texture().get_image().save_png(OUT + "XBD_Game_" + side + "_preview.png")
		assert(saved == OK, "Screenshot must save")
	print("BLENDER_GAME_ASSETS_PASS masters=14 opening=32 board=loaded intersection_picks=", checked)
	quit()
