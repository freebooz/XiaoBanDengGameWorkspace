extends "res://modules/game_framework/card3d/poker_screen.gd"
## 园林木桌斗地主。牌、座位、计时与结果来自服务器；外观和声音保存在本机。

const GARDEN := "res://modules/games/landlord/assets/ui/landlord_garden.png"
const OPPONENTS := "res://modules/games/landlord/assets/ui/landlord_opponents.png"
const WOOD := "res://modules/games/landlord/assets/ui/landlord_table_wood.png"
const VOICE = preload("res://modules/games/landlord/landlord_voice.gd")
const AUDIO := "res://modules/games/landlord/assets/audio/"
const CHAT_IDS := ["hello", "hurry", "well_played", "thanks", "good_game"]
const CHAT_TEXTS := ["大家好，很高兴一起玩！", "快点吧，我等到花儿都谢了！", "这手牌打得漂亮！", "谢谢！", "好牌，好局！"]
const EMOTE_IDS := ["smile", "laugh", "thumbs_up", "cry", "angry"]
const EMOTE_TEXTS := ["微笑", "大笑", "点赞", "流泪", "生气"]
const PROP_IDS := ["flower", "egg", "tomato", "cheers"]
const PROP_TEXTS := ["鲜花", "鸡蛋", "番茄", "干杯"]
const ACTION_COLORS := [Color("#bf3326"), Color("#266bc0"), Color("#6a7472"), Color("#d8a036"), Color("#238e54"), Color("#ce8427")]
const ACTION_ART := {
	"不抢":"res://modules/games/landlord/assets/ui/button_decline_bid.png",
	"不出":"res://modules/games/landlord/assets/ui/button_pass.png",
	"提示":"res://modules/games/landlord/assets/ui/button_hint.png",
	"出牌":"res://modules/games/landlord/assets/ui/button_play.png",
	"加倍 ×2":"res://modules/games/landlord/assets/ui/button_double.png",
}
const ACTION_ART_REGIONS := {
	"不抢":Rect2(359, 132, 1455, 477),
	"不出":Rect2(509, 174, 1154, 393),
	"提示":Rect2(291, 99, 1590, 516),
	"出牌":Rect2(322, 134, 1529, 458),
	"加倍 ×2":Rect2(450, 71, 1299, 561),
}

var preference_file := "user://landlord_preferences.cfg"
var history_file := "user://landlord_results.json"
var _music_enabled := true
var _sound_enabled := true
var _table_theme := "wood"
var _back_theme := "blue"
var _sort_mode := 0
var _hand_collapsed := false
var _tool_open := ""
var _history: Array = []
var _training_session := "%d_%d" % [int(Time.get_unix_time_from_system() * 1000), Time.get_ticks_usec()]
var _music: AudioStreamPlayer
var _sfx: AudioStreamPlayer
var _voice
var _recording := false
var _record_started := 0
var _last_social_send := -1000
var _social_events: Dictionary = {}
var _social_layer: Control
var _header_layer: Control
var _toolbar_layer: Control
var _brand: Label
var _clock_label: Label
var _clock_panel: Panel
var _status_backdrop: Panel
var _instruction_backdrop: Panel
var _sort_button: Button
var _collapse_button: Button
var _voice_button: Button
var _deadline_tick := 0
var _last_play_signature := ""
var _wood_material: StandardMaterial3D
var _felt_material: StandardMaterial3D
var _hand_sample_order: Array[int] = []
var _action_art_textures: Dictionary = {}


func _ready() -> void:
	_load_preferences()
	super._ready()
	_voice = VOICE.new()
	_voice.configure(self)
	_build_audio()
	_apply_audio()
	call_deferred("_apply_appearance")


func _exit_tree() -> void:
	if _recording and is_instance_valid(_voice): _voice.stop_recording()
	_stop_audio()
	super._exit_tree()


func _stop_audio() -> void:
	if is_instance_valid(_music):
		_music.stop()
		_music.stream = null
	if is_instance_valid(_sfx):
		_sfx.stop()
		_sfx.stream = null


func _load_preferences() -> void:
	var config := ConfigFile.new()
	if config.load(preference_file) == OK:
		_music_enabled = bool(config.get_value("sound", "music", true))
		_sound_enabled = bool(config.get_value("sound", "effects", true))
		_table_theme = str(config.get_value("appearance", "table", "wood"))
		_back_theme = str(config.get_value("appearance", "back", "blue"))
		_sort_mode = clampi(int(config.get_value("hand", "sort", 0)), 0, 1)
	if _table_theme not in ["wood", "jade"]: _table_theme = "wood"
	if _back_theme not in ["blue", "jade", "violet"]: _back_theme = "blue"
	if FileAccess.file_exists(history_file):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(history_file))
		if parsed is Array:
			for row in parsed:
				if row is Dictionary and row.has("key") and row.has("score"): _history.append(row)


func _save_preferences() -> void:
	var config := ConfigFile.new()
	config.set_value("sound", "music", _music_enabled)
	config.set_value("sound", "effects", _sound_enabled)
	config.set_value("appearance", "table", _table_theme)
	config.set_value("appearance", "back", _back_theme)
	config.set_value("hand", "sort", _sort_mode)
	config.save(preference_file)


func _build_audio() -> void:
	_music = AudioStreamPlayer.new()
	_music.stream = load(AUDIO + "garden_guzheng.mp3")
	_music.volume_db = -25
	if _music.stream is AudioStreamMP3: _music.stream.loop = true
	add_child(_music)
	_sfx = AudioStreamPlayer.new()
	_sfx.stream = load(AUDIO + "card_play.wav")
	_sfx.volume_db = -14
	add_child(_sfx)


func _apply_audio() -> void:
	if is_instance_valid(_music):
		if _music_enabled and not _music.playing: _music.play()
		elif not _music_enabled: _music.stop()
	if is_instance_valid(_voice): _voice.set_playback_enabled(_sound_enabled)
	if not _sound_enabled and is_instance_valid(_sfx): _sfx.stop()


func _play_sound() -> void:
	if _sound_enabled and is_instance_valid(_sfx): _sfx.play()


func _build_ui() -> void:
	var garden := TextureRect.new()
	garden.name = "GardenBackground"
	garden.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	garden.texture = load(GARDEN)
	garden.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	garden.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	garden.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(garden)
	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient := Shader.new()
	gradient.code = "shader_type canvas_item; void fragment(){float shade=.18+smoothstep(.48,1.0,UV.y)*.45;float top=1.0-smoothstep(0.0,.18,UV.y);COLOR=vec4(.025,.016,.011,max(shade,top*.62));}"
	var shade := ShaderMaterial.new()
	shade.shader = gradient
	veil.material = shade
	add_child(veil)
	_build_table()
	_camera.position = Vector3(0, 2.25, 1.35)
	_camera.look_at(Vector3(0, 0, 0.08), Vector3.UP)
	_camera.fov = 55
	_header_layer = _layer("LandlordHeader")
	_brand = _label(self, "小板凳斗地主", 22, 12, 315, 60, 36, Color("#ffe0a1"))
	_brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_brand.add_theme_color_override("font_outline_color", Color("#4a281b"))
	_brand.add_theme_constant_override("outline_size", 5)
	_label(self, "快乐一局 · 好友常在", 26, 72, 300, 27, 17, Color("#f4dec1"))
	_seat_layer = _layer("LandlordSeats")
	_toolbar_layer = _layer("LandlordTools")
	_action_layer = Control.new()
	_action_layer.name = "LandlordActions"
	_action_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_action_layer)
	_clock_panel = Panel.new()
	_clock_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock_panel.add_theme_stylebox_override("panel", _style(Color("#f5d27af2"), Color("#946522"), 38))
	add_child(_clock_panel)
	_clock_label = _label(_clock_panel, "—", 0, 0, 70, 70, 33, Color("#862b1d"))
	_sort_button = _button(self, "理牌 · 点数", 0, 0, 158, 44, _sort_hand)
	_collapse_button = _button(self, "收起  ∧", 0, 0, 122, 44, _toggle_hand)
	_status_backdrop = _text_backdrop("LandlordStatusBackdrop")
	_status = _label(self, "正在连接牌桌……", 0, 0, 780, 31, 20, Color("#ffe4ba"))
	_instruction_backdrop = _text_backdrop("LandlordInstructionBackdrop")
	_instruction = _label(self, "轻触手牌选中，再次轻触取消", 0, 0, 720, 26, 15, Color("#f0d2a7"))
	_social_layer = _layer("LandlordSocialBubbles")
	_overlay_layer = _layer("LandlordDialogs")
	_layout_ui()


func _layer(title: String) -> Control:
	var node := Control.new()
	node.name = title
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)
	return node


func _text_backdrop(title: String) -> Panel:
	var panel := Panel.new()
	panel.name = title
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style(Color("#281b14d4"), Color("#b992574d"), 12))
	add_child(panel)
	return panel


func _layout_ui() -> void:
	if _exiting or not is_inside_tree() or _camera == null or not _camera.is_inside_tree() or _status == null: return
	var canvas := _canvas_size()
	var width := minf(canvas.x - 192, (canvas.y - 102) * 1.8)
	_table_rect = Rect2(Vector2((canvas.x - width) * 0.5, canvas.y - width / 1.8 + 20), Vector2(width, width / 1.8))
	_board_view.position = _table_rect.position
	_board_view.size = _table_rect.size
	_action_layer.position = Vector2((canvas.x - 1030) * 0.5, canvas.y - 280)
	_action_layer.size = Vector2(1030, 60)
	_clock_panel.position = Vector2(canvas.x * 0.5 - 35, canvas.y - 365)
	_clock_panel.size = Vector2(70, 70)
	_status.position = Vector2(canvas.x * 0.5 - 330, canvas.y - 216)
	_status.size = Vector2(660, 30)
	_status_backdrop.position = _status.position - Vector2(15, 4)
	_status_backdrop.size = _status.size + Vector2(30, 8)
	_instruction.position = Vector2(canvas.x * 0.5 - 350, 126)
	_instruction.size = Vector2(700, 26)
	_instruction_backdrop.position = _instruction.position - Vector2(12, 4)
	_instruction_backdrop.size = _instruction.size + Vector2(24, 8)
	_sort_button.position = Vector2(215, canvas.y - 53)
	_collapse_button.position = Vector2(canvas.x - 151, canvas.y - 53)
	_render_toolbar()
	_render_header()
	if not _state.is_empty(): _render()


func _render_toolbar() -> void:
	_clear(_toolbar_layer)
	var canvas := _canvas_size()
	var titles := ["设置", "背包", "规则", "退出"]
	var tools := ["settings", "backpack", "rules", "leave"]
	for index in range(4):
		var button := _button(_toolbar_layer, titles[index], canvas.x - 326 + index * 78, 18, 70, 58, _open_tool.bind(tools[index]))
		button.add_theme_font_size_override("font_size", 19)
	var side_titles := ["聊天", "表情", "语音", "道具", "战绩"]
	var side_tools := ["chat", "emote", "voice", "prop", "history"]
	for index in range(5):
		var button := _button(_toolbar_layer, side_titles[index], canvas.x - 92, 158 + index * 78, 70, 66, _open_tool.bind(side_tools[index]))
		button.add_theme_font_size_override("font_size", 21)
		if index == 2:
			button.pressed.disconnect(_open_tool.bind("voice"))
			button.tooltip_text = "按住录音，松开发送，最长 5 秒"
			button.button_down.connect(_voice_down)
			button.button_up.connect(_voice_up)
			_voice_button = button


func _render_header() -> void:
	_clear(_header_layer)
	var canvas := _canvas_size()
	var room_id := str(match_context.get("room_id", ""))
	var room := "练习桌" if training_mode else "房间 " + (("…" + room_id.right(10)) if room_id.length() > 10 else room_id)
	var room_label := _label(_header_layer, room, 340, 15, 225, 34, 18, Color("#ffe2b0"))
	room_label.tooltip_text = room_id
	_label(_header_layer, "第 %d 次发牌 · 叫分 %d" % [int(_state.get("deal_number", 1)), int(_state.get("highest_bid", 0))], 340, 52, 225, 30, 16, Color("#e6d7bf"))
	var bottom := _array("bottom")
	for index in range(3):
		var image := TextureRect.new()
		image.name = "BottomCard%d" % index
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.texture = load(_poker.face_path(bottom[index])) if index < bottom.size() else load(CARD_ART + "back.png")
		image.position = Vector2(canvas.x * 0.5 - 88 + index * 60, 13)
		image.size = Vector2(54, 75)
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_header_layer.add_child(image)
	_label(_header_layer, "底  牌", canvas.x * 0.5 - 84, 89, 174, 24, 17, Color("#f6d8a2"))
	var landlord := int(_state.get("landlord", -1))
	var role := "未确定" if landlord < 0 else ("我是地主" if landlord == int(_state.get("your_seat", -2)) else "%d 号位地主" % (landlord + 1))
	_label(_header_layer, "倍数 ×%d" % int(_state.get("multiplier", 1)), canvas.x * 0.5 + 116, 16, 154, 33, 23, Color("#ffdb84"))
	_label(_header_layer, role, canvas.x * 0.5 + 116, 54, 154, 27, 17, Color("#ffead1"))


func _seat_rect(relative: int) -> Rect2:
	var canvas := _canvas_size()
	if relative == 0: return Rect2(24, canvas.y - 108, 190, 78)
	return Rect2(28 if relative == 2 else canvas.x - 328, 335, 224, 74)


func _render_seats() -> void:
	var players := _array("players")
	var counts := _array("hand_counts")
	for seat in range(mini(3, players.size())):
		var relative := _relative_seat(seat)
		var rect := _seat_rect(relative)
		var active := seat == int(_state.get("turn", -1)) and str(_state.get("phase", "")) != "finished"
		var role := "待叫地主" if int(_state.get("landlord", -1)) < 0 else ("地主" if seat == int(_state.get("landlord", -1)) else "农民")
		var count := int(counts[seat]) if seat < counts.size() else 0
		if relative != 0:
			var portrait := TextureRect.new()
			portrait.name = "OpponentPortrait%d" % seat
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			var atlas := AtlasTexture.new()
			atlas.atlas = load(OPPONENTS)
			var half := float(atlas.atlas.get_width()) * 0.5
			atlas.region = Rect2((0 if relative == 2 else 1) * half, 0, half, atlas.atlas.get_height())
			portrait.texture = atlas
			portrait.position = Vector2(rect.position.x + 2, 127)
			portrait.size = Vector2(220, 220)
			portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_seat_layer.add_child(portrait)
		CHROME.player(_seat_layer, "我" if relative == 0 else str(players[seat]).right(8), "%s · %d 张" % [role, count], rect, active, seat)
	_render_header()


func _render_bottom() -> void:
	# Canonical face images form the top HUD; every playing card remains modeled in 3D.
	pass


func _render_last_play() -> void:
	if not bool(_state.get("has_last_play", false)): return
	var last: Dictionary = _state.get("last_play", {})
	var cards: Array = last.get("cards", [])
	for index in range(cards.size()):
		var along := (float(index) - float(cards.size()-1) * 0.5) * minf(0.10, 1.40 / maxf(1.0, float(cards.size()-1)))
		_card_model(cards[index], Vector3(along, -0.010 + index * 0.0025, -0.16), 1.8)
	var point := _table_point(Vector3(0, 0, -0.16))
	_label(_seat_layer, "上手 · " + _pattern_name(str(last.get("pattern", {}).get("kind", ""))), point.x - 170, point.y - 62, 340, 26, 17, Color("#ffe0a8"))


func _render_my_hand() -> void:
	var hand := _array("hand").duplicate()
	hand.sort_custom(_card_before)
	_hand_sample_order.clear()
	for index in range(hand.size()):
		var card: Dictionary = hand[index]
		var id := int(card.get("id", -1))
		var along := 0.08 + (float(index) - float(hand.size()-1) * 0.5) * minf(0.124, 1.90 / maxf(1.0, float(hand.size()-1)))
		var rest := 0.040 + index * 0.0046
		var model := _card_model(card, Vector3(along, rest + (0.08 if _selected.has(id) else 0.0), 0.60), 3.0)
		model.rotation.x = deg_to_rad(26)
		model.set_meta("rest_y", rest)
		model.set_meta("card_id", id)
		model.visible = not _hand_collapsed
		_hand_nodes.append(model)
		_hand_ids.append(id)
		_hand_sample_order.append(id)


func _card_before(a: Dictionary, b: Dictionary) -> bool:
	var suits := {"spade":0, "heart":1, "club":2, "diamond":3, "joker":4}
	if _sort_mode == 1 and str(a.get("suit", "")) != str(b.get("suit", "")):
		return int(suits.get(str(a.get("suit", "")), 5)) < int(suits.get(str(b.get("suit", "")), 5))
	if int(a.get("rank", 0)) != int(b.get("rank", 0)): return int(a.get("rank", 0)) > int(b.get("rank", 0))
	return int(a.get("id", -1)) < int(b.get("id", -1))


func _update_selected() -> void:
	for index in range(_hand_nodes.size()):
		_hand_nodes[index].position.y = float(_hand_nodes[index].get_meta("rest_y", 0.040)) + (0.08 if _selected.has(_hand_ids[index]) else 0.0)
	_status.text = "已选 %d 张 · 点击出牌提交" % _selected.size()
	if not _actions_ready(): _status.text = "连接恢复中，请稍候再操作"


func _on_board_input(event: InputEvent) -> void:
	if not _hand_collapsed: super._on_board_input(event)


func _render_actions() -> void:
	var phase := str(_state.get("phase", ""))
	var mine := int(_state.get("your_seat", -2))
	var my_turn := _actions_ready() and str(_state.get("status", "")) == "playing" and int(_state.get("turn", -1)) == mine
	var may_pass := bool(_state.get("has_last_play", false)) and int(_state.get("last_play", {}).get("seat", -1)) != mine
	var titles := ["抢地主", "不加倍" if phase == "double" else "不抢", "不出", "提示", "出牌", "加倍 ×2"]
	var callbacks := [_open_tool.bind("bid"), _send_double.bind(false) if phase == "double" else _send_bid.bind(0), _send_pass, _request_hint, _send_play, _send_double.bind(true)]
	var allowed := [my_turn and phase == "bid" and int(_state.get("highest_bid", 0)) < 3, my_turn and phase in ["bid", "double"], my_turn and phase == "play" and may_pass, my_turn and phase == "play", my_turn and phase == "play", my_turn and phase == "double"]
	for index in range(6):
		var button := _button(_action_layer, titles[index], index * 174, 0, 160, 58, callbacks[index])
		_skin_color(button, ACTION_COLORS[index])
		button.disabled = not allowed[index]
		if ACTION_ART.has(titles[index]): _skin_action_art(button, titles[index])
	_sort_button.text = "理牌 · 点数" if _sort_mode == 0 else "理牌 · 花色"
	_collapse_button.text = "展开  ∨" if _hand_collapsed else "收起  ∧"


func _skin_action_art(button: Button, title: String) -> void:
	if not _action_art_textures.has(title):
		var texture: Texture2D = load(ACTION_ART[title])
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		# Visible alpha bounds plus 5 px preserve the 2x badge and soft edges, excluding distant alpha=1 specks.
		atlas.region = ACTION_ART_REGIONS[title]
		_action_art_textures[title] = atlas
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	# Retain the semantic text for accessibility and existing automation; the art owns its lettering.
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_disabled_color", "font_focus_color", "font_outline_color"]:
		button.add_theme_color_override(state, Color.TRANSPARENT)
	button.add_theme_constant_override("outline_size", 0)
	button.tooltip_text = title
	var art := TextureRect.new()
	art.name = "ActionArtwork"
	art.texture = _action_art_textures[title]
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if title == "加倍 ×2":
		# The badge rises above the shared button body; retain the existing touch rectangle.
		art.offset_top = -maxf(0.0, button.size.x * art.texture.get_height() / art.texture.get_width() - button.size.y)
	button.draw.connect(_sync_action_art.bind(button, art))
	_sync_action_art(button, art)


func _sync_action_art(button: Button, art: TextureRect) -> void:
	match button.get_draw_mode():
		BaseButton.DRAW_DISABLED: art.self_modulate = Color(0.66, 0.66, 0.66, 0.62)
		BaseButton.DRAW_PRESSED, BaseButton.DRAW_HOVER_PRESSED: art.self_modulate = Color(0.82, 0.82, 0.82)
		BaseButton.DRAW_HOVER: art.self_modulate = Color(1.12, 1.12, 1.12)
		_: art.self_modulate = Color.WHITE


func _skin_color(button: Button, fill: Color) -> void:
	button.add_theme_stylebox_override("normal", _style(fill, Color("#ffcf69"), 28))
	button.add_theme_stylebox_override("hover", _style(fill.lightened(0.13), Color("#fff2be"), 28))
	button.add_theme_stylebox_override("pressed", _style(fill.darkened(0.13), Color("#ffe092"), 28))
	button.add_theme_stylebox_override("disabled", _style(Color("#4d514bba"), Color("#8f8b7877"), 28))
	button.add_theme_color_override("font_color", Color("#fff7df"))
	button.add_theme_color_override("font_disabled_color", Color("#c0beb2"))
	button.add_theme_color_override("font_outline_color", Color("#493121"))
	button.add_theme_constant_override("outline_size", 3)
	button.add_theme_font_size_override("font_size", 25)


func _render() -> void:
	super._render()
	if str(_state.get("phase", "")) == "double":
		_status.text = "轮到你选择是否加倍" if _is_turn("double") else "等待牌友选择加倍"
		_instruction.text = "每位玩家选择一次 · 每次加倍使本局倍数 ×2"
	else: _instruction.text = "手牌已收起 · 点击展开查看" if _hand_collapsed else "轻触选牌 · 点数与花色理牌均保留选中牌"
	_apply_appearance()
	_update_clock()
	if is_instance_valid(_voice_button): _voice_button.disabled = not _actions_ready() and not _recording
	_render_bubbles()
	if _tool_open == "bid" and not _is_turn("bid"): _tool_open = ""
	if not _tool_open.is_empty():
		_clear(_overlay_layer)
		_render_tool()
	if not _actions_ready() and str(_state.get("phase", "")) != "finished": _status.text = "连接恢复中，请稍候再操作"


func _is_turn(phase: String) -> bool:
	return _actions_ready() and str(_state.get("phase", "")) == phase and str(_state.get("status", "")) == "playing" and int(_state.get("turn", -1)) == int(_state.get("your_seat", -2))


func _refresh_connection_actions() -> void:
	super._refresh_connection_actions()
	if _exiting: return
	if is_instance_valid(_voice_button): _voice_button.disabled = not _actions_ready() and not _recording
	if _tool_open in ["bid", "chat", "emote", "prop"] and _overlay_layer != null:
		_clear(_overlay_layer)
		_render_tool()


func _send_bid(amount: int) -> void:
	if not _require_actions_ready(): return
	if not _is_turn("bid") or amount < 0 or amount > 3 or (amount > 0 and amount <= int(_state.get("highest_bid", 0))):
		_status.text = "请选择当前可叫的分数"
		return
	super._send_bid(amount)
	if _last_send_error == OK:
		_close_tool()
		_play_sound()


func _send_double(enabled: bool) -> void:
	if not _require_actions_ready(): return
	if not _is_turn("double"):
		_status.text = "当前不是你的加倍回合"
		return
	_send({"type":"landlord_action", "action":"double", "enabled":enabled})
	if _last_send_error == OK:
		_close_tool()
		_play_sound()


func _request_hint() -> void:
	if not _require_actions_ready(): return
	if _is_turn("play"): _send({"type":"landlord_action", "action":"hint"})


func _send_play() -> void:
	if not _require_actions_ready(): return
	if _hand_collapsed:
		_status.text = "请先展开手牌并选择要出的牌"
		return
	if _is_turn("play"): super._send_play()


func _send_pass() -> void:
	if not _require_actions_ready(): return
	if _is_turn("play") and bool(_state.get("has_last_play", false)) and int(_state.get("last_play", {}).get("seat", -1)) != int(_state.get("your_seat", -2)):
		super._send_pass()


func _sort_hand() -> void:
	_sort_mode = 1 - _sort_mode
	_save_preferences()
	_render()


func _toggle_hand() -> void:
	_hand_collapsed = not _hand_collapsed
	_selected.clear()
	_render()


func _apply_appearance() -> void:
	if _camera == null or not _camera.is_inside_tree(): return
	var table := _camera.get_parent().get_parent().get_node_or_null("ImportedPokerTable")
	if table != null:
		var surface := table.find_child("FeltPlayingSurface", true, false) as MeshInstance3D
		if surface != null:
			if _wood_material == null:
				_wood_material = StandardMaterial3D.new()
				_wood_material.albedo_color = Color("#cbb59c")
				_wood_material.roughness = 0.68
				_wood_material.metallic_specular = 0.18
				_felt_material = StandardMaterial3D.new()
				_felt_material.albedo_color = Color("#1e6753")
				_felt_material.roughness = 0.88
			if _wood_material.albedo_texture == null and ResourceLoader.exists(WOOD): _wood_material.albedo_texture = load(WOOD)
			surface.material_override = _wood_material if _table_theme == "wood" else _felt_material
	if _poker._back != null:
		_poker._back.albedo_color = {"blue":Color.WHITE, "jade":Color(0.45, 1.0, 0.70), "violet":Color(0.95, 0.54, 1.0)}[_back_theme]


func _process(delta: float) -> void:
	super._process(delta)
	_update_clock()
	if _recording and Time.get_ticks_msec() - _record_started >= 5000: _voice_up()
	var expired := false
	for seat in _social_events.keys():
		if Time.get_ticks_msec() >= int(_social_events[seat].get("until", 0)):
			_social_events.erase(seat)
			expired = true
	if expired: _render_bubbles()


func _update_clock() -> void:
	if _clock_label == null: return
	var phase := str(_state.get("phase", ""))
	_clock_panel.visible = _actions_ready() and str(_state.get("status", "")) == "playing" and phase in ["bid", "double", "play"]
	_clock_label.text = str(maxi(0, ceili(float(_deadline_tick - Time.get_ticks_msec()) / 1000.0))) if _deadline_tick > 0 else "—"


func _handle_packet(raw: String) -> void:
	var parsed = JSON.parse_string(raw)
	if not parsed is Dictionary: return
	var kind := str(parsed.get("type", ""))
	if kind == "landlord_state":
		var deadline := int(parsed.get("action_deadline_ms", 0))
		_deadline_tick = Time.get_ticks_msec() + maxi(0, deadline - int(parsed.get("server_now_ms", 0))) if deadline > 0 else 0
		if str(parsed.get("phase", "")) == "finished": _record_result(parsed)
		var signature := JSON.stringify(parsed.get("last_play", {})) if bool(parsed.get("has_last_play", false)) else ""
		if not signature.is_empty() and signature != _last_play_signature: _play_sound()
		_last_play_signature = signature
	elif kind == "landlord_social":
		_receive_social(parsed)
		return
	super._handle_packet(raw)


func _send(payload: Dictionary) -> void:
	if str(payload.get("type", "")) == "landlord_training_start":
		_training_session = "%d_%d" % [int(Time.get_unix_time_from_system() * 1000), Time.get_ticks_usec()]
	super._send(payload)


func _record_result(state: Dictionary) -> void:
	var scores = state.get("scores", [])
	if not scores is Array or scores.size() != 3 or int(state.get("winner", -1)) < 0: return
	var room := str(state.get("room_id", match_context.get("room_id", "")))
	var key := "%s|%s|%s|%s" % [room, _training_session if training_mode else "live", state.get("deal_number", 1), state.get("epoch", 0)]
	for row in _history:
		if str(row.get("key", "")) == key: return
	_history.push_front({"key":key, "room":room, "training":training_mode, "time":Time.get_datetime_string_from_system(false, true), "score":int(scores[int(state.get("your_seat", 0))]), "multiplier":int(state.get("multiplier", 1)), "winner":int(state.get("winner", -1)), "deal":int(state.get("deal_number", 1))})
	if _history.size() > 100: _history.resize(100)
	var file := FileAccess.open(history_file, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(_history))


func _open_tool(tool: String) -> void:
	if tool == "bid" and not _require_actions_ready(): return
	if tool == "leave":
		_request_leave()
		return
	_tool_open = tool
	_menu_open = false
	_clear(_overlay_layer)
	_render_tool()


func _close_tool() -> void:
	_tool_open = ""
	_clear(_overlay_layer)
	if str(_state.get("phase", "")) == "finished": _render_settlement()


func _render_tool() -> void:
	match _tool_open:
		"settings": _settings_panel()
		"backpack": _backpack_panel()
		"rules": _rules_panel()
		"bid": _bid_panel()
		"chat", "emote": _social_panel()
		"prop": _prop_panel()
		"history": _history_panel()


func _tool_panel(title: String, height: float = 420) -> Panel:
	var panel := _modal_panel(Vector2(640, height))
	_label(panel, title, 24, 18, 520, 50, 28)
	_button(panel, "关闭", 548, 20, 68, 44, _close_tool)
	return panel


func _settings_panel() -> void:
	var panel := _tool_panel("牌桌设置", 380)
	_label(panel, "画质", 28, 96, 100, 48, 21)
	for index in range(3):
		_button(panel, ["低", "中", "高"][index], 142 + index * 148, 96, 132, 48, _choose_quality.bind(index), index == _quality)
	_button(panel, "音效与语音：" + ("开" if _sound_enabled else "关"), 40, 180, 560, 58, _toggle_sound)
	_button(panel, "古筝音乐：" + ("开" if _music_enabled else "关"), 40, 264, 560, 58, _toggle_music)


func _choose_quality(index: int) -> void:
	_set_quality(index)
	_clear(_overlay_layer)
	_settings_panel()


func _toggle_sound() -> void:
	_sound_enabled = not _sound_enabled
	_save_preferences()
	_apply_audio()
	_clear(_overlay_layer)
	_settings_panel()


func _toggle_music() -> void:
	_music_enabled = not _music_enabled
	_save_preferences()
	_apply_audio()
	_clear(_overlay_layer)
	_settings_panel()


func _backpack_panel() -> void:
	var panel := _tool_panel("免费外观 · 本机保存", 380)
	_label(panel, "牌背", 28, 96, 100, 48, 21)
	for index in range(3):
		var theme: String = ["blue", "jade", "violet"][index]
		_button(panel, ["原蓝", "墨绿", "暮紫"][index], 142 + index * 148, 96, 132, 48, _choose_back.bind(theme), theme == _back_theme)
	_label(panel, "桌面", 28, 181, 100, 48, 21)
	_button(panel, "暖木桌", 142, 181, 206, 54, _choose_table.bind("wood"), _table_theme == "wood")
	_button(panel, "碧玉毡", 368, 181, 218, 54, _choose_table.bind("jade"), _table_theme == "jade")
	_label(panel, "所有外观均免费，可随时切换", 28, 285, 584, 32, 18, Color("#b8c1aa"))


func _choose_back(theme: String) -> void:
	if theme not in ["blue", "jade", "violet"]: return
	_back_theme = theme
	_save_preferences()
	_apply_appearance()
	_clear(_overlay_layer)
	_backpack_panel()


func _choose_table(theme: String) -> void:
	if theme not in ["wood", "jade"]: return
	_table_theme = theme
	_save_preferences()
	_apply_appearance()
	_clear(_overlay_layer)
	_backpack_panel()


func _rules_panel() -> void:
	var panel := _tool_panel("斗地主规则", 476)
	var phase := str(_state.get("phase", "等待入座"))
	var phase_name := str({"bid":"叫分", "double":"加倍", "play":"出牌", "finished":"结算"}.get(phase, "等待入座"))
	_label(panel, "当前：%s · 本局倍数 ×%d" % [phase_name, int(_state.get("multiplier", 1))], 32, 87, 576, 38, 22, Color("#eec57c"))
	_label(panel, "三人一副牌，地主 20 张，农民各 17 张。\n抢地主选择 1、2、3 分，须高于已叫分；也可不抢。\n叫分后每人决定是否加倍，每次加倍使公共倍数 ×2。\n地主先出，同牌型且更大的牌可压；炸弹和王炸另计倍数。\n任一方出完手牌结算；暂离牌桌后，联网对局继续托管。", 38, 146, 564, 246, 20, Color("#eee4cb"))
	_label(panel, "提示由本局服务器计算 · 旧版房间可能不含加倍阶段", 32, 411, 576, 28, 16, Color("#9badab"))


func _bid_panel() -> void:
	var panel := _tool_panel("抢地主 · 请选择叫分", 292)
	var high := int(_state.get("highest_bid", 0))
	_label(panel, "当前最高 %d 分，须选择更高分数" % high, 24, 88, 592, 36, 20, Color("#eec57c"))
	for amount in range(1, 4):
		var button := _button(panel, "叫 %d 分" % amount, 32 + (amount-1) * 194, 164, 180, 64, _send_bid.bind(amount), true)
		button.disabled = amount <= high or not _is_turn("bid")


func _social_panel() -> void:
	var chatting := _tool_open == "chat"
	var panel := _tool_panel("快捷聊天" if chatting else "牌桌表情", 480)
	var ids := CHAT_IDS if chatting else EMOTE_IDS
	var texts := CHAT_TEXTS if chatting else EMOTE_TEXTS
	for index in range(ids.size()):
		var button := _button(panel, texts[index], 40, 91 + index * 66, 560, 54, _send_social_choice.bind("chat" if chatting else "emote", "quick_chat" if chatting else "emote", ids[index]))
		button.disabled = not _actions_ready()
	if not _actions_ready(): _label(panel, "连接恢复后可互动", 24, 426, 592, 28, 17, Color("#deb879"))


func _prop_panel() -> void:
	var panel := _tool_panel("免费互动道具", 410)
	_label(panel, "送给哪位牌友？", 24, 88, 592, 36, 20, Color("#eec57c"))
	var mine := int(_state.get("your_seat", 0))
	for side in range(2):
		var target := (mine + side + 1) % 3
		_label(panel, "%d 号位" % (target + 1), 36 + side * 300, 139, 268, 32, 19)
		for index in range(4):
			var button := _button(panel, PROP_TEXTS[index], 36 + side * 300 + (index % 2) * 138, 191 + int(index / 2) * 82, 130, 62, _send_prop.bind(PROP_IDS[index], target))
			button.disabled = not _actions_ready()
	if not _actions_ready(): _label(panel, "连接恢复后可互动", 24, 362, 592, 28, 17, Color("#deb879"))


func _history_panel() -> void:
	var panel := _tool_panel("本机战绩", 484)
	if _history.is_empty():
		_label(panel, "暂无结算记录\n完成实际对局后，会自动保存本机收到的结算", 32, 142, 576, 150, 22, Color("#b8c1aa"))
	for index in range(mini(7, _history.size())):
		var row: Dictionary = _history[index]
		var label := "训练" if bool(row.get("training", false)) else "联网"
		_label(panel, "%s  %s  第%d次发牌  %+d分  ×%d" % [label, str(row.get("time", "")).left(16), int(row.get("deal", 1)), int(row.get("score", 0)), int(row.get("multiplier", 1))], 24, 88 + index * 46, 592, 42, 18)
	_label(panel, "只记录已收到的结算 · 最多保存最近 100 局", 24, 438, 592, 26, 15, Color("#9badab"))


func _send_social_choice(action: String, field: String, value: String) -> void:
	var payload := {"type":"landlord_social", "action":action}
	payload[field] = value
	_submit_social(payload)


func _send_prop(prop: String, target: int) -> void:
	_submit_social({"type":"landlord_social", "action":"prop", "prop":prop, "target_seat":target})


func _submit_social(payload: Dictionary) -> bool:
	if not _require_actions_ready(): return false
	if Time.get_ticks_msec() - _last_social_send < 1000:
		_status.text = "稍等一秒再互动"
		return false
	payload["message_id"] = "%d_%d" % [get_instance_id(), Time.get_ticks_usec()]
	_send(payload)
	if _last_send_error != OK: return false
	_last_social_send = Time.get_ticks_msec()
	_close_tool()
	_status.text = "互动已提交 · 等待牌桌确认"
	return true


func _voice_down() -> void:
	if _recording: return
	if not _require_actions_ready(): return
	if not is_instance_valid(_voice): return
	var error: Error = _voice.start_recording()
	if error != OK:
		_status.text = _voice.last_error
		return
	_recording = true
	_record_started = Time.get_ticks_msec()
	_voice_button.text = "录音中"
	_status.text = "正在录音 · 松开发送 · 最长 5 秒"


func _voice_up() -> void:
	if not _recording: return
	_recording = false
	_voice_button.text = "语音"
	_voice_button.disabled = not _actions_ready()
	var payload: Dictionary = _voice.stop_recording()
	if payload.is_empty():
		_status.text = _voice.last_error
		return
	payload["type"] = "landlord_social"
	payload["action"] = "voice"
	if _submit_social(payload): _status.text = "语音已提交 · 等待牌桌确认"


func _receive_social(event: Dictionary) -> void:
	var seat := int(event.get("seat", -1))
	if seat < 0 or seat > 2: return
	var text := ""
	match str(event.get("action", "")):
		"chat": text = str(event.get("text", ""))
		"emote":
			var index := EMOTE_IDS.find(str(event.get("emote", "")))
			if index >= 0: text = EMOTE_TEXTS[index]
		"prop":
			var index := PROP_IDS.find(str(event.get("prop", "")))
			if index >= 0: text = "%d 号位送来%s" % [seat + 1, PROP_TEXTS[index]]
			seat = int(event.get("target_seat", seat))
		"voice":
			text = "语音 %.1f 秒" % (float(event.get("duration_ms", 0)) / 1000.0)
			if seat != int(_state.get("your_seat", -1)) and is_instance_valid(_voice):
				if _voice.play(event) != OK: _status.text = _voice.last_error
	if text.is_empty(): return
	_social_events[seat] = {"text":text, "until":Time.get_ticks_msec() + 4500}
	_render_bubbles()


func _render_bubbles() -> void:
	if _social_layer == null: return
	_clear(_social_layer)
	for seat in _social_events:
		var relative := _relative_seat(int(seat))
		var rect := _seat_rect(relative)
		var box := Panel.new()
		box.position = Vector2(rect.position.x, rect.end.y + 12 if relative != 0 else rect.position.y - 62)
		box.size = Vector2(230, 52)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_stylebox_override("panel", _style(Color("#f6e1bbed"), Color("#9f762f"), 14))
		_social_layer.add_child(box)
		_label(box, str(_social_events[seat].get("text", "")), 8, 4, 214, 44, 17, Color("#51351c"))


func _request_leave() -> void:
	_tool_open = ""
	super._request_leave()


func _return_now() -> void:
	if _recording and is_instance_valid(_voice):
		_voice.stop_recording()
		_recording = false
	_stop_audio()
	super._return_now()


func _render_settlement() -> void:
	super._render_settlement()
