extends SceneTree
## Render the current landscape duel and verify both player perspectives.
const SCREEN = preload("res://modules/games/chinese_chess/chinese_chess_3d_screen.gd")

func _initialize() -> void:
	call_deferred("run_review")

func run_review() -> void:
	var preview_dir := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--preview-dir="):
			preview_dir = argument.trim_prefix("--preview-dir=")
	if not preview_dir.is_empty() and (DisplayServer.get_name() == "headless" or not DirAccess.dir_exists_absolute(preview_dir)):
		_fail("Preview output requires an existing directory and the native renderer")
		return
	var lobby_design := root.content_scale_size
	var lobby_aspect := root.content_scale_aspect
	var screen = SCREEN.new()
	screen.training_mode = true
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	await process_frame
	if root.content_scale_size != Vector2i(1440, 810) or screen._pieces_by_pos.size() != 32:
		_fail("Duel did not enter the landscape display with the complete opening position")
		return
	for dimensions in [Vector2i(1280, 720), Vector2i(1280, 800), Vector2i(1280, 960)]:
		root.size = dimensions
		await process_frame
		var bounds: Rect2 = screen.get_global_rect()
		var board: Rect2 = screen._board_frame.get_global_rect()
		if not board.has_area() or not bounds.encloses(board):
			_fail("Duel board is clipped at %s" % dimensions)
			return
		for button: Button in screen._action_buttons:
			if not bounds.encloses(button.get_global_rect()) or board.intersects(button.get_global_rect()):
				_fail("Duel button %s is clipped or covers the board at %s" % [button.name, dimensions])
				return
		for side in ["red", "black"]:
			screen._your_color = side
			screen._apply_player_view()
			screen._update_player_panels()
			var own_badge: Label = screen._left_card.get_node("SideBadge/SideBadgeText")
			var other_badge: Label = screen._right_card.get_node("SideBadge/SideBadgeText")
			if own_badge.text != ("红方" if side == "red" else "黑方") or own_badge.text == other_badge.text:
				_fail("Duel badges do not reflect opposing seats in the %s perspective" % side)
				return
			if not preview_dir.is_empty():
				await RenderingServer.frame_post_draw
				var file := "XBD_Game_duel_%s_%dx%d.png" % [side, dimensions.x, dimensions.y]
				if root.get_texture().get_image().save_png(preview_dir.path_join(file)) != OK:
					_fail("Could not save the requested duel preview " + file)
					return
		print("DUEL_LAYOUT_SMOKE window=", root.size, " board=", board.size, " actions=", screen._action_buttons.size())
	screen.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	if root.content_scale_size != lobby_design or root.content_scale_aspect != lobby_aspect:
		_fail("Duel did not restore the lobby display")
		return
	print("DUEL_LAYOUT_SMOKE_PASS layouts=3 perspectives=2 lobby_restored=true")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
