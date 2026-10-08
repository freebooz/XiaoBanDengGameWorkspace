extends Control
signal request_return_to_lobby
## ChineseChess3DScreen（小板凳象棋三维在线对局界面）
## 国风横屏对弈布局：上下玩家侧栏、厚木棋盘、立体棋子与独立操作区。
## 红黑双方分别从自己的棋盘一侧观察，黑方相机与红方相差180度。
## 服务端棋盘坐标始终保持统一，客户端只旋转摄像机，不旋转权威棋局数据。

const STAGE_SCRIPT = preload("res://modules/game_framework/tabletop3d/tabletop_stage.gd")
const TRAINING_RULES_SCRIPT = preload("res://modules/games/chinese_chess/chess_training_rules.gd")
const PBR_FACTORY = preload("res://modules/game_framework/tabletop3d/pbr_material_factory.gd")
const COUNTDOWN_CLOCK_SCRIPT = preload("res://modules/foundation/ui/turn_countdown_clock.gd")
const WARNING_SOUND_SCRIPT = preload("res://modules/foundation/audio/turn_warning_sound.gd")
const DISPLAY = preload("res://modules/foundation/ui/battle_display.gd")
const CHROME = preload("res://modules/foundation/ui/battle_chrome.gd")
const LANDSCAPE_TEXTURE_PATH := "res://modules/games/chinese_chess/assets/ink_landscape_background.png"
const PORTRAIT_TEXTURE_PATH := "res://modules/games/chinese_chess/assets/player_portraits.png"
const BOARD_SURFACE_TEXTURE_PATH := "res://modules/games/chinese_chess/assets/engraved_chessboard.png"
const WOOD_GRAIN_TEXTURE_PATH := "res://modules/games/chinese_chess/assets/red_sandalwood_woodgrain.png"
const GOLDEN_NANMU_TEXTURE_PATH := "res://modules/games/chinese_chess/assets/golden_nanmu_woodgrain.png"
const BLENDER_BOARD_PATH := "res://modules/games/chinese_chess/assets/models/chess_board.glb"
const BLENDER_PIECES_PATH := "res://modules/games/chinese_chess/assets/models/chess_pieces.glb"
const MOVE_SOUND_PATH := "res://modules/games/chinese_chess/assets/audio/sfx_chess_move_wood_01.wav"
const MOVE_SOUND_FALLBACK_PATH := "res://modules/games/chinese_chess/assets/audio/move_wood.wav"
const BGM_PATH := "res://modules/games/chinese_chess/assets/audio/bgm_chinese_guzheng_01.mp3"
const BGM_FALLBACK_PATH := "res://modules/games/chinese_chess/assets/audio/bgm_guofeng.wav"
const ACTION_ICON_ROOT := "res://modules/games/chinese_chess/assets/ui/mobile/"
const BRAND_STOOL_PATH := ACTION_ICON_ROOT + "brand_stool_3d.png"

const CELL_SIZE := 0.86
const BOARD_Y := 0.125
const PIECE_CENTER_Y := 0.22
const GRID_WIDTH := CELL_SIZE * 8.0
const GRID_HEIGHT := CELL_SIZE * 9.0
const PIECE_RADIUS := CELL_SIZE * 0.45
const BLENDER_MODEL_SCALE := CELL_SIZE / 0.040
const BLENDER_BOARD_TOP := 0.020
const INVALID_POS := Vector2i(-1, -1)
const DEFAULT_ROOM_ID := "1000"
const BOARD_VIEW_SIZE := Vector2i(1000, 1140)
const CAMERA_FOV := 35.0
const CAMERA_HEIGHT := BOARD_Y + 18.0
const CAMERA_RADIUS := 2.5
const VISUAL_SETTINGS_PATH := "user://chinese_chess_visuals.cfg"
const QUALITY_SIZES := [Vector2i(750, 855), Vector2i(1000, 1140), Vector2i(1500, 1710)]
const QUALITY_MSAA := [Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X]
const INK := Color("#1b1713")
const GOLD := Color("#efd1a0")
enum LayoutMode {
	PHONE_LANDSCAPE,
	TABLET_LANDSCAPE,
	DESKTOP,
	WIDE_DESKTOP,
}


var product: Dictionary = {}
var match_context: Dictionary = {}
var training_mode := false
var _landscape_texture: Texture2D
var _portrait_texture: Texture2D
var _board_surface_texture: Texture2D
var _wood_grain_texture: Texture2D
var _golden_nanmu_texture: Texture2D

var _socket := WebSocketPeer.new()
var _connected := false
var _joined := false
var _room_id := DEFAULT_ROOM_ID
var _client_id := ""

var _your_color := ""
var _turn := ""
var _winner := ""
var _loser := ""
var _end_reason := ""
var _dissolved := false
var _finished_at_ms: int = 0
var _room_status := "waiting"
var _selected := INVALID_POS
var _move_number := 1
var _layout_mode := LayoutMode.PHONE_LANDSCAPE
var _last_reported_layout_mode := -1

var _stage
var _board_viewport: SubViewport
var _camera: Camera3D
var _piece_root: Node3D
var _board_text_root: Node3D
var _selection_ring: MeshInstance3D
var _pieces_by_pos: Dictionary = {}
var _blender_piece_templates: Dictionary = {}
var _grid_x_m := PackedFloat64Array([-.160, -.120, -.080, -.040, 0, .040, .080, .120, .160])
var _grid_y_m := PackedFloat64Array([.180, .140, .100, .060, .020, -.020, -.060, -.100, -.140, -.180])
var _grid_registration_loaded := false
var _pbr_material_reported := false

var _status_label: Label
var _role_label: Label
var _turn_label: Label
var _turn_status_label: Label
var _round_status_label: Label
var _left_player_label: Label
var _left_timer_label: Label
var _right_player_label: Label
var _right_timer_label: Label
var _chrome: Control
var _match_info_panel: Panel
var _action_panel: Panel
var _action_title: Label
var _action_hint: Label
var _status_panel: Panel
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
var _music_quick_button: Button
var _settings_quick_button: Button
var _menu_overlay: ColorRect
var _menu_panel: Panel
var _menu_label: Label
var _menu_close: Button
var _quality_label: Label
var _quality_option: OptionButton
var _render_quality := 1
var _match_duration_label: Label
var _countdown_clock: Control
var _warning_audio: AudioStreamPlayer
var _move_audio: AudioStreamPlayer
var _bgm_audio: AudioStreamPlayer
var _bgm_enabled := true
var _app_has_focus := true
var _sfx_enabled := true
var _bgm_toggle_button: Button
var _sfx_toggle_button: Button
var _settlement_overlay: ColorRect
var _settlement_panel: Panel
var _settlement_title: Label
var _settlement_detail: Label
var _settlement_stats: Label
var _settlement_review_button: Button
var _settlement_lobby_button: Button
var _settlement_shown := false
var _auto_validation_move_sent := false

# 服务端权威计时状态。客户端仅平滑显示，不自行决定规则超时。
var _server_clock_offset_ms: int = 0
var _match_started_at_ms: int = 0
var _turn_started_at_ms: int = 0
var _step_warning_seconds: int = 60
var _step_countdown_seconds: int = 30
var _last_countdown_second: int = -999


func _ready() -> void:
	DISPLAY.enter(self)
	_room_id = str(match_context.get("room_id", DEFAULT_ROOM_ID))
	_client_id = str(match_context.get("account_id", ""))
	if _client_id == "":
		_client_id = "pc-%s" % str(OS.get_process_id())
	print("CHESS_CONTEXT room=%s client=%s" % [_room_id, _client_id])
	_landscape_texture = _load_png_texture(LANDSCAPE_TEXTURE_PATH, Color("#2b211b"))
	_portrait_texture = _load_png_texture(PORTRAIT_TEXTURE_PATH, Color("#8a5f45"))
	_board_surface_texture = _load_png_texture(BOARD_SURFACE_TEXTURE_PATH, Color("#935d37"))
	_wood_grain_texture = _load_png_texture(WOOD_GRAIN_TEXTURE_PATH, Color("#65402b"))
	_golden_nanmu_texture = _load_png_texture(GOLDEN_NANMU_TEXTURE_PATH, Color("#d2ad6f"))
	mouse_filter = Control.MOUSE_FILTER_PASS
	_load_render_quality()
	_build_3d_world()
	_build_hud()
	_apply_render_quality(_render_quality, false)
	_show_preview_position()
	resized.connect(_layout_hud)
	_layout_hud()
	if training_mode:
		_joined = true
		_your_color = "red"
		_turn = "red"
		_room_status = "playing"
		_apply_player_view()
		_update_hud()
		_status_label.text = "双人同机训练 · 红方先走，点击棋子与目标格"
		set_process(false)
	else:
		_connect_socket()
		set_process(true)


func _exit_tree() -> void:
	DISPLAY.leave(self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_app_has_focus = true
		_sync_bgm_playback()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_app_has_focus = false
		_sync_bgm_playback()


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
	# Touch generates an emulated mouse press before the real touch event.
	if event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			var board_pos := _screen_to_board(mouse_event.position)
			if board_pos != INVALID_POS:
				_on_board_pressed(board_pos)
				_board_view.accept_event()
	elif event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			var board_pos := _screen_to_board(touch_event.position)
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
		Vector3(0.0, CAMERA_HEIGHT, CAMERA_RADIUS),
		Vector3(0.0, BOARD_Y, 0.0),
		true,
		CAMERA_FOV
	)
	_stage.set_orbit_view(0.0, CAMERA_RADIUS, CAMERA_HEIGHT, Vector3(0.0, BOARD_Y, 0.0))
	_stage.get_node("Floor").visible = false
	var board_environment: WorldEnvironment = _stage.get_node("WorldEnvironment")
	board_environment.environment.background_mode = Environment.BG_CLEAR_COLOR

	# 恢复早期檀木棋盘：红檀木厚底座/边框 + 温润雕刻盘面。
	var table_material := PBR_FACTORY.create_material(Color("#4b1f19"), 0.42, 0.01)
	var frame_material := PBR_FACTORY.create_material(Color("#6c2a21"), 0.38, 0.01)
	var engraved_material := PBR_FACTORY.create_material(Color("#d3aa70"), 0.52, 0.0)
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
	# 优先使用真正的雕刻三维棋盘；程序化棋盘仅作为资源加载失败时的降级方案。
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
	# Godot 4.x 对 .glb 源路径的 ResourceLoader.exists() 在部分运行模式下可能返回 false，
	# 即使资源已经被编辑器正确导入；因此直接加载 PackedScene，并以 null 作为降级判断。
	var board_scene := ResourceLoader.load(BLENDER_BOARD_PATH, "PackedScene") as PackedScene
	var pieces_scene := ResourceLoader.load(BLENDER_PIECES_PATH, "PackedScene") as PackedScene
	print("CHESS_GLTF_LOAD board=%s pieces=%s" % [str(board_scene != null), str(pieces_scene != null)])
	if board_scene == null or pieces_scene == null:
		return false

	var board := board_scene.instantiate() as Node3D
	board.name = "BlenderRedSandalwoodBoard"
	board.scale = Vector3.ONE * BLENDER_MODEL_SCALE
	board.position.y = BOARD_Y - BLENDER_BOARD_TOP * BLENDER_MODEL_SCALE
	world.add_child(board)
	_load_board_grid_registration(board)
	_configure_board_visuals(board)
	var physical_board_width := 0.412 * BLENDER_MODEL_SCALE
	var physical_board_height := 0.452 * BLENDER_MODEL_SCALE
	var horizontal_clearance := (physical_board_width - GRID_WIDTH) * 0.5 - PIECE_RADIUS
	var vertical_clearance := (physical_board_height - GRID_HEIGHT) * 0.5 - PIECE_RADIUS
	print("CHESS_BOARD_CLEARANCE horizontal=%.3f vertical=%.3f" % [horizontal_clearance, vertical_clearance])

	var library := pieces_scene.instantiate() as Node3D
	library.name = "BlenderPieceLibrary"
	library.visible = false
	world.add_child(library)
	for side in ["Black", "Red"]:
		for role in ["Rook", "Horse", "Elephant", "Advisor", "General", "Cannon", "Soldier"]:
			var template_name: String = "Piece_%s_%s" % [side, role]
			var template := library.find_child(template_name, true, false) as Node3D
			if template != null:
				_configure_piece_template_visuals(template)
				_blender_piece_templates[template_name] = template
	if _blender_piece_templates.size() != 14:
		_blender_piece_templates.clear()
		library.queue_free()
		return false

	# 降低暖光强度，避免金丝楠木纹理被高光洗平。
	var environment_node: WorldEnvironment = _stage.get_node("WorldEnvironment")
	environment_node.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment.ambient_light_color = Color("#e4d4c2")
	environment_node.environment.ambient_light_energy = 0.27
	var reflection_sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#75808b")
	sky_material.sky_horizon_color = Color("#e7dac1")
	sky_material.ground_horizon_color = Color("#7b6250")
	sky_material.ground_bottom_color = Color("#191511")
	reflection_sky.sky_material = sky_material
	environment_node.environment.sky = reflection_sky
	environment_node.environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var key_light: DirectionalLight3D = _stage.get_node("KeyLight")
	key_light.light_color = Color("#fff2df")
	key_light.light_energy = 0.72
	var fill_light: OmniLight3D = _stage.get_node("FillLight")
	fill_light.light_color = Color("#d9a576")
	fill_light.light_energy = 0.26
	return true


func _load_board_grid_registration(board: Node) -> void:
	var mesh := board.find_child("ChessBoard_RedSandalwood", true, false)
	if mesh == null:
		return
	var extras: Dictionary = mesh.get_meta("extras", {})
	var xs: Array = extras.get("grid_x_m", [])
	var ys: Array = extras.get("grid_y_m", [])
	if xs.size() != 9 or ys.size() != 10:
		return
	for i in range(xs.size()):
		if not is_finite(float(xs[i])) or absf(float(xs[i])) > .161:
			return
		if i > 0 and float(xs[i]) - float(xs[i - 1]) < .030:
			return
	for i in range(ys.size()):
		if not is_finite(float(ys[i])) or absf(float(ys[i])) > .181:
			return
		if i > 0 and float(ys[i - 1]) - float(ys[i]) < .030:
			return
	_grid_x_m = PackedFloat64Array(xs)
	_grid_y_m = PackedFloat64Array(ys)
	_grid_registration_loaded = true
	print("CHESS_GRID_REGISTRATION loaded=true files=9 ranks=10")


func _configure_board_visuals(node: Node) -> void:
	# 棋盘在不同俯视角下统一使用各向异性 Mipmap，强化红檀木木纹和雕刻沟槽边缘。
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface_index in range(mesh_instance.mesh.get_surface_count()):
				var source_material := mesh_instance.get_active_material(surface_index)
				if source_material is StandardMaterial3D:
					var material := source_material.duplicate() as StandardMaterial3D
					material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
					material.texture_repeat = false
					if material.albedo_texture != null:
						material.clearcoat_enabled = true
						material.clearcoat = 0.20
						material.clearcoat_roughness = 0.24
						material.roughness = 0.40
					mesh_instance.set_surface_override_material(surface_index, material)
					print("CHESS_BOARD_PBR material=%s albedo=%s normal=%s roughness=%s" % [
						material.resource_name,
						str(material.albedo_texture != null),
						str(material.normal_enabled and material.normal_texture != null),
						str(material.roughness_texture != null),
					])
	for child in node.get_children():
		_configure_board_visuals(child)


func _load_render_quality() -> void:
	var settings := ConfigFile.new()
	if settings.load(VISUAL_SETTINGS_PATH) == OK:
		var saved = settings.get_value("graphics", "quality", 1)
		if saved is int and saved >= 0 and saved <= 2:
			_render_quality = saved


func _apply_render_quality(index: int, persist: bool = true) -> void:
	_render_quality = clampi(index, 0, 2)
	if _board_viewport != null:
		_board_viewport.size = QUALITY_SIZES[_render_quality]
		_board_viewport.msaa_3d = QUALITY_MSAA[_render_quality]
	if _stage != null:
		_stage.get_node("KeyLight").shadow_enabled = _render_quality > 0
		_apply_quality_texture_filter(_board_viewport)
	if _quality_option != null:
		_quality_option.select(_render_quality)
	if persist:
		var settings := ConfigFile.new()
		settings.set_value("graphics", "quality", _render_quality)
		var saved := settings.save(VISUAL_SETTINGS_PATH)
		if saved != OK:
			push_warning("Could not save chess render quality: %s" % error_string(saved))
	print("CHESS_RENDER_QUALITY quality=%d resolution=%s msaa=%d" % [_render_quality, str(QUALITY_SIZES[_render_quality]), QUALITY_MSAA[_render_quality]])


func _apply_quality_texture_filter(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for surface in range(node.mesh.get_surface_count()):
			var material = node.get_active_material(surface)
			if material is StandardMaterial3D:
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if _render_quality == 0 else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	for child in node.get_children():
		_apply_quality_texture_filter(child)


func _configure_piece_template_visuals(node: Node) -> void:
	# 俯视/斜俯视下启用各向异性 Mipmap 过滤，减少木纹在倾斜表面的模糊。
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface_index in range(mesh_instance.mesh.get_surface_count()):
				var source_material := mesh_instance.get_active_material(surface_index)
				if source_material is StandardMaterial3D:
					var tuned_material := source_material.duplicate() as StandardMaterial3D
					tuned_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
					if tuned_material.albedo_texture != null:
						# glTF clearcoat is absent from the imported StandardMaterial3D.
						# Apply the saved Blender lacquer contract explicitly in Godot.
						tuned_material.clearcoat_enabled = true
						tuned_material.clearcoat = 0.58
						tuned_material.clearcoat_roughness = 0.12
						tuned_material.normal_scale = 0.08
					if not _pbr_material_reported and tuned_material.albedo_texture != null:
						_pbr_material_reported = true
						print("CHESS_PBR material=%s albedo=%s normal=%s roughness=%s filter=%s" % [
							tuned_material.resource_name,
							str(tuned_material.albedo_texture != null),
							str(tuned_material.normal_enabled and tuned_material.normal_texture != null),
							str(tuned_material.roughness_texture != null),
							str(tuned_material.texture_filter),
						])
					mesh_instance.set_surface_override_material(surface_index, tuned_material)
	for child in node.get_children():
		_configure_piece_template_visuals(child)


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
	# 开发组合工程直接读取PNG字节，不依赖Godot导入缓存；正式导出时源文件也会随模块复制。
	if FileAccess.file_exists(path):
		var bytes := FileAccess.get_file_as_bytes(path)
		if not bytes.is_empty():
			var image := Image.new()
			var load_error := image.load_png_from_buffer(bytes)
			if load_error == OK and not image.is_empty():
				return ImageTexture.create_from_image(image)

	# PNG缺失或损坏时生成可见占位纹理，避免单张美术资源阻断对局。
	var fallback := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	fallback.fill(fallback_color)
	return ImageTexture.create_from_image(fallback)


func _load_svg_texture(path: String) -> Texture2D:
	var image := Image.new()
	if FileAccess.file_exists(path) and image.load_svg_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
		return ImageTexture.create_from_image(image)
	return _load_png_texture("", GOLD)


func _build_hud() -> void:
	_chrome = CHROME.backdrop(self, "小板凳 · 象棋", "训练" if training_mode else _room_id)
	_chrome.name = "ChessBattleChrome"
	_music_quick_button = Button.new()
	_music_quick_button.name = "MusicQuickButton"
	_music_quick_button.text = "音乐"
	_music_quick_button.tooltip_text = "开启或暂停背景音乐"
	_music_quick_button.pressed.connect(_toggle_bgm)
	add_child(_music_quick_button)
	_settings_quick_button = Button.new()
	_settings_quick_button.name = "SettingsQuickButton"
	_settings_quick_button.text = "设置"
	_settings_quick_button.pressed.connect(_on_action_pressed.bind("菜单"))
	add_child(_settings_quick_button)
	for quick_button in [_music_quick_button, _settings_quick_button]:
		CHROME.skin_button(quick_button)

	_left_card = _create_player_card(true)
	_right_card = _create_player_card(false)
	_match_info_panel = Panel.new()
	_match_info_panel.name = "DuelInformation"
	_match_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_match_info_panel.add_theme_stylebox_override("panel", CHROME.style(Color("#102925e8"), Color("#58684a"), 18))
	add_child(_match_info_panel)
	_role_label = _make_label(_match_info_panel, "我方：连接中", 18, CHROME.MUTED)
	_turn_label = _make_label(_match_info_panel, "当前：等待", 18, CHROME.TEXT)
	_turn_status_label = _make_label(_match_info_panel, "等待双方进入对局", 25, CHROME.GOLD)
	_round_status_label = _make_label(_match_info_panel, "第 1 步", 18, CHROME.MUTED)
	_match_duration_label = _make_label(_match_info_panel, "对局时长 00:00", 20, CHROME.TEXT)

	_board_frame = Panel.new()
	_board_frame.name = "WoodBoardFrame"
	_board_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_frame.add_theme_stylebox_override("panel", CHROME.style(Color("#09171355"), Color("#806b4355"), 18))
	add_child(_board_frame)
	_board_view = TextureRect.new()
	_board_view.name = "InteractiveBoard"
	_board_view.texture = _board_viewport.get_texture()
	_board_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_board_view.stretch_mode = TextureRect.STRETCH_SCALE
	_board_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_board_view.gui_input.connect(_on_board_gui_input)
	_board_frame.add_child(_board_view)

	_action_panel = Panel.new()
	_action_panel.name = "ChessActions"
	_action_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_action_panel.add_theme_stylebox_override("panel", CHROME.style(Color("#0e2422ed"), Color("#71633f"), 18))
	add_child(_action_panel)
	_action_title = _make_label(_action_panel, "对局操作", 26, CHROME.GOLD)
	_action_hint = _make_label(_action_panel, "点击棋子，再选择落点", 17, CHROME.MUTED)
	for item in [
		["菜单", "icon_menu.png"], ["悔棋", "icon_undo.png"], ["提示", "icon_hint.png"],
		["求和", "icon_draw.png"], ["认输", "icon_resign.png"], ["离开", "icon_exit.png"]
	]:
		var button := Button.new()
		button.name = "Action_" + str(item[0])
		button.tooltip_text = str(item[0])
		CHROME.skin_button(button, str(item[0]) == "菜单", str(item[0]) == "认输" or str(item[0]) == "离开")
		var icon := TextureRect.new()
		icon.name = "ActionIcon"
		icon.texture = _load_svg_texture(ACTION_ICON_ROOT + "icon_exit_gold.svg") if str(item[0]) == "离开" else _load_png_texture(ACTION_ICON_ROOT + str(item[1]), GOLD)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)
		var caption := _make_label(button, str(item[0]), 22, Color("#221a0e") if str(item[0]) == "菜单" else CHROME.TEXT)
		caption.name = "ActionCaption"
		button.pressed.connect(_on_action_pressed.bind(str(item[0])))
		_action_panel.add_child(button)
		_action_buttons.append(button)

	_status_panel = Panel.new()
	_status_panel.name = "MoveInformation"
	_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_panel.add_theme_stylebox_override("panel", CHROME.style(Color("#091815"), Color("#394f42"), 12))
	_action_panel.add_child(_status_panel)
	_status_label = _make_label(_status_panel, "正在连接对局，棋盘显示开局预览", 19, CHROME.TEXT)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.clip_text = false
	_footer_label = _make_label(_action_panel, "以棋会友 · 步步从容", 16, CHROME.MUTED)

	_menu_overlay = ColorRect.new()
	_menu_overlay.name = "MenuShade"
	_menu_overlay.color = Color("#030c0bb3")
	_menu_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_overlay.visible = false
	add_child(_menu_overlay)
	_menu_panel = Panel.new()
	_menu_panel.name = "ChessSettings"
	_menu_panel.add_theme_stylebox_override("panel", CHROME.style(Color("#102b27fa"), CHROME.GOLD, 22))
	_menu_panel.visible = false
	add_child(_menu_panel)
	_menu_label = _make_label(_menu_panel, "小板凳象棋", 22, Color("#f3d8ab"))
	_menu_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_menu_label.clip_text = false
	_bgm_toggle_button = Button.new()
	CHROME.skin_button(_bgm_toggle_button)
	_bgm_toggle_button.pressed.connect(_toggle_bgm)
	_menu_panel.add_child(_bgm_toggle_button)

	_sfx_toggle_button = Button.new()
	CHROME.skin_button(_sfx_toggle_button)
	_sfx_toggle_button.pressed.connect(_toggle_sfx)
	_menu_panel.add_child(_sfx_toggle_button)

	_quality_label = _make_label(_menu_panel, "画质", 16, GOLD)
	_quality_option = OptionButton.new()
	_quality_option.name = "RenderQuality"
	_quality_option.add_item("低 · 流畅", 0)
	_quality_option.add_item("中 · 均衡", 1)
	_quality_option.add_item("高 · 精细", 2)
	_quality_option.select(_render_quality)
	_quality_option.add_theme_font_size_override("font_size", 16)
	_quality_option.add_theme_color_override("font_color", GOLD)
	_quality_option.add_theme_stylebox_override("normal", CHROME.style(Color("#152b2a"), Color("#706447"), 12))
	_quality_option.item_selected.connect(_apply_render_quality)
	_menu_panel.add_child(_quality_option)

	_menu_close = Button.new()
	_menu_close.text = "返回棋局"
	CHROME.skin_button(_menu_close, true)
	_menu_close.pressed.connect(func() -> void:
		_menu_panel.visible = false
		_menu_overlay.visible = false
	)
	_menu_panel.add_child(_menu_close)

	_settlement_overlay = ColorRect.new()
	_settlement_overlay.color = Color("#030c0bb3")
	_settlement_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_settlement_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settlement_overlay.visible = false
	add_child(_settlement_overlay)

	_settlement_panel = Panel.new()
	_settlement_panel.name = "ChessSettlement"
	_settlement_panel.add_theme_stylebox_override("panel", CHROME.style(Color("#102b27fa"), CHROME.GOLD, 22))
	_settlement_panel.visible = false
	add_child(_settlement_panel)
	_settlement_title = _make_label(_settlement_panel, "对局结算", 30, Color("#ffe1a5"))
	_settlement_detail = _make_label(_settlement_panel, "", 18, Color("#fff1da"))
	_settlement_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_settlement_detail.clip_text = false
	_settlement_stats = _make_label(_settlement_panel, "", 15, Color("#d9b990"))
	_settlement_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_settlement_stats.clip_text = false

	_settlement_review_button = Button.new()
	_settlement_review_button.text = "查看棋局"
	CHROME.skin_button(_settlement_review_button)
	_settlement_review_button.pressed.connect(_hide_settlement_for_review)
	_settlement_panel.add_child(_settlement_review_button)

	_settlement_lobby_button = Button.new()
	_settlement_lobby_button.text = "返回大厅"
	CHROME.skin_button(_settlement_lobby_button, true)
	_settlement_lobby_button.pressed.connect(_return_to_lobby)
	_settlement_panel.add_child(_settlement_lobby_button)

	_countdown_clock = COUNTDOWN_CLOCK_SCRIPT.new()
	_countdown_clock.size = Vector2(230.0, 230.0)
	add_child(_countdown_clock)

	_warning_audio = AudioStreamPlayer.new()
	_warning_audio.name = "TurnWarningAudio"
	_warning_audio.stream = WARNING_SOUND_SCRIPT.create_warning_stream()
	_warning_audio.volume_db = -4.0
	add_child(_warning_audio)
	_setup_audio()
	_update_player_panels()


func _make_label(parent: Node, value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
	card.name = "OwnPlayer" if left_side else "OpponentPlayer"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", CHROME.style(Color("#101e21ed"), Color("#415852"), 18))
	add_child(card)
	var seat_label := _make_label(card, "我方" if left_side else "对手", 15, CHROME.GOLD)
	seat_label.name = "SeatLabel"
	seat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

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
	portrait.material = CHROME.portrait_material(0 if left_side else 1)
	avatar_frame.add_child(portrait)

	var name_label := _make_label(card, "等待玩家", 23, Color("#fff1d9"))
	var rank_label := _make_label(card, "象棋对弈", 15, Color("#d8b77e"))
	var timer_label := _make_label(card, "--:--", 27, Color("#f2e9d4"))
	var badge := Panel.new()
	badge.name = "SideBadge"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override("panel", _flat_style(Color("#ad2520"), Color("#d9a15f"), 8, 1))
	card.add_child(badge)
	var badge_text := _make_label(badge, "红方" if left_side else "黑方", 13, Color.WHITE)
	badge_text.name = "SideBadgeText"
	var timer_frame := Panel.new()
	timer_frame.name = "TimerFrame"
	timer_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_frame.add_theme_stylebox_override("panel", _flat_style(Color("#0b0c0c"), Color("#9a733e"), 10, 1))
	card.add_child(timer_frame)
	var watch := _make_label(timer_frame, "◷", 23, GOLD)
	watch.name = "TimerIcon"
	timer_label.reparent(timer_frame)
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


func _resolve_layout_mode(w: float, h: float) -> LayoutMode:
	var ratio := w / maxf(h, 1.0)
	if h < 680.0:
		return LayoutMode.PHONE_LANDSCAPE
	if ratio < 1.48:
		return LayoutMode.TABLET_LANDSCAPE
	if ratio >= 2.0:
		return LayoutMode.WIDE_DESKTOP
	return LayoutMode.DESKTOP


func _layout_hud() -> void:
	if _board_frame == null or size.x < 100.0 or size.y < 100.0:
		return
	var w := size.x
	var h := size.y
	var ui_scale := clampf(minf(w / 1440.0, h / 810.0), 0.55, 1.25)
	_layout_mode = _resolve_layout_mode(w, h)
	if _last_reported_layout_mode != int(_layout_mode):
		_last_reported_layout_mode = int(_layout_mode)
		print("CHESS_LAYOUT mode=%s size=%dx%d" % [LayoutMode.keys()[_layout_mode], int(w), int(h)])

	# Header stays clear of the shared title strip; all other content fits actual size.
	var margin := 28.0 * ui_scale
	var gutter := 24.0 * ui_scale
	var content_top := maxf(104.0 * ui_scale, 100.0)
	var content_h := h - content_top - margin
	var aspect := float(BOARD_VIEW_SIZE.x) / float(BOARD_VIEW_SIZE.y)
	var minimum_sidebar := 238.0 * ui_scale
	var board_w := minf(content_h * aspect, w - 2.0 * (margin + gutter + minimum_sidebar))
	var board_h := board_w / aspect
	var board_x := (w - board_w) * 0.5
	var board_y := content_top + (content_h - board_h) * 0.5
	var sidebar_w := minf(340.0 * ui_scale, board_x - margin - gutter)
	var players_x := board_x - gutter - sidebar_w
	var actions_x := board_x + board_w + gutter
	var card_h := minf(210.0 * ui_scale, content_h * 0.30)

	_board_frame.position = Vector2(board_x, board_y)
	_board_frame.size = Vector2(board_w, board_h)
	_board_view.position = Vector2.ZERO
	_board_view.size = _board_frame.size
	_right_card.position = Vector2(players_x, content_top)
	_left_card.position = Vector2(players_x, content_top + content_h - card_h)
	_left_card.size = Vector2(sidebar_w, card_h)
	_right_card.size = _left_card.size
	_layout_player_card(_left_card, _left_avatar, _left_player_label, _left_rank_label, _left_timer_label, 72.0 * ui_scale, ui_scale)
	_layout_player_card(_right_card, _right_avatar, _right_player_label, _right_rank_label, _right_timer_label, 72.0 * ui_scale, ui_scale)

	_match_info_panel.position = Vector2(players_x, content_top + card_h + gutter)
	_match_info_panel.size = Vector2(sidebar_w, content_h - 2.0 * card_h - 2.0 * gutter)
	var info_w := sidebar_w - 32.0 * ui_scale
	_turn_status_label.position = Vector2(16.0, 14.0) * ui_scale
	_turn_status_label.size = Vector2(info_w, 40.0 * ui_scale)
	_turn_label.position = Vector2(16.0, 58.0) * ui_scale
	_turn_label.size = Vector2(info_w, 30.0 * ui_scale)
	_round_status_label.position = Vector2(16.0, 94.0) * ui_scale
	_round_status_label.size = Vector2(info_w, 28.0 * ui_scale)
	_match_duration_label.position = Vector2(16.0, 126.0) * ui_scale
	_match_duration_label.size = Vector2(info_w, 32.0 * ui_scale)
	_role_label.position = Vector2(16.0, 166.0) * ui_scale
	_role_label.size = Vector2(info_w, 30.0 * ui_scale)
	_turn_status_label.add_theme_font_size_override("font_size", roundi(maxf(18.0, minf(25.0 * ui_scale, info_w / 10.0))))
	_turn_label.add_theme_font_size_override("font_size", roundi(maxf(16.0, 18.0 * ui_scale)))
	_round_status_label.add_theme_font_size_override("font_size", roundi(maxf(15.0, 18.0 * ui_scale)))
	_match_duration_label.add_theme_font_size_override("font_size", roundi(maxf(16.0, 20.0 * ui_scale)))
	_role_label.add_theme_font_size_override("font_size", roundi(maxf(14.0, 17.0 * ui_scale)))

	_action_panel.position = Vector2(actions_x, content_top)
	_action_panel.size = Vector2(sidebar_w, content_h)
	_action_title.position = Vector2(18.0, 18.0) * ui_scale
	_action_title.size = Vector2(sidebar_w - 36.0 * ui_scale, 34.0 * ui_scale)
	_action_title.add_theme_font_size_override("font_size", roundi(maxf(19.0, 26.0 * ui_scale)))
	_action_hint.position = Vector2(18.0, 58.0) * ui_scale
	_action_hint.size = Vector2(sidebar_w - 36.0 * ui_scale, 38.0 * ui_scale)
	_action_hint.add_theme_font_size_override("font_size", roundi(maxf(14.0, 17.0 * ui_scale)))
	var action_gap := 12.0 * ui_scale
	var action_w := (sidebar_w - 36.0 * ui_scale - action_gap) * 0.5
	var action_h := 78.0 * ui_scale
	for i in range(_action_buttons.size()):
		var button := _action_buttons[i]
		button.position = Vector2(18.0 * ui_scale + float(i % 2) * (action_w + action_gap), 114.0 * ui_scale + floorf(float(i) / 2.0) * (action_h + action_gap))
		button.size = Vector2(action_w, action_h)
		var icon: TextureRect = button.get_node("ActionIcon")
		icon.position = Vector2(10.0 * ui_scale, (action_h - 28.0 * ui_scale) * 0.5)
		icon.size = Vector2.ONE * 28.0 * ui_scale
		var caption: Label = button.get_node("ActionCaption")
		caption.position = Vector2(44.0 * ui_scale, 0.0)
		caption.size = Vector2(action_w - 50.0 * ui_scale, action_h)
		caption.add_theme_font_size_override("font_size", roundi(maxf(16.0, 22.0 * ui_scale)))

	_status_panel.position = Vector2(18.0, 398.0) * ui_scale
	_status_panel.size = Vector2(sidebar_w - 36.0 * ui_scale, content_h - 468.0 * ui_scale)
	_status_label.position = Vector2.ONE * 16.0 * ui_scale
	_status_label.size = _status_panel.size - Vector2.ONE * 32.0 * ui_scale
	_status_label.add_theme_font_size_override("font_size", roundi(maxf(16.0, 19.0 * ui_scale)))
	_footer_label.position = Vector2(18.0 * ui_scale, content_h - 50.0 * ui_scale)
	_footer_label.size = Vector2(sidebar_w - 36.0 * ui_scale, 30.0 * ui_scale)
	_footer_label.add_theme_font_size_override("font_size", roundi(maxf(13.0, 16.0 * ui_scale)))

	var quick_w := 90.0 * ui_scale
	var quick_h := maxf(44.0, 48.0 * ui_scale)
	_music_quick_button.position = Vector2(w - margin - quick_w * 2.0 - 12.0 * ui_scale, 22.0)
	_settings_quick_button.position = Vector2(w - margin - quick_w, 22.0)
	for quick_button in [_music_quick_button, _settings_quick_button]:
		quick_button.size = Vector2(quick_w, quick_h)
		quick_button.add_theme_font_size_override("font_size", roundi(maxf(16.0, 20.0 * ui_scale)))

	if _countdown_clock != null:
		var clock_scale := minf(ui_scale, board_w * 0.46 / 230.0)
		_countdown_clock.size = Vector2(230.0, 230.0)
		_countdown_clock.scale = Vector2.ONE * clock_scale
		_countdown_clock.position = Vector2(board_x + board_w * 0.5, board_y + board_h * 0.5) - Vector2.ONE * 115.0 * clock_scale
	_layout_modal_panels(w, h)


func _layout_modal_panels(w: float, h: float) -> void:
	var ui_scale := clampf(minf(w / 1440.0, h / 810.0), 0.55, 1.25)
	var pad := 24.0 * ui_scale
	var row_h := maxf(44.0, 52.0 * ui_scale)
	var gap := 12.0 * ui_scale
	_menu_panel.size = Vector2(minf(560.0 * ui_scale, w - pad * 2.0), minf(500.0 * ui_scale, h - pad * 2.0))
	_menu_panel.position = (size - _menu_panel.size) * 0.5
	_menu_label.position = Vector2(20.0, 20.0) * ui_scale
	_menu_label.size = Vector2(_menu_panel.size.x - 40.0 * ui_scale, 108.0 * ui_scale)
	_menu_label.add_theme_font_size_override("font_size", roundi(maxf(18.0, 23.0 * ui_scale)))
	var first_row := 148.0 * ui_scale
	_bgm_toggle_button.position = Vector2(pad, first_row)
	_bgm_toggle_button.size = Vector2(_menu_panel.size.x - pad * 2.0, row_h)
	_sfx_toggle_button.position = Vector2(pad, first_row + row_h + gap)
	_sfx_toggle_button.size = _bgm_toggle_button.size
	_quality_label.position = Vector2(pad, first_row + (row_h + gap) * 2.0)
	_quality_label.size = Vector2(90.0 * ui_scale, row_h)
	_quality_option.position = Vector2(pad + 104.0 * ui_scale, _quality_label.position.y)
	_quality_option.size = Vector2(_menu_panel.size.x - pad * 2.0 - 104.0 * ui_scale, row_h)
	_menu_close.position = Vector2(pad, _menu_panel.size.y - pad - row_h)
	_menu_close.size = _bgm_toggle_button.size
	for button in [_bgm_toggle_button, _sfx_toggle_button, _menu_close, _quality_option]:
		button.add_theme_font_size_override("font_size", roundi(maxf(16.0, 20.0 * ui_scale)))

	if _settlement_panel != null:
		_settlement_panel.size = Vector2(minf(600.0 * ui_scale, w - pad * 2.0), minf(470.0 * ui_scale, h - pad * 2.0))
		_settlement_panel.position = (size - _settlement_panel.size) * 0.5
		var settlement_w := _settlement_panel.size.x
		var settlement_h := _settlement_panel.size.y
		_settlement_title.position = Vector2(24.0, 26.0) * ui_scale
		_settlement_title.size = Vector2(settlement_w - pad * 2.0, 56.0 * ui_scale)
		_settlement_detail.position = Vector2(28.0, 100.0) * ui_scale
		_settlement_detail.size = Vector2(settlement_w - 56.0 * ui_scale, 80.0 * ui_scale)
		_settlement_stats.position = Vector2(28.0, 192.0) * ui_scale
		_settlement_stats.size = Vector2(settlement_w - 56.0 * ui_scale, 118.0 * ui_scale)
		_settlement_title.add_theme_font_size_override("font_size", roundi(maxf(24.0, 32.0 * ui_scale)))
		_settlement_detail.add_theme_font_size_override("font_size", roundi(maxf(16.0, 20.0 * ui_scale)))
		_settlement_stats.add_theme_font_size_override("font_size", roundi(maxf(15.0, 18.0 * ui_scale)))
		var button_w := (settlement_w - pad * 2.0 - gap) * 0.5
		_settlement_review_button.position = Vector2(pad, settlement_h - pad - row_h)
		_settlement_review_button.size = Vector2(button_w, row_h)
		_settlement_lobby_button.position = Vector2(pad + button_w + gap, _settlement_review_button.position.y)
		_settlement_lobby_button.size = _settlement_review_button.size
		for button in [_settlement_review_button, _settlement_lobby_button]:
			button.add_theme_font_size_override("font_size", roundi(maxf(16.0, 20.0 * ui_scale)))


func _layout_player_card(card: Panel, avatar: TextureRect, name_label: Label, rank_label: Label, timer_label: Label, avatar_size: float, scale_factor: float) -> void:
	var pad := 18.0 * scale_factor
	var frame: Panel = card.get_node("AvatarFrame")
	frame.position = Vector2(pad, 40.0 * scale_factor)
	frame.size = Vector2.ONE * avatar_size
	avatar.position = Vector2.ONE * 3.0 * scale_factor
	avatar.size = frame.size - Vector2.ONE * 6.0 * scale_factor
	var text_x := pad + avatar_size + 14.0 * scale_factor
	var text_w := maxf(48.0, card.size.x - text_x - pad)
	name_label.position = Vector2(text_x, 38.0 * scale_factor)
	name_label.size = Vector2(text_w, 34.0 * scale_factor)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rank_label.position = Vector2(text_x, 77.0 * scale_factor)
	rank_label.size = Vector2(text_w, 28.0 * scale_factor)
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var seat_label: Label = card.get_node("SeatLabel")
	seat_label.position = Vector2(pad, 11.0 * scale_factor)
	seat_label.size = Vector2(card.size.x * 0.5, 22.0 * scale_factor)
	seat_label.add_theme_font_size_override("font_size", roundi(maxf(13.0, 15.0 * scale_factor)))
	var badge: Panel = card.get_node("SideBadge")
	badge.position = Vector2(card.size.x - pad - 56.0 * scale_factor, 11.0 * scale_factor)
	badge.size = Vector2(56.0, 24.0) * scale_factor
	var badge_text: Label = badge.get_node("SideBadgeText")
	badge_text.position = Vector2.ZERO
	badge_text.size = badge.size
	badge_text.add_theme_font_size_override("font_size", roundi(maxf(12.0, 14.0 * scale_factor)))
	var timer_frame: Panel = card.get_node("TimerFrame")
	timer_frame.position = Vector2(pad, card.size.y - 62.0 * scale_factor)
	timer_frame.size = Vector2(card.size.x - pad * 2.0, 44.0 * scale_factor)
	var watch: Label = timer_frame.get_node("TimerIcon")
	watch.position = Vector2(10.0 * scale_factor, 0.0)
	watch.size = Vector2(30.0 * scale_factor, timer_frame.size.y)
	timer_label.position = Vector2(42.0 * scale_factor, 0.0)
	timer_label.size = Vector2(timer_frame.size.x - 52.0 * scale_factor, timer_frame.size.y)
	name_label.add_theme_font_size_override("font_size", roundi(maxf(18.0, 24.0 * scale_factor)))
	rank_label.add_theme_font_size_override("font_size", roundi(maxf(13.0, 16.0 * scale_factor)))
	timer_label.add_theme_font_size_override("font_size", roundi(maxf(18.0, 25.0 * scale_factor)))

func _on_action_pressed(action: String) -> void:
	if action == "菜单":
		_menu_label.text = "小板凳象棋\n房间：%s\n规则：标准象棋 · %s" % [_room_id, str(product.get("rule_version", "1.0.0"))]
		_menu_overlay.visible = true
		_menu_overlay.move_to_front()
		_menu_panel.visible = true
		_menu_panel.move_to_front()
		return
	if action == "离开":
		_return_to_lobby()
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
			_joined = true
			_your_color = str(message.get("your_color", ""))
			print("CHESS_JOINED color=%s room=%s" % [_your_color, _room_id])
			_apply_player_view()
			_status_label.text = "状态：%s" % str(message.get("message", "已加入房间"))
			_update_hud()
		"chess_state":
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
	_move_number = maxi(1, int(message.get("move_number", _move_number)))
	_winner = str(message.get("winner", ""))
	_loser = str(message.get("loser", ""))
	_end_reason = str(message.get("end_reason", ""))
	_dissolved = bool(message.get("dissolved", false))
	_room_status = str(message.get("status", "waiting"))
	var previous_turn_started_at_ms := _turn_started_at_ms
	var server_time_ms := int(message.get("server_time_ms", 0))
	if server_time_ms > 0:
		_server_clock_offset_ms = server_time_ms - _local_unix_ms()
	_match_started_at_ms = int(message.get("match_started_at_ms", _match_started_at_ms))
	_turn_started_at_ms = int(message.get("turn_started_at_ms", _turn_started_at_ms))
	_finished_at_ms = int(message.get("finished_at_ms", _finished_at_ms))
	_step_warning_seconds = int(message.get("step_warning_seconds", 60))
	_step_countdown_seconds = int(message.get("step_countdown_seconds", 30))
	if previous_turn_started_at_ms != _turn_started_at_ms:
		_last_countdown_second = -999
		if previous_turn_started_at_ms > 0:
			_play_move_sound()
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

	if "--auto-flow" in OS.get_cmdline_user_args() and not _auto_validation_move_sent and _room_status == "playing" and _your_color == "red" and _turn == "red":
		_auto_validation_move_sent = true
		call_deferred("_send_auto_validation_move")

	if _room_status == "finished" or _winner != "" or _end_reason != "":
		if _end_reason == "timeout":
			_status_label.text = "本局结束：%s思考超时，对局已自动解散。" % _color_name(_loser)
		elif _winner != "":
			_status_label.text = "本局结束：%s获胜。" % _color_name(_winner)
		else:
			_status_label.text = "本局已经结束。"
		_show_settlement()
	elif _room_status == "waiting":
		_status_label.text = "状态：等待第二位玩家进入同一房间。"
	elif _turn == _your_color:
		_status_label.text = "状态：轮到你走棋。"
	else:
		_status_label.text = "状态：等待对方走棋。"


func _send_auto_validation_move() -> void:
	# 自动验收专用：红方标准开局先走 0 路兵一步，正常玩家启动不会触发。
	if _room_status != "playing" or _your_color != "red" or _turn != "red":
		return
	_send_json({
		"type": "chess_move",
		"piece_id": "red_soldier_0",
		"from": {"x": 0, "y": 6},
		"to": {"x": 0, "y": 5}
	})
	print("CHESS_AUTO_MOVE submitted room=%s" % _room_id)


func _apply_player_view() -> void:
	if _stage == null:
		return
	if _your_color == "black":
		_stage.set_orbit_view(180.0, CAMERA_RADIUS, CAMERA_HEIGHT, Vector3(0.0, BOARD_Y, 0.0))
	else:
		_stage.set_orbit_view(0.0, CAMERA_RADIUS, CAMERA_HEIGHT, Vector3(0.0, BOARD_Y, 0.0))

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
	var body_material := PBR_FACTORY.create_material(Color("#d1a564"), 0.36, 0.01)
	body_material.albedo_texture = _golden_nanmu_texture
	body.material_override = body_material
	root.add_child(body)

	var top_disc := MeshInstance3D.new()
	var top_cylinder := CylinderMesh.new()
	top_cylinder.top_radius = PIECE_RADIUS * 0.88
	top_cylinder.bottom_radius = PIECE_RADIUS * 0.88
	top_cylinder.height = 0.026
	top_cylinder.radial_segments = 40
	top_disc.mesh = top_cylinder
	top_disc.position.y = 0.097
	var top_material := PBR_FACTORY.create_material(Color("#e6c27e"), 0.44, 0.0)
	top_material.albedo_texture = _golden_nanmu_texture
	top_disc.material_override = top_material
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

	_round_status_label.text = "第 %d 步" % _move_number
	if training_mode:
		_role_label.text = "训练模式 · 红黑轮流"
		_turn_status_label.text = "训练结束 · %s获胜" % _color_name(_winner) if _winner != "" else "轮到%s走棋" % _color_name(_turn)
		_turn_label.text = "双人同机练习"
		_update_player_panels()
		return
	if _your_color == "":
		_role_label.text = "我方：观战"
	else:
		_role_label.text = "我方：%s · %s" % [_color_name(_your_color), "在线" if _connected else "连接中"]

	if _winner != "":
		_turn_status_label.text = "对局结束 · %s获胜" % _color_name(_winner)
		_turn_status_label.add_theme_color_override("font_color", Color("#f0c978"))
		_turn_label.text = "胜方：%s" % _color_name(_winner)
	elif _end_reason == "timeout":
		_turn_status_label.text = "对局结束 · 超时解散"
		_turn_status_label.add_theme_color_override("font_color", Color("#d7c5ad"))
		_turn_label.text = "结算：超时解散"
	elif _room_status == "waiting" or _turn == "":
		_turn_status_label.text = "等待对手进入对局"
		_turn_status_label.add_theme_color_override("font_color", Color("#b8aea4"))
		_turn_label.text = "当前：等待"
	elif _turn == _your_color:
		_turn_status_label.text = "● 轮到你走棋"
		_turn_status_label.add_theme_color_override("font_color", Color("#f2c978"))
		_turn_label.text = "当前：%s · 我方思考" % _color_name(_turn)
	else:
		_turn_status_label.text = "● 对手思考中"
		_turn_status_label.add_theme_color_override("font_color", Color("#ded7cf"))
		_turn_label.text = "当前：%s · 对手思考" % _color_name(_turn)

	_update_player_panels()


func _update_player_panels() -> void:
	if _left_player_label == null or _right_player_label == null:
		return

	var left_color := "black" if _your_color == "black" else "red"
	var right_color := "red" if left_color == "black" else "black"
	var display_name := str(match_context.get("display_name", "我"))
	if display_name == "":
		display_name = "我"

	_left_player_label.text = display_name
	_right_player_label.text = str(match_context.get("opponent_display_name", "对手"))
	_left_card.get_node("SideBadge/SideBadgeText").text = "红方" if left_color == "red" else "黑方"
	_right_card.get_node("SideBadge/SideBadgeText").text = "红方" if right_color == "red" else "黑方"
	_left_card.get_node("SideBadge").add_theme_stylebox_override("panel", _flat_style(Color("#a51f1d") if left_color == "red" else Color("#45484a"), Color("#d8ae74"), 7, 1))
	_right_card.get_node("SideBadge").add_theme_stylebox_override("panel", _flat_style(Color("#a51f1d") if right_color == "red" else Color("#45484a"), Color("#d8ae74"), 7, 1))

	var left_active := _room_status == "playing" and _turn == left_color
	var right_active := _room_status == "playing" and _turn == right_color
	_left_rank_label.text = "● 执棋中" if left_active else ("● 同机练习" if training_mode else ("● 在线" if _room_status == "playing" else "● 等待"))
	_right_rank_label.text = "● 执棋中" if right_active else ("● 同机练习" if training_mode else ("● 在线" if _room_status == "playing" else "● 等待"))
	_left_rank_label.add_theme_color_override("font_color", Color("#f2c978") if left_active else Color("#7fcf9b"))
	_right_rank_label.add_theme_color_override("font_color", Color("#f2c978") if right_active else Color("#7fcf9b"))
	_update_player_card_visual(_left_card, left_active)
	_update_player_card_visual(_right_card, right_active)

	# 计时由 _update_time_ui() 使用服务端权威时间戳持续刷新。
	_update_time_ui()


func _update_player_card_visual(card: Panel, active: bool) -> void:
	if card == null:
		return
	if active:
		card.add_theme_stylebox_override("panel", CHROME.style(Color("#14352fed"), CHROME.GOLD, 18))
	else:
		card.add_theme_stylebox_override("panel", CHROME.style(Color("#101e21ed"), Color("#415852"), 18))


func _update_time_ui() -> void:
	if _match_duration_label == null or _left_timer_label == null or _right_timer_label == null:
		return

	var now_ms := _authoritative_now_ms()
	if _match_started_at_ms > 0:
		var match_elapsed := maxi(0, int((now_ms - _match_started_at_ms) / 1000))
		_match_duration_label.text = "对局时长 %s" % _format_duration(match_elapsed)
	else:
		_match_duration_label.text = "对局时长 00:00"

	if _room_status != "playing" or _turn_started_at_ms <= 0 or _winner != "" or _end_reason != "":
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
	# The countdown brings itself forward; active dialogs must retain the top layer.
	if _settlement_panel.visible:
		_settlement_overlay.move_to_front()
		_settlement_panel.move_to_front()
	elif _menu_panel.visible:
		_menu_overlay.move_to_front()
		_menu_panel.move_to_front()


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
	if not _sfx_enabled or _warning_audio == null:
		return
	_warning_audio.stop()
	_warning_audio.play()


func _load_audio_stream(path: String) -> AudioStream:
	# 开发态和发布态都优先直接解码源音频字节，避免依赖Godot编辑器导入缓存。
	if FileAccess.file_exists(path):
		var bytes := FileAccess.get_file_as_bytes(path)
		if not bytes.is_empty():
			var extension := path.get_extension().to_lower()
			if extension == "wav":
				var wav_stream := AudioStreamWAV.load_from_buffer(bytes)
				if wav_stream != null:
					return wav_stream
			elif extension == "mp3":
				var mp3_stream := AudioStreamMP3.load_from_buffer(bytes)
				if mp3_stream != null:
					return mp3_stream

	var imported = load(path)
	if imported is AudioStream:
		return imported as AudioStream
	return null


func _setup_audio() -> void:
	_move_audio = AudioStreamPlayer.new()
	_move_audio.name = "MoveWoodAudio"
	_move_audio.volume_db = -5.0
	var move_stream := _load_audio_stream(MOVE_SOUND_PATH)
	var move_source_path := MOVE_SOUND_PATH
	if move_stream is AudioStream:
		_move_audio.stream = move_stream
	else:
		var fallback_move_stream := _load_audio_stream(MOVE_SOUND_FALLBACK_PATH)
		move_source_path = MOVE_SOUND_FALLBACK_PATH
		if fallback_move_stream is AudioStream:
			_move_audio.stream = fallback_move_stream
	add_child(_move_audio)
	print("CHESS_MOVE_SOUND_SOURCE path=%s stream=%s" % [
		move_source_path,
		_move_audio.stream.get_class() if _move_audio.stream != null else "null"
	])

	_bgm_audio = AudioStreamPlayer.new()
	_bgm_audio.name = "GuofengBgmAudio"
	_bgm_audio.volume_db = -17.0
	var bgm_stream := _load_audio_stream(BGM_PATH)
	var bgm_source_path := BGM_PATH
	if bgm_stream is AudioStream:
		_bgm_audio.stream = bgm_stream
	else:
		# 新古筝BGM在目标平台导入失败时自动降级到项目内置国风音乐。
		var fallback_stream := _load_audio_stream(BGM_FALLBACK_PATH)
		bgm_source_path = BGM_FALLBACK_PATH
		if fallback_stream is AudioStream:
			_bgm_audio.stream = fallback_stream
	_bgm_audio.finished.connect(_on_bgm_finished)
	add_child(_bgm_audio)
	var window := get_window()
	_app_has_focus = window == null or window.has_focus()
	_sync_bgm_playback()
	_update_audio_toggle_labels()
	print("CHESS_BGM_SOURCE path=%s stream=%s" % [bgm_source_path, _bgm_audio.stream.get_class() if _bgm_audio.stream != null else "null"])
	print("CHESS_BGM playing=%s enabled=%s focused=%s paused=%s" % [
		str(_bgm_audio.playing),
		str(_bgm_enabled),
		str(_app_has_focus),
		str(_bgm_audio.stream_paused)
	])
	if "--auto-bgm-toggle" in OS.get_cmdline_user_args():
		call_deferred("_run_bgm_toggle_validation")


func _on_bgm_finished() -> void:
	# WAV 未设置导入循环时由这里无缝重启；关闭音乐或失去焦点时绝不自动拉起。
	if _bgm_enabled and _app_has_focus and _bgm_audio != null and _bgm_audio.stream != null:
		_bgm_audio.play()


func _sync_bgm_playback() -> void:
	if _bgm_audio == null or _bgm_audio.stream == null:
		_update_audio_toggle_labels()
		return

	var should_play := _bgm_enabled and _app_has_focus
	if should_play:
		if _bgm_audio.playing:
			_bgm_audio.stream_paused = false
		else:
			_bgm_audio.stream_paused = false
			_bgm_audio.play()
	else:
		# 使用暂停而不是 stop，重新开启时从原位置继续；双客户端调试时后台窗口自动静音。
		if _bgm_audio.playing:
			_bgm_audio.stream_paused = true
	_update_audio_toggle_labels()


func _toggle_bgm() -> void:
	_bgm_enabled = not _bgm_enabled
	_sync_bgm_playback()
	print("CHESS_BGM_TOGGLE enabled=%s playing=%s focused=%s paused=%s" % [
		str(_bgm_enabled),
		str(_bgm_audio != null and _bgm_audio.playing),
		str(_app_has_focus),
		str(_bgm_audio != null and _bgm_audio.stream_paused)
	])


func _run_bgm_toggle_validation() -> void:
	_toggle_bgm()
	print("CHESS_BGM_VALIDATE_OFF enabled=%s paused=%s" % [
		str(_bgm_enabled),
		str(_bgm_audio != null and _bgm_audio.stream_paused)
	])
	await get_tree().create_timer(0.12).timeout
	_toggle_bgm()
	print("CHESS_BGM_VALIDATE_ON enabled=%s paused=%s" % [
		str(_bgm_enabled),
		str(_bgm_audio != null and _bgm_audio.stream_paused)
	])


func _toggle_sfx() -> void:
	_sfx_enabled = not _sfx_enabled
	if not _sfx_enabled and _warning_audio != null:
		_warning_audio.stop()
	_update_audio_toggle_labels()


func _update_audio_toggle_labels() -> void:
	if _music_quick_button != null:
		_music_quick_button.text = "音乐" if _bgm_enabled else "静音"
		_music_quick_button.tooltip_text = "暂停背景音乐" if _bgm_enabled else "开启背景音乐"
	if _bgm_toggle_button != null:
		var bgm_state := "关"
		if _bgm_enabled:
			bgm_state = "开" if _app_has_focus else "开（后台暂停）"
		_bgm_toggle_button.text = "背景音乐：%s" % bgm_state
	if _sfx_toggle_button != null:
		_sfx_toggle_button.text = "走棋音效：%s" % ("开" if _sfx_enabled else "关")


func _play_move_sound() -> void:
	if not _sfx_enabled or _move_audio == null or _move_audio.stream == null:
		return
	_move_audio.stop()
	_move_audio.play()
	print("CHESS_MOVE_SOUND played room=%s" % _room_id)


func _show_settlement() -> void:
	if _settlement_panel == null or _settlement_shown:
		return
	_settlement_shown = true

	var title_text := "对局结算"
	var detail_text := ""
	if _end_reason == "timeout":
		title_text = "对局已解散"
		detail_text = "%s思考超时，本局已由服务端自动解散。" % _color_name(_loser)
	elif _winner != "":
		var result_text := "胜利" if _winner == _your_color else "失利"
		title_text = "本局%s" % result_text
		detail_text = "%s吃将获胜，对局已经完成结算。" % _color_name(_winner)
	else:
		title_text = "对局结束"
		detail_text = "本局已经结束。"

	var duration_seconds := 0
	if _match_started_at_ms > 0:
		var end_ms := _finished_at_ms if _finished_at_ms > 0 else _authoritative_now_ms()
		duration_seconds = maxi(0, int((end_ms - _match_started_at_ms) / 1000))

	var reason_text := "正常结束"
	if _end_reason == "timeout":
		reason_text = "单步超时自动解散"
	elif _end_reason == "general_captured":
		reason_text = "将/帅被吃"

	_settlement_title.text = title_text
	_settlement_detail.text = detail_text
	_settlement_stats.text = "对局时长：%s\n结束原因：%s\n房间：%s" % [
		_format_duration(duration_seconds),
		reason_text,
		_room_id
	]
	_settlement_overlay.visible = true
	_settlement_panel.visible = true
	_settlement_overlay.move_to_front()
	_settlement_panel.move_to_front()
	print("CHESS_SETTLEMENT reason=%s loser=%s winner=%s dissolved=%s" % [_end_reason, _loser, _winner, str(_dissolved)])


func _hide_settlement_for_review() -> void:
	if _settlement_overlay != null:
		_settlement_overlay.visible = false
	if _settlement_panel != null:
		_settlement_panel.visible = false


func _return_to_lobby() -> void:
	if _bgm_audio != null:
		_bgm_audio.stop()
	emit_signal("request_return_to_lobby")


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
	if _winner != "" or _end_reason != "" or _room_status == "finished":
		_status_label.text = "状态：本局已经结束。"
		return
	if not training_mode and _turn != _your_color:
		_status_label.text = "状态：当前不是你的回合。"
		return
	var active_color := _turn if training_mode else _your_color

	var clicked_piece := _piece_at(pos)
	if _selected == INVALID_POS:
		if clicked_piece.is_empty():
			_status_label.text = "请选择自己的三维棋子。"
			return
		if str(clicked_piece.get("color", "")) != active_color:
			_status_label.text = "不能选择对方棋子。"
			return
		_selected = pos
		_status_label.text = "已选择%s，请点击目标格。" % _piece_symbol(active_color, str(clicked_piece.get("type", "")))
		_update_selection()
		return

	if not clicked_piece.is_empty() and str(clicked_piece.get("color", "")) == active_color:
		_selected = pos
		_status_label.text = "已切换选择，请点击目标格。"
		_update_selection()
		return

	var selected_piece := _piece_at(_selected)
	if selected_piece.is_empty():
		_selected = INVALID_POS
		_update_selection()
		return
	if training_mode:
		var reason: String = TRAINING_RULES_SCRIPT.validate(_pieces_by_pos, _selected, pos, _turn)
		if reason != "":
			_status_label.text = reason
			return
		var captured: Dictionary = _piece_at(pos)
		_pieces_by_pos.erase(_selected)
		_pieces_by_pos[pos] = selected_piece
		_selected = INVALID_POS
		_move_number += 1
		if str(captured.get("type", "")) == "general":
			_winner = _turn
			_room_status = "finished"
			_status_label.text = "%s吃将，训练结束" % _color_name(_winner)
		else:
			_turn = "black" if _turn == "red" else "red"
			_status_label.text = "双人同机训练 · 轮到%s" % _color_name(_turn)
		_rebuild_piece_models()
		_update_selection()
		_update_hud()
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
		screen_pos.x * _board_viewport.size.x / _board_view.size.x,
		screen_pos.y * _board_viewport.size.y / _board_view.size.y
	)
	var ray_origin := _camera.project_ray_origin(viewport_pos)
	var ray_direction := _camera.project_ray_normal(viewport_pos)
	if absf(ray_direction.y) < 0.00001:
		return INVALID_POS
	var distance := (BOARD_Y - ray_origin.y) / ray_direction.y
	if distance <= 0.0:
		return INVALID_POS
	var hit := ray_origin + ray_direction * distance
	var x := _nearest_grid_index(hit.x / BLENDER_MODEL_SCALE, _grid_x_m)
	var y := _nearest_grid_index(-hit.z / BLENDER_MODEL_SCALE, _grid_y_m)
	var snapped := _board_to_world(Vector2i(x, y))
	if Vector2(hit.x - snapped.x, hit.z - snapped.z).length() > CELL_SIZE * 0.48:
		return INVALID_POS
	return Vector2i(x, y)


func _board_to_world(pos: Vector2i) -> Vector3:
	return Vector3(
		_grid_x_m[pos.x] * BLENDER_MODEL_SCALE,
		PIECE_CENTER_Y,
		-_grid_y_m[pos.y] * BLENDER_MODEL_SCALE
	)


func _nearest_grid_index(value: float, positions: PackedFloat64Array) -> int:
	var nearest := 0
	for i in range(1, positions.size()):
		if absf(value - positions[i]) < absf(value - positions[nearest]):
			nearest = i
	return nearest


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
