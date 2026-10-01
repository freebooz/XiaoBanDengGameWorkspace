extends Control
## 贵阳麻将实时桌面：只提交动作意图，暗牌、牌墙、胡牌判定均来自服务端。

signal request_return_to_lobby

const ART := "res://modules/games/mahjong/guiyang/assets/"
const API_SCRIPT = preload("res://modules/foundation/network/api_client.gd")

var product: Dictionary = {}
var match_context: Dictionary = {}
var _socket := WebSocketPeer.new()
var _joined := false
var _state: Dictionary = {}
var _textures: Dictionary = {}
var _selected_id := 0
var _auto_played := false
var _reconnect_wait := 0.0
var _status: Label
var _header: Label
var _hand_root: Control
var _actions_root: Control
var _table_root: Control
var _seat_root: Control
var _overlay_root: Control


func _ready() -> void:
	_build_static_ui()
	_connect_socket()
	set_process(true)


func _exit_tree() -> void:
	_socket.close()


func _texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	var texture := ImageTexture.create_from_image(image)
	_textures[path] = texture
	return texture


func _style(bg: Color, border: Color, radius: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color("#00000088")
	style.shadow_size = 5
	return style


func _label(parent: Node, value: String, x: float, y: float, width: float, height: float, size: int = 19, color: Color = Color("#ffe9bc")) -> Label:
	var label := Label.new()
	label.text = value
	label.position = Vector2(x, y)
	label.size = Vector2(width, height)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _button(parent: Node, value: String, x: float, y: float, width: float, height: float, action: Callable, accent: Color = Color("#d9a441")) -> Button:
	var button := Button.new()
	button.text = value
	button.position = Vector2(x, y)
	button.size = Vector2(width, height)
	button.add_theme_font_size_override("font_size", 19)
	button.add_theme_color_override("font_color", Color("#fff1d3"))
	button.add_theme_stylebox_override("normal", _style(Color("#073f36ed"), accent))
	button.add_theme_stylebox_override("hover", _style(Color("#166b5bec"), Color("#ffe2a1")))
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _build_static_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("#071a17")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var board := TextureRect.new()
	board.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	board.stretch_mode = TextureRect.STRETCH_SCALE
	board.texture = _texture(ART + "backgrounds/T_BG_GameTable_GreenFelt.png")
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board)
	board.position = Vector2(10, 277)
	board.size = Vector2(700, 394)
	_header = _label(self, "小板凳麻将 · 贵阳麻将", 24, 17, 520, 50, 29)
	_label(self, "房间 %s" % str(match_context.get("room_id", "")), 530, 18, 170, 45, 17, Color("#dfbd83"))
	_status = _label(self, "正在连接实时对局……", 30, 1100, 660, 70, 19)
	_table_root = Control.new()
	_table_root.position = Vector2(10, 277)
	_table_root.size = Vector2(700, 394)
	add_child(_table_root)
	_seat_root = Control.new()
	_seat_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_seat_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_seat_root)
	_hand_root = Control.new()
	_hand_root.position = Vector2(0, 790)
	_hand_root.size = Vector2(720, 190)
	add_child(_hand_root)
	_actions_root = Control.new()
	_actions_root.position = Vector2(0, 1000)
	_actions_root.size = Vector2(720, 90)
	add_child(_actions_root)
	_overlay_root = Control.new()
	_overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay_root)
	_label(self, "点击手牌选中，再点击“打出”", 30, 1187, 660, 50, 16, Color("#c9a771"))


func _connect_socket() -> void:
	_socket = WebSocketPeer.new()
	var api = API_SCRIPT.new()
	var err := _socket.connect_to_url(api.websocket_url())
	if err != OK:
		_status.text = "实时服务连接失败，正在重试：%s" % str(err)
		_reconnect_wait = 2.0


func _process(delta: float) -> void:
	if _reconnect_wait > 0.0:
		_reconnect_wait -= delta
		if _reconnect_wait <= 0.0:
			_connect_socket()
		return
	_socket.poll()
	var ready := _socket.get_ready_state()
	if ready == WebSocketPeer.STATE_OPEN and not _joined:
		_joined = true
		_send({"type": "mahjong_join", "room_id": str(match_context.get("room_id", "")), "client_id": str(match_context.get("account_id", ""))})
	if ready == WebSocketPeer.STATE_OPEN:
		while _socket.get_available_packet_count() > 0:
			_handle_packet(_socket.get_packet().get_string_from_utf8())
	elif ready == WebSocketPeer.STATE_CLOSED:
		_joined = false
		_reconnect_wait = 2.0
		_status.text = "连接已断开，正在恢复原座位……"


func _send(payload: Dictionary) -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify(payload))


func _handle_packet(raw: String) -> void:
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	match str(parsed.get("type", "")):
		"mahjong_joined":
			_status.text = "已入座 %d 号位，等待四位牌友连接。" % (int(parsed.get("your_seat", 0)) + 1)
		"mahjong_state":
			_state = parsed
			_render()
		"mahjong_error":
			_status.text = "操作未生效：" + str(parsed.get("message", "未知错误"))


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		child.queue_free()


func _array(key: String) -> Array:
	var value = _state.get(key, [])
	return value if typeof(value) == TYPE_ARRAY else []


func _render() -> void:
	_clear(_table_root)
	_clear(_seat_root)
	_clear(_hand_root)
	_clear(_actions_root)
	_clear(_overlay_root)
	_selected_id = _selected_id if _hand_contains(_selected_id) else 0
	_render_seats()
	_render_opponent_hands()
	_render_discards()
	_render_melds()
	_render_hand()
	_render_actions()
	var phase := str(_state.get("phase", ""))
	var status := str(_state.get("status", "waiting"))
	if status == "waiting":
		_status.text = "等待四位牌友连接 · %d / 4" % int(_state.get("connected_players", 0))
	elif phase == "finished":
		_status.text = "本局结束"
		_render_settlement()
	elif phase == "reaction":
		_status.text = "等待碰、杠、胡响应" if _options().is_empty() else "你可以响应上家弃牌"
	elif int(_state.get("turn", -1)) == int(_state.get("your_seat", -2)):
		_status.text = "轮到你出牌 · 牌墙剩余 %d 张" % int(_state.get("remaining", 0))
	else:
		_status.text = "等待其他玩家 · 牌墙剩余 %d 张" % int(_state.get("remaining", 0))
	print("MAHJONG_STATE room=%s phase=%s turn=%s seat=%s remaining=%s" % [str(_state.get("room_id", "")), phase, str(_state.get("turn", "")), str(_state.get("your_seat", "")), str(_state.get("remaining", ""))])
	if "--auto-flow" in OS.get_cmdline_user_args() and not _auto_played and status == "playing" and phase == "turn" and int(_state.get("turn", -1)) == int(_state.get("your_seat", -2)):
		_auto_played = true
		var hand: Array = _array("hand")
		if not hand.is_empty():
			call_deferred("_send_action", "play", int(hand[0].get("id", 0)))


func _relative_seat(seat: int) -> int:
	return (seat - int(_state.get("your_seat", 0)) + 4) % 4


func _render_seats() -> void:
	var players: Array = _array("players")
	var counts: Array = _array("hand_counts")
	var scores: Array = _array("scores")
	var places := [Vector2(165, 705), Vector2(490, 204), Vector2(170, 104), Vector2(10, 204)]
	var widths := [390.0, 220.0, 380.0, 220.0]
	var titles := ["我的手牌", "右家", "对家", "左家"]
	for seat in range(4):
		var relative := _relative_seat(seat)
		var pos: Vector2 = places[relative]
		var short_name := str(players[seat]).right(6) if seat < players.size() else ""
		var count := int(counts[seat]) if seat < counts.size() else 0
		var score := int(scores[seat]) if seat < scores.size() else 0
		var label := _label(_seat_root, "%s · %s\n%d 张   %d 分" % [titles[relative], short_name, count, score], pos.x, pos.y, widths[relative], 70, 18)
		if seat == int(_state.get("turn", -1)) and str(_state.get("phase", "")) != "finished":
			label.add_theme_color_override("font_color", Color("#ffcd55"))


func _tile_path(tile: Dictionary) -> String:
	var suit := str(tile.get("suit", ""))
	var prefix := ""
	match suit:
		"wan": prefix = "Wan"
		"tong": prefix = "Tong"
		"tiao": prefix = "Tiao"
	if prefix == "":
		return ART + "tiles/T_Tile_Back.png"
	return ART + "tiles/T_Tile_%s_%02d.png" % [prefix, int(tile.get("rank", 1))]


func _tile_image(parent: Node, tile: Dictionary, x: float, y: float, width: float, height: float) -> TextureRect:
	var image := TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_SCALE
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.texture = _texture(_tile_path(tile))
	parent.add_child(image)
	image.position = Vector2(x, y)
	image.size = Vector2(width, height)
	return image


func _render_opponent_hands() -> void:
	var counts: Array = _array("hand_counts")
	for seat in range(mini(4, counts.size())):
		var relative := _relative_seat(seat)
		if relative == 0:
			continue
		var count := mini(int(counts[seat]), 14)
		for index in range(count):
			if relative == 2:
				_tile_image(_seat_root, {}, 190.0 + index * 24.0, 226.0, 25.0, 38.0)
			elif relative == 3:
				_tile_image(_seat_root, {}, 23.0, 325.0 + index * 21.0, 26.0, 34.0)
			else:
				_tile_image(_seat_root, {}, 671.0, 325.0 + index * 21.0, 26.0, 34.0)


func _render_discards() -> void:
	var zones := [Vector2(245, 268), Vector2(490, 165), Vector2(245, 35), Vector2(52, 165)]
	var per_seat := [[], [], [], []]
	for raw in _array("discards"):
		if typeof(raw) == TYPE_DICTIONARY:
			var seat := int(raw.get("seat", -1))
			if seat >= 0 and seat < 4 and not bool(raw.get("claimed", false)):
				per_seat[seat].append(raw.get("tile", {}))
	for seat in range(4):
		var pos: Vector2 = zones[_relative_seat(seat)]
		for index in range(per_seat[seat].size()):
			var col := index % 6
			var row := index / 6
			_tile_image(_table_root, per_seat[seat][index], pos.x + col * 32.0, pos.y + row * 39.0, 29, 38)


func _render_melds() -> void:
	var meld_groups: Array = _array("melds")
	var positions := [Vector2(5, 355), Vector2(470, 285), Vector2(245, 4), Vector2(5, 285)]
	for seat in range(mini(4, meld_groups.size())):
		var pos: Vector2 = positions[_relative_seat(seat)]
		var melds: Array = meld_groups[seat]
		for index in range(melds.size()):
			var meld: Dictionary = melds[index]
			var tiles: Array = meld.get("tiles", [])
			_label(_table_root, _meld_name(str(meld.get("kind", ""))), pos.x + index * 75, pos.y, 70, 23, 13, Color("#f2d292"))
			for tile_index in range(mini(4, tiles.size())):
				_tile_image(_table_root, tiles[tile_index], pos.x + index * 75 + tile_index * 17, pos.y + 24, 17, 26)


func _meld_name(kind: String) -> String:
	match kind:
		"peng": return "碰"
		"ming_gang": return "明杠"
		"an_gang": return "暗杠"
		"bu_gang": return "补杠"
	return kind


func _render_hand() -> void:
	var hand: Array = _array("hand")
	if hand.is_empty():
		return
	var tile_width := minf(47.0, 660.0 / float(hand.size()))
	var start_x := (720.0 - tile_width * float(hand.size())) / 2.0
	for index in range(hand.size()):
		var tile: Dictionary = hand[index]
		var id := int(tile.get("id", 0))
		var button := TextureButton.new()
		button.texture_normal = _texture(_tile_path(tile))
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_SCALE
		button.position = Vector2(start_x + float(index) * tile_width, 80 if id == _selected_id else 96)
		button.size = Vector2(tile_width + 2, 88)
		button.pressed.connect(_select_tile.bind(id))
		_hand_root.add_child(button)
	_label(_hand_root, "我的手牌", 20, 15, 680, 50, 18, Color("#e2be7d"))


func _select_tile(id: int) -> void:
	_selected_id = id
	_render_hand_only()


func _render_hand_only() -> void:
	_clear(_hand_root)
	_render_hand()


func _hand_contains(id: int) -> bool:
	if id <= 0:
		return false
	for tile in _array("hand"):
		if int(tile.get("id", 0)) == id:
			return true
	return false


func _options() -> Array:
	return _array("options")


func _render_actions() -> void:
	var options := _options()
	if options.is_empty():
		return
	var button_width := minf(120.0, 680.0 / float(options.size()))
	var start_x := (720.0 - button_width * float(options.size())) / 2.0
	for index in range(options.size()):
		var option: Dictionary = options[index]
		var kind := str(option.get("type", ""))
		var tile_id := int(option.get("tile_id", 0))
		var text_value := _action_name(kind)
		if kind == "play":
			_button(_actions_root, text_value, start_x + index * button_width, 0, button_width - 5, 72, _on_play)
		else:
			_button(_actions_root, text_value, start_x + index * button_width, 0, button_width - 5, 72, _send_action.bind(kind, tile_id))


func _action_name(kind: String) -> String:
	match kind:
		"play": return "打出"
		"pass": return "过"
		"peng": return "碰"
		"ming_gang": return "明杠"
		"an_gang": return "暗杠"
		"bu_gang": return "补杠"
		"hu": return "胡"
	return kind


func _on_play() -> void:
	if _selected_id <= 0:
		_status.text = "请先点击一张手牌"
		return
	_send_action("play", _selected_id)


func _send_action(kind: String, tile_id: int = 0) -> void:
	_send({"type": "mahjong_action", "action": kind, "tile_id": tile_id})
	_selected_id = 0


func _render_settlement() -> void:
	var panel := Panel.new()
	panel.position = Vector2(90, 315)
	panel.size = Vector2(540, 440)
	panel.add_theme_stylebox_override("panel", _style(Color("#082d26f4"), Color("#d9a441"), 24))
	_overlay_root.add_child(panel)
	var heading := _label(panel, "本局结算", 30, 24, 480, 60, 35)
	heading.add_theme_color_override("font_color", Color("#ffe1a2"))
	var winners: Array = _array("winners")
	var summary := "流局 · 牌墙已摸完" if winners.is_empty() else "胡牌座位：" + ", ".join(winners.map(func(value): return str(int(value) + 1)))
	_label(panel, summary, 25, 105, 490, 75, 22)
	var scores: Array = _array("scores")
	for seat in range(mini(4, scores.size())):
		_label(panel, "%d 号位     %+d 分" % [seat + 1, int(scores[seat])], 60, 188 + seat * 43, 420, 40, 19)
	_button(panel, "返回大厅", 140, 374, 260, 55, func(): request_return_to_lobby.emit())
