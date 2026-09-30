extends SceneTree
## Real 3D duel screen: portrait reference layout and usable action row.
const SCREEN = preload("res://modules/games/chinese_chess/chinese_chess_3d_screen.gd")
const OUT := "E:/work/2026/XiaoBanDengGameWorkspace/SourceAssets/Blender/ChineseChess/"

func _initialize() -> void:
	call_deferred("run_review")

func run_review() -> void:
	var screen = SCREEN.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	screen._socket.close()
	screen.set_process(false)
	await create_timer(.4).timeout
	assert(screen._brand_stool != null and screen._brand_stool.texture != null)
	assert(screen._music_quick_button != null and screen._settings_quick_button != null)
	for canvas in [Vector2(450,800), Vector2(720,1280)]:
		screen.size = canvas
		screen._layout_hud()
		var visible_board_top := INF
		for x in [-.206, .206]:
			for z in [-.226, .226]:
				var projected: Vector2 = screen._camera.unproject_position(Vector3(x * screen.BLENDER_MODEL_SCALE, screen.BOARD_Y, z * screen.BLENDER_MODEL_SCALE))
				visible_board_top = minf(visible_board_top, screen._board_frame.position.y + projected.y * screen._board_frame.size.y / float(screen._board_viewport.size.y))
		assert(screen._right_card.position.y + screen._right_card.size.y <= visible_board_top + 5.0)
		assert(screen._board_frame.position.y + screen._board_frame.size.y <= screen._left_card.position.y)
		assert(screen._left_card.position.y + screen._left_card.size.y <= screen._action_buttons[0].position.y)
		assert(screen._board_frame.size.x >= canvas.x * .86)
		for button in screen._action_buttons:
			assert(is_equal_approx(button.position.y, screen._action_buttons[0].position.y))
			assert(button.position.y + button.size.y <= canvas.y)
		assert(screen._music_quick_button.position.y + screen._music_quick_button.size.y <= screen._right_card.position.y)
		assert(screen._settings_quick_button.position.y + screen._settings_quick_button.size.y <= screen._right_card.position.y)
		await process_frame
		await RenderingServer.frame_post_draw
		var file := OUT + "XBD_Game_duel_" + str(int(canvas.x)) + "x" + str(int(canvas.y)) + ".png"
		assert(root.get_texture().get_image().save_png(file) == OK)
		print("DUEL_LAYOUT_SMOKE layout=", canvas, " board=", screen._board_frame.size, " actions=6")
	screen._your_color = "black"
	screen._apply_player_view()
	screen._update_player_panels()
	assert(screen._left_card.get_node("SideBadge/SideBadgeText").text == "黑方")
	assert(screen._right_card.get_node("SideBadge/SideBadgeText").text == "红方")
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUT + "XBD_Game_duel_black_720x1280.png") == OK)
	screen.queue_free()
	await process_frame
	print("DUEL_LAYOUT_SMOKE_PASS portraits=2 black_perspective=1")
	quit()
