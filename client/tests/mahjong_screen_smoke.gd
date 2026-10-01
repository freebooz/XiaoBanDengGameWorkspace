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
	print("MAHJONG_BOARD_SIZE=" + str(screen.get_child(1).size))
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
	if screen._hand_root.get_child_count() < 14 or screen._actions_root.get_child_count() != 1:
		push_error("手牌或打牌按钮未渲染")
		quit(1)
		return
	print("MAHJONG_SCREEN_SMOKE_OK hand=14 actions=1")
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
