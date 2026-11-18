extends Control
## 贵阳麻将实时桌面：只提交动作意图，暗牌、牌墙、胡牌判定均来自服务端。

signal request_return_to_lobby
signal request_return_to_room
signal entry_cancelled(message: String)
signal request_next_round
signal match_finished(result: Dictionary)
signal wallet_snapshot_received(snapshot: Dictionary)
signal session_expired

const ART := "res://modules/games/mahjong/guiyang/assets/"
const TRANSPORT := preload("res://modules/games/mahjong/guiyang/mahjong_transport.gd")
const STAGE_SCRIPT = preload("res://modules/game_framework/tabletop3d/tabletop_stage.gd")
const NATIVE_VIEW := preload("res://modules/game_framework/tabletop3d/native_3d_view.gd")
const TILE_MODEL := preload("res://modules/games/mahjong/guiyang/real_tile_model.gd")
const MAHJONG_CORE := preload("res://modules/game_framework/tile/mahjong_core.gd")
const TILE_MATERIALS = preload("res://modules/games/mahjong/guiyang/real_tile_materials.gd")
const CLUB_CHROME = preload("res://modules/games/mahjong/guiyang/club_chrome.gd")
const RURAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_theme.gd")
const MODAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_modal.gd")
const SETTLEMENT := preload("res://modules/games/mahjong/guiyang/mahjong_settlement_view.gd")
const SETTINGS := preload("res://modules/games/mahjong/guiyang/mahjong_settings_view.gd")
const WIND_DIAL := preload("res://modules/games/mahjong/guiyang/mahjong_wind_dial.gd")
const PRESENCE_SHADER := preload("res://modules/games/mahjong/guiyang/mahjong_presence.gdshader")
const TABLE_THEME := preload("res://modules/games/mahjong/guiyang/mahjong_table_theme.gd")
const TILE_FOCUS := preload("res://modules/games/mahjong/guiyang/mahjong_tile_focus.gd")
const BATTLE_ART := preload("res://modules/games/mahjong/guiyang/mahjong_battle_art.gd")
const DISPLAY = preload("res://modules/foundation/ui/battle_display.gd")
const CHROME = preload("res://modules/foundation/ui/battle_chrome.gd")
const QUALITY_FILE := "user://mahjong_visuals.cfg"
const AUDIO := preload("res://modules/games/mahjong/guiyang/mahjong_audio.gd")
const ACTION_EFFECT := preload("res://modules/games/mahjong/guiyang/mahjong_action_effect.gd")
const COACH_STATE := preload("res://modules/games/mahjong/guiyang/mahjong_coach_state.gd")
const COACH_OVERLAY := preload("res://modules/games/mahjong/guiyang/mahjong_efficiency_overlay.gd")
const CHAT_IDS := ["hello", "hurry", "well_played", "thanks", "good_game"]
const CHAT_TEXTS := ["大家好，很高兴一起玩！", "快点吧，我等到花儿都谢了！", "这手牌打得漂亮！", "谢谢！", "好牌，好局！"]
const EMOTE_IDS := ["smile", "laugh", "thumbs_up", "cry", "angry"]
const EMOTE_TEXTS := ["微笑", "大笑", "点赞", "流泪", "生气"]
const RESPONSE_KINDS := ["chi", "peng", "gang", "hu", "pass"]
const ACTION_BUTTON_SIZE := Vector2(125.0, 56.0)
const ACTION_BUTTON_GAP := 8.0
const ACTION_HAND_GAP := 8.0
const ACTION_FONT_SIZE := 24
const DINGQUE_SUITS := {"wan":"万", "tong":"筒", "tiao":"条"}
const CAMERA_PITCH_DEGREES := 35.0
const CAMERA_SENSOR_WIDTH_MM := 36.0
const CAMERA_FOCAL_LENGTH_MM := 40.0
const CAMERA_TARGET := Vector3(0.0, 0.0, 0.0144)
const TILE_SIZE := TILE_MODEL.SIZE
const TILE_BODY_BOUNDS := AABB(Vector3(-TILE_SIZE.x * 0.5, 0.0, -TILE_SIZE.z * 0.5), TILE_SIZE)
const HAND_ROW_RADIUS := 0.30 + TILE_SIZE.z
const HAND_STANDING_ANGLE := PI * 0.5
# The flat model pivots on its back. After standing it up, its thickness extends toward its owner.
const HAND_PIVOT_DEPTH := HAND_ROW_RADIUS - TILE_SIZE.y * 0.5
const HAND_PIVOT_HEIGHT := TILE_SIZE.z * 0.5
const DISCARD_COLUMNS := 8
const RIVER_CORNER_GAP := 0.006
const RIVER_SIDE_OFFSET := 0.074
const MELD_ROW_GAP := 0.009
const OPPONENT_MELD_SEPARATION := 0.054
const SEAT_CARD_SIZE := Vector2(178, 76)
const OWN_HAND_LIFT := 0.020
const FULL_HAND_COUNT := 14
const HAND_SIDE_MARGIN_TILES := 1.0
const PLAY_AREA_NEAR_DEPTH := HAND_ROW_RADIUS + TILE_SIZE.z * 0.5

var product: Dictionary = {}
var match_context: Dictionary = {}
var session_token := ""
var training_mode := false
var _training_wall: Array[Dictionary] = []
var _training_other_hands: Array[Array] = []
var _training_restart: Button
var preserve_window_size := false
var _transport: Node
var _joined := false
var _joined_match_id := ""
var _spectator_permission_pending: Variant = null
var _spectator_permission_notice := ""
var _snapshot_ready := false
var _dealt := false
var _exiting := false
var _last_send_error: Error = OK
var _state: Dictionary = {}
var _textures: Dictionary = {}
var _tile_materials := TILE_MATERIALS.new()
var _selected_id := 0
var _auto_played := false
var _status: Label
var _actions_root: Control
var _seat_root: Control
var _action_effects: Control
var _last_action_sequence := 0
var _overlay_root: Control
var _turn_label: Label
var _seat_panels: Array[Panel] = []
var _avatar_portraits: Array[TextureRect] = []
var _play_button: Button
var _settlement_panel: Panel
var _settlement_reopen: Button
var _settlement_dismissed := false
var _settlement_content: Dictionary = {}
var _finished_round_key := ""
var _notice_title := ""
var _notice_message := ""
var _tool_opener: WeakRef
var _tool_surface: PanelContainer
var _tool_title: Label
var _settings_view: Panel
var _board_view: NATIVE_VIEW
var _board_surface: SubViewportContainer
var _board_viewport: SubViewport
var _play_area := Rect2()
var _stage: Node3D
var _camera: Camera3D
var _camera_impact: Tween
var _camera_displacement := Vector2.ZERO
var _camera_world_per_pixel := 0.0
var _pieces_root: Node3D
var _tile_focus: Node3D
var _hand_models: Array[Node3D] = []
var _hand_ids: Array[int] = []
var _face_materials: Dictionary = {}
var _quality := 1
var _quality_option: OptionButton
var preference_file := QUALITY_FILE
var _header: Label
var _remaining_panel: Panel
var _remaining_number: Label
var _round_number: Label
var _wall_number: Label
var _toolbar: Control
var _side_tools: Control
var _response_buttons: Dictionary = {}
var _seat_voice_buttons: Dictionary = {}
var _muted_accounts: Dictionary = {}
const REPORT_REASONS := ["abusive_chat", "spam", "voice_abuse", "other"]
var _moderation_seat := -1
var _moderation_account := ""
var _report_reason := -1
var _report_command := ""
var _report_match := ""
var _report_target := ""
var _report_notice := ""
var _report_timeout: Timer
var _social_root: Control
var _social_events: Dictionary = {}
var _seen_social: Dictionary = {}
var _last_social_send := -1000
var _tool_open := ""
var _own_mic: Button
var _self_voice_layer: Control
var _voice
var _recording := false
var _voice_deadline: Timer
var _bubble_deadline: Timer
var _playing_voice_account := ""
var _music_enabled := false
var _sound_enabled := true
var product_audio: Node
var _owns_audio := false
var _deadline_tick := 0
var _pending_action := false
var _pending_command := ""
var _pending_action_kind := ""
var _pending_epoch := 0
var _pending_accepted := false
var _dingque_buttons: Dictionary[String, Button] = {}
var _command_serial := 0
var _command_prefix := Crypto.new().generate_random_bytes(12).hex_encode()
var _clock_animation: Tween
var _reported_match := ""
var _selected_outline: Control
var _wind_dial: Node3D
var _safe := Vector4i.ZERO
var _coach: Object
var _coach_overlay: Control
var _coach_key: Array = []
var _coach_results: Dictionary = {}
var _coach_enabled := false
var _coach_selection_key: Array = []
var _coach_auto_selected := false
var _coach_manual_selection := false
var _action_snapshot_revision := 0


func _ready() -> void:
	DISPLAY.enter(self, preserve_window_size)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_quality()
	_build_static_ui()
	_build_audio()
	_voice_deadline = Timer.new()
	_voice_deadline.one_shot = true
	_voice_deadline.timeout.connect(_voice_up)
	add_child(_voice_deadline)
	_bubble_deadline = Timer.new()
	_bubble_deadline.one_shot = true
	_bubble_deadline.timeout.connect(_expire_bubbles)
	add_child(_bubble_deadline)
	_report_timeout = Timer.new()
	_report_timeout.one_shot = true
	_report_timeout.timeout.connect(_on_report_timeout)
	add_child(_report_timeout)
	var voice_script = load("res://modules/foundation/network/room_voice.gd")
	if voice_script != null:
		_voice = voice_script.new()
		_voice.configure(self)
	_apply_audio()
	resized.connect(_layout_ui)
	get_window().size_changed.connect(_layout_ui, CONNECT_DEFERRED)
	if training_mode:
		_start_training()
	else:
		_connect_socket()


func _exit_tree() -> void:
	_exiting = true
	_reset_report_request()
	_stop_recording()
	_stop_audio()
	_stop_camera_impact()
	_stop_clock()
	if is_instance_valid(_transport): _transport.stop()
	DISPLAY.leave(self)


func _load_quality() -> void:
	var config := ConfigFile.new()
	if config.load(preference_file) == OK:
		_quality = clampi(int(config.get_value("rendering", "quality", 1)), 0, 2)
		_music_enabled = bool(config.get_value("sound", "music", false))
		_sound_enabled = bool(config.get_value("sound", "effects", true))
		var legacy_labels := bool(config.get_value("assistance", "efficiency", false))
		_coach_enabled = bool(config.get_value("assistance", "efficiency_labels", legacy_labels))


func _save_preferences() -> void:
	var config := ConfigFile.new()
	config.load(preference_file)
	config.set_value("rendering", "quality", _quality)
	config.set_value("assistance", "efficiency_labels", _coach_enabled)
	config.save(preference_file)


func _set_quality(index: int) -> void:
	_quality = clampi(index, 0, 2)
	if is_instance_valid(_quality_option): _quality_option.select(_quality)
	_sync_viewport_size()
	TABLE_THEME.configure_viewport(_board_viewport, _quality)
	TABLE_THEME.configure_stage(_stage, _quality)
	if is_instance_valid(_tile_focus): _tile_focus.set_quality(_quality)
	_layout_hand_controls()
	_save_preferences()
	_sync_settings()


func _start_training() -> void:
	var wall := MAHJONG_CORE.new().build_standard_wall()
	for index in wall.size():
		wall[index]["id"] = index + 1
	wall.shuffle()
	var hand := wall.slice(0, 14)
	var dealt := hand.size()
	var hand_counts := [dealt]
	_training_other_hands.clear()
	for seat in range(1, 4):
		var concealed := wall.slice(dealt, dealt + 13)
		_training_other_hands.append(concealed)
		hand_counts.append(concealed.size())
		dealt += concealed.size()
	_training_wall = wall.slice(dealt)
	_selected_id = 0
	_state = {
		"room_id": "练习", "status": "playing", "phase": "turn", "turn": 0, "your_seat": 0,
		"players": ["我", "练习位一", "练习位二", "练习位三"], "hand": hand,
		"hand_counts": hand_counts, "scores": [0, 0, 0, 0],
		"melds": [[], [], [], []], "discards": [], "remaining": _training_wall.size(),
		"options": [{"type": "play"}], "winners": [], "dealer": 0, "drawn_tile_id": hand.back().id
	}
	_render()


func _texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	if ResourceLoader.exists(path, "Texture2D"):
		var imported := load(path) as Texture2D
		if imported != null:
			_textures[path] = imported
			return imported
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	var texture := ImageTexture.create_from_image(image)
	_textures[path] = texture
	return texture


func _show_recording(recording: bool) -> void:
	if not is_instance_valid(_own_mic): return
	_own_mic.self_modulate = Color("#ffda80") if recording else Color.WHITE


func _layout_compass() -> void:
	if not is_instance_valid(_round_number) or not is_instance_valid(_wind_dial) or not _camera.is_inside_tree(): return
	var well := _projected_dial(0.0709)
	var extent := well.size * Vector2(0.90, 0.80)
	_remaining_panel.size = extent
	_remaining_panel.position = well.get_center() - extent * 0.5
	var line_size := Vector2(extent.x, extent.y * 0.5)
	var font := _round_number.get_theme_font("font")
	var point_size := maxi(1, floori(line_size.y))
	while point_size > 1 and (font.get_height(point_size) > line_size.y or font.get_string_size("余牌 108", HORIZONTAL_ALIGNMENT_CENTER, -1, point_size).x > extent.x):
		point_size -= 1
	for line: Label in [_round_number, _wall_number]:
		line.add_theme_font_size_override("font_size", point_size)
		line.position = Vector2.ZERO if line == _round_number else Vector2(0, line_size.y)
		line.size = line_size


func _projected_dial(radius: float) -> Rect2:
	var center: Vector3 = _wind_dial.get_timer_position()
	var bounds := Rect2(_project_to_board(center), Vector2.ZERO)
	for axis in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		bounds = bounds.expand(_project_to_board(center + _wind_dial.global_basis * (axis * radius)))
	bounds.position += _board_view.position
	return bounds


func _update_compass_winds() -> void:
	var mine := int(_state.get("your_seat", match_context.get("seat_index", 0)))
	_wind_dial.set_winds(mine, int(_state.get("dealer", -1)))


func _style(bg: Color, border: Color, radius: int = 12) -> StyleBoxFlat:
	return CHROME.style(bg, border, radius)


func _label(parent: Node, value: String, x: float, y: float, width: float, height: float, size: int = 19, color: Color = Color("#ffe9bc")) -> Label:
	return CHROME.label(parent, value, Rect2(x, y, width, height), size, color)


func _decoration(parent: Node, texture: Texture2D, node_name: String) -> TextureRect:
	var artwork := TextureRect.new()
	artwork.name = node_name
	artwork.texture = texture
	artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(artwork)
	return artwork


func _button(parent: Node, value: String, x: float, y: float, width: float, height: float, action: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = value
	button.position = Vector2(x, y)
	button.size = Vector2(width, height)
	RURAL.skin_button(button, primary)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _build_static_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = TABLE_THEME.FELT_COLOR
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_build_3d_table()
	_header = _label(self,"正在连接牌桌",8,0,720,40,23,Color("#ffd36a"))
	_header.name = "MahjongRoomHeading"
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_header.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_header.add_theme_font_override("font", RURAL.title_font())
	_header.add_theme_constant_override("outline_size", 2)
	_header.add_theme_color_override("font_outline_color", Color("#231507"))
	_header.autowrap_mode = TextServer.AUTOWRAP_OFF
	_header.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_toolbar = Control.new()
	_toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toolbar)
	for index in range(3):
		var tool: String = ["rules","settings","leave"][index]
		var button := _button(_toolbar,"",0,0,48,48,_open_tool.bind(tool))
		button.name = "MahjongTool_" + tool
		BATTLE_ART.hud_button(button, tool, ["规则", "设置", "离开牌桌"][index])
	_quality_option = OptionButton.new()
	for title in ["低画质","中画质","高画质"]: _quality_option.add_item(title)
	CHROME.skin_button(_quality_option)
	_quality_option.select(_quality)
	_quality_option.item_selected.connect(_set_quality)
	_quality_option.visible = false
	add_child(_quality_option)
	_remaining_panel = Panel.new()
	_remaining_panel.name = "MahjongTurnCompass"
	_remaining_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_remaining_panel.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	add_child(_remaining_panel)
	_round_number = _label(_remaining_panel,"局数 —",0,0,0,0,16,Color("#ffe6a1"))
	_wall_number = _label(_remaining_panel,"余牌 —",0,0,0,0,16,TABLE_THEME.CREAM)
	for line in [_round_number, _wall_number]:
		line.autowrap_mode = TextServer.AUTOWRAP_OFF
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.clip_text = true
		line.add_theme_font_override("font", RURAL.title_font())
	_remaining_number = _label(self,"—",0,0,80,52,18,Color("#ffe6a1"))
	_remaining_number.name = "MahjongAuthoritativeCountdown"
	_remaining_number.hide()
	_remaining_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_remaining_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_remaining_number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var clock_style := RURAL.frame(Color("#233027"), Color("#b69a63"), 8, 1)
	clock_style.set_content_margin_all(0.0)
	clock_style.shadow_size = 0
	_remaining_number.add_theme_stylebox_override("normal", clock_style)
	var dial_font := FontVariation.new()
	dial_font.base_font = RURAL.title_font()
	dial_font.variation_embolden = 0.7
	_remaining_number.add_theme_font_override("font", dial_font)
	_remaining_number.add_theme_color_override("font_outline_color", Color("#663015"))
	_remaining_number.add_theme_constant_override("outline_size", 3)
	_turn_label = _label(self,"正在入座",0,0,270,27,16,Color("#edd59a"))
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_label.add_theme_constant_override("outline_size", 4)
	_turn_label.add_theme_color_override("font_outline_color", Color("#342517"))
	_status = _label(self,"正在连接牌桌……",0,0,600,34,18,TABLE_THEME.CREAM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_status.add_theme_constant_override("outline_size", 2)
	_status.add_theme_color_override("font_outline_color", Color("#231507"))
	_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_seat_root = Control.new()
	_seat_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_seat_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_seat_root)
	move_child(_remaining_number, _seat_root.get_index())
	_self_voice_layer = Control.new()
	_self_voice_layer.name = "MahjongStableSelfVoice"
	_self_voice_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_self_voice_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_self_voice_layer)
	_own_mic = _button(_self_voice_layer,"",0,0,48,48,func():pass)
	_own_mic.name = "MahjongOwnSeatMic"
	BATTLE_ART.hud_button(_own_mic, "mic", "发送语音")
	_own_mic.button_down.connect(_voice_down)
	_own_mic.button_up.connect(_voice_up)
	_own_mic.tooltip_text = "训练无联网语音" if training_mode else "按住录音，松开发送；最长 5 秒"
	_own_mic.visible = not _is_spectating()
	if ClassDB.class_exists("MahjongCoachBridge"):
		_coach = ClassDB.instantiate("MahjongCoachBridge")
	_coach_overlay = COACH_OVERLAY.new()
	_coach_overlay.tile_materials = _tile_materials
	_coach_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_coach_overlay)
	_selected_outline = CLUB_CHROME.new()
	_selected_outline.name = "MahjongSelectedTileOutline"
	_selected_outline.kind = "selection"
	_selected_outline.visible = false
	add_child(_selected_outline)
	_actions_root = Panel.new()
	_actions_root.name = "MahjongActions"
	_actions_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_actions_root.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_actions_root.hide()
	add_child(_actions_root)
	_play_button = _action_button("打出", _on_play, "play")
	_play_button.name = "MahjongPlaySelectedTile"
	if training_mode:
		_training_restart = _action_button("再练一局", _start_training)
		_training_restart.name = "MahjongPracticeRestartButton"
		_training_restart.hide()
	_social_root = Control.new()
	_social_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_social_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_social_root)
	_side_tools = Control.new()
	_side_tools.visible = not _is_spectating()
	_side_tools.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_side_tools)
	var chat := _button(_side_tools,"",0,0,48,48,_open_tool.bind("chat"))
	chat.name = "MahjongChat"
	BATTLE_ART.hud_button(chat, "chat", "快捷语与表情")
	_action_effects = Control.new()
	_action_effects.name = "MahjongConfirmedActionEffects"
	_action_effects.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_action_effects.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_action_effects)
	_overlay_root = Control.new()
	_overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay_root)
	_layout_ui()
	_render_seats()
	_render_actions()


func _layout_ui() -> void:
	if _board_view == null or _exiting: return
	_stop_camera_impact()
	var width := size.x if size.x>0 else 1440.0
	var height := size.y if size.y>0 else 810.0
	var factor := minf(width/1440.0,height/810.0)
	_safe = RURAL.safe_insets(self)
	var icon_extent := MODAL.icon_button_extent(self)
	var usable_width := width - _safe.x - _safe.z
	var horizontal_inset := _horizontal_screen_pixels(10.0)
	var top := float(_safe.y)
	var bottom := height - _safe.w
	# Keep the play and HUD anchors in a landscape area inside the full-screen felt.
	var board_top := top + 60 * factor
	var board_height := minf(bottom - board_top, usable_width / 1.25)
	_play_area = Rect2(_safe.x, (board_top + bottom - board_height) * 0.5, usable_width, board_height)
	var tool_width := icon_extent
	var tool_height := icon_extent
	var tool_gap := maxf(8.0 * factor, icon_extent / 8.0)
	var toolbar_width := tool_width * _toolbar.get_child_count() + tool_gap * (_toolbar.get_child_count() - 1)
	var opposite_seat := _seat_rect(2)
	_header.position = Vector2(_safe.x + horizontal_inset, opposite_seat.position.y)
	var bar_width := maxf(1.0, opposite_seat.position.x - _header.position.x - 12.0 * factor)
	_header.size = Vector2(bar_width, minf(tool_height, maxf(44.0 * factor, icon_extent * 0.67)))
	BATTLE_ART.fit_room_heading(_header, roundi(28*factor), 2)
	_toolbar.position = Vector2(width-_safe.z-toolbar_width-15*factor,top + 12*factor)
	if _toolbar.position.x < opposite_seat.end.x + 8.0 * factor:
		_toolbar.position.y = opposite_seat.end.y + 8.0 * factor
	_toolbar.size = Vector2(toolbar_width,tool_height)
	for index in range(_toolbar.get_child_count()):
		var tool := _toolbar.get_child(index) as Button
		tool.position = Vector2(index*(tool_width+tool_gap),0)
		MODAL.size_icon_button(tool, self)
		tool.size = Vector2(tool_width,tool_height)
	_quality_option.position = Vector2.ZERO
	_quality_option.size = Vector2(180,48)
	_status.size = Vector2(bar_width, 31.0 * factor)
	_status.add_theme_font_size_override("font_size",roundi(14*factor))
	var social_extent := icon_extent
	var social_right := width - _safe.z - horizontal_inset
	var stack_social := _frames_player_hand()
	var tool_step := (Vector2.DOWN if stack_social else Vector2.RIGHT) * (social_extent + tool_gap)
	_side_tools.size = Vector2.ONE * social_extent
	_own_mic.position = Vector2(social_right - social_extent, bottom - social_extent - 11.0 * factor)
	_side_tools.position = _own_mic.position - tool_step
	_sync_viewport_size()
	var own_seat := _seat_rect(0)
	_turn_label.position = Vector2(own_seat.position.x, own_seat.end.y + 4.0 * factor)
	_turn_label.size = Vector2(own_seat.size.x, 26.0 * factor)
	_turn_label.add_theme_font_size_override("font_size", roundi(17.0 * factor))
	_status.position = Vector2(_header.position.x, _turn_label.get_rect().end.y + 2.0 * factor)
	for index in range(_side_tools.get_child_count()):
		var tool := _side_tools.get_child(index) as Button
		tool.position = index * tool_step
		MODAL.size_icon_button(tool, self)
		tool.size = Vector2.ONE * social_extent
	_layout_compass()
	_render_seats()
	_layout_own_mic()
	_layout_hand_controls()
	_render_bubbles()
	_fit_settlement()
	if _settings_open():
		_fit_settings()
	elif is_instance_valid(_tool_surface) and _tool_surface.is_inside_tree():
		_fit_tool_panel()
	elif _tool_open == "leave":
		_fit_leave_panel(_overlay_root.get_node_or_null("MahjongToolPanel_leave") as Control)


func _horizontal_screen_pixels(pixels: float) -> float:
	var canvas := get_viewport_transform() * get_global_transform()
	return pixels / maxf(0.01, canvas.x.length())


func _seat_rect(relative: int) -> Rect2:
	var factor := minf(size.x/1440.0,size.y/810.0)
	var box := SEAT_CARD_SIZE * factor
	var horizontal_inset := _horizontal_screen_pixels(10.0)
	var left := _safe.x + horizontal_inset
	var right := size.x - _safe.z - horizontal_inset - box.x
	var side_y := _safe.y + (size.y - _safe.y - _safe.w - box.y) * 0.5
	match relative:
		0:
			return Rect2(Vector2(left, _header.get_rect().end.y + 4.0 * factor), box)
		1: return Rect2(Vector2(right,side_y),box)
		2:
			var far_y := _safe.y + 12.0 * factor
			return Rect2(Vector2(_play_area.get_center().x - box.x * 0.5, far_y), box)
	return Rect2(Vector2(left,side_y),box)


func _uses_tablet_layout() -> bool:
	var available_height := size.y - _safe.y - _safe.w
	return available_height > 0.0 and (size.x - _safe.x - _safe.z) / available_height <= 1.60


func _frames_player_hand() -> bool:
	return not _is_spectating() and (size.x - _safe.x - _safe.z) >= 1.67 * maxf(1.0, size.y - _safe.y - _safe.w)


func _own_hand_top() -> float:
	if not is_instance_valid(_pieces_root) or not is_instance_valid(_camera) or not _camera.is_inside_tree():
		return _play_area.end.y - 140.0 * minf(size.x / 1440.0, size.y / 810.0)
	return _board_view.position.y + _own_tile_rect(0.0, OWN_HAND_LIFT).position.y


func _own_tile_pose(along: float, lift: float) -> Transform3D:
	# The GLB origin sits on the bottom of its body, in the middle of its footprint.
	var basis := Basis(Vector3.RIGHT, HAND_STANDING_ANGLE)
	return _pieces_root.global_transform * Transform3D(basis, _own_tile_position(along, lift))


func _own_tile_position(along: float, lift: float) -> Vector3:
	return Vector3(along, HAND_PIVOT_HEIGHT + lift, HAND_PIVOT_DEPTH)


func _own_tile_rect(along: float, lift: float) -> Rect2:
	var pose := _own_tile_pose(along, lift)
	var rect := Rect2(_project_to_board(pose * TILE_BODY_BOUNDS.position), Vector2.ZERO)
	for corner in range(1, 8):
		rect = rect.expand(_project_to_board(pose * TILE_BODY_BOUNDS.get_endpoint(corner)))
	return rect


func _layout_hand_controls() -> void:
	if _exiting or not is_instance_valid(_camera) or not _camera.is_inside_tree(): return
	_layout_response_actions()
	_layout_own_mic()
	_layout_compass()
	_layout_coach()
	_layout_selection()


func _layout_selection() -> void:
	# Selection lives on the actual printed face and resin material. No screen
	# rectangle follows the projected tile; recommendation remains independent.
	_selected_outline.visible = false


func _layout_coach() -> void:
	if not is_instance_valid(_coach_overlay): return
	_sync_coach_selection_window()
	if _hand_models.is_empty() or _state.get("status") != "playing" or _state.get("phase") in ["dingque", "finished"]:
		_coach_key.clear()
		_coach_results.clear()
		_coach_overlay.clear()
		return
	# Only confirmed snapshot events change these inputs. Turn ownership and an
	# in-flight command do not erase the last confirmed hand's analysis.
	var key := _coach_analysis_key()
	if _coach_key != key:
		_coach_key = key.duplicate(true)
		_coach_results = COACH_STATE.analyze(_state, _coach)
	_apply_coach_auto_selection(key, _coach_results)
	if not _coach_enabled:
		_coach_overlay.clear()
		return
	var unavailable_hint := "当前牌或规则暂无可用分析；不会显示推测数值。" if is_instance_valid(_coach) else "本机牌效分析组件未加载，暂不能计算向听和进张。"
	var tiles: Array = []
	var board_origin := _board_view.position
	for index in range(_hand_models.size()):
		var model := _hand_models[index]
		var rect := _projected_tile_rect(model)
		var body := _projected_tile_rect(model, &"TileBody")
		var bottom := maxf(rect.end.y, body.end.y)
		rect.position += board_origin
		tiles.append({"id": _hand_ids[index], "rect": rect, "top":board_origin.y + body.position.y, "bottom": board_origin.y + bottom})
	var snapshot_note := ""
	if not _actions_ready(): snapshot_note = "最近一次同步的牌局数据；重连后更新。"
	elif _pending_action: snapshot_note = "当前为服务器已确认的数据；动作确认后更新。"
	_coach_overlay.present(tiles, _coach_results, _selected_id, _usable_modal_area(), unavailable_hint, snapshot_note)


func _coach_analysis_key() -> Array:
	return [_state.get("room_id"), _state.get("match_id"), _state.get("epoch"), _state.get("status"),
		_state.get("phase"), _state.get("turn"), _state.get("your_seat"), _state.get("saving"),
		_state.get("rule_set_id"), _state.get("rule_version"), _state.get("rule"),
		_state.get("hand"), _state.get("discards"), _state.get("melds"), _state.get("options"),
		_state.get("flipped_ji"), _state.get("remaining"), _state.get("missing_suits"), _state.get("reported_ready"),
		_coach.get_instance_id() if is_instance_valid(_coach) else 0]


func _sync_coach_selection_window() -> void:
	var window: Array = []
	if not _legal_options("play").is_empty():
		var identities: Array = []
		for tile in _array("hand"):
			if not tile is Dictionary: return
			identities.append([int(tile.get("id", 0)), tile.get("suit"), tile.get("rank")])
		identities.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var seat := int(_state.get("your_seat", -1))
		var melds := _array("melds")
		window = [_state.get("room_id"), _state.get("match_id"), seat, identities,
			_state.get("drawn_tile_id"), melds[seat] if seat >= 0 and seat < melds.size() else []]
	if window != _coach_selection_key:
		_coach_selection_key = window.duplicate(true)
		_coach_auto_selected = false
		_coach_manual_selection = false


func _apply_coach_auto_selection(source_key: Array, results: Dictionary) -> void:
	_sync_coach_selection_window()
	if _coach_selection_key.is_empty() or _coach_auto_selected or _coach_manual_selection: return
	if not _actions_ready() or _pending_action or not is_instance_valid(_coach): return
	# Source identity must still describe this exact confirmed decision. This
	# also rejects a delayed analysis if the native bridge becomes asynchronous.
	if source_key != _coach_key or source_key != _coach_analysis_key(): return
	var best_id := 0
	var best_rank := 35
	for raw_id in results:
		if not COACH_STATE._whole(raw_id): continue
		var id := int(raw_id)
		var row: Variant = results[raw_id]
		if not _can_play_tile(id) or not COACH_OVERLAY._valid_efficiency(row): continue
		if row.get("analysisMode") != "discard": continue
		var rank: Variant = row.get("rank")
		if not COACH_STATE._whole(rank) or rank < 1 or rank > 34: continue
		if rank < best_rank or (rank == best_rank and id < best_id):
			best_id = id
			best_rank = int(rank)
	if best_id == 0: return
	# Mark before updating the highlight: projection/layout reentry is harmless.
	_coach_auto_selected = true
	_selected_id = best_id
	_render_hand_only()


func _layout_response_actions() -> void:
	var buttons: Array[Button] = []
	for kind in RESPONSE_KINDS:
		var button: Button = _response_buttons.get(kind)
		if is_instance_valid(button) and button.visible:
			buttons.append(button)
	for button in _dingque_buttons.values():
		if button.visible:
			buttons.append(button)
	if _play_button.visible:
		buttons.append(_play_button)
	if is_instance_valid(_training_restart) and _training_restart.visible:
		buttons.append(_training_restart)
	_actions_root.visible = not buttons.is_empty()
	if buttons.is_empty():
		return

	# Build a dock from the projected hand envelope, keeping tile selections
	# from moving it. Reserve the closest clear row when discards reach that edge.
	var step := ACTION_BUTTON_SIZE + Vector2.ONE * ACTION_BUTTON_GAP
	var area := _usable_modal_area().grow(-ACTION_BUTTON_GAP)
	area.position.y = maxf(area.position.y, _header.get_rect().end.y + ACTION_BUTTON_GAP)
	area.end.y = _own_hand_top() - ACTION_HAND_GAP
	if _frames_player_hand() and _coach_enabled:
		area.end.y -= COACH_OVERLAY.LABEL_HEIGHT + COACH_OVERLAY.LABEL_GAP
	if not area.has_area():
		_actions_root.hide()
		return
	var preferred_x := _board_view.get_rect().get_center().x
	if not _hand_models.is_empty():
		var hand_x := (_hand_models[0].position.x + _hand_models[-1].position.x) * 0.5
		var hand_anchor := _pieces_root.to_global(_own_tile_position(hand_x, 0.0))
		preferred_x = _board_view.position.x + _project_to_board(hand_anchor).x
	var obstacles: Array[Rect2] = [_projected_dial(0.147), _side_tools.get_rect(), _own_mic.get_global_rect()]
	for panel in _seat_panels:
		obstacles.append(panel.get_rect())
	for model in _pieces_root.get_children():
		if model.is_queued_for_deletion() or _hand_models.has(model):
			continue
		var tile := _projected_tile_rect(model)
		tile.position += _board_view.position
		if tile.intersects(area):
			obstacles.append(tile.grow(1.0))
	obstacles.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.x < b.position.x)

	var max_columns := clampi(floori((area.size.x + ACTION_BUTTON_GAP) / step.x), 1, buttons.size())
	var lane := Rect2()
	var columns := max_columns
	for count in range(max_columns, 0, -1):
		var rows := ceili(float(buttons.size()) / count)
		var extent := Vector2(count, rows) * step - Vector2.ONE * ACTION_BUTTON_GAP
		var candidate := _find_action_lane(area, extent, preferred_x, obstacles)
		if candidate.has_area() and (not lane.has_area() or candidate.end.y > lane.end.y + 0.1):
			columns = count
			lane = candidate
			if is_equal_approx(lane.end.y, area.end.y):
				break
	if not lane.has_area():
		# Even an unusually constrained window must keep every legal action available.
		var rows := ceili(float(buttons.size()) / columns)
		var extent := Vector2(columns, rows) * step - Vector2.ONE * ACTION_BUTTON_GAP
		var left := clampf(preferred_x - extent.x * 0.5, area.position.x, maxf(area.position.x, area.end.x - extent.x))
		lane = Rect2(Vector2(left, area.end.y - extent.y), extent)

	_actions_root.position = lane.position
	_actions_root.size = lane.size
	for index in buttons.size():
		var row := floori(float(index) / columns)
		var count := mini(columns, buttons.size() - row * columns)
		var width := count * step.x - ACTION_BUTTON_GAP
		buttons[index].position = Vector2((lane.size.x - width) * 0.5 + (index % columns) * step.x, row * step.y)


func _find_action_lane(area: Rect2, extent: Vector2, preferred_x: float, obstacles: Array[Rect2]) -> Rect2:
	if area.size.x < extent.x or area.size.y < extent.y:
		return Rect2()
	var edge_top := area.end.y - extent.y
	var rows: Array[float] = [edge_top]
	for obstacle in obstacles:
		var top := obstacle.position.y - extent.y
		if area.position.y <= top and top < edge_top and not rows.has(top):
			rows.append(top)
	rows.sort()
	rows.reverse()

	var desired_left := preferred_x - extent.x * 0.5
	for top in rows:
		var closest := INF
		var left := area.position.x
		for obstacle in obstacles:
			if obstacle.end.y <= top or obstacle.position.y >= top + extent.y:
				continue
			var right := minf(area.end.x, obstacle.position.x)
			if right - left >= extent.x:
				var position_x := clampf(desired_left, left, right - extent.x)
				if absf(position_x - desired_left) < absf(closest - desired_left):
					closest = position_x
			left = maxf(left, obstacle.end.x)
		if area.end.x - left >= extent.x:
			var position_x := clampf(desired_left, left, area.end.x - extent.x)
			if absf(position_x - desired_left) < absf(closest - desired_left):
				closest = position_x
		if is_finite(closest):
			return Rect2(Vector2(closest, top), extent)
	return Rect2()


func _layout_own_mic() -> void:
	if is_instance_valid(_own_mic):
		var extent := MODAL.icon_button_extent(self)
		MODAL.size_icon_button(_own_mic, self)
		_own_mic.size = Vector2.ONE * extent


func _sync_viewport_size() -> void:
	if _board_viewport == null or _board_view == null or _board_view.size.x <= 0 or _board_view.size.y <= 0: return
	_board_view.sync_native_size()
	_fit_camera()
	if OS.has_feature("android") and ProjectSettings.get_setting("xiaobandeng/testing/log_mahjong_viewport", false):
		var output_transform := _board_surface.get_viewport_transform() * _board_surface.get_global_transform()
		var output_density := Vector2(output_transform.x.length(), output_transform.y.length())
		var output_pixels := Vector2i((_board_surface.size * output_density).round())
		var texture_pixels := Vector2i(_board_viewport.get_texture().get_size())
		var window_pixels := get_window().size
		print("MAHJONG_NATIVE_VIEWPORT " + JSON.stringify({
			"window_px": [window_pixels.x, window_pixels.y],
			"board_output_px": [output_pixels.x, output_pixels.y],
			"board_texture_px": [texture_pixels.x, texture_pixels.y],
			"vertical_fov_deg": _camera.fov,
			"render_scale": _board_viewport.scaling_3d_scale,
			"container_stretch": _board_surface.stretch,
			"max_fps": Engine.max_fps,
			"vsync_mode": DisplayServer.window_get_vsync_mode(),
			"renderer": RenderingServer.get_current_rendering_method(),
			"gpu": RenderingServer.get_video_adapter_name()
		}))


func _fit_camera() -> void:
	if not is_instance_valid(_camera) or not _camera.is_inside_tree() or not _play_area.has_area():
		return
	var aspect := Vector2(_board_viewport.size).aspect()
	var pitch := deg_to_rad(CAMERA_PITCH_DEGREES)
	_camera.position = CAMERA_TARGET + Vector3(0.0, sin(pitch), cos(pitch))
	_camera.look_at(CAMERA_TARGET)
	if _frames_player_hand() and is_instance_valid(_pieces_root) and _pieces_root.is_inside_tree():
		_fit_player_hand_camera(aspect)
		return

	var view := Transform3D(_camera.global_basis, CAMERA_TARGET).affine_inverse()
	# The long edge of the film gate is horizontal in landscape and vertical in portrait.
	var tan_y := CAMERA_SENSOR_WIDTH_MM / (2.0 * CAMERA_FOCAL_LENGTH_MM * maxf(1.0, aspect))
	var tan_x := tan_y * aspect
	var far := view * Vector3(0.0, TILE_SIZE.z, -HAND_ROW_RADIUS)
	var near_depth := HAND_PIVOT_DEPTH + TILE_SIZE.y if _is_spectating() else PLAY_AREA_NEAR_DEPTH
	var near_edge := view * Vector3(0.0, 0.0, near_depth)
	var far_seat := _seat_rect(2)
	var gap := 8.0 * far_seat.size.y / SEAT_CARD_SIZE.y
	var top := 1.0 - 2.0 * (maxf(_play_area.position.y, far_seat.end.y) + gap) / size.y
	var bottom := 1.0 - 2.0 * (minf(_play_area.end.y, _side_tools.position.y) - gap) / size.y
	var usable_width := _play_area.size.x / size.x
	if aspect >= 1.0: usable_width -= 2.0 * far_seat.size.x / size.x
	usable_width = maxf(0.3, usable_width)
	var side_extent := HAND_PIVOT_DEPTH + TILE_SIZE.y
	var distance := maxf(near_edge.z + side_extent / (tan_x * usable_width),
		((far.y - near_edge.y) / tan_y + top * far.z - bottom * near_edge.z) / maxf(0.1, top - bottom))
	if not _is_spectating():
		var outer := (FULL_HAND_COUNT - 1) * TILE_SIZE.x * 0.5
		var end_tile := view * _own_tile_pose(outer, 0.0)
		for index in 8:
			var point := end_tile * TILE_BODY_BOUNDS.get_endpoint(index)
			distance = maxf(distance, point.z + absf(point.x) / (tan_x * _play_area.size.x / size.x * 0.98))
	var top_offset := far.y - top * (distance - far.z) * tan_y
	var bottom_offset := near_edge.y - bottom * (distance - near_edge.z) * tan_y
	_camera.set_perspective(rad_to_deg(2.0 * atan(tan_y)), _camera.near, _camera.far)
	_camera.position = CAMERA_TARGET + _camera.basis.z * distance
	_camera.h_offset = (near_edge.z - distance) * tan_x * (2.0 * _play_area.get_center().x / size.x - 1.0)
	_camera.v_offset = (top_offset + bottom_offset) * 0.5
	if aspect < 1.0:
		# Frame the board above the side portraits and keep the far edge of the felt offscreen.
		var side_end := view * Vector3(0.0, 0.0, HAND_PIVOT_DEPTH)
		var above_portraits := 1.0 - 2.0 * (_seat_rect(1).position.y - gap) / size.y
		var half_felt := TABLE_THEME.FELT_SIZE_METRES.y * 0.4995
		var far_felt := view * Vector3(0.0, 0.0, -half_felt)
		var near_felt := view * Vector3(0.0, 0.0, half_felt)
		var portrait_offset := side_end.y - above_portraits * (distance - side_end.z) * tan_y
		_camera.v_offset = clampf(minf(_camera.v_offset, portrait_offset),
			near_felt.y + (distance - near_felt.z) * tan_y, far_felt.y - (distance - far_felt.z) * tan_y)
	_camera_world_per_pixel = 2.0 * (distance - near_edge.z) * tan_y / size.y


func _fit_player_hand_camera(aspect: float) -> void:
	# Measure the standing tile in camera axes. The 14-tile reference stays fixed as tiles are played.
	var view := Transform3D(_camera.global_basis, CAMERA_TARGET).affine_inverse()
	var row := view * _own_tile_pose(0.0, 0.0)
	var corners := PackedVector3Array()
	var nearest_z := -INF
	for i in 8:
		var point := row * TILE_BODY_BOUNDS.get_endpoint(i)
		corners.append(point)
		nearest_z = maxf(nearest_z, point.z)

	var board_height := _board_view.size.y
	# Keep a full badge row below the resting hand, including at fractional native pixel scales.
	var pixel_scale := maxf((get_viewport_transform() * get_global_transform()).y.length(), 0.01)
	var bottom := floorf((size.y - _safe.w - COACH_OVERLAY.LABEL_HEIGHT - COACH_OVERLAY.LABEL_GAP) * pixel_scale - 1.0) / pixel_scale
	var bottom_ndc := 1.0 - 2.0 * bottom / board_height

	var tangent := CAMERA_SENSOR_WIDTH_MM / (2.0 * CAMERA_FOCAL_LENGTH_MM * aspect)
	# Use the existing row spacing to frame a reference hand, independent of melds and the live tile count.
	var half_span := _concealed_row_start(0, 1) - _concealed_row_start(0, FULL_HAND_COUNT)
	var hand_width := 2.0 * half_span + TILE_SIZE.x
	var safe_fraction := 1.0 - 2.0 * maxf(_safe.x, _safe.z) / _board_view.size.x
	var frame_width := maxf(hand_width + 2.0 * HAND_SIDE_MARGIN_TILES * TILE_SIZE.x, hand_width / maxf(0.01, safe_fraction))
	var distance := nearest_z + frame_width / (2.0 * aspect * tangent)
	var vertical_offset := INF
	for point in corners:
		vertical_offset = minf(vertical_offset, point.y - bottom_ndc * (distance - point.z) * tangent)
	# Translate the camera to frame the hand while its centre ray retains the specified pitch.
	_camera.set_perspective(rad_to_deg(2.0 * atan(tangent)), _camera.near, _camera.far)
	_camera.position = CAMERA_TARGET + _camera.basis.z * distance
	_camera.h_offset = row.origin.x
	_camera.v_offset = vertical_offset
	_camera_world_per_pixel = 2.0 * (distance - row.origin.z) * tangent / board_height


func _on_native_projection_resized() -> void:
	if not is_instance_valid(_camera) or _exiting: return
	_stop_camera_impact()
	_fit_camera()
	_layout_compass()
	_layout_hand_controls()


func _build_3d_table() -> void:
	_board_view = NATIVE_VIEW.new()
	_board_view.name = "Mahjong3DTableView"
	_board_view.clip_contents = true
	_board_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_board_view.gui_input.connect(_on_board_input)
	add_child(_board_view)
	_board_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board_surface = _board_view.surface
	_board_surface.name = "MahjongNativeRenderSurface"
	_board_viewport = _board_view.viewport
	_board_viewport.name = "Mahjong3DViewport"
	TABLE_THEME.configure_viewport(_board_viewport, _quality)
	_board_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var world := Node3D.new()
	world.name = "MahjongWorld"
	_board_viewport.add_child(world)
	_stage = STAGE_SCRIPT.new()
	world.add_child(_stage)
	var pitch := deg_to_rad(CAMERA_PITCH_DEGREES)
	_camera = _stage.configure(2.0, CAMERA_TARGET + Vector3(0, sin(pitch), cos(pitch)), CAMERA_TARGET, true, 30.0)
	TABLE_THEME.configure_stage(_stage, _quality)
	world.add_child(TABLE_THEME.create_felt_surface())
	_wind_dial = WIND_DIAL.new()
	world.add_child(_wind_dial)
	_pieces_root = Node3D.new()
	_pieces_root.name = "ThreeDimensionalTiles"
	world.add_child(_pieces_root)
	_tile_focus = TILE_FOCUS.new()
	world.add_child(_tile_focus)
	_tile_focus.set_quality(_quality)
	_board_view.projection_resized.connect(_on_native_projection_resized)
func _on_board_input(event: InputEvent) -> void:
	if _state.get("phase") == "dingque": return
	var touch_position := Vector2.ZERO
	if event is InputEventMouseButton:
		# ScreenTouch 已处理选牌；触屏产生的模拟鼠标不能再次选择抬起后的手牌。
		if event.device == -1:
			return
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
	var nearest_distance := INF
	for index in range(_hand_models.size()):
		var bounds := _projected_tile_rect(_hand_models[index])
		if not bounds.grow(10.0).has_point(touch_position):
			continue
		var distance := touch_position.distance_to(bounds.get_center())
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_id = _hand_ids[index]
	if nearest_id > 0:
		# First click selects; a second click on that physical tile confirms a
		# discard through the same legality/pending guard as the play button.
		if nearest_id == _selected_id:
			_on_play()
		else:
			_select_tile(nearest_id)


func _project_to_board(world_position: Vector3) -> Vector2:
	return _camera.unproject_position(world_position) * _board_surface.scale


func _projected_tile_rect(model: Node3D, mesh_name: StringName = &"TileFace") -> Rect2:
	if not is_instance_valid(model) or not model.is_inside_tree() or not is_instance_valid(_camera) or not _camera.is_inside_tree():
		return Rect2(Vector2(-10000,-10000),Vector2.ZERO)
	var mesh := model.find_child(mesh_name, true, false) as MeshInstance3D
	if mesh == null:
		return Rect2(Vector2(-10000, -10000), Vector2.ZERO)
	var bounds := mesh.get_aabb()
	var projected := _project_to_board(mesh.global_transform * bounds.get_endpoint(0))
	var rect := Rect2(projected, Vector2.ZERO)
	for index in range(1, 8):
		projected = _project_to_board(mesh.global_transform * bounds.get_endpoint(index))
		rect = rect.expand(projected)
	return rect


func _connect_socket() -> void:
	if _exiting: return
	if not is_instance_valid(_transport):
		_transport = TRANSPORT.new()
		add_child(_transport)
		_transport.opened.connect(_join_board)
		_transport.connection_lost.connect(_board_lost)
		_transport.session_expired.connect(_session_expired)
		_transport.seat_replaced.connect(_abort_entry.bind("本座位已在另一客户端打开"))
		_transport.packet_received.connect(_handle_packet)
	_board_lost("正在连接牌桌")
	_transport.start(str(match_context.get("websocket_url","")), session_token)


func _session_expired() -> void:
	if _exiting: return
	session_token = ""
	_board_lost("游客会话已失效")
	session_expired.emit()


func _join_board() -> void:
	if _exiting: return
	var request := {"type":"mahjong_join", "room_id":str(match_context.get("room_id","")), "client_id":str(match_context.get("account_id",""))}
	if _is_spectating():
		request["type"] = "mahjong_watch_join"
		request["watch_seat"] = int(match_context.get("watch_seat", -1))
		if match_context.has("password"): request["password"] = match_context.password
		_send(request)
		return
	if not _joined_match_id.is_empty(): request["match_id"] = _joined_match_id
	_send(request)


func _board_lost(reason: String) -> void:
	if _exiting: return
	_joined = false
	_snapshot_ready = false
	_spectator_permission_pending = null
	_clear_pending_command()
	if not _report_command.is_empty():
		_reset_report_request()
		_report_notice = "连接已断开，未收到举报结果"
	_refresh_moderation_tool()
	_deadline_tick = 0
	_update_clock()
	_refresh_connection_actions()
	if is_instance_valid(_action_effects): _clear(_action_effects)
	_stop_camera_impact()
	if is_instance_valid(product_audio):
		product_audio.stop_callout()
		product_audio.stop_action_impact()
	_status.text = reason + (" · 正在恢复观战" if _is_spectating() else " · 等待原座位状态")


func _send(payload: Dictionary) -> void:
	_last_send_error = _wire_send(payload) if _transport_open() and not _exiting else ERR_CONNECTION_ERROR
	if _last_send_error != OK:
		_status.text = "发送失败（%d）· 已保留当前选择，请重试" % int(_last_send_error)
		_refresh_connection_actions()


func _transport_open() -> bool:
	return is_instance_valid(_transport) and _transport.is_open()


func _wire_send(payload: Dictionary) -> Error:
	return _transport.send(payload)


func _actions_ready() -> bool:
	return not _is_spectating() and not _exiting and (training_mode or (_transport_open() and _joined and _snapshot_ready and not _state.get("saving", false)))


func _is_spectating() -> bool:
	return bool(match_context.get("spectating", false))


func _require_actions_ready() -> bool:
	if _actions_ready(): return true
	_status.text = "正在保存牌局" if _state.get("saving", false) else "连接恢复中 · 入座确认和新状态到达后可操作"
	_refresh_connection_actions()
	return false


func _refresh_connection_actions(refresh_tool: bool = true) -> void:
	_refresh_avatar_presence()
	if not is_instance_valid(_actions_root): return
	var connected := _actions_ready()
	for kind in _response_buttons:
		var button: Button = _response_buttons[kind]
		var allowed: bool = kind != "chi" or bool(_table_rule().get("allow_chi", false))
		button.visible = connected and allowed and not _legal_options(str(kind)).is_empty()
		button.disabled = not button.visible or _pending_action
		button.set_meta("legal_emphasis", kind == "hu" and not button.disabled)
	var choices := _legal_options("dingque")
	for suit in _dingque_buttons:
		var button := _dingque_buttons[suit]
		button.visible = connected and choices.any(func(choice: Dictionary) -> bool: return choice.suit == suit)
		button.disabled = not button.visible or _pending_action
	_update_selection()
	if is_instance_valid(_own_mic):
		_own_mic.disabled = (not _actions_ready() or _is_practice_table() or str(_state.get("status", "waiting")) == "waiting") and not _recording
	if not _actions_ready(): _stop_recording()
	if refresh_tool and _tool_open == "chat" and is_instance_valid(_tool_surface):
		_refresh_social_choices()
	elif refresh_tool and _tool_open == "gang" and is_instance_valid(_overlay_root):
		_clear(_overlay_root)
		_render_tool()


func _handle_packet(raw: String) -> void:
	if _exiting: return
	var decoded := JSON.new()
	if decoded.parse(raw)!=OK or not decoded.data is Dictionary: return
	var parsed: Dictionary = decoded.data
	if _is_spectating():
		_handle_watch_packet(parsed)
		return
	match str(parsed.get("type", "")):
		"mahjong_match_cancelled":
			apply_match_cancellation(parsed)
		"mahjong_joined":
			if str(parsed.get("room_id", match_context.get("room_id", ""))) != str(match_context.get("room_id", "")): return
			var match_id := str(parsed.get("match_id", ""))
			if not _joined_match_id.is_empty() and not match_id.is_empty() and _joined_match_id != match_id: return
			if not match_id.is_empty(): _joined_match_id = match_id
			_joined = true
			_snapshot_ready = false
			_clear_pending_command()
			_refresh_connection_actions()
			_status.text = "已入座 %d 号位，正在同步牌桌。" % (int(parsed.get("your_seat", 0)) + 1)
		"mahjong_state":
			if not training_mode and not _joined: return
			if str(parsed.get("room_id", "")) != str(match_context.get("room_id", "")): return
			var match_id := str(parsed.get("match_id", ""))
			if not _joined_match_id.is_empty() and not match_id.is_empty() and _joined_match_id != match_id: return
			# An earlier snapshot from this match cannot replace a newer decision.
			if _snapshot_ready and match_id == str(_state.get("match_id", "")) and parsed.has("epoch") and _state.has("epoch"):
				if int(parsed.epoch) < int(_state.epoch): return
			var expected := str(match_context.get("rule_set_id",""))
			if not expected.is_empty() and (str(parsed.get("rule_set_id",""))!=expected or str(parsed.get("rule_version",""))!=str(match_context.get("rule_version",""))):
				_snapshot_ready = false
				_clear_pending_command()
				_refresh_connection_actions()
				if _status.text != "牌桌规则与房间不一致，请退出后重新入座":
					_status.text = "牌桌规则与房间不一致，请退出后重新入座"
					_show_table_notice("牌桌规则已变更", _status.text)
				return
			var committed := _collect_action_events(parsed)
			var cue := _snapshot_audio_cue(parsed)
			var discard := _snapshot_discard(parsed)
			_snapshot_ready = true
			_dealt = _dealt or str(parsed.get("status", "")) in ["playing", "finished"]
			if not match_id.is_empty(): _joined_match_id = match_id
			_action_snapshot_revision += 1
			_state = parsed
			if _spectator_permission_pending != null and parsed.get("spectator_allowed", false) == _spectator_permission_pending:
				_spectator_permission_pending = null
				_spectator_permission_notice = ""
			_debug_rejected_action_options()
			# Only an accepted private server snapshot may update the session wallet.
			# Refresh the reconnect fallback before the seat labels are rendered.
			var eggs: Variant = parsed.get("egg_counts")
			var players: Variant = parsed.get("players")
			var own_seat := int(parsed.get("your_seat", -1))
			var account := str(match_context.get("account_id", ""))
			if not training_mode and not account.is_empty() and eggs is Array and players is Array \
					and own_seat >= 0 and own_seat < eggs.size() and own_seat < players.size() and players[own_seat] == account:
				var amount: Variant = eggs[own_seat]
				if amount == null or ((amount is int or amount is float) and is_finite(float(amount)) and float(amount) >= 0 and float(amount) == floorf(float(amount))):
					if amount == null: match_context.erase("own_egg_balance")
					else: match_context["own_egg_balance"] = int(amount)
					wallet_snapshot_received.emit({"account_id":account, "amount":amount})
			if _pending_command.is_empty(): _pending_action = false
			_maybe_complete_command()
			var deadline := int(parsed.get("action_deadline_ms", 0))
			_deadline_tick = Time.get_ticks_msec() + maxi(0, deadline - int(parsed.get("server_now_ms", 0))) if deadline > 0 else 0
			_render()
			if not discard.is_empty():
				_play_sound("discard")
				_play_callout("discard", discard)
			if not committed.is_empty():
				_show_action_effects(committed)
			elif not cue.is_empty() and (cue != "discard" or discard.is_empty()):
				_play_sound(cue)
			_report_settlement()
		"mahjong_action_result":
			if _pending_command.is_empty() or str(parsed.get("command_id","")) != _pending_command: return
			if bool(parsed.get("ok",false)):
				_pending_accepted = true
				if _maybe_complete_command(): _refresh_connection_actions()
			else:
				_clear_pending_command()
				_refresh_connection_actions()
				_show_table_notice("操作未生效", str(parsed.get("message", "牌桌未接受这次操作，请按当前牌局继续。")))
		"mahjong_social":
			_receive_social(parsed)
		"mahjong_report_result":
			_accept_report_result(parsed)
		"mahjong_entry_cancelled":
			if str(parsed.get("room_id", "")) != str(match_context.get("room_id", "")) or str(parsed.get("match_id", "")) != _joined_match_id: return
			_abort_entry(str(parsed.get("message", "入桌已取消，请重新准备或匹配")))
		"mahjong_error":
			if parsed.get("operation") == "spectator_permission":
				_spectator_permission_pending = null
				_spectator_permission_notice = str(parsed.get("message", "未能更新观战权限"))
				_sync_settings()
				return
			if parsed.get("operation", "") == "join":
				if parsed.get("code") == "match_unavailable":
					if not _joined: _end_confirmed_match(parsed, "原对局已结束，请返回大厅重新开局。")
					return
				if parsed.has("room_id") and parsed.room_id != match_context.get("room_id"): return
				if parsed.has("match_id") and parsed.match_id != _joined_match_id: return
				if _joined: return
				if _dealt:
					if is_instance_valid(_transport) and _transport.is_open():
						_transport._lose("入座尚未恢复")
					return
				_abort_entry(str(parsed.get("message", "未能入桌，请返回大厅")))
				return
			if _pending_command.is_empty(): _pending_action = false
			_refresh_connection_actions()
			_show_table_notice("操作未生效", str(parsed.get("message", "请按当前牌局继续。")))


func _handle_watch_packet(packet: Dictionary) -> void:
	if packet.get("type") == "mahjong_error" and packet.get("operation") == "watch":
		_abort_entry(str(packet.get("message", "未能进入观战")))
		return
	if str(packet.get("room_id", "")) != str(match_context.get("room_id", "")): return
	match str(packet.get("type", "")):
		"mahjong_watch_joined":
			_joined = true
			_snapshot_ready = false
			_refresh_avatar_presence()
			_status.text = "正在同步观战牌桌"
		"mahjong_watch_state":
			var seat := _option_integer(packet.get("watch_seat", -1))
			if not _joined or seat < 0 or seat >= 4: return
			var match_id := str(packet.get("match_id", ""))
			if _snapshot_ready and match_id == str(_state.get("match_id", "")) and int(packet.get("epoch", 0)) < int(_state.get("epoch", 0)): return
			# The viewed seat only defines camera orientation. It never owns a hand.
			_state = packet.duplicate()
			for private_key in ["players", "egg_counts", "egg_deltas", "drawn_tile_id"]:
				_state.erase(private_key)
			_state["hand"] = []
			_state["options"] = []
			_state["your_seat"] = seat
			match_context["watch_seat"] = seat
			_snapshot_ready = true
			var deadline := int(packet.get("action_deadline_ms", 0))
			_deadline_tick = Time.get_ticks_msec() + maxi(0, deadline - int(packet.get("server_now_ms", 0))) if deadline > 0 else 0
			_render()
		"mahjong_watch_ended":
			_abort_entry(str(packet.get("message", "观战已结束")))


var released_match_id := ""


func apply_match_cancellation(packet: Dictionary) -> void:
	if packet.get("reason") == "disconnect_timeout":
		_end_confirmed_match(packet, "有玩家断线超过5分钟，本局已解散")


func _end_confirmed_match(packet: Dictionary, message: String) -> void:
	if _exiting or training_mode or _is_spectating() or not released_match_id.is_empty(): return
	if _joined_match_id.is_empty() or packet.get("match_id") != _joined_match_id: return
	var room := str(match_context.get("room_id", ""))
	if room.is_empty() or packet.get("room_id") != room or _state.get("phase") == "finished": return
	released_match_id = _joined_match_id
	_abort_entry(message)


func _abort_entry(message: String) -> void:
	if _exiting: return
	_clear_pending_command()
	_spectator_permission_pending = null
	_deadline_tick = 0
	if is_instance_valid(_bubble_deadline): _bubble_deadline.stop()
	_social_events.clear()
	_stop_camera_impact()
	entry_cancelled.emit(message)
	_return_now()


func reconcile_lobby_assignment(assignment: Dictionary) -> void:
	if _dealt or _exiting or training_mode or _is_spectating(): return
	var same_room := str(assignment.get("room_id", "")) == str(match_context.get("room_id", ""))
	if not same_room or not bool(assignment.get("start", false)):
		_abort_entry("本次入桌已结束，请重新准备或匹配")


func _clear_pending_command() -> void:
	_pending_action = false
	_pending_command = ""
	_pending_action_kind = ""
	_pending_accepted = false
	_pending_epoch = 0


func _maybe_complete_command() -> bool:
	if not _pending_accepted: return false
	var advanced := int(_state.get("epoch", 0)) > _pending_epoch
	# A single private selection can be confirmed while the other seats still
	# share the same game epoch. The accepted receipt and fresh options agree.
	var options: Variant = _state.get("options")
	var dingque_locked: bool = _pending_action_kind == "dingque" and _state.get("phase") == "dingque" \
		and not _state.get("saving", false) and options is Array and options.is_empty()
	if not advanced and not dingque_locked: return false
	_clear_pending_command()
	return true


func _report_settlement() -> void:
	var id := str(_state.get("match_id",""))
	if str(_state.get("phase",""))!="finished" or _state.get("saving", false) or id.is_empty() or id==_reported_match: return
	var seat := int(_state.get("your_seat",-1))
	var scores := _array("scores")
	if seat<0 or seat>=scores.size(): return
	_reported_match = id
	var winners := _array("winners").map(func(value): return int(value))
	var result := "流局" if winners.is_empty() else ("胡牌" if winners.has(seat) else "已结算")
	var record := {"match_id":id,"name":_rule_name(),"kind":_room_kind(),"score":int(scores[seat]),"result":result}
	var eggs := _array("egg_deltas")
	if seat < eggs.size() and (eggs[seat] is int or eggs[seat] is float) and is_finite(float(eggs[seat])) and float(eggs[seat]) == floorf(float(eggs[seat])):
		record["egg_delta"] = int(eggs[seat])
	match_finished.emit(record)


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _array(key: String) -> Array:
	var value = _state.get(key, [])
	return value if typeof(value) == TYPE_ARRAY else []


func _render() -> void:
	_clear(_pieces_root)
	_hand_models.clear()
	_hand_ids.clear()
	var phase := str(_state.get("phase", ""))
	var status := str(_state.get("status", "waiting"))
	var finished := phase == "finished" and not bool(_state.get("saving", false))
	var finished_key := "%s/%s/%d" % [_state.get("room_id", ""), _state.get("match_id", ""), int(_state.get("completed_rounds", 0))] if finished else ""
	var first_finish := not finished_key.is_empty() and finished_key != _finished_round_key
	_finished_round_key = finished_key
	if first_finish:
		_coach_overlay.close_detail()
		_tool_open = ""
		_tool_opener = null
		_settings_view = null
		_settlement_dismissed = false
	var stable_tool := _settings_open() or (_tool_open in ["chat", "notice"] and is_instance_valid(_tool_surface) and _tool_surface.is_inside_tree())
	var keep_settlement := false
	var previous_view := {}
	if finished and not training_mode and not _is_spectating():
		var content := {}
		for field in ["room_id", "match_id", "kind", "rule", "rule_set_id", "rule_version", "round_limit", "completed_rounds", "can_rematch", "your_seat", "winners", "win_kind", "win_from", "hu_details", "fan_breakdown", "settlement_hands", "hand", "melds", "robbed_tile", "ready_seats", "scores", "player_names", "players", "ji_counts", "egg_counts", "egg_deltas", "flipped_ji", "score_breakdown", "series_rounds", "series_total_rounds", "series_scores", "series_ranks"]:
			if _state.has(field): content[field] = _state[field]
		keep_settlement = not first_finish and _tool_open.is_empty() and ((is_instance_valid(_settlement_panel) and _settlement_panel.is_inside_tree() and content == _settlement_content) or (is_instance_valid(_settlement_reopen) and _settlement_reopen.is_inside_tree() and _settlement_dismissed))
		_settlement_content = content
		if not first_finish and not keep_settlement and _tool_open.is_empty() and is_instance_valid(_settlement_panel) and _settlement_panel.is_inside_tree():
			previous_view = _settlement_panel.navigation_snapshot()
	if not stable_tool and not keep_settlement:
		_clear(_overlay_root)
		_settlement_panel = null
	if _tool_open.is_empty() and (_state.get("phase") != "finished" or training_mode or _is_spectating()):
		_block_board_focus(false)
	_selected_id = _selected_id if _state.get("phase") != "dingque" and _hand_contains(_selected_id) else 0
	_render_seats()
	_render_opponent_hands()
	_render_discards()
	_render_melds()
	_render_hand()
	_update_context_labels()
	_refresh_connection_actions(false)
	_render_bubbles()
	if _settings_open():
		_sync_settings()
	elif stable_tool and _tool_open == "chat":
		_refresh_social_choices()
	elif not stable_tool and not _tool_open.is_empty():
		_render_tool()
	if phase != "finished": _settlement_dismissed = false
	if finished:
		_status.text = ""
		if training_mode or _is_spectating():
			if first_finish:
				_show_table_notice("本局结束", "牌墙已摸完，本次练习结束。" if training_mode else "你观战的这一局已结束。")
		elif _tool_open.is_empty() and not keep_settlement:
			_render_settlement_overlay()
			if not previous_view.is_empty() and is_instance_valid(_settlement_panel):
				_settlement_panel.restore_navigation(previous_view)
	elif _is_spectating():
		_status.text = "观战 · %d 号位 · %s" % [int(_state.get("your_seat", match_context.get("watch_seat", 0))) + 1,
			"等待牌局开始" if status == "waiting" else "只查看公开牌局"]
	elif _state.get("saving", false):
		_status.text = "正在保存牌局"
	elif status == "waiting":
		_status.text = "正在连接训练桌" if _room_kind()=="training" else "等待四位牌友连接 · %d / 4" % int(_state.get("connected_players", 0))
	elif not _actions_ready():
		_status.text = "连接恢复中 · 等待入座确认和新状态"
	elif phase == "dingque":
		_status.text = "已提交定缺 · 等待牌友" if _legal_options("dingque").is_empty() else "请选择一门定缺"
	elif phase == "reaction":
		_status.text = "等待牌友响应" if _options().is_empty() else "请选择响应动作"
	elif int(_state.get("turn", -1)) == int(_state.get("your_seat", -2)):
		_status.text = _discard_prompt()
	else:
		_status.text = "等待牌友出牌"
	print("MAHJONG_STATE room=%s phase=%s turn=%s seat=%s remaining=%s" % [str(_state.get("room_id", "")), phase, str(_state.get("turn", "")), str(_state.get("your_seat", "")), str(_state.get("remaining", ""))])
	if "--auto-flow" in OS.get_cmdline_user_args() and not _auto_played and _actions_ready() and status == "playing" and phase == "turn" and int(_state.get("turn", -1)) == int(_state.get("your_seat", -2)):
		_auto_played = true
		var hand: Array = _array("hand")
		if not hand.is_empty():
			call_deferred("_send_action", "play", int(hand[0].get("id", 0)))


func _relative_seat(seat: int) -> int:
	return (seat - int(_state.get("your_seat", 0)) + 4) % 4


func _refresh_avatar_presence() -> void:
	# Presence follows confirmed room events in every phase, not turn ownership.
	# A disconnected or freshly rejoined client must not show stale online data.
	var synced := training_mode or (_joined and _snapshot_ready)
	var connected := _array("connected_seats")
	for seat in _avatar_portraits.size():
		var portrait := _avatar_portraits[seat]
		if is_instance_valid(portrait):
			var occupied := bool(portrait.get_meta("occupied", false))
			var online: bool = occupied and not _exiting and (training_mode or (synced and seat < connected.size() and bool(connected[seat])))
			(portrait.material as ShaderMaterial).set_shader_parameter("online", online)
			portrait.tooltip_text = ("在线" if online else "离线") if occupied else "等待入座"
			portrait.accessibility_name = portrait.tooltip_text


func _render_seats() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	var focused_seat_button := focus.name if is_instance_valid(focus) and _seat_root.is_ancestor_of(focus) else &""
	_clear(_seat_root)
	_avatar_portraits.clear()
	var players := _array("players")
	var player_names := _array("player_names")
	var eggs := _array("egg_counts")
	var public_seats := _array("occupied_seats")
	var watching := _is_spectating()
	var missing_suits := _public_missing_suits()
	var factor := minf(size.x/1440.0,size.y/810.0)
	var clear_background := StyleBoxEmpty.new()
	_seat_voice_buttons.clear()
	_seat_panels.resize(4)
	for seat in range(4):
		var relative := _relative_seat(seat)
		var occupied := seat < players.size() and not str(players[seat]).is_empty()
		if watching: occupied = seat < public_seats.size() and bool(public_seats[seat])
		var nickname := "等待入座"
		if relative == 0 and not watching: nickname = str(match_context.get("display_name", "自己"))
		elif training_mode: nickname = ["自己", "右侧练习位", "对座练习位", "左侧练习位"][relative]
		elif _is_practice_table(): nickname = ["自己", "右侧电脑", "对座电脑", "左侧电脑"][relative]
		elif seat < player_names.size() and player_names[seat] is String and not player_names[seat].is_empty():
			nickname = player_names[seat]
		elif occupied: nickname = "%d 号位" % (seat + 1) if watching else ["自己", "右家", "对家", "左家"][relative]
		var balance: Variant = eggs[seat] if seat < eggs.size() else null
		if relative == 0 and balance == null: balance = match_context.get("own_egg_balance")
		var known: bool = (balance is int or balance is float) and balance >= 0 and is_finite(float(balance))
		var egg_text := str(int(balance)) if known else "—"
		var dealer := seat == int(_state.get("dealer", -1))
		var panel := Panel.new()
		panel.name="MahjongSeat%d"%relative
		panel.position=_seat_rect(relative).position
		panel.size=_seat_rect(relative).size
		panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
		panel.add_theme_stylebox_override("panel", clear_background)
		_seat_root.add_child(panel)
		var avatar := Panel.new()
		avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		avatar.position = Vector2(4, 4) * factor
		avatar.size = Vector2(68, 68) * factor
		avatar.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		var surround := RURAL.frame(Color("#e0a24c"), TABLE_THEME.BRASS, roundi(34 * factor), 1)
		surround.shadow_size = 0
		avatar.add_theme_stylebox_override("panel", surround)
		panel.add_child(avatar)
		var portrait := TextureRect.new()
		portrait.name="MahjongSquarePortrait"
		portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE
		portrait.texture=BATTLE_ART.player_portrait(relative)
		portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.position=Vector2.ONE*factor
		portrait.size=Vector2(66,66)*factor
		portrait.set_meta("occupied", occupied or training_mode)
		var presence_material := ShaderMaterial.new()
		presence_material.shader = PRESENCE_SHADER
		portrait.material = presence_material
		avatar.add_child(portrait)
		_avatar_portraits.append(portrait)
		var ring := _decoration(panel, BATTLE_ART.portrait_ring(), "MahjongAvatarGoldRim")
		ring.position = Vector2(2,2)*factor
		ring.size = Vector2(72,72)*factor
		if _can_moderate(seat):
			var manage := Button.new()
			manage.name = "MahjongSeatModeration%d" % seat
			manage.flat = true
			manage.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			manage.tooltip_text = "管理此牌友 · 静音或举报"
			manage.pressed.connect(_open_moderation.bind(seat))
			avatar.add_child(manage)
			manage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var name_label := _label(panel,"",74*factor,5*factor,0,27*factor,roundi(20*factor),Color("#fff1d4"))
		name_label.name = "MahjongSeatNickname"
		name_label.add_theme_stylebox_override("normal", clear_background)
		name_label.add_theme_color_override("font_outline_color", Color("#17261e"))
		name_label.add_theme_constant_override("outline_size", maxi(1, roundi(2 * factor)))
		name_label.add_theme_font_override("font", RURAL.title_font())
		name_label.autowrap_mode=TextServer.AUTOWRAP_OFF
		name_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.clip_text = true
		name_label.text = nickname
		var name_size := roundi(20 * factor)
		while name_size > 10 and name_label.get_theme_font("font").get_height(name_size) > 25 * factor:
			name_size -= 1
		name_label.add_theme_font_size_override("font_size", maxi(12, name_size))
		var text_edge := panel.size.x - 7.0 * factor
		name_label.size = Vector2(text_edge - name_label.position.x, 27.0 * factor)
		name_label.tooltip_text = nickname + (" · 庄家" if dealer else "")
		if not missing_suits.is_empty():
			var suit: String = DINGQUE_SUITS[missing_suits[seat]]
			var missing_x := text_edge - 47.0 * factor
			name_label.size.x = missing_x - name_label.position.x - 2.0 * factor
			var missing := _label(panel, "缺 " + suit, missing_x, 5 * factor, 47 * factor, 27 * factor,
				maxi(10, roundi(15 * factor)), TABLE_THEME.CREAM)
			missing.name = "MahjongMissingSuit%d" % seat
			missing.tooltip_text = "定缺" + suit
		var quantity := _label(panel,"",74*factor,34*factor,0,36*factor,roundi(31*factor),Color("#a42316"))
		quantity.name = "MahjongSeatEggs"
		quantity.add_theme_color_override("font_outline_color", Color("#ffe6c1"))
		quantity.add_theme_constant_override("outline_size", maxi(1, roundi(2 * factor)))
		quantity.add_theme_font_override("font", RURAL.title_font())
		quantity.autowrap_mode = TextServer.AUTOWRAP_OFF
		# CJK fonts have a taller line box than their point size. Fit the real
		# metrics so Godot never clips the entire balance line on compact cards.
		var balance_font := quantity.get_theme_font("font")
		var balance_size := maxi(10, roundi(31 * factor))
		var balance_width := text_edge - quantity.position.x
		var egg_extent := Vector2(20, 25) * factor
		var egg_gap := 4.0 * factor
		var balance_space := Vector2(maxf(1.0, balance_width - egg_extent.x - egg_gap - 6.0 * factor), 34.0 * factor)
		while balance_size > 10 and (balance_font.get_height(balance_size) > balance_space.y or balance_font.get_string_size(egg_text, HORIZONTAL_ALIGNMENT_LEFT, -1, balance_size).x > balance_space.x):
			balance_size -= 1
		quantity.add_theme_font_size_override("font_size", balance_size)
		quantity.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		quantity.clip_text = true
		quantity.text = egg_text
		# Center the number and its trailing currency icon as one unit. Reserve
		# the icon before fitting digits, including zero and long balances.
		var number_width := minf(balance_space.x + 2.0 * factor, balance_font.get_string_size(egg_text, HORIZONTAL_ALIGNMENT_LEFT, -1, balance_size).x + 2.0 * factor)
		var group_width := number_width + egg_gap + egg_extent.x
		quantity.position.x += maxf(0.0, (balance_width - group_width) * 0.5)
		quantity.size = Vector2(number_width, 36.0 * factor)
		quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		quantity.tooltip_text = "鸡蛋 %s 枚" % egg_text if known else "鸡蛋余额暂不可用"
		quantity.accessibility_name = quantity.tooltip_text
		var egg_icon := _decoration(panel, BATTLE_ART.EGG, "MahjongSeatEggIcon")
		egg_icon.position = Vector2(quantity.position.x + number_width + egg_gap, quantity.position.y + (quantity.size.y - egg_extent.y) * 0.5)
		egg_icon.size = egg_extent
		egg_icon.tooltip_text = quantity.tooltip_text
		if relative == 0:
			_seat_voice_buttons[seat] = _own_mic
		elif _can_moderate(seat):
			var mic := _button(panel,"",52*factor,50*factor,22*factor,22*factor,_toggle_seat_mute.bind(seat))
			mic.name="MahjongSeatMic%d"%seat
			BATTLE_ART.hud_button(mic, "muted" if _seat_muted(seat) else "mic", "切换此牌友静音")
			MODAL.size_icon_button(mic, self, 22.0 * factor)
			mic.size = mic.custom_minimum_size
			mic.tooltip_text="取消静音（本桌）" if _seat_muted(seat) else "静音此牌友的聊天、表情与语音"
			_seat_voice_buttons[seat]=mic
		_seat_panels[relative]=panel
	_refresh_avatar_presence()
	_position_avatar_clock()
	if focused_seat_button != &"":
		var replacement := _seat_root.find_child(str(focused_seat_button), true, false) as Button
		if is_instance_valid(replacement) and not replacement.disabled:
			replacement.grab_focus()
	_layout_own_mic()


func _table_rule() -> Dictionary:
	var value = _state.get("rule",match_context.get("rule",{}))
	return value if value is Dictionary else {}


func _rule_name() -> String:
	if training_mode: return "摸打练习"
	var title := str(_table_rule().get("name", "")).strip_edges()
	if not title.is_empty(): return title
	return "基础 108" if str(_state.get("rule_set_id", match_context.get("rule_set_id", ""))) == "basic_108" else "贵阳捉鸡"


func _room_kind() -> String:
	return str(_state.get("kind",match_context.get("kind","quick")))


func _is_practice_table() -> bool:
	return training_mode or _room_kind()=="training"


func _update_context_labels() -> void:
	var phase := str(_state.get("phase", ""))
	var status := str(_state.get("status", "waiting"))
	var own_turn := not _is_spectating() and int(_state.get("turn", -1)) == int(_state.get("your_seat", -2))
	_turn_label.text = "" if own_turn else "等待牌友"
	_turn_label.add_theme_color_override("font_color", Color("#ffe19b") if own_turn else Color("#fff8df"))
	var limit := int(_state.get("round_limit", match_context.get("round_limit", 0)))
	var completed := int(_state.get("completed_rounds", match_context.get("completed_rounds", 0)))
	_round_number.text = "%d/%d局" % [clampi(completed + 1, 1, limit), limit] if limit > 0 else ("练习" if _is_practice_table() else "第%d局" % maxi(1, completed + 1))
	_wall_number.text = "余牌 %d" % int(_state.remaining) if _state.has("remaining") else "余牌 —"
	var room := str(_state.get("room_id", match_context.get("room_id", "—")))
	_header.text = _rule_name() if training_mode else "%s · %s %s" % [_rule_name(), "训练房" if _room_kind() == "training" else "房间", room]
	BATTLE_ART.fit_room_heading(_header)
	if _state.get("saving", false):
		_turn_label.text = "正在保存"
	elif status == "waiting":
		_turn_label.text = "等待入座"
	elif phase == "reaction":
		_turn_label.text = "等待响应" if _options().is_empty() else "可以响应"
	elif phase == "finished":
		_turn_label.text = ""
	if _is_spectating(): _turn_label.text = "观战 · %d 号位" % (int(match_context.get("watch_seat", 0)) + 1)
	_turn_label.visible = not _turn_label.text.is_empty()
	_update_compass_winds()
	_update_clock()


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


func _tile_model(tile: Dictionary, location: Vector3, relative: int = 0, concealed: bool = false, tabletop := false) -> Node3D:
	var model := TILE_MODEL.build(_tile_materials, tile, concealed, tabletop)
	model.position = location
	var pitch := HAND_STANDING_ANGLE
	if tabletop: pitch = PI if concealed else 0.0
	model.rotation = Vector3(pitch, float(relative) * PI * 0.5, 0.0)
	_pieces_root.add_child(model)
	return model


func _render_opponent_hands() -> void:
	var counts := _array("hand_counts")
	for seat in range(mini(4,counts.size())):
		var relative := _relative_seat(seat)
		if relative == 0 and not _is_spectating(): continue
		var count := mini(int(counts[seat]),14)
		var hand_start := _concealed_row_start(relative, count)
		for index in range(count):
			var along := hand_start + float(index) * TILE_SIZE.x
			var position := _seat_table_position(relative, along, HAND_PIVOT_HEIGHT, HAND_PIVOT_DEPTH)
			var model := _tile_model({},position,relative,true)
			model.name="MahjongConcealedHand%d_%d"%[relative,index]


func _seat_table_position(relative: int, along: float, height: float, depth: float) -> Vector3:
	return Vector3(along, height, depth).rotated(Vector3.UP, float(relative) * PI * 0.5)


func _meld_layout(relative: int) -> Dictionary:
	var seats := _array("melds")
	var seat := posmod(relative + int(_state.get("your_seat", 0)), 4)
	var origins: Array[Vector2i] = []
	var widest := 0
	if seat < seats.size() and seats[seat] is Array:
		var remaining_width := _seat_concealed_count(relative) * TILE_SIZE.x
		var capacity := clampi(floori((2.0 * HAND_ROW_RADIUS - remaining_width - OPPONENT_MELD_SEPARATION) / TILE_SIZE.x), 4, 12)
		var row := 0
		var used := 0
		for meld in seats[seat].slice(0, 4):
			var count := mini(4, meld.tiles.size()) if meld is Dictionary and meld.get("tiles") is Array else 0
			if used + count > capacity:
				row += 1
				used = 0
			origins.append(Vector2i(used, row))
			used += count
			widest = maxi(widest, used)
	return {"origins":origins, "columns":widest}


func _seat_concealed_count(relative: int) -> int:
	if relative == 0 and not _is_spectating(): return _array("hand").size()
	var counts := _array("hand_counts")
	for seat in range(mini(4, counts.size())):
		if _relative_seat(seat) == relative: return clampi(int(counts[seat]), 0, 14)
	return 0


func _concealed_row_start(relative: int, count: int) -> float:
	var meld_width := int(_meld_layout(relative).columns) * TILE_SIZE.x
	var separator := _meld_hand_gap(relative) if meld_width > 0.0 and count > 0 else 0.0
	return (meld_width + separator - count * TILE_SIZE.x + TILE_SIZE.x) * 0.5


func _meld_hand_gap(relative: int) -> float:
	return TILE_SIZE.x if relative == 0 and not _is_spectating() else OPPONENT_MELD_SEPARATION


func _render_discards() -> void:
	var per_seat := [[], [], [], []]
	var discards := _array("discards")
	var last: Dictionary = discards.back() if not discards.is_empty() and discards.back() is Dictionary else {}
	var latest_model: Node3D = null
	for raw in discards:
		if typeof(raw) == TYPE_DICTIONARY:
			var seat := int(raw.get("seat", -1))
			if seat >= 0 and seat < 4 and not bool(raw.get("claimed", false)):
				per_seat[seat].append(raw.get("tile", {}))
	var river_columns: Array[int] = []
	for river: Array in per_seat:
		river_columns.append(14 if training_mode else clampi(ceili(river.size() / 2.0), DISCARD_COLUMNS, 12))
	for seat in range(4):
		var relative := _relative_seat(seat)
		var count: int = per_seat[seat].size()
		var columns := river_columns[seat]
		# Leave enough room for the perpendicular rivers at each corner without changing a tile's size.
		var adjacent_columns := maxi(river_columns[(seat + 1) % 4], river_columns[(seat + 3) % 4])
		var inner_edge := 0.114 if training_mode else maxf(0.112, adjacent_columns * TILE_SIZE.x * 0.5 - RIVER_SIDE_OFFSET + RIVER_CORNER_GAP)
		var first_depth := inner_edge + TILE_SIZE.z * 1.5
		for index in range(count):
			var row := int(index / columns)
			var col := index % columns
			var visible_columns := mini(columns, count - row * columns) if training_mode else columns
			var along := (col - (visible_columns - 1) * 0.5) * TILE_SIZE.x + (0.0 if training_mode else RIVER_SIDE_OFFSET)
			var depth := first_depth + row * TILE_SIZE.z
			var position := _seat_table_position(relative, along, 0.0015, depth)
			var model := _tile_model(per_seat[seat][index], position, relative, false, true)
			model.name = "MahjongDiscard%d_%d" % [seat, index]
			var last_tile: Variant = last.get("tile", {})
			if not bool(last.get("claimed", false)) and int(last.get("seat", -1)) == seat and last_tile is Dictionary and int(last_tile.get("id", 0)) > 0 and int(last_tile.get("id", 0)) == int(per_seat[seat][index].get("id", 0)):
				latest_model = model
	var key := "%s:%d:%d:%d" % [str(_state.get("match_id", "")), int(last.get("seat", -1)), discards.size(), int(last.get("tile", {}).get("id", 0))] if is_instance_valid(latest_model) else ""
	if str(_state.get("phase", "")) == "finished": latest_model = null
	_tile_focus.bind_last_discard(latest_model, key)


func _render_melds() -> void:
	var meld_groups: Array = _array("melds")
	for seat in range(mini(4, meld_groups.size())):
		if not meld_groups[seat] is Array:
			continue
		var relative := _relative_seat(seat)
		var melds: Array = meld_groups[seat]
		var layout := _meld_layout(relative)
		var concealed_count := _seat_concealed_count(relative)
		var meld_width := int(layout.columns) * TILE_SIZE.x
		var hand_width := concealed_count * TILE_SIZE.x
		var separator := _meld_hand_gap(relative) if concealed_count > 0 else 0.0
		var bank_width := meld_width + hand_width + separator
		var start := (TILE_SIZE.x - bank_width) * 0.5
		for index in range(mini(4, melds.size())):
			var meld: Variant = melds[index]
			if not meld is Dictionary or not meld.get("tiles") is Array:
				continue
			var tiles: Array = meld.tiles
			var origin: Vector2i = layout.origins[index]
			var depth := HAND_ROW_RADIUS - origin.y * (TILE_SIZE.z + MELD_ROW_GAP)
			var concealed: bool = (relative != 0 or _is_spectating()) and meld.get("kind") == "an_gang"
			# Every seat reads its exposed sets from its own left, just ahead of
			# its remaining concealed row. Rotate both rows with the same seat basis.
			var height := 0.0015 + (TILE_SIZE.y if concealed else 0.0)
			for tile_index in range(mini(4, tiles.size())):
				if not tiles[tile_index] is Dictionary:
					continue
				var along := start + (origin.x + tile_index) * TILE_SIZE.x
				var position := _seat_table_position(relative, along, height, depth)
				var model := _tile_model(tiles[tile_index], position, relative, concealed, true)
				model.name = "MahjongMeld%d_%d_%d" % [relative, index, tile_index]


func _render_hand() -> void:
	var hand: Array = _array("hand")
	if hand.is_empty():
		_tile_focus.select_tile(null)
		return
	var drawn_id := int(_state.get("drawn_tile_id",0))
	if drawn_id > 0:
		for index in range(hand.size()):
			if int(hand[index].get("id",0)) != drawn_id: continue
			hand = hand.duplicate()
			var drawn: Dictionary = hand.pop_at(index)
			hand.append(drawn)
			break
	_hand_models.clear()
	_hand_ids.clear()
	var hand_start := _concealed_row_start(0, hand.size())
	for index in range(hand.size()):
		var tile: Dictionary = hand[index]
		var id := int(tile.get("id", 0))
		var along := hand_start + float(index) * TILE_SIZE.x
		var model := _tile_model(tile, _own_tile_position(along, OWN_HAND_LIFT if id == _selected_id else 0.0))
		_hand_models.append(model)
		_hand_ids.append(id)
	_sync_selected_tile_emission()


func _sync_selected_tile_emission() -> void:
	var selected: Node3D = null
	for index in _hand_ids.size():
		if _hand_ids[index] == _selected_id:
			selected = _hand_models[index]
			break
	_tile_focus.select_tile(selected)


func _select_tile(id: int) -> void:
	if training_mode and _state.get("phase") != "turn": return
	if id != 0 and not _hand_contains(id): return
	_sync_coach_selection_window()
	if not _coach_selection_key.is_empty(): _coach_manual_selection = true
	_selected_id = id
	_render_hand_only()
	if not _legal_options("play").is_empty() and not _pending_action:
		_status.text = _discard_prompt()


func _discard_prompt() -> String:
	if training_mode and int(_state.get("remaining", 0)) == 0:
		return "牌墙已空 · 打出后结束"
	if _selected_id == 0:
		return "点选手牌，再点一次或点击打出"
	return "当前不能打出这张牌" if _play_button.disabled else ""


func _render_hand_only() -> void:
	for index in range(_hand_models.size()):
		var model := _hand_models[index]
		model.position = _own_tile_position(model.position.x, OWN_HAND_LIFT if _hand_ids[index] == _selected_id else 0.0)
	_sync_selected_tile_emission()
	_update_selection()


func _update_selection() -> void:
	if is_instance_valid(_play_button):
		var may_play := not _legal_options("play").is_empty()
		_play_button.visible = _actions_ready() and may_play
		_play_button.disabled = not may_play or _pending_action or not _can_play_tile(_selected_id)
		_play_button.tooltip_text = "选中一张手牌后打出" if may_play else "等到自己的出牌回合"
	if is_instance_valid(_training_restart): _training_restart.visible = _state.get("phase") == "finished"
	_layout_hand_controls()


func _tile_title(tile: Dictionary) -> String:
	var ranks := ["一", "二", "三", "四", "五", "六", "七", "八", "九"]
	var suffix := {"wan": "万", "tong": "筒", "tiao": "条"}
	return str(ranks[clampi(int(tile.get("rank", 1)) - 1, 0, 8)]) + str(suffix.get(str(tile.get("suit", "")), ""))


func _hand_contains(id: int) -> bool:
	if id <= 0:
		return false
	for tile in _array("hand"):
		if int(tile.get("id", 0)) == id:
			return true
	return false


func _options() -> Array:
	return _array("options")


func _action_button(caption: String, action: Callable, style: String = "") -> Button:
	var button := _button(_actions_root, caption, 0, 0, ACTION_BUTTON_SIZE.x, ACTION_BUTTON_SIZE.y, action, style.is_empty())
	if not style.is_empty():
		BATTLE_ART.lacquer(button, style)
	button.add_theme_font_size_override("font_size", ACTION_FONT_SIZE)
	button.custom_minimum_size = ACTION_BUTTON_SIZE
	button.size = ACTION_BUTTON_SIZE
	return button


func _render_actions() -> void:
	for index in range(RESPONSE_KINDS.size()):
		var kind: String = RESPONSE_KINDS[index]
		var button := _action_button(["吃", "碰", "杠", "胡", "过"][index], _on_response.bind(kind), kind)
		button.name = "MahjongAction_" + kind
		if kind == "pass": button.tooltip_text = "放弃对他人这次出牌或补杠的响应"
		_response_buttons[kind] = button
	for suit in DINGQUE_SUITS:
		var button := _action_button("缺" + DINGQUE_SUITS[suit],
			_send_action.bind("dingque", 0, [], suit))
		button.name = "MahjongDingque_" + suit
		button.tooltip_text = "选择定缺" + DINGQUE_SUITS[suit]
		_dingque_buttons[suit] = button
	_refresh_connection_actions(false)


func _is_dingque_table() -> bool:
	return _state.get("rule_set_id") == "zunyi_dingque" and _state.get("rule_version") == "1.0.0" and _table_rule().get("dingque") == true


func _public_missing_suits() -> Array:
	if not _is_dingque_table() or _state.get("phase") not in ["turn", "reaction", "finished"]: return []
	var suits: Variant = _state.get("missing_suits")
	if not suits is Array or suits.size() != 4 or not suits.all(func(suit): return DINGQUE_SUITS.has(suit)): return []
	return suits


func _requires_kong_to_claim() -> bool:
	var rule := _table_rule()
	var rule_id: Variant = _state.get("rule_set_id", rule.get("rule_set_id", match_context.get("rule_set_id")))
	return rule_id == "guiyang" or rule.get("requires_kong_to_claim") == true


func _has_completed_kong(seat: int) -> bool:
	var melds := _array("melds")
	if seat < 0 or seat >= melds.size() or not melds[seat] is Array: return false
	for meld in melds[seat]:
		if meld is Dictionary and meld.get("kind") in ["ming_gang", "an_gang", "bu_gang"] \
				and meld.get("tiles") is Array and meld.tiles.size() == 4:
			return true
	return false


func _legal_options(kind: String) -> Array:
	var found: Array = []
	var phase := str(_state.get("phase", ""))
	if str(_state.get("status", "")) != "playing" or _state.get("saving",false): return found
	var seat := _option_integer(_state.get("your_seat",-1))
	if seat < 0 or seat >= 4: return found
	if phase == "dingque":
		if kind != "dingque" or not _is_dingque_table(): return found
		var suits := {}
		for option in _options():
			if not option is Dictionary or option.get("type") != "dingque" or option.has("tile_id"): continue
			var suit: Variant = option.get("suit")
			if not DINGQUE_SUITS.has(suit) or suits.has(suit): continue
			suits[suit] = true
			found.append(option)
		return found
	if phase not in ["turn", "reaction"]: return found
	var turn := _option_integer(_state.get("turn",-1))
	if turn<0 or turn>3 or (phase=="turn" and turn!=seat) or (phase=="reaction" and turn==seat): return found
	var seen := {}
	for raw in _options():
		if not raw is Dictionary: continue
		var option_kind := str(raw.get("type", ""))
		if option_kind != kind and not (kind == "gang" and option_kind in ["ming_gang", "an_gang", "bu_gang"]): continue
		# "gang" is a presentation group, never a server command. Enforce the
		# private snapshot's phase and physical tile identity before showing it.
		var tile_id := _option_integer(raw.get("tile_id",0))
		if tile_id<0: continue
		match option_kind:
			"play":
				if phase!="turn" or (tile_id!=0 and not _hand_contains(tile_id)): continue
			"an_gang", "bu_gang":
				if phase!="turn" or tile_id<=0 or _option_integer(_state.get("remaining",0))<=0: continue
				var tile := _option_hand_tile(tile_id)
				if tile.is_empty(): continue
				if option_kind=="an_gang" and _option_hand_copies(tile)!=4: continue
				if option_kind=="bu_gang" and not _option_has_own_pong(tile,seat): continue
			"peng", "ming_gang", "chi":
				if phase!="reaction" or tile_id!=0: continue
				var discarded := _option_claim_tile(turn)
				if discarded.is_empty(): continue
				if option_kind=="peng" and _option_hand_copies(discarded)<2: continue
				if option_kind=="ming_gang" and (_option_hand_copies(discarded)!=3 or _option_integer(_state.get("remaining",0))<=0): continue
				if option_kind=="chi" and not bool(_table_rule().get("allow_chi",false)): continue
			"pass":
				if phase!="reaction" or tile_id!=0: continue
			"hu":
				if tile_id!=0: continue
				if phase == "reaction" and _requires_kong_to_claim() and not _has_completed_kong(seat): continue
				if not _option_hu_shape(seat, turn, phase): continue
			_: continue
		var identity := "%s:%d"%[option_kind,tile_id]
		if seen.has(identity): continue
		seen[identity]=true
		found.append(raw)
	return found


func _option_integer(value: Variant) -> int:
	if not (value is int or value is float) or not is_finite(float(value)) or float(value)!=floorf(float(value)): return -1
	return int(value)


func _debug_rejected_action_options() -> Dictionary:
	# One event-path diagnostic per accepted private snapshot, never from the
	# frequently queried option projector. Do not log hands or free-form fields.
	if not OS.is_debug_build(): return {}
	var received: Array[String] = []
	var accepted: Array[String] = []
	var checked := {}
	var subtypes := ["play","peng","chi","ming_gang","an_gang","bu_gang","hu","pass","dingque"]
	for raw in _options():
		var subtype := str(raw.get("type","")) if raw is Dictionary else ""
		received.append(subtype if subtype in subtypes or subtype=="gang" else "unknown")
		if subtype not in subtypes or checked.has(subtype): continue
		checked[subtype]=true
		for option in _legal_options(subtype): accepted.append(subtype)
	if received.size()==accepted.size(): return {}
	var phase := str(_state.get("phase",""))
	var diagnostic := {"phase":phase if phase in ["turn","reaction","dingque","finished"] else "unknown", "turn":_option_integer(_state.get("turn",-1)), "own_seat":_option_integer(_state.get("your_seat",-1)), "epoch":_option_integer(_state.get("epoch",-1)), "received":received, "accepted":accepted}
	print("MAHJONG_ACTION_OPTIONS_FILTERED "+JSON.stringify(diagnostic))
	return diagnostic


func _option_hand_tile(id: int) -> Dictionary:
	for raw in _array("hand"):
		if raw is Dictionary and _option_integer(raw.get("id",0))==id: return raw
	return {}


func _option_same_kind(a: Dictionary, b: Dictionary) -> bool:
	var rank := _option_integer(a.get("rank",0))
	return rank>0 and not str(a.get("suit","")).is_empty() and str(a.get("suit",""))==str(b.get("suit","")) and rank==_option_integer(b.get("rank",0))


func _option_hand_copies(tile: Dictionary) -> int:
	var ids := {}
	for raw in _array("hand"):
		if not raw is Dictionary: continue
		var id := _option_integer(raw.get("id",0))
		if id>0 and _option_same_kind(raw,tile): ids[id]=true
	return ids.size()


func _option_has_own_pong(tile: Dictionary, seat: int) -> bool:
	var melds := _array("melds")
	if seat>=melds.size() or not melds[seat] is Array: return false
	for meld in melds[seat]:
		if not meld is Dictionary or meld.get("kind")!="peng" or not meld.get("tiles") is Array or meld.tiles.size()!=3: continue
		var matching := true
		var ids := {}
		for held in meld.tiles:
			if not held is Dictionary or not _option_same_kind(held,tile):
				matching=false
				continue
			var id := _option_integer(held.get("id",0))
			if id<=0 or id==_option_integer(tile.get("id",0)): matching=false
			ids[id]=true
		if matching and ids.size()==3: return true
	return false


func _option_claim_tile(turn: int) -> Dictionary:
	if _state.get("pending_kind", "discard") != "discard" or _option_integer(_state.get("pending_from", turn)) != turn: return {}
	var discarded: Variant = _state.get("last_discard")
	var river := _array("discards")
	if not discarded is Dictionary or river.is_empty(): return {}
	var last: Variant=river.back()
	if not last is Dictionary or last.get("claimed",false) or _option_integer(last.get("seat",-1))!=turn or not last.get("tile") is Dictionary: return {}
	var id := _option_integer(discarded.get("id",0))
	if id<=0 or _hand_contains(id) or id!=_option_integer(last.tile.get("id",0)) or not _option_same_kind(discarded,last.tile): return {}
	return discarded


func _option_hu_shape(seat: int, turn: int, phase: String) -> bool:
	var melds := _array("melds")
	if seat >= melds.size() or not melds[seat] is Array: return false
	var hand := _array("hand").duplicate()
	if phase == "turn":
		var drawn := _option_integer(_state.get("drawn_tile_id", 0))
		if drawn <= 0 or not _hand_contains(drawn): return false
	else:
		var tile := _option_claim_tile(turn)
		if tile.is_empty(): tile = _option_rob_kong_tile(turn)
		if tile.is_empty(): return false
		hand.append(tile)
	if _is_dingque_table():
		var missing := _public_missing_suits()
		if missing.size() != 4: return false
		for tile in hand:
			if tile is Dictionary and tile.get("suit") == missing[seat]: return false
		for meld in melds[seat]:
			if not meld is Dictionary or not meld.get("tiles") is Array: return false
			for tile in meld.tiles:
				if tile is Dictionary and tile.get("suit") == missing[seat]: return false
	return MAHJONG_CORE.has_complete_hand(hand, melds[seat])


func _option_rob_kong_tile(turn: int) -> Dictionary:
	if _state.get("pending_kind", "bu_gang") != "bu_gang" or _option_integer(_state.get("pending_from", turn)) != turn: return {}
	var options: Variant = _table_rule().get("options", {})
	if options is Dictionary and options.get("rob_kong", true) != true: return {}
	var tile: Variant = _state.get("last_discard")
	if not tile is Dictionary: return {}
	var id := _option_integer(tile.get("id", 0))
	if id <= 0 or _hand_contains(id): return {}
	# An upgrade exposes the owner's fourth tile, not a tile already in a river.
	for discarded in _array("discards"):
		if discarded is Dictionary and discarded.get("tile") is Dictionary and _option_integer(discarded.tile.get("id", 0)) == id: return {}
	return tile if _option_has_own_pong(tile, turn) else {}


func _action_snapshot_key() -> Array:
	return [_action_snapshot_revision,_state.get("room_id"),_state.get("match_id"),_state.get("epoch"),_state.get("phase"),_state.get("turn"),_state.get("your_seat")]


func _can_play_tile(id: int) -> bool:
	if not _hand_ids.has(id) or not _hand_contains(id): return false
	for option in _legal_options("play"):
		var allowed: Variant = option.get("tile_id", 0)
		if not (allowed is int or allowed is float) or not is_finite(float(allowed)): continue
		if allowed == 0 or allowed == id: return true
	return false


func _on_response(kind: String) -> void:
	if _pending_action:
		_status.text = "操作已提交 · 等待牌桌确认"
		return
	if kind == "chi" and not bool(_table_rule().get("allow_chi",false)):
		_status.text = "本桌玩法不支持吃牌 · 可按服务器提示碰、杠、胡"
		return
	if not _require_actions_ready(): return
	var options := _legal_options(kind)
	if options.is_empty():
		_status.text = "当前没有合法的%s操作" % _action_name(kind)
		return
	if kind == "gang" and options.size() > 1:
		_open_tool("gang")
		return
	var option: Dictionary = options[0]
	_send_action(str(option.get("type", "")), int(option.get("tile_id", 0)))


func _action_name(kind: String) -> String:
	match kind:
		"play": return "打出"
		"pass": return "过"
		"peng": return "碰"
		"gang": return "杠"
		"ming_gang": return "明杠"
		"an_gang": return "暗杠"
		"bu_gang": return "补杠"
		"hu": return "胡"
	return kind


func _on_play() -> void:
	if training_mode and _state.get("phase") != "turn": return
	if _selected_id <= 0:
		_status.text = "请先点击一张手牌"
		return
	_send_action("play", _selected_id)


func _send_action(kind: String, tile_id: int = 0, source_key: Array = [], suit: String = "") -> void:
	if not source_key.is_empty() and source_key!=_action_snapshot_key():
		_status.text = "牌桌已更新，请按当前可用操作继续"
		_refresh_connection_actions()
		return
	if _pending_action:
		_status.text = "操作已提交 · 等待牌桌确认"
		return
	if not _require_actions_ready(): return
	var legal := _can_play_tile(tile_id) if kind == "play" else _legal_options(kind).any(
		func(option: Dictionary) -> bool:
			return option.get("suit") == suit if kind == "dingque" else int(option.get("tile_id", 0)) == tile_id)
	if not legal:
		_status.text = "该操作不在服务器当前合法选项中"
		return
	if training_mode:
		if kind == "play":
			_training_play(tile_id)
		return
	var packet := {"type":"mahjong_action","action":kind}
	if kind == "dingque": packet["suit"] = suit
	else: packet["tile_id"] = tile_id
	var window_id: Variant = _state.get("action_window_id")
	if window_id is String and not window_id.is_empty():
		packet["action_window_id"] = window_id
	var id := ""
	var match_id := str(_state.get("match_id", ""))
	if not match_id.is_empty():
		_command_serial += 1
		id = "%s-%d" % [_command_prefix, _command_serial]
		packet["command_id"] = id
		packet["match_id"] = match_id
	_send(packet)
	if _last_send_error == OK:
		_pending_action = true
		_pending_command = id
		_pending_action_kind = kind
		_pending_epoch = int(_state.get("epoch",0))
		_pending_accepted = false
		if id.is_empty():
			_selected_id = 0
			_render_hand_only()
		if _tool_open == "gang": _close_tool()
		_refresh_connection_actions()
		_status.text = "操作已提交 · 等待牌桌确认"


func _training_play(tile_id: int) -> void:
	if tile_id <= 0 or _state.get("phase") != "turn":
		return
	var hand: Array = _array("hand")
	for index in range(hand.size()):
		if int(hand[index].get("id", 0)) != tile_id:
			continue
		var discards: Array = _array("discards")
		var played: Dictionary = hand[index]
		discards.append({"seat": 0, "tile": played, "claimed": false})
		hand.remove_at(index)
		if _training_wall.is_empty():
			_state["status"] = "finished"
			_state["phase"] = "finished"
			_state["turn"] = -1
			_state["options"] = []
			_state["drawn_tile_id"] = 0
		else:
			var drawn: Dictionary = _training_wall.pop_back()
			hand.append(drawn)
			_state["drawn_tile_id"] = drawn.id
		_state["hand_counts"][0] = hand.size()
		_state["remaining"] = _training_wall.size()
		_selected_id = 0
		_play_sound()
		_play_callout("discard", played)
		_render()
		return


func _snapshot_audio_cue(incoming: Dictionary) -> String:
	# Only live updates after a fresh snapshot are audible.
	if not _snapshot_ready or _state.get("status") != "playing": return ""
	if incoming.get("match_id", "") != _state.get("match_id", ""): return ""
	var epoch := int(_state.get("epoch", -1))
	if epoch < 0 or int(incoming.get("epoch", -1)) <= epoch: return ""
	if incoming.has("action_events"):
		if incoming.get("phase") == "finished": return "settlement"
		var recent_discards: Variant = incoming.get("discards")
		return "discard" if recent_discards is Array and recent_discards.size() == _array("discards").size() + 1 else ""
	if int(incoming.get("epoch", -1)) != epoch + 1: return ""
	if incoming.get("phase") == "finished": return "settlement"
	var prior_melds: Array = _array("melds")
	var melds: Variant = incoming.get("melds")
	if melds is Array:
		for seat in range(mini(melds.size(), prior_melds.size())):
			var before: Variant = prior_melds[seat]
			var after: Variant = melds[seat]
			if not before is Array or not after is Array: continue
			for index in range(after.size()):
				if index < before.size() and after[index].get("kind") == before[index].get("kind"): continue
				var kind := str(after[index].get("kind", ""))
				if kind == "peng": return "peng"
				if kind.ends_with("gang"): return "gang"
	var discards: Variant = incoming.get("discards")
	return "discard" if discards is Array and discards.size() == _array("discards").size() + 1 else ""


func _collect_action_events(incoming: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var history: Variant = incoming.get("action_events")
	if not history is Array: return result
	var live := _snapshot_ready and str(incoming.get("match_id", "")) == str(_state.get("match_id", ""))
	if not live: _last_action_sequence = 0
	for event in history:
		if not event is Dictionary: continue
		var sequence := int(event.get("sequence", 0))
		var seat := int(event.get("seat", -1))
		var action := str(event.get("type", ""))
		if sequence <= _last_action_sequence or seat < 0 or seat > 3 or not ACTION_EFFECT.NAMES.has(action): continue
		_last_action_sequence = sequence
		if live: result.append(event)
	return result


func _snapshot_discard(incoming: Dictionary) -> Dictionary:
	if not _snapshot_ready or _state.get("status") != "playing": return {}
	if incoming.get("match_id", "") != _state.get("match_id", ""): return {}
	if int(incoming.get("epoch", -1)) <= int(_state.get("epoch", -1)): return {}
	var discards: Variant = incoming.get("discards")
	if not discards is Array or discards.size() != _array("discards").size() + 1: return {}
	var latest: Variant = discards.back()
	if not latest is Dictionary: return {}
	var tile: Variant = latest.get("tile")
	return tile if tile is Dictionary and int(tile.get("id", 0)) > 0 else {}


func _show_action_effects(events: Array[Dictionary]) -> void:
	var unit := minf(size.x / 1440.0, size.y / 810.0)
	var chosen: Dictionary = events.back()
	for event in events:
		if event.type == "hu":
			chosen = event
	var action: String = chosen.type
	_clear(_action_effects)
	var effect := ACTION_EFFECT.new()
	effect.name = "MahjongAction%d" % int(chosen.sequence)
	effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	effect.size = Vector2(360, 230) * unit
	effect.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	_action_effects.add_child(effect)
	effect.position = (size - effect.size) * 0.5
	effect.show_action(action)
	_start_camera_impact(action, unit)
	_play_sound("settlement" if action == "hu" else "peng" if action == "peng" else "gang")
	if is_instance_valid(product_audio):
		product_audio.play_action_impact(action)
	_play_callout(action)


func _start_camera_impact(action: String, unit: float) -> void:
	_stop_camera_impact()
	var strength := (5.0 if action == "hu" else 3.8 if action.ends_with("gang") else 2.2)*unit
	_camera_impact = create_tween()
	_camera_impact.tween_method(_apply_camera_impact.bind(strength), 0.0, 1.0, 0.24)


func _apply_camera_impact(progress: float, strength: float) -> void:
	if not is_instance_valid(_camera): return
	var delta := Vector2(sin(progress*TAU*2.5), sin(progress*TAU*3.0)*0.55)
	delta *= strength * pow(1.0 - progress, 2.0)
	var step := delta - _camera_displacement
	_camera_displacement = delta
	# Keep the native surface fixed so the impact cannot expose a window edge.
	_camera.h_offset -= step.x * _camera_world_per_pixel
	_camera.v_offset += step.y * _camera_world_per_pixel
	_coach_overlay.shift_badges(step)
	_layout_compass()
	_layout_selection()


func _stop_camera_impact() -> void:
	if is_instance_valid(_camera_impact): _camera_impact.kill()
	_camera_impact = null
	if _camera_displacement != Vector2.ZERO and not _exiting:
		_apply_camera_impact(1.0, 0.0)


func _build_audio() -> void:
	if not is_instance_valid(product_audio):
		_owns_audio = true
		product_audio = AUDIO.new()
		product_audio.preference_file = preference_file
		product_audio.music_enabled = _music_enabled
		product_audio.effects_enabled = _sound_enabled
		add_child(product_audio)
	_music_enabled = product_audio.music_enabled
	_sound_enabled = product_audio.effects_enabled
	product_audio.preferences_changed.connect(_audio_preferences_changed)


func _audio_preferences_changed(music: bool, effects: bool) -> void:
	_music_enabled = music
	_sound_enabled = effects
	_apply_audio()
	_sync_settings()


func _apply_audio() -> void:
	if is_instance_valid(_voice): _voice.set_playback_enabled(_sound_enabled and not _muted_accounts.has(_playing_voice_account))


func _play_sound(cue: String = "discard") -> void:
	if is_instance_valid(product_audio): product_audio.play_cue(cue)


func _play_callout(cue: String, tile: Dictionary = {}) -> void:
	if is_instance_valid(product_audio): product_audio.play_callout(cue, tile)


func _stop_audio() -> void:
	if is_instance_valid(_voice): _voice.set_playback_enabled(false)
	if is_instance_valid(product_audio):
		product_audio.stop_callout()
		product_audio.stop_action_impact()
		if product_audio.preferences_changed.is_connected(_audio_preferences_changed):
			product_audio.preferences_changed.disconnect(_audio_preferences_changed)
	if _owns_audio and is_instance_valid(product_audio):
		product_audio.queue_free()
	product_audio = null


func _update_clock() -> void:
	if not is_instance_valid(_remaining_number): return
	_stop_clock()
	var watching_live := _is_spectating() and _joined and _snapshot_ready and not _exiting
	_position_avatar_clock()
	if _remaining_number.visible and _deadline_tick > 0 and (_actions_ready() or watching_live):
		var seconds := maxf(0.0,float(_deadline_tick-Time.get_ticks_msec())/1000.0)
		_draw_clock(seconds)
		if seconds>0.0:
			_clock_animation = create_tween()
			_clock_animation.tween_method(_draw_clock,seconds,0.0,seconds)
	else:
		_remaining_number.text = "—"
		_remaining_number.hide()


func _position_avatar_clock() -> void:
	if not is_instance_valid(_remaining_number): return
	var phase := str(_state.get("phase", ""))
	var seat := -1
	if phase == "turn":
		seat = int(_state.get("turn", -1))
	elif phase in ["reaction", "dingque"] and not _is_spectating() and not _options().is_empty():
		seat = int(_state.get("your_seat", -1))
	var ready := (_is_spectating() and _joined and _snapshot_ready) or _actions_ready()
	_remaining_number.visible = not _exiting and ready and _state.get("status") == "playing" and _deadline_tick > 0 and seat >= 0 and seat < _avatar_portraits.size()
	if not _remaining_number.visible: return
	var portrait := _avatar_portraits[seat]
	var bounds := portrait.get_global_rect()
	# The mute control is at the lower right. Keep the timer on the portrait's lower left.
	var extent := Vector2(bounds.size.x * 0.60, bounds.size.y * 0.37)
	var point_size := maxi(8, roundi(extent.y * 0.68))
	_remaining_number.add_theme_font_size_override("font_size", point_size)
	_remaining_number.size = extent
	_remaining_number.global_position = Vector2(bounds.position.x, bounds.end.y - _remaining_number.size.y)
	_remaining_number.tooltip_text = "出牌剩余秒数" if phase == "turn" else ("定缺剩余秒数" if phase == "dingque" else "响应剩余秒数")


func _draw_clock(seconds: float) -> void:
	var text := str(maxi(0,ceili(seconds)))
	if is_instance_valid(_remaining_number) and _remaining_number.text!=text:
		_remaining_number.text = text


func _stop_clock() -> void:
	if is_instance_valid(_clock_animation): _clock_animation.kill()
	_clock_animation = null


func _open_tool(kind: String) -> void:
	if _exiting: return
	if _tool_open.is_empty():
		var focus := get_viewport().gui_get_focus_owner()
		_tool_opener = weakref(focus) if is_instance_valid(focus) and not _overlay_root.is_ancestor_of(focus) else null
	_coach_overlay.close_detail()
	_tool_open = "leave" if kind == "exit" else ("chat" if kind == "emote" else kind)
	_clear(_overlay_root)
	_render_tool()


func _show_table_notice(title: String, message: String) -> void:
	if _tool_open == "notice" and _notice_title == title and _notice_message == message: return
	_notice_title = title
	_notice_message = message
	_open_tool("notice")


func _close_tool() -> void:
	var opener := _tool_opener.get_ref() as Control if _tool_opener != null else null
	_tool_opener = null
	_tool_open = ""
	_clear(_overlay_root)
	_settings_view = null
	_block_board_focus(false)
	if not training_mode and str(_state.get("phase", "")) == "finished":
		_render_settlement_overlay()
	if is_instance_valid(opener) and opener.is_visible_in_tree() and not is_instance_valid(_settlement_panel):
		opener.grab_focus()


func _block_board_focus(blocked: bool) -> void:
	for child in get_children():
		if child is Control and child != _overlay_root:
			child.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED if blocked else Control.FOCUS_BEHAVIOR_INHERITED


func _usable_modal_area() -> Rect2:
	var origin := Vector2(_safe.x, _safe.y)
	return Rect2(origin, size - origin - Vector2(_safe.z, _safe.w))


func _tool_panel(title: String, height: float) -> VBoxContainer:
	var dim := ColorRect.new()
	dim.name = "MahjongToolDim"
	dim.color = Color("#22191096")
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_root.add_child(dim)
	_tool_surface = MODAL.village_panel(_overlay_root)
	_tool_surface.name = "MahjongToolPanel_" + _tool_open
	_tool_surface.set_meta("preferred_height", height)
	var layout := VBoxContainer.new()
	_tool_surface.add_child(layout)
	layout.add_theme_constant_override("separation", 12)
	var header := HBoxContainer.new()
	layout.add_child(header)
	var leading_space := Control.new()
	leading_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(leading_space)
	var title_slot := CenterContainer.new()
	title_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_slot)
	_tool_title = MODAL.village_title(title_slot, title, _tool_surface)
	_tool_title.get_parent().name = "MahjongToolTitlePlate"
	_tool_title.clip_text = true
	_tool_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_tool_title.add_theme_font_size_override("font_size", 27)
	var close := _button(header, "", 0, 0, 48, 48, _close_tool)
	close.name = "MahjongToolClose"
	MODAL.icon_button(close, MODAL.icon("close"), "关闭")
	var scroll := ScrollContainer.new()
	scroll.name = "MahjongToolScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	_fit_tool_panel()
	close.grab_focus()
	return body


func _modal_pixel_scale() -> float:
	var canvas := get_viewport_transform() * get_global_transform()
	return 1.0 / maxf(0.01, minf(canvas.x.length(), canvas.y.length()))


func _fit_tool_panel() -> void:
	var area := _usable_modal_area()
	var pixel := _modal_pixel_scale()
	var bounds := Rect2(Vector2.ZERO, area.size / pixel).grow(-12.0)
	var width := minf(640.0, bounds.size.x)
	var height := minf(float(_tool_surface.get_meta("preferred_height")), bounds.size.y - 16.0)
	_tool_title.get_parent().custom_minimum_size.x = clampf(width - 190.0, 96.0, 345.0)
	_tool_surface.scale = Vector2.ONE * pixel
	var close := _tool_surface.find_child("MahjongToolClose", true, false) as Button
	var tool_header := close.get_parent()
	(tool_header.get_child(0) as Control).custom_minimum_size.x = MODAL.size_icon_button(close, close)
	_tool_surface.size = Vector2(width, height)
	var plate := _tool_title.get_parent() as Control
	var headroom := maxf(0.0, plate.get_combined_minimum_size().y * 0.5 - float(_tool_surface.get_meta("title_border_offset", 0)))
	_tool_surface.position = area.get_center() - (_tool_surface.size - Vector2(0, headroom)) * pixel * 0.5


func _tool_action(body: Container, title: String, action: Callable, primary := false) -> Button:
	var button := _button(body, title, 0, 0, 230, 48, action, primary)
	MODAL.village_button(button, primary)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.custom_minimum_size = Vector2(230, 48)
	button.tooltip_text = title
	return button


func _tool_copy(body: VBoxContainer, text: String, font_size := 19) -> Label:
	var copy := _label(body, text, 0, 0, 0, 0, font_size, RURAL.INK)
	copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return copy


func _render_tool() -> void:
	_block_board_focus(true)
	match _tool_open:
		"notice":
			var body := _tool_panel(_notice_title, 320)
			var copy := _tool_copy(body, _notice_message, 21)
			copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var acknowledge := _tool_action(body, "知道了", _close_tool, true)
			acknowledge.name = "MahjongNoticeConfirm"
			acknowledge.grab_focus()
		"rules":
			var body := _tool_panel("本桌规则", 466)
			_tool_copy(body, _rule_name(), 24)
			_tool_copy(body, _rule_text(), 20)
			var version := str(_state.get("rule_version",match_context.get("rule_version","")))
			_tool_copy(body, "本地练习" if training_mode else ("规则版本 " + version if not version.is_empty() else "以本桌结算为准"), 17)
		"settings": _settings_panel()
		"chat": _social_panel()
		"moderation": _moderation_panel()
		"gang": _gang_panel()
		"leave": _leave_panel()


func _rule_text() -> String:
	if training_mode:
		return "本地摸打使用 108 张牌。选中手牌，再点一次或点击「打出」。\n只练习自己的摸牌和弃牌，其余三家保留起手牌。\n牌墙摸空后，再弃一张牌，即可开始下一局。"
	var rule := _table_rule()
	var options: Dictionary = rule.get("options", {})
	var turn_seconds := int(_state.get("turn_timeout_seconds", _state.get("action_timeout_seconds", 15)))
	if _is_dingque_table():
		var chicken := "胡后计幺鸡和翻鸡。" if options.get("chicken") == true else "本桌不计鸡分。"
		var rob_kong := "可抢补杠胡。" if options.get("rob_kong") == true else "本桌关闭抢杠胡。"
		return "四人，万、筒、条共 108 张，不吃牌。\n开局各选一门定缺，四家选齐后公开。\n手中有缺门牌时须先打出，且缺门牌不能碰、杠、胡。\n自摸、接炮均无需先杠，可一炮多响。%s\n牌墙摸完无人胡则查叫，流局不结鸡分。\n%s出牌时限 %d 秒。" % [rob_kong, chicken, turn_seconds]
	var requires_kong := _requires_kong_to_claim()
	var claim := "接炮须本人已完成明杠、暗杠或补杠。" if requires_kong else "无杠也可接炮胡。"
	var rob := "抢补杠胡同样须先杠。" if requires_kong else "可抢补杠胡。"
	if not bool(options.get("rob_kong",true)): rob = "本桌关闭抢杠胡。"
	var hu_line := claim + "自摸无需先杠。" + rob
	var ji_line := "本桌不计鸡分。"
	if bool(rule.get("chicken", true)):
		var items := PackedStringArray(["翻鸡", "幺鸡"])
		if bool(options.get("black_eight", true)): items.append("黑八")
		if bool(options.get("charge_chicken", true)): items.append("冲锋鸡与责任鸡")
		ji_line = "本桌计入" + "、".join(items) + "。"
	if _state.get("rule_set_id", match_context.get("rule_set_id")) == "guiyang" and str(_state.get("rule_version", match_context.get("rule_version", ""))) == "3.0.0":
		return "四人，万、筒、条共 108 张，不吃牌。\n%s\n本人回合须打出或按规则杠牌、自摸。过仅放弃响应。\n按牌型计番，可一炮多响，同巡过胡、过碰受到限制。\n黄庄查叫；热炮、抢杠和黄庄撤销本局鸡分与杠分。\n首局随机庄，赢家接庄，流局留庄。\n%s 出牌时限 %d 秒。" % [hu_line, ji_line, turn_seconds]
	return "四人，万、筒、条共 108 张。\n庄家 14 张，其余 13 张，不吃牌。\n自己的回合须打出一张牌，也可按规则杠牌或自摸。\n「过」仅放弃他人出牌或补杠时的响应。碰后须出牌，杠后补牌。\n%s\n支持平胡与七对，确认胡牌后结算，牌墙耗尽且无人胡则流局。\n%s\n出牌时限 %d 秒，超时自动出牌。" % [hu_line,ji_line,turn_seconds]


func _settings_panel() -> void:
	var dim := ColorRect.new()
	dim.name = "MahjongToolDim"
	dim.color = Color("#21160eb0")
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.z_index = 2
	_overlay_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_view = SETTINGS.new()
	_settings_view.z_index = 2
	_overlay_root.add_child(_settings_view)
	var selector: OptionButton = product_audio.make_callout_selector() if is_instance_valid(product_audio) else null
	_settings_view.setup(_close_tool, _toggle_music, _toggle_sound, _choose_quality, selector, _set_coach_enabled)
	_fit_settings()
	_sync_settings()


func _settings_open() -> bool:
	return _tool_open == "settings" and is_instance_valid(_settings_view) and _settings_view.is_inside_tree()


func _fit_settings() -> void:
	var area := _usable_modal_area()
	var pixel := _modal_pixel_scale()
	_settings_view.scale = Vector2.ONE * pixel
	_settings_view.fit(Rect2(Vector2.ZERO, area.size / pixel))
	_settings_view.position = area.position + _settings_view.position * pixel


func _sync_settings() -> void:
	if not _settings_open(): return
	var voice_index := AUDIO.VOICE_IDS.find(product_audio.callout_voice) if is_instance_valid(product_audio) else -1
	_settings_view.sync(_music_enabled, _sound_enabled, _quality, voice_index, _rule_name() + " · 本桌规则\n\n" + _rule_text(), _coach_enabled)
	var notice := "正在更新观战权限" if _spectator_permission_pending != null else _spectator_permission_notice
	_settings_view.sync_spectator_permission(not _is_spectating() and bool(_state.get("allow_spectators", false)),
		bool(_state.get("spectator_allowed", false)), bool(_state.get("spectator_occupied", false)),
		_actions_ready() and _spectator_permission_pending == null, notice, _set_spectator_permission)


func _set_spectator_permission(enabled: bool) -> void:
	if not _actions_ready() or not _state.get("allow_spectators", false) or _spectator_permission_pending != null:
		_sync_settings()
		return
	_spectator_permission_pending = enabled
	_spectator_permission_notice = ""
	_send({"type": "mahjong_spectator_permission", "room_id": str(_state.get("room_id", "")), "enabled": enabled})
	if _last_send_error != OK:
		_spectator_permission_pending = null
		_spectator_permission_notice = "发送失败，请重试"
	_sync_settings()


func _set_coach_enabled(enabled: bool) -> void:
	_coach_enabled = enabled
	_save_preferences()
	_layout_coach()
	_sync_settings()


func _choose_quality(index: int) -> void:
	_set_quality(index)


func _toggle_music(enabled: Variant = null) -> void:
	if is_instance_valid(product_audio):
		product_audio.set_music_enabled(not _music_enabled if enabled == null else bool(enabled))


func _toggle_sound(enabled: Variant = null) -> void:
	if is_instance_valid(product_audio):
		product_audio.set_effects_enabled(not _sound_enabled if enabled == null else bool(enabled))


func _gang_panel() -> void:
	var options := _legal_options("gang")
	var body := _tool_panel("选择要杠的牌", minf(640, 150 + options.size() * 58))
	for index in range(options.size()):
		var option: Dictionary = options[index]
		var tile_id := int(option.get("tile_id", 0))
		var title := _action_name(str(option.get("type", "")))
		for tile in _array("hand"):
			if int(tile.get("id", 0)) == tile_id:
				title += " · " + _tile_title(tile)
				break
		var button := _tool_action(body, title, _send_action.bind(str(option.get("type", "")), tile_id, _action_snapshot_key()), true)
		button.name = "MahjongGangChoice%d" % index
		button.disabled = _pending_action or not _actions_ready()
	if options.is_empty(): _tool_copy(body, "杠牌选项已更新，请关闭后继续对局")


func _social_panel() -> void:
	var body := _tool_panel("牌桌聊天", 655)
	_tool_copy(body, "表情", 18)
	var emotes := HFlowContainer.new()
	emotes.alignment = FlowContainer.ALIGNMENT_CENTER
	body.add_child(emotes)
	for index in EMOTE_IDS.size():
		var button := _tool_action(emotes, EMOTE_TEXTS[index], _send_social_choice.bind("emote", "emote", EMOTE_IDS[index]))
		button.name = "MahjongSocialChoice_" + EMOTE_IDS[index]
		button.custom_minimum_size = Vector2(84, 48)
	_tool_copy(body, "快捷语", 18)
	for index in CHAT_IDS.size():
		var button := _tool_action(body, CHAT_TEXTS[index], _send_social_choice.bind("chat", "quick_chat", CHAT_IDS[index]))
		button.name = "MahjongSocialChoice_" + CHAT_IDS[index]
	_tool_copy(body, "训练互动仅在本机显示" if training_mode else "所有牌友均可见 · 每秒一次", 16)
	_refresh_social_choices()


func _refresh_social_choices() -> void:
	var disabled := not _actions_ready() or (not training_mode and str(_state.get("status", "waiting")) == "waiting")
	for button: Button in _tool_surface.find_children("MahjongSocialChoice_*", "Button", true, false):
		button.disabled = disabled


func _seat_account(seat: int) -> String:
	var players := _array("players")
	return str(players[seat]) if seat >= 0 and seat < players.size() else ""


func _can_moderate(seat: int) -> bool:
	if _is_spectating(): return false
	var own_seat := int(_state.get("your_seat", -1))
	return own_seat >= 0 and seat != own_seat and not _is_practice_table() and not _seat_account(seat).is_empty()


func _seat_muted(seat: int) -> bool:
	return _muted_accounts.has(_seat_account(seat))


func _open_moderation(seat: int) -> void:
	if not _can_moderate(seat):
		return
	var account := _seat_account(seat)
	if _moderation_account != account:
		_report_notice = ""
		_report_reason = -1
	_moderation_seat = seat
	_moderation_account = account
	_open_tool("moderation")


func _moderation_panel() -> void:
	var body := _tool_panel("%d 号位 · 牌友管理" % (_moderation_seat + 1), 440)
	var valid := _can_moderate(_moderation_seat) and _seat_account(_moderation_seat) == _moderation_account
	var mute := _tool_action(body, "取消静音" if _seat_muted(_moderation_seat) else "静音此牌友", _toggle_moderation_mute)
	mute.name = "MahjongModerationMute"
	mute.disabled = not valid
	_tool_copy(body, "静音仅本桌生效，屏蔽该牌友的聊天、表情和语音。")
	var reasons := OptionButton.new()
	reasons.name = "MahjongReportReason"
	body.add_child(reasons)
	reasons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	reasons.custom_minimum_size = Vector2(230, 48)
	reasons.fit_to_longest_item = false
	RURAL.skin_button(reasons)
	for caption in ["不当聊天", "刷屏", "语音滥用", "其他"]:
		reasons.add_item(caption)
	reasons.select(_report_reason)
	if _report_reason < 0:
		reasons.text = "选择举报原因"
	var submit := _tool_action(body, "提交举报", _submit_report, true)
	submit.name = "MahjongReportSubmit"
	var available := valid and _can_report()
	reasons.disabled = not available
	submit.disabled = not available or _report_reason < 0
	reasons.item_selected.connect(func(index: int) -> void:
		_report_reason = index
		submit.disabled = not _can_report())
	var notice := _report_notice
	if not valid: notice = "这个座位的牌友已变更"
	elif notice.is_empty() and not _can_report(): notice = "恢复连接并同步本局后可举报"
	var feedback := _tool_copy(body, notice)
	feedback.name = "MahjongReportFeedback"
	_tool_copy(body, "举报仅发送所选原因。麦克风仅在按住说话时录音，松开即停止。", 17)


func _toggle_moderation_mute() -> void:
	if _seat_account(_moderation_seat) != _moderation_account:
		return
	_toggle_seat_mute(_moderation_seat)


func _can_report() -> bool:
	return (_can_moderate(_moderation_seat) and _seat_account(_moderation_seat) == _moderation_account
		and _actions_ready() and str(_state.get("status", "")) in ["playing", "finished"]
		and not str(_state.get("match_id", "")).is_empty() and _report_command.is_empty())


func _submit_report() -> void:
	if not _can_report() or _report_reason < 0 or _report_reason >= REPORT_REASONS.size():
		return
	_report_match = str(_state["match_id"])
	_report_target = _moderation_account
	_report_command = "report-%s-%d" % [_command_prefix, Time.get_ticks_usec()]
	var failure := _wire_send({"type": "mahjong_report", "target_seat": _moderation_seat,
		"reason": REPORT_REASONS[_report_reason], "match_id": _report_match, "command_id": _report_command})
	if failure == OK:
		_report_notice = "举报已发送，等待服务器确认"
		_report_timeout.start(7.0)
	else:
		_reset_report_request()
		_report_notice = "举报发送失败，请重试"
	_refresh_moderation_tool()


func _accept_report_result(packet: Dictionary) -> void:
	if (_report_command.is_empty() or str(packet.get("command_id", "")) != _report_command
			or _report_match != str(_state.get("match_id", ""))):
		return
	var notice := str(packet.get("message", "")).strip_edges()
	if notice.is_empty():
		notice = "举报已提交" if bool(packet.get("ok", false)) else "未能提交举报，请重试"
	_finish_report(notice, bool(packet.get("ok", false)))


func _on_report_timeout() -> void:
	_finish_report("暂未收到举报确认，可重新提交", false)


func _finish_report(notice: String, succeeded: bool) -> void:
	var same_target := _report_target == _moderation_account
	_reset_report_request()
	if same_target:
		_report_notice = notice
		if succeeded: _report_reason = -1
	if is_instance_valid(_status):
		_status.text = notice
	_refresh_moderation_tool()


func _reset_report_request() -> void:
	if is_instance_valid(_report_timeout): _report_timeout.stop()
	_report_command = ""
	_report_match = ""
	_report_target = ""


func _refresh_moderation_tool() -> void:
	if _tool_open == "moderation" and is_instance_valid(_overlay_root):
		_clear(_overlay_root)
		_render_tool()


func _send_social_choice(action: String, field: String, value: String) -> void:
	var payload := {"type":"mahjong_social", "action":action}
	payload[field] = value
	_submit_social(payload)


func _submit_social(payload: Dictionary) -> bool:
	if not _require_actions_ready(): return false
	if Time.get_ticks_msec() - _last_social_send < 1000:
		_status.text = "稍等一秒再互动"
		return false
	if training_mode:
		var action := str(payload.get("action", ""))
		var ids := CHAT_IDS if action == "chat" else EMOTE_IDS
		var texts := CHAT_TEXTS if action == "chat" else EMOTE_TEXTS
		var index := ids.find(str(payload.get("quick_chat" if action == "chat" else "emote", "")))
		if index < 0: return false
		_social_events[0] = {"text":"训练 · " + texts[index], "until":Time.get_ticks_msec() + 4500}
		_last_social_send = Time.get_ticks_msec()
		_close_tool()
		_render_bubbles()
		_schedule_bubble_expiry()
		_status.text = "训练互动仅在本机显示"
		return true
	if _room_kind()=="training":
		_status.text = "训练房专注人机对局"
		return false
	if str(_state.get("status", "waiting")) == "waiting":
		_status.text = "四位牌友开局后可互动"
		return false
	payload["message_id"] = "%d_%d" % [get_instance_id(), Time.get_ticks_usec()]
	var match_id := str(_state.get("match_id", ""))
	if not match_id.is_empty(): payload["match_id"] = match_id
	_send(payload)
	if _last_send_error != OK: return false
	_last_social_send = Time.get_ticks_msec()
	_close_tool()
	_status.text = "互动已提交 · 等待牌桌确认"
	return true


func _voice_down() -> void:
	if _recording or _is_practice_table(): return
	if not _require_actions_ready() or str(_state.get("status", "waiting")) == "waiting": return
	if not is_instance_valid(_voice):
		_status.text = "语音尚未就绪"
		return
	if _voice.start_recording() != OK:
		_status.text = _voice.last_error
		return
	_recording = true
	_voice_deadline.start(5.0)
	_show_recording(true)
	_status.text = "正在录音 · 松开发送 · 最长 5 秒"


func _voice_up() -> void:
	if not _recording: return
	_recording = false
	_voice_deadline.stop()
	_show_recording(false)
	var payload: Dictionary = _voice.stop_recording()
	if payload.is_empty():
		_status.text = _voice.last_error
		return
	payload["type"] = "mahjong_social"
	payload["action"] = "voice"
	if _submit_social(payload): _status.text = "语音已提交 · 等待牌桌确认"


func _stop_recording() -> void:
	if is_instance_valid(_voice_deadline): _voice_deadline.stop()
	if _recording and is_instance_valid(_voice): _voice.stop_recording()
	_recording = false
	_show_recording(false)


func _toggle_seat_mute(seat: int) -> void:
	if not _can_moderate(seat): return
	var account := _seat_account(seat)
	var muted := not _muted_accounts.has(account)
	if muted:
		_muted_accounts[account] = true
		_social_events.erase(seat)
		_render_bubbles()
		_schedule_bubble_expiry()
	else:
		_muted_accounts.erase(account)
	var mic: Button = _seat_voice_buttons.get(seat)
	if is_instance_valid(mic):
		mic.icon = BATTLE_ART.icon("muted" if muted else "mic")
		mic.tooltip_text = "取消静音（本桌）" if muted else "静音此牌友的聊天、表情与语音"
	_status.text = "%d 号位互动已%s（仅本桌）" % [seat + 1, "静音" if muted else "恢复"]
	if account == _playing_voice_account: _apply_audio()
	_refresh_moderation_tool()


func _receive_social(event: Dictionary) -> void:
	if not _joined or not _snapshot_ready or str(event.get("room_id", "")) != str(_state.get("room_id", "")): return
	var match_id := str(event.get("match_id", ""))
	if not match_id.is_empty() and match_id != str(_state.get("match_id", "")): return
	var seat := int(event.get("seat", -1))
	if seat < 0 or seat > 3: return
	var nonce := str(event.get("message_id", ""))
	if not nonce.is_empty():
		var message_key := JSON.stringify([str(event.get("room_id", "")), seat, nonce])
		if _seen_social.has(message_key): return
		_seen_social[message_key] = true
		if _seen_social.size() > 128: _seen_social.erase(_seen_social.keys()[0])
	if _seat_muted(seat): return
	var text := ""
	match str(event.get("action", "")):
		"chat": text = str(event.get("text", ""))
		"emote":
			var index := EMOTE_IDS.find(str(event.get("emote", "")))
			if index >= 0: text = EMOTE_TEXTS[index]
		"voice":
			text = "语音 %.1f 秒" % (float(event.get("duration_ms", 0)) / 1000.0)
			if seat == int(_state.get("your_seat", -1)):
				_status.text = "语音已送达牌桌 · " + text
			elif not _sound_enabled:
				text += "（已静音）"
				_status.text = "收到牌友语音，当前“牌声与语音”已关闭，可在设置中开启"
			elif is_instance_valid(_voice):
				_playing_voice_account = _seat_account(seat)
				_voice.set_playback_enabled(true)
				if _voice.play(event) != OK:
					text = "语音播放失败"
					_status.text = _voice.last_error
	if text.is_empty(): return
	_social_events[seat] = {"text":text, "until":Time.get_ticks_msec() + 4500}
	_render_bubbles()
	_schedule_bubble_expiry()


func _schedule_bubble_expiry() -> void:
	_bubble_deadline.stop()
	var next := -1
	for bubble in _social_events.values():
		var until := int(bubble.get("until",0))
		if next<0 or until<next: next = until
	if next>=0:
		_bubble_deadline.start(maxf(0.01,float(next-Time.get_ticks_msec())/1000.0))


func _expire_bubbles() -> void:
	var now := Time.get_ticks_msec()
	for seat in _social_events.keys():
		if int(_social_events[seat].get("until",0))<=now: _social_events.erase(seat)
	_render_bubbles()
	_schedule_bubble_expiry()


func _render_bubbles() -> void:
	if not is_instance_valid(_social_root): return
	_clear(_social_root)
	for seat in _social_events:
		var relative := _relative_seat(int(seat))
		var rect := _seat_panels[relative].get_rect() if relative < _seat_panels.size() and is_instance_valid(_seat_panels[relative]) else _seat_rect(relative)
		var box := Panel.new()
		box.name = "MahjongSocialSeat%d" % int(seat)
		var bubble_x := rect.position.x if relative != 1 else rect.end.x - 280
		box.size = Vector2(280, 52)
		var bubble_y := rect.end.y + 32.0
		if relative == 0:
			if rect.end.x + 8.0 + box.size.x <= _seat_rect(2).position.x:
				bubble_x = rect.end.x + 8.0
				bubble_y = rect.position.y
			else:
				bubble_y = _status.get_rect().end.y + 4.0
		box.position = Vector2(clampf(bubble_x, 8, size.x - 288), bubble_y)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_stylebox_override("panel", _style(Color("#fff5deef"), Color("#b39c61"), 16))
		_social_root.add_child(box)
		_label(box, str(_social_events[seat].get("text", "")), 8, 3, 264, 46, 17, Color("#3d4b34"))


func _request_leave() -> void:
	_open_tool("leave")


func _leave_panel() -> void:
	var dim := ColorRect.new()
	dim.name = "MahjongToolDim"
	dim.color = Color("#21160e99")
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.z_index = 2
	_overlay_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := MODAL.village_panel(_overlay_root, Vector4(24, 24, 24, 27))
	panel.name = "MahjongToolPanel_leave"
	panel.z_index = 2
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	panel.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var balance := Control.new()
	balance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(balance)
	var title_area := CenterContainer.new()
	title_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_area)
	var title := MODAL.village_title(title_area, "结束观战？" if _is_spectating() else "离开牌桌？", panel)
	title.get_parent().name = "MahjongLeaveTitlePlate"
	title.name = "MahjongLeaveHeading"
	title.clip_text = true
	var close := Button.new()
	close.name = "MahjongLeaveCloseButton"
	close.tooltip_text = "关闭"
	close.accessibility_name = "关闭离桌确认"
	MODAL.icon_button(close, MODAL.icon("close"), "关闭离桌确认")
	header.add_child(close)
	close.pressed.connect(_close_tool)
	var message := "离开后对局继续，超时将自动托管。\n可从大厅返回原牌桌。"
	var destination := str(match_context.get("return_destination", "大厅"))
	if training_mode or _is_spectating(): message = "离开后返回%s。" % destination
	elif _room_kind()=="training": message = "离开将结束本次人机训练并返回%s。" % destination
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var copy := Label.new()
	copy.name = "MahjongLeaveText"
	copy.text = message
	copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	copy.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.size_flags_vertical = Control.SIZE_EXPAND_FILL
	copy.add_theme_color_override("font_color", MODAL.INK)
	copy.add_theme_font_override("font", MODAL.village_font())
	scroll.add_child(copy)
	var actions := HFlowContainer.new()
	actions.alignment = FlowContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("h_separation", 12)
	actions.add_theme_constant_override("v_separation", 8)
	content.add_child(actions)
	var stay := Button.new()
	stay.name = "MahjongLeaveStayButton"
	stay.text = "继续观战" if _is_spectating() else "继续打牌"
	var confirm := Button.new()
	confirm.name = "MahjongLeaveConfirm"
	confirm.text = "结束观战" if _is_spectating() else "离开牌桌"
	for button in [stay, confirm]:
		actions.add_child(button)
		MODAL.village_button(button, button == stay)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stay.pressed.connect(_close_tool)
	confirm.pressed.connect(_return_now)
	stay.grab_focus()
	panel.minimum_size_changed.connect(_fit_leave_panel.bind(panel), CONNECT_DEFERRED)
	_fit_leave_panel.call_deferred(panel)
	_fit_leave_panel(panel)


func _fit_leave_panel(panel: Control) -> void:
	if not is_instance_valid(panel) or not panel.is_inside_tree(): return
	var area := _usable_modal_area()
	var pixel := _modal_pixel_scale()
	var width := minf(1280, area.size.x / pixel * 0.89)
	var height := minf(clampf(width * 0.55, 240.0, 645.0), area.size.y / pixel - 36.0)
	var compact := width < 660.0 or height < 380.0
	var heading := panel.find_child("MahjongLeaveHeading", true, false) as Label
	heading.add_theme_font_size_override("font_size", 27 if compact else 52)
	var plate := heading.get_parent() as Control
	plate.custom_minimum_size = Vector2(minf(width * 0.5, 620.0), 61 if compact else 100)
	var copy := panel.find_child("MahjongLeaveText", true, false) as Label
	copy.add_theme_font_size_override("font_size", 21 if compact else 36)
	for name in ["MahjongLeaveStayButton", "MahjongLeaveConfirm"]:
		var action := panel.find_child(name, true, false) as Button
		action.custom_minimum_size = Vector2(128 if compact else 230, maxf(RURAL.touch_extent(self) / pixel, 48 if compact else 62))
		action.add_theme_font_size_override("font_size", 21 if compact else 30)
	panel.scale = Vector2.ONE * pixel
	var close := panel.find_child("MahjongLeaveCloseButton", true, false) as Button
	var header := close.get_parent()
	(header.get_child(0) as Control).custom_minimum_size.x = MODAL.size_icon_button(close, close)
	panel.size = Vector2(width, height)
	var headroom := maxf(0.0, plate.custom_minimum_size.y * 0.5 - float(panel.get_meta("title_border_offset", 0)))
	panel.position = area.get_center() - (panel.size - Vector2(0, headroom)) * pixel * 0.5


func finished_friend_match_id() -> String:
	if _room_kind() == "friend" and str(_state.get("phase", "")) == "finished" and bool(_state.get("can_rematch", false)):
		return str(_state.get("match_id", ""))
	return ""


func _return_now(keep_room: bool = false) -> void:
	if keep_room and finished_friend_match_id().is_empty(): return
	_exit_board(request_next_round if keep_room else request_return_to_lobby)


func _return_to_finished_room() -> void:
	if not finished_friend_match_id().is_empty():
		_exit_board(request_return_to_room)


func _exit_board(destination: Signal) -> void:
	if _exiting: return
	_exiting = true
	_reset_report_request()
	_joined = false
	_snapshot_ready = false
	_stop_recording()
	_stop_audio()
	_stop_clock()
	if is_instance_valid(_transport): _transport.stop()
	_refresh_connection_actions()
	destination.emit()


func _fit_settlement() -> void:
	var area := _usable_modal_area()
	var pixel := _modal_pixel_scale()
	if is_instance_valid(_settlement_reopen) and _settlement_reopen.is_inside_tree():
		_settlement_reopen.custom_minimum_size = Vector2(158, 48) * pixel
		_settlement_reopen.size = _settlement_reopen.custom_minimum_size
		_settlement_reopen.add_theme_font_size_override("font_size", roundi(19.0 * pixel))
		_settlement_reopen.position = Vector2(area.get_center().x - _settlement_reopen.size.x * 0.5, area.end.y - 66.0 * pixel)
	if not is_instance_valid(_settlement_panel) or not _settlement_panel.is_inside_tree(): return
	var physical := area.size / pixel
	var compact := physical.x < 960 or physical.y < 540
	var width := minf(1590.0, physical.x * (0.97 if compact else 0.95))
	if not compact and physical.x > physical.y:
		width = minf(width,maxf(physical.y * 1.48,physical.x * 0.81))
	var height := minf(970.0, physical.y * (0.96 if compact else 0.89))
	_settlement_panel.scale = Vector2.ONE * pixel
	_settlement_panel.size = Vector2(width, height)
	var spare := area.size - _settlement_panel.size * pixel
	_settlement_panel.position = area.position + spare * Vector2(0.5,0.5 if compact else 0.75)


func _render_settlement_overlay() -> void:
	if _is_spectating(): return
	if not _settlement_dismissed:
		_render_settlement()
		return
	_block_board_focus(false)
	_settlement_reopen = _button(_overlay_root, "本局结算", 0, 0, 172, 52, _reopen_settlement)
	_settlement_reopen.name = "MahjongSettlementReopenButton"
	_fit_settlement()


func _dismiss_settlement() -> void:
	_settlement_dismissed = true
	_clear(_overlay_root)
	_settlement_panel = null
	_render_settlement_overlay()
	_settlement_reopen.grab_focus()


func _reopen_settlement() -> void:
	_settlement_dismissed = false
	_clear(_overlay_root)
	_settlement_reopen = null
	_render_settlement_overlay()


func _settlement_tiles(seat: int, own_seat: int) -> Array:
	var hands := _array("settlement_hands")
	var concealed: Variant = hands[seat] if seat < hands.size() else _state.get("hand") if seat == own_seat else null
	if not concealed is Array: return []
	var tiles := []
	var melds := _array("melds")
	var group := 0
	if seat < melds.size() and melds[seat] is Array:
		for meld in melds[seat]:
			if not meld is Dictionary or not meld.get("tiles") is Array: continue
			for tile in meld.tiles:
				if tile is Dictionary and DINGQUE_SUITS.has(tile.get("suit")) and _option_integer(tile.get("rank")) in range(1,10):
					tiles.append({"suit":tile.suit,"rank":int(tile.rank),"group":group})
				elif meld.get("kind") == "an_gang":
					tiles.append({"concealed":true,"group":group})
			group += 1
	for tile in concealed:
		if tile is Dictionary and DINGQUE_SUITS.has(tile.get("suit")) and _option_integer(tile.get("rank")) in range(1,10):
			tiles.append({"suit":tile.suit,"rank":int(tile.rank),"group":group})
	return tiles


func _render_settlement() -> void:
	_block_board_focus(true)
	var dim := ColorRect.new()
	dim.name = "MahjongSettlementDim"
	var blur := ShaderMaterial.new()
	blur.shader = preload("res://modules/games/mahjong/guiyang/settlement_backdrop.gdshader")
	dim.material = blur
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_root.add_child(dim)
	var panel := SETTLEMENT.new()
	var winners := _array("winners").map(func(value): return int(value))
	var own_seat := int(_state.get("your_seat", -1))
	var outcome := "draw" if winners.is_empty() else "win" if winners.has(own_seat) else "loss"
	var win_kind := str(_state.get("win_kind", ""))
	var hu_details := {}
	for detail in _array("hu_details"):
		if detail is Dictionary: hu_details[int(detail.get("seat", -1))] = detail
	var method_names := {"zi_mo":"自摸", "dian_pao":"胡牌", "gang_shang_hua":"杠上花", "re_pao":"热炮", "qiang_gang":"抢杠胡", "cha_jiao":"查叫"}
	var outcome_title := "流局"
	if not winners.is_empty():
		var first: Dictionary = hu_details.get(winners[0], {})
		outcome_title = str(method_names.get(first.get("kind", win_kind), "胡牌"))
	var summary := "牌墙已摸完" if winners.is_empty() else "胡牌座位 · " + "、".join(winners.map(func(seat): return "%d 号位" % (seat + 1)))
	var robbed_tile: Variant = _state.get("robbed_tile")
	if win_kind == "qiang_gang" and not winners.is_empty() and robbed_tile is Dictionary:
		if robbed_tile.get("suit") in ["wan", "tong", "tiao"] and _option_integer(robbed_tile.get("rank")) in range(1, 10):
			summary += " · 抢杠牌 " + _tile_title(robbed_tile)
	if winners.is_empty() and _is_dingque_table(): summary = "查叫结算"
	if winners.is_empty() and _state.has("ready_seats"): summary = "黄庄查叫"
	var version := str(_state.get("rule_version", match_context.get("rule_version", "")))
	var room_id := str(_state.get("room_id", match_context.get("room_id", "")))
	var room := "%s · 房间 %s" % [_rule_name(), room_id]
	var round_caption := "房间%s  ·  本局结算" % room_id
	if not version.is_empty(): room += " · 规则 " + version
	var round_limit := int(_state.get("round_limit", match_context.get("round_limit", 0)))
	if _room_kind() == "friend" and round_limit > 0:
		var completed := int(_state.get("completed_rounds", match_context.get("completed_rounds", 0)))
		room += " · %d/%d 局" % [clampi(completed + 1, 1, round_limit), round_limit]
		round_caption = "房间%s  ·  第 %d 局结算" % [room_id,clampi(completed+1,1,round_limit)]
	var series_rounds := int(_state.get("series_rounds", 0))
	var series_scores := _array("series_scores")
	var series_ranks := _array("series_ranks")
	if series_rounds > 0 and series_scores.size() == 4 and series_ranks.size() == 4:
		var total_rounds := int(_state.get("series_total_rounds", series_rounds))
		room += " · 累计 %d/%d 局" % [series_rounds, total_rounds]
	var data := {"room":room, "summary":summary, "outcome":outcome, "outcome_title":outcome_title, "rows":[], "rematch":not finished_friend_match_id().is_empty()}
	data["round_caption"] = round_caption
	data["return_caption"] = "返回" + str(match_context.get("return_destination", "大厅"))
	var indicator: Variant = _state.get("flipped_ji", {})
	if indicator is Dictionary and str(indicator.get("suit", "")) in ["wan", "tong", "tiao"] and int(indicator.get("rank",0)) in range(1, 10):
		data["indicator"] = _texture(_tile_path(indicator))
		data["indicator_title"] = _tile_title(indicator)
	var scores := _array("scores")
	var players := _array("players")
	var chicken := _array("ji_counts")
	var egg_deltas := _array("egg_deltas")
	var egg_counts := _array("egg_counts")
	var fan_by_seat := {}
	for fan in _array("fan_breakdown"):
		if fan is Dictionary and fan.get("items") is Array and _option_integer(fan.get("total")) >= 0:
			fan_by_seat[_option_integer(fan.get("seat"))] = fan
	var player_names := _array("player_names")
	var breakdown: Variant = _state.get("score_breakdown")
	var win_from := int(_state.get("win_from", -1))
	var seats := range(mini(4, scores.size()))
	if own_seat in seats:
		seats.erase(own_seat)
		seats.push_front(own_seat)
	for seat: int in seats:
		var name_value := "%d 号位" % (seat + 1)
		if seat < player_names.size() and player_names[seat] is String and not str(player_names[seat]).is_empty(): name_value = str(player_names[seat])
		if seat == own_seat: name_value = "%s（我）" % str(match_context.get("display_name", name_value))
		elif _room_kind()=="training": name_value += " · 电脑牌友"
		elif seat >= player_names.size() and seat < players.size(): name_value += " · 牌友"
		var seat_result := "流局" if winners.is_empty() else "未胡"
		if winners.has(seat): seat_result = str(method_names.get(win_kind, "胡牌"))
		elif not winners.is_empty() and seat == win_from: seat_result = "被抢杠" if win_kind == "qiang_gang" else "点炮"
		var win_method := seat_result
		if hu_details.has(seat):
			var detail: Dictionary = hu_details[seat]
			var method := str(method_names.get(detail.get("kind"), seat_result))
			win_method = method
			seat_result = "%s · %s %d 番" % [method, str(detail.get("pattern", "")), int(detail.get("fan", 0))]
		if seat < chicken.size() and int(chicken[seat]) > 0: seat_result += " · 鸡值 %d" % int(chicken[seat])
		var row := {"seat":seat, "name":name_value, "score":int(scores[seat]), "result":seat_result, "own":seat == own_seat}
		row["relative"] = _relative_seat(seat)
		row["winner"] = winners.has(seat)
		row["method"] = win_method
		row["status"] = "胡牌" if row.winner else "闲家" if win_method == "未胡" else win_method
		row["tiles"] = _settlement_tiles(seat, own_seat)
		if seat < egg_counts.size() and _option_integer(egg_counts[seat]) >= 0:
			row["balance"] = int(egg_counts[seat])
		if fan_by_seat.has(seat):
			var fan: Dictionary = fan_by_seat[seat]
			var items := []
			for item in fan.items:
				if item is Dictionary and item.get("name") is String and _option_integer(item.get("fan")) >= 0:
					items.append({"name":item.name,"fan":int(item.fan)})
			if not items.is_empty():
				row["fan_items"] = items
				row["fan_total"] = int(fan.total)
		if not row.has("fan_total") and hu_details.has(seat):
			var hu: Dictionary = hu_details[seat]
			if _option_integer(hu.get("fan")) >= 0:
				row["fan_total"] = int(hu.fan)
				row["fan_items"] = [{"name":"%s · %s" % [str(hu.get("pattern","胡牌")), win_method],"fan":int(hu.fan)}]
		if series_rounds > 0 and series_scores.size() == 4 and series_ranks.size() == 4:
			row["series"] = "累计 %+d 分 · 第 %d 名" % [int(series_scores[seat]), int(series_ranks[seat])]
		row["counts_eggs"] = not training_mode and _room_kind() != "training"
		if seat < egg_deltas.size() and (egg_deltas[seat] is int or egg_deltas[seat] is float) and is_finite(float(egg_deltas[seat])) and float(egg_deltas[seat]) == floorf(float(egg_deltas[seat])):
			row["egg_delta"] = int(egg_deltas[seat])
		if breakdown is Dictionary:
			var hu: Variant = breakdown.get("hu")
			var gang: Variant = breakdown.get("gang")
			var ji: Variant = breakdown.get("ji")
			if hu is Array and hu.size() == 4 and gang is Array and gang.size() == 4 and ji is Array and ji.size() == 4:
				row["details"] = "胡 %+d   杠 %+d   鸡 %+d" % [int(hu[seat]), int(gang[seat]), int(ji[seat])]
				row["score_items"] = [{"name":"胡牌","points":int(hu[seat])},{"name":"杠分","points":int(gang[seat])},{"name":"鸡分","points":int(ji[seat])}]
				var checked: Variant = breakdown.get("cha_jiao")
				if checked is Array and checked.size() == 4 and (_is_dingque_table() or _state.has("ready_seats")):
					row["details"] += "   查叫 %+d" % int(checked[seat])
					row.score_items.append({"name":"查叫","points":int(checked[seat])})
		data.rows.append(row)
	panel.setup(data, _return_now, _return_now.bind(true), _open_tool.bind("rules"), _dismiss_settlement, _return_to_finished_room, _tile_materials)
	_overlay_root.add_child(panel)
	_settlement_panel = panel
	_fit_settlement()
	var close := panel.find_child("MahjongSettlementCloseButton", true, false) as Button
	if is_instance_valid(close): close.grab_focus()
