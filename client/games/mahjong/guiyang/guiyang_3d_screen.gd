extends Control
## 贵阳麻将实时桌面：只提交动作意图，暗牌、牌墙、胡牌判定均来自服务端。

signal request_return_to_lobby

const ART := "res://modules/games/mahjong/guiyang/assets/"
const API_SCRIPT = preload("res://modules/foundation/network/api_client.gd")
const STAGE_SCRIPT = preload("res://modules/game_framework/tabletop3d/tabletop_stage.gd")
const TABLE_SCENE = preload("res://modules/games/mahjong/guiyang/assets/models/mahjong_table.glb")
const TILE_SCENE = preload("res://modules/games/mahjong/guiyang/assets/models/mahjong_tile.glb")
const DISPLAY = preload("res://modules/foundation/ui/battle_display.gd")
const CHROME = preload("res://modules/foundation/ui/battle_chrome.gd")
const QUALITY_FILE := "user://mahjong_visuals.cfg"
## 画质指定横向采样数；纵向采样始终由当前桌面比例计算。
const QUALITY_SIZES := [Vector2i(960, 540), Vector2i(1440, 810), Vector2i(1920, 1080)]

var product: Dictionary = {}
var match_context: Dictionary = {}
var training_mode := false
var _socket := WebSocketPeer.new()
var _joined := false
var _state: Dictionary = {}
var _textures: Dictionary = {}
var _selected_id := 0
var _auto_played := false
var _reconnect_wait := 0.0
var _status: Label
var _actions_root: Control
var _seat_root: Control
var _overlay_root: Control
var _table_frame: Panel
var _actions_panel: Panel
var _turn_label: Label
var _wall_label: Label
var _selection_label: Label
var _action_hint: Label
var _instructions: Label
var _table_caption: Label
var _return_button: Button
var _mode_label: Label
var _seat_panels: Array[Panel] = []
var _play_button: Button
var _settlement_panel: Panel
var _table_bounds := AABB(Vector3(-0.75, -0.065, -0.75), Vector3(1.5, 0.19, 1.5))
var _board_view: TextureRect
var _board_viewport: SubViewport
var _stage: Node3D
var _camera: Camera3D
var _pieces_root: Node3D
var _hand_models: Array[Node3D] = []
var _hand_ids: Array[int] = []
var _face_materials: Dictionary = {}
var _quality := 1
var _quality_option: OptionButton


func _ready() -> void:
	DISPLAY.enter(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_quality()
	_build_static_ui()
	resized.connect(_layout_ui)
	if training_mode:
		_start_training()
		set_process(false)
	else:
		_connect_socket()
		set_process(true)


func _exit_tree() -> void:
	if not training_mode:
		_socket.close()
	DISPLAY.leave(self)


func _load_quality() -> void:
	var config := ConfigFile.new()
	if config.load(QUALITY_FILE) == OK:
		_quality = clampi(int(config.get_value("rendering", "quality", 1)), 0, 2)


func _set_quality(index: int) -> void:
	_quality = clampi(index, 0, 2)
	_sync_viewport_size()
	_board_viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_4X, Viewport.MSAA_8X][_quality]
	_stage.get_node("KeyLight").shadow_enabled = _quality > 0
	var config := ConfigFile.new()
	config.set_value("rendering", "quality", _quality)
	config.save(QUALITY_FILE)


func _start_training() -> void:
	var hand: Array = []
	for index in range(14):
		var suit: String = ["wan", "tong", "tiao"][int(index / 5) % 3]
		hand.append({"id": index + 1, "suit": suit, "rank": index % 9 + 1})
	_state = {
		"room_id": "训练", "status": "playing", "phase": "turn", "turn": 0, "your_seat": 0,
		"players": ["我", "练习位一", "练习位二", "练习位三"], "hand": hand,
		"hand_counts": [14, 13, 13, 13], "scores": [0, 0, 0, 0],
		"melds": [[], [], [], []], "discards": [], "remaining": 55,
		"options": [{"type": "play"}], "winners": []
	}
	_render()
	_status.text = "单人训练 · 点击三维手牌，再点击“打出”"


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
	return CHROME.style(bg, border, radius)


func _label(parent: Node, value: String, x: float, y: float, width: float, height: float, size: int = 19, color: Color = Color("#ffe9bc")) -> Label:
	return CHROME.label(parent, value, Rect2(x, y, width, height), size, color)


func _button(parent: Node, value: String, x: float, y: float, width: float, height: float, action: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = value
	button.position = Vector2(x, y)
	button.size = Vector2(width, height)
	CHROME.skin_button(button, primary, false)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _build_static_ui() -> void:
	CHROME.backdrop(self, "小板凳麻将 · 贵阳麻将", "训练" if training_mode else str(match_context.get("room_id", "")))
	_table_frame = Panel.new()
	_table_frame.name = "MahjongTableFrame"
	_table_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_table_frame.add_theme_stylebox_override("panel", _style(Color("#0b222184"), Color("#96774770"), 24))
	add_child(_table_frame)
	_build_3d_table()
	_table_caption = _label(self, "贵阳麻将 · 练习桌" if training_mode else "贵阳麻将 · 四人对局", 0, 0, 400, 30, 17, Color("#a8b9a6"))
	_quality_option = OptionButton.new()
	for title in ["低画质", "中画质", "高画质"]:
		_quality_option.add_item(title)
	CHROME.skin_button(_quality_option, false, false)
	_quality_option.add_theme_font_size_override("font_size", 18)
	_quality_option.select(_quality)
	_quality_option.item_selected.connect(_set_quality)
	add_child(_quality_option)
	if training_mode:
		_return_button = _button(self, "返回大厅", 0, 0, 168, 48, func(): request_return_to_lobby.emit())
	else:
		_mode_label = _label(self, "四人实时桌", 0, 0, 168, 48, 18, CHROME.GOLD)
	_actions_panel = Panel.new()
	_actions_panel.name = "MahjongActionsPanel"
	_actions_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_actions_panel.add_theme_stylebox_override("panel", _style(Color("#0e211feb"), Color("#9b7a486a"), 20))
	add_child(_actions_panel)
	_turn_label = _label(self, "正在入座", 0, 0, 216, 54, 29)
	_wall_label = _label(self, "准备开始对局", 0, 0, 216, 36, 18, CHROME.GOLD)
	_selection_label = _label(self, "请选择一张手牌", 0, 0, 216, 60, 22, CHROME.MUTED)
	_action_hint = _label(self, "等待牌友入座", 0, 0, 216, 32, 16, CHROME.MUTED)
	_status = _label(self, "正在连接实时对局……", 0, 0, 660, 48, 21)
	_instructions = _label(self, "点击三维手牌选择 · 再点击打出", 0, 0, 660, 28, 16, CHROME.MUTED)
	_seat_root = Control.new()
	_seat_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_seat_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_seat_root)
	_actions_root = Control.new()
	_actions_root.name = "MahjongActions"
	_actions_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_actions_root)
	_overlay_root = Control.new()
	_overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay_root)
	_layout_ui()


func _layout_ui() -> void:
	if _board_view == null:
		return
	var width := size.x if size.x > 0 else 1440.0
	var height := size.y if size.y > 0 else 810.0
	var column_x := width - 280.0
	_table_frame.position = Vector2(28, 104)
	_table_frame.size = Vector2(column_x - 50.0, height - 208.0)
	_board_view.position = _table_frame.position + Vector2(4, 4)
	_board_view.size = _table_frame.size - Vector2(8, 8)
	_actions_panel.position = Vector2(column_x, 110)
	_actions_panel.size = Vector2(252, height - 225)
	_quality_option.position = Vector2(width - 402, 24)
	_quality_option.size = Vector2(180, 48)
	if _return_button != null:
		_return_button.position = Vector2(width - 196, 24)
	if _mode_label != null:
		_mode_label.position = Vector2(width - 196, 24)
	_turn_label.position = Vector2(column_x + 18, 125)
	_wall_label.position = Vector2(column_x + 18, 182)
	_selection_label.position = Vector2(column_x + 18, 225)
	_actions_root.position = Vector2(column_x + 18, 298)
	_actions_root.size = Vector2(216, height - 442)
	_action_hint.position = Vector2(column_x + 18, height - 136)
	_status.position = Vector2(352, height - 86)
	_status.size = Vector2(width - 680, 48)
	_instructions.position = Vector2(352, height - 42)
	_instructions.size = Vector2(width - 680, 26)
	_table_caption.position = Vector2(_board_view.position.x + _board_view.size.x * 0.5 - 200, 204)
	_sync_viewport_size()
	for index in range(_seat_panels.size()):
		if is_instance_valid(_seat_panels[index]):
			var rect := _seat_rect(index)
			_seat_panels[index].position = rect.position
			_seat_panels[index].size = rect.size
	if is_instance_valid(_settlement_panel):
		_settlement_panel.position = (Vector2(width, height) - _settlement_panel.size) * 0.5


func _seat_rect(relative: int) -> Rect2:
	var center := _board_view.position.x + _board_view.size.x * 0.5
	match relative:
		0: return Rect2(32, size.y - 88, 300, 70)
		1: return Rect2(_board_view.position.x + _board_view.size.x - 254, 238, 240, 80)
		2: return Rect2(center - 150, 112, 300, 78)
	return Rect2(_board_view.position.x + 14, 238, 240, 80)


func _sync_viewport_size() -> void:
	if _board_viewport == null or _board_view == null or _board_view.size.y <= 0:
		return
	var pixels: int = QUALITY_SIZES[_quality].x
	_board_viewport.size = Vector2i(pixels, maxi(1, roundi(float(pixels) * _board_view.size.y / _board_view.size.x)))
	_fit_camera()


func _fit_camera() -> void:
	if _camera == null:
		return
	# 投影模型边界求垂直视角，宽屏、平板扩展画面都保留真实比例。
	var aspect := _board_view.size.x / _board_view.size.y
	var inverse := _camera.global_transform.affine_inverse()
	var tangent := 0.0
	for index in range(8):
		var point: Vector3 = inverse * _table_bounds.get_endpoint(index)
		var depth := maxf(0.1, -point.z)
		tangent = maxf(tangent, absf(point.x) / (depth * aspect * 0.94))
		tangent = maxf(tangent, absf(point.y) / (depth * 0.91))
	_camera.fov = clampf(rad_to_deg(2.0 * atan(tangent)), 26.0, 60.0)


func _build_3d_table() -> void:
	_board_viewport = SubViewport.new()
	_board_viewport.name = "Mahjong3DViewport"
	_board_viewport.size = QUALITY_SIZES[_quality]
	_board_viewport.transparent_bg = true
	_board_viewport.own_world_3d = true
	_board_viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_4X, Viewport.MSAA_8X][_quality]
	_board_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_board_viewport)
	var world := Node3D.new()
	world.name = "MahjongWorld"
	_board_viewport.add_child(world)
	_stage = STAGE_SCRIPT.new()
	world.add_child(_stage)
	_camera = _stage.configure(2.0, Vector3(0, 1.38, 1.65), Vector3(0, 0, 0), true, 34.0)
	_stage.get_node("WorldEnvironment").environment.background_mode = Environment.BG_CLEAR_COLOR
	_stage.get_node("Floor").visible = false
	_stage.get_node("KeyLight").shadow_enabled = _quality > 0
	var table := TABLE_SCENE.instantiate()
	table.name = "ImportedMahjongTable"
	world.add_child(table)
	_pieces_root = Node3D.new()
	_pieces_root.name = "ThreeDimensionalTiles"
	world.add_child(_pieces_root)
	_board_view = TextureRect.new()
	_board_view.name = "Mahjong3DTableView"
	_board_view.texture = _board_viewport.get_texture()
	_board_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_board_view.stretch_mode = TextureRect.STRETCH_SCALE
	_board_view.gui_input.connect(_on_board_input)
	add_child(_board_view)


func _on_board_input(event: InputEvent) -> void:
	var touch_position := Vector2.ZERO
	if event is InputEventMouseButton:
		if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
			return
		touch_position = event.position
	elif event is InputEventScreenTouch:
		if not event.pressed:
			return
		touch_position = event.position
	else:
		return
	var nearest_id := 0
	var nearest_distance := 36.0
	for index in range(_hand_models.size()):
		var projected := _camera.unproject_position(_hand_models[index].global_position) * _board_view.size / Vector2(_board_viewport.size)
		var distance := touch_position.distance_to(projected)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_id = _hand_ids[index]
	if nearest_id > 0:
		_select_tile(nearest_id)


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
	_clear(_pieces_root)
	_hand_models.clear()
	_hand_ids.clear()
	_clear(_seat_root)
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
	var places := [Vector2(165, 912), Vector2(490, 204), Vector2(170, 104), Vector2(10, 204)]
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


func _face_material(tile: Dictionary) -> StandardMaterial3D:
	var path := _tile_path(tile)
	if _face_materials.has(path):
		return _face_materials[path]
	var material := StandardMaterial3D.new()
	material.albedo_texture = _texture(path)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.32
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_face_materials[path] = material
	return material


func _tile_model(tile: Dictionary, location: Vector3, relative: int = 0, concealed: bool = false) -> Node3D:
	var model := TILE_SCENE.instantiate() as Node3D
	model.position = location
	model.scale = Vector3.ONE * 1.17
	model.rotation.y = float(relative) * PI / 2.0
	_pieces_root.add_child(model)
	var face := model.find_child("TileFace", true, false) as MeshInstance3D
	if face != null:
		face.material_override = _face_material(tile)
		face.visible = not concealed
	if concealed:
		model.rotation.x = PI
	return model


func _render_opponent_hands() -> void:
	var counts: Array = _array("hand_counts")
	for seat in range(mini(4, counts.size())):
		var relative := _relative_seat(seat)
		if relative == 0:
			continue
		var count := mini(int(counts[seat]), 14)
		for index in range(count):
			var along := (float(index) - float(count - 1) / 2.0) * 0.068
			var position := Vector3(along, 0.052, -0.54)
			if relative == 1:
				position = Vector3(0.54, 0.052, along)
			elif relative == 3:
				position = Vector3(-0.54, 0.052, along)
			var model := _tile_model({}, position, relative, true)
			model.scale = Vector3.ONE * 1.70


func _render_discards() -> void:
	var per_seat := [[], [], [], []]
	for raw in _array("discards"):
		if typeof(raw) == TYPE_DICTIONARY:
			var seat := int(raw.get("seat", -1))
			if seat >= 0 and seat < 4 and not bool(raw.get("claimed", false)):
				per_seat[seat].append(raw.get("tile", {}))
	for seat in range(4):
		var relative := _relative_seat(seat)
		for index in range(per_seat[seat].size()):
			var col := index % 6
			var row := int(index / 6)
			var along := (float(col) - 2.5) * 0.046
			var position := Vector3(along, 0.002, 0.16 + float(row) * 0.067)
			if relative == 2:
				position = Vector3(-along, 0.002, -0.16 - float(row) * 0.067)
			elif relative == 1:
				position = Vector3(0.16 + float(row) * 0.067, 0.002, along)
			elif relative == 3:
				position = Vector3(-0.16 - float(row) * 0.067, 0.002, -along)
			_tile_model(per_seat[seat][index], position, relative)


func _render_melds() -> void:
	var meld_groups: Array = _array("melds")
	for seat in range(mini(4, meld_groups.size())):
		var relative := _relative_seat(seat)
		var melds: Array = meld_groups[seat]
		for index in range(melds.size()):
			var meld: Dictionary = melds[index]
			var tiles: Array = meld.get("tiles", [])
			for tile_index in range(mini(4, tiles.size())):
				var along := (float(index) * 4.0 + float(tile_index) - 5.0) * 0.047
				var position := Vector3(along, 0.002, 0.41)
				if relative == 2:
					position = Vector3(-along, 0.002, -0.41)
				elif relative == 1:
					position = Vector3(0.41, 0.002, along)
				elif relative == 3:
					position = Vector3(-0.41, 0.002, -along)
				_tile_model(tiles[tile_index], position, relative)


func _render_hand() -> void:
	var hand: Array = _array("hand")
	if hand.is_empty():
		return
	_hand_models.clear()
	_hand_ids.clear()
	for index in range(hand.size()):
		var tile: Dictionary = hand[index]
		var id := int(tile.get("id", 0))
		var along := (float(index) - float(hand.size() - 1) / 2.0) * 0.068
		var model := _tile_model(tile, Vector3(along, 0.026 if id == _selected_id else 0.002, 0.54))
		model.scale = Vector3.ONE * 1.70
		_hand_models.append(model)
		_hand_ids.append(id)


func _select_tile(id: int) -> void:
	_selected_id = id
	_render_hand_only()


func _render_hand_only() -> void:
	for index in range(_hand_models.size()):
		_hand_models[index].position.y = 0.026 if _hand_ids[index] == _selected_id else 0.002


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
	var count := options.size() + (1 if training_mode else 0)
	var button_width := minf(150.0, 680.0 / float(count))
	var start_x := (720.0 - button_width * float(count)) / 2.0
	for index in range(options.size()):
		var option: Dictionary = options[index]
		var kind := str(option.get("type", ""))
		var tile_id := int(option.get("tile_id", 0))
		var text_value := _action_name(kind)
		if kind == "play":
			_button(_actions_root, text_value, start_x + index * button_width, 0, button_width - 5, 72, _on_play)
		else:
			_button(_actions_root, text_value, start_x + index * button_width, 0, button_width - 5, 72, _send_action.bind(kind, tile_id))
	if training_mode:
		_button(_actions_root, "返回大厅", start_x + options.size() * button_width, 0, button_width - 5, 72, func(): request_return_to_lobby.emit())


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
	if training_mode:
		if kind == "play":
			_training_play(tile_id)
		return
	_send({"type": "mahjong_action", "action": kind, "tile_id": tile_id})
	_selected_id = 0


func _training_play(tile_id: int) -> void:
	if tile_id <= 0:
		return
	var hand: Array = _array("hand")
	for index in range(hand.size()):
		if int(hand[index].get("id", 0)) != tile_id:
			continue
		var discards: Array = _array("discards")
		discards.append({"seat": 0, "tile": hand[index], "claimed": false})
		hand.remove_at(index)
		var next_id := 1000 + discards.size()
		var suit: String = ["wan", "tong", "tiao"][discards.size() % 3]
		hand.append({"id": next_id, "suit": suit, "rank": discards.size() % 9 + 1})
		_state["remaining"] = maxi(0, int(_state.get("remaining", 0)) - 1)
		_selected_id = 0
		_render()
		_status.text = "单人训练 · 已打出 %d 张 · 点击下一张手牌" % discards.size()
		return


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
