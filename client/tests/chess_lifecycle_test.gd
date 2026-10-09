extends SceneTree
## 使用真实棋盘脚本验证等待交互和跨房间消息；在组合后的象棋工程中运行。

func _initialize() -> void:
	var screen = load("res://modules/games/chinese_chess/chinese_chess_3d_screen.gd").new()
	var status := Label.new()
	screen._status_label = status
	screen._handle_message(JSON.stringify({
		"type": "chess_joined", "room_id": "another-room", "your_color": "black"
	}))
	if screen._joined or screen._your_color != "":
		printerr("其他房间加入确认不应改变当前身份")
		status.free()
		screen.free()
		quit(1)
		return
	screen._joined = true
	screen._your_color = "red"
	screen._turn = "red"
	screen._room_status = "waiting"
	screen._pieces_by_pos[Vector2i(0, 6)] = {"id": "red_soldier_0", "color": "red", "type": "soldier"}
	screen._on_board_pressed(Vector2i(0, 6))
	if screen._selected != Vector2i(-1, -1):
		printerr("等待对手期间不应选择棋子")
		status.free()
		screen.free()
		quit(1)
		return
	screen._handle_message(JSON.stringify({
		"type": "chess_state", "room_id": "another-room",
		"turn": "black", "your_color": "black", "status": "playing", "pieces": []
	}))
	if screen._turn != "red" or screen._your_color != "red" or screen._pieces_by_pos.size() != 1:
		printerr("其他房间快照不应改变当前棋盘")
		status.free()
		screen.free()
		quit(1)
		return
	status.free()
	screen.free()
	print("Chess lifecycle checks passed")
	quit(0)
