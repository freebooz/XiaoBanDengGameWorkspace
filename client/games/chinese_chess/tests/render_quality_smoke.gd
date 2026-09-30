extends SceneTree
## Exercise real menu selection, persistence and picking at all three resolutions.
const SCREEN = preload("res://modules/games/chinese_chess/chinese_chess_3d_screen.gd")
const SETTINGS := "user://chinese_chess_visuals.cfg"
var original_settings: PackedByteArray
var had_settings := false

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var screen = SCREEN.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not screen.has_method("_apply_render_quality"):
		push_error("RENDER_QUALITY_SMOKE: low/medium/high settings are missing")
		screen.free()
		quit(1)
		return
	had_settings = FileAccess.file_exists(SETTINGS)
	if had_settings:
		original_settings = FileAccess.get_file_as_bytes(SETTINGS)
	root.add_child(screen)
	screen._socket.close()
	screen.set_process(false)
	await process_frame
	var expected_sizes := [Vector2i(750,855), Vector2i(1000,1140), Vector2i(1500,1710)]
	var expected_msaa := [Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X]
	var checked := 0
	for quality in range(3):
		screen._quality_option.select(quality)
		screen._quality_option.item_selected.emit(quality)
		assert(screen._board_viewport.size == expected_sizes[quality])
		assert(screen._board_viewport.msaa_3d == expected_msaa[quality])
		assert(screen._stage.get_node("KeyLight").shadow_enabled == (quality > 0))
		assert(screen._camera.projection == Camera3D.PROJECTION_PERSPECTIVE)
		var probe = SCREEN.new()
		probe._load_render_quality()
		assert(probe._render_quality == quality, "Selected quality must survive reload")
		probe.free()
		for side in ["red", "black"]:
			screen._your_color = side
			screen._apply_player_view()
			await process_frame
			for row in range(10):
				for col in range(9):
					var pos := Vector2i(col,row)
					var point: Vector3 = screen._board_to_world(pos)
					point.y = screen.BOARD_Y
					var viewport_pos: Vector2 = screen._camera.unproject_position(point)
					var click: Vector2 = viewport_pos * screen._board_view.size / Vector2(screen._board_viewport.size)
					assert(screen._screen_to_board(click) == pos, "Quality changes must preserve picking: profile=%d side=%s expected=%s actual=%s size=%s" % [quality, side, str(pos), str(screen._screen_to_board(click)), str(screen._board_view.size)])
					checked += 1
		print("RENDER_QUALITY_SMOKE quality=", quality, " resolution=", screen._board_viewport.size, " msaa=", screen._board_viewport.msaa_3d)
	for resolution in [Vector2(450,800), Vector2(900,500), Vector2(1440,900)]:
		screen.size = resolution
		screen._layout_hud()
		for node in [screen._bgm_toggle_button, screen._sfx_toggle_button, screen._quality_label, screen._quality_option, screen._menu_close]:
			assert(node.position.y >= 0 and node.position.y + node.size.y <= screen._menu_panel.size.y, "Menu controls must fit portrait and landscape")
		assert(screen._quality_option.position.y + screen._quality_option.size.y <= screen._menu_close.position.y, "Quality selector must not overlap the return button")
	screen.queue_free()
	await process_frame
	if had_settings:
		var output := FileAccess.open(SETTINGS, FileAccess.WRITE)
		output.store_buffer(original_settings)
		output.close()
	else:
		DirAccess.remove_absolute(SETTINGS)
	print("RENDER_QUALITY_SMOKE_PASS profiles=3 persisted=3 intersection_picks=", checked, " menu_layouts=3")
	quit()
