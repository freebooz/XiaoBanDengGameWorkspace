extends SceneTree
## 横屏布局回归：玩家上下顺序、棋盘比例、触控按钮、双视角拾取和居中弹窗。

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)


func _inside(control: Control, bounds: Rect2) -> bool:
	return bounds.encloses(control.get_global_rect())


func _run() -> void:
	var screen_script = load("res://modules/games/chinese_chess/chinese_chess_3d_screen.gd")
	if screen_script == null:
		push_error("象棋横屏脚本无法加载")
		quit(1)
		return
	var screen = screen_script.new()
	screen.training_mode = true
	screen.match_context = {"room_id": "训练", "display_name": "横屏棋友", "opponent_display_name": "同机练习"}
	root.add_child(screen)
	await process_frame
	_check(screen._board_viewport.own_world_3d, "棋盘必须使用独立三维世界")
	_check(screen._pieces_by_pos.size() == 32, "横屏棋盘未保留标准开局")
	for extent in [Vector2(1440, 810), Vector2(1800, 810), Vector2(1440, 1080), Vector2(960, 540)]:
		screen.size = extent
		screen._layout_hud()
		await process_frame
		var bounds := Rect2(screen.global_position, extent)
		_check(screen._right_card.position.y + screen._right_card.size.y < screen._left_card.position.y, "对手应在自己上方：%s" % extent)
		_check(_inside(screen._board_view, bounds), "棋盘超出横屏：%s" % extent)
		_check(absf(screen._board_view.size.x / screen._board_view.size.y - 1000.0 / 1140.0) < 0.0001, "棋盘纹理被拉伸：%s" % extent)
		_check(_inside(screen._status_label, bounds), "对局提示超出横屏：%s" % extent)
		for i in range(screen._action_buttons.size()):
			var button: Button = screen._action_buttons[i]
			_check(_inside(button, bounds), "操作按钮超出横屏：%s %s" % [extent, button.name])
			_check(button.size.x >= 48 and button.size.y >= 48, "操作触控区域过小：%s %s" % [extent, button.name])
			_check(not button.get_global_rect().intersects(screen._board_view.get_global_rect()), "操作遮挡棋盘：%s %s" % [extent, button.name])
			for j in range(i):
				_check(not button.get_global_rect().intersects(screen._action_buttons[j].get_global_rect()), "操作按钮重叠：%s" % extent)
		_check(screen._left_player_label.size.x > 0 and screen._right_player_label.size.x > 0, "玩家名称区域宽度无效：%s" % extent)
		screen._layout_modal_panels(extent.x, extent.y)
		_check(_inside(screen._menu_panel, bounds), "菜单超出横屏：%s" % extent)
		_check(_inside(screen._settlement_panel, bounds), "结算超出横屏：%s" % extent)
		_check(screen._menu_panel.get_global_rect().get_center().distance_to(bounds.get_center()) < 1.0, "菜单没有居中：%s" % extent)
		_check(screen._settlement_panel.get_global_rect().get_center().distance_to(bounds.get_center()) < 1.0, "结算没有居中：%s" % extent)
		for side in ["red", "black"]:
			screen._your_color = side
			screen._apply_player_view()
			await process_frame
			for board_pos in [Vector2i(0, 0), Vector2i(8, 0), Vector2i(4, 4), Vector2i(0, 9), Vector2i(8, 9)]:
				var viewport_pos: Vector2 = screen._camera.unproject_position(screen._board_to_world(board_pos))
				var tap_pos: Vector2 = viewport_pos * screen._board_view.size / Vector2(screen._board_viewport.size)
				_check(screen._screen_to_board(tap_pos) == board_pos, "棋盘拾取错位：%s %s %s" % [extent, side, board_pos])
	screen._your_color = "red"
	screen._apply_player_view()
	screen._selected = screen.INVALID_POS
	var soldier_pos: Vector2 = screen._camera.unproject_position(screen._board_to_world(Vector2i(0, 6))) * screen._board_view.size / Vector2(screen._board_viewport.size)
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = soldier_pos
	screen._on_board_gui_input(touch)
	_check(screen._selected == Vector2i(0, 6), "触屏无法选中自己的棋子")
	screen._selected = screen.INVALID_POS
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	mouse.position = soldier_pos
	screen._on_board_gui_input(mouse)
	_check(screen._selected == Vector2i(0, 6), "鼠标无法选中自己的棋子")
	screen.queue_free()
	await process_frame
	if _failures.is_empty():
		print("CHESS_LANDSCAPE_SMOKE_OK sizes=4 views=2 actions=6 touch=1 mouse=1")
	quit(0 if _failures.is_empty() else 1)
