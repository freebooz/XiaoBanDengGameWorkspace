extends Control
## Three-dimensional poker table. All live rules and hidden hands come from the server.

signal request_return_to_lobby
signal hint_received(card_ids: Array)

const API_SCRIPT = preload("res://modules/foundation/network/api_client.gd")
const STAGE_SCRIPT = preload("res://modules/game_framework/tabletop3d/tabletop_stage.gd")
const DISPLAY = preload("res://modules/foundation/ui/battle_display.gd")
const CHROME = preload("res://modules/foundation/ui/battle_chrome.gd")
const TABLE_SCENE = preload("res://modules/game_framework/card3d/assets/models/poker_table.glb")
const CARD_SCENE = preload("res://modules/game_framework/card3d/assets/models/poker_card.glb")
const CARD_ART := "res://modules/game_framework/card3d/assets/cards/"
var quality_file := "user://landlord_visuals.cfg"
var game_protocol := "landlord"
var game_title := "小板凳 · 斗地主"
var seat_count := 3
const QUALITY_SIZES := [Vector2i(900, 500), Vector2i(1350, 750), Vector2i(1800, 1000)]

var product: Dictionary = {}
var match_context: Dictionary = {}
var training_mode := false
var _socket := WebSocketPeer.new()
var _joined := false
var _join_sent := false
var _fresh_state := false
var _last_send_error: Error = OK
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
var _back_button: Button
var _instruction: Label
var _table_rect := Rect2(116, 102, 1098, 610)
var _menu_open := false
var _exiting := false


func _ready() -> void:
	DISPLAY.enter(self)
	_load_quality()
	_build_ui()
	resized.connect(_layout_ui)
	call_deferred("_layout_ui")
	_connect_socket()
	set_process(true)


func _exit_tree() -> void:
	_exiting = true
	if resized.is_connected(_layout_ui): resized.disconnect(_layout_ui)
	_socket.close()
	DISPLAY.leave(self)


func _load_quality() -> void:
	var config := ConfigFile.new()
	if config.load(quality_file) == OK:
		_quality = clampi(int(config.get_value("rendering", "quality", 1)), 0, 2)


func _set_quality(index: int) -> void:
	_quality = clampi(index, 0, 2)
	_viewport.size = QUALITY_SIZES[_quality]
	_viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_4X, Viewport.MSAA_8X][_quality]
	_stage.get_node("KeyLight").shadow_enabled = _quality > 0
	_stage.get_node("KeyLight").directional_shadow_max_distance = 5.0
	_stage.get_node("KeyLight").shadow_bias = 0.01
	_stage.get_node("KeyLight").shadow_normal_bias = 0.1
	var config := ConfigFile.new()
	config.set_value("rendering", "quality", _quality)
	config.save(quality_file)


func _style(bg: Color, border: Color, radius: int = 14) -> StyleBoxFlat:
	return CHROME.style(bg, border, radius)


func _label(parent: Node, value: String, x: float, y: float, w: float, h: float, size: int = 20, color: Color = Color("#fff0d6")) -> Label:
	return CHROME.label(parent, value, Rect2(x, y, w, h), size, color)


func _button(parent: Node, value: String, x: float, y: float, w: float, h: float, action: Callable, primary: bool = false, danger: bool = false) -> Button:
	var node := Button.new()
	node.text = value
	node.position = Vector2(x, y)
	node.size = Vector2(w, h)
	CHROME.skin_button(node, primary, danger)
	node.pressed.connect(action)
	parent.add_child(node)
	return node


func _build_ui() -> void:
	CHROME.backdrop(self, game_title, str(match_context.get("room_id", "")))
	_build_table()
	_quality_option = OptionButton.new()
	_quality_option.size = Vector2(148, 44)
	for title in ["低画质", "中画质", "高画质"]:
		_quality_option.add_item(title)
	_quality_option.select(_quality)
	_quality_option.item_selected.connect(_set_quality)
	CHROME.skin_button(_quality_option)
	_quality_option.add_theme_font_size_override("font_size", 18)
	add_child(_quality_option)
	_back_button = _button(self, "返回大厅" if training_mode else "牌桌菜单", 0, 22, 160, 44, _request_leave)
	_back_button.add_theme_font_size_override("font_size", 18)
	_seat_layer = Control.new()
	_seat_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_seat_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_seat_layer)
	_action_layer = Control.new()
	_action_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_action_layer)
	_status = _label(self, "正在连接对局……", 0, 0, 700, 36, 21, Color("#f3cf91"))
	_instruction = _label(self, "轻触手牌选中 · 再次轻触取消", 0, 0, 700, 25, 15, Color("#9badab"))
	_overlay_layer = Control.new()
	_overlay_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay_layer)
	_layout_ui()


func _canvas_size() -> Vector2:
	return size if size.x > 0 and size.y > 0 else Vector2(1440, 810)


func _layout_ui() -> void:
	if _exiting or not is_inside_tree() or _board_view == null or _status == null: return
	if _camera == null or not _camera.is_inside_tree(): return
	var canvas := _canvas_size()
	var available := Vector2(canvas.x - 342, canvas.y - 184)
	var width := minf(available.x, available.y * 1.8)
	var board_size := Vector2(width, width / 1.8)
	_table_rect = Rect2(Vector2(116 + (available.x - width) * 0.5, 102 + (available.y - board_size.y) * 0.5), board_size)
	_board_view.position = _table_rect.position
	_board_view.size = _table_rect.size
	_quality_option.position = Vector2(canvas.x - 352, 22)
	_back_button.position = Vector2(canvas.x - 188, 22)
	_action_layer.position = Vector2(canvas.x - 216, canvas.y - 424)
	_action_layer.size = Vector2(188, 308)
	_status.position = Vector2(324, canvas.y - 83)
	_status.size = Vector2(canvas.x - 582, 36)
	_instruction.position = Vector2(324, canvas.y - 45)
	_instruction.size = Vector2(canvas.x - 582, 25)
	if not _state.is_empty(): _render()


func _seat_rect(relative: int) -> Rect2:
	var canvas := _canvas_size()
	match relative:
		0: return Rect2(28, canvas.y - 87, 276, 68)
		1: return Rect2(canvas.x - 228, 234 + (canvas.y - 810) * 0.3, 200, 88)
		2:
			if seat_count == 4: return Rect2(_table_rect.get_center().x - 142, 102, 284, 74)
	return Rect2(28, 234 + (canvas.y - 810) * 0.3, 200, 88)


func _table_point(location: Vector3) -> Vector2:
	if _camera == null or not _camera.is_inside_tree(): return _table_rect.get_center()
	return _table_rect.position + _camera.unproject_position(location) / Vector2(_viewport.size) * _table_rect.size


func _action_button(value: String, index: int, total: int, action: Callable, primary: bool = false) -> Button:
	return _button(_action_layer, value, 0, _action_layer.size.y - total * 72 + index * 72, _action_layer.size.x, 62, action, primary)


func _action_heading(value: String) -> void:
	_label(_action_layer, value, 0, -40, _action_layer.size.x, 32, 19, Color("#deb879"))


func _build_table() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "Poker3DViewport"
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.size = QUALITY_SIZES[_quality]
	_viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_4X, Viewport.MSAA_8X][_quality]
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var world := Node3D.new()
	world.name = "PokerWorld"
	_viewport.add_child(world)
	_stage = STAGE_SCRIPT.new()
	world.add_child(_stage)
	_camera = _stage.configure(2.5, Vector3(0, 2.65, 1.65), Vector3(0, 0, 0.06), true, 47.0)
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_stage.get_node("WorldEnvironment").environment.background_color = Color("#08141100")
	_stage.get_node("Floor").visible = false
	_stage.get_node("KeyLight").shadow_enabled = _quality > 0
	_stage.get_node("KeyLight").directional_shadow_max_distance = 5.0
	_stage.get_node("KeyLight").shadow_bias = 0.01
	_stage.get_node("KeyLight").shadow_normal_bias = 0.1
	var table := TABLE_SCENE.instantiate()
	table.name = "ImportedPokerTable"
	table.rotation.y = PI * 0.5
	world.add_child(table)
	_cards_root = Node3D.new()
	_cards_root.name = "ThreeDimensionalCards"
	world.add_child(_cards_root)
	_board_view = TextureRect.new()
	_board_view.name = "Poker3DTableView"
	_board_view.texture = _viewport.get_texture()
	_board_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_board_view.stretch_mode = TextureRect.STRETCH_SCALE
	_board_view.position = _table_rect.position
	_board_view.size = _table_rect.size
	_board_view.gui_input.connect(_on_board_input)
	add_child(_board_view)


func _connect_socket() -> void:
	_socket = WebSocketPeer.new()
	_socket.inbound_buffer_size = 256 * 1024
	_socket.outbound_buffer_size = 256 * 1024
	_joined = false
	_join_sent = false
	_fresh_state = false
	_refresh_connection_actions()
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
	if ready != WebSocketPeer.STATE_OPEN and (_joined or _fresh_state):
		_joined = false
		_join_sent = false
		_fresh_state = false
		_refresh_connection_actions()
		_status.text = "连接已中断，正在恢复……"
	if ready == WebSocketPeer.STATE_OPEN and not _join_sent:
		_join_sent = true
		if training_mode:
			_send({"type": game_protocol + "_training_start"})
		else:
			_send({"type": game_protocol + "_join", "room_id": str(match_context.get("room_id", "")), "client_id": str(match_context.get("account_id", ""))})
		if _last_send_error != OK: _join_sent = false
	if ready == WebSocketPeer.STATE_OPEN:
		while _socket.get_available_packet_count() > 0:
			_handle_packet(_socket.get_packet().get_string_from_utf8())
	elif ready == WebSocketPeer.STATE_CLOSED:
		_joined = false
		_join_sent = false
		_fresh_state = false
		_reconnect_wait = 2.0
		_status.text = "连接已断开，正在恢复……"
		_refresh_connection_actions()


func _send(payload: Dictionary) -> void:
	_last_send_error = ERR_CONNECTION_ERROR
	var kind := str(payload.get("type", ""))
	if (kind.ends_with("_action") or kind.ends_with("_social")) and not _require_actions_ready(): return
	if _socket_open(): _last_send_error = _socket.send_text(JSON.stringify(payload))
	if _last_send_error != OK and _status != null:
		_status.text = "发送未成功，请连接恢复后重试：%s" % error_string(_last_send_error)


func _socket_open() -> bool:
	return _socket.get_ready_state() == WebSocketPeer.STATE_OPEN


func _actions_ready() -> bool:
	return _socket_open() and _joined and _fresh_state


func _require_actions_ready() -> bool:
	if _actions_ready(): return true
	_last_send_error = ERR_UNAVAILABLE
	if _status != null: _status.text = "连接恢复中，请稍候再操作"
	return false


func _refresh_connection_actions() -> void:
	if _action_layer == null or _exiting: return
	_clear(_action_layer)
	_render_actions()
	if _overlay_layer != null and str(_state.get("phase", "")) == "round_finished":
		_clear(_overlay_layer)
		_render_settlement()


func _handle_packet(raw: String) -> void:
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY: return
	var kind := str(parsed.get("type", ""))
	if kind == game_protocol + "_joined":
		_joined = true
		_fresh_state = false
		_status.text = "已入座，正在同步牌桌……"
		_refresh_connection_actions()
	elif kind == game_protocol + "_state":
		_joined = true
		_fresh_state = true
		_state = parsed
		_render()
	elif kind == game_protocol + "_error":
		_status.text = "操作未生效：" + str(parsed.get("message", "未知错误"))
	elif kind == game_protocol + "_hint":
		_selected.clear()
		var ids: Array = []
		for id in parsed.get("card_ids", []):
			ids.append(int(id))
			_selected[int(id)] = true
		_update_selected()
		if ids.is_empty(): _status.text = "没有可压过的牌，可选择不出"
		hint_received.emit(ids)


func _on_board_input(event: InputEvent) -> void:
	var touch := Vector2.ZERO
	if event is InputEventMouseButton:
		if event.device == InputEvent.DEVICE_ID_EMULATION: return
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
	# Test the actual modeled card footprint, with the foremost overlapping card first.
	for index in range(_hand_nodes.size() - 1, -1, -1):
		var model := _hand_nodes[index]
		var footprint := PackedVector2Array()
		for corner in [Vector3(-0.0315, 0, -0.044), Vector3(0.0315, 0, -0.044), Vector3(0.0315, 0, 0.044), Vector3(-0.0315, 0, 0.044)]:
			footprint.append(_camera.unproject_position(model.to_global(corner)))
		if Geometry2D.is_point_in_polygon(viewport_point, footprint):
			best = index
			break
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
	_instruction.text = "轻触手牌选中 · 再次轻触取消"
	if _menu_open and phase != "finished": _render_leave_menu()
	print("LANDLORD_STATE room=%s phase=%s turn=%s seat=%s hand=%d" % [str(_state.get("room_id", "")), phase, str(_state.get("turn", "")), str(_state.get("your_seat", "")), hand.size()])


func _render_seats() -> void:
	var players := _array("players")
	var counts := _array("hand_counts")
	for seat in range(mini(3, players.size())):
		var relative := _relative_seat(seat)
		var title: String = ["我", "下家", "上家"][relative]
		var role := "待叫地主" if int(_state.get("landlord", -1)) < 0 else ("地主" if seat == int(_state.get("landlord", -1)) else "农民")
		var name := str(players[seat]).right(8)
		var count := int(counts[seat]) if seat < counts.size() else 0
		var active := seat == int(_state.get("turn", -1)) and str(_state.get("status", "")) == "playing" and str(_state.get("phase", "")) != "finished"
		var player_title := "%s · %s" % [title, name] if relative == 0 else "%s%s" % [title, role if role != "待叫地主" else ""]
		var detail := "%s  ·  %d 张%s" % [role, count, "  ·  行动中" if active else ""] if relative == 0 else "%s\n%d 张" % [name, count]
		CHROME.player(_seat_layer, player_title, detail, _seat_rect(relative), active, seat)
	var bid := int(_state.get("highest_bid", 0))
	var center := _table_rect.get_center().x
	_label(_seat_layer, "叫分 %d   ·   倍数 ×%d" % [bid, int(_state.get("multiplier", 1))], center - 180, 113, 360, 38, 20, Color("#dfbb79"))
	var bottom_point := _table_point(Vector3(0, 0, -0.46))
	_label(_seat_layer, "地主底牌", bottom_point.x - 80, bottom_point.y - 58, 160, 26, 16, Color("#a9b8a7"))


func _render_other_hands() -> void:
	var counts := _array("hand_counts")
	for seat in range(mini(3, counts.size())):
		var relative := _relative_seat(seat)
		if relative == 0: continue
		var count := mini(int(counts[seat]), 12)
		for index in range(count):
			var along := (float(index) - float(count-1)/2.0) * 0.030
			var x := -0.84 if relative == 2 else 0.84
			var card := _card_model({}, Vector3(x, -0.017 + index * 0.0017, along - 0.16), 1.15, true)
			card.rotation.y = PI * 0.5 if relative == 2 else -PI * 0.5


func _render_bottom() -> void:
	var bottom := _array("bottom")
	if bottom.is_empty():
		for index in range(3): _card_model({}, Vector3((index-1)*0.125, -0.016, -0.46), 1.65, true)
	else:
		for index in range(bottom.size()): _card_model(bottom[index], Vector3((index-1)*0.125, -0.016, -0.46), 1.65)


func _render_last_play() -> void:
	if not bool(_state.get("has_last_play", false)): return
	var last: Dictionary = _state.get("last_play", {})
	var cards: Array = last.get("cards", [])
	for index in range(cards.size()):
		var along := (float(index) - float(cards.size()-1)/2.0) * minf(0.094, 1.12/maxf(1.0,float(cards.size()-1)))
		_card_model(cards[index], Vector3(along, -0.014+index*0.0023, -0.055), 1.65)
	var point := _table_point(Vector3(0, 0, -0.055))
	_label(_seat_layer, "上手 · " + _pattern_name(str(last.get("pattern", {}).get("kind", ""))), point.x - 190, point.y - 72, 380, 28, 17, Color("#ead1a7"))


func _pattern_name(kind: String) -> String:
	return {"single":"单张", "pair":"对子", "triple":"三张", "triple_single":"三带一", "triple_pair":"三带二", "straight":"顺子", "pair_straight":"连对", "airplane":"飞机", "airplane_single":"飞机带单", "airplane_pair":"飞机带对", "four_two_single":"四带二", "four_two_pair":"四带两对", "bomb":"炸弹", "rocket":"王炸"}.get(kind, kind)


func _render_my_hand() -> void:
	var hand := _array("hand")
	for index in range(hand.size()):
		var card: Dictionary = hand[index]
		var id := int(card.get("id", -1))
		var along := (float(index)-float(hand.size()-1)/2.0) * minf(0.117,1.85/maxf(1.0,float(hand.size()-1)))
		var rest_y := 0.020 + index * 0.0035
		var model := _card_model(card, Vector3(along, rest_y + (0.075 if _selected.has(id) else 0.0), 0.49), 2.45)
		model.rotation.x = deg_to_rad(15)
		model.set_meta("rest_y", rest_y)
		model.set_meta("card_id", id)
		_hand_nodes.append(model)
		_hand_ids.append(id)


func _update_selected() -> void:
	for index in range(_hand_nodes.size()):
		_hand_nodes[index].position.y = float(_hand_nodes[index].get_meta("rest_y", 0.020)) + (0.075 if _selected.has(_hand_ids[index]) else 0.0)
	_status.text = "已选 %d 张 · 点击出牌提交" % _selected.size()
	if not _actions_ready(): _status.text = "连接恢复中，请稍候再操作"


func _render_actions() -> void:
	if not _actions_ready():
		_action_heading("连接恢复中")
		return
	if str(_state.get("status", "")) != "playing": return
	if int(_state.get("turn", -1)) != int(_state.get("your_seat", -2)):
		_action_heading("等待牌友行动")
		return
	if str(_state.get("phase", "")) == "bid":
		var high := int(_state.get("highest_bid", 0))
		var total := 4 - high
		_action_heading("轮到你叫地主")
		_action_button("不叫", 0, total, _send_bid.bind(0))
		for amount in range(high+1, 4):
			_action_button("叫 %d 分" % amount, amount - high, total, _send_bid.bind(amount), amount == 3)
	elif str(_state.get("phase", "")) == "play":
		var may_pass := bool(_state.get("has_last_play", false)) and int(_state.get("last_play", {}).get("seat", -1)) != int(_state.get("your_seat", -2))
		var total := 3 if may_pass else 2
		_action_heading("轮到你出牌")
		_action_button("重选", 0, total, _clear_selection)
		if may_pass: _action_button("不出", 1, total, _send_pass)
		_action_button("出牌", total - 1, total, _send_play, true)


func _clear_selection() -> void:
	_selected.clear()
	_update_selected()


func _send_bid(amount: int) -> void:
	if not _require_actions_ready(): return
	_send({"type":game_protocol + "_action", "action":"bid", "amount":amount})


func _send_pass() -> void:
	if not _require_actions_ready(): return
	_send({"type":game_protocol + "_action", "action":"pass"})


func _send_play() -> void:
	if not _require_actions_ready(): return
	if _selected.is_empty():
		_status.text = "请先点击桌上的三维手牌"
		return
	var ids: Array[int] = []
	for id in _selected.keys(): ids.append(int(id))
	_send({"type":game_protocol + "_action", "action":"play", "card_ids":ids})


func _render_settlement() -> void:
	_menu_open = false
	var panel := _modal_panel(Vector2(744, 434))
	var winner := int(_state.get("winner", -1))
	var landlord := int(_state.get("landlord", -1))
	_label(panel, "本局结算", 24, 22, 696, 52, 32)
	_label(panel, "地主胜利" if winner == landlord else "农民胜利", 24, 84, 696, 46, 29, Color("#f8d488"))
	_label(panel, "本局倍数 ×%d" % int(_state.get("multiplier", 1)), 24, 136, 696, 28, 18, Color("#9badab"))
	var scores := _array("scores")
	var players := _array("players")
	for seat in range(mini(3, scores.size())):
		var x := 32 + seat * 232
		var name := "我" if seat == int(_state.get("your_seat", -1)) else (str(players[seat]).right(8) if seat < players.size() else "%d 号位" % (seat + 1))
		var role := "地主" if seat == landlord else "农民"
		var tile := Panel.new()
		tile.position = Vector2(x, 184)
		tile.size = Vector2(216, 118)
		tile.add_theme_stylebox_override("panel", _style(Color("#19362f"), Color("#496254")))
		panel.add_child(tile)
		_label(tile, "%s · %s" % [name, role], 8, 10, 200, 38, 19)
		_label(tile, "%+d 分" % int(scores[seat]), 8, 58, 200, 45, 30, Color("#f8d488") if int(scores[seat]) >= 0 else Color("#9badab"))
	_button(panel, "返回大厅", 232, 342, 280, 64, _return_now, true)


func _modal_panel(panel_size: Vector2) -> Panel:
	var shade := ColorRect.new()
	shade.name = "BattleModalShade"
	shade.color = Color("#020a0bc4")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay_layer.add_child(shade)
	var panel := Panel.new()
	panel.position = (_canvas_size() - panel_size) * 0.5
	panel.size = panel_size
	panel.add_theme_stylebox_override("panel", _style(Color("#102825fc"), Color("#e3b663"), 24))
	_overlay_layer.add_child(panel)
	return panel


func _request_leave() -> void:
	if training_mode or str(_state.get("phase", "")) == "finished":
		_return_now()
		return
	_menu_open = true
	_clear(_overlay_layer)
	_render_leave_menu()


func _render_leave_menu() -> void:
	var panel := _modal_panel(Vector2(584, 276))
	_label(panel, "暂离牌桌", 24, 26, 536, 54, 30)
	_label(panel, "返回大厅后，本局将继续托管", 24, 93, 536, 46, 22, Color("#c8cbb6"))
	_button(panel, "继续对局", 32, 178, 240, 64, _close_leave_menu)
	_button(panel, "返回大厅", 312, 178, 240, 64, _return_now, true)


func _close_leave_menu() -> void:
	_menu_open = false
	_clear(_overlay_layer)


func _return_now() -> void:
	set_process(false)
	_socket.close()
	request_return_to_lobby.emit()
