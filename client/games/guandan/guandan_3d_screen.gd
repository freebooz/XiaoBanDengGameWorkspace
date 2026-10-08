extends "res://modules/game_framework/card3d/poker_screen.gd"
## 掼蛋使用统一扑克工厂，仅负责四人搭档布局和掼蛋操作。

var _leave_requested := false
var leave_on_join := false
var _exchange_marker_material: StandardMaterial3D

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
	_back_button.text = "返回大厅" if training_mode else "离开牌桌"
	var phase := str(_state.get("phase", ""))
	_instruction.text = "轻触手牌选中 · 对坐为搭档 · 红桃级牌可作配牌"
	if str(_state.get("status", "")) == "waiting":
		_status.text = "等待四名牌友连接 · %d / 4" % int(_state.get("connected_players", 0))
	elif phase == "tribute":
		_status.text = "请选择一张进贡牌" if not _array("eligible_card_ids").is_empty() else "等待牌友进贡"
		_instruction.text = "金色标记为可进贡牌 · 最大的非红桃级牌"
	elif phase == "return":
		_status.text = "请选择一张还贡牌" if not _array("eligible_card_ids").is_empty() else "等待牌友还贡"
		_instruction.text = "金色标记为可还贡牌 · 不大于 10 的非配牌"
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
	var titles := ["我", "下家", "搭档", "上家"]
	for seat in range(mini(4, players.size())):
		var relative := _relative_seat(seat)
		var count := int(counts[seat]) if seat < counts.size() else 0
		var active := seat == int(_state.get("turn", -1)) and str(_state.get("phase", "")) == "play"
		var relation := "我方" if relative % 2 == 0 else "对手"
		var player_title := "%s · %s" % [titles[relative], str(players[seat]).right(6)] if relative % 2 == 0 else "%s对手" % titles[relative]
		var detail := "%s  ·  %d 张%s" % [relation, count, "  ·  行动中" if active else ""] if relative % 2 == 0 else "%s\n%d 张" % [str(players[seat]).right(6), count]
		CHROME.player(_seat_layer, player_title, detail, _seat_rect(relative), active, seat)
	var level := _rank_name(int(_state.get("level_rank", 2)))
	var levels := _array("team_levels")
	var mine := int(_state.get("your_seat", 0)) % 2
	var progress := ""
	if levels.size() == 2: progress = " · 我方%s / 对方%s" % [_rank_name(int(levels[mine])), _rank_name(int(levels[1-mine]))]
	var info_y := _seat_rect(3).end.y + 18
	_label(_seat_layer, "第 %d 副   ·   打 %s" % [int(_state.get("round", 1)), level], 28, info_y, 200, 32, 20, Color("#dfbb79"))
	_label(_seat_layer, "红桃 %s 配牌" % level, 28, info_y + 38, 200, 30, 17, Color("#dfbb79"))
	_label(_seat_layer, progress.trim_prefix(" · "), 28, info_y + 76, 200, 30, 16, Color("#9badab"))

func _render_other_hands() -> void:
	var counts := _array("hand_counts")
	for seat in range(mini(4, counts.size())):
		var relative := _relative_seat(seat)
		if relative == 0: continue
		var count := mini(int(counts[seat]), 9)
		for index in range(count):
			var along := (float(index)-float(count-1)/2.0)*0.040
			var stack_y := -0.016+index*0.0007
			var location := Vector3(along, stack_y, -0.59)
			if relative == 1: location = Vector3(0.84, stack_y, along-0.16)
			elif relative == 3: location = Vector3(-0.84, stack_y, along-0.16)
			var model := _card_model({}, location, 1.15, true)
			if relative != 2: model.rotation.y = PI * 0.5 if relative == 1 else -PI * 0.5

func _render_bottom() -> void:
	pass

func _render_last_play() -> void:
	if not bool(_state.get("has_last_play", false)): return
	var last: Dictionary = _state.get("last_play", {})
	var cards: Array = last.get("cards", [])
	var first_row := mini(14, cards.size())
	for index in range(cards.size()):
		var row := 0 if index < first_row else 1
		var column := index if row == 0 else index - first_row
		var count := first_row if row == 0 else cards.size() - first_row
		var along := (float(column)-float(count-1)/2.0)*minf(0.094,1.12/maxf(1.0,float(count-1)))
		_card_model(cards[index], Vector3(along, -0.014+column*0.0005, -0.13+row*0.18), 1.55)
	var point := _table_point(Vector3(0, 0, -0.13))
	_label(_seat_layer, "上手 · " + _pattern_name(str(last.get("pattern", {}).get("kind", ""))), point.x - 190, point.y - 66, 380, 28, 17, Color("#efcf99"))

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
		var along := (float(column)-float(count-1)/2.0)*0.114
		var rest_y := 0.022+column*0.0008
		var model := _card_model(card, Vector3(along, rest_y+(0.075 if _selected.has(id) else 0.0), 0.29+row*0.28), 2.35)
		model.rotation.x = deg_to_rad(15.0)
		model.set_meta("rest_y", rest_y)
		model.set_meta("card_id", id)
		model.set_meta("wild", str(card.get("suit", "")) == "heart" and (2 if int(card.get("rank", 0)) == 15 else int(card.get("rank", 0))) == int(_state.get("level_rank", 2)))
		if _array("eligible_card_ids").has(id) and str(_state.get("phase", "")) in ["tribute", "return"]:
			_add_exchange_marker(model)
		_hand_nodes.append(model)
		_hand_ids.append(id)

func _update_selected() -> void:
	for index in range(_hand_nodes.size()):
		_hand_nodes[index].position.y = float(_hand_nodes[index].get_meta("rest_y"))+ (0.075 if _selected.has(_hand_ids[index]) else 0.0)
	var phase := str(_state.get("phase", ""))
	var action := "进贡" if phase == "tribute" else ("还贡" if phase == "return" else "出牌")
	_status.text = "已选 %d 张 · 点击%s提交" % [_selected.size(), action]

func _add_exchange_marker(model: Node3D) -> void:
	if _exchange_marker_material == null:
		_exchange_marker_material = StandardMaterial3D.new()
		_exchange_marker_material.albedo_color = Color("#f7ce72")
		_exchange_marker_material.emission_enabled = true
		_exchange_marker_material.emission = Color("#d5a649")
		_exchange_marker_material.emission_energy_multiplier = 0.4
	var marker := MeshInstance3D.new()
	marker.name = "EligibleExchangeMark"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.063, 0.0005, 0.005)
	marker.mesh = mesh
	marker.position = Vector3(0, 0.0012, -0.040)
	marker.material_override = _exchange_marker_material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(marker)

func _render_actions() -> void:
	var phase := str(_state.get("phase", ""))
	if str(_state.get("status", "")) != "playing": return
	if phase == "tribute" or phase == "return":
		if not _array("eligible_card_ids").is_empty():
			_action_heading("请选择一张牌")
			_action_button("重选", 0, 2, _clear_selection)
			_action_button("确认进贡" if phase == "tribute" else "确认还贡", 1, 2, _submit_exchange.bind(phase), true)
		else: _action_heading("等待贡还完成")
		return
	if phase != "play": return
	if int(_state.get("turn", -1)) != int(_state.get("your_seat", -2)):
		_action_heading("等待牌友行动")
		return
	var may_pass := bool(_state.get("has_last_play", false)) and int(_state.get("last_play", {}).get("seat", -1)) != int(_state.get("your_seat", -2))
	var total := 4 if may_pass else 3
	_action_heading("轮到你出牌")
	_action_button("提示", 0, total, func(): _send({"type":"guandan_action", "action":"hint"}))
	_action_button("重选", 1, total, _clear_selection)
	if may_pass: _action_button("不出", 2, total, _send_pass)
	_action_button("出牌", total - 1, total, _send_play, true)

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
		_return_now()
		return
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_leave_requested = true
		_send({"type":"guandan_action", "action":"leave"})
	else: _status.text = "连接恢复后可离开房间"

func _return_after_leave() -> void:
	_return_now()

func _render_settlement() -> void:
	var panel := _modal_panel(Vector2(784, 446))
	var match_finished := str(_state.get("phase", "")) == "finished"
	_label(panel, "本场结束" if match_finished else "本副结算", 24, 22, 736, 52, 32)
	var winner := int(_state.get("match_winner" if match_finished else "round_winner", -1))
	var my_team := int(_state.get("your_seat", 0)) % 2
	var summary := "我方获胜" if winner == my_team else "对方获胜"
	if winner < 0: summary = str(_state.get("reason", "本场已结束"))
	elif not match_finished: summary += " · 升 %d 级" % int(_state.get("round_advance", 1))
	_label(panel, summary, 24, 88, 736, 46, 27, Color("#f8d488"))
	var order := _array("finish_order")
	for index in range(mini(order.size(), 4)):
		var seat := int(order[index])
		var tile := Panel.new()
		tile.position = Vector2(32 + index * 182, 164)
		tile.size = Vector2(172, 116)
		tile.add_theme_stylebox_override("panel", _style(Color("#19362f"), Color("#496254")))
		panel.add_child(tile)
		_label(tile, ["头游", "二游", "三游", "末游"][index], 8, 10, 156, 32, 23, Color("#f8d488"))
		_label(tile, "%d 号位 · %s" % [seat + 1, "我方" if seat % 2 == my_team else "对方"], 8, 51, 156, 48, 18)
	if not match_finished:
		var ready := _array("round_ready")
		var mine := int(_state.get("your_seat", 0))
		var ready_count := 0
		for value in ready:
			if bool(value): ready_count += 1
		_label(panel, "下一副准备 %d / 4" % ready_count, 24, 296, 736, 30, 18, Color("#9badab"))
		var button := _button(panel, "已准备" if ready.size() > mine and bool(ready[mine]) else "下一副", 414, 350, 324, 64, func(): _send({"type":"guandan_action", "action":"next_round"}), true)
		button.disabled = ready.size() > mine and bool(ready[mine])
		_button(panel, "返回大厅", 46, 350, 324, 64, _request_leave)
	else: _button(panel, "返回大厅", 242, 350, 300, 64, _return_after_leave, true)
