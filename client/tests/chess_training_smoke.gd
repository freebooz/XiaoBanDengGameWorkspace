extends SceneTree
## 验证象棋训练入口加载三维棋局及双方轮流走棋。

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var screen_script = load("res://modules/games/chinese_chess/chinese_chess_3d_screen.gd")
	if screen_script == null:
		push_error("象棋训练脚本无法加载")
		quit(1)
		return
	var screen = screen_script.new()
	screen.training_mode = true
	screen.match_context = {"room_id": "训练", "display_name": "我", "opponent_display_name": "同机练习"}
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	await process_frame
	if screen._pieces_by_pos.size() != 32 or screen._turn != "red" or not screen._joined:
		push_error("训练模式未创建标准三维棋盘")
		quit(1)
		return
	var tap := InputEventScreenTouch.new()
	tap.pressed = true
	tap.position = screen._camera.unproject_position(screen._board_to_world(Vector2i(0, 6))) * screen._board_view.size / Vector2(screen._board_viewport.size)
	screen._on_board_gui_input(tap)
	if screen._selected != Vector2i(0, 6):
		push_error("触屏未能选中三维棋子")
		quit(1)
		return
	screen._on_board_pressed(Vector2i(0, 5))
	if screen._turn != "black" or not screen._pieces_by_pos.has(Vector2i(0, 5)):
		push_error("红方兵未按规则前进")
		quit(1)
		return
	screen._on_board_pressed(Vector2i(0, 3))
	screen._on_board_pressed(Vector2i(0, 4))
	if screen._turn != "red" or not screen._pieces_by_pos.has(Vector2i(0, 4)):
		push_error("黑方卒未按规则前进")
		quit(1)
		return
	var rules = load("res://modules/games/chinese_chess/chess_training_rules.gd")
	if rules.validate(screen._pieces_by_pos, Vector2i(0, 9), Vector2i(1, 8), "red") == "":
		push_error("非法斜走车未被拒绝")
		quit(1)
		return
	print("CHESS_TRAINING_SMOKE_OK pieces=32 red_and_black_moves=2")
	quit(0)
