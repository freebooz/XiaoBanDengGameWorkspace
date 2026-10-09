extends Control
## ChineseChess3DScreen（小板凳象棋三维在线对局界面）
## 参考国风竖屏对弈布局：山水背景、厚木棋盘、立体棋子与双人信息区。
## 红黑双方分别从自己的棋盘一侧观察，黑方相机与红方相差180度。
## 服务端棋盘坐标始终保持统一，客户端只旋转摄像机，不旋转权威棋局数据。

const STAGE_SCRIPT = preload("res://modules/game_framework/tabletop3d/tabletop_stage.gd")
const PBR_FACTORY = preload("res://modules/game_framework/tabletop3d/pbr_material_factory.gd")
const COUNTDOWN_CLOCK_SCRIPT = preload("res://modules/foundation/ui/turn_countdown_clock.gd")
const WARNING_SOUND_SCRIPT = preload("res://modules/foundation/audio/turn_warning_sound.gd")
const LANDSCAPE_TEXTURE_PATH := "res://modules/games/chinese_chess/assets/ink_landscape_background.png"
const PORTRAIT_TEXTURE_PATH := "res://modules/games/chinese_chess/assets/player_portraits.png"
const BOARD_SURFACE_TEXTURE_PATH := "res://modules/games/chinese_chess/assets/engraved_chessboard.png"
const WOOD_GRAIN_TEXTURE_PATH := "res://modules/games/chinese_chess/assets/board_woodgrain.png"
const BLENDER_BOARD_PATH := "res://modules/games/chinese_chess/assets/models/chess_board.glb"
const BLENDER_PIECES_PATH := "res://modules/games/chinese_chess/assets/models/chess_pieces.glb"

const CELL_SIZE := 0.86
const BOARD_Y := 0.125
const PIECE_CENTER_Y := 0.22
const GRID_WIDTH := CELL_SIZE * 8.0
const GRID_HEIGHT := CELL_SIZE * 9.0
const PIECE_RADIUS := CELL_SIZE * 0.40
const BLENDER_MODEL_SCALE := CELL_SIZE / 0.040
const BLENDER_BOARD_TOP := 0.020
const INVALID_POS := Vector2i(-1, -1)
const DEFAULT_ROOM_ID := "manual-chess-001"
const BOARD_VIEW_SIZE := Vector2i(1000, 1140)
const INK := Color("#1b1713")
const GOLD := Color("#efd1a0")

var product: Dictionary = {}
var _landscape_texture: Texture2D
var _portrait_texture: Texture2D
var _board_surface_texture: Texture2D
var _wood_grain_texture: Texture2D

var _socket := WebSocketPeer.new()
var _connected := false
var _joined := false
var _room_id := DEFAULT_ROOM_ID
var _client_id := ""

var _your_color := ""
var _turn := ""
var _winner := ""
var _room_status := "waiting"
var _selected := INVALID_POS

var _stage
var _board_viewport: SubViewport
var _camera: Camera3D
var _piece_root: Node3D
var _board_text_root: Node3D
var _selection_ring: MeshInstance3D
var _pieces_by_pos: Dictionary = {}
var _blender_piece_templates: Dictionary = {}

var _status_label: Label
var _role_label: Label
var _turn_label: Label
var _left_player_label: Label
var _left_timer_label: Label
var _right_player_label: Label
var _right_timer_label: Label
var _background: TextureRect
var _top_shade: ColorRect
var _bottom_shade: ColorRect
var _title_label: Label
var _subtitle_label: Label
var _seal_label: Label
var _left_card: Panel
var _right_card: Panel
var _left_avatar: TextureRect
var _right_avatar: TextureRect
var _left_rank_label: Label
var _right_rank_label: Label
var _board_frame: Panel
var _board_view: TextureRect
var _action_buttons: Array[Button] = []
var _footer_label: Label
var _menu_panel: Panel
var _menu_label: Label
var _menu_close: Button
var _match_duration_label: Label
var _countdown_clock: Control
var _warning_audio: AudioStreamPlayer

# 服务端权威计时状态。客户端仅平滑显示，不自行决定规则超时。
var _server_clock_offset_ms: int = 0
var _match_started_at_ms: int = 0
var _turn_started_at_ms: int = 0
var _step_warning_seconds: int = 60
var _step_countdown_seconds: int = 30
var _last_countdown_second: int = -999


func _ready() -> void:
	_client_id = "pc-%s" % str(OS.get_process_id())
	_landscape_texture = _load_png_texture(LANDSCAPE_TEXTURE_PATH, Color("#2b211b"))
	_portrait_texture = _load_png_texture(PORTRAIT_TEXTURE_PATH, Color("#8a5f45"))
	_board_surface_texture = _load_png_texture(BOARD_SURFACE_TEXTURE_PATH, Color("#935d37"))
	_wood_grain_texture = _load_png_texture(WOOD_GRAIN_TEXTURE_PATH, Color("#65402b"))
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_3d_world()
	_build_hud()
	_show_preview_position()
	resized.connect(_layout_hud)
	_layout_hud()
	_connect_socket()
	set_process(true)


func _process(_delta: float) -> void:
	_socket.poll()
	var state := _socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _connected:
			_connected = true
			_status_label.text = "状态：实时连接已建立，正在加入房间……"
			_send_join()
		while _socket.get_available_packet_count() > 0:
			var packet := _socket.get_packet()
			_handle_message(packet.get_string_from_utf8())
	elif state == WebSocketPeer.STATE_CLOSED and _connected:
		_connected = false
		_joined = false
		_status_label.text = "状态：连接已断开，可重新启动客户端恢复测试。"

	_update_time_ui()


func _on_board_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			var board_pos := _screen_to_board(mouse_event.position)
			if board_pos != INVALID_POS:
				_on_board_pressed(board_pos)
				_board_view.accept_event()


func _build_3d_world() -> void:
	_board_viewport = SubViewport.new()
	_board_viewport.name = "ChessBoardViewport"
	_board_viewport.size = BOARD_VIEW_SIZE
	_board_viewport.transparent_bg = true
	_board_viewport.own_world_3d = true
	_board_viewport.msaa_3d = Viewport.MSAA_4X
	_board_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_board_viewport)

	var world := Node3D.new()
	world.name = "Chess3DWorld"
	_board_viewport.add_child(world)

	_stage = STAGE_SCRIPT.new()
	_stage.name = "TabletopStage"
	world.add_child(_stage)
	_camera = _stage.configure(
		9.7,
		Vector3(0.0, 17.0, 4.2),
		Vector3(0.0, 0.0, 0.0),
		false,
		34.0
	)
	_stage.set_orbit_view(0.0, 4.2, 17.0, Vector3.ZERO)
	_stage.get_node("Floor").visible = false
	var board_environment: WorldEnvironment = _stage.get_node("WorldEnvironment")
	board_environment.environment.background_mode = Environment.BG_CLEAR_COLOR

	var table_material := PBR_FACTORY.create_material(Color("#5c3827"), 0.52, 0.01)
	var frame_material := PBR_FACTORY.create_material(Color("#744b35"), 0.48, 0.01)
	var engraved_material := PBR_FACTORY.create_material(Color("#d2b7a0"), 0.64, 0.0)
	table_material.albedo_texture = _wood_grain_texture
	frame_material.albedo_texture = _wood_grain_texture
	engraved_material.albedo_texture = _board_surface_texture

	_create_box(
		world,
		"ChessTable",
		Vector3(8.55, 0.52, 9.05),
		Vector3(0.0, -0.25, 0.0),
		table_material
	)
	_create_box(
		world,
		"ChessBoardCarvedBody",
		Vector3(8.27, 0.24, 8.69),
		Vector3.ZERO,
		frame_material
	)
	# 棋盘参考图成为三维木板的可替换顶面材质，棋子和落点仍是独立三维对象。
	var engraved_face := MeshInstance3D.new()
	engraved_face.name = "EngravedPlayingSurface"
	var face_mesh := PlaneMesh.new()
	face_mesh.size = Vector2(8.27, 8.69)
	engraved_face.mesh = face_mesh
	engraved_face.material_override = engraved_material
	engraved_face.position.y = 0.128
	world.add_child(engraved_face)
	if _add_blender_assets(world):
		world.get_node("ChessTable").visible = false
		world.get_node("ChessBoardCarvedBody").visible = false
		engraved_face.visible = false

	_piece_root = Node3D.new()
	_piece_root.name = "Pieces"
	world.add_child(_piece_root)

	_selection_ring = MeshInstance3D.new()
	_selection_ring.name = "SelectionRing"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = PIECE_RADIUS * 0.90
	ring_mesh.outer_radius = PIECE_RADIUS * 1.14
	ring_mesh.rings = 32
	ring_mesh.ring_segments = 12
	_selection_ring.mesh = ring_mesh
	_selection_ring.material_override = PBR_FACTORY.create_emissive_material(
		Color("#ffd96a"), Color("#ffb300"), 1.7, 0.28
	)
	_selection_ring.visible = false
	world.add_child(_selection_ring)


func _add_blender_assets(world: Node3D) -> bool:
	if not ResourceLoader.exists(BLENDER_BOARD_PATH) or not ResourceLoader.exists(BLENDER_PIECES_PATH):
		return false
	var board_scene := load(BLENDER_BOARD_PATH) as PackedScene
	var pieces_scene := load(BLENDER_PIECES_PATH) as PackedScene
	if board_scene == null or pieces_scene == null:
		return false
	var library := pieces_scene.instantiate() as Node3D
	library.name = "BlenderPieceLibrary"
	library.visible = false
	world.add_child(library)
	for side in ["Black", "Red"]:
		for role in ["Rook", "Horse", "Elephant", "Advisor", "General", "Cannon", "Soldier"]:
			var template_name: String = "Piece_%s_%s" % [side, role]
			var template := library.find_child(template_name, true, false) as Node3D
			if template != null:
				_blender_piece_templates[template_name] = template
	if _blender_piece_templates.size() != 14:
		_blender_piece_templates.clear()
		library.queue_free()
		return false
	var board := board_scene.instantiate() as Node3D
	board.name = "BlenderBambooBoard"
	board.scale = Vector3.ONE * BLENDER_MODEL_SCALE
	board.position.y = BOARD_Y - BLENDER_BOARD_TOP * BLENDER_MODEL_SCALE
	world.add_child(board)
	# 木材模型使用柔和照明，保留浅竹纹与金丝楠木高光的细节。
	var environment_node: WorldEnvironment = _stage.get_node("WorldEnvironment")
	environment_node.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment.ambient_light_color = Color("#e5dfd6")
	environment_node.environment.ambient_light_energy = 0.42
	var key_light: DirectionalLight3D = _stage.get_node("KeyLight")
	key_light.light_color = Color("#fff4e5")
	key_light.light_energy = 0.95
	var fill_light: OmniLight3D = _stage.get_node("FillLight")
	fill_light.light_energy = 0.45
	return true


func _build_grid(parent: Node3D) -> void:
	var line_material := PBR_FACTORY.create_material(Color("#714923"), 0.64, 0.0)
	var line_width := 0.021
	var river_half_gap := CELL_SIZE * 0.50

	for y in range(10):
		_create_box(
			parent,
			"GridH_%d" % y,
			Vector3(GRID_WIDTH + line_width, 0.026, line_width),
			Vector3(0.0, BOARD_Y, (float(y) - 4.5) * CELL_SIZE),
			line_material
		)

	for x in range(9):
		var world_x := (float(x) - 4.0) * CELL_SIZE
		if x == 0 or x == 8:
			_create_box(
				parent,
				"GridV_%d" % x,
				Vector3(line_width, 0.026, GRID_HEIGHT + line_width),
				Vector3(world_x, BOARD_Y, 0.0),
				line_material
			)
			continue

		var segment_length := GRID_HEIGHT * 0.5 - river_half_gap
		var segment_center := GRID_HEIGHT * 0.25 + river_half_gap * 0.5
		_create_box(
			parent,
			"GridVTop_%d" % x,
			Vector3(line_width, 0.026, segment_length),
			Vector3(world_x, BOARD_Y, -segment_center),
			line_material
		)
		_create_box(
			parent,
			"GridVBottom_%d" % x,
			Vector3(line_width, 0.026, segment_length),
			Vector3(world_x, BOARD_Y, segment_center),
			line_material
		)


func _build_palaces(parent: Node3D) -> void:
	var line_material := PBR_FACTORY.create_material(Color("#714923"), 0.64, 0.0)
	_create_diagonal(parent, "BlackPalaceA", Vector2i(3, 0), Vector2i(5, 2), line_material)
	_create_diagonal(parent, "BlackPalaceB", Vector2i(5, 0), Vector2i(3, 2), line_material)
	_create_diagonal(parent, "RedPalaceA", Vector2i(3, 7), Vector2i(5, 9), line_material)
	_create_diagonal(parent, "RedPalaceB", Vector2i(5, 7), Vector2i(3, 9), line_material)


func _create_diagonal(parent: Node3D, node_name: String, from_pos: Vector2i, to_pos: Vector2i, material: Material) -> void:
	var from_world := _board_to_world(from_pos)
	var to_world := _board_to_world(to_pos)
	var center := (from_world + to_world) * 0.5
	var direction := to_world - from_world
	var length := Vector2(direction.x, direction.z).length()

	var line := _create_box(
		parent,
		node_name,
		Vector3(0.024, 0.026, length),
		Vector3(center.x, BOARD_Y, center.z),
		material
	)
	line.rotation_degrees.y = rad_to_deg(atan2(direction.x, direction.z))


func _build_river_labels(parent: Node3D) -> void:
	_board_text_root = Node3D.new()
	_board_text_root.name = "BoardText"
	parent.add_child(_board_text_root)

	var left := _create_board_label("楚 河", Color("#6b3b20"))
	left.position = Vector3(-1.65, 0.17, 0.0)
	_board_text_root.add_child(left)

	var right := _create_board_label("汉 界", Color("#6b3b20"))
	right.position = Vector3(1.65, 0.17, 0.0)
	_board_text_root.add_child(right)


func _create_board_label(text: String, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = 48
	label.outline_size = 4
	label.modulate = color
	label.outline_modulate = Color("#ba654f")
	label.pixel_size = 0.007
	label.rotation_degrees.x = -90.0
	return label


func _load_png_texture(path: String, fallback_color: Color) -> Texture2D:
	# 导入后的纹理可随 Android 导出打包；开发机首次扫描时再尝试读取 PNG 源文件。
	var imported := ResourceLoader.load(path, "Texture2D")
	if imported is Texture2D:
		return imported as Texture2D
	var image := Image.load_from_file(path)
	if image != null and not image.is_empty():
		return ImageTexture.create_from_image(image)

	# 读取失败时仍生成可见占位纹理，避免单张美术资源导致客户端无法启动。
	var fallback := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	fallback.fill(fallback_color)
	return ImageTexture.create_from_image(fallback)


func _build_hud() -> void:
	_background = TextureRect.new()
	_background.texture = _landscape_texture
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_background)

	_top_shade = ColorRect.new()
	_top_shade.color = Color("#17141388")
	_top_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top_shade)
	_bottom_shade = ColorRect.new()
	_bottom_shade.color = Color("#17100bba")
	_bottom_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bottom_shade)

	_title_label = _make_label(self, "中国象棋", 56, Color("#fff0d1"))
	_subtitle_label = _make_label(self, "楚河汉界 · 棋逢知己", 22, Color("#f2d9ab"))
	_match_duration_label = _make_label(self, "对局时长 00:00", 18, Color("#f5c76e"))
	_seal_label = _make_label(self, "对\n弈", 22, Color.WHITE)
	_seal_label.add_theme_stylebox_override("normal", _flat_style(Color("#9e211d"), Color("#d68b63"), 8, 1))

	_left_card = _create_player_card(true)
	_right_card = _create_player_card(false)

	_board_frame = Panel.new()
	_board_frame.name = "WoodBoardFrame"
	_board_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_frame.add_theme_stylebox_override("panel", _flat_style(Color("#4d291b"), Color("#dfaa69"), 16, 4, 18))
	add_child(_board_frame)
	_board_view = TextureRect.new()
	_board_view.name = "InteractiveBoard"
	_board_view.texture = _board_viewport.get_texture()
	_board_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_board_view.stretch_mode = TextureRect.STRETCH_SCALE
	_board_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_board_view.gui_input.connect(_on_board_gui_input)
	_board_frame.add_child(_board_view)
	_match_duration_label.move_to_front()

	_role_label = _make_label(self, "阵营：连接中", 18, GOLD)
	_turn_label = _make_label(self, "回合：等待", 20, Color("#fff4de"))
	_status_label = _make_label(self, "正在连接本地服务端，棋盘显示开局预览", 17, Color("#fff1d7"))
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	for item in [
		["≡", "菜单"], ["↶", "悔棋"], ["✦", "提示"],
		["◇", "求和"], ["⚑", "认输"], ["✉", "聊天"]
	]:
		var button := Button.new()
		button.text = "%s\n%s" % [item[0], item[1]]
		button.add_theme_font_size_override("font_size", 20)
		button.add_theme_color_override("font_color", GOLD)
		button.add_theme_color_override("font_hover_color", Color.WHITE)
		button.add_theme_stylebox_override("normal", _flat_style(Color("#181a1ccc"), Color("#be9a6b"), 28, 2))
		button.add_theme_stylebox_override("hover", _flat_style(Color("#573322ee"), Color("#f1cf98"), 28, 2))
		button.add_theme_stylebox_override("pressed", _flat_style(Color("#804622"), Color("#fff0cb"), 28, 2))
		button.pressed.connect(_on_action_pressed.bind(str(item[1])))
		add_child(button)
		_action_buttons.append(button)

	_footer_label = _make_label(self, "— 以棋会友 · 乐在棋中 —", 22, Color("#e5b76f"))
	_menu_panel = Panel.new()
	_menu_panel.add_theme_stylebox_override("panel", _flat_style(Color("#251a15f2"), Color("#dcb67b"), 20, 2, 18))
	_menu_panel.visible = false
	add_child(_menu_panel)
	_menu_label = _make_label(_menu_panel, "小板凳象棋", 22, Color("#f3d8ab"))
	_menu_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_menu_close = Button.new()
	_menu_close.text = "返回棋局"
	_menu_close.add_theme_font_size_override("font_size", 18)
	_menu_close.add_theme_stylebox_override("normal", _flat_style(Color("#9e542f"), GOLD, 8, 1))
	_menu_close.pressed.connect(func() -> void: _menu_panel.visible = false)
	_menu_panel.add_child(_menu_close)
	_countdown_clock = COUNTDOWN_CLOCK_SCRIPT.new()
	_countdown_clock.size = Vector2(230.0, 230.0)
	add_child(_countdown_clock)

	_warning_audio = AudioStreamPlayer.new()
	_warning_audio.name = "TurnWarningAudio"
	_warning_audio.stream = WARNING_SOUND_SCRIPT.create_warning_stream()
	_warning_audio.volume_db = -4.0
	add_child(_warning_audio)
	_update_player_panels()


func _make_label(parent: Node, value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color("#180d0bbb"))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _flat_style(fill: Color, stroke: Color, radius: int, border: int, shadow: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = stroke
	style.set_border_width_all(border)
	style.set_corner_radius_all(radius)
	if shadow > 0:
		style.shadow_color = Color("#140b09a8")
		style.shadow_size = shadow
		style.shadow_offset = Vector2(0, 7)
	return style


func _create_player_card(left_side: bool) -> Panel:
	var card := Panel.new()
	card.name = "LeftPlayer" if left_side else "RightPlayer"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", _flat_style(Color("#151413ce"), Color("#c7a274"), 18, 2))
	add_child(card)

	var avatar_frame := Panel.new()
	avatar_frame.name = "AvatarFrame"
	avatar_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar_frame.add_theme_stylebox_override("panel", _flat_style(Color("#a37645"), Color("#f5d6a6"), 80, 3))
	card.add_child(avatar_frame)
	var portrait := TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = _portrait_texture
	var half_width: float = float(_portrait_texture.get_width()) / 2.0
	atlas.region = Rect2(0.0 if left_side else half_width, 0.0, half_width, float(_portrait_texture.get_height()))
	portrait.texture = atlas
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var round_shader := Shader.new()
	round_shader.code = "shader_type canvas_item; void fragment() { vec4 c = texture(TEXTURE, UV); c.a *= 1.0 - smoothstep(0.46, 0.50, distance(UV, vec2(0.5))); COLOR = c; }"
	var round_material := ShaderMaterial.new()
	round_material.shader = round_shader
	portrait.material = round_material
	avatar_frame.add_child(portrait)

	var name_label := _make_label(card, "等待玩家", 23, Color("#fff1d9"))
	var rank_label := _make_label(card, "象棋对弈", 15, Color("#d8b77e"))
	var timer_label := _make_label(card, "--:--", 27, Color("#f2e9d4"))
	if left_side:
		_left_avatar = portrait
		_left_player_label = name_label
		_left_rank_label = rank_label
		_left_timer_label = timer_label
	else:
		_right_avatar = portrait
		_right_player_label = name_label
		_right_rank_label = rank_label
		_right_timer_label = timer_label
	return card


func _layout_hud() -> void:
	if _board_frame == null or size.x < 100.0 or size.y < 100.0:
		return
	var w := size.x
	var h := size.y
	var portrait := h > w * 1.12
	var board_w: float
	var board_h: float
	var board_x: float
	var board_y: float
	var card_w: float
	var card_h: float
	var card_y: float
	var avatar_size: float
	var scale_factor: float
	if portrait:
		board_w = minf(w - 12.0, h * 0.64 / 1.14)
		board_h = board_w * 1.14
		board_x = (w - board_w) * 0.5
		board_y = h * 0.159
		card_w = (board_w - 16.0) * 0.5
		card_h = h * 0.068
		card_y = board_y - card_h - 14.0
		avatar_size = minf(card_h - 10.0, card_w * 0.28)
		scale_factor = minf(1.0, w / 940.0)
		_top_shade.position = Vector2.ZERO
		_top_shade.size = Vector2(w, board_y)
		_bottom_shade.position = Vector2(0, board_y + board_h + 8.0)
		_bottom_shade.size = Vector2(w, h - _bottom_shade.position.y)
		_title_label.position = Vector2(board_x + board_w * 0.20, h * 0.010)
		_title_label.size = Vector2(board_w * 0.60, h * 0.050)
		_subtitle_label.position = Vector2(board_x + board_w * 0.16, h * 0.058)
		_subtitle_label.size = Vector2(board_w * 0.68, h * 0.022)
		_match_duration_label.position = Vector2(board_x + board_w * 0.25, board_y + 5.0)
		_match_duration_label.size = Vector2(board_w * 0.50, 28.0)
		_seal_label.position = Vector2(board_x + board_w * 0.78, h * 0.022)
		_seal_label.size = Vector2(board_w * 0.055, h * 0.050)
		_left_card.position = Vector2(board_x + 3.0, card_y)
		_right_card.position = Vector2(board_x + board_w - card_w - 3.0, card_y)
		_role_label.position = Vector2(board_x, board_y + board_h + 8.0)
		_role_label.size = Vector2(board_w * 0.36, 32.0)
		_turn_label.position = Vector2(board_x + board_w * 0.36, board_y + board_h + 8.0)
		_turn_label.size = Vector2(board_w * 0.64, 32.0)
		var action_y := board_y + board_h + 44.0
		var gap := 8.0
		var action_w := (board_w - gap * 5.0) / 6.0
		for i in range(_action_buttons.size()):
			_action_buttons[i].position = Vector2(board_x + i * (action_w + gap), action_y)
			_action_buttons[i].size = Vector2(action_w, minf(92.0, h * 0.064))
		_status_label.position = Vector2(board_x + 4.0, action_y + minf(92.0, h * 0.064) + 10.0)
		_status_label.size = Vector2(board_w - 8.0, 38.0)
		_footer_label.position = Vector2(board_x, h - maxf(45.0, h * 0.04))
		_footer_label.size = Vector2(board_w, 35.0)
	else:
		board_h = h * 0.70
		board_w = board_h / 1.14
		board_x = (w - board_w) * 0.5
		board_y = h * 0.12
		card_w = maxf(180.0, minf(330.0, (w - board_w) * 0.5 - 34.0))
		card_h = minf(150.0, h * 0.21)
		card_y = h * 0.24
		avatar_size = minf(card_h - 20.0, card_w * 0.31)
		scale_factor = minf(0.85, h / 840.0)
		_top_shade.position = Vector2.ZERO
		_top_shade.size = Vector2(w, h * 0.12)
		_bottom_shade.position = Vector2(0, h * 0.87)
		_bottom_shade.size = Vector2(w, h * 0.13)
		_title_label.position = Vector2(board_x + board_w * 0.10, 3.0)
		_title_label.size = Vector2(board_w * 0.80, h * 0.065)
		_subtitle_label.position = Vector2(board_x + board_w * 0.15, h * 0.062)
		_subtitle_label.size = Vector2(board_w * 0.70, h * 0.036)
		_match_duration_label.position = Vector2(board_x + board_w * 0.25, board_y + 3.0)
		_match_duration_label.size = Vector2(board_w * 0.50, 24.0)
		_seal_label.position = Vector2(board_x + board_w * 0.80, 6.0)
		_seal_label.size = Vector2(34.0, 48.0)
		_left_card.position = Vector2(maxf(12.0, board_x - card_w - 18.0), card_y)
		_right_card.position = Vector2(minf(w - card_w - 12.0, board_x + board_w + 18.0), card_y)
		_role_label.position = Vector2(_left_card.position.x, card_y + card_h + 15.0)
		_role_label.size = Vector2(card_w, 34.0)
		_turn_label.position = Vector2(_right_card.position.x, card_y + card_h + 15.0)
		_turn_label.size = Vector2(card_w, 34.0)
		var action_y := h * 0.84
		var action_w := minf(105.0, (w - 60.0) / 6.0)
		var action_gap := minf(24.0, (w - action_w * 6.0) / 7.0)
		var total_action_w := action_w * 6.0 + action_gap * 5.0
		for i in range(_action_buttons.size()):
			_action_buttons[i].position = Vector2((w - total_action_w) * 0.5 + i * (action_w + action_gap), action_y)
			_action_buttons[i].size = Vector2(action_w, h * 0.105)
		_status_label.position = Vector2(board_x + 6.0, board_y + board_h + 5.0)
		_status_label.size = Vector2(board_w - 12.0, 30.0)
		_footer_label.position = Vector2(0, h - 27.0)
		_footer_label.size = Vector2(w, 24.0)
	_board_frame.position = Vector2(board_x, board_y)
	_board_frame.size = Vector2(board_w, board_h)
	_board_view.position = Vector2(7.0, 7.0)
	_board_view.size = Vector2(board_w - 14.0, board_h - 14.0)
	if _countdown_clock != null:
		_countdown_clock.size = Vector2(230.0, 230.0)
		_countdown_clock.position = Vector2(board_x + board_w * 0.5 - 115.0, board_y + board_h * 0.5 - 115.0)
	_left_card.size = Vector2(card_w, card_h)
	_right_card.size = Vector2(card_w, card_h)
	_layout_player_card(_left_card, _left_avatar, _left_player_label, _left_rank_label, _left_timer_label, avatar_size, scale_factor)
	_layout_player_card(_right_card, _right_avatar, _right_player_label, _right_rank_label, _right_timer_label, avatar_size, scale_factor)
	_title_label.add_theme_font_size_override("font_size", roundi(56.0 * scale_factor))
	_subtitle_label.add_theme_font_size_override("font_size", roundi(22.0 * scale_factor))
	_match_duration_label.add_theme_font_size_override("font_size", roundi(18.0 * scale_factor))
	_seal_label.add_theme_font_size_override("font_size", roundi(22.0 * scale_factor))
	_menu_panel.size = Vector2(minf(400.0, w * 0.78), 210.0)
	_menu_panel.position = (size - _menu_panel.size) * 0.5
	_menu_label.position = Vector2(20.0, 20.0)
	_menu_label.size = Vector2(_menu_panel.size.x - 40.0, 115.0)
	_menu_close.position = Vector2((_menu_panel.size.x - 130.0) * 0.5, 147.0)
	_menu_close.size = Vector2(130.0, 42.0)


func _layout_player_card(card: Panel, avatar: TextureRect, name_label: Label, rank_label: Label, timer_label: Label, avatar_size: float, scale_factor: float) -> void:
	var frame: Panel = card.get_node("AvatarFrame")
	frame.position = Vector2(7.0, (card.size.y - avatar_size) * 0.5)
	frame.size = Vector2(avatar_size, avatar_size)
	avatar.position = Vector2(3.0, 3.0)
	avatar.size = frame.size - Vector2(6.0, 6.0)
	var text_x := avatar_size + 13.0
	var text_w := card.size.x - text_x - 5.0
	name_label.position = Vector2(text_x, 7.0)
	name_label.size = Vector2(text_w, card.size.y * 0.30)
	rank_label.position = Vector2(text_x, card.size.y * 0.34)
	rank_label.size = Vector2(text_w, card.size.y * 0.22)
	timer_label.position = Vector2(text_x, card.size.y * 0.59)
	timer_label.size = Vector2(text_w, card.size.y * 0.31)
	name_label.add_theme_font_size_override("font_size", roundi(22.0 * scale_factor))
	rank_label.add_theme_font_size_override("font_size", roundi(15.0 * scale_factor))
	timer_label.add_theme_font_size_override("font_size", roundi(27.0 * scale_factor))


func _on_action_pressed(action: String) -> void:
	if action == "菜单":
		_menu_label.text = "小板凳象棋\n房间：%s\n规则：标准象棋 · %s" % [_room_id, str(product.get("rule_version", "1.0.0"))]
		_menu_panel.visible = true
		_menu_panel.move_to_front()
		return
	var detail := "该功能正在接入服务端。"
	if action == "提示":
		detail = "提示需要服务端 AI 能力接入。"
	elif action == "聊天":
		detail = "聊天功能正在接入房间服务。"
	_status_label.text = "%s：%s" % [action, detail]


func _connect_socket() -> void:
	var api_script = load("res://modules/foundation/network/api_client.gd")
	var api = api_script.new()
	var error := _socket.connect_to_url(api.websocket_url())
	if error != OK:
		_status_label.text = "状态：连接服务端失败，错误码=%s" % str(error)


func _send_join() -> void:
	_send_json({
		"type": "chess_join",
		"room_id": _room_id,
		"client_id": _client_id,
		"product_id": product.get("product_id", "xbd_chinese_chess"),
		"game_id": "chinese_chess",
		"rule_set_id": "standard",
		"rule_version": product.get("rule_version", "1.0.0")
	})


func _send_json(payload: Dictionary) -> void:
	if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		_status_label.text = "状态：实时连接尚未就绪。"
		return
	var error := _socket.send_text(JSON.stringify(payload))
	if error != OK:
		_status_label.text = "状态：发送实时消息失败，错误码=%s" % str(error)


func _handle_message(text: String) -> void:
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_status_label.text = "状态：收到无法解析的服务端消息。"
		return
	var message: Dictionary = parsed
	match str(message.get("type", "")):
		"connected":
			_status_label.text = "状态：服务端已连接。"
		"chess_joined":
			if str(message.get("room_id", "")) != _room_id:
				return
			_joined = true
			_your_color = str(message.get("your_color", ""))
			_apply_player_view()
			_status_label.text = "状态：%s" % str(message.get("message", "已加入房间"))
			_update_hud()
		"chess_state":
			if str(message.get("room_id", "")) != _room_id:
				return
			_apply_state(message)
		"chess_error":
			_selected = INVALID_POS
			_status_label.text = "服务端拒绝：%s" % str(message.get("message", "未知错误"))
			_update_selection()
		_:
			pass


func _apply_state(message: Dictionary) -> void:
	var previous_color := _your_color
	_your_color = str(message.get("your_color", _your_color))
	_turn = str(message.get("turn", ""))
	_winner = str(message.get("winner", ""))
	_room_status = str(message.get("status", "waiting"))
	var previous_turn_started_at_ms := _turn_started_at_ms
	var server_time_ms := int(message.get("server_time_ms", 0))
	if server_time_ms > 0:
		_server_clock_offset_ms = server_time_ms - _local_unix_ms()
	_match_started_at_ms = int(message.get("match_started_at_ms", _match_started_at_ms))
	_turn_started_at_ms = int(message.get("turn_started_at_ms", _turn_started_at_ms))
	_step_warning_seconds = int(message.get("step_warning_seconds", 60))
	_step_countdown_seconds = int(message.get("step_countdown_seconds", 30))
	if previous_turn_started_at_ms != _turn_started_at_ms:
		_last_countdown_second = -999
	_pieces_by_pos.clear()

	if previous_color != _your_color:
		_apply_player_view()

	var items = message.get("pieces", [])
	if typeof(items) == TYPE_ARRAY:
		for raw_piece in items:
			if typeof(raw_piece) != TYPE_DICTIONARY:
				continue
			var piece: Dictionary = raw_piece
			var pos := Vector2i(int(piece.get("x", -1)), int(piece.get("y", -1)))
			_pieces_by_pos[pos] = piece

	_selected = INVALID_POS
	_rebuild_piece_models()
	_update_hud()

	if _winner != "":
		_status_label.text = "本局结束：%s获胜。" % _color_name(_winner)
	elif _room_status == "waiting":
		_status_label.text = "状态：等待第二位玩家进入同一房间。"
	elif _turn == _your_color:
		_status_label.text = "状态：轮到你走棋。"
	else:
		_status_label.text = "状态：等待对方走棋。"


func _apply_player_view() -> void:
	if _stage == null:
		return
	if _your_color == "black":
		_stage.set_orbit_view(180.0, 4.2, 17.0, Vector3.ZERO)
	else:
		_stage.set_orbit_view(0.0, 4.2, 17.0, Vector3.ZERO)

	_rebuild_piece_models()


func _rebuild_piece_models() -> void:
	if _piece_root == null:
		return
	for child in _piece_root.get_children():
		child.queue_free()

	for pos in _pieces_by_pos.keys():
		var piece: Dictionary = _pieces_by_pos[pos]
		var model := _create_piece_model(piece)
		model.position = _board_to_world(pos)
		if model.has_meta("blender_piece"):
			model.position.y = BOARD_Y + 0.0002 * BLENDER_MODEL_SCALE
		_piece_root.add_child(model)

	_update_selection()


func _create_piece_model(piece: Dictionary) -> Node3D:
	var piece_type := str(piece.get("type", ""))
	var model_role := "Rook" if piece_type == "chariot" else piece_type.capitalize()
	var template_name := "Piece_%s_%s" % [str(piece.get("color", "")).capitalize(), model_role]
	var template := _blender_piece_templates.get(template_name) as Node3D
	if template != null:
		var imported := template.duplicate() as Node3D
		imported.name = str(piece.get("id", "ChessPiece"))
		imported.visible = true
		imported.scale *= BLENDER_MODEL_SCALE
		if _your_color == "black":
			imported.rotation_degrees.y += 180.0
		imported.set_meta("blender_piece", true)
		return imported
	var root := Node3D.new()
	root.name = str(piece.get("id", "ChessPiece"))

	var body := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = PIECE_RADIUS
	cylinder.bottom_radius = PIECE_RADIUS * 1.03
	cylinder.height = 0.17
	cylinder.radial_segments = 40
	body.mesh = cylinder
	body.material_override = PBR_FACTORY.create_material(Color("#946138"), 0.39, 0.01)
	root.add_child(body)

	var top_disc := MeshInstance3D.new()
	var top_cylinder := CylinderMesh.new()
	top_cylinder.top_radius = PIECE_RADIUS * 0.88
	top_cylinder.bottom_radius = PIECE_RADIUS * 0.88
	top_cylinder.height = 0.026
	top_cylinder.radial_segments = 40
	top_disc.mesh = top_cylinder
	top_disc.position.y = 0.097
	top_disc.material_override = PBR_FACTORY.create_material(Color("#f0d7a8"), 0.48, 0.0)
	root.add_child(top_disc)

	var color := str(piece.get("color", ""))
	var label := Label3D.new()
	label.text = _piece_symbol(color, str(piece.get("type", "")))
	label.font_size = 62
	label.outline_size = 4
	label.pixel_size = 0.0050
	label.position.y = 0.116
	label.rotation_degrees.x = -90.0
	if _your_color == "black":
		label.rotation_degrees.y = 180.0
	if color == "red":
		label.modulate = Color("#c2201c")
		label.outline_modulate = Color("#f3d6ac")
	else:
		label.modulate = Color("#15100e")
		label.outline_modulate = Color("#f1d5aa")
	root.add_child(label)

	return root


func _update_hud() -> void:
	if _role_label == null:
		return
	if _your_color == "":
		_role_label.text = "阵营：观战"
	else:
		_role_label.text = "阵营：%s" % _color_name(_your_color)
	if _winner != "":
		_turn_label.text = "胜方：%s" % _color_name(_winner)
	elif _turn == "":
		_turn_label.text = "回合：等待"
	else:
		_turn_label.text = "回合：%s" % _color_name(_turn)
	_update_player_panels()


func _update_player_panels() -> void:
	if _left_player_label == null or _right_player_label == null:
		return
	if _your_color == "black":
		_left_player_label.text = "黑方 · 我"
		_right_player_label.text = "红方 · 对手"
	else:
		_left_player_label.text = "红方 · 我"
		_right_player_label.text = "黑方 · 对手"
	_left_rank_label.text = "本局执棋"
	_right_rank_label.text = "同室棋友"
	# 计时由 _update_time_ui() 使用服务端权威时间戳持续刷新。
	_update_time_ui()


func _update_time_ui() -> void:
	if _match_duration_label == null or _left_timer_label == null or _right_timer_label == null:
		return

	var now_ms := _authoritative_now_ms()
	if _match_started_at_ms > 0:
		var match_elapsed := maxi(0, int((now_ms - _match_started_at_ms) / 1000))
		_match_duration_label.text = "对局时长 %s" % _format_duration(match_elapsed)
	else:
		_match_duration_label.text = "对局时长 00:00"

	if _room_status != "playing" or _turn_started_at_ms <= 0 or _winner != "":
		_left_timer_label.text = "--:--"
		_right_timer_label.text = "--:--"
		_left_timer_label.add_theme_color_override("font_color", Color("#f2e9d4"))
		_right_timer_label.add_theme_color_override("font_color", Color("#f2e9d4"))
		if _countdown_clock != null:
			_countdown_clock.hide_clock()
		_last_countdown_second = -999
		return

	var turn_elapsed := maxi(0, int((now_ms - _turn_started_at_ms) / 1000))
	var left_color := "black" if _your_color == "black" else "red"
	var right_color := "red" if left_color == "black" else "black"
	_update_side_step_timer(_left_timer_label, left_color, turn_elapsed)
	_update_side_step_timer(_right_timer_label, right_color, turn_elapsed)

	if turn_elapsed <= _step_warning_seconds:
		if _countdown_clock != null:
			_countdown_clock.hide_clock()
		_last_countdown_second = -999
		return

	var overdue_seconds := turn_elapsed - _step_warning_seconds
	var remaining := _step_countdown_seconds - overdue_seconds
	var side_text := _color_name(_turn)

	if remaining > 0:
		if _countdown_clock != null:
			_countdown_clock.show_countdown(remaining, _step_countdown_seconds, side_text)
		if remaining != _last_countdown_second:
			# 进入倒计时立即提醒一次，最后10秒每秒提醒；声音只提醒当前执棋方本人。
			if _turn == _your_color and (remaining == _step_countdown_seconds or remaining <= 10):
				_play_warning_tone()
			_last_countdown_second = remaining
	else:
		if _countdown_clock != null:
			_countdown_clock.show_timeout(side_text)
		if _last_countdown_second != 0:
			if _turn == _your_color:
				_play_warning_tone()
			_last_countdown_second = 0


func _update_side_step_timer(label: Label, side_color: String, elapsed_seconds: int) -> void:
	if side_color != _turn:
		label.text = "等待"
		label.add_theme_color_override("font_color", Color("#b9ad99"))
		return

	if elapsed_seconds <= _step_warning_seconds:
		label.text = "本步 %s" % _format_duration(elapsed_seconds)
		label.add_theme_color_override("font_color", Color("#f2e9d4"))
		return

	var remaining := maxi(0, _step_countdown_seconds - (elapsed_seconds - _step_warning_seconds))
	label.text = "倒计时 %02d" % remaining
	label.add_theme_color_override("font_color", Color("#ff5540"))


func _authoritative_now_ms() -> int:
	return _local_unix_ms() + _server_clock_offset_ms


func _local_unix_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


func _format_duration(total_seconds: int) -> String:
	var safe_seconds := maxi(total_seconds, 0)
	var hours := safe_seconds / 3600
	var minutes := (safe_seconds % 3600) / 60
	var seconds := safe_seconds % 60
	if hours > 0:
		return "%02d:%02d:%02d" % [hours, minutes, seconds]
	return "%02d:%02d" % [minutes, seconds]


func _play_warning_tone() -> void:
	if _warning_audio == null:
		return
	_warning_audio.stop()
	_warning_audio.play()


func _show_preview_position() -> void:
	# 未连接时只展示标准开局排布；服务端 chess_state 到达即整体替换。
	if not _pieces_by_pos.is_empty():
		return
	var major_types: Array[String] = ["chariot", "horse", "elephant", "advisor", "general", "advisor", "elephant", "horse", "chariot"]
	for x in range(9):
		var major_type := major_types[x]
		_pieces_by_pos[Vector2i(x, 0)] = {"id": "preview-black-%d" % x, "color": "black", "type": major_type}
		_pieces_by_pos[Vector2i(x, 9)] = {"id": "preview-red-%d" % x, "color": "red", "type": major_type}
	for x in [1, 7]:
		_pieces_by_pos[Vector2i(x, 2)] = {"id": "preview-black-cannon-%d" % x, "color": "black", "type": "cannon"}
		_pieces_by_pos[Vector2i(x, 7)] = {"id": "preview-red-cannon-%d" % x, "color": "red", "type": "cannon"}
	for x in [0, 2, 4, 6, 8]:
		_pieces_by_pos[Vector2i(x, 3)] = {"id": "preview-black-soldier-%d" % x, "color": "black", "type": "soldier"}
		_pieces_by_pos[Vector2i(x, 6)] = {"id": "preview-red-soldier-%d" % x, "color": "red", "type": "soldier"}
	_rebuild_piece_models()


func _on_board_pressed(pos: Vector2i) -> void:
	if not _joined:
		_status_label.text = "状态：尚未加入房间。"
		return
	if _your_color != "red" and _your_color != "black":
		_status_label.text = "状态：当前是观战身份。"
		return
	if _winner != "":
		_status_label.text = "状态：本局已经结束。"
		return
	if _room_status != "playing":
		_status_label.text = "状态：等待双方就绪后才能走棋。"
		return
	if _turn != _your_color:
		_status_label.text = "状态：当前不是你的回合。"
		return

	var clicked_piece := _piece_at(pos)
	if _selected == INVALID_POS:
		if clicked_piece.is_empty():
			_status_label.text = "请选择自己的三维棋子。"
			return
		if str(clicked_piece.get("color", "")) != _your_color:
			_status_label.text = "不能选择对方棋子。"
			return
		_selected = pos
		_status_label.text = "已选择%s，请点击目标格。" % _piece_symbol(_your_color, str(clicked_piece.get("type", "")))
		_update_selection()
		return

	if not clicked_piece.is_empty() and str(clicked_piece.get("color", "")) == _your_color:
		_selected = pos
		_status_label.text = "已切换选择，请点击目标格。"
		_update_selection()
		return

	var selected_piece := _piece_at(_selected)
	if selected_piece.is_empty():
		_selected = INVALID_POS
		_update_selection()
		return

	_send_json({
		"type": "chess_move",
		"piece_id": selected_piece.get("id", ""),
		"from": {"x": _selected.x, "y": _selected.y},
		"to": {"x": pos.x, "y": pos.y}
	})
	_status_label.text = "状态：已提交走子，等待服务端权威判定……"
	_selected = INVALID_POS
	_update_selection()


func _update_selection() -> void:
	if _selection_ring == null:
		return
	if _selected == INVALID_POS:
		_selection_ring.visible = false
		return
	_selection_ring.position = _board_to_world(_selected) + Vector3(0.0, -0.04, 0.0)
	_selection_ring.visible = true


func _screen_to_board(screen_pos: Vector2) -> Vector2i:
	if _camera == null or _board_view == null or _board_view.size.x <= 0.0 or _board_view.size.y <= 0.0:
		return INVALID_POS
	var viewport_pos := Vector2(
		screen_pos.x * BOARD_VIEW_SIZE.x / _board_view.size.x,
		screen_pos.y * BOARD_VIEW_SIZE.y / _board_view.size.y
	)
	var ray_origin := _camera.project_ray_origin(viewport_pos)
	var ray_direction := _camera.project_ray_normal(viewport_pos)
	if absf(ray_direction.y) < 0.00001:
		return INVALID_POS
	var distance := (BOARD_Y - ray_origin.y) / ray_direction.y
	if distance <= 0.0:
		return INVALID_POS
	var hit := ray_origin + ray_direction * distance
	var x := roundi(hit.x / CELL_SIZE + 4.0)
	var y := roundi(hit.z / CELL_SIZE + 4.5)
	if x < 0 or x > 8 or y < 0 or y > 9:
		return INVALID_POS
	var snapped := _board_to_world(Vector2i(x, y))
	if Vector2(hit.x - snapped.x, hit.z - snapped.z).length() > CELL_SIZE * 0.48:
		return INVALID_POS
	return Vector2i(x, y)


func _board_to_world(pos: Vector2i) -> Vector3:
	return Vector3(
		(float(pos.x) - 4.0) * CELL_SIZE,
		PIECE_CENTER_Y,
		(float(pos.y) - 4.5) * CELL_SIZE
	)


func _piece_at(pos: Vector2i) -> Dictionary:
	var value = _pieces_by_pos.get(pos, {})
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _create_box(parent: Node3D, node_name: String, size: Vector3, position_value: Vector3, material: Material) -> MeshInstance3D:
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = box_mesh
	instance.position = position_value
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _color_name(color: String) -> String:
	return "红方" if color == "red" else "黑方"


func _piece_symbol(color: String, piece_type: String) -> String:
	if color == "red":
		match piece_type:
			"general": return "帅"
			"advisor": return "仕"
			"elephant": return "相"
			"horse": return "马"
			"chariot": return "车"
			"cannon": return "炮"
			"soldier": return "兵"
	else:
		match piece_type:
			"general": return "将"
			"advisor": return "士"
			"elephant": return "象"
			"horse": return "马"
			"chariot": return "车"
			"cannon": return "炮"
			"soldier": return "卒"
	return "?"
