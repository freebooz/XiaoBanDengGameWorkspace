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
	screen._set_quality(0)
	if screen._board_viewport.size != Vector2i(700, 630):
		push_error("低画质视口设置失败")
		quit(1)
		return
	screen._set_quality(2)
	if screen._board_viewport.size != Vector2i(1400, 1260):
		push_error("高画质视口设置失败")
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
	if screen._hand_models.size() != 14 or screen._actions_root.get_child_count() != 1 or screen._pieces_root.get_child_count() < 14:
		push_error("三维手牌或打牌按钮未渲染")
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
	training._training_play(1)
	await process_frame
	if training._array("discards").size() != 1 or training._hand_models.size() != 14:
		push_error("训练模式打牌后未补牌")
		quit(1)
		return
	training.queue_free()
	print("MAHJONG_TRAINING_SMOKE_OK")
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
