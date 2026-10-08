extends Control
## Three-dimensional poker table. All live rules and hidden hands come from the server.

signal request_return_to_lobby

const API_SCRIPT = preload("res://modules/foundation/network/api_client.gd")
const STAGE_SCRIPT = preload("res://modules/game_framework/tabletop3d/tabletop_stage.gd")
const TABLE_SCENE = preload("res://modules/game_framework/card3d/assets/models/poker_table.glb")
const CARD_SCENE = preload("res://modules/game_framework/card3d/assets/models/poker_card.glb")
const CARD_ART := "res://modules/game_framework/card3d/assets/cards/"
var quality_file := "user://landlord_visuals.cfg"
var game_protocol := "landlord"
var game_title := "小板凳 · 斗地主"
var seat_count := 3
const QUALITY_SIZES := [Vector2i(700, 790), Vector2i(1050, 1185), Vector2i(1400, 1580)]

var product: Dictionary = {}
var match_context: Dictionary = {}
var training_mode := false
var _socket := WebSocketPeer.new()
var _joined := false
var _state: Dictionary = {}
var _reconnect_wait := 0.0
var _quality := 1
var _viewport: SubViewport
var _board_view: TextureRect
var _stage: Node3D
var _camera: Camera3D
var _cards_root: Node3D
var _hand_nodes: Array[Node3D] = []
var _hand_ids: Array[int] = []
var _selected: Dictionary = {}
var _faces: Dictionary = {}
var _back_material: StandardMaterial3D
var _poker = preload("res://modules/game_framework/card3d/poker_factory.gd").new()
var _seat_layer: Control
var _action_layer: Control
var _overlay_layer: Control
var _status: Label
var _quality_option: OptionButton


func _ready() -> void:
	_load_quality()
	_build_ui()
	_connect_socket()
	set_process(true)


func _exit_tree() -> void:
	_socket.close()


func _load_quality() -> void:
	var config := ConfigFile.new()
	if config.load(quality_file) == OK:
		_quality = clampi(int(config.get_value("rendering", "quality", 1)), 0, 2)


func _set_quality(index: int) -> void:
	_quality = clampi(index, 0, 2)
	_viewport.size = QUALITY_SIZES[_quality]
	_viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_4X, Viewport.MSAA_8X][_quality]
	_stage.get_node("KeyLight").shadow_enabled = _quality > 0
	var config := ConfigFile.new()
	config.set_value("rendering", "quality", _quality)
	config.save(quality_file)


func _style(bg: Color, border: Color, radius: int = 14) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(radius)
	box.shadow_color = Color("#00000088")
	box.shadow_size = 5
	return box


func _label(parent: Node, value: String, x: float, y: float, w: float, h: float, size: int = 20, color: Color = Color("#fff0d6")) -> Label:
	var node := Label.new()
	node.text = value
	node.position = Vector2(x, y)
	node.size = Vector2(w, h)
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	parent.add_child(node)
	return node


func _button(parent: Node, value: String, x: float, y: float, w: float, h: float, action: Callable, accent: Color = Color("#d3aa62")) -> Button:
	var node := Button.new()
	node.text = value
	node.position = Vector2(x, y)
	node.size = Vector2(w, h)
	node.add_theme_font_size_override("font_size", 19)
	node.add_theme_color_override("font_color", Color("#fff4dc"))
	node.add_theme_stylebox_override("normal", _style(Color("#132e2e"), accent))
	node.add_theme_stylebox_override("hover", _style(Color("#1d4945"), Color("#f7d38c")))
	node.pressed.connect(action)
	parent.add_child(node)
	return node


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("#090d0e")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_build_table()
	_label(self, game_title, 20, 15, 460, 58, 31)
	_label(self, "房间 %s" % str(match_context.get("room_id", "")), 490, 20, 205, 47, 17, Color("#d6b06f"))
	_quality_option = OptionButton.new()
	_quality_option.position = Vector2(535, 75)
	_quality_option.size = Vector2(155, 45)
	for title in ["低画质", "中画质", "高画质"]:
		_quality_option.add_item(title)
	_quality_option.select(_quality)
	_quality_option.item_selected.connect(_set_quality)
	add_child(_quality_option)
	_seat_layer = Control.new()
	_seat_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_seat_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_seat_layer)
	_action_layer = Control.new()
	_action_layer.position = Vector2(10, 1065)
	_action_layer.size = Vector2(700, 92)
	add_child(_action_layer)
	_status = _label(self, "正在连接对局……", 32, 1168, 656, 67, 19, Color("#f3cf91"))
	_overlay_layer = Control.new()
	_overlay_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay_layer)
	_label(self, "点击三维手牌可多选 · 出牌由服务端判定", 30, 1235, 660, 35, 15, Color("#aa9271"))


func _build_table() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "Landlord3DViewport"
	_viewport.size = QUALITY_SIZES[_quality]
	_viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_4X, Viewport.MSAA_8X][_quality]
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var world := Node3D.new()
	world.name = "LandlordWorld"
	_viewport.add_child(world)
	_stage = STAGE_SCRIPT.new()
	world.add_child(_stage)
	_camera = _stage.configure(2.0, Vector3(0, 2.58, 1.46), Vector3(0, 0, 0.14), true, 42.0)
	_stage.get_node("Floor").visible = false
	_stage.get_node("KeyLight").shadow_enabled = _quality > 0
	var table := TABLE_SCENE.instantiate()
	table.name = "ImportedPokerTable"
	world.add_child(table)
	_cards_root = Node3D.new()
	_cards_root.name = "ThreeDimensionalCards"
	world.add_child(_cards_root)
	_board_view = TextureRect.new()
	_board_view.name = "Landlord3DTableView"
	_board_view.texture = _viewport.get_texture()
	_board_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_board_view.stretch_mode = TextureRect.STRETCH_SCALE
	_board_view.position = Vector2(10, 210)
	_board_view.size = Vector2(700, 790)
	_board_view.gui_input.connect(_on_board_input)
	add_child(_board_view)


func _connect_socket() -> void:
	_socket = WebSocketPeer.new()
	var api = API_SCRIPT.new()
	var err := _socket.connect_to_url(api.websocket_url())
	if err != OK:
		_status.text = "实时连接失败，正在重试：%s" % str(err)
		_reconnect_wait = 2.0


func _process(delta: float) -> void:
	if _reconnect_wait > 0:
		_reconnect_wait -= delta
		if _reconnect_wait <= 0:
			_connect_socket()
		return
	_socket.poll()
	var ready := _socket.get_ready_state()
	if ready == WebSocketPeer.STATE_OPEN and not _joined:
		_joined = true
		if training_mode:
			_send({"type": game_protocol + "_training_start"})
		else:
			_send({"type": game_protocol + "_join", "room_id": str(match_context.get("room_id", "")), "client_id": str(match_context.get("account_id", ""))})
	if ready == WebSocketPeer.STATE_OPEN:
		while _socket.get_available_packet_count() > 0:
			_handle_packet(_socket.get_packet().get_string_from_utf8())
	elif ready == WebSocketPeer.STATE_CLOSED:
		_joined = false
		_reconnect_wait = 2.0
		_status.text = "连接已断开，正在恢复……"


func _send(payload: Dictionary) -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify(payload))


func _handle_packet(raw: String) -> void:
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY: return
	var kind := str(parsed.get("type", ""))
	if kind == game_protocol + "_joined":
		_status.text = "已入座，等待牌友连接"
	elif kind == game_protocol + "_state":
		_state = parsed
		_render()
	elif kind == game_protocol + "_error":
		_status.text = "操作未生效：" + str(parsed.get("message", "未知错误"))
	elif kind == game_protocol + "_hint":
		_selected.clear()
		for id in parsed.get("card_ids", []): _selected[int(id)] = true
		_update_selected()


func _on_board_input(event: InputEvent) -> void:
	var touch := Vector2.ZERO
	if event is InputEventMouseButton:
		if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
			return
		touch = event.position
	elif event is InputEventScreenTouch:
		if not event.pressed:
			return
		touch = event.position
	else:
		return
	var viewport_point: Vector2 = touch * Vector2(_viewport.size) / _board_view.size
	var best := -1
	var distance := 55.0 * float(_viewport.size.x) / 700.0
	for index in range(_hand_nodes.size()):
		var projected := _camera.unproject_position(_hand_nodes[index].global_position)
		var candidate := viewport_point.distance_to(projected)
		if candidate < distance:
			distance = candidate
			best = index
	if best >= 0:
		var id := _hand_ids[best]
		if _selected.has(id): _selected.erase(id)
		else: _selected[id] = true
		_update_selected()


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		child.queue_free()


func _array(key: String) -> Array:
	var value = _state.get(key, [])
	return value if typeof(value) == TYPE_ARRAY else []


func _card_model(card: Dictionary, location: Vector3, scale_value: float = 1.0, concealed: bool = false) -> Node3D:
	var model: Node3D = _poker.create_card(card, concealed)
	model.position = location
	model.scale = Vector3.ONE * scale_value
	_cards_root.add_child(model)
	return model


func _relative_seat(seat: int) -> int:
	return (seat - int(_state.get("your_seat", 0)) + seat_count) % seat_count


func _render() -> void:
	_clear(_cards_root)
	_clear(_seat_layer)
	_clear(_action_layer)
	_clear(_overlay_layer)
	_hand_nodes.clear()
	_hand_ids.clear()
	var hand: Array = _array("hand")
	var valid := {}
	for card in hand: valid[int(card.get("id", -1))] = true
	for id in _selected.keys():
		if not valid.has(id): _selected.erase(id)
	_render_seats()
	_render_other_hands()
	_render_bottom()
	_render_last_play()
	_render_my_hand()
	_render_actions()
	var phase := str(_state.get("phase", ""))
	if str(_state.get("status", "")) == "waiting":
		_status.text = "等待三位玩家连接 · %d / 3" % int(_state.get("connected_players", 0))
	elif phase == "bid":
		_status.text = "轮到你叫地主" if int(_state.get("turn", -1)) == int(_state.get("your_seat", -2)) else "等待其他玩家叫地主"
	elif phase == "finished":
		_status.text = "本局结束 · 倍数 %d" % int(_state.get("multiplier", 1))
		_render_settlement()
	elif int(_state.get("turn", -1)) == int(_state.get("your_seat", -2)):
		_status.text = "轮到你出牌 · 已选 %d 张 · 倍数 %d" % [_selected.size(), int(_state.get("multiplier", 1))]
	else:
		_status.text = "等待牌友出牌 · 倍数 %d" % int(_state.get("multiplier", 1))
	print("LANDLORD_STATE room=%s phase=%s turn=%s seat=%s hand=%d" % [str(_state.get("room_id", "")), phase, str(_state.get("turn", "")), str(_state.get("your_seat", "")), hand.size()])


func _render_seats() -> void:
	var players := _array("players")
	var counts := _array("hand_counts")
	for seat in range(mini(3, players.size())):
		var relative := _relative_seat(seat)
		var position: Vector2 = [Vector2(125, 1005), Vector2(465, 127), Vector2(15, 127)][relative]
		var title := "我" if relative == 0 else "牌友"
		var role := "地主" if seat == int(_state.get("landlord", -1)) else "农民"
		var name := str(players[seat]).right(8)
		var count := int(counts[seat]) if seat < counts.size() else 0
		var text_value := "%s · %s · %s · %d张" % [title, name, role, count]
		var label := _label(_seat_layer, text_value, position.x, position.y, 330 if relative == 0 else 230, 52, 17)
		if seat == int(_state.get("turn", -1)):
			label.add_theme_color_override("font_color", Color("#ffd36f"))
	var bid := int(_state.get("highest_bid", 0))
	_label(_seat_layer, "叫分 %d  ·  倍数 %d" % [bid, int(_state.get("multiplier", 1))], 245, 174, 230, 30, 16, Color("#dfbb79"))


func _render_other_hands() -> void:
	var counts := _array("hand_counts")
	for seat in range(mini(3, counts.size())):
		var relative := _relative_seat(seat)
		if relative == 0: continue
		var count := mini(int(counts[seat]), 12)
		for index in range(count):
			var along := (float(index) - float(count-1)/2.0) * 0.037
			var x := -0.56 if relative == 2 else 0.56
			var card := _card_model({}, Vector3(x, -0.0218, along-0.13), 1.0, true)
			card.rotation.y = -0.15 if relative == 2 else 0.15


func _render_bottom() -> void:
	var bottom := _array("bottom")
	if bottom.is_empty():
		for index in range(3): _card_model({}, Vector3((index-1)*0.10, -0.0215, -0.34), 1.2, true)
	else:
		for index in range(bottom.size()): _card_model(bottom[index], Vector3((index-1)*0.11, -0.0215, -0.34), 1.2)


func _render_last_play() -> void:
	if not bool(_state.get("has_last_play", false)): return
	var last: Dictionary = _state.get("last_play", {})
	var cards: Array = last.get("cards", [])
	for index in range(cards.size()):
		var along := (float(index) - float(cards.size()-1)/2.0) * minf(0.078, 0.85/maxf(1.0,float(cards.size())))
		_card_model(cards[index], Vector3(along, -0.0215+index*0.0001, -0.04), 1.3)
	_label(_seat_layer, "上手 %s" % str(last.get("pattern", {}).get("kind", "")), 205, 682, 310, 32, 15, Color("#ead1a7"))


func _render_my_hand() -> void:
	var hand := _array("hand")
	for index in range(hand.size()):
		var card: Dictionary = hand[index]
		var id := int(card.get("id", -1))
		var along := (float(index)-float(hand.size()-1)/2.0) * minf(0.062,1.08/maxf(1.0,float(hand.size())))
		var model := _card_model(card, Vector3(along, -0.010 if _selected.has(id) else -0.0215, 0.54), 1.62)
		_hand_nodes.append(model)
		_hand_ids.append(id)


func _update_selected() -> void:
	for index in range(_hand_nodes.size()):
		_hand_nodes[index].position.y = -0.010 if _selected.has(_hand_ids[index]) else -0.0215
	_status.text = "已选 %d 张 · 点击出牌提交" % _selected.size()


func _render_actions() -> void:
	if training_mode:
		_button(_action_layer, "返回大厅", 10, 0, 145, 74, func(): request_return_to_lobby.emit())
	if str(_state.get("status", "")) != "playing": return
	if int(_state.get("turn", -1)) != int(_state.get("your_seat", -2)): return
	if str(_state.get("phase", "")) == "bid":
		var high := int(_state.get("highest_bid", 0))
		_button(_action_layer, "不叫", 170, 0, 115, 74, _send_bid.bind(0))
		for amount in range(high+1, 4):
			_button(_action_layer, "%d分" % amount, 170+(amount-high)*120, 0, 110, 74, _send_bid.bind(amount))
	elif str(_state.get("phase", "")) == "play":
		_button(_action_layer, "重选", 170, 0, 115, 74, _clear_selection)
		if bool(_state.get("has_last_play", false)):
			_button(_action_layer, "不出", 305, 0, 115, 74, _send_pass)
		_button(_action_layer, "出牌", 450, 0, 225, 74, _send_play, Color("#e4bd70"))


func _clear_selection() -> void:
	_selected.clear()
	_update_selected()


func _send_bid(amount: int) -> void:
	_send({"type":game_protocol + "_action", "action":"bid", "amount":amount})


func _send_pass() -> void:
	_send({"type":game_protocol + "_action", "action":"pass"})


func _send_play() -> void:
	if _selected.is_empty():
		_status.text = "请先点击桌上的三维手牌"
		return
	var ids: Array[int] = []
	for id in _selected.keys(): ids.append(int(id))
	_send({"type":game_protocol + "_action", "action":"play", "card_ids":ids})


func _render_settlement() -> void:
	var panel := Panel.new()
	panel.position = Vector2(90, 345)
	panel.size = Vector2(540, 400)
	panel.add_theme_stylebox_override("panel", _style(Color("#102825f4"), Color("#e3b663"), 24))
	_overlay_layer.add_child(panel)
	var winner := int(_state.get("winner", -1))
	var landlord := int(_state.get("landlord", -1))
	_label(panel, "本局结算", 20, 25, 500, 65, 34)
	_label(panel, "地主胜利" if winner == landlord else "农民胜利", 30, 103, 480, 60, 26, Color("#f8d488"))
	var scores := _array("scores")
	for seat in range(mini(3, scores.size())):
		_label(panel, "%d 号位    %+d 分" % [seat+1, int(scores[seat])], 40, 173+seat*43, 460, 40, 21)
	_button(panel, "返回大厅", 150, 326, 240, 55, func(): request_return_to_lobby.emit())
