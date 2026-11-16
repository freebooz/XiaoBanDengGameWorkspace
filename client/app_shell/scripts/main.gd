extends Control
## Main（小板凳象棋客户端应用流程入口）
## 正式流程：Boot（启动）→ Login（登录）→ Lobby（大厅）→ Matchmaking（匹配）
## → Room（同房间/红黑座位/准备）→ Game（3D对局）。
## 所有业务状态来自Go服务端；图片只负责表现，不把账号、房间、按钮文字烘焙进背景。

const API_CLIENT_SCRIPT = preload("res://modules/foundation/network/api_client.gd")
const PORTRAIT_FLOW := preload("res://modules/foundation/ui/portrait_flow.gd")

const UI_ROOT := "res://modules/games/chinese_chess/assets/ui/mobile/"
const BG_PATH := "res://modules/games/chinese_chess/assets/ink_landscape_background.png"
const BOARD_PREVIEW_PATH := "res://modules/games/chinese_chess/assets/engraved_chessboard.png"
const HEADER_PATH := UI_ROOT + "header_foreground.png"
const MASCOT_PATH := UI_ROOT + "mascot.png"

enum FlowState {
	BOOT,
	LOGIN,
	LOBBY,
	MATCHING,
	ROOM,
	GAME,
}

var _product: Dictionary = {}
var _account: Dictionary = {}
var _match: Dictionary = {}
var _state: FlowState = FlowState.BOOT
var _api
var _screen_root: Control
var _http_request: HTTPRequest
var _poll_timer: Timer
var _request_kind := ""
var _status_label: Label
var _primary_button: Button
var _auto_flow := false
var _terms_checkbox: CheckBox
var _local_ready := false
var _server_field: LineEdit

# 房间页动态控件引用。
var _room_red_label: Label
var _room_black_label: Label
var _room_ready_count_label: Label
var _room_status_label: Label
var _room_ready_button: Button


func _ready() -> void:
	_product = _load_product_config()
	_auto_flow = "--auto-flow" in OS.get_cmdline_user_args()
	_api = API_CLIENT_SCRIPT.new()

	_screen_root = Control.new()
	_screen_root.name = "FlowScreenRoot"
	_screen_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_screen_root)
	resized.connect(_fit_flow)

	_http_request = HTTPRequest.new()
	_http_request.name = "FlowHttpRequest"
	_http_request.timeout = 6.0
	_http_request.request_completed.connect(_on_http_request_completed)
	add_child(_http_request)

	_poll_timer = Timer.new()
	_poll_timer.name = "FlowPollTimer"
	_poll_timer.one_shot = true
	_poll_timer.wait_time = 0.8
	_poll_timer.timeout.connect(_on_poll_timer)
	add_child(_poll_timer)

	_show_boot()
	_request_health()


func _load_product_config() -> Dictionary:
	var file := FileAccess.open("res://product.json", FileAccess.READ)
	if file == null:
		push_error("未找到 product.json，请通过 tools/compose-godot.ps1 生成产品工程。")
		return {
			"display_name": "小板凳开发壳",
			"product_id": "unknown",
			"game_id": "unknown",
			"rule_set_id": "unknown",
			"rule_version": "0.0.0"
		}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("product.json 格式错误")
		return {}
	return parsed


func _set_state(next_state: FlowState) -> void:
	_state = next_state
	print("FLOW_STATE=%s" % FlowState.keys()[next_state])


func _clear_screen() -> void:
	_fit_flow()
	for child in _screen_root.get_children():
		child.queue_free()
	_status_label = null
	_primary_button = null
	_terms_checkbox = null
	_room_red_label = null
	_room_black_label = null
	_room_ready_count_label = null
	_room_status_label = null
	_room_ready_button = null
	_server_field = null


func _fit_flow() -> void:
	PORTRAIT_FLOW.fit(self, _screen_root, _state == FlowState.GAME)


func _make_server_field(y: float) -> void:
	_server_field = LineEdit.new()
	_server_field.name = "ServerAddress"
	_server_field.text = _api.base_url
	_server_field.placeholder_text = "服务器地址，如 http://192.168.1.10:8080"
	_server_field.position = Vector2(80, y)
	_server_field.size = Vector2(560, 56)
	_server_field.add_theme_font_size_override("font_size", 21)
	_server_field.add_theme_color_override("font_color", Color("#fff3d7"))
	_server_field.add_theme_color_override("font_placeholder_color", Color("#ddc499"))
	_server_field.add_theme_stylebox_override("normal", _panel_style(Color("#321f17ed"), Color("#d8a86c"), 9))
	_server_field.add_theme_stylebox_override("focus", _panel_style(Color("#51301ded"), Color("#ffe1a6"), 9))
	_screen_root.add_child(_server_field)


func _apply_server_field() -> bool:
	if _server_field != null and _api.set_base_url(_server_field.text):
		return true
	if _status_label != null:
		_status_label.text = "请输入以 http:// 或 https:// 开头的服务器地址。"
	return false


func _retry_server_address() -> void:
	if _apply_server_field():
		_request_health()


func _load_png_texture(path: String, fallback: Color = Color("#5c3a25")) -> Texture2D:
	if FileAccess.file_exists(path):
		var bytes := FileAccess.get_file_as_bytes(path)
		if not bytes.is_empty():
			var image := Image.new()
			if image.load_png_from_buffer(bytes) == OK and not image.is_empty():
				return ImageTexture.create_from_image(image)
	var fallback_image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	fallback_image.fill(fallback)
	return ImageTexture.create_from_image(fallback_image)


func _load_ui_texture(path: String) -> Texture2D:
	# UI 运行资产统一使用透明 PNG，直接解码源文件，避免依赖编辑器导入缓存。
	if path.get_extension().to_lower() == "png":
		return _load_png_texture(path)
	var resource = load(path)
	if resource is Texture2D:
		return resource as Texture2D
	return _load_png_texture(path)


func _build_background(darken: float = 0.22) -> void:
	var background := TextureRect.new()
	background.name = "DesignBackground"
	background.texture = _load_png_texture(BG_PATH, Color("#7d5536"))
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_root.add_child(background)

	var warm := ColorRect.new()
	warm.color = Color(0.18, 0.08, 0.03, darken)
	warm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	warm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_root.add_child(warm)


func _add_header(position_value: Vector2 = Vector2(50, 36), size_value: Vector2 = Vector2(620, 310)) -> void:
	var header := TextureRect.new()
	header.name = "TransparentHeaderForeground"
	header.texture = _load_ui_texture(HEADER_PATH)
	header.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	header.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.position = position_value
	header.size = size_value
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_root.add_child(header)

	var title := _make_label("小板凳象棋", 48, Color("#fff6d8"))
	title.position = Vector2(position_value.x + size_value.x * 0.12, position_value.y + size_value.y * 0.68)
	title.size = Vector2(size_value.x * 0.76, 70)
	title.add_theme_color_override("font_shadow_color", Color("#6a2618"))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 4)
	_screen_root.add_child(title)


func _make_label(text_value: String, font_size: int, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _panel_style(color: Color, border: Color = Color("#f0c889"), radius: int = 18, width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.15, 0.06, 0.02, 0.30)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 6)
	return style


func _button_style(color: Color, border: Color, radius: int = 18) -> StyleBoxFlat:
	var style := _panel_style(color, border, radius, 2)
	style.shadow_size = 7
	style.shadow_offset = Vector2(0, 4)
	return style


func _make_action_button(
	text_value: String,
	icon_path: String,
	color: Color,
	border: Color,
	callable: Callable,
	minimum_height: float = 70.0
) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(0, minimum_height)
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", Color("#fff8e9"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _button_style(color, border))
	button.add_theme_stylebox_override("hover", _button_style(color.lightened(0.08), border.lightened(0.12)))
	button.add_theme_stylebox_override("pressed", _button_style(color.darkened(0.08), border))
	button.icon = _load_ui_texture(icon_path)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(callable)
	return button


func _make_small_tool(text_value: String, callable: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(86, 58)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_stylebox_override("normal", _button_style(Color("#3f2a20cc"), Color("#d49c5c"), 14))
	button.add_theme_stylebox_override("hover", _button_style(Color("#5b3826ee"), Color("#f0b45a"), 14))
	button.pressed.connect(callable)
	return button


func _make_mode_button(
	title_text: String,
	subtitle_text: String,
	icon_path: String,
	color: Color,
	callable: Callable
) -> Button:
	var button := Button.new()
	button.text = "%s\n%s" % [title_text, subtitle_text]
	button.custom_minimum_size = Vector2(0, 150)
	button.add_theme_font_size_override("font_size", 21)
	button.add_theme_color_override("font_color", Color("#4d2415"))
	button.add_theme_color_override("font_hover_color", Color("#3a190f"))
	button.add_theme_stylebox_override("normal", _button_style(color, color.darkened(0.22), 20))
	button.add_theme_stylebox_override("hover", _button_style(color.lightened(0.08), color.darkened(0.08), 20))
	button.add_theme_stylebox_override("pressed", _button_style(color.darkened(0.05), color.darkened(0.22), 20))
	button.icon = _load_ui_texture(icon_path)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(callable)
	return button


func _add_top_tools() -> void:
	var tools := HBoxContainer.new()
	tools.position = Vector2(430, 20)
	tools.size = Vector2(270, 64)
	tools.add_theme_constant_override("separation", 8)
	_screen_root.add_child(tools)
	tools.add_child(_make_small_tool("客服", _on_info_tool.bind("客服中心")))
	tools.add_child(_make_small_tool("公告", _on_info_tool.bind("公告")))
	tools.add_child(_make_small_tool("设置", _on_info_tool.bind("设置")))


func _add_status(text_value: String, position_value: Vector2, size_value: Vector2) -> Label:
	_status_label = _make_label(text_value, 15, Color("#fff2d6"))
	_status_label.position = position_value
	_status_label.size = size_value
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_shadow_color", Color("#2e140dcc"))
	_status_label.add_theme_constant_override("shadow_offset_x", 1)
	_status_label.add_theme_constant_override("shadow_offset_y", 2)
	_screen_root.add_child(_status_label)
	return _status_label


func _show_boot() -> void:
	_set_state(FlowState.BOOT)
	_clear_screen()
	_build_background(0.38)
	_add_header(Vector2(70, 190), Vector2(580, 290))

	var loading_card := PanelContainer.new()
	loading_card.position = Vector2(90, 650)
	loading_card.size = Vector2(540, 180)
	loading_card.add_theme_stylebox_override("panel", _panel_style(Color("#25150ddb"), Color("#dca45d"), 24))
	_screen_root.add_child(loading_card)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	loading_card.add_child(box)
	var label := _make_label("正在启动小板凳象棋", 26, Color("#ffe3a8"))
	box.add_child(label)
	var bar := ProgressBar.new()
	bar.indeterminate = true
	bar.custom_minimum_size = Vector2(430, 16)
	box.add_child(bar)
	_status_label = _make_label("正在检查业务服务、产品配置与网络环境……", 14, Color("#e4cfba"))
	box.add_child(_status_label)


func _show_boot_error(message: String) -> void:
	if _status_label != null:
		_status_label.text = "启动失败：%s" % message
	if _primary_button == null:
		_make_server_field(930)
		_primary_button = _make_action_button(
			"重新连接",
			UI_ROOT + "icon_quick.png",
			Color("#c8792f"),
			Color("#f0b45a"),
			_retry_server_address,
			58
		)
		_primary_button.position = Vector2(180, 1010)
		_primary_button.size = Vector2(360, 64)
		_screen_root.add_child(_primary_button)


func _show_login() -> void:
	_set_state(FlowState.LOGIN)
	_clear_screen()
	_build_background(0.18)
	_add_top_tools()
	_add_header(Vector2(50, 70), Vector2(620, 310))

	var slogan := _make_label("一局象棋 · 闲出好心情！", 28, Color("#fff1c9"))
	slogan.position = Vector2(80, 365)
	slogan.size = Vector2(560, 64)
	slogan.add_theme_color_override("font_shadow_color", Color("#572416"))
	slogan.add_theme_constant_override("shadow_offset_x", 2)
	slogan.add_theme_constant_override("shadow_offset_y", 3)
	_screen_root.add_child(slogan)

	var mascot := TextureRect.new()
	mascot.texture = _load_ui_texture(MASCOT_PATH)
	mascot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mascot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mascot.position = Vector2(225, 430)
	mascot.size = Vector2(270, 270)
	mascot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_root.add_child(mascot)

	var login_panel := PanelContainer.new()
	login_panel.position = Vector2(72, 720)
	login_panel.size = Vector2(576, 390)
	login_panel.add_theme_stylebox_override("panel", _panel_style(Color("#fff6e8ed"), Color("#dfae70"), 28))
	_screen_root.add_child(login_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 24)
	login_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)

	var welcome := _make_label("欢迎回来，棋友！", 26, Color("#5c2c1b"))
	box.add_child(welcome)

	var wechat := _make_action_button(
		"微信登录",
		UI_ROOT + "icon_wechat.png",
		Color("#25b94e"),
		Color("#7bdd8c"),
		_on_wechat_login
	)
	box.add_child(wechat)

	_primary_button = _make_action_button(
		"游客登录",
		UI_ROOT + "icon_guest.png",
		Color("#d79b55"),
		Color("#f3ce91"),
		_on_guest_login
	)
	box.add_child(_primary_button)

	_terms_checkbox = CheckBox.new()
	_terms_checkbox.text = "我已阅读并同意《用户协议》和《隐私政策》"
	_terms_checkbox.add_theme_font_size_override("font_size", 13)
	_terms_checkbox.add_theme_color_override("font_color", Color("#6f6258"))
	box.add_child(_terms_checkbox)
	if _auto_flow:
		_terms_checkbox.button_pressed = true

	_status_label = _make_label("登录即享快乐对弈", 14, Color("#9a6a3a"))
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(0, 44)
	box.add_child(_status_label)
	_make_server_field(1120)

	var footer := _make_label("小板凳 · 大快乐 · 棋聚好时光", 14, Color("#f4d39d"))
	footer.position = Vector2(80, 1200)
	footer.size = Vector2(560, 44)
	_screen_root.add_child(footer)

	if _auto_flow:
		call_deferred("_on_guest_login")


func _show_lobby() -> void:
	_set_state(FlowState.LOBBY)
	_clear_screen()
	_build_background(0.10)

	# 顶部玩家状态栏。
	var player_card := PanelContainer.new()
	player_card.position = Vector2(18, 18)
	player_card.size = Vector2(395, 100)
	player_card.add_theme_stylebox_override("panel", _panel_style(Color("#321e14dd"), Color("#d39a56"), 18))
	_screen_root.add_child(player_card)

	var player_box := HBoxContainer.new()
	player_box.add_theme_constant_override("separation", 12)
	player_card.add_child(player_box)
	var avatar := TextureRect.new()
	avatar.texture = _load_ui_texture(MASCOT_PATH)
	avatar.custom_minimum_size = Vector2(84, 84)
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	player_box.add_child(avatar)
	var player_text := VBoxContainer.new()
	player_box.add_child(player_text)
	var display_name := str(_account.get("display_name", "小板凳玩家"))
	if display_name == "":
		display_name = "小板凳玩家"
	player_text.add_child(_make_label(display_name, 20, Color("#fff1d6")))
	var rank := _make_label("休闲棋友 · 标准象棋", 13, Color("#e5b971"))
	player_text.add_child(rank)

	var mail := _make_small_tool("消息", _on_info_tool.bind("消息"))
	mail.position = Vector2(630, 28)
	mail.size = Vector2(72, 64)
	_screen_root.add_child(mail)

	_add_header(Vector2(90, 115), Vector2(540, 270))

	var announcement := PanelContainer.new()
	announcement.position = Vector2(24, 380)
	announcement.size = Vector2(672, 62)
	announcement.add_theme_stylebox_override("panel", _panel_style(Color("#fff0d2ee"), Color("#df9d4d"), 16))
	_screen_root.add_child(announcement)
	var announce_text := _make_label("📣 官方  周末欢乐赛火热开启！以棋会友，快乐对弈", 15, Color("#7a321d"))
	announcement.add_child(announce_text)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.position = Vector2(24, 466)
	grid.size = Vector2(672, 540)
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	_screen_root.add_child(grid)

	var quick := _make_mode_button(
		"快速对局",
		"随时开玩 · 真人匹配",
		UI_ROOT + "icon_quick.png",
		Color("#ffd064"),
		_on_quick_match
	)
	quick.custom_minimum_size = Vector2(329, 160)
	grid.add_child(quick)
	var ranked := _make_mode_button(
		"排位赛",
		"挑战自我 · 冲击段位",
		UI_ROOT + "icon_ranked.png",
		Color("#ff8067"),
		_on_lobby_feature.bind("排位赛")
	)
	ranked.custom_minimum_size = Vector2(329, 160)
	grid.add_child(ranked)
	var friend := _make_mode_button(
		"好友房",
		"约上好友 · 快乐对弈",
		UI_ROOT + "icon_friend.png",
		Color("#75b5ff"),
		_on_lobby_feature.bind("好友房")
	)
	friend.custom_minimum_size = Vector2(329, 150)
	grid.add_child(friend)
	var ai := _make_mode_button(
		"双人训练",
		"轮流走棋 · 熟悉规则",
		UI_ROOT + "icon_ai.png",
		Color("#65d68b"),
		_on_lobby_feature.bind("双人训练")
	)
	ai.custom_minimum_size = Vector2(329, 150)
	grid.add_child(ai)
	var puzzle := _make_mode_button(
		"走子练习",
		"标准开局 · 基础练习",
		UI_ROOT + "icon_puzzle.png",
		Color("#b995ff"),
		_on_lobby_feature.bind("走子练习")
	)
	puzzle.custom_minimum_size = Vector2(329, 150)
	grid.add_child(puzzle)
	var social := _make_mode_button(
		"棋友圈",
		"分享棋谱 · 结交棋友",
		UI_ROOT + "icon_friend.png",
		Color("#f0d08b"),
		_on_lobby_feature.bind("棋友圈")
	)
	social.custom_minimum_size = Vector2(329, 150)
	grid.add_child(social)

	_add_status("大厅就绪 · 选择“快速对局”进入真人匹配", Vector2(40, 1016), Vector2(640, 48))

	var nav := HBoxContainer.new()
	nav.position = Vector2(20, 1090)
	nav.size = Vector2(680, 100)
	nav.add_theme_constant_override("separation", 8)
	_screen_root.add_child(nav)
	for item in ["⌂ 首页", "⚔ 对局", "🎁 活动", "♟ 社交", "☺ 我的"]:
		var b := Button.new()
		b.text = item
		b.custom_minimum_size = Vector2(128, 76)
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_stylebox_override("normal", _button_style(Color("#5b321fe8"), Color("#c88a4f"), 14))
		b.pressed.connect(_on_lobby_feature.bind(item))
		nav.add_child(b)

	var footer := _make_label("小板凳 · 大快乐", 15, Color("#f5d8a8"))
	footer.position = Vector2(200, 1200)
	footer.size = Vector2(320, 40)
	_screen_root.add_child(footer)

	if _auto_flow:
		call_deferred("_on_quick_match")


func _show_matching() -> void:
	_set_state(FlowState.MATCHING)
	_clear_screen()
	_build_background(0.32)
	_add_header(Vector2(90, 110), Vector2(540, 270))

	var mascot := TextureRect.new()
	mascot.texture = _load_ui_texture(MASCOT_PATH)
	mascot.position = Vector2(235, 405)
	mascot.size = Vector2(250, 250)
	mascot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mascot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_screen_root.add_child(mascot)

	var panel := PanelContainer.new()
	panel.position = Vector2(75, 700)
	panel.size = Vector2(570, 300)
	panel.add_theme_stylebox_override("panel", _panel_style(Color("#2b1a13e8"), Color("#e2ad66"), 24))
	_screen_root.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	box.add_child(_make_label("正在寻找棋友", 30, Color("#ffe2a6")))
	var spinner := ProgressBar.new()
	spinner.indeterminate = true
	spinner.custom_minimum_size = Vector2(470, 16)
	box.add_child(spinner)
	_status_label = _make_label("正在加入快速匹配队列……", 16, Color("#dfc8ae"))
	box.add_child(_status_label)
	var cancel := _make_action_button(
		"取消匹配",
		UI_ROOT + "icon_exit.png",
		Color("#9b5937"),
		Color("#dba06b"),
		_on_cancel_flow,
		62
	)
	cancel.custom_minimum_size = Vector2(360, 62)
	box.add_child(cancel)


func _show_room() -> void:
	_set_state(FlowState.ROOM)
	_clear_screen()
	_build_background(0.06)
	_add_header(Vector2(115, 22), Vector2(490, 245))

	var info := PanelContainer.new()
	info.position = Vector2(38, 250)
	info.size = Vector2(644, 98)
	info.add_theme_stylebox_override("panel", _panel_style(Color("#fff0d8ee"), Color("#d48a3a"), 18))
	_screen_root.add_child(info)
	var info_text := _make_label(
		"房间号：%s    |    经典对弈\n规则：%s · v%s" % [
			str(_match.get("room_id", "")),
			str(_product.get("rule_set_id", "standard")),
			str(_product.get("rule_version", "1.0.0"))
		],
		16,
		Color("#66321f")
	)
	info.add_child(info_text)

	var seats := HBoxContainer.new()
	seats.position = Vector2(38, 370)
	seats.size = Vector2(644, 210)
	seats.add_theme_constant_override("separation", 18)
	_screen_root.add_child(seats)

	var red_card := _create_seat_card("红方", true)
	seats.add_child(red_card)
	var black_card := _create_seat_card("黑方", false)
	seats.add_child(black_card)

	var board_panel := PanelContainer.new()
	board_panel.position = Vector2(115, 605)
	board_panel.size = Vector2(490, 330)
	board_panel.add_theme_stylebox_override("panel", _panel_style(Color("#72462be8"), Color("#f0c178"), 20))
	_screen_root.add_child(board_panel)
	var board_preview := TextureRect.new()
	board_preview.texture = _load_png_texture(BOARD_PREVIEW_PATH, Color("#c58b50"))
	board_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	board_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	board_panel.add_child(board_preview)

	var chat := PanelContainer.new()
	chat.position = Vector2(36, 952)
	chat.size = Vector2(648, 108)
	chat.add_theme_stylebox_override("panel", _panel_style(Color("#301b12d9"), Color("#a66a3d"), 16))
	_screen_root.add_child(chat)
	var chat_text := _make_label(
		"棋友：大家好！ 👋    系统：双方进入同一房间后，准备即可开局。\n快捷：  好棋！   加油！   再来一局！",
		13,
		Color("#f7ddbb")
	)
	chat_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chat.add_child(chat_text)

	var actions := HBoxContainer.new()
	actions.position = Vector2(30, 1080)
	actions.size = Vector2(660, 96)
	actions.add_theme_constant_override("separation", 10)
	_screen_root.add_child(actions)
	var exit_button := _make_action_button(
		"退出房间",
		UI_ROOT + "icon_exit.png",
		Color("#a75f3d"),
		Color("#dda170"),
		_on_cancel_flow,
		80
	)
	exit_button.custom_minimum_size = Vector2(200, 80)
	actions.add_child(exit_button)
	var invite_button := _make_action_button(
		"邀请好友",
		UI_ROOT + "icon_invite.png",
		Color("#42b86e"),
		Color("#8edaa4"),
		_on_invite_friend,
		80
	)
	invite_button.custom_minimum_size = Vector2(210, 80)
	actions.add_child(invite_button)
	_room_ready_button = _make_action_button(
		"准备",
		UI_ROOT + "icon_ready.png",
		Color("#e8a928"),
		Color("#ffe185"),
		_on_room_ready,
		80
	)
	_room_ready_button.custom_minimum_size = Vector2(230, 80)
	actions.add_child(_room_ready_button)

	_room_ready_count_label = _make_label("", 14, Color("#ffe3b0"))
	_room_ready_count_label.position = Vector2(135, 1180)
	_room_ready_count_label.size = Vector2(450, 42)
	_screen_root.add_child(_room_ready_count_label)

	_room_status_label = _make_label("", 14, Color("#fff2da"))
	_room_status_label.position = Vector2(60, 1215)
	_room_status_label.size = Vector2(600, 42)
	_screen_root.add_child(_room_status_label)

	_refresh_room_ui()
	_poll_timer.start()

	if _auto_flow:
		call_deferred("_on_room_ready")


func _create_seat_card(title_text: String, is_red: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(313, 205)
	var bg := Color("#fff2d9ed") if is_red else Color("#ede6dced")
	var border := Color("#d9533f") if is_red else Color("#4d3a32")
	card.add_theme_stylebox_override("panel", _panel_style(bg, border, 20))
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)

	var side := _make_label(title_text, 23, Color("#b52f25") if is_red else Color("#28201c"))
	box.add_child(side)

	var avatar := TextureRect.new()
	avatar.texture = _load_ui_texture(MASCOT_PATH)
	avatar.custom_minimum_size = Vector2(95, 95)
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(avatar)

	var player := _make_label("等待玩家", 14, Color("#5d483c"))
	box.add_child(player)
	if is_red:
		_room_red_label = player
	else:
		_room_black_label = player
	return card


func _refresh_room_ui() -> void:
	if _room_red_label == null:
		return
	var red_id := str(_match.get("red_account_id", ""))
	var black_id := str(_match.get("black_account_id", ""))
	_room_red_label.text = _room_player_text(red_id, "红方")
	_room_black_label.text = _room_player_text(black_id, "黑方")
	var ready_players := int(_match.get("ready_players", 0))
	_room_ready_count_label.text = "准备状态：%d / 2" % ready_players
	var seat := str(_match.get("seat_color", ""))
	var seat_name := "红方" if seat == "red" else "黑方"
	_room_status_label.text = "你的座位：%s · %s" % [
		seat_name,
		"已准备，等待对手…" if _local_ready else "点击“准备”进入开局等待"
	]
	_room_ready_button.text = "已准备" if _local_ready else "准备"
	_room_ready_button.disabled = _local_ready
	print("ROOM_SEAT=%s room=%s ready=%s" % [seat, str(_match.get("room_id", "")), str(ready_players)])


func _room_player_text(account_id: String, fallback: String) -> String:
	if account_id == "":
		return "等待棋友进入"
	if account_id == str(_account.get("account_id", "")):
		return "%s · 我方" % fallback
	var short_id := account_id.right(6) if account_id.length() > 6 else account_id
	return "棋友 %s" % short_id


func _request_health() -> void:
	if _http_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	if _state != FlowState.BOOT:
		_show_boot()
	_request_kind = "boot"
	var error := _http_request.request(_api.health_url())
	if error != OK:
		_show_boot_error("无法发起健康检查，错误码=%s" % str(error))


func _on_wechat_login() -> void:
	if _status_label != null:
		_status_label.text = "微信登录接口已预留，当前开发验证请使用“游客登录”。"


func _on_guest_login() -> void:
	if _state != FlowState.LOGIN:
		return
	if not _apply_server_field():
		return
	if _terms_checkbox != null and not _terms_checkbox.button_pressed:
		_status_label.text = "请先勾选并同意《用户协议》和《隐私政策》。"
		return
	_primary_button.disabled = true
	_status_label.text = "正在创建统一游客 AccountId……"
	_request_kind = "login"
	var headers := PackedStringArray(["Content-Type: application/json"])
	var error := _http_request.request(
		_api.guest_login_url(),
		headers,
		HTTPClient.METHOD_POST,
		"{}"
	)
	if error != OK:
		_primary_button.disabled = false
		_status_label.text = "登录请求发送失败，错误码=%s" % str(error)


func _on_quick_match() -> void:
	if _state != FlowState.LOBBY:
		return
	_local_ready = false
	_match = {}
	_show_matching()
	_request_match()


func _on_poll_timer() -> void:
	if _state == FlowState.MATCHING:
		_request_match()
	elif _state == FlowState.ROOM:
		if _local_ready:
			_request_ready()
		else:
			_request_room_poll()


func _request_match() -> void:
	if _http_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_poll_timer.start()
		return
	var account_id := str(_account.get("account_id", ""))
	if account_id == "":
		if _status_label != null:
			_status_label.text = "账号状态丢失，请重新登录。"
		return
	_request_kind = "match" if _state == FlowState.MATCHING else "room_poll"
	var payload := {
		"account_id": account_id,
		"product_id": str(_product.get("product_id", "")),
		"game_id": str(_product.get("game_id", "")),
		"rule_set_id": str(_product.get("rule_set_id", "")),
		"rule_version": str(_product.get("rule_version", "")),
	}
	_post_json(_api.quick_match_url(), payload)


func _request_room_poll() -> void:
	_request_match()


func _on_room_ready() -> void:
	if _state != FlowState.ROOM or _local_ready:
		return
	_local_ready = true
	_refresh_room_ui()
	_request_ready()


func _request_ready() -> void:
	if _state != FlowState.ROOM:
		return
	if _http_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_poll_timer.start()
		return
	_request_kind = "ready"
	_post_json(_api.room_ready_url(), {
		"account_id": str(_account.get("account_id", "")),
		"room_id": str(_match.get("room_id", "")),
	})


func _on_cancel_flow() -> void:
	if _state != FlowState.MATCHING and _state != FlowState.ROOM:
		return
	# --auto-flow is used to keep two local review clients in one match while
	# the user's keyboard focus may be on a game window during development.
	if _auto_flow:
		return
	_poll_timer.stop()
	if str(_account.get("account_id", "")) == "":
		_match = {}
		_local_ready = false
		_show_lobby()
		return
	if _http_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_http_request.cancel_request()
	_request_kind = "cancel"
	_post_json(_api.cancel_match_url(), {
		"account_id": str(_account.get("account_id", "")),
	})


func _on_invite_friend() -> void:
	var room_id := str(_match.get("room_id", ""))
	if room_id != "":
		DisplayServer.clipboard_set(room_id)
		if _room_status_label != null:
			_room_status_label.text = "房间号 %s 已复制，可以发送给好友。" % room_id


func _on_lobby_feature(feature: String) -> void:
	if feature == "双人训练" or feature == "走子练习":
		_enter_training()
		return
	if _status_label != null:
		_status_label.text = "%s 已进入一期功能规划；当前请体验“快速对局”。" % feature


func _enter_training() -> void:
	if _state != FlowState.LOBBY:
		return
	_set_state(FlowState.GAME)
	_clear_screen()
	var screen_script = load("res://modules/games/chinese_chess/chinese_chess_3d_screen.gd")
	if screen_script == null:
		_show_lobby()
		return
	var screen = screen_script.new()
	screen.product = _product
	screen.training_mode = true
	screen.match_context = {
		"room_id": "训练", "account_id": str(_account.get("account_id", "")),
		"display_name": str(_account.get("display_name", "我")),
		"opponent_display_name": "同机练习"
	}
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.request_return_to_lobby.connect(_on_game_return_to_lobby)
	_screen_root.add_child(screen)


func _on_info_tool(tool_name: String) -> void:
	if _status_label != null:
		_status_label.text = "%s：一期界面入口已预留。" % tool_name


func _post_json(url: String, payload: Dictionary) -> void:
	var headers := PackedStringArray(["Content-Type: application/json"])
	var error := _http_request.request(
		url,
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if error != OK:
		_handle_request_error("请求发送失败，错误码=%s" % str(error))


func _on_http_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	var body_text := body.get_string_from_utf8()
	var parsed = JSON.parse_string(body_text) if body_text != "" else {}

	if result != HTTPRequest.RESULT_SUCCESS:
		_handle_request_error("网络请求失败，结果码=%s" % str(result))
		return
	if response_code < 200 or response_code >= 300:
		var message := "HTTP %s" % str(response_code)
		if typeof(parsed) == TYPE_DICTIONARY and str(parsed.get("error", "")) != "":
			message = str(parsed.get("error", ""))
		_handle_request_error(message)
		return

	match _request_kind:
		"boot":
			_show_login()
		"login":
			if typeof(parsed) != TYPE_DICTIONARY or str(parsed.get("account_id", "")) == "":
				_handle_request_error("登录响应缺少 AccountId")
				return
			_account = parsed
			_show_lobby()
		"match":
			_handle_match_response(parsed)
		"room_poll":
			_handle_match_response(parsed)
		"ready":
			_handle_ready_response(parsed)
		"cancel":
			_match = {}
			_local_ready = false
			_show_lobby()


func _handle_match_response(parsed) -> void:
	if typeof(parsed) != TYPE_DICTIONARY:
		_handle_request_error("匹配响应格式错误")
		return
	_match = parsed
	var status := str(parsed.get("status", ""))
	if bool(parsed.get("start", false)):
		_poll_timer.stop()
		_enter_game()
		return
	if status == "matched":
		_poll_timer.stop()
		if _state != FlowState.ROOM:
			_show_room()
		else:
			_refresh_room_ui()
			_poll_timer.start()
		return

	# waiting：第一个玩家或对手退出后继续等待。
	if _state == FlowState.ROOM:
		_local_ready = false
		_show_matching()
	if _status_label != null:
		_status_label.text = "等待棋友…… 当前房间 %s，玩家 %s/2" % [
			str(parsed.get("room_id", "")),
			str(parsed.get("players", 1))
		]
	_poll_timer.start()


func _handle_ready_response(parsed) -> void:
	if typeof(parsed) != TYPE_DICTIONARY:
		_handle_request_error("准备响应格式错误")
		return
	var ready_players := int(parsed.get("ready_players", 0))
	_match["ready_players"] = ready_players
	if bool(parsed.get("start", false)):
		_match["start"] = true
		_poll_timer.stop()
		_enter_game()
		return
	_refresh_room_ui()
	_poll_timer.start()


func _handle_request_error(message: String) -> void:
	match _request_kind:
		"boot":
			_show_boot_error(message)
		"login":
			if _primary_button != null:
				_primary_button.disabled = false
			if _status_label != null:
				_status_label.text = "登录失败：%s" % message
		"match", "room_poll":
			if _status_label != null:
				_status_label.text = "匹配暂时失败：%s，稍后自动重试。" % message
			_poll_timer.start()
		"ready":
			_local_ready = false
			if _room_status_label != null:
				_room_status_label.text = "准备失败：%s" % message
			_refresh_room_ui()
		"cancel":
			if _room_status_label != null:
				_room_status_label.text = "退出房间失败：%s" % message


func _enter_game() -> void:
	var room_id := str(_match.get("room_id", ""))
	if room_id == "":
		if _room_status_label != null:
			_room_status_label.text = "匹配结果缺少 RoomId，无法进入对局。"
		return

	_set_state(FlowState.GAME)
	_poll_timer.stop()
	_clear_screen()

	var game_id := str(_product.get("game_id", ""))
	var script_path := ""
	if game_id == "chinese_chess":
		script_path = "res://modules/games/chinese_chess/chinese_chess_3d_screen.gd"
	elif game_id == "mahjong":
		script_path = "res://modules/games/mahjong/guiyang/guiyang_3d_screen.gd"
	else:
		push_error("当前产品没有可运行的游戏表现模块：%s" % game_id)
		_show_lobby()
		return

	var screen_script = load(script_path)
	if screen_script == null:
		push_error("未找到游戏界面模块：%s" % script_path)
		_show_lobby()
		return

	var screen = screen_script.new()
	screen.set("product", _product)
	if game_id == "chinese_chess":
		var own_color := str(_match.get("seat_color", ""))
		var opponent_id := str(_match.get("red_account_id", "")) if own_color == "black" else str(_match.get("black_account_id", ""))
		screen.set("match_context", {
			"room_id": room_id,
			"account_id": str(_account.get("account_id", "")),
			"display_name": str(_account.get("display_name", "游客")),
			"opponent_display_name": "棋友-" + opponent_id.right(6) if opponent_id != "" else "对手",
			"seat_color": own_color,
		})
		if screen.has_signal("request_return_to_lobby"):
			screen.connect("request_return_to_lobby", _on_game_return_to_lobby)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_root.add_child(screen)
	print("FLOW_ROOM=%s" % room_id)


func _on_game_return_to_lobby() -> void:
	# 对局结算返回大厅时清空当前房间上下文，但保留已登录 AccountId。
	_match = {}
	_local_ready = false
	_show_lobby()
