extends SceneTree

const MODAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_modal.gd")
const PATCH := preload("res://modules/foundation/ui/aspect_nine_patch_style.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1200, 820)
	var canvas := Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(canvas)
	var back := ColorRect.new()
	back.color = Color("#f5e0bf")
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(back)
	var position_y := 20.0
	var checked := 0
	for role in ["orange", "green", "blue", "gold", "cream"]:
		var x := 20.0
		for dimensions in [Vector2(180, 48), Vector2(330, 80), Vector2(600, 120)]:
			var button := Button.new()
			button.text = "九宫格按钮"
			canvas.add_child(button)
			if role in ["gold", "cream"]: MODAL.village_button(button, role == "gold")
			else: MODAL.login_button(button, role)
			button.size = dimensions
			button.position = Vector2(x, position_y)
			button.add_theme_font_size_override("font_size", roundi(dimensions.y * 0.37))
			for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
				var style := button.get_theme_stylebox(state)
				assert(style.get_script() == PATCH, "Every textured state uses shared nine-slice")
				var pieces: Array = style.patch_layout(Rect2(Vector2.ZERO, dimensions))
				assert(pieces.size() == 9)
				for corner in [0, 2, 6, 8]:
					var from: Rect2 = pieces[corner].source
					var to: Rect2 = pieces[corner].destination
					assert(absf(to.size.x / from.size.x - to.size.y / from.size.y) < 0.0001, "Corner artwork retains its aspect")
				var total_area := 0.0
				for piece in pieces:
					assert(Rect2(Vector2.ZERO, dimensions).encloses(piece.destination), "No patch exceeds the control")
					total_area += piece.destination.get_area()
				assert(absf(total_area - dimensions.x * dimensions.y) < 0.1, "No missing patch or repeated fill")
				checked += 1
			x += dimensions.x + 15
		position_y += 150
	var checked_panels := 0
	for dimensions in [Vector2(320, 560), Vector2(874, 1200), Vector2(1500, 450), Vector2(600, 300)]:
		var panel = MODAL.paper_frame()
		var border := PATCH.new()
		border.texture = MODAL.VILLAGE_FRAME
		border.region_rect = panel.source_region
		border.source_margins = panel.source_cuts
		border.corner_scale = panel.border_scale_for_size(dimensions)
		border.draw_center = false
		var pieces := border.patch_layout(Rect2(Vector2.ZERO, dimensions))
		assert(pieces.size() == 8, "The transparent panel center is supplied by the separate paper layer")
		for corner in [0, 2, 5, 7]:
			var from: Rect2 = pieces[corner].source
			var to: Rect2 = pieces[corner].destination
			assert(absf(to.size.x / from.size.x - to.size.y / from.size.y) < 0.0001, "Panel ropes and leaves preserve their original proportions")
		for piece in pieces:
			assert(Rect2(Vector2.ZERO, dimensions).encloses(piece.destination), "Panel edge stays in its bounds")
		checked_panels += 1
	for frame in 5: await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0]) == OK)
	print("MAHJONG_NINE_PATCH_OK styles=%d panels=%d corner_aspect=preserved" % [checked, checked_panels])
	quit()
