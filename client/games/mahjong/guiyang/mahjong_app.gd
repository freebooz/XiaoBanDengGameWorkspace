extends Control
## 小板凳麻将独立产品壳：大厅与等候房消费服务端事件。

const API_SCRIPT = preload("res://modules/foundation/network/api_client.gd")
const ART := "res://modules/games/mahjong/guiyang/assets/"
const GAME_SCRIPT := "res://modules/games/mahjong/guiyang/guiyang_3d_screen.gd"
const BATTLE_DISPLAY := preload("res://modules/foundation/ui/battle_display.gd")
const LOBBY_SCRIPT := "res://modules/games/mahjong/guiyang/mahjong_lobby_view.gd"
const TRANSPORT := preload("res://modules/games/mahjong/guiyang/mahjong_transport.gd")
const GUEST_SESSIONS := preload("res://modules/games/mahjong/guiyang/mahjong_guest_sessions.gd")
const LOGIN_THEME := preload("res://modules/games/mahjong/guiyang/mahjong_rural_theme.gd")
const MODAL_THEME := preload("res://modules/games/mahjong/guiyang/mahjong_rural_modal.gd")
const GUEST_VIEW := preload("res://modules/games/mahjong/guiyang/mahjong_guest_identity_view.gd")
const LOGIN_VIEW := preload("res://modules/games/mahjong/guiyang/mahjong_login_view.gd")
const ERROR_VIEW := preload("res://modules/games/mahjong/guiyang/mahjong_error_view.gd")
const SETTINGS := preload("res://modules/games/mahjong/guiyang/mahjong_settings_view.gd")
const LOGIN_ART := preload(ART + "ui/series/xbd_mahjong_welcome.png")
const LOGIN_LANDSCAPE := preload(ART + "ui/series/rural_lobby_banner.png")
const LOGIN_ASSETS := ART + "ui/login_rural/"
const LOGIN_BUTTON_ART := {
	"wechat": preload(LOGIN_ASSETS + "button_wechat.svg"),
	"phone": preload(LOGIN_ASSETS + "button_phone.svg"),
	"guest": preload(LOGIN_ASSETS + "button_guest.svg"),
	"account": preload(LOGIN_ASSETS + "button_account.svg"),
	"enter": preload(LOGIN_ASSETS + "button_enter.svg"),
}
const LOGIN_ICONS := {
	"wechat": preload(LOGIN_ASSETS + "icon_wechat.svg"),
	"phone": preload(LOGIN_ASSETS + "icon_phone.svg"),
	"guest": preload(LOGIN_ASSETS + "icon_person.svg"),
	"account": preload(LOGIN_ASSETS + "icon_person.svg"),
	"exit": preload(LOGIN_ASSETS + "icon_power.svg"),
}
const LOGIN_EYE := preload(LOGIN_ASSETS + "icon_eye.svg")
const LOGIN_EYE_OFF := preload(LOGIN_ASSETS + "icon_eye_off.svg")
const LOGIN_LOCK := preload(LOGIN_ASSETS + "icon_lock.svg")
const AUDIO := preload("res://modules/games/mahjong/guiyang/mahjong_audio.gd")
const LOGIN_CREAM := Color("#fff0d9")
const LOGIN_METAL := Color("#ad815c")
const RECENT_LIMIT := 12
const DEFAULT_SERVER_URL := "https://api.xbd.freeboozstudio.test"

var _error_dialog: Control
var _error_code := ""
var _error_restore_focus: WeakRef
var _page_revision := 0

var _api
var _product: Dictionary = {}
var _account: Dictionary = {}
var _match: Dictionary = {}
var _screen: Control
var _game: Control
var _audio: Node
var _login_margin: MarginContainer
var _login_layout: BoxContainer
var _login_header: VBoxContainer
var _login_logo: TextureRect
var _login_art: TextureRect
var _login_tray: PanelContainer
var _login_pad: MarginContainer
var _login_content: VBoxContainer
var _login_form_intro: VBoxContainer
var _login_form_columns: BoxContainer
var _login_form_fields: VBoxContainer
var _login_form_actions: VBoxContainer
var _login_form_title: Label
var _login_title_clearance: Control
var _login_footer: Label
var _login_form_back: Button
var _entry_buttons: Array[Button] = []
var _guest_identity_view: Control
var _lobby_entry: Button
var _connected_server := ""
var _guest_save_error: Error = OK
var _login_identifier: LineEdit
var _login_secret: LineEdit
var _remember_identifier: CheckBox
var _submit_account: Button
var _request_identifier := ""
var account_preferences_path := "user://mahjong_account_login.cfg"
var _http: HTTPRequest
var _state := "boot"
var _request_kind := ""
var _request_server := ""
var _request_token := ""
var session_store_path := GUEST_SESSIONS.DIRECTORY
var _sessions: RefCounted
var _saved_token := ""
var _session_token := ""
var _session_server := ""
var _next_session_probe_tick := 0
var _auto_flow := false
var _status: Label
var _guest_button: Button
var _connect_button: Button
var _lobby_view: Control
var _exit_dialog: Control
var _egg_request: HTTPRequest
var _egg_balance := -1
var _egg_request_generation := 0
var _wallet_session_generation := 0
var _board_return_route: Dictionary = {}
var _lobby_socket: Node
var _lobby_deadline: Timer
var _room_directory_deadline: Timer
var _lobby_synced := false
var _lobby_connecting := false
var _lobby_message := "正在连接麻将大厅……"
var _lobby_command_error := ""
var _room_directory_open := false
var _room_directory_available := false
var _room_directory_loaded := false
var _room_directory_request := 0
var _room_directory_error := ""
var _public_rooms: Array = []
var _spectator_supported := false
var _pending_watch: Dictionary = {}
var _watch_return_message := ""
var _presets: Array = []
var _selected_rule: Dictionary = {}
var _pending_lobby_id := ""
var _lobby_command_acked := false
var _lobby_command_serial := 0
var _enter_when_ready := false
var _auto_match_sent := false
var _recent: Array = []
var _local_recent: Array[Dictionary] = []
var _remote_recent: Array[Dictionary] = []
var _seen_results: Dictionary = {}
var _history_http: HTTPRequest
var _history_generation := 0
var _history_refresh_pending := false
var _history_loaded := false
var _history_cursor := ""
var _history_extra: Array[Dictionary] = []
var _history_extra_loaded := false
var _history_open := false
var _history_detail_id := ""
var _history_detail: Dictionary = {}
var _history_replay_open := false
var _history_replay: Dictionary = {}
var _history_error := ""
var _history_page_http: HTTPRequest
var _history_page_generation := 0
var _privacy_open := false
var _privacy_review := false
var _privacy_acknowledged := false
var _privacy_error := ""
var _account_http: HTTPRequest
var _account_request := ""
var _account_request_generation := 0
var _account_session_expired := false
var _training_to_abandon := ""
var _finished_friend_return: Dictionary = {}
var _rematch_window_match_id := ""


func _ready() -> void:
	# Responsive menus use actual viewport units; the battle display restores this on exit.
	get_window().content_scale_size = Vector2i.ZERO
	if OS.has_feature("mobile"):
		get_tree().quit_on_go_back = false
	var file := FileAccess.open("res://product.json", FileAccess.READ)
	if file != null:
		var parsed = JSON.parse_string(file.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			_product = parsed
	var configured_server := str(ProjectSettings.get_setting("xiaobandeng/network/default_server_url", DEFAULT_SERVER_URL)).strip_edges()
	_api = API_SCRIPT.new(DEFAULT_SERVER_URL if configured_server.is_empty() else configured_server)
	_sessions = GUEST_SESSIONS.new(session_store_path)
	_auto_flow = "--auto-flow" in OS.get_cmdline_user_args()
	_screen = Control.new()
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_screen)
	_screen.resized.connect(_layout_screen)
	_audio = AUDIO.new()
	add_child(_audio)
	_http = HTTPRequest.new()
	_http.timeout = 7.0
	_http.max_redirects = 0
	_http.request_completed.connect(_on_response)
	add_child(_http)
	_lobby_socket = TRANSPORT.new()
	add_child(_lobby_socket)
	_lobby_socket.opened.connect(_on_lobby_open)
	_lobby_socket.connection_lost.connect(_on_lobby_lost)
	_lobby_socket.session_expired.connect(_on_live_session_expired)
	_lobby_socket.packet_received.connect(_on_lobby_packet)
	_lobby_deadline = Timer.new()
	_lobby_deadline.one_shot = true
	_lobby_deadline.timeout.connect(_on_lobby_deadline)
	add_child(_lobby_deadline)
	_room_directory_deadline = Timer.new()
	_room_directory_deadline.one_shot = true
	_room_directory_deadline.timeout.connect(_on_room_directory_deadline)
	add_child(_room_directory_deadline)
	_show_login(false)
	_request_health()


func _reset(next_state: String, background: Texture2D = null) -> void:
	_clear_error_dialog()
	_page_revision += 1
	if _room_directory_open:
		_set_room_directory(false)
	_state = next_state
	_close_history_page()
	_close_privacy_page()
	_game = null
	_login_margin = null
	_login_header = null
	_login_footer = null
	_login_form_back = null
	_login_form_intro = null
	_login_form_columns = null
	_login_form_fields = null
	_login_form_actions = null
	_login_form_title = null
	_login_title_clearance = null
	_entry_buttons.clear()
	_guest_identity_view = null
	_lobby_entry = null
	if is_instance_valid(_login_secret): _login_secret.clear()
	_login_identifier = null
	_login_secret = null
	_remember_identifier = null
	_submit_account = null
	for child in _screen.get_children():
		if child is CanvasItem: child.hide()
		child.queue_free()
	_status = null
	_guest_button = null
	_connect_button = null
	_lobby_view = null
	_exit_dialog = null
	print("MAHJONG_FLOW=%s" % next_state)
	if background == null: return
	var image := TextureRect.new()
	image.name = "MahjongLoginArtwork"
	image.texture = background
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(image)
	_login_art = image


func _label(value: String, x: float, y: float, width: float, height: float, size: int = 24, color: Color = Color("#f9e9c5")) -> Label:
	var node := Label.new()
	node.text = value
	node.position = Vector2(x, y)
	node.size = Vector2(width, height)
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	_screen.add_child(node)
	return node


func _login_button(parent: Container, value: String, height: float, action: Callable, primary: bool = false) -> Button:
	var node := Button.new()
	node.text = value
	node.custom_minimum_size.y = height
	LOGIN_THEME.skin_button(node, primary)
	node.add_theme_font_size_override("font_size", 32 if primary else 21)
	node.pressed.connect(action)
	parent.add_child(node)
	return node


func _skin_login_secondary(button: Button) -> void:
	LOGIN_THEME.CAPTION.attach(button)
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var fill := Color("#563820c7")
		var edge := LOGIN_METAL
		match state:
			"hover": fill = Color("#775135e2")
			"pressed", "hover_pressed": fill = Color("#2b190fed")
			"focus":
				fill = Color.TRANSPARENT
				edge = LOGIN_CREAM
		var skin := LOGIN_THEME.frame(fill, edge, 22, 1)
		skin.shadow_size = 0
		button.add_theme_stylebox_override(state, skin)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, LOGIN_CREAM)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _skin_login_option(button: Button, kind: String) -> void:
	if kind == "exit":
		MODAL_THEME.button(button)
		button.add_theme_constant_override("h_separation", 10)
		button.add_theme_constant_override("icon_max_width", 34)
		button.expand_icon = true
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		return
	LOGIN_THEME.CAPTION.attach(button)
	var surface: Texture2D = LOGIN_BUTTON_ART[kind]
	var dark_ink := kind in ["phone", "guest"]
	var ink := Color("#354c56") if kind == "guest" else Color("#6a4328") if dark_ink else LOGIN_CREAM
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var tint := Color.WHITE
		match state:
			"hover": tint = Color(1.06, 1.04, 1.02)
			"pressed", "hover_pressed": tint = Color("#d7c5ab")
			"disabled": tint = Color("#d4cdc1")
		var box := MODAL_THEME.button_frame(surface, Vector4(8, 8, 8, 8), tint)
		button.add_theme_stylebox_override(state, box)
	var focus := LOGIN_THEME.frame(Color.TRANSPARENT, Color("#fff7ce"), 28, 2)
	focus.shadow_size = 0
	button.add_theme_stylebox_override("focus", focus)
	for style in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		button.add_theme_color_override(style, ink)
	button.add_theme_constant_override("h_separation", 10)
	button.add_theme_constant_override("icon_max_width", 38)
	button.expand_icon = true
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _login_entry(parent: Container, title: String, kind: String, handler: Callable = Callable()) -> Button:
	var button := Button.new()
	button.text = title
	button.icon = LOGIN_ICONS.get(kind)
	_skin_login_option(button, kind)
	button.custom_minimum_size.y = 67
	button.add_theme_font_size_override("font_size", 27)
	if handler.is_valid():
		button.pressed.connect(handler)
	else:
		button.disabled = true
		button.tooltip_text = "此版本暂不支持" + title
	parent.add_child(button)
	_entry_buttons.append(button)
	return button


func _login_asset(file_name: String, fallback: Texture2D) -> Texture2D:
	var path := LOGIN_ASSETS + file_name
	return load(path) as Texture2D if ResourceLoader.exists(path) else fallback


func _build_login_tray() -> VBoxContainer:
	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(margins)
	_login_margin = margins
	var scroll := ScrollContainer.new()
	scroll.name = "MahjongLoginScroll"
	# A temporary vertical scrollbar during a resize must not widen the form.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	margins.add_child(scroll)
	var layout := BoxContainer.new()
	layout.vertical = true
	layout.name = "MahjongLoginLayout"
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll.add_child(layout)
	_login_layout = layout
	_login_title_clearance = Control.new()
	_login_title_clearance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_login_title_clearance.hide()
	layout.add_child(_login_title_clearance)
	_login_header = VBoxContainer.new()
	layout.add_child(_login_header)
	_login_logo = _login_brand()
	_screen.add_child(_login_logo)
	var motto := Label.new()
	motto.text = "◇  乡里麻将 · 亲友对局 · 轻松娱乐  ◇"
	motto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	motto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	motto.add_theme_color_override("font_color", Color("#ffe7b8"))
	motto.add_theme_color_override("font_outline_color", Color("#463023"))
	motto.add_theme_constant_override("outline_size", 5)
	motto.add_theme_font_size_override("font_size", 22)
	_login_header.add_child(motto)
	var tray: PanelContainer = MODAL_THEME.village_panel(layout)
	tray.name = "MahjongLoginTray"
	_login_tray = tray
	var pad := MarginContainer.new()
	tray.add_child(pad)
	_login_pad = pad
	var content := VBoxContainer.new()
	pad.add_child(content)
	_login_content = content
	_login_footer = Label.new()
	_login_footer.name = "MahjongLoginCopyright"
	_login_footer.text = "© Freeboozstudio 工作室 版权所有"
	_login_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_login_footer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_login_footer.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_login_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_login_footer.add_theme_font_size_override("font_size", 19)
	_login_footer.add_theme_color_override("font_color", LOGIN_CREAM)
	var footer_surface := StyleBoxFlat.new()
	footer_surface.bg_color = Color("#2c2119dc")
	_login_footer.add_theme_stylebox_override("normal", footer_surface)
	_screen.add_child(_login_footer)
	_login_footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_layout_screen()
	return content


func _login_brand() -> TextureRect:
	var sign := TextureRect.new()
	sign.name = "MahjongLoginBrandLogo"
	sign.texture = _login_asset("sign.png", LOGIN_THEME.MAHJONG_BRAND)
	sign.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sign.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sign


func _layout_screen() -> void:
	if not is_instance_valid(_screen): return
	_center_exit_dialog()
	var safe := LOGIN_THEME.safe_insets(_screen)
	if is_instance_valid(_login_form_back):
		var hit := MODAL_THEME.size_icon_button(_login_form_back, _screen)
		_login_form_back.offset_left = -safe.z - hit - 14
		_login_form_back.offset_right = -safe.z - 14
		_login_form_back.offset_top = safe.y + 14
		_login_form_back.offset_bottom = safe.y + 14 + hit
	if not is_instance_valid(_login_margin): return
	var viewport_size := _screen.size
	var touch := LOGIN_THEME.touch_extent(_screen)
	var available := viewport_size - Vector2(safe.x + safe.z, safe.y + safe.w)
	var compact := LOGIN_THEME.compact_entry_landscape(available)
	var wide := not compact and available.x >= 900.0 and (available.x >= available.y * 1.5 or available.y < 1100.0)
	var roomy := available.x >= (1380.0 if wide else 780.0) and available.y >= (1050.0 if wide else 1250.0)
	var form_width := minf(740.0, available.x - 40.0)
	var edge := maxf(20.0, (available.x - form_width) * 0.5)
	_login_margin.offset_left = edge + safe.x
	_login_margin.offset_right = -edge - safe.z
	var logo_width := 72.0 if compact else minf(available.x * 0.34, clampf(available.y * 0.20, 120.0, 220.0))
	_login_logo.size = Vector2(logo_width, logo_width / _login_logo.texture.get_size().aspect())
	_login_logo.position = Vector2(safe.x + 12.0, safe.y + 8.0)
	var top := 26.0 if compact else clampf(viewport_size.y * 0.045, 20.0, 64.0)
	if not compact and edge < 20.0 + logo_width:
		top = maxf(top, 16.0 + _login_logo.size.y)
	_login_margin.offset_top = safe.y + top
	var unit := minf(form_width / 740.0, 1.0)
	var entry_height := maxf(touch, 52.0 if compact else (116.0 if roomy else 60.0))
	var requested_entry_width := 224.0 if compact else (600.0 if roomy else (420.0 if wide else 242.0))
	var entry_width := minf(requested_entry_width, (form_width - 92.0) * 0.5 if compact else form_width - 104.0)
	var footer_height := 32.0 if compact else 43.0
	_login_footer.offset_left = safe.x
	_login_footer.offset_right = -safe.z
	_login_footer.offset_top = -safe.w - footer_height
	_login_footer.offset_bottom = -safe.w
	_login_margin.offset_bottom = -safe.w - footer_height - (4.0 if compact else 8.0)
	_login_layout.add_theme_constant_override("separation", 14)
	_login_header.visible = not compact and (not wide or available.y >= 760.0)
	_login_title_clearance.visible = compact
	if is_instance_valid(_login_form_title):
		_login_form_title.add_theme_font_size_override("font_size", 23 if compact else 28)
		_login_form_title.get_parent().custom_minimum_size.y = 50.0 if compact else 61.0
	_login_tray.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_login_tray.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_login_tray.custom_minimum_size.x = form_width
	var motto := _login_header.get_child(0) as Label
	motto.add_theme_font_size_override("font_size", 18 if form_width < 420.0 else 22)
	for side in ["left", "right"]: _login_pad.add_theme_constant_override("margin_" + side, 12 if compact else 22)
	_login_pad.add_theme_constant_override("margin_top", 0 if compact else 13)
	_login_pad.add_theme_constant_override("margin_bottom", 0 if compact else 14)
	var row_gap := roundi(maxf(8.0, 12.0 * unit))
	# A short landscape viewport keeps full-size fields and the paper rim;
	# reclaim space between rows rather than shrinking readable bold glyphs.
	if wide and viewport_size.y < 800.0:
		row_gap = 8
	if compact: row_gap = 4
	_login_content.add_theme_constant_override("separation", row_gap)
	_login_content.alignment = BoxContainer.ALIGNMENT_BEGIN
	var fields: Container = _login_content
	if is_instance_valid(_login_form_columns):
		_login_form_intro.visible = not compact
		_login_form_columns.vertical = not compact
		_login_form_columns.add_theme_constant_override("separation", 18 if compact else row_gap)
		for section in [_login_form_intro, _login_form_fields, _login_form_actions]:
			section.add_theme_constant_override("separation", row_gap)
			section.size_flags_horizontal = Control.SIZE_EXPAND_FILL if compact else Control.SIZE_FILL
			section.size_flags_vertical = Control.SIZE_SHRINK_CENTER if compact else Control.SIZE_FILL
		fields = _login_form_fields
	for child in fields.get_children():
		if child is PanelContainer and child.has_meta("account_field"):
			child.size_flags_vertical = Control.SIZE_FILL
			child.custom_minimum_size.y = maxf(touch, 68.0 if compact else maxf(76.0, 90.0 * unit))
			var field_style: StyleBox = child.get_theme_stylebox("panel")
			field_style.set_content_margin(SIDE_TOP, 5.0 if compact else 8.0)
			field_style.set_content_margin(SIDE_BOTTOM, 5.0 if compact else 8.0)
	if _state == "account_register" and is_instance_valid(_login_secret):
		_login_secret.placeholder_text = "8–128位" if compact or form_width < 420.0 else "输入 8–128 个字符"
	_login_art.texture = MODAL_THEME.VILLAGE_LANDSCAPE if available.x >= available.y * 0.85 else MODAL_THEME.LOGIN_BACKDROP
	for button in _entry_buttons:
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.size_flags_vertical = Control.SIZE_FILL
		button.custom_minimum_size = Vector2(maxf(touch, entry_width), entry_height)
		button.add_theme_font_size_override("font_size", clampi(roundi(entry_height * 0.39), 22, 30))
	if touch > 0.0:
		for button: BaseButton in _login_content.find_children("*", "BaseButton", true, false):
			if button in _entry_buttons: continue
			var base: Vector2 = button.get_meta("login_minimum", button.custom_minimum_size)
			button.set_meta("login_minimum", base)
			button.custom_minimum_size = base.max(Vector2.ONE * touch)


func _add_login_status(parent: Container, message: String) -> void:
	_status = Label.new()
	_status.name = "MahjongLoginStatus"
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 19)
	parent.add_child(_status)
	_set_login_status(message)


func _set_login_status(message: String, failed: bool = false, error_code := "", retry_action := Callable()) -> void:
	if not is_instance_valid(_status): return
	_status.text = message
	_status.visible = not message.is_empty()
	var dark_panel := _state in ["login", "account_login", "account_register"]
	var ink := Color("#963d28") if dark_panel else Color("#ffd7c0")
	var normal := LOGIN_THEME.INK if dark_panel else Color("#dbe8bc")
	_status.add_theme_color_override("font_color", ink if failed else normal)
	if failed and not message.is_empty():
		_present_error(message, error_code, retry_action)


func _clear_error_dialog() -> void:
	if is_instance_valid(_error_dialog):
		_error_dialog.hide()
		_error_dialog.queue_free()
	_error_dialog = null
	_error_code = ""
	_error_restore_focus = null


func _present_error(message: String, code := "", retry_action := Callable()) -> void:
	if not is_instance_valid(_screen): return
	var focused := get_viewport().gui_get_focus_owner()
	var prior_focus: WeakRef = _error_restore_focus if is_instance_valid(_error_dialog) else (weakref(focused) if is_instance_valid(focused) else null)
	_clear_error_dialog()
	var dialog := ERROR_VIEW.new()
	var revision := _page_revision
	var gateway: String = _api.base_url
	_error_dialog = dialog
	_error_code = code
	_error_restore_focus = prior_focus
	dialog.z_index = 20
	_screen.add_child(dialog)
	var guarded_retry := Callable()
	if retry_action.is_valid():
		guarded_retry = func():
			if revision == _page_revision and gateway == _api.base_url:
				retry_action.call()
	dialog.build(message, code, guarded_retry, func():
		if _error_dialog != dialog: return
		_error_dialog = null
		_error_code = ""
		_error_restore_focus = null
		var focus: Control = prior_focus.get_ref() if prior_focus != null else null
		if is_instance_valid(focus) and focus.is_visible_in_tree(): focus.grab_focus())


func _dismiss_connection_error() -> void:
	if is_instance_valid(_error_dialog) and _error_code == "NET-001":
		_error_dialog.call("dismiss")


func _update_login_request_state() -> void:
	var busy := not _request_kind.is_empty()
	if is_instance_valid(_guest_button):
		_guest_button.disabled = busy or _connected_server != _api.base_url
		_guest_button.text = "继续游戏" if not _saved_token.is_empty() else "游客登录"
		if _request_kind == "restore": _guest_button.text = "正在验证会话……"
		elif _request_kind == "login": _guest_button.text = "正在登录……"
	if is_instance_valid(_connect_button):
		_connect_button.visible = not busy and _connected_server != _api.base_url
	if is_instance_valid(_submit_account): _submit_account.disabled = busy
	if is_instance_valid(_login_identifier): _login_identifier.editable = not busy
	if is_instance_valid(_login_secret): _login_secret.editable = not busy


func _request_health() -> void:
	_start_session_request("health", _api.health_url())


func _show_login(connected: bool = true) -> void:
	if connected: _connected_server = _api.base_url
	_reset("login")
	_saved_token = _sessions.read(_api.base_url)
	var view := LOGIN_VIEW.new()
	view.name = "MahjongAccountEntry"
	_screen.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.build(_remembered_account(), {
		"submit": _submit_named_account, "guest": _login,
		"wechat": func(): _set_login_status("此版本暂未配置微信登录，请使用账号或游客登录。", true),
		"forgot": func(): _set_login_status("此版本尚未提供密码找回，可选择游客登录。", true),
		"register": _show_account_registration, "exit": _confirm_exit_game,
		"retry": _request_health,
	})
	_login_art = view.background
	_login_logo = view.logo
	_login_tray = view.form
	_login_footer = view.footer
	_login_identifier = view.identifier
	_login_secret = view.secret
	_remember_identifier = view.remember
	_submit_account = view.submit
	_guest_button = view.guest
	_connect_button = view.retry
	_status = view.status
	_entry_buttons.assign([view.submit, view.wechat, view.guest])
	_set_login_status("" if _connected_server == _api.base_url else "正在连接小板凳服务……")
	_update_login_request_state()
	_layout_screen()


func _show_guest_identity() -> void:
	_reset("guest_identity")
	var view := GUEST_VIEW.new()
	view.name = "MahjongGuestIdentity"
	_screen.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.build(str(_account.get("display_name", "")), _guest_save_error == OK, _guest_identity_back, _enter_guest_lobby)
	_guest_identity_view = view
	_lobby_entry = view.enter_button


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo() and _navigate_village_back():
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST or not is_instance_valid(_screen):
		return
	if _navigate_village_back():
		return
	if _state == "login":
		_confirm_exit_game()
	elif _state not in ["lobby", "room", "guest_identity"]:
		_quit_game()


func _navigate_village_back() -> bool:
	if is_instance_valid(_exit_dialog):
		_exit_dialog.call("dismiss")
		return true
	if is_instance_valid(_error_dialog):
		_error_dialog.call("dismiss")
		return true
	if is_instance_valid(_login_form_back) and _login_form_back.is_visible_in_tree():
		_login_form_back.pressed.emit()
		return true
	if not is_instance_valid(_screen):
		return false
	var settings := _screen.get_node_or_null("MahjongGlobalSettings")
	if settings != null:
		settings.queue_free()
		return true
	if _state == "guest_identity" and is_instance_valid(_guest_identity_view):
		return _guest_identity_view.navigate_back()
	return is_instance_valid(_lobby_view) and _lobby_view.navigate_village_back()


func _login_form_heading(parent: Container, caption: String, back_name: String, go_back: Callable) -> void:
	var title := MODAL_THEME.village_title(parent, caption, _login_tray)
	_login_form_title = title
	title.add_theme_font_size_override("font_size", 28)
	var back := Button.new()
	back.name = back_name
	back.tooltip_text = "返回上一级"
	back.accessibility_name = "返回"
	MODAL_THEME.close_button(back)
	back.icon = MODAL_THEME.icon("back")
	back.pressed.connect(go_back)
	_screen.add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_login_form_back = back


func _guest_label(parent: Container, value: String, font_size: int, ink: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", MODAL_THEME.village_font())
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", ink)
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _show_account_login() -> void:
	_back_to_login()


func _show_account_registration() -> void:
	_show_account_form(true)


func _show_account_form(registering: bool) -> void:
	if not _request_kind.is_empty(): return
	_reset("account_register" if registering else "account_login", LOGIN_ART)
	var tray := _build_login_tray()
	_login_form_heading(tray, "注册新账号" if registering else "账号登录", "MahjongAccountLoginBackButton",
		_show_account_login if registering else _back_to_login)
	_login_form_intro = VBoxContainer.new()
	tray.add_child(_login_form_intro)
	_guest_label(_login_form_intro, "创建小板凳账号" if registering else "欢迎回到小板凳乡村麻将", 21, Color("#795237"))
	var credentials := _guest_label(_login_form_intro, "账号与密码" if registering else "账号密码登录", 24, LOGIN_THEME.INK)
	credentials.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_login_form_columns = BoxContainer.new()
	_login_form_columns.vertical = true
	tray.add_child(_login_form_columns)
	_login_form_fields = VBoxContainer.new()
	_login_form_columns.add_child(_login_form_fields)
	_login_form_actions = VBoxContainer.new()
	_login_form_columns.add_child(_login_form_actions)
	_login_identifier = _account_field(_login_form_fields, "账号", "请输入用户名", LOGIN_ICONS["account"], false)
	_login_identifier.name = "MahjongAccountLoginUsername"
	_login_identifier.max_length = 32
	_login_identifier.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	var remembered := _remembered_account()
	if not registering: _login_identifier.text = remembered
	_login_secret = _account_field(_login_form_fields, "密码", "输入 8–128 个字符" if registering else "请输入登录密码", LOGIN_LOCK, true)
	_login_secret.name = "MahjongAccountLoginPassword"
	_login_secret.max_length = 128
	_login_secret.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
	var helpers := HBoxContainer.new()
	_login_form_fields.add_child(helpers)
	_remember_identifier = CheckBox.new()
	_remember_identifier.name = "MahjongRememberAccount"
	_remember_identifier.text = "记住账号"
	_remember_identifier.custom_minimum_size = Vector2(112.0, 44.0)
	_remember_identifier.add_theme_font_override("font", MODAL_THEME.village_font())
	_remember_identifier.set_pressed_no_signal(not remembered.is_empty())
	_remember_identifier.add_theme_color_override("font_color", LOGIN_THEME.INK)
	_remember_identifier.add_theme_color_override("font_hover_color", LOGIN_THEME.INK)
	_remember_identifier.add_theme_font_size_override("font_size", 18)
	helpers.add_child(_remember_identifier)
	if not registering:
		var forgot := _account_link(helpers, "忘记密码？", func():
			_set_login_status("此版本尚未提供密码找回，可返回并选择游客登录。", true))
		forgot.name = "MahjongForgotPasswordButton"
	var section_status := "账号用 3–32 位英文字母、数字或下划线，首位不能为下划线。" if registering else ""
	_add_login_status(_login_form_actions, section_status)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", LOGIN_THEME.INK)
	_status.add_theme_font_size_override("font_size", 16)
	_submit_account = _login_entry(_login_form_actions, "创建账号" if registering else "登 录", "enter", _submit_named_account)
	MODAL_THEME.village_button(_submit_account, true)
	_submit_account.name = "MahjongAccountLoginSubmit"
	_login_identifier.text_submitted.connect(func(_value: String): _login_secret.grab_focus())
	_login_secret.text_submitted.connect(func(_value: String): _submit_named_account())
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 7)
	_login_form_actions.add_child(bottom)
	if not registering: _account_link(bottom, "注册新账号", _show_account_registration).name = "MahjongRegisterButton"
	_account_link(bottom, "返回其他登录方式", _back_to_login).name = "MahjongOtherLoginMethods"
	_layout_screen()


func _account_field(parent: Container, title: String, placeholder: String, icon: Texture2D, hide_text: bool) -> LineEdit:
	var card := PanelContainer.new()
	card.set_meta("account_field", true)
	card.add_theme_stylebox_override("panel", MODAL_THEME.capsule_frame(Vector4(22, 8, 22, 8)))
	parent.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	card.add_child(row)
	var stamp := TextureRect.new()
	stamp.texture = icon
	stamp.custom_minimum_size = Vector2(35, 35)
	stamp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stamp.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(stamp)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 0)
	row.add_child(stack)
	var label := _guest_label(stack, title, 14, Color("#8d6843"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.tooltip_text = placeholder
	field.secret = hide_text
	field.add_theme_font_override("font", MODAL_THEME.village_font())
	field.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	field.add_theme_stylebox_override("read_only", StyleBoxEmpty.new())
	var focus := LOGIN_THEME.frame(Color.TRANSPARENT, Color("#b4854b"), 6, 1)
	focus.shadow_size = 0
	field.add_theme_stylebox_override("focus", focus)
	for state in ["font_color", "font_selected_color", "font_uneditable_color", "caret_color"]:
		field.add_theme_color_override(state, LOGIN_THEME.INK)
	field.add_theme_color_override("font_placeholder_color", Color("#887765"))
	field.add_theme_color_override("selection_color", Color("#efd194"))
	field.add_theme_font_size_override("font_size", 21)
	field.custom_minimum_size = Vector2(84.0, maxf(44.0, LOGIN_THEME.touch_extent(_screen)))
	stack.add_child(field)
	if hide_text:
		var eye := Button.new()
		eye.name = "MahjongTogglePasswordVisibility"
		eye.icon = LOGIN_EYE
		eye.expand_icon = true
		eye.add_theme_constant_override("icon_max_width", 32)
		eye.flat = true
		eye.tooltip_text = "显示密码"
		eye.custom_minimum_size = Vector2(45.0, 44.0)
		eye.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		eye.pressed.connect(func():
			field.secret = not field.secret
			eye.icon = LOGIN_EYE if field.secret else LOGIN_EYE_OFF
			eye.tooltip_text = "显示密码" if field.secret else "隐藏密码")
		row.add_child(eye)
	return field


func _account_link(parent: Container, title: String, action: Callable) -> Button:
	var button := Button.new()
	LOGIN_THEME.CAPTION.attach(button)
	button.text = title
	button.flat = true
	button.custom_minimum_size = Vector2(196, 44)
	button.add_theme_font_size_override("font_size", 17)
	for style in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(style, Color("#4f7348"))
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _back_to_login() -> void:
	if not _request_kind.is_empty():
		_http.cancel_request()
		_request_kind = ""
		_request_server = ""
		_request_token = ""
		_request_identifier = ""
	_show_login(false)


func _submit_named_account() -> void:
	if _state not in ["login", "account_login", "account_register"] or not _request_kind.is_empty(): return
	var identifier := _login_identifier.text.strip_edges()
	var password := _login_secret.text
	var format := RegEx.create_from_string("^[A-Za-z0-9][A-Za-z0-9_]{2,31}$")
	if format.search(identifier) == null:
		_set_login_status("请输入 3–32 位有效用户名，首位须为字母或数字。", true)
		return
	if password.length() < 8 or password.length() > 128 or password.to_utf8_buffer().size() > 512:
		_set_login_status("密码须为 8–128 个字符。", true)
		return
	if _connected_server != _api.base_url:
		_set_login_status("网络连接异常，请检查网络后重试。", true, "NET-001", _request_health)
		return
	var registering := _state == "account_register"
	var result := _send_named_request(registering, identifier, password)
	if result != OK:
		_set_login_status("暂时无法发送请求，请重试。", true, "NET-001", _request_health)
		return
	_request_kind = "register" if registering else "named_login"
	_request_server = _api.base_url
	_request_identifier = identifier if _remember_identifier.button_pressed else ""
	_login_secret.clear()
	_set_login_status("正在创建账号……" if registering else "正在登录……")
	_update_login_request_state()


func _send_named_request(registering: bool, username: String, password: String) -> Error:
	var endpoint := "/api/v1/auth/register" if registering else "/api/v1/auth/login"
	return _http.request(_api.base_url + endpoint, PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST, JSON.stringify({"username": username, "password": password}))


func _remembered_account() -> String:
	var preferences := ConfigFile.new()
	if preferences.load(account_preferences_path) != OK: return ""
	return str(preferences.get_value("login", "username", ""))


func _remember_account(username: String) -> void:
	var preferences := ConfigFile.new()
	if not username.is_empty():
		preferences.set_value("login", "username", username)
		preferences.save(account_preferences_path)
	elif FileAccess.file_exists(account_preferences_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(account_preferences_path))


func _guest_identity_back() -> void:
	if _state != "guest_identity": return
	_clear_live_session()
	_show_login(false)


func _enter_guest_lobby() -> void:
	if _state != "guest_identity" or not _has_account_session(): return
	_show_lobby()
	_start_lobby_connection()
	if _guest_save_error != OK:
		_lobby_message = "当前会话有效，本机无法保存，下次启动需要重新登录"
		_render_lobby()


func _open_settings() -> void:
	if _screen.has_node("MahjongGlobalSettings"): return
	var overlay := ColorRect.new()
	overlay.name = "MahjongGlobalSettings"
	overlay.color = Color("#21160eb0")
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_screen.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var view := SETTINGS.new()
	overlay.add_child(view)
	var config := ConfigFile.new()
	config.load(_audio.preference_file)
	var rule: Dictionary = _match.get("rule", {})
	var rules: String = "创建房间时可选择并查看玩法。" if rule.is_empty() else _lobby_view._rule_name(rule) + "\n\n" + _lobby_view._room_rule_text(rule)
	var sync_view := func() -> void:
		var quality := clampi(int(config.get_value("rendering", "quality", 1)), 0, 2)
		view.sync(_audio.music_enabled, _audio.effects_enabled, quality, AUDIO.VOICE_IDS.find(_audio.callout_voice), rules,
			bool(config.get_value("assistance", "efficiency", false)))
	var set_quality := func(index: int) -> void:
		config.load(_audio.preference_file)
		config.set_value("rendering", "quality", index)
		config.save(_audio.preference_file)
		sync_view.call()
	var set_coach := func(enabled: bool) -> void:
		config.load(_audio.preference_file)
		config.set_value("assistance", "efficiency", enabled)
		config.save(_audio.preference_file)
		sync_view.call()
	view.setup(overlay.queue_free, _audio.set_music_enabled, _audio.set_effects_enabled, set_quality, _audio.make_callout_selector(), set_coach)
	sync_view.call()
	overlay.resized.connect(_fit_global_settings.bind(overlay, view))
	_fit_global_settings(overlay, view)


func _fit_global_settings(overlay: Control, view: Control) -> void:
	var safe := LOGIN_THEME.safe_insets(overlay)
	var origin := Vector2(safe.x, safe.y)
	var content := overlay.size - origin - Vector2(safe.z, safe.w)
	view.fit(Rect2(origin, content))


func _login() -> void:
	if _state != "login" or not _request_kind.is_empty():
		return
	var address: String = _api.base_url
	if _connected_server != address:
		_set_login_status("请先连接服务器，再进入游戏", true)
		return
	if _saved_token.is_empty():
		_start_session_request("login", _api.guest_login_url())
	else:
		_start_session_request("restore", address + "/api/v1/auth/session", _saved_token)


func _start_session_request(kind: String, url: String, token: String = "") -> void:
	if not _request_kind.is_empty(): return
	var error := _send_session_request(kind, url, token)
	if error != OK:
		_update_login_request_state()
		if kind != "probe": _set_login_status("网络连接异常，请检查网络后重试。", true, "NET-001", _request_health)
		return
	_request_kind = kind
	_request_server = _api.base_url
	_request_token = token
	_update_login_request_state()
	match kind:
		"health": _set_login_status("正在检查服务器连接……")
		"login": _set_login_status("正在登录……")
		"restore": _set_login_status("正在验证原游客会话……")


func _send_session_request(kind: String, url: String, token: String) -> Error:
	if kind == "login":
		return _http.request(url, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, "{}")
	var headers := PackedStringArray()
	if not token.is_empty(): headers.append("Authorization: Bearer " + token)
	return _http.request(url, headers)


func _show_lobby(route: Dictionary = {}) -> void:
	_reset("lobby")
	var script = load(LOBBY_SCRIPT)
	if script == null:
		_status = _label("麻将大厅加载失败", 60, 500, 600, 80, 23)
		return
	_lobby_view = script.new()
	_lobby_view.restore_navigation_route(route)
	_lobby_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lobby_view.action_requested.connect(_on_lobby_action)
	_screen.add_child(_lobby_view)
	_render_lobby()
	_refresh_history()
	_refresh_eggs()


func _back_from_lobby() -> void:
	if _account.get("kind") == "guest" and _has_account_session():
		_disconnect_lobby()
		_show_guest_identity()
	else:
		_clear_live_session()
		_show_account_login()


func _confirm_exit_game() -> void:
	if is_instance_valid(_exit_dialog):
		return
	var focused := get_viewport().gui_get_focus_owner()
	var restore_focus: WeakRef = weakref(focused) if focused != null else null
	var dialog := ERROR_VIEW.new()
	_exit_dialog = dialog
	_screen.add_child(dialog)
	dialog.z_index = 30
	dialog.build("确定退出小板凳麻将？", "", _quit_game, func() -> void:
		_exit_dialog = null
		var previous: Control = restore_focus.get_ref() as Control if restore_focus != null else null
		if is_instance_valid(previous) and previous.is_visible_in_tree():
			previous.grab_focus()
	, {"title": "退出游戏", "primary_text": "退出游戏", "cancel_text": "继续游戏", "show_art": false, "height_ratio": 0.42})
	_exit_dialog.name = "MahjongExitGameDialog"
	_focus_exit_cancel.call_deferred()


func _focus_exit_cancel() -> void:
	if is_instance_valid(_exit_dialog):
		(_exit_dialog.call("get_cancel_button") as Button).grab_focus()


func _center_exit_dialog() -> void:
	if is_instance_valid(_exit_dialog) and _exit_dialog.visible:
		_exit_dialog.call("_fit")


func _quit_game() -> void:
	get_tree().quit()


func _refresh_eggs() -> void:
	if not _has_account_session() or is_instance_valid(_egg_request): return
	_egg_request_generation += 1
	var request := HTTPRequest.new()
	request.timeout = 7.0
	request.max_redirects = 0
	add_child(request)
	_egg_request = request
	request.request_completed.connect(_receive_egg_balance.bind(request, _egg_request_generation,
		_session_server, str(_account.get("account_id", "")), _session_token))
	if _send_egg_request(request, _session_server + "/api/v1/wallet", _session_token) != OK:
		_cancel_egg_request()


func _send_egg_request(request: HTTPRequest, url: String, token: String) -> Error:
	return request.request(url, PackedStringArray(["Authorization: Bearer " + token]))


func _refresh_lobby_eggs() -> void:
	if _state not in ["lobby", "room"] or not _has_account_session(): return
	# An HTTP snapshot started before the notification may contain the old amount.
	_cancel_egg_request()
	_refresh_eggs()


func _receive_egg_balance(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray,
		request: HTTPRequest, generation: int, server: String, account: String, token: String) -> void:
	if request != _egg_request or generation != _egg_request_generation: return
	_cancel_egg_request()
	if server != _session_server or account != str(_account.get("account_id", "")) or token != _session_token: return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200: return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if data is Dictionary and data.get("account_id") == account and data.get("asset_id") == "xbd_egg" and _is_history_integer(data.get("amount")) and float(data.amount) >= 0:
		_egg_balance = int(data.amount)
		_render_lobby()


func _cancel_egg_request() -> void:
	_egg_request_generation += 1
	if not is_instance_valid(_egg_request): return
	var request := _egg_request
	_egg_request = null
	request.cancel_request()
	request.queue_free()


func _render_lobby() -> void:
	if not is_instance_valid(_lobby_view): return
	var waiting := not _finished_friend_return.is_empty() and (bool(_finished_friend_return.leave) or not _is_next_friend_round())
	var idle := not waiting and str(_match.get("status", "idle")) == "idle"
	if _history_open and not idle:
		_close_history_page()
	if _privacy_open and not idle and _account_request.is_empty():
		_close_privacy_page()
	var can_manage_account := idle and _pending_lobby_id.is_empty() and _has_account_session()
	_lobby_view.apply({
		"state": {} if waiting else _match, "presets": _presets, "selected": _selected_rule,
		"account": _account, "online": _lobby_synced and not waiting, "connecting": _lobby_connecting or (waiting and _lobby_synced),
		"wallet_available": _has_account_session(), "egg_balance": _egg_balance,
		"pending": not _pending_lobby_id.is_empty(), "message": _lobby_message,
		"command_error": _lobby_command_error, "directory_available": _room_directory_available,
		"directory_loaded": _room_directory_loaded, "directory_error": _room_directory_error, "public_rooms": _public_rooms,
		"spectator_supported": _spectator_supported,
		"recent": _recent,
		"privacy": {
			"available": can_manage_account, "open": _privacy_open, "can_submit": can_manage_account,
			"display_name": _account.get("display_name", "玩家"), "account_kind": _account.get("kind", "guest"), "confirm": _privacy_review,
			"acknowledged": _privacy_acknowledged, "error": _privacy_error, "pending": _account_request,
		},
		"history": {
			"open": _history_open, "rows": _history_rows() if _history_open else [], "more": not _history_cursor.is_empty(),
			"loading": is_instance_valid(_history_page_http) or (not _history_loaded and is_instance_valid(_history_http)),
			"match_id": _history_detail_id, "detail": _history_detail, "error": _history_error,
			"replay_open": _history_replay_open, "replay": _history_replay,
		},
	})


func _start_lobby_connection() -> void:
	var resync := _lobby_synced and not _pending_lobby_id.is_empty()
	_lobby_synced = false
	_lobby_connecting = true
	_pending_lobby_id = ""
	_lobby_command_acked = false
	_lobby_deadline.stop()
	_lobby_message = "操作确认超时，正在重新同步房间……" if resync else "正在连接麻将大厅……"
	_room_directory_available = false
	_spectator_supported = false
	_pending_watch.clear()
	_clear_room_directory_snapshot()
	_next_session_probe_tick = 0
	_lobby_socket.start(TRANSPORT.endpoint(_session_server), _session_token)
	_render_lobby()


func _on_lobby_open() -> void:
	_lobby_connecting = true
	var error := _subscribe_lobby()
	if error != OK:
		_lobby_socket.stop()
		_on_lobby_lost("订阅大厅失败，请重试")
		return
	_lobby_deadline.start(7.0)
	_render_lobby()


func _subscribe_lobby() -> Error:
	return _send_lobby_packet({"type":"mahjong_lobby_subscribe", "client_id":str(_account.get("account_id",""))})


func _on_lobby_lost(reason: String) -> void:
	_lobby_synced = false
	_lobby_connecting = false
	_pending_lobby_id = ""
	_lobby_command_acked = false
	_lobby_command_error = ""
	_room_directory_available = false
	_spectator_supported = false
	_pending_watch.clear()
	_clear_room_directory_snapshot()
	_lobby_deadline.stop()
	_lobby_message = reason + " · 等待重新同步"
	_render_lobby()
	if _state in ["lobby", "room"]:
		_present_error("网络连接异常，请检查网络后重试。", "NET-001", _start_lobby_connection)
	var now := Time.get_ticks_msec()
	if now >= _next_session_probe_tick and not _session_token.is_empty() and _request_kind.is_empty():
		_next_session_probe_tick = now + 10000
		_start_session_request("probe", _session_server + "/api/v1/auth/session", _session_token)


func _on_lobby_deadline() -> void:
	if _lobby_synced and not _pending_lobby_id.is_empty():
		_start_lobby_connection()
		return
	_lobby_socket.stop()
	_on_lobby_lost("大厅未收到确认，请检查连接并重试")


func _on_lobby_packet(raw: String) -> void:
	var decoded := JSON.new()
	if decoded.parse(raw) != OK or not decoded.data is Dictionary: return
	var packet: Dictionary = decoded.data
	match str(packet.get("type","")):
		"mahjong_lobby_state":
			if packet.get("state") is Dictionary and packet.get("presets") is Array:
				_spectator_supported = bool(packet.get("spectator_supported", false))
				_room_directory_available = bool(packet.get("room_directory", false))
				var current_request: bool = not bool(packet.get("room_directory_requests", false)) or packet.get("directory_request_id") == str(_room_directory_request)
				if _room_directory_open and _room_directory_available and current_request and packet.state.get("status") == "idle" and packet.get("public_rooms") is Array:
					_public_rooms = packet.public_rooms.duplicate(true)
					_room_directory_loaded = true
					_room_directory_error = ""
					_room_directory_deadline.stop()
				_on_lobby_state(packet.state, packet.presets)
		"mahjong_lobby_result":
			var confirmed: Variant = packet.get("state")
			_on_lobby_result(str(packet.get("command_id","")), bool(packet.get("ok",false)), str(packet.get("message","")), str(packet.get("code","")), confirmed if confirmed is Dictionary else {})
		"mahjong_wallet_changed":
			if packet.get("account_id") == _account.get("account_id", ""):
				_refresh_lobby_eggs()


func _set_room_directory(open: bool) -> void:
	_room_directory_open = open
	_clear_room_directory_snapshot()
	if not _lobby_synced or not _room_directory_available: return
	_room_directory_request += 1
	var error := _send_lobby_packet({"type":"mahjong_room_directory", "open":open, "request_id":str(_room_directory_request)})
	if not open: return
	if error == OK:
		_room_directory_deadline.start(7.0)
	else:
		_room_directory_error = "无法刷新房间列表，请重试"


func _clear_room_directory_snapshot() -> void:
	_room_directory_deadline.stop()
	_room_directory_loaded = false
	_room_directory_error = ""
	_public_rooms = []


func _on_room_directory_deadline() -> void:
	if not _room_directory_open or _room_directory_loaded: return
	_room_directory_error = "刷新房间列表超时，请重试"
	_render_lobby()


func _on_lobby_state(state: Dictionary, presets: Array) -> void:
	var phase := str(state.get("status",""))
	if phase not in ["idle","waiting","matched","playing"]: return
	var first := not _lobby_synced
	var joined_room := _lobby_command_acked and phase in ["waiting", "matched"] and str(_match.get("room_id", "")) != str(state.get("room_id", ""))
	_lobby_synced = true
	_dismiss_connection_error()
	_next_session_probe_tick = 0
	_lobby_connecting = false
	if first and phase == "idle" and _room_directory_open:
		_set_room_directory(true)
	if _lobby_command_acked:
		_pending_lobby_id = ""
		_lobby_command_acked = false
		_lobby_message = ""
		_lobby_command_error = ""
	if _pending_lobby_id.is_empty(): _lobby_deadline.stop()
	_match = state.duplicate(true)
	if joined_room: _audio.play_cue("room")
	_presets = presets.duplicate(true)
	if not _valid_rule(_selected_rule):
		_selected_rule = {}
		for item in _presets:
			if item is Dictionary and str(item.get("rule_set_id",""))==str(_product.get("rule_set_id","guiyang")) and str(item.get("rule_version",""))==str(_product.get("rule_version","2.0.0")):
				_selected_rule = {"rule_set_id":item.rule_set_id,"rule_version":item.rule_version}
				break
		if _selected_rule.is_empty() and not _presets.is_empty() and _presets[0] is Dictionary:
			_selected_rule = {"rule_set_id":str(_presets[0].get("rule_set_id","")),"rule_version":str(_presets[0].get("rule_version",""))}
	if first:
		_lobby_message = ""
		_refresh_lobby_eggs()
	if _state == "game" and is_instance_valid(_game):
		_game.reconcile_lobby_assignment(state)
		return
	if _state not in ["lobby","room"]: return
	_apply_lobby_assignment()


func _apply_lobby_assignment() -> void:
	if _resolve_finished_friend_return(): return
	var phase := str(_match.get("status", "idle"))
	if not _training_to_abandon.is_empty():
		var abandon := _training_to_abandon==str(_match.get("room_id","")) and str(_match.get("kind",""))=="training" and phase=="playing"
		_training_to_abandon = ""
		if abandon:
			_on_lobby_action("leave", {})
			return
	if phase in ["waiting","matched"]:
		if _room_directory_open: _set_room_directory(false)
		if _state != "room": print("MAHJONG_FLOW=room")
		_state = "room"
		_enter_when_ready = true
	elif phase=="playing" and bool(_match.get("start",false)) and _enter_when_ready and _account_request.is_empty():
		_enter_when_ready = false
		_enter_game()
		return
	else:
		_state = "lobby"
	_render_lobby()
	if _auto_flow and phase=="idle" and not _auto_match_sent:
		_auto_match_sent = true
		call_deferred("_start_match")
	elif _auto_flow and phase=="matched":
		call_deferred("_ready_up")


func _valid_rule(selection: Dictionary) -> bool:
	return not _catalog_rule(selection).is_empty()


func _catalog_rule(selection: Dictionary) -> Dictionary:
	if selection.is_empty(): return {}
	for item in _presets:
		if item is Dictionary and str(item.get("rule_set_id",""))==str(selection.get("rule_set_id","")) and str(item.get("rule_version",""))==str(selection.get("rule_version","")):
			return item
	return {}


func _on_lobby_result(id: String, ok: bool, message: String, code := "", confirmed: Dictionary = {}) -> void:
	if id.is_empty() or id != _pending_lobby_id: return
	var watch := _pending_watch
	_pending_watch = {}
	if ok and not watch.is_empty():
		_lobby_deadline.stop()
		_pending_lobby_id = ""
		_lobby_command_acked = false
		_lobby_message = ""
		if _state == "lobby" and _match.get("status", "idle") == "idle":
			watch["spectating"] = true
			watch["kind"] = "watch"
			_make_game(false, watch)
		return
	if ok:
		_lobby_command_acked = true
		if confirmed.get("status") in ["idle", "waiting", "matched", "playing"]:
			_on_lobby_state(confirmed, _presets)
		elif _lobby_socket.is_open():
			# Older servers send the receipt and the room state separately.
			_subscribe_lobby()
		return
	_lobby_deadline.stop()
	_pending_lobby_id = ""
	_lobby_command_acked = false
	if _finished_friend_return.get("ready_command_id", "") == id:
		_finished_friend_return.clear()
	_lobby_message = message if not message.is_empty() else "操作未完成，请重试"
	_lobby_command_error = code
	_present_error(_lobby_message, code)
	if code == "room_not_found" and _room_directory_open:
		_set_room_directory(true)
	if str(_match.get("status","idle"))=="idle": _enter_when_ready = false
	_render_lobby()


func _on_lobby_action(action: String, payload: Dictionary) -> void:
	if _state not in ["lobby","room"]: return
	if action in ["lobby_back", "exit_game"]:
		if is_instance_valid(_lobby_view) and _lobby_view.is_lobby_page() and _pending_lobby_id.is_empty():
			if action == "lobby_back": _back_from_lobby()
			else: _confirm_exit_game()
		return
	if action.begins_with("account_"):
		_on_account_action(action, payload)
		return
	if action in ["settings", "audio"]:
		_open_settings()
		return
	if _privacy_open: return
	if not _finished_friend_return.is_empty() and action != "retry":
		if bool(_finished_friend_return.leave) or not _is_next_friend_round(): return
		if action == "leave" and _lobby_synced and _pending_lobby_id.is_empty():
			_finished_friend_return.clear()
	var phase := str(_match.get("status","idle"))
	match action:
		"refresh_eggs":
			_refresh_eggs()
			return
		"refresh_rooms":
			if phase == "idle" and _pending_lobby_id.is_empty():
				_lobby_message = ""
				_lobby_command_error = ""
				_set_room_directory(true)
				_render_lobby()
			return
		"close_rooms":
			if _room_directory_open: _set_room_directory(false)
			return
		"clear_room_message":
			if _lobby_synced and _pending_lobby_id.is_empty():
				_lobby_message = ""
				_lobby_command_error = ""
				_render_lobby()
			return
		"history_open":
			if phase == "idle" and _pending_lobby_id.is_empty():
				_history_open = true
				_history_error = ""
				if not _history_loaded and not is_instance_valid(_history_http): _refresh_history()
				_render_lobby()
			return
		"history_back":
			_close_history_page()
			_render_lobby()
			return
		"history_more":
			if _history_open and _history_detail_id.is_empty() and not _history_cursor.is_empty():
				_request_history_page()
			return
		"history_match":
			var id := str(payload.get("match_id", ""))
			if _history_open and not id.is_empty() and _history_rows().any(func(row: Dictionary) -> bool: return row.get("match_id") == id):
				_cancel_history_page_request()
				_history_detail_id = id
				_history_detail = {}
				_request_history_page(id)
			return
		"history_detail_back":
			_cancel_history_page_request()
			_history_detail_id = ""
			_history_detail = {}
			_history_error = ""
			_render_lobby()
			return
		"history_replay":
			if _history_open and not _history_detail.is_empty():
				_history_replay_open = true
				_history_replay = {}
				_request_history_page(_history_detail_id, true)
			return
		"history_replay_back":
			_cancel_history_page_request()
			_history_replay_open = false
			_history_replay = {}
			_history_error = ""
			_render_lobby()
			return
		"history_retry":
			if _history_open:
				if not _history_detail_id.is_empty(): _request_history_page(_history_detail_id, _history_replay_open)
				elif not _history_loaded:
					_history_error = ""
					_refresh_history()
					_render_lobby()
				else: _request_history_page()
			return
		"practice":
			if phase=="idle" and _pending_lobby_id.is_empty(): _enter_training()
			return
		"copy":
			var code := str(_match.get("room_id",""))
			if not _valid_room_code(code): return
			_lobby_message = "请将房号 %s 发给好友" % code
			if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
				DisplayServer.clipboard_set(code)
				if DisplayServer.clipboard_get() == code:
					_lobby_message = "已复制房号 %s，可发给好友" % code
			_render_lobby()
			return
		"retry":
			if not _lobby_synced and not _lobby_connecting:
				_start_lobby_connection()
				_refresh_history()
			return
		"select":
			if phase=="idle" and _valid_rule(payload):
				_selected_rule = {"rule_set_id":str(payload.rule_set_id),"rule_version":str(payload.rule_version)}
				_render_lobby()
			return
		"resume":
			if _lobby_synced and phase=="playing" and not str(_match.get("room_id","")).is_empty():
				_enter_game()
			return
	if not _lobby_synced or not _pending_lobby_id.is_empty(): return
	var fields: Dictionary = {}
	match action:
		"quick","create","training":
			if phase != "idle": return
			var rule_choice := _selected_rule
			if action == "create" and (payload.has("rule_set_id") or payload.has("rule_version")):
				rule_choice = {"rule_set_id": str(payload.get("rule_set_id", "")), "rule_version": str(payload.get("rule_version", ""))}
			var descriptor := _catalog_rule(rule_choice)
			if descriptor.is_empty() or (action == "quick" and descriptor.get("quick_match", true) == false): return
			fields = rule_choice.duplicate()
			if action == "create":
				if payload.get("options") is Dictionary: fields["options"] = payload.options.duplicate()
				for key in ["room_id", "round_limit", "turn_timeout_seconds", "password"]:
					if payload.has(key): fields[key] = payload[key]
				if _spectator_supported and payload.get("allow_spectators") is bool:
					fields["allow_spectators"] = payload.allow_spectators
		"join", "watch":
			if phase!="idle": return
			var code := str(payload.get("room_id","")).strip_edges()
			if not _valid_room_code(code):
				_lobby_message = "请输入四位数字房号"
				_render_lobby()
				return
			fields = {"room_id":code}
			if payload.has("password"): fields["password"] = payload.password
			if action == "watch":
				var seat: Variant = payload.get("watch_seat")
				if not _spectator_supported or not seat is int or seat < 0 or seat >= 4: return
				fields["watch_seat"] = seat
		"set_spectator_permission":
			var enabled: Variant = payload.get("enabled")
			if not _spectator_supported or not _match.get("allow_spectators", false) or not enabled is bool: return
			fields = {"room_id": str(_match.get("room_id", "")), "enabled": enabled}
		"ready", "unready":
			var players: Array = _match.get("player_account_ids",[])
			var ready_accounts: Array = _match.get("ready_account_ids",[])
			var own_id := str(_account.get("account_id", ""))
			var own_ready := ready_accounts.has(own_id)
			if own_id not in players or not _room_allows_ready() or own_ready != (action == "unready"): return
			fields = {"room_id":str(_match.get("room_id",""))}
		"leave":
			if phase=="idle" or (phase=="playing" and str(_match.get("kind",""))!="training"): return
			fields = {"room_id":str(_match.get("room_id",""))}
		_: return
	if action in ["quick","create","join","training","ready"]: _enter_when_ready = true
	if action == "leave":
		_enter_when_ready = false
		_rematch_window_match_id = ""
	_submit_lobby(action, fields)


func _room_allows_ready() -> bool:
	var phase := str(_match.get("status", ""))
	if phase == "waiting":
		return _match.get("kind") == "friend"
	return phase == "matched" and _match.get("player_account_ids", []).size() == int(_match.get("capacity", 4))


func _valid_room_code(code: String) -> bool:
	if code.length()!=4: return false
	for index in range(4):
		var value := code.unicode_at(index)
		if value<48 or value>57: return false
	return true


func _submit_lobby(action: String, fields: Dictionary) -> void:
	_lobby_command_serial += 1
	var command_id := "%d-%d" % [Time.get_ticks_usec(),_lobby_command_serial]
	var packet := {"type":"mahjong_lobby_command","action":action,"command_id":command_id}
	packet.merge(fields)
	var error := _send_lobby_packet(packet)
	if error != OK:
		_lobby_message = "发送失败，请重试"
		_render_lobby()
		return
	_pending_lobby_id = command_id
	_pending_watch = fields.duplicate() if action == "watch" else {}
	_lobby_command_acked = false
	_lobby_command_error = ""
	_lobby_message = "等待牌桌服务确认……"
	_lobby_deadline.start(7.0)
	_render_lobby()


func _send_lobby_packet(packet: Dictionary) -> Error:
	return _lobby_socket.send(packet)


func _start_match() -> void:
	_on_lobby_action("quick", {})


func _ready_up() -> void:
	_on_lobby_action("ready", {})


func _on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var kind := _request_kind
	var server := _request_server
	var token := _request_token
	var identifier := _request_identifier
	_request_kind = ""
	_request_server = ""
	_request_token = ""
	_request_identifier = ""
	_update_login_request_state()
	if kind.is_empty() or server != _api.base_url: return
	if kind == "probe":
		if token != _session_token: return
		if result == HTTPRequest.RESULT_SUCCESS and code == 401:
			_on_live_session_expired()
		return
	if kind == "restore" and result == HTTPRequest.RESULT_SUCCESS and code == 401:
		_expire_saved_session(server, token)
		return
	var decoded := JSON.new()
	var parsed: Variant = null
	if not body.is_empty() and decoded.parse(body.get_string_from_utf8())==OK: parsed = decoded.data
	if kind in ["named_login", "register"]:
		_finish_named_account(kind, server, identifier, result, code, parsed)
		return
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		var detail := str(parsed.get("error", "")) if kind != "restore" and parsed is Dictionary else ""
		if detail.is_empty():
			detail = "服务器返回 %d" % code if code > 0 else "请检查网络后重试"
		var failure := "暂时无法验证原会话" if kind == "restore" else ("登录失败" if kind == "login" else "连接失败")
		var retry_action := Callable()
		if result != HTTPRequest.RESULT_SUCCESS or code >= 500:
			retry_action = _request_health
		_set_login_status(failure + " · " + detail, true, "NET-001" if retry_action.is_valid() else "HTTP-%d" % code, retry_action)
		return
	match kind:
		"health":
			if _state == "login":
				_connected_server = server
				_update_login_request_state()
				_set_login_status("")
				_dismiss_connection_error()
		"login", "restore":
			if _state!="login": return
			var session := str(parsed.get("session_token", "")) if kind == "login" and parsed is Dictionary else token
			if not parsed is Dictionary or str(parsed.get("account_id", "")).is_empty() or not GUEST_SESSIONS.valid_token(session):
				_set_login_status("未收到有效游客会话，请重试", true)
				return
			_guest_save_error = _sessions.save(server, session) if kind == "login" else OK
			_account = {"account_id": str(parsed.account_id), "display_name": str(parsed.get("display_name", "游客")), "kind": "guest"}
			_session_server = server
			_session_token = session
			_show_guest_identity()


func _finish_named_account(kind: String, server: String, identifier: String, result: int, code: int, parsed: Variant) -> void:
	if _state not in ["login", "account_login", "account_register"]: return
	var registering := kind == "register"
	var success := result == HTTPRequest.RESULT_SUCCESS and code == (201 if registering else 200)
	var token := str(parsed.get("session_token", "")) if parsed is Dictionary else ""
	if not success or not parsed is Dictionary or str(parsed.get("account_id", "")).is_empty() or not GUEST_SESSIONS.valid_token(token):
		var detail := "账号或密码不正确，或登录暂不可用。"
		if registering: detail = "未能创建账号，请检查输入或更换用户名。"
		if code == 429: detail = "尝试次数过多，请稍后重试。"
		elif result != HTTPRequest.RESULT_SUCCESS or code >= 500: detail = "暂时无法连接登录服务，请稍后重试。"
		var retry_action := _request_health if result != HTTPRequest.RESULT_SUCCESS or code >= 500 else Callable()
		_set_login_status(detail, true, "NET-001" if retry_action.is_valid() else "AUTH-%d" % code, retry_action)
		return
	_remember_account(identifier)
	_account = {"account_id": str(parsed.account_id), "display_name": str(parsed.get("display_name", "")), "kind": "named"}
	_session_server = server
	_session_token = token
	_show_lobby()
	_start_lobby_connection()


func _expire_saved_session(server: String, token: String) -> void:
	var error: Error = _sessions.remove(server, token)
	_saved_token = ""
	_update_login_request_state()
	var detail := "游客会话已失效，请重新登录" if error == OK else "游客会话已失效，无法清除本机记录，请重新登录"
	_set_login_status(detail, true)


func _has_account_session() -> bool:
	return GUEST_SESSIONS.valid_token(_session_token) and not _session_server.is_empty() and not _account.is_empty()


func _on_account_action(action: String, payload: Dictionary) -> void:
	if not _account_request.is_empty(): return
	if action == "account_open":
		if _privacy_open or not _has_account_session() or not _finished_friend_return.is_empty(): return
		if str(_match.get("status", "idle")) != "idle" or not _pending_lobby_id.is_empty(): return
		_close_history_page()
		_privacy_open = true
	elif _privacy_open:
		_privacy_error = ""
		match action:
			"account_back":
				if not _privacy_review: _close_privacy_page()
				_privacy_review = false
				_privacy_acknowledged = false
			"account_delete_review": _privacy_review = true
			"account_acknowledge":
				if _privacy_review: _privacy_acknowledged = payload.get("value", false) == true
			"account_delete_submit":
				if _privacy_review and _privacy_acknowledged: _submit_account_request("delete")
			"account_logout":
				if not _privacy_review: _submit_account_request("logout")
	else:
		return
	_render_lobby()


func _submit_account_request(kind: String) -> void:
	if not _has_account_session() or not _pending_lobby_id.is_empty() or str(_match.get("status", "idle")) != "idle": return
	var endpoint := "/api/v1/auth/logout" if kind == "logout" else "/api/v1/auth/delete-request"
	_account_request_generation += 1
	_account_request = kind
	_account_http = HTTPRequest.new()
	_account_http.name = "MahjongAccountRequest"
	_account_http.timeout = 7.0
	_account_http.max_redirects = 0
	add_child(_account_http)
	_account_http.request_completed.connect(_on_account_response.bind(
		_account_request_generation, _session_server, str(_account.get("account_id")), _session_token, kind))
	if _send_account_request(_account_http, _session_server + endpoint, _session_token) != OK:
		_cancel_account_request()
		_privacy_error = "暂时无法发送请求，请重试。"


func _send_account_request(request: HTTPRequest, url: String, token: String) -> Error:
	var headers := PackedStringArray(["Authorization: Bearer " + token, "Content-Type: application/json"])
	return request.request(url, headers, HTTPClient.METHOD_POST, "{}")


func _on_account_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray,
		generation: int, server: String, account: String, token: String, kind: String) -> void:
	if generation != _account_request_generation: return
	var session_expired := _account_session_expired
	_cancel_account_request()
	if server != _session_server or account != _account.get("account_id") or token != _session_token: return
	if result == HTTPRequest.RESULT_SUCCESS:
		if kind == "logout" and code == 204:
			_expire_live_session("已退出登录，当前会话已结束。")
			return
		if kind == "delete" and code == 202:
			var receipt: Variant = JSON.parse_string(body.get_string_from_utf8())
			if receipt is Dictionary and receipt.get("account_id") == account and receipt.get("status") == "pending_retention_review" and receipt.get("request_id") is String and not receipt.request_id.is_empty():
				_expire_live_session("删除申请已受理 · 账号已停用，关联记录待审核\n申请编号 %s" % receipt.request_id)
			else:
				_expire_live_session("删除申请已受理，服务器回执不完整。")
			return
		if code == 401:
			_expire_live_session()
			return
	if session_expired:
		_expire_live_session()
		return
	_privacy_error = "此账号当前无法通过游戏内入口申请删除。" if kind == "delete" and code == 409 else "暂时无法完成请求，请检查连接后重试。"
	_render_lobby()


func _cancel_account_request() -> void:
	_account_request_generation += 1
	_account_request = ""
	_account_session_expired = false
	if is_instance_valid(_account_http):
		_account_http.cancel_request()
		_account_http.queue_free()
		_account_http = null


func _close_privacy_page() -> void:
	_cancel_account_request()
	_privacy_open = false
	_privacy_review = false
	_privacy_acknowledged = false
	_privacy_error = ""


func _on_live_session_expired() -> void:
	# Revocation may close the lobby socket before the account HTTP receipt arrives.
	if not _account_request.is_empty():
		_account_session_expired = true
		return
	_expire_live_session()


func _disconnect_lobby() -> void:
	if _request_kind == "probe":
		_http.cancel_request()
		_request_kind = ""
		_request_server = ""
		_request_token = ""
	_lobby_socket.stop()
	_lobby_deadline.stop()
	_lobby_synced = false
	_lobby_connecting = false
	_pending_lobby_id = ""
	_lobby_command_acked = false
	_clear_room_directory_snapshot()
	_room_directory_open = false
	_room_directory_available = false
	_spectator_supported = false
	_pending_watch.clear()
	_lobby_command_error = ""
	_enter_when_ready = false
	_cancel_history()
	_cancel_egg_request()


func _clear_live_session() -> void:
	_wallet_session_generation += 1
	_disconnect_lobby()
	_egg_balance = -1
	_session_token = ""
	_session_server = ""
	_account.clear()
	_match.clear()
	_presets.clear()
	_selected_rule.clear()
	_recent.clear()
	_local_recent.clear()
	_remote_recent.clear()
	_seen_results.clear()
	_history_loaded = false
	_history_cursor = ""
	_history_extra.clear()
	_history_extra_loaded = false
	_finished_friend_return.clear()
	_rematch_window_match_id = ""
	_training_to_abandon = ""
	_board_return_route.clear()
	_auto_match_sent = false


func _expire_live_session(message: String = "") -> void:
	if _session_token.is_empty(): return
	var expired_token := _session_token
	var expired_server := _session_server
	_clear_live_session()
	var removed: Error = _sessions.remove(expired_server, expired_token)
	_show_login(false)
	_saved_token = ""
	_update_login_request_state()
	var detail := "登录会话已失效，请重新登录" if message.is_empty() else message
	if removed != OK: detail += "\n无法清除本机旧会话记录"
	_set_login_status(detail, message.is_empty() or removed != OK)


func _enter_game() -> void:
	var context := _match.duplicate(true)
	if str(context.get("room_id","")).is_empty(): return
	var game = _make_game(false, context)
	if game!=null: print("MAHJONG_ROOM=%s" % str(context.room_id))


func _enter_training() -> void:
	if _state!="lobby": return
	_make_game(true, {"room_id":"练习","seat_index":0,"kind":"practice"})


func _make_game(practice: bool, context: Dictionary) -> Variant:
	var preserve_window_size: bool = (
		not _rematch_window_match_id.is_empty() and context.get("kind") == "friend"
		and context.get("previous_match_id") == _rematch_window_match_id
	)
	_rematch_window_match_id = ""
	_board_return_route = _lobby_view.navigation_route() if is_instance_valid(_lobby_view) else {}
	_reset("training" if practice else "game")
	var screen_script := load(GAME_SCRIPT) as Script
	if screen_script == null or not screen_script.can_instantiate():
		_status = _label("麻将牌桌加载失败", 60, 580, 600, 80, 22)
		return null
	var game = screen_script.new()
	game.product = _product
	game.training_mode = practice
	game.preserve_window_size = preserve_window_size
	if (practice or context.get("kind") == "training") and _board_return_route.get("training_open", false):
		context["return_destination"] = "训练场"
	context["account_id"] = str(_account.get("account_id",""))
	context["display_name"] = str(_account.get("display_name","我"))
	if _egg_balance >= 0 and not context.get("spectating", false): context["own_egg_balance"] = _egg_balance
	context["websocket_url"] = TRANSPORT.endpoint(_session_server)
	if not context.get("rule") is Dictionary:
		for item in _presets:
			if item is Dictionary and str(item.get("rule_set_id",""))==str(context.get("rule_set_id","")) and str(item.get("rule_version",""))==str(context.get("rule_version","")):
				context["rule"] = item.duplicate(true)
				break
	game.match_context = context
	game.session_token = _session_token
	game.product_audio = _audio
	_game = game
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.session_expired.connect(_expire_live_session)
	game.entry_cancelled.connect(func(message: String):
		_lobby_message = message
		if context.get("spectating", false): _watch_return_message = message)
	game.request_return_to_lobby.connect(_return_from_game.bind(game, false))
	game.request_next_round.connect(_return_from_game.bind(game, true))
	var source := [game, _wallet_session_generation, _session_server, str(_account.get("account_id", "")), _session_token]
	if game.has_signal("match_finished"): game.match_finished.connect(_record_game_result.bindv(source))
	if game.has_signal("wallet_snapshot_received"): game.wallet_snapshot_received.connect(_on_game_wallet_snapshot.bindv(source))
	_screen.add_child(game)
	_layout_screen()
	return game


func _game_event_is_current(game: Control, generation: int, server: String, account: String, token: String) -> bool:
	return is_instance_valid(game) and not game.is_queued_for_deletion() and game == _game and _state in ["game", "training"] \
		and generation == _wallet_session_generation and server == _session_server \
		and account == str(_account.get("account_id", "")) and token == _session_token


func _on_game_wallet_snapshot(snapshot: Dictionary, game: Control, generation: int, server: String, account: String, token: String) -> void:
	if not _has_account_session() or not _game_event_is_current(game, generation, server, account, token): return
	if snapshot.get("account_id") != account or not snapshot.has("amount"): return
	var amount: Variant = snapshot.amount
	if amount != null and (not _is_history_integer(amount) or float(amount) < 0): return
	# A delayed HTTP response started before this board event must not restore an
	# older wallet. Unknown is explicit; neither scores nor the old fallback is money.
	_cancel_egg_request()
	_egg_balance = -1 if amount == null else int(amount)
	_render_lobby()


func _record_game_result(result: Dictionary, game: Control, generation: int, server: String, account: String, token: String) -> void:
	if _game_event_is_current(game, generation, server, account, token): _record_result(result)


func _record_result(result: Dictionary) -> void:
	var id := str(result.get("match_id",""))
	if id.is_empty() or _seen_results.has(id): return
	_seen_results[id] = true
	for stored in _remote_recent:
		if stored.match_id == id: return
	_local_recent.push_front(result.duplicate(true))
	if _local_recent.size() > RECENT_LIMIT: _local_recent.pop_back()
	_merge_history()
	_refresh_history()


func _refresh_history() -> void:
	var account := str(_account.get("account_id", ""))
	if not GUEST_SESSIONS.valid_token(_session_token) or _session_server.is_empty() or account.is_empty(): return
	if is_instance_valid(_history_http):
		_history_refresh_pending = true
		return
	_history_generation += 1
	_history_http = HTTPRequest.new()
	_history_http.name = "MahjongHistoryRequest"
	_history_http.timeout = 7.0
	_history_http.max_redirects = 0
	add_child(_history_http)
	_history_http.request_completed.connect(_on_history_response.bind(_history_generation, _session_server, account, _session_token))
	var error := _send_history_request(_history_http, _session_server + "/api/v1/mahjong/history?limit=%d" % RECENT_LIMIT, _session_token)
	if error != OK:
		_cancel_history()
		if not _history_loaded:
			_history_error = "暂时无法获取战绩"
			_render_lobby()


func _send_history_request(request: HTTPRequest, url: String, token: String) -> Error:
	return request.request(url, PackedStringArray(["Authorization: Bearer " + token]))


func _cancel_history() -> void:
	_history_generation += 1
	_history_refresh_pending = false
	if is_instance_valid(_history_http):
		_history_http.cancel_request()
		_history_http.queue_free()
		_history_http = null


func _on_history_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, generation: int, server: String, account: String, token: String) -> void:
	if generation != _history_generation: return
	var refresh_pending := _history_refresh_pending
	_cancel_history()
	if server != _session_server or account != str(_account.get("account_id", "")) or token != _session_token: return
	var accepted := false
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var data: Variant = JSON.parse_string(body.get_string_from_utf8())
		if data is Dictionary and data.get("matches") is Array:
			accepted = true
			_history_loaded = true
			if not _history_extra_loaded and not is_instance_valid(_history_page_http):
				_history_cursor = str(data.get("next_cursor", ""))
			if _history_detail_id.is_empty() and not _history_extra_loaded: _history_error = ""
			_accept_history(data.matches)
	if not accepted and not _history_loaded:
		_history_error = "暂时无法获取战绩"
		_render_lobby()
	if refresh_pending: _refresh_history()


func _accept_history(matches: Array) -> void:
	var stored_ids := {}
	var previous := _remote_recent.duplicate() if _history_extra_loaded else []
	_remote_recent.clear()
	for raw in matches.slice(0, RECENT_LIMIT):
		var row := _history_summary(raw)
		if row.is_empty() or stored_ids.has(row.match_id): continue
		stored_ids[row.match_id] = true
		_remote_recent.append(row)
	if _history_extra_loaded:
		var older: Array[Dictionary] = []
		for row: Dictionary in previous + _history_extra:
			if stored_ids.has(row.match_id): continue
			stored_ids[row.match_id] = true
			older.append(row)
		_history_extra = older
	for index in range(_local_recent.size() - 1, -1, -1):
		if stored_ids.has(_local_recent[index].match_id): _local_recent.remove_at(index)
	_merge_history()


func _merge_history() -> void:
	_recent = (_local_recent + _remote_recent).slice(0, RECENT_LIMIT)
	_render_lobby()


func _history_summary(raw: Variant) -> Dictionary:
	if not raw is Dictionary: return {}
	var id := str(raw.get("match_id", ""))
	var rule: Variant = raw.get("rule")
	var scores: Variant = raw.get("scores")
	var winners: Variant = raw.get("winners")
	var seat_value: Variant = raw.get("your_seat")
	if id.is_empty() or not rule is Dictionary or not scores is Array or not winners is Array or typeof(seat_value) not in [TYPE_FLOAT, TYPE_INT]: return {}
	var seat := int(seat_value)
	if float(seat_value) != float(seat) or seat < 0 or seat >= 4 or scores.size() != 4: return {}
	if not _is_history_integer(scores[seat]): return {}
	var outcome := "流局" if winners.is_empty() else ("胡牌" if winners.has(float(seat)) or winners.has(seat) else "已结算")
	var row := {"match_id": id, "name": str(rule.get("name", "贵阳麻将")), "kind": str(raw.get("kind", "")),
		"score": int(scores[seat]), "result": outcome, "finished_at": str(raw.get("finished_at", ""))}
	var egg_deltas: Variant = raw.get("egg_deltas")
	if egg_deltas is Array and egg_deltas.size() == 4 and egg_deltas.all(_is_history_integer):
		row["egg_delta"] = int(egg_deltas[seat])
	var breakdown: Variant = raw.get("score_breakdown")
	if breakdown is Dictionary:
		var own_scores := {}
		for component in ["hu", "gang", "ji"]:
			var values: Variant = breakdown.get(component)
			if values is Array and values.size() == 4 and values.all(_is_history_integer):
				own_scores[component] = int(values[seat])
		if own_scores.size() == 3:
			var checked: Variant = breakdown.get("cha_jiao")
			if rule.get("dingque") == true and checked is Array and checked.size() == 4 and checked.all(_is_history_integer):
				own_scores["cha_jiao"] = int(checked[seat])
			row["breakdown"] = own_scores
	return row


func _is_history_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value))


func _history_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var seen := {}
	for row in _local_recent + _remote_recent + _history_extra:
		var id: String = row.match_id
		if not seen.has(id):
			seen[id] = true
			rows.append(row)
	return rows


func _request_history_page(match_id: String = "", replay: bool = false) -> void:
	if not _history_open or is_instance_valid(_history_page_http): return
	if not GUEST_SESSIONS.valid_token(_session_token) or _session_server.is_empty() or _account.is_empty(): return
	if match_id.is_empty() and _history_cursor.is_empty(): return
	_history_error = ""
	var cursor := _history_cursor
	var path := "/api/v1/mahjong/history"
	if match_id.is_empty():
		path += "?limit=%d&cursor=%s" % [RECENT_LIMIT, cursor.uri_encode()]
	else:
		path += "/" + match_id.uri_encode()
		if replay: path += "/replay"
	_history_page_generation += 1
	_history_page_http = HTTPRequest.new()
	_history_page_http.name = "MahjongPersonalHistoryRequest"
	_history_page_http.timeout = 7.0
	_history_page_http.max_redirects = 0
	add_child(_history_page_http)
	_history_page_http.request_completed.connect(_on_history_page_response.bind(
		_history_page_generation, _session_server, _account.get("account_id"), _session_token, match_id, cursor, replay))
	if _send_history_request(_history_page_http, _session_server + path, _session_token) != OK:
		_cancel_history_page_request()
		_history_error = "暂时无法获取战绩"
	_render_lobby()


func _cancel_history_page_request() -> void:
	_history_page_generation += 1
	if is_instance_valid(_history_page_http):
		_history_page_http.cancel_request()
		_history_page_http.queue_free()
		_history_page_http = null


func _close_history_page() -> void:
	_cancel_history_page_request()
	_history_open = false
	_history_detail_id = ""
	_history_detail = {}
	_history_replay_open = false
	_history_replay = {}
	_history_error = ""


func _on_history_page_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray,
		generation: int, server: String, account: String, token: String, match_id: String, cursor: String, replay: bool) -> void:
	if generation != _history_page_generation: return
	_cancel_history_page_request()
	if not _history_open or server != _session_server or account != _account.get("account_id") or token != _session_token: return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
	if replay:
		var public_replay: Variant = data.get("replay") if data is Dictionary else null
		if public_replay is Dictionary and public_replay.get("version") == 1 and public_replay.get("events") is Array:
			_history_replay = public_replay
		else:
			_history_error = "这局没有可用的复盘记录" if code == 404 else "暂时无法获取复盘记录"
	elif not match_id.is_empty():
		var row := _history_summary(data.get("match")) if data is Dictionary else {}
		if row.get("match_id") == match_id:
			_history_detail = row
		else:
			_history_error = "这局战绩尚未保存或无法查看" if code == 404 else "暂时无法获取单局明细"
	elif data is Dictionary and data.get("matches") is Array:
		var seen := {}
		for row in _history_rows(): seen[row.match_id] = true
		for raw in data.matches:
			var row := _history_summary(raw)
			if not row.is_empty() and not seen.has(row.match_id):
				seen[row.match_id] = true
				_history_extra.append(row)
		_history_extra_loaded = true
		var next_cursor := str(data.get("next_cursor", ""))
		_history_cursor = "" if next_cursor == cursor else next_cursor
	else:
		_history_error = "暂时无法加载更多战绩"
	_render_lobby()


func _return_to_lobby() -> void:
	_enter_when_ready = false
	var route := _board_return_route
	_board_return_route = {}
	_show_lobby(route)
	if str(_match.get("kind",""))=="training" and str(_match.get("status","idle"))=="playing":
		if _lobby_synced and _pending_lobby_id.is_empty():
			_on_lobby_action("leave", {})
		else:
			_training_to_abandon = str(_match.get("room_id",""))


func _return_from_game(game: Control, keep_room: bool) -> void:
	if game != _game: return
	if game.match_context.get("spectating", false):
		var notice := _watch_return_message
		_watch_return_message = ""
		_return_to_lobby()
		if not notice.is_empty(): _present_error(notice, "watch_ended")
		return
	var match_id: String = game.finished_friend_match_id()
	if not match_id.is_empty():
		_finished_friend_return = {
			"room_id":str(game.match_context.get("room_id", "")), "match_id":match_id,
			"rounds":int(game.match_context.get("completed_rounds", 0)) + 1, "leave":not keep_room,
		}
		_lobby_message = "正在同步好友房……"
		if not keep_room:
			_board_return_route.clear()
		elif not OS.has_feature("mobile"):
			_rematch_window_match_id = match_id
			# Relinquish the display before opening the waiting room or another board.
			BATTLE_DISPLAY.leave(game, true)
	_return_to_lobby()
	if not _finished_friend_return.is_empty() and _lobby_synced:
		_apply_lobby_assignment()


func _is_next_friend_round() -> bool:
	return (
		not _finished_friend_return.is_empty()
		and _match.get("kind") == "friend"
		and _match.get("room_id") == _finished_friend_return.room_id
		and _match.get("previous_match_id") == _finished_friend_return.match_id
		and int(_match.get("completed_rounds", 0)) == int(_finished_friend_return.rounds)
	)


func _resolve_finished_friend_return() -> bool:
	if _finished_friend_return.is_empty(): return false
	if str(_match.get("room_id", "")) != _finished_friend_return.room_id:
		_finished_friend_return.clear()
		_lobby_message = ""
		return false
	var same_round := _is_next_friend_round()
	if not same_round and int(_match.get("completed_rounds", 0)) < int(_finished_friend_return.rounds):
		_lobby_message = "正在同步好友房……"
		_render_lobby()
		return true
	var phase := str(_match.get("status", ""))
	if bool(_finished_friend_return.leave):
		var leave := same_round and phase in ["waiting", "matched"]
		if leave and not _pending_lobby_id.is_empty(): return true
		_finished_friend_return.clear()
		_lobby_message = ""
		if leave:
			_on_lobby_action("leave", {})
			return true
		return false
	var own_id := str(_account.get("account_id", ""))
	var players: Array = _match.get("player_account_ids", [])
	if not same_round or own_id not in players:
		_finished_friend_return.clear()
		_lobby_message = ""
		return false
	_enter_when_ready = true
	if own_id in _match.get("ready_account_ids", []):
		_finished_friend_return.clear()
		_lobby_message = ""
	elif _room_allows_ready() and _pending_lobby_id.is_empty():
		_submit_lobby("ready", {"room_id":_match.room_id})
		if _pending_lobby_id.is_empty():
			_finished_friend_return.clear()
		else:
			_finished_friend_return["ready_command_id"] = _pending_lobby_id
	return false
