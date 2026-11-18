extends SceneTree
## 运行方法：Godot --headless --path client/.generated/mahjong --script <本文件>

class RenderFixture:
	extends "res://modules/games/mahjong/guiyang/guiyang_3d_screen.gd"
	var submitted: Array[Dictionary] = []
	func _send_action(kind: String, tile_id: int = 0, _source_key: Array = [], _suit: String = "") -> void:
		submitted.append({"kind":kind,"tile_id":tile_id})
	func _connect_socket() -> void:
		pass
	func _actions_ready() -> bool:
		return true

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1440, 810)
	var script = load("res://modules/games/mahjong/guiyang/guiyang_3d_screen.gd")
	if script == null:
		push_error("麻将对局脚本无法加载")
		quit(1)
		return
	var screen := RenderFixture.new()
	screen.match_context = {"room_id": "1234", "account_id": "smoke-east", "seat_index": 0}
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	screen.set_process(false)
	await process_frame
	print("MAHJONG_VIEWPORT_SIZE=" + str(screen._board_viewport.size))
	if not _verify_landscape(screen):
		quit(1)
		return
	root.content_scale_size = Vector2i(1440, 810)
	root.size = Vector2i(2560, 1440)
	for frame in 3: await process_frame
	for quality in [0, 1, 2]:
		screen._set_quality(quality)
		if not _verify_aspect(screen):
			quit(1)
			return
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1440, 810)
	for frame in 3: await process_frame
	screen._set_quality(1)
	var hand: Array = []
	for index in range(14):
		hand.append({"id": index + 1, "suit": "wan", "rank": index % 9 + 1})
	screen._state = {
		"room_id": "1234", "status": "playing", "phase": "turn", "turn": 0, "your_seat": 0,
		"players": ["smoke-east", "smoke-south", "smoke-west", "smoke-north"],
		"hand": hand, "hand_counts": [14, 13, 13, 13], "scores": [0, 0, 0, 0],
		"melds": [[], [], [], []], "discards": [], "remaining": 55,
		"options": [{"type": "play"}], "winners": [], "reason": "", "drawn_tile_id": 14
	}
	screen._render()
	await process_frame
	if screen._hand_models.size() != 14 or screen._response_buttons.size() != 5 or screen._response_buttons.pass.visible or screen._pieces_root.get_child_count() < 14 or not screen._play_button.visible:
		push_error("三维手牌或打牌按钮未渲染")
		quit(1)
		return
	if not _verify_hand_and_controls(screen):
		quit(1)
		return
	if not _verify_touching_row(screen._hand_models):
		quit(1)
		return
	for relative in range(1, 4):
		if not _verify_touching_row(screen._pieces_root.find_children("MahjongConcealedHand%d_*" % relative, "Node3D", false, false)):
			quit(1)
			return
	if screen._hand_models[0].find_child("TileFace", true, false) == null:
		push_error("三维牌面贴图网格未找到")
		quit(1)
		return
	print("MAHJONG_SCREEN_SMOKE_OK 3d_hand=14 response_controls=5 play_button=true")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = screen._camera.unproject_position(screen._hand_models[0].global_position) * screen._board_view.size / Vector2(screen._board_viewport.size)
	screen._on_board_input(click)
	if screen._selected_id != 1 or screen._hand_models[0].position.y <= screen._hand_models[1].position.y:
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
	for index in range(14):
		if not _pick(screen, index, index % 2 == 0, true):
			quit(1)
			return
	print("MAHJONG_ALL_FACES_PICKING_OK")
	var delivered: Array = []
	var previous_mouse_emulation: bool = Input.emulate_mouse_from_touch
	Input.emulate_mouse_from_touch = true
	screen._board_view.gui_input.connect(func(event):
		if event is InputEventMouseButton or event is InputEventScreenTouch:
			delivered.append(event)
	)
	var touch_face := screen._hand_models[5].find_child("TileFace", true, false) as MeshInstance3D
	var face_point: Vector2 = screen._camera.unproject_position(touch_face.global_transform * touch_face.get_aabb().get_center()) * screen._board_view.size / Vector2(screen._board_viewport.size)
	var gui_point: Vector2 = screen._board_view.get_viewport_transform() * screen._board_view.get_global_transform() * face_point
	var gui_touch := InputEventScreenTouch.new()
	screen.submitted.clear()
	gui_touch.index = 0
	gui_touch.pressed = true
	gui_touch.position = gui_point
	Input.parse_input_event(gui_touch)
	await process_frame
	var touch_delivered := delivered.any(func(event): return event is InputEventScreenTouch and event.pressed)
	if not touch_delivered or screen._selected_id != 6:
		push_error("真实 GUI 触屏投递没有正确选中牌面")
		quit(1)
		return
	gui_touch.pressed = false
	Input.parse_input_event(gui_touch)
	await process_frame
	var suppressed_mouse := InputEventMouseButton.new()
	suppressed_mouse.device = -1
	suppressed_mouse.button_index = MOUSE_BUTTON_LEFT
	suppressed_mouse.pressed = true
	suppressed_mouse.position = screen._projected_tile_rect(screen._hand_models[6]).get_center()
	screen._on_board_input(suppressed_mouse)
	if screen._selected_id != 6:
		push_error("触屏模拟鼠标重复触发，误选了相邻牌")
		quit(1)
		return
	gui_touch.pressed = true
	gui_touch.position = screen._board_view.get_viewport_transform() * screen._board_view.get_global_transform() * screen._projected_tile_rect(screen._hand_models[5]).get_center()
	Input.parse_input_event(gui_touch)
	await process_frame
	if screen._selected_id != 6 or screen._selected_outline.visible or screen.submitted != [{"kind":"play","tile_id":6}] or screen._hand_models[5].position.y <= screen._hand_models[4].position.y:
		push_error("再次点触同一张手牌应提交一次出牌，并保留抬起状态直到服务器确认")
		quit(1)
		return
	gui_touch.pressed = false
	Input.parse_input_event(gui_touch)
	await process_frame
	var real_face := screen._hand_models[9].find_child("TileFace", true, false) as MeshInstance3D
	var mouse_local: Vector2 = screen._camera.unproject_position(real_face.global_transform * real_face.get_aabb().get_center()) * screen._board_view.size / Vector2(screen._board_viewport.size)
	var real_mouse := InputEventMouseButton.new()
	real_mouse.device = 0
	real_mouse.button_index = MOUSE_BUTTON_LEFT
	real_mouse.pressed = true
	real_mouse.position = screen._board_view.get_viewport_transform() * screen._board_view.get_global_transform() * mouse_local
	real_mouse.global_position = real_mouse.position
	Input.parse_input_event(real_mouse)
	await process_frame
	if screen._selected_id != 10 or not delivered.any(func(event): return event is InputEventMouseButton and event.device == 0 and event.pressed):
		push_error("真实 GUI 鼠标投递没有正确选牌")
		quit(1)
		return
	real_mouse.pressed = false
	Input.parse_input_event(real_mouse)
	Input.emulate_mouse_from_touch = previous_mouse_emulation
	print("MAHJONG_GUI_TOUCH_EMULATION_OK")
	for quality in [0, 2, 1]:
		screen._set_quality(quality)
		await process_frame
		if not _pick(screen, 13, true, true) or not _verify_aspect(screen):
			quit(1)
			return
	print("MAHJONG_QUALITY_PICKING_OK")
	for layout_size in [Vector2(1800, 810), Vector2(1440, 1080), Vector2(1440, 810)]:
		root.size = Vector2i(layout_size)
		for frame in 3: await process_frame
		if not _verify_landscape(screen) or not _verify_hand_and_controls(screen) or not _pick(screen, 6, false):
			quit(1)
			return
	print("MAHJONG_LANDSCAPE_RESIZE_OK")
	screen._state["phase"] = "reaction"
	screen._state["turn"] = 1
	screen._state["rule_set_id"] = "basic_108"
	var reaction_hand: Array[Dictionary] = []
	for group in [["wan", [1, 1, 1, 2, 3]], ["tong", [1, 2, 3, 5, 5]], ["tiao", [1, 2, 3]]]:
		for rank in group[1]:
			reaction_hand.append({"id": reaction_hand.size() + 1, "suit": group[0], "rank": rank})
	screen._state["hand"] = reaction_hand
	screen._state["hand_counts"] = [13, 13, 13, 13]
	screen._state["drawn_tile_id"] = 0
	var reaction_tile := {"id": 98, "suit": "wan", "rank": 1}
	screen._state["last_discard"] = reaction_tile
	screen._state["discards"] = [{"seat":1, "tile":reaction_tile, "claimed":false}]
	screen._state["options"] = [{"type":"peng"}, {"type":"ming_gang"}, {"type":"hu"}, {"type":"pass"}]
	screen._render()
	await process_frame
	if _buttons(screen._actions_root).filter(func(button): return button.is_visible_in_tree()).size() != 4 or not screen._response_buttons.pass.is_visible_in_tree() or screen._play_button.visible or screen._legal_options("gang").size() != 1 or not _verify_hand_and_controls(screen):
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
	var tiles := func(suit: String, rank: int, ids: Array) -> Array:
		return ids.map(func(id): return {"id": id, "suit": suit, "rank": rank})
	var peng: Array = tiles.call("tong", 3, [21, 22, 23])
	screen._state["discards"] = [{"seat": 1, "tile": peng[0], "claimed": true},
		{"seat": 1, "tile": {"id": 24, "suit": "tong", "rank": 4}, "claimed": false}]
	screen._state["melds"] = [
		[{"kind": "peng", "tiles": peng}],
		[{"kind": "ming_gang", "tiles": tiles.call("tiao", 4, [31, 32, 33, 34])}],
		[{"kind": "an_gang", "tiles": [{}, {}, {}, {}]}],
		[{"kind": "bu_gang", "tiles": tiles.call("tiao", 8, [41, 42, 43, 44])}],
	]
	screen._state["hand"] = hand.slice(0, 11)
	screen._render()
	await process_frame
	if screen._pieces_root.find_children("MahjongDiscard*", "Node3D", false, false).size() != 1 or not _verify_melds(screen):
		push_error("碰杠牌组或被认领的弃牌显示错误")
		quit(1)
		return
	var left_hand: Node3D = screen._hand_models.front()
	var right_hand: Node3D = screen._hand_models.back()
	var own_melds: Array = screen._pieces_root.find_children("MahjongMeld0_*", "Node3D", false, false)
	var hand_width: float = screen.TILE_SIZE.x
	var meld_width: float = screen.TILE_SIZE.x
	var row_left: float = own_melds.front().position.x - meld_width * 0.5
	var row_right := right_hand.position.x + hand_width * 0.5
	var gap: float = left_hand.position.x - hand_width * 0.5 - (own_melds.back().position.x + meld_width * 0.5)
	if not is_zero_approx((row_left + row_right) * 0.5) or not is_equal_approx(gap, hand_width):
		push_error("手牌与左侧副露应整体居中，间隔一张手牌宽度")
		quit(1)
		return
	print("MAHJONG_DISCARD_AND_MELD_OK exposed=11 concealed=4 touching_rows=true")
	var public_discards: Array = []
	for seat in range(4):
		for index in range(12):
			public_discards.append({"seat":seat,"tile":{"id":200+seat*12+index,"suit":"wan","rank":index%9+1},"claimed":false})
	screen._state["discards"] = public_discards
	screen._state["melds"] = [[],[],[],[]]
	screen._render()
	await process_frame
	for model in screen._pieces_root.find_children("MahjongDiscard*", "Node3D", false, false):
		var printed_face: Rect2 = screen._projected_tile_rect(model)
		printed_face.position += screen._board_view.position
		if printed_face.grow(-1).intersects(screen._remaining_panel.get_global_rect()):
			push_error("中央剩余牌数遮挡了四方公开弃牌")
			quit(1)
			return
	print("MAHJONG_PUBLIC_DISCARDS_CLEAR_OK tiles=48")
	var training = script.new()
	training.training_mode = true
	training.match_context = {"room_id": "训练", "seat_index": 0}
	root.add_child(training)
	await process_frame
	if training._hand_models.size() != 14 or training._transport_open():
		push_error("训练模式未正确创建三维手牌或错误连接了实时房间")
		quit(1)
		return
	if training._board_viewport.find_world_3d() == screen._board_viewport.find_world_3d():
		push_error("两张牌桌共享了三维世界")
		quit(1)
		return
	training._request_leave()
	await process_frame
	var training_returns := _buttons(training).filter(func(button): return button.name == "MahjongLeaveConfirm")
	if training_returns.is_empty() or not _inside(training_returns[0].get_global_rect(), training.get_global_rect()):
		push_error("训练返回大厅入口不可见")
		quit(1)
		return
	training._close_tool()
	if not _pick(training, 0, true):
		quit(1)
		return
	training._play_button.pressed.emit()
	await process_frame
	if training._array("discards").size() != 1 or training._hand_models.size() != 14:
		push_error("训练模式打牌后未补牌")
		quit(1)
		return
	training._state["options"] = []
	training._render()
	await process_frame
	var returned := [false]
	training.request_return_to_lobby.connect(func(): returned[0] = true)
	training._request_leave()
	await process_frame
	var return_controls := _buttons(training).filter(func(button): return button.name == "MahjongLeaveConfirm")
	return_controls[0].pressed.emit()
	if not returned[0]:
		push_error("训练返回按钮没有响应")
		quit(1)
		return
	training.queue_free()
	print("MAHJONG_TRAINING_SMOKE_OK")
	screen._state["phase"] = "finished"
	screen._state["status"] = "finished"
	screen._state["options"] = []
	screen._state["winners"] = [0]
	screen._state["scores"] = [3, -1, -1, -1]
	screen._state["score_breakdown"] = {"hu":[2,-2,0,0],"gang":[1,0,-1,0],"ji":[0,1,0,-1]}
	screen._render()
	await process_frame
	var settlement := screen._overlay_root.find_child("MahjongSettlement", true, false) as Panel
	if settlement == null or not _inside(settlement.get_global_rect(), screen.get_global_rect()) or _buttons(settlement).is_empty():
		push_error("横屏结算或返回按钮不完整")
		quit(1)
		return
	var score_detail := settlement.find_child("MahjongSettlementBreakdown0", true, false) as Label
	if score_detail == null or score_detail.text != "胡 +2   杠 +1   鸡 +0":
		push_error("结算缺少独立分项")
		quit(1)
		return
	var settlement_returned := [false]
	screen.request_return_to_lobby.connect(func(): settlement_returned[0] = true)
	var return_button := settlement.find_child("MahjongSettlementLobbyButton", true, false) as Button
	if is_instance_valid(return_button): return_button.pressed.emit()
	if not settlement_returned[0]:
		push_error("结算返回按钮没有响应")
		quit(1)
		return
	print("MAHJONG_SETTLEMENT_OK")
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen._state["phase"] = "turn"
	screen._state["turn"] = 0
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
			if not _verify_rendered_ink(screen, picture):
				quit(1)
				return
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("--preview="):
					print("MAHJONG_SCREENSHOT_RESULT=" + str(picture.save_png(arg.trim_prefix("--preview="))))
	screen.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	quit(0)


func _buttons(parent: Node) -> Array[Button]:
	var found: Array[Button] = []
	for child in parent.get_children():
		if child is Button and not child.is_queued_for_deletion():
			found.append(child)
		found.append_array(_buttons(child))
	return found


func _pick(screen, index: int, touch: bool, face_center: bool = false) -> bool:
	# Explicitly reset the prior pick so this helper always tests selecting.
	screen._select_tile(0)
	var world_point: Vector3 = screen._hand_models[index].global_position
	if face_center:
		var face := screen._hand_models[index].find_child("TileFace", true, false) as MeshInstance3D
		world_point = face.global_transform * face.get_aabb().get_center()
	var point: Vector2 = screen._camera.unproject_position(world_point) * screen._board_view.size / Vector2(screen._board_viewport.size)
	if touch:
		var tap := InputEventScreenTouch.new()
		tap.pressed = true
		tap.position = point
		screen._on_board_input(tap)
	else:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = point
		screen._on_board_input(click)
	if screen._selected_id != screen._hand_ids[index]:
		push_error("画质或横屏比例变化后选牌位置错误")
		return false
	return true


func _inside(inner: Rect2, outer: Rect2) -> bool:
	return outer.grow(1.0).encloses(inner)


func _verify_aspect(screen) -> bool:
	var physical: Vector2 = screen._board_view.size * Vector2(root.size) / root.get_visible_rect().size
	var difference := (Vector2(screen._board_viewport.size) - physical).abs()
	if difference.x > 1.0 or difference.y > 1.0 or screen._board_viewport.scaling_3d_scale != 1.0:
		push_error("三维牌桌没有按窗口实际像素重绘")
		return false
	var surface: SubViewportContainer = screen._board_surface
	var output := surface.get_viewport_transform() * surface.get_global_transform()
	if surface.stretch or not is_equal_approx(output.x.length(), 1.0) or not is_equal_approx(output.y.length(), 1.0):
		push_error("三维视口输出未按原始像素显示")
		return false
	return true


func _verify_landscape(screen) -> bool:
	var bounds: Rect2 = screen.get_global_rect()
	if bounds.size.x < bounds.size.y or screen._board_view.size.x <= screen._board_view.size.y:
		push_error("麻将仍然使用竖屏牌桌布局")
		return false
	for control in [screen._board_view, screen._actions_root, screen._status, screen._quality_option]:
		if not _inside(control.get_global_rect(), bounds):
			push_error("横屏核心控件超出屏幕")
			return false
	if not screen._board_viewport.own_world_3d or not screen._board_viewport.transparent_bg:
		push_error("麻将缺少独立透明三维视口")
		return false
	var seats: Array = screen._seat_root.get_children().filter(func(child): return child is Panel and not child.is_queued_for_deletion())
	if seats.size() != 4:
		push_error("四个座位头像没有完整显示")
		return false
	for seat in seats:
		if not _inside(seat.get_global_rect(), bounds):
			push_error("座位信息超出横屏画面")
			return false
		var portrait := seat.find_child("MahjongSquarePortrait", true, false) as TextureRect
		if portrait == null or not _inside(portrait.get_global_rect(), seat.get_global_rect()):
			push_error("座位头像缺失或超出信息卡")
			return false
		var decoration := seat.find_child("MahjongSeatBlossom", false, false) as TextureRect
		if decoration != null and (decoration.mouse_filter != Control.MOUSE_FILTER_IGNORE or not _inside(decoration.get_global_rect(), bounds)):
			push_error("座位花饰超出画面或拦截输入")
			return false
	return _verify_aspect(screen)


func _verify_hand_and_controls(screen) -> bool:
	var board_rect: Rect2 = screen._board_view.get_global_rect()
	var previous := Vector2.ZERO
	for index in range(screen._hand_models.size()):
		var face_rect: Rect2 = screen._projected_tile_rect(screen._hand_models[index])
		if face_rect.size.x < 44 or face_rect.size.y < 52:
			push_error("自己的牌面过小或过于平躺，手机难以辨认")
			return false
		face_rect.position += board_rect.position
		if not _inside(face_rect, board_rect):
			push_error("放大的三维牌面超出牌桌画面")
			return false
		if screen._actions_root.visible and face_rect.grow(-1).intersects(screen._actions_root.get_global_rect()):
			push_error("响应按钮遮挡了手牌的完整牌面")
			return false
		if face_rect.grow(-1).intersects(screen._side_tools.get_global_rect()):
			push_error("底部操作栏遮挡了手牌的完整牌面")
			return false
		for seat_panel in screen._seat_panels:
			if is_instance_valid(seat_panel) and face_rect.grow(-1).intersects(seat_panel.get_global_rect()):
				push_error("玩家信息遮挡了手牌的完整牌面")
				return false
		var point: Vector2 = screen._camera.unproject_position(screen._hand_models[index].global_position) * screen._board_view.size / Vector2(screen._board_viewport.size) + board_rect.position
		if not board_rect.grow(-12).has_point(point) or (screen._actions_root.visible and screen._actions_root.get_global_rect().has_point(point)):
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
	if not _verify_hand_on_felt(screen):
		return false
	var visible_buttons := _buttons(screen._actions_root).filter(func(button): return button.is_visible_in_tree())
	var minimum_target: float = screen.RURAL.touch_extent(screen)
	for button in visible_buttons:
		if button.size.x < minimum_target or button.size.y < minimum_target or not _inside(button.get_global_rect(), screen._actions_root.get_global_rect()):
			push_error("响应按钮过小或超出操作区")
			return false
	for left_index in range(visible_buttons.size()):
		for right_index in range(left_index + 1, visible_buttons.size()):
			if visible_buttons[left_index].get_global_rect().grow(-1).intersects(visible_buttons[right_index].get_global_rect().grow(-1)):
				push_error("麻将响应按钮互相遮挡")
				return false
	return true


func _verify_hand_on_felt(screen) -> bool:
	var felt := screen._board_viewport.find_child("Mahjong_Felt_Surface", true, false) as MeshInstance3D
	if felt == null:
		push_error("无法读取三维绒布的真实边界")
		return false
	var felt_bounds: AABB = felt.global_transform * felt.get_aabb()
	for model in screen._hand_models:
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			var geometry: AABB = mesh.get_aabb()
			for index in range(8):
				var point: Vector3 = mesh.global_transform * geometry.get_endpoint(index)
				if point.x < felt_bounds.position.x or point.x > felt_bounds.end.x or point.z < felt_bounds.position.z or point.z > felt_bounds.end.z or point.y < felt_bounds.end.y - 0.0005:
					push_error("放大的手牌溢出台面或穿入台布")
					return false
	return true


func _verify_touching_row(models: Array) -> bool:
	if models.size() < 2:
		return false
	var body := models[0].find_child("TileBody", true, false) as MeshInstance3D
	var width: float = body.get_aabb().size.x * body.global_basis.x.length() / models[0].get_parent().global_basis.x.length()
	for index in range(1, models.size()):
		var offset: Vector3 = models[index].position - models[index - 1].position
		if absf(absf(offset.dot(models[index].basis.x.normalized())) - width) > 0.0001:
			push_error("同一排麻将牌未按实体宽度贴合")
			return false
	return true


func _verify_melds(screen) -> bool:
	for relative in range(4):
		var models: Array = screen._pieces_root.find_children("MahjongMeld%d_*" % relative, "Node3D", false, false)
		if models.size() != (3 if relative == 0 else 4) or not _verify_touching_row(models):
			return false
		for model in models:
			var face := model.find_child("TileFace", true, false) as MeshInstance3D
			if relative == 2:
				if not is_equal_approx(model.rotation.x, PI) or face.material_override != screen._tile_materials.blank_face():
					return false
			elif not face.material_override is ShaderMaterial or not is_zero_approx(model.rotation.x):
				return false
	return true


func _verify_rendered_ink(screen, picture: Image) -> bool:
	var display_transform: Transform2D = screen._board_view.get_viewport_transform() * screen._board_view.get_global_transform()
	for model in screen._hand_models:
		var rect: Rect2 = display_transform * screen._projected_tile_rect(model)
		rect = rect.grow(-2.0)
		var red_pixels := 0
		for y in range(maxi(0, ceili(rect.position.y)), mini(picture.get_height(), floori(rect.end.y))):
			for x in range(maxi(0, ceili(rect.position.x)), mini(picture.get_width(), floori(rect.end.x))):
				var pixel := picture.get_pixel(x, y)
				if pixel.r - maxf(pixel.g, pixel.b) > 0.18:
					red_pixels += 1
		if red_pixels < 3:
			push_error("实际渲染中万字牌的红色被高光洗白")
			return false
	print("MAHJONG_RENDERED_INK_OK")
	return true
