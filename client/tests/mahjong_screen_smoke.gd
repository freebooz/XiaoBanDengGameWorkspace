extends SceneTree
## 运行方法：Godot --headless --path client/.generated/mahjong --script <本文件>

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var script = load("res://modules/games/mahjong/guiyang/guiyang_3d_screen.gd")
	if script == null:
		push_error("麻将对局脚本无法加载")
		quit(1)
		return
	var screen = script.new()
	screen.match_context = {"room_id": "1234", "account_id": "smoke-east", "seat_index": 0}
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	await process_frame
	print("MAHJONG_VIEWPORT_SIZE=" + str(screen._board_viewport.size))
	if not _verify_landscape(screen):
		quit(1)
		return
	screen._set_quality(0)
	var low_pixels: int = screen._board_viewport.size.x * screen._board_viewport.size.y
	if not _verify_aspect(screen):
		quit(1)
		return
	screen._set_quality(2)
	if screen._board_viewport.size.x * screen._board_viewport.size.y < low_pixels * 3 or not _verify_aspect(screen):
		push_error("高画质没有提高渲染精度或改变了牌桌比例")
		quit(1)
		return
	screen._set_quality(1)
	var hand: Array = []
	for index in range(14):
		hand.append({"id": index + 1, "suit": "wan", "rank": index % 9 + 1})
	screen._state = {
		"room_id": "1234", "status": "playing", "phase": "turn", "turn": 0, "your_seat": 0,
		"players": ["smoke-east", "smoke-south", "smoke-west", "smoke-north"],
		"hand": hand, "hand_counts": [14, 13, 13, 13], "scores": [0, 0, 0, 0],
		"melds": [[], [], [], []], "discards": [], "remaining": 55,
		"options": [{"type": "play"}], "winners": [], "reason": ""
	}
	screen._render()
	await process_frame
	if screen._hand_models.size() != 14 or _buttons(screen._actions_root).size() != 1 or screen._pieces_root.get_child_count() < 14:
		push_error("三维手牌或打牌按钮未渲染")
		quit(1)
		return
	if not _verify_hand_and_controls(screen):
		quit(1)
		return
	if screen._hand_models[0].find_child("TileFace", true, false) == null:
		push_error("三维牌面贴图网格未找到")
		quit(1)
		return
	print("MAHJONG_SCREEN_SMOKE_OK 3d_hand=14 actions=1")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = screen._camera.unproject_position(screen._hand_models[0].global_position) * screen._board_view.size / Vector2(screen._board_viewport.size)
	screen._on_board_input(click)
	if screen._selected_id != 1 or screen._hand_models[0].position.y < 0.02:
		push_error("点击三维手牌后未选中或抬起")
		quit(1)
		return
	print("MAHJONG_3D_SELECTION_OK")
	var tap := InputEventScreenTouch.new()
	tap.pressed = true
	tap.position = screen._camera.unproject_position(screen._hand_models[1].global_position) * screen._board_view.size / Vector2(screen._board_viewport.size)
	screen._on_board_input(tap)
	if screen._selected_id != 2:
		push_error("触屏未能选中三维手牌")
		quit(1)
		return
	print("MAHJONG_TOUCH_SELECTION_OK")
	for layout_size in [Vector2(1800, 810), Vector2(1440, 960), Vector2(1440, 810)]:
		screen.size = layout_size
		await process_frame
		if not _verify_landscape(screen) or not _verify_hand_and_controls(screen):
			quit(1)
			return
	print("MAHJONG_LANDSCAPE_RESIZE_OK")
	screen._state["phase"] = "reaction"
	screen._state["options"] = [{"type": "peng"}, {"type": "ming_gang"}, {"type": "an_gang", "tile_id": 2}, {"type": "bu_gang", "tile_id": 3}, {"type": "hu"}, {"type": "pass"}]
	screen._render()
	await process_frame
	if _buttons(screen._actions_root).size() != 6 or not _verify_hand_and_controls(screen):
		push_error("碰、杠、胡、过操作没有全部显示")
		quit(1)
		return
	print("MAHJONG_REACTIONS_OK")
	screen._state["discards"] = null
	screen._state["options"] = null
	screen._state["winners"] = null
	screen._render()
	await process_frame
	print("MAHJONG_EMPTY_ARRAYS_OK")
	screen._state["discards"] = [{"seat": 1, "tile": {"id": 100, "suit": "tong", "rank": 3}, "claimed": false}]
	screen._state["melds"] = [[{"kind": "peng", "tiles": [{"id": 101, "suit": "wan", "rank": 2}, {"id": 102, "suit": "wan", "rank": 2}, {"id": 103, "suit": "wan", "rank": 2}]}], [], [], []]
	screen._render()
	await process_frame
	print("MAHJONG_DISCARD_AND_MELD_OK")
	var training = script.new()
	training.training_mode = true
	training.match_context = {"room_id": "训练", "seat_index": 0}
	root.add_child(training)
	await process_frame
	if training._hand_models.size() != 14 or training._socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		push_error("训练模式未正确创建三维手牌或错误连接了实时房间")
		quit(1)
		return
	if training._board_viewport.world_3d == screen._board_viewport.world_3d:
		push_error("两张牌桌共享了三维世界")
		quit(1)
		return
	var training_returns := _buttons(training).filter(func(button): return button.text == "返回大厅")
	if training_returns.is_empty() or not _inside(training_returns[0].get_global_rect(), training.get_global_rect()):
		push_error("训练返回大厅入口不可见")
		quit(1)
		return
	training._training_play(1)
	await process_frame
	if training._array("discards").size() != 1 or training._hand_models.size() != 14:
		push_error("训练模式打牌后未补牌")
		quit(1)
		return
	training.queue_free()
	print("MAHJONG_TRAINING_SMOKE_OK")
	screen._state["phase"] = "finished"
	screen._state["status"] = "finished"
	screen._state["options"] = []
	screen._state["winners"] = [0]
	screen._render()
	await process_frame
	var settlement := screen._overlay_root.find_child("MahjongSettlement", true, false) as Panel
	if settlement == null or not _inside(settlement.get_global_rect(), screen.get_global_rect()) or _buttons(settlement).is_empty():
		push_error("横屏结算或返回按钮不完整")
		quit(1)
		return
	print("MAHJONG_SETTLEMENT_OK")
	screen._state["phase"] = "turn"
	screen._state["status"] = "playing"
	screen._state["discards"] = []
	screen._state["melds"] = [[], [], [], []]
	screen._state["options"] = [{"type": "play"}]
	screen._state["winners"] = []
	screen._render()
	await process_frame
	print("MAHJONG_DISPLAY=" + DisplayServer.get_name())
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var picture := root.get_viewport().get_texture().get_image()
		if picture != null and not picture.is_empty():
			print("MAHJONG_SCREENSHOT_RESULT=" + str(picture.save_png("E:/work/2026/XiaoBanDengGameWorkspace/artifacts/mahjong_screen_smoke.png")))
	quit(0)


func _buttons(parent: Node) -> Array[Button]:
	var found: Array[Button] = []
	for child in parent.get_children():
		if child is Button and not child.is_queued_for_deletion():
			found.append(child)
		found.append_array(_buttons(child))
	return found


func _inside(inner: Rect2, outer: Rect2) -> bool:
	return outer.grow(1.0).encloses(inner)


func _verify_aspect(screen) -> bool:
	var displayed: float = screen._board_view.size.x / screen._board_view.size.y
	var rendered: float = float(screen._board_viewport.size.x) / float(screen._board_viewport.size.y)
	if absf(displayed - rendered) > 0.004:
		push_error("三维牌桌纹理发生拉伸")
		return false
	return true


func _verify_landscape(screen) -> bool:
	var bounds: Rect2 = screen.get_global_rect()
	if bounds.size.x < bounds.size.y or screen._board_view.size.x < screen._board_view.size.y * 1.45:
		push_error("麻将仍然使用竖屏牌桌布局")
		return false
	for control in [screen._board_view, screen._actions_root, screen._status, screen._quality_option]:
		if not _inside(control.get_global_rect(), bounds):
			push_error("横屏核心控件超出屏幕")
			return false
	if not screen._board_viewport.own_world_3d or not screen._board_viewport.transparent_bg:
		push_error("麻将缺少独立透明三维视口")
		return false
	return _verify_aspect(screen)


func _verify_hand_and_controls(screen) -> bool:
	var board_rect: Rect2 = screen._board_view.get_global_rect()
	var previous := Vector2.ZERO
	for index in range(screen._hand_models.size()):
		var point: Vector2 = screen._camera.unproject_position(screen._hand_models[index].global_position) * screen._board_view.size / Vector2(screen._board_viewport.size) + board_rect.position
		if not board_rect.grow(-12).has_point(point) or screen._actions_root.get_global_rect().has_point(point):
			push_error("三维手牌被裁切或操作区遮挡")
			return false
		for seat_panel in screen._seat_root.get_children():
			if seat_panel is Control and not seat_panel.is_queued_for_deletion() and seat_panel.get_global_rect().has_point(point):
				push_error("座位头像遮挡自己的手牌")
				return false
		if index > 0 and point.distance_to(previous) < 27:
			push_error("十四张手牌过小，难以触控选择")
			return false
		previous = point
	var visible_buttons := _buttons(screen._actions_root)
	for button in visible_buttons:
		if button.size.x < 90 or button.size.y < 60 or not _inside(button.get_global_rect(), screen._actions_root.get_global_rect()):
			push_error("响应按钮过小或超出操作区")
			return false
	for left_index in range(visible_buttons.size()):
		for right_index in range(left_index + 1, visible_buttons.size()):
			if visible_buttons[left_index].get_global_rect().grow(-1).intersects(visible_buttons[right_index].get_global_rect().grow(-1)):
				push_error("麻将响应按钮互相遮挡")
				return false
	return true
