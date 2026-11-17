extends SceneTree

class ScreenFixture:
	extends "res://modules/games/mahjong/guiyang/guiyang_3d_screen.gd"
	var sent: Array[Dictionary] = []
	func _load_quality() -> void:
		super._load_quality()
		_music_enabled = false
	func _connect_socket() -> void: pass
	func _transport_open() -> bool: return true
	func _wire_send(payload: Dictionary) -> Error:
		sent.append(payload.duplicate(true))
		return OK

var failures := 0

func _initialize() -> void: call_deferred("_run")

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var game := ScreenFixture.new()
	game.match_context = {"room_id":"0624","seat_index":0,"kind":"training","rule_set_id":"basic_108","rule_version":"1.0.0"}
	root.add_child(game)
	game._handle_packet(JSON.stringify({"type":"mahjong_joined","room_id":"0624","your_seat":0}))
	var hand: Array = []
	for index in range(14):
		hand.append({"id":index+1,"suit":["wan","tong","tiao"][index%3],"rank":index%9+1})
	var snapshot: Dictionary = {
		"type":"mahjong_state","room_id":"0624","match_id":"round-1","kind":"training","status":"playing","phase":"turn","epoch":1,
		"rule_set_id":"basic_108","rule_version":"1.0.0","rule":{"name":"基础 108","summary":"可点炮 · 不翻鸡","chicken":false,"allow_chi":false,"requires_kong_to_claim":false},
		"your_seat":0,"turn":0,"dealer":0,"players":["me","b1","b2","b3"],"hand":hand,"hand_counts":[14,13,13,13],
		"melds":[[],[],[],[]],"discards":[],"remaining":55,"scores":[0,0,0,0],"options":[{"type":"play"}],
		"connected_seats":[true,true,true,true]
	}
	game._handle_packet(JSON.stringify(snapshot))
	var earlier: Dictionary = snapshot.duplicate(true)
	_expect("基础 108" in game._header.text and "训练" in game._header.text, "基础 108 训练牌桌显示了错误的玩法")
	game._join_board()
	_expect(game.sent[-1].get("match_id", "") == "round-1", "重连应绑定原对局编号")
	game.sent.clear()
	game._select_tile(1)
	game._on_play()
	if game.sent.is_empty() or not game.sent[0].has("command_id") or game.sent[0].get("match_id", "") != "round-1":
		push_error("联网出牌未携带可关联的命令编号")
		game.queue_free()
		await process_frame
		quit(1)
		return
	var id: String = game.sent[0].command_id
	game._handle_packet(JSON.stringify(snapshot))
	_expect(game._pending_action, "在线状态快照错误解除在途操作")
	game._handle_packet(JSON.stringify({"type":"mahjong_action_result","command_id":id,"ok":false,"message":"当前操作未生效"}))
	_expect(not game._pending_action and game._selected_id==1 and "未生效" in game._status.text, "服务器拒绝后未恢复可重试选择")
	game._on_play()
	id = game.sent[-1].command_id
	game._handle_packet(JSON.stringify({"type":"mahjong_action_result","command_id":id,"ok":true}))
	_expect(game._pending_action, "只有回执、没有新牌局快照时过早开放操作")
	hand.remove_at(0)
	snapshot["epoch"]=2
	snapshot["hand"]=hand
	snapshot["turn"]=1
	snapshot["options"]=[]
	game._handle_packet(JSON.stringify(snapshot))
	_expect(not game._pending_action and game._selected_id==0, "收到实际新状态仍未释放确认或清空已打出的牌")
	var confirmed_efficiency: Dictionary = game._coach_results.duplicate(true)
	game._handle_packet(JSON.stringify(earlier))
	_expect(game._state.epoch == 2 and game._hand_models.size() == 13 and game._coach_results == confirmed_efficiency, "旧快照覆盖了已确认的手牌或牌效")
	snapshot.epoch = 3
	snapshot.turn = 0
	snapshot.options = [{"type": "play", "tile_id": 3}]
	hand.append({"id": 41, "suit": "tiao", "rank": 8})
	game._handle_packet(JSON.stringify(snapshot))
	_expect(not ClassDB.class_exists("MahjongCoachBridge") or (game._coach_results.size() == 1 and game._coach_results.has(3)), "牌效未按最新合法实体 ID 更新")
	game._select_tile(2)
	_expect(game._play_button.disabled, "服务器限制的牌仍可点击打出")
	game._select_tile(3)
	_expect(not game._play_button.disabled, "合法实体牌不能打出")
	game.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	if failures==0: print("MAHJONG_RULESET_SCREEN_OK training_title=true command_receipt=true rejection_preserves_selection=true")
	quit(0 if failures==0 else 1)
