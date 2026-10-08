extends "res://modules/game_framework/card3d/poker_screen.gd"
## 掼蛋使用统一扑克工厂，仅负责四人搭档布局和掼蛋操作。

var _leave_requested := false
var leave_on_join := false

func _init() -> void:
	game_protocol = "guandan"
	game_title = "小板凳 · 掼蛋"
	seat_count = 4
	quality_file = "user://guandan_visuals.cfg"

func _handle_packet(raw: String) -> void:
	super._handle_packet(raw)
	if leave_on_join and not _state.is_empty():
		leave_on_join = false
		_request_leave()

func _rank_name(rank: int) -> String:
	match rank:
		11: return "J"
		12: return "Q"
		13: return "K"
		14: return "A"
	return str(rank)

func _pattern_name(kind: String) -> String:
	return {"single":"单张", "pair":"对子", "triple":"三张", "triple_pair":"三带对", "straight":"顺子", "pair_straight":"三连对", "triple_straight":"钢板", "bomb":"炸弹", "straight_flush":"同花顺", "rocket":"四王炸"}.get(kind, kind)

func _render() -> void:
	_clear(_cards_root)
	_clear(_seat_layer)
	_clear(_action_layer)
	_clear(_overlay_layer)
	_hand_nodes.clear()
	_hand_ids.clear()
	var owned := {}
	for card in _array("hand"): owned[int(card.get("id", -1))] = true
	for id in _selected.keys():
		if not owned.has(id): _selected.erase(id)
	_render_seats()
	_render_other_hands()
	_render_last_play()
	_render_my_hand()
	_render_actions()
	var phase := str(_state.get("phase", ""))
	if str(_state.get("status", "")) == "waiting":
		_status.text = "等待四名牌友连接 · %d / 4" % int(_state.get("connected_players", 0))
	elif phase == "tribute": _status.text = "进贡：选最大的非红桃级牌" if not _array("eligible_card_ids").is_empty() else "等待牌友进贡"
	elif phase == "return": _status.text = "还贡：选不大于10的非配牌" if not _array("eligible_card_ids").is_empty() else "等待牌友还贡"
	elif phase == "round_finished" or phase == "finished":
		_render_settlement()
		_status.text = "本副结算 · 四人准备后开始下一副" if phase == "round_finished" else str(_state.get("reason", "本场结束"))
		if _leave_requested: call_deferred("_return_after_leave")
	elif int(_state.get("turn", -1)) == int(_state.get("your_seat", -2)):
		_status.text = "轮到你出牌 · 选牌后点击出牌"
	else: _status.text = "等待牌友出牌 · 对坐是你的搭档"
	print("GUANDAN_STATE room=%s phase=%s round=%s turn=%s seat=%s hand=%d" % [str(_state.get("room_id", "")), phase, str(_state.get("round", "")), str(_state.get("turn", "")), str(_state.get("your_seat", "")), _hand_nodes.size()])

func _render_seats() -> void:
	var players := _array("players")
	var counts := _array("hand_counts")
	var places := [Vector2(125, 1005), Vector2(480, 126), Vector2(240, 126), Vector2(5, 126)]
	var widths := [330.0, 230.0, 240.0, 230.0]
	var titles := ["我", "下家 · 对手", "搭档", "上家 · 对手"]
	for seat in range(mini(4, players.size())):
		var relative := _relative_seat(seat)
		var pos: Vector2 = places[relative]
		var count := int(counts[seat]) if seat < counts.size() else 0
		var label := _label(_seat_layer, "%s · %s\n%d 张" % [titles[relative], str(players[seat]).right(6), count], pos.x, pos.y, widths[relative], 52, 16)
		if seat == int(_state.get("turn", -1)) and str(_state.get("phase", "")) == "play": label.add_theme_color_override("font_color", Color("#ffd36f"))
	var level := _rank_name(int(_state.get("level_rank", 2)))
	var levels := _array("team_levels")
	var mine := int(_state.get("your_seat", 0)) % 2
	var progress := ""
	if levels.size() == 2: progress = " · 我方%s / 对方%s" % [_rank_name(int(levels[mine])), _rank_name(int(levels[1-mine]))]
	_label(_seat_layer, "第%d副 · 打%s · 红桃%s配牌%s" % [int(_state.get("round", 1)), level, level, progress], 15, 181, 690, 28, 16, Color("#dfbb79"))

func _render_other_hands() -> void:
	var counts := _array("hand_counts")
	for seat in range(mini(4, counts.size())):
		var relative := _relative_seat(seat)
		if relative == 0: continue
		var count := mini(int(counts[seat]), 9)
		for index in range(count):
			var along := (float(index)-float(count-1)/2.0)*0.047
			var stack_y := -0.0218+index*0.0014
			var location := Vector3(along, stack_y, -0.64)
			if relative == 1: location = Vector3(0.56, stack_y, along-0.10)
			elif relative == 3: location = Vector3(-0.56, stack_y, along-0.10)
			var model := _card_model({}, location, 1.0, true)
			if relative != 2: model.rotation.y = 0.12 if relative == 1 else -0.12

func _render_bottom() -> void:
	pass

func _render_last_play() -> void:
	if not bool(_state.get("has_last_play", false)): return
	var last: Dictionary = _state.get("last_play", {})
	var cards: Array = last.get("cards", [])
	for index in range(cards.size()):
		var along := (float(index)-float(cards.size()-1)/2.0)*minf(0.078,0.85/maxf(1.0,float(cards.size())))
		_card_model(cards[index], Vector3(along, -0.0215+index*0.0018, -0.09), 1.30)
	_label(_seat_layer, "上手：" + _pattern_name(str(last.get("pattern", {}).get("kind", ""))), 210, 566, 300, 32, 17, Color("#efcf99"))

func _render_my_hand() -> void:
	var hand := _array("hand")
	var first_row := mini(14, int(ceil(float(hand.size())/2.0)))
	if hand.size() <= 14: first_row = hand.size()
	for index in range(hand.size()):
		var row := 0 if index < first_row else 1
		var column := index if row == 0 else index-first_row
		var count := first_row if row == 0 else hand.size()-first_row
		var card: Dictionary = hand[index]
		var id := int(card.get("id", -1))
		var along := (float(column)-float(count-1)/2.0)*0.093
		var rest_y := 0.020+column*0.0034
		var model := _card_model(card, Vector3(along, rest_y+0.05 if _selected.has(id) else rest_y, 0.34+row*0.31), 2.45)
		model.rotation.x = deg_to_rad(12.0)
		model.set_meta("rest_y", rest_y)
		model.set_meta("card_id", id)
		model.set_meta("wild", str(card.get("suit", "")) == "heart" and (2 if int(card.get("rank", 0)) == 15 else int(card.get("rank", 0))) == int(_state.get("level_rank", 2)))
		_hand_nodes.append(model)
		_hand_ids.append(id)

func _update_selected() -> void:
	for index in range(_hand_nodes.size()):
		_hand_nodes[index].position.y = float(_hand_nodes[index].get_meta("rest_y"))+ (0.05 if _selected.has(_hand_ids[index]) else 0.0)
	_status.text = "已选 %d 张 · 点击出牌提交" % _selected.size()

func _render_actions() -> void:
	_button(_action_layer, "返回大厅" if training_mode else "离开", 5, 0, 125, 74, _request_leave)
	var phase := str(_state.get("phase", ""))
	if str(_state.get("status", "")) != "playing": return
	if phase == "tribute" or phase == "return":
		if not _array("eligible_card_ids").is_empty():
			_button(_action_layer, "重选", 170, 0, 120, 74, _clear_selection)
			_button(_action_layer, "进贡" if phase == "tribute" else "还贡", 435, 0, 245, 74, _submit_exchange.bind(phase))
		return
	if phase != "play" or int(_state.get("turn", -1)) != int(_state.get("your_seat", -2)): return
	_button(_action_layer, "提示", 140, 0, 115, 74, func(): _send({"type":"guandan_action", "action":"hint"}))
	_button(_action_layer, "重选", 270, 0, 115, 74, _clear_selection)
	if bool(_state.get("has_last_play", false)): _button(_action_layer, "不出", 400, 0, 115, 74, _send_pass)
	_button(_action_layer, "出牌", 530, 0, 155, 74, _send_play)

func _submit_exchange(kind: String) -> void:
	if _selected.size() != 1:
		_status.text = "请选择一张贡牌或还牌"
		return
	var id := int(_selected.keys()[0])
	if not _array("eligible_card_ids").has(id):
		_status.text = "所选牌不符合贡还规则，请重新选择"
		return
	_send({"type":"guandan_action", "action":kind, "card_id":id})

func _request_leave() -> void:
	if training_mode:
		request_return_to_lobby.emit()
		return
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_leave_requested = true
		_send({"type":"guandan_action", "action":"leave"})
	else: _status.text = "连接恢复后可离开房间"

func _return_after_leave() -> void:
	request_return_to_lobby.emit()

func _render_settlement() -> void:
	var panel := Panel.new()
	panel.position = Vector2(65, 365)
	panel.size = Vector2(590, 410)
	panel.add_theme_stylebox_override("panel", _style(Color("#102825f4"), Color("#e3b663"), 24))
	_overlay_layer.add_child(panel)
	var match_finished := str(_state.get("phase", "")) == "finished"
	_label(panel, "本场结束" if match_finished else "本副结算", 20, 18, 550, 60, 32)
	var winner := int(_state.get("match_winner" if match_finished else "round_winner", -1))
	var my_team := int(_state.get("your_seat", 0)) % 2
	var summary := "我方获胜" if winner == my_team else "对方获胜"
	if not match_finished: summary += " · 升%d级" % int(_state.get("round_advance", 1))
	_label(panel, summary, 25, 88, 540, 55, 26, Color("#f8d488"))
	var order := _array("finish_order")
	for index in range(order.size()):
		var seat := int(order[index])
		_label(panel, "%s：%d号位 · %s" % [["头游", "二游", "三游", "末游"][index], seat+1, "我方" if seat%2 == my_team else "对方"], 45, 148+index*36, 500, 34, 19)
	if not match_finished:
		var ready := _array("round_ready")
		var mine := int(_state.get("your_seat", 0))
		var button := _button(panel, "已准备" if ready.size() > mine and bool(ready[mine]) else "下一副", 315, 326, 220, 60, func(): _send({"type":"guandan_action", "action":"next_round"}))
		button.disabled = ready.size() > mine and bool(ready[mine])
	_button(panel, "返回大厅", 55, 326, 220, 60, _request_leave if not match_finished else _return_after_leave)
