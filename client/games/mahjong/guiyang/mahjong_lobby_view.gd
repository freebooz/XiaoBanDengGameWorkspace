extends Control

signal action_requested(action: String, payload: Dictionary)

const ART := "res://modules/games/mahjong/guiyang/assets/ui/"
const RURAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_theme.gd")
const HISTORY_VIEW := preload("res://modules/games/mahjong/guiyang/mahjong_history_view.gd")
const GUIDED_VIEW := preload("res://modules/games/mahjong/guiyang/mahjong_guided_view.gd")
const ACCOUNT_VIEW := preload("res://modules/games/mahjong/guiyang/mahjong_account_view.gd")
const MODAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_modal.gd")
const ROOM_PAGES := preload("res://modules/games/mahjong/guiyang/mahjong_room_pages.gd")
const LOBBY_ART := ART + "lobby_rural/"
const EXIT_ICON := preload(ART + "login_rural/icon_power.svg")
const PERSON_ICON := preload(ART + "login_rural/icon_person.svg")
const PROFILE_ICON := preload(ART + "login_rural/avatar.svg")
const FEATURE_TILES := preload(LOBBY_ART + "icon_tiles.svg")
const FEATURE_PAVILION := preload(LOBBY_ART + "icon_pavilion.svg")
const FEATURE_DOOR := preload(LOBBY_ART + "icon_door.svg")
const TRAINING_COURTYARD := preload(ART + "series/training_courtyard.png")
const VILLAGE_SEATS := [
	preload(ART + "rice_field_hud/portrait_self.png"),
	preload(ART + "rice_field_hud/portrait_left.png"),
	preload(ART + "rice_field_hud/portrait_far.png"),
	preload(ART + "rice_field_hud/portrait_right.png"),
]
const INK := Color("#453326")
const MUTED := Color("#725847")
const CREAM := Color("#fffaf1")
const EDGE := Color("#d9c5ad")
const OLIVE := Color("#596e4c")
const DEEP_OLIVE := Color("#3e5133")
const DARK_WOOD := Color("#543220")
const HONEY := Color("#c18b55")
const WOOD := Color("#b57743")
const PHONE_CONTENT_WIDTH := 672.0
const PORTRAIT_CONTENT_WIDTH := 830.0
const ROOM_MODES := {"quick": "快速匹配", "friend": "好友房", "training": "人机训练"}

class LessonIcon extends Control:
	var group_table := false

	func _draw() -> void:
		var center := size * 0.5
		var shade := Color("#506845") if group_table else Color("#784e34")
		var base := Color("#e4ecdc") if group_table else Color("#f6e1cb")
		draw_circle(center, 41, base, true, -1.0, true)
		draw_circle(center, 41, shade.lightened(0.42), false, 1.0, true)
		if group_table:
			_draw_table(center, shade)
		else:
			_draw_tiles(center, shade)

	func _draw_table(center: Vector2, shade: Color) -> void:
		for direction in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
			draw_circle(center + direction * 28.0, 4.0, shade, true, -1.0, true)
		var table := StyleBoxFlat.new()
		table.bg_color = Color("#79936d")
		table.border_color = shade
		table.set_border_width_all(2)
		table.set_corner_radius_all(6)
		draw_style_box(table, Rect2(center - Vector2(19, 19), Vector2(38, 38)))
		for tile_offset in [Vector2(-13, -2), Vector2(-4, -2), Vector2(5, -2)]:
			draw_rect(Rect2(center + tile_offset, Vector2(7, 9)), Color("#f9f1dc"))

	func _draw_tiles(center: Vector2, shade: Color) -> void:
		var tile := StyleBoxFlat.new()
		tile.bg_color = Color("#fff8e6")
		tile.border_color = shade
		tile.set_border_width_all(1)
		tile.border_width_bottom = 3
		tile.set_corner_radius_all(4)
		draw_set_transform(center + Vector2(-11, 1), -0.19)
		draw_style_box(tile, Rect2(-10, -14, 20, 28))
		draw_line(Vector2(-2, 1), Vector2(3, -5), Color("#667c52"), 3.0, true)
		draw_set_transform(center + Vector2(12, -3), 0.17)
		draw_style_box(tile, Rect2(-10, -14, 20, 28))
		draw_circle(Vector2(0, -5), 2.7, Color("#9a5c43"), true, -1.0, true)
		draw_circle(Vector2(0, 3), 2.7, Color("#9a5c43"), true, -1.0, true)
		draw_set_transform(Vector2.ZERO)


var _data: Dictionary = {}
var _state: Dictionary = {}
var _account: Dictionary = {}
var _presets: Array = []
var _page := ""
var _scroll: ScrollContainer
var _inset: MarginContainer
var _content: VBoxContainer
var _content_layouts: Array[BoxContainer] = []
var _content_banners: Array[PanelContainer] = []
var _banner_images: Array[TextureRect] = []
var _portrait_banner_heights: Array[int] = []
var _touch_sizes: Dictionary[Control, float] = {}
var _lobby_landscape: Control
var _portrait_scene: TextureRect
var _portrait_shade: TextureRect
var _lobby: VBoxContainer
var _lobby_village_header: HBoxContainer
var _lobby_scene_gap: Control
var _header_shell: PanelContainer
var _header_brand_slot: Control
var _viewport_brand_frame: Control
var _viewport_brand: TextureRect
var _header_content: VBoxContainer
var _header_toolbar: HBoxContainer
var _profile_toolbar: HBoxContainer
var _header_avatar: TextureRect
var _profile_card: PanelContainer
var _profile_avatar_button: Button
var _settings_button: Button
var _featured_actions: BoxContainer
var _feature_contents: Dictionary[Button, Control] = {}
var _secondary_actions: VBoxContainer
var _custom_rules: Button
var _bottom_nav: HBoxContainer
var _room: VBoxContainer
var _training_hall: VBoxContainer
var _training_hall_button: Button
var _training_rule: Label
var _training_rule_select: MenuButton
var _training_grid: GridContainer
var _training_open := false
var _guided_view: Control
var _guided_open := false
var _guided_button: Button
var _connection: Label
var _identity: Label
var _feedback_shell: PanelContainer
var _feedback: HBoxContainer
var _message: Label
var _retry: Button
var _quick: Button
var _create: Button
var _open_join: Button
var _room_pages: Control
var _room_page := ""
var _room_page_parent := ""
var _room_collapsed := false
var _egg_wallet: Button
var _lobby_back: Button
var _lobby_exit: Button
var _lobby_resume: Button
var _room_list_button: Button
var _wide_layout := false
var _short_lobby := false
var _training: Button
var _practice: Button
var _history_open_button: Button
var _account_open_button: Button
var _account_view: Control
var _personal_history: Control
var _history_list_scroll := 0
var _history_detail_open := false
var _room_village_header: HBoxContainer
var _quick_header_gap: Control
var _room_staging_panel: PanelContainer
var _quick_panel: PanelContainer
var _quick_title: Label
var _room_board: VBoxContainer
var _room_summary: HBoxContainer
var _room_info: VBoxContainer
var _room_code_row: BoxContainer
var _seats_title: HBoxContainer
var _seat_grid: GridContainer
var _quick_footer: VBoxContainer
var _quick_room := false
var _room_title: Label
var _room_wallet: Label
var _room_mode: Label
var _room_code: Label
var _room_copy: Button
var _room_details: Label
var _room_rule_details: Label
var _seating: VBoxContainer
var _seat_count: Label
var _ready_count: Label
var _ready_progress: ProgressBar
var _seat_frames: Array[PanelContainer] = []
var _seat_names: Array[Label] = []
var _seat_statuses: Array[Label] = []
var _seat_badges: Array[PanelContainer] = []
var _seat_icons: Array[TextureRect] = []
var _seat_ready_bars: Array[ProgressBar] = []
var _seat_portraits: Array[AtlasTexture] = []
var _room_note: Label
var _room_controls: VBoxContainer
var _room_layout: BoxContainer
var _ready_button: Button
var _watch_permission: Button
var _leave_button: Button
var _resume: Button
var _village: Texture2D
var _portrait: Texture2D
var _lobby_banner: Texture2D
var _training_scene: Texture2D
var _training_layout: BoxContainer
var _training_banner: PanelContainer
var _training_cards: Array[PanelContainer] = []
var _training_titles: Array[Label] = []
var _wood_grain: Texture2D
var _lettering: Font


func _ready() -> void:
	name = "MahjongLobbyView"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_render()
	if _page == "directory": _refresh_returned_directory.call_deferred()


func apply(data: Dictionary) -> void:
	_data = data.duplicate(true)
	if _scroll != null:
		_render()


func is_lobby_page() -> bool:
	return _page == "lobby"


func navigate_village_back() -> bool:
	var back: Button
	match _page:
		"lobby": back = _lobby_back
		"room": back = _leave_button
		"create", "join", "directory": return _room_pages.navigate_back()
	if not is_instance_valid(back) or not back.is_visible_in_tree() or back.disabled:
		return false
	back.pressed.emit()
	return true


func navigation_route() -> Dictionary:
	return {"room_page": _room_page, "room_page_parent": _room_page_parent, "training_open": _training_open}


func restore_navigation_route(route: Dictionary) -> void:
	_room_page = str(route.get("room_page", ""))
	_room_page_parent = str(route.get("room_page_parent", ""))
	_training_open = bool(route.get("training_open", false))


func _build() -> void:
	_village = _texture(ART + "series/rural_hero_v2.png")
	_portrait = _texture(ART + "series/rural_lobby_v2.png")
	_lobby_banner = _texture(ART + "series/flow_lobby_scene.png")
	if _lobby_banner == null:
		_lobby_banner = _village
	_training_scene = _crop_image(_texture(ART + "series/rural_training_v2.png"), Rect2(0, 210, 1536, 814))
	_wood_grain = _texture(ART + "mahjong_wood.png")
	if _village == null:
		_village = _texture("res://modules/games/mahjong/guiyang/assets/backgrounds/T_BG_Lobby_JiaxiuTower.png")
	_lettering = RURAL.title_font()
	var background := _gradient(Color("#2e1c15"), Color("#503426"))
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_build_lobby_landscape()

	_scroll = ScrollContainer.new()
	_scroll.name = "MahjongLobbyScroll"
	# Keep the page's minimum width from widening the viewport during a resize.
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.follow_focus = true
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_scroll)
	_viewport_brand_frame = Control.new()
	_viewport_brand_frame.clip_contents = true
	_viewport_brand_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_viewport_brand_frame)
	_viewport_brand = _picture(MODAL.VILLAGE_BRAND, TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	_viewport_brand.name = "MahjongViewportBrand"
	_viewport_brand_frame.add_child(_viewport_brand)
	_scroll.get_v_scroll_bar().value_changed.connect(_scroll_brand)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(center)
	_inset = MarginContainer.new()
	center.add_child(_inset)
	_content = _column(_inset, 12)
	resized.connect(_fit_content)
	get_window().size_changed.connect(_fit_content, CONNECT_DEFERRED)


	_lobby_village_header = MODAL.village_header(_content, "MahjongLobbyBackButton", func() -> void:
		action_requested.emit("lobby_back", {}), "MahjongLobbyBrandSpace", false)
	_lobby_back = _lobby_village_header.get_child(-1) as Button
	_lobby_exit = _command_button(_lobby_village_header, "MahjongLobbyExitButton", "", "exit_game", false, 44, 18)
	_lobby_exit.tooltip_text = "退出游戏"
	_lobby_exit.accessibility_name = "退出游戏"
	MODAL.close_button(_lobby_exit)
	_lobby_exit.icon = EXIT_ICON
	_lobby_exit.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby_exit.expand_icon = true
	_lobby_exit.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_lobby_village_header.move_child(_lobby_exit, _lobby_back.get_index())

	_header_shell = PanelContainer.new()
	_header_shell.name = "MahjongFlowHeader"
	_content.add_child(_header_shell)
	_header_content = _column(_header_shell, 7)
	_header_toolbar = _row(_header_content, 10)
	_header_brand_slot = Control.new()
	_header_brand_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_toolbar.add_child(_header_brand_slot)
	_build_profile_card(_header_toolbar)
	_settings_button = _command_button(_profile_toolbar, "MahjongSettingsButton", "设置", "settings", false, 52, 22)
	MODAL.icon_button(_settings_button, MODAL.icon("settings"), "设置")
	_lobby_resume = _command_button(_header_content, "MahjongLobbyResumeButton", "返回牌桌", "resume", true, 54, 21)
	MODAL.village_button(_lobby_resume, true)

	_feedback_shell = PanelContainer.new()
	_content.add_child(_feedback_shell)
	_feedback = _row(_feedback_shell, 12)
	_message = _label(_feedback, "", 19, CREAM, true)
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_retry = _command_button(_feedback, "MahjongRetryButton", "重试连接", "retry", false, 48)
	MODAL.button(_retry, "auxiliary")

	_lobby = _column(_content, 12)
	_build_lobby()
	_room_pages = ROOM_PAGES.new()
	_room_pages.action_requested.connect(_on_room_page_action)
	_content.add_child(_room_pages)
	_room = _column(_content, 12)
	_build_room()
	_training_hall = _column(_content, 12)
	_build_training_hall()
	_personal_history = HISTORY_VIEW.new()
	_personal_history.action_requested.connect(func(action: String, payload: Dictionary) -> void:
		action_requested.emit(action, payload))
	_content.add_child(_personal_history)
	_guided_view = GUIDED_VIEW.new()
	_guided_view.back_requested.connect(_close_guided_training)
	_content.add_child(_guided_view)
	_account_view = ACCOUNT_VIEW.new()
	_account_view.action_requested.connect(func(action: String, payload: Dictionary) -> void:
		action_requested.emit(action, payload))
	_content.add_child(_account_view)
	_fit_content()


func _build_profile_card(parent: Control) -> void:
	_profile_card = PanelContainer.new()
	_profile_card.name = "MahjongLobbyProfileCard"
	_profile_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(_profile_card)
	_profile_toolbar = _row(_profile_card, 10)
	_profile_avatar_button = Button.new()
	_profile_avatar_button.name = "MahjongLobbyProfileOpenButton"
	_profile_avatar_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_profile_avatar_button.flat = true
	_profile_avatar_button.tooltip_text = "个人中心"
	_profile_avatar_button.pressed.connect(func() -> void: action_requested.emit("account_open", {}))
	var outline := _surface(Color.TRANSPARENT, Color("#f5ce8c"), 36)
	outline.set_border_width_all(2)
	_profile_avatar_button.add_theme_stylebox_override("focus", outline)
	_profile_toolbar.add_child(_profile_avatar_button)
	_header_avatar = _picture(PROFILE_ICON, TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	_header_avatar.name = "MahjongLobbyProfileAvatar"
	_profile_avatar_button.add_child(_header_avatar)
	_header_avatar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var identity := _column(_profile_toolbar, 3)
	identity.alignment = BoxContainer.ALIGNMENT_CENTER
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.custom_minimum_size.x = 75
	_identity = _label(identity, "", 30, CREAM)
	_identity.name = "MahjongLobbyAccountName"
	_identity.add_theme_font_override("font", MODAL.village_font())
	_identity.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_connection = _label(identity, "", 19, Color("#356841"))
	_connection.add_theme_font_override("font", MODAL.village_font())
	_connection.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_egg_wallet = _command_button(_profile_toolbar, "MahjongEggBalanceButton", "鸡蛋 —", "refresh_eggs", false, 44, 19)
	_egg_wallet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_egg_wallet.tooltip_text = "点击刷新鸡蛋余额"
	MODAL.village_button(_egg_wallet)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var wallet_skin := _egg_wallet.get_theme_stylebox(state).duplicate() as StyleBox
		wallet_skin.set_content_margin(SIDE_LEFT, 7)
		wallet_skin.set_content_margin(SIDE_RIGHT, 7)
		_egg_wallet.add_theme_stylebox_override(state, wallet_skin)


func _build_lobby_landscape() -> void:
	_lobby_landscape = Control.new()
	_lobby_landscape.name = "MahjongLobbyLandscape"
	_lobby_landscape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lobby_landscape.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_lobby_landscape)
	_portrait_scene = _picture(_village, TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	_portrait_scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait_scene.anchor_bottom = 0.67
	_lobby_landscape.add_child(_portrait_scene)
	var shades := Gradient.new()
	shades.offsets = PackedFloat32Array([0, 0.24, 0.45, 0.65, 1])
	shades.colors = PackedColorArray([Color("#25160d67"), Color("#25160d04"), Color("#5e392639"), Color("#e1b989"), Color("#e7cda7")])
	var backdrop := GradientTexture2D.new()
	backdrop.gradient = shades
	backdrop.fill_to = Vector2(0, 1)
	_portrait_shade = _picture(backdrop, TextureRect.STRETCH_SCALE)
	_portrait_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lobby_landscape.add_child(_portrait_shade)


func _fit_content() -> void:
	var viewport_size := size
	var wide := viewport_size.x >= 960 and viewport_size.x >= viewport_size.y * 1.36
	var landscape_art := viewport_size.x >= viewport_size.y * 1.12
	_wide_layout = wide
	var is_room_menu := not _room_page.is_empty() and _page == _room_page
	var is_room := _page == "room"
	var is_lobby := _page == "lobby"
	var is_training := _page in ["training", "guided"]
	var is_record := _page in ["history", "account"]
	var full_background := is_lobby or is_room_menu or is_room or is_training or is_record
	var harvest := is_lobby or is_room_menu or (is_room and _quick_room)
	_portrait_scene.texture = (MODAL.VILLAGE_LANDSCAPE if landscape_art else MODAL.VILLAGE_PORTRAIT) if harvest else TRAINING_COURTYARD if is_training or is_room or is_record else _page_art(_page)
	_portrait_scene.anchor_bottom = 1.0 if wide or full_background else 0.67
	_portrait_scene.modulate = Color.WHITE if harvest else Color(0.79, 0.76, 0.74) if is_room or is_record else Color(0.89, 0.87, 0.84) if is_training else Color.WHITE
	_portrait_shade.visible = not wide and not full_background
	_lobby_landscape.visible = full_background or not wide
	var tablet := viewport_size.x >= 800
	var horizontal_margin := clampi(roundi(viewport_size.x * 0.022), 22, 72) if wide else 36 if tablet else 22
	var vertical_margin := 13 if is_lobby else 24 if tablet else 18
	var viewport_margin := Vector2i(horizontal_margin, vertical_margin)
	var safe := RURAL.safe_insets(self)
	var safe_size := viewport_size - Vector2(safe.x + safe.z, safe.y + safe.w)
	var short_landscape := safe_size.y <= 480.0 and safe_size.x >= safe_size.y * 1.55
	var minimum_panel_width := RURAL.tablet_panel_min_width(safe_size)
	_inset.add_theme_constant_override("margin_left", viewport_margin.x + safe.x)
	_inset.add_theme_constant_override("margin_top", viewport_margin.y + safe.y)
	_inset.add_theme_constant_override("margin_right", viewport_margin.x + safe.z)
	_inset.add_theme_constant_override("margin_bottom", viewport_margin.y + safe.w + 6)
	var usable_width := safe_size.x - 2.0 * horizontal_margin
	var lobby_height := safe_size.y - 2.0 * vertical_margin - 6.0
	var max_width := minf(1370.0, lobby_height * 1.96)
	var wide_friend_room := is_room and not _quick_room and usable_width >= 880.0 and safe_size.x >= safe_size.y * 1.30
	var wide_training := _page == "training" and usable_width >= 1080.0 and safe_size.x >= safe_size.y * 1.30
	if wide or wide_friend_room or wide_training:
		if is_lobby or (is_room and _quick_room):
			max_width = minf(1260.0, lobby_height * 1.82)
	else:
		max_width = PORTRAIT_CONTENT_WIDTH if tablet else PHONE_CONTENT_WIDTH
		if is_lobby:
			max_width = 941.0
		elif is_room_menu or is_record:
			max_width = 910.0
		elif is_training or is_room:
			max_width = 925.0 if is_room and _quick_room else 880.0
	var lobby_width := clampf(usable_width, 0.0, maxf(minimum_panel_width, max_width))
	_content.custom_minimum_size.x = lobby_width
	var brand_width := clampf(minf(safe_size.x * 0.34, safe_size.y * 0.32), 88.0, 174.0)
	_viewport_brand_frame.position = Vector2(safe.x + 8, safe.y + 6)
	_viewport_brand_frame.size = Vector2(brand_width, brand_width / MODAL.VILLAGE_BRAND.get_size().aspect())
	_viewport_brand.size = _viewport_brand_frame.size
	_scroll_brand(_scroll.scroll_vertical)
	var content_left := horizontal_margin + maxf(0.0, (usable_width - lobby_width) * 0.5)
	_header_brand_slot.custom_minimum_size = Vector2(maxf(0.0, 8.0 + brand_width - content_left), 44 if is_record and _page == "account" and short_landscape else 82)
	_room_layout.vertical = _quick_room or safe_size.x < safe_size.y or lobby_width < 880.0
	_room_layout.add_theme_constant_override("separation", 30 if not _room_layout.vertical else 20)
	_room_code_row.vertical = lobby_width < 420.0
	for index in range(_content_layouts.size()):
		var layout := _content_layouts[index]
		var banner := _content_banners[index]
		layout.vertical = not wide
		layout.add_theme_constant_override("separation", 22 if wide else 0)
		banner.custom_minimum_size.y = 420 if wide else _portrait_banner_heights[index]
		banner.size_flags_vertical = Control.SIZE_FILL if wide else Control.SIZE_EXPAND_FILL
		_banner_images[index].visible = wide
		banner.add_theme_stylebox_override("panel", _surface(Color("#684328"), HONEY, 23) if wide else StyleBoxEmpty.new())
	var touch := RURAL.touch_extent(self)
	for target in _touch_sizes:
		target.custom_minimum_size.y = maxf(_touch_sizes[target], maxf(touch, 70.0 if wide else 56.0))
	if _training_grid != null and _page == "training":
		_fit_training(lobby_width, viewport_size.y, wide or wide_training, touch)
	_fit_lobby(lobby_width, lobby_height, wide, touch, is_lobby, short_landscape)
	if is_room:
		MODAL.fit_village_header(_room_village_header, lobby_width, lobby_height)
		_fit_quick_room(lobby_width, lobby_height, wide, touch)
	if is_instance_valid(_room_pages):
		_room_pages.set_page(_room_page if is_room_menu else "", wide, lobby_width,
			_room_page_parent == "directory", minimum_panel_width)


func _scroll_brand(offset: float) -> void:
	_viewport_brand.position.y = -offset


func _fit_lobby(width: float, height: float, wide: bool, touch: float, active: bool, short_landscape: bool) -> void:
	var settings_parent: Control = _profile_toolbar if active else _header_toolbar
	if _page == "room" and not _quick_room:
		settings_parent = _room_village_header
	if _settings_button.get_parent() != settings_parent:
		var was_focused := _settings_button.has_focus()
		_settings_button.reparent(settings_parent, false)
		if settings_parent == _room_village_header:
			_room_village_header.move_child(_settings_button, _leave_button.get_index())
		if was_focused: _settings_button.grab_focus.call_deferred()
	_profile_card.custom_minimum_size.x = 0.0
	_short_lobby = short_landscape and active
	var short_account := short_landscape and _page == "account"
	var compact_header := _short_lobby or short_account
	var avatar_extent := 56.0 if _short_lobby else clampf(width * (0.10 if wide else 0.145), 45.0, 112.0)
	_profile_avatar_button.custom_minimum_size = Vector2.ONE * maxf(touch, avatar_extent)
	var compact_profile := wide or width < 500.0 or compact_header
	var profile_action_height := maxf(touch, 48.0 if compact_header else clampf(width * 0.086, 44.0, 58.0 if compact_profile else 75.0))
	_egg_wallet.custom_minimum_size = Vector2(clampf(width * (0.26 if compact_profile else 0.307), 82.0, 280.0), profile_action_height)
	var action_font := 20 if compact_header else roundi(clampf(width * 0.039, 14.0, 34.0))
	_egg_wallet.add_theme_font_size_override("font_size", action_font)
	MODAL.size_icon_button(_settings_button, self)
	_identity.add_theme_font_size_override("font_size", 20 if compact_header else roundi(clampf(width * 0.037, 13.0, 38.0)))
	_connection.add_theme_font_size_override("font_size", 14 if compact_header else roundi(clampf(width * 0.025, 13.0, 22.0)))
	if not active: return
	MODAL.fit_village_header(_lobby_village_header, width, height)
	_lobby_village_header.custom_minimum_size.y = 0.0 if wide or _short_lobby else clampf(width * 0.268, 98.0, 224.0)
	MODAL.size_icon_button(_lobby_exit, self)
	_featured_actions.vertical = width < 330.0
	var compact := wide or height < 670.0
	var card_height := maxf(touch, clampf(minf(width * (0.10 if wide else 0.188), height * 0.13), 56.0, 165.0))
	var side_gap := 8 if _short_lobby else clampi(roundi(width * 0.02), 7, 20)
	_secondary_actions.add_theme_constant_override("separation", side_gap)
	_featured_actions.add_theme_constant_override("separation", side_gap)
	for button in [_create, _open_join, _room_list_button]:
		button.custom_minimum_size.y = card_height
	_quick.custom_minimum_size.y = card_height * (1.75 if _featured_actions.vertical else 3.0) + side_gap * 2.0
	var scene_gap := height * 0.075 if compact else minf(width * 0.392, height * 0.225)
	_lobby_scene_gap.custom_minimum_size.y = 0.0 if _short_lobby else clampf(scene_gap, 10.0, 365.0)
	_lobby.add_theme_constant_override("separation", 8 if _short_lobby else 13 if compact else clampi(roundi(width * 0.027), 14, 26))
	_content.add_theme_constant_override("separation", 6 if _short_lobby else 8 if compact else 13)
	var nav_height := maxf(touch, clampf(minf(width * (0.083 if wide else 0.172), height * 0.105), 56.0, 149.0))
	for button in [_training_hall_button, _history_open_button, _account_open_button, _custom_rules]:
		button.custom_minimum_size.y = nav_height
	for button in [_lobby_resume, _retry]:
		button.custom_minimum_size.y = maxf(touch, 50.0)


func _fit_training(width: float, height: float, wide: bool, touch: float) -> void:
	var split := wide and width >= 1080.0
	_training_layout.vertical = not split
	_training_layout.add_theme_constant_override("separation", 24 if split else 16)
	_training_grid.columns = 2 if split or width >= 600.0 else 1
	var banner_height := clampf(height * 0.58, 345.0, 690.0) if split else clampf(width * 0.44, 150.0, 340.0)
	_training_banner.custom_minimum_size.y = banner_height
	_training_banner.size_flags_vertical = Control.SIZE_FILL
	(_training_banner.get_child(0) as TextureRect).show()
	var card_height := banner_height - maxf(70.0, touch) - 14.0 if split else clampf(width * 0.52, 244.0, 400.0)
	for card in _training_cards:
		card.custom_minimum_size.y = card_height
	for title in _training_titles:
		title.add_theme_font_size_override("font_size", clampi(roundi(card_height * 0.095), 27, 43))
	for button in [_training, _practice, _guided_button]:
		button.custom_minimum_size.y = maxf(touch, clampf(card_height * 0.17, 58.0, 94.0))


func _page_actions(parent: VBoxContainer, page: String, separation: int) -> VBoxContainer:
	var layout := BoxContainer.new()
	layout.name = "Mahjong%sLayout" % page.capitalize()
	parent.add_child(layout)
	var banner := _build_banner(layout, page)
	banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner.size_flags_stretch_ratio = 1.08
	_content_layouts.append(layout)
	_content_banners.append(banner)
	_portrait_banner_heights.append(int(banner.custom_minimum_size.y))
	var actions := _column(layout, separation)
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.size_flags_stretch_ratio = 0.92
	return actions



func _build_lobby() -> void:
	_lobby_scene_gap = Control.new()
	_lobby_scene_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lobby.add_child(_lobby_scene_gap)
	_featured_actions = BoxContainer.new()
	_featured_actions.name = "MahjongLobbyFeaturedActions"
	_lobby.add_child(_featured_actions)
	_quick = _command_button(_featured_actions, "MahjongQuickButton", "开始游戏", "quick", true, 200, 32)
	_quick.size_flags_stretch_ratio = 1.04
	_feature_art(_quick, "与其他玩家匹配", MODAL.VILLAGE_TILES, true, true)

	_secondary_actions = _column(_featured_actions, 11)
	_secondary_actions.name = "MahjongLobbySecondaryActions"
	_secondary_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_create = _button(_secondary_actions, "MahjongCreateButton", "创建房间", false, 82, 27)
	_create.pressed.connect(_open_room_page.bind("create"))
	_feature_art(_create, "与好友组局", MODAL.art("stool"))
	_open_join = _button(_secondary_actions, "MahjongOpenJoinButton", "加入房间", false, 82, 27)
	_open_join.pressed.connect(_open_room_page.bind("join"))
	_feature_art(_open_join, "输入四位房号", FEATURE_TILES)
	_room_list_button = _button(_secondary_actions, "MahjongRoomListButton", "房间列表", false, 82, 27)
	_room_list_button.pressed.connect(_open_room_page.bind("directory"))
	_feature_art(_room_list_button, "查看公开房间", MODAL.icon("rules"))

	var navigation := MODAL.village_panel(_lobby, Vector4(12, 10, 12, 11))
	_bottom_nav = _row(navigation, 4)
	_bottom_nav.name = "MahjongLobbyNavigation"
	_training_hall_button = _button(_bottom_nav, "MahjongTrainingHallButton", "训练场", false, 60, 20)
	_training_hall_button.pressed.connect(_set_training_open.bind(true))
	_feature_art(_training_hall_button, "练习玩法", FEATURE_PAVILION, false, true)
	_history_open_button = _command_button(_bottom_nav, "MahjongHistoryOpenButton", "战绩记录", "history_open", false, 60, 20)
	_feature_art(_history_open_button, "查看战绩", MODAL.icon("rules"), false, true)
	_account_open_button = _command_button(_bottom_nav, "MahjongAccountOpenButton", "个人中心", "account_open", false, 60, 20)
	_feature_art(_account_open_button, "查看账户", PERSON_ICON, false, true)
	_custom_rules = _button(_bottom_nav, "MahjongCustomRulesButton", "自定义规则", false, 60, 20)
	_custom_rules.pressed.connect(_open_room_page.bind("create"))
	_feature_art(_custom_rules, "自选玩法并创建房间", MODAL.icon("settings"), false, true)
	var entries: Array[Button] = [_training_hall_button, _history_open_button, _account_open_button, _custom_rules]
	for index in entries.size():
		var entry := entries[index]
		entry.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		entry.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
		if index > 0:
			var divider := ColorRect.new()
			divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
			divider.color = Color("#d6b17e")
			divider.custom_minimum_size.x = 1.0
			_bottom_nav.add_child(divider)
			_bottom_nav.move_child(divider, entry.get_index())


func _feature_art(button: Button, tooltip: String, artwork: Texture2D, primary := false, vertical := false) -> void:
	MODAL.village_button(button, primary)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = tooltip
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_disabled_color", "font_focus_color", "font_outline_color"]:
		button.add_theme_color_override(state, Color.TRANSPARENT)
	var art := Control.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.clip_contents = true
	button.add_child(art)
	_feature_contents[button] = art
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	if primary:
		var gold := Panel.new()
		gold.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gold.add_theme_stylebox_override("panel", button.get_theme_stylebox("normal"))
		art.add_child(gold)
		gold.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		gold.anchor_top = 0.60
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var fill := Color("#ec9a05")
			if state in ["hover", "hover_pressed"]: fill = Color("#ffc336")
			elif state == "pressed": fill = Color("#d88107")
			elif state == "disabled": fill = Color("#c6ab77")
			var card := _surface(fill, Color("#fff1bf"), 32, 5)
			card.set_border_width_all(3)
			card.shadow_color = Color("#67360d55")
			card.shadow_offset = Vector2(0, 4)
			card.shadow_size = 6
			button.add_theme_stylebox_override(state, card)
	var picture := _picture(artwork, TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	if artwork == MODAL.icon("rules") or artwork == MODAL.icon("settings"):
		picture.self_modulate = Color("#a35812")
	elif artwork == PERSON_ICON:
		picture.self_modulate = Color("#edab39")
	art.add_child(picture)
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picture.anchor_left = 0.035 if primary else 0.08 if vertical else 0.025
	picture.anchor_right = 0.965 if primary else 0.92 if vertical else 0.33
	picture.anchor_top = 0.025 if primary else 0.06 if vertical else 0.10
	picture.anchor_bottom = (0.64 if primary else 0.59) if vertical else 0.90
	var heading := _label(art, button.text, 30, CREAM if primary else INK)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_theme_font_override("font", MODAL.village_font())
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if primary:
		heading.add_theme_constant_override("outline_size", 3)
		heading.add_theme_color_override("font_outline_color", Color("#925015"))
	heading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	heading.anchor_left = 0.03 if vertical else 0.33
	heading.anchor_right = 0.97
	heading.anchor_top = (0.63 if primary else 0.55) if vertical else 0.0
	heading.anchor_bottom = 0.95
	button.resized.connect(func() -> void:
		var scale_hint := 0.164 if primary else 0.158 if vertical else 0.133
		var font_size := clampf(button.size.x * scale_hint, 11.0, 64.0 if primary else 43.0)
		var caption_width := maxf(1.0, (button.size.x - 10.0) * (0.90 if vertical else 0.62))
		var caption_size := mini(roundi(font_size), floori(caption_width / button.text.length()))
		if _short_lobby:
			var caption_height := (button.size.y - 8.0) * (heading.anchor_bottom - heading.anchor_top)
			var line_height := heading.get_theme_font("font").get_height(roundi(font_size))
			caption_size = maxi(11, mini(caption_size, floori(font_size * caption_height / line_height)))
		heading.add_theme_font_size_override("font_size", caption_size)
	)


func _open_room_page(page: String) -> void:
	var previous := _room_page
	_room_page_parent = "directory" if previous == "directory" and page != "directory" else ""
	_room_page = page
	_render()
	if previous == "directory" or page == "directory":
		action_requested.emit("refresh_rooms" if page == "directory" else "close_rooms", {})


func _on_room_page_action(action: String, payload: Dictionary) -> void:
	match action:
		"page_back", "page_home":
			var previous := _room_page
			_room_page = _room_page_parent if action == "page_back" else ""
			_room_page_parent = ""
			_room_pages.clear_credentials()
			_render()
			if previous == "directory" or _room_page == "directory":
				action_requested.emit("refresh_rooms" if _room_page == "directory" else "close_rooms", {})
			action_requested.emit("clear_room_message", {})
		"open_create":
			_open_room_page("create")
		"open_join":
			_open_room_page("join")
		"open_watch":
			_open_room_page("join")
			_room_pages.prefill_watch(str(payload.room_id), int(payload.watch_seat))
		_:
			action_requested.emit(action, payload)


func _refresh_returned_directory() -> void:
	if _page == "directory" and is_visible_in_tree():
		action_requested.emit("refresh_rooms", {})


func _build_banner(parent: Control, page: String) -> PanelContainer:
	var banner := PanelContainer.new()
	banner.custom_minimum_size.y = 50 if page == "room" else 315 if page == "training" else 330
	banner.add_theme_stylebox_override("panel", _surface(Color("#ead8c4"), EDGE, 21))
	banner.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	parent.add_child(banner)
	var scenery := _picture(_page_art(page), TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	_banner_images.append(scenery)
	banner.add_child(scenery)
	return banner


func _page_art(page: String) -> Texture2D:
	if page == "training":
		if _training_scene != null:
			return _training_scene
		if _portrait != null:
			return _crop_image(_portrait, Rect2(0, 285, 941, 647))
	if page == "lobby" and _lobby_banner != null:
		return _lobby_banner
	return _village


func _build_training_hall() -> void:
	var toolbar := _row(_training_hall, 10)
	var back := _button(toolbar, "MahjongTrainingHallBackButton", "‹  返回大厅", false, 53)
	MODAL.button(back)
	back.pressed.connect(_set_training_open.bind(false))
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(space)
	var heading := MODAL.heading(toolbar, "训练场")
	heading.custom_minimum_size.x = 206
	var actions := _page_actions(_training_hall, "training", 13)
	_training_layout = actions.get_parent() as BoxContainer
	_training_banner = _content_banners.back()
	_training_banner.size_flags_stretch_ratio = 0.94
	actions.size_flags_stretch_ratio = 1.06
	_training_grid = GridContainer.new()
	_training_grid.columns = 2
	_training_grid.add_theme_constant_override("h_separation", 12)
	_training_grid.add_theme_constant_override("v_separation", 12)
	actions.add_child(_training_grid)

	var bots := _lesson_copy(_training_grid, true)
	var bots_title := _label(bots, "人机训练", 32, INK)
	_training_titles.append(bots_title)
	bots_title.add_theme_font_override("font", _lettering)
	bots_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_centered(bots, "与三位电脑牌友完成一局", 19, MUTED)
	_training_rule = _label(bots, "", 18, MUTED, true)
	_training_rule.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_training_rule_select = MenuButton.new()
	_training_rule_select.name = "MahjongTrainingRuleSelect"
	_training_rule_select.text = "切换玩法"
	_training_rule_select.custom_minimum_size.y = RURAL.touch_extent(self)
	_training_rule_select.about_to_popup.connect(_training_rule_menu)
	_training_rule_select.get_popup().id_pressed.connect(_select_training_rule)
	MODAL.button(_training_rule_select, "secondary")
	bots.add_child(_training_rule_select)
	_add_flexible_gap(bots)
	_training = _command_button(bots, "MahjongTrainingButton", "开始训练", "training", true, 57, 25)
	MODAL.button(_training, "primary")

	var practice := _lesson_copy(_training_grid, false)
	var practice_title := _label(practice, "摸打练习", 32, INK)
	_training_titles.append(practice_title)
	practice_title.add_theme_font_override("font", _lettering)
	practice_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_centered(practice, "练习选牌与打出", 19, MUTED)
	_add_flexible_gap(practice)
	_practice = _command_button(practice, "MahjongPracticeButton", "开始练习", "practice", true, 57, 25)
	MODAL.button(_practice, "secondary")
	_guided_button = _button(actions, "MahjongGuidedTrainingButton", "新手引导   ›", false, 60, 25)
	MODAL.button(_guided_button, "auxiliary")
	_guided_button.pressed.connect(_open_guided_training)


func _open_guided_training() -> void:
	_guided_open = true
	_render()
	_guided_view.restart()


func _close_guided_training() -> void:
	_guided_open = false
	_render()


func _lesson_copy(parent: Control, group_table: bool) -> VBoxContainer:
	var shell := PanelContainer.new()
	shell.name = "MahjongTrainingBotCard" if group_table else "MahjongTrainingPracticeCard"
	shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_theme_stylebox_override("panel", MODAL.paper_frame(Vector4(21, 21, 21, 21)))
	parent.add_child(shell)
	_training_cards.append(shell)
	var lesson := _column(shell, 10)
	_add_flexible_gap(lesson)
	var icon := LessonIcon.new()
	icon.name = "MahjongTrainingTableIcon" if group_table else "MahjongPracticeTilesIcon"
	icon.group_table = group_table
	icon.custom_minimum_size = Vector2(108, 116)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lesson.add_child(icon)
	return lesson


func _add_flexible_gap(parent: Control) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 13
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(spacer)


func _set_training_open(opened: bool) -> void:
	_training_open = opened
	_render()


func _build_room() -> void:
	_room_village_header = MODAL.village_header(_room, "MahjongLeaveButton", _back_from_room, "MahjongRoomBrandSpace", false)
	_leave_button = _room_village_header.get_child(-1) as Button
	_quick_header_gap = Control.new()
	_quick_header_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_room.add_child(_quick_header_gap)
	_quick_header_gap.hide()
	_room_board = _paper_board(_room)
	_room_staging_panel = _room_board.get_parent() as PanelContainer
	_room_staging_panel.name = "MahjongRoomBoard"
	_quick_panel = MODAL.village_panel(_room, Vector4(28, 25, 28, 28))
	_quick_panel.name = "MahjongQuickMatchPanel"
	_quick_panel.hide()
	_quick_title = MODAL.village_title(_room_board, "快速匹配", _quick_panel)
	_quick_title.get_parent().get_parent().hide()
	_room_summary = _row(_room_board, 10)
	_room_mode = _label(_room_summary, "", 28, INK)
	_room_mode.add_theme_font_override("font", _lettering)
	_room_title = _label(_room_summary, "", 19, MUTED)
	_room_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_room_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_room_layout = BoxContainer.new()
	_room_layout.name = "MahjongRoomLayout"
	_room_board.add_child(_room_layout)
	_room_info = _column(_room_layout, 14)
	_room_info.name = "MahjongRoomInfo"
	_room_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_code_row = BoxContainer.new()
	_room_code_row.name = "MahjongRoomCodePlaque"
	_room_code_row.add_theme_constant_override("separation", 13)
	_room_info.add_child(_room_code_row)
	var code_shell := PanelContainer.new()
	var plaque := _surface(DARK_WOOD, HONEY, 19, 6)
	plaque.set_border_width_all(2)
	plaque.border_blend = true
	plaque.shadow_color = Color("#56362732")
	plaque.shadow_offset = Vector2(0, 3)
	plaque.shadow_size = 4
	code_shell.add_theme_stylebox_override("panel", plaque)
	_room_code_row.add_child(code_shell)
	code_shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _wood_grain != null:
		code_shell.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		var timber := _picture(_wood_grain, TextureRect.STRETCH_KEEP_ASPECT_COVERED)
		timber.modulate = Color("#855337ad")
		code_shell.add_child(timber)
	var code_text := _row(code_shell, 13)
	code_text.alignment = BoxContainer.ALIGNMENT_CENTER
	_label(code_text, "房间号", 24, Color("#fff0d3"))
	_room_code = _label(code_text, "", 52, CREAM)
	_room_code.name = "MahjongRoomCode"
	_room_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_code.add_theme_constant_override("outline_size", 2)
	_room_code.add_theme_color_override("font_outline_color", Color("#57351f"))
	_room_copy = _button(_room_code_row, "MahjongCopyButton", "复制房号", false, 54)
	_room_copy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_room_copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_room_copy.pressed.connect(func() -> void:
		action_requested.emit("copy", {"room_id": str(_state.get("room_id", ""))}))
	_room_details = _label(_room_info, "", 23, INK, true)
	_room_details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_rule_details = _label(_room_info, "", 18, MUTED, true)
	_room_rule_details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_rule_details.name = "MahjongRoomRuleDetails"
	_room_controls = _column(_room_info, 9)
	_ready_button = _button(_room_controls, "MahjongReadyButton", "准备", true, 81, 34)
	_watch_permission = _button(_room_controls, "MahjongSeatWatchPermission", "", false, 56, 22)
	_watch_permission.hide()
	_watch_permission.pressed.connect(func() -> void:
		action_requested.emit("set_spectator_permission", {"enabled": not bool(_state.get("spectator_allowed", false))}))

	_seating = _column(_room_layout, 12)
	_seating.name = "MahjongRoomSeats"
	_seating.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seats_title = _row(_seating, 12)
	_label(_seats_title, "房间座位", 22, INK)
	_room_wallet = _label(_seats_title, "", 18, OLIVE)
	_room_wallet.name = "MahjongRoomEggBalance"
	_room_wallet.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_room_wallet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_wallet.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seat_count = _label(_seats_title, "", 18, MUTED)
	_seat_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seat_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_seat_grid = GridContainer.new()
	_seat_grid.columns = 2
	_seat_grid.add_theme_constant_override("h_separation", 12)
	_seat_grid.add_theme_constant_override("v_separation", 12)
	_seating.add_child(_seat_grid)
	for index in range(4):
		var frame := PanelContainer.new()
		frame.name = "MahjongSeat%d" % (index + 1)
		frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		frame.custom_minimum_size.y = 97
		_seat_grid.add_child(frame)
		frame.resized.connect(_fit_quick_card_inset.bind(frame), CONNECT_DEFERRED)
		var seat := _column(frame, 3)
		var avatar := PanelContainer.new()
		avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		avatar.custom_minimum_size = Vector2(86, 86)
		avatar.add_theme_stylebox_override("panel", _surface(Color("#dfc3a0"), Color("#bc965f"), 48))
		avatar.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		seat.add_child(avatar)
		var icon := _picture(RURAL.BRAND, TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
		avatar.add_child(icon)
		var details := _column(seat, 2)
		details.alignment = BoxContainer.ALIGNMENT_CENTER
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var player := _label(details, "", 22, INK)
		player.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		player.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		player.mouse_filter = Control.MOUSE_FILTER_PASS
		var badge := PanelContainer.new()
		badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		details.add_child(badge)
		var status := _label(badge, "", 16, MUTED)
		var ready_bar := ProgressBar.new()
		ready_bar.max_value = 1.0
		ready_bar.show_percentage = false
		ready_bar.custom_minimum_size = Vector2(90, 6)
		ready_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ready_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ready_bar.add_theme_stylebox_override("background", _surface(Color("#e8cfad"), Color("#cda57b"), 5))
		ready_bar.add_theme_stylebox_override("fill", _surface(Color("#75875b"), Color("#5b7148"), 5))
		details.add_child(ready_bar)
		_seat_frames.append(frame)
		_seat_names.append(player)
		_seat_statuses.append(status)
		_seat_badges.append(badge)
		_seat_icons.append(icon)
		_seat_ready_bars.append(ready_bar)
		_seat_portraits.append(RURAL.seat_portrait(index))
	_ready_count = _label(_seating, "", 21, INK)
	_ready_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ready_progress = ProgressBar.new()
	_ready_progress.name = "MahjongReadyProgress"
	_ready_progress.show_percentage = false
	_ready_progress.custom_minimum_size.y = 14
	_ready_progress.add_theme_stylebox_override("background", _surface(Color("#e7d6bd"), Color("#c1a687"), 7))
	_ready_progress.add_theme_stylebox_override("fill", _surface(Color("#758d60"), OLIVE, 7))
	_seating.add_child(_ready_progress)
	_room_note = _label(_seating, "", 18, MUTED, true)
	_room_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ready_button.pressed.connect(func() -> void:
		var ready_accounts: Array = _state.get("ready_account_ids", [])
		var own_ready := str(_account.get("account_id", "")) in ready_accounts
		action_requested.emit("unready" if own_ready else "ready", {})
	)
	_ready_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resume = _command_button(_room_info, "MahjongResumeButton", "返回牌桌", "resume", true, 70)
	_quick_footer = _column(_room_board, 9)
	_quick_footer.hide()


func _set_quick_room(active: bool) -> void:
	if active == _quick_room:
		return
	_quick_room = active
	_room_board.reparent(_quick_panel if active else _room_staging_panel, false)
	_quick_panel.visible = active
	_room_staging_panel.visible = not active
	_quick_header_gap.visible = active
	_quick_title.get_parent().get_parent().visible = active
	_room_summary.visible = not active
	_room_code_row.visible = not active
	_room_details.visible = not active
	_seats_title.visible = not active
	_ready_progress.visible = not active
	_quick_footer.visible = active
	_ready_count.reparent(_room_info if active else _seating, false)
	if active:
		_room_controls.reparent(_quick_footer, false)
		_room_note.reparent(_quick_footer, false)
		_quick_footer.move_child(_room_note, 0)
		MODAL.village_button(_ready_button, true)
		_room_note.add_theme_stylebox_override("normal", MODAL.list_row())
		_room_note.add_theme_font_override("font", MODAL.village_font())
		_room_note.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_room_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_ready_count.add_theme_font_override("font", MODAL.village_font())
		_room_controls.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	else:
		_room_controls.reparent(_room_info, false)
		_room_info.move_child(_room_controls, _resume.get_index())
		_room_note.reparent(_seating, false)
		_seating.move_child(_ready_count, _ready_progress.get_index())
		_skin_button(_ready_button, true, 34)
		_room_note.remove_theme_stylebox_override("normal")
		_room_note.remove_theme_font_override("font")
		_room_note.size_flags_horizontal = Control.SIZE_FILL
		_room_note.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_ready_count.remove_theme_font_override("font")
		_room_controls.size_flags_horizontal = Control.SIZE_FILL
		_room_controls.custom_minimum_size.x = 0.0
	for bar in _seat_ready_bars:
		bar.visible = not active


func _fit_quick_room(width: float, height: float, wide: bool, touch: float) -> void:
	var portrait_size := Vector2(86, 86)
	if _quick_room:
		var extent := clampf(minf(width * 0.195, height * 0.132), 46.0, 167.0)
		portrait_size = Vector2.ONE * extent
		_quick_header_gap.custom_minimum_size.y = 0.0 if wide else clampf(height * 0.054, 17.0, 84.0)
		_quick_title.add_theme_font_size_override("font_size", roundi(clampf(width * 0.061, 24.0, 51.0)))
		(_quick_title.get_parent() as Control).custom_minimum_size = Vector2(clampf(width * 0.55, 156.0, 462.0), clampf(height * 0.078, 52.0, 104.0))
		_ready_count.add_theme_font_size_override("font_size", roundi(clampf(width * 0.048, 19.0, 41.0)))
		_room_controls.custom_minimum_size.x = clampf(width * 0.72, 160.0, 640.0)
		_room_note.custom_minimum_size = Vector2(clampf(width * 0.61, 145.0, 446.0), 26.0 if wide else clampf(height * 0.032, 24.0, 53.0))
		_room_note.add_theme_font_size_override("font_size", roundi(clampf(width * 0.034, 16.0, 30.0)))
		_ready_button.custom_minimum_size.y = maxf(touch, clampf(height * 0.089, 48.0, 134.0))
		_ready_button.add_theme_font_size_override("font_size", roundi(clampf(width * 0.063, 24.0, 50.0)))
		_room_board.add_theme_constant_override("separation", 10 if wide else clampi(roundi(height * 0.014), 13, 22))
		_quick_panel.custom_minimum_size.y = minf(height * (0.64 if wide else 0.76), width * (0.55 if wide else 1.36))
		_room_layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_seating.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_seat_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_quick_footer.add_theme_constant_override("separation", 9 if wide else clampi(roundi(height * 0.011), 11, 20))
		_seat_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_seat_grid.custom_minimum_size.x = maxf(1.0, minf(width - 58.0, width * 0.82))
	else:
		_room_note.custom_minimum_size = Vector2.ZERO
		_room_note.add_theme_font_size_override("font_size", 18)
		_ready_count.add_theme_font_size_override("font_size", 21)
		_ready_button.custom_minimum_size.y = maxf(touch, 81.0)
		_ready_button.add_theme_font_size_override("font_size", 34)
		_room_board.add_theme_constant_override("separation", 12)
		_room_layout.size_flags_vertical = Control.SIZE_FILL
		_seating.size_flags_vertical = Control.SIZE_FILL
		_seat_grid.size_flags_vertical = Control.SIZE_FILL
		_seat_grid.size_flags_horizontal = Control.SIZE_FILL
		_seat_grid.custom_minimum_size.x = 0.0
	for slot in _seat_icons.size():
		var avatar := _seat_icons[slot].get_parent() as PanelContainer
		avatar.custom_minimum_size = portrait_size
		var seat := avatar.get_parent() as VBoxContainer
		seat.alignment = BoxContainer.ALIGNMENT_CENTER if _quick_room else BoxContainer.ALIGNMENT_BEGIN
		var ring := _surface(Color("#dfc3a0"), Color("#e4a822") if _quick_room else Color("#bc965f"), ceili(portrait_size.x * 0.5))
		ring.set_border_width_all(3 if _quick_room else 2)
		avatar.add_theme_stylebox_override("panel", ring)
		if _quick_room:
			_seat_names[slot].add_theme_font_override("font", MODAL.village_font())
			_seat_statuses[slot].add_theme_font_override("font", MODAL.village_font())
			_seat_statuses[slot].horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_seat_frames[slot].size_flags_vertical = Control.SIZE_EXPAND_FILL
			_seat_frames[slot].custom_minimum_size.y = 97.0 if wide else clampf(minf(height * 0.183, width * 0.35), 112.0, 309.0)
			_seat_badges[slot].custom_minimum_size.x = clampf(width * 0.22, 58.0, 176.0)
		else:
			_seat_names[slot].remove_theme_font_override("font")
			_seat_statuses[slot].remove_theme_font_override("font")
			_seat_statuses[slot].horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			_seat_frames[slot].size_flags_vertical = Control.SIZE_FILL
			_seat_frames[slot].custom_minimum_size.y = 97.0
			_seat_badges[slot].custom_minimum_size.x = 0.0
		_seat_names[slot].add_theme_font_size_override("font_size", roundi(clampf(width * 0.038, 16.0, 32.0)) if _quick_room else 22)
		_seat_statuses[slot].add_theme_font_size_override("font_size", roundi(clampf(width * 0.027, 13.0, 23.0)) if _quick_room else 16)
	_seat_grid.columns = 4 if _quick_room and wide and height < 755.0 else 2


func _back_from_room() -> void:
	if _state.get("status") == "playing":
		_room_collapsed = true
		_render()
	else:
		action_requested.emit("leave", {})


func _render() -> void:
	var previous_status := str(_state.get("status", "idle"))
	_state = _data.get("state", {})
	_account = _data.get("account", {})
	var status := str(_state.get("status", "idle"))
	if status != "playing": _room_collapsed = false
	var has_room := status in ["waiting", "matched", "playing"] and not _room_collapsed
	if has_room and _page != "room": _room_pages.clear_credentials()
	var history: Dictionary = _data.get("history", {})
	var privacy: Dictionary = _data.get("privacy", {})
	var page := "account" if privacy.get("open", false) else "room" if has_room else "history" if history.get("open", false) else _room_page if not _room_page.is_empty() else "guided" if _guided_open else "training" if _training_open else "lobby"
	if _room_collapsed: page = "lobby"
	var returning_to_directory := previous_status != "idle" and page == "directory"
	var page_changed := page != _page
	var quick: bool = page == "room" and _state.get("kind") == "quick" and status != "playing"
	var room_layout_changed := quick != _quick_room
	_set_quick_room(quick)
	if page_changed:
		_scroll.set_deferred("scroll_vertical", 0)
		_page = page
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		_scroll.follow_focus = true
		_content.add_theme_constant_override("separation", 12)
	_lobby.visible = page == "lobby"
	_lobby_village_header.visible = page == "lobby"
	var showing_room_menu := not _room_page.is_empty() and page == _room_page
	_header_shell.visible = not showing_room_menu and page not in ["room", "guided"]
	_header_brand_slot.visible = page != "lobby"
	_profile_avatar_button.visible = page == "lobby"
	if page_changed or not _header_shell.has_theme_stylebox_override("panel"):
		var header_style: StyleBox = StyleBoxEmpty.new() if page == "lobby" else _surface(Color("#322117ed"), Color("#895d3e"), 21, 9)
		_header_shell.add_theme_stylebox_override("panel", header_style)
		var profile_style: StyleBox = MODAL.paper_frame(Vector4(14, 8, 16, 9)) if page == "lobby" else StyleBoxEmpty.new()
		_profile_card.add_theme_stylebox_override("panel", profile_style)
		var feedback_style: StyleBox = _surface(Color("#312015ed"), Color("#bb8b58"), 15, 6) if page == "lobby" else StyleBoxEmpty.new()
		_feedback_shell.add_theme_stylebox_override("panel", feedback_style)
	if page_changed or room_layout_changed: _fit_content()
	_room.visible = page == "room"
	_training_hall.visible = page == "training"
	_guided_view.visible = page == "guided"
	_personal_history.visible = page == "history"
	_account_view.visible = page == "account"
	if _account_view.visible and _account_view.apply(privacy):
		_scroll.set_deferred("scroll_vertical", 0)
	if _personal_history.visible:
		var showing_detail := not str(history.get("match_id", "")).is_empty()
		if showing_detail != _history_detail_open:
			if showing_detail: _history_list_scroll = _scroll.scroll_vertical
			_scroll.set_deferred("scroll_vertical", 0 if showing_detail else _history_list_scroll)
			_history_detail_open = showing_detail
		_personal_history.apply(history)
	else:
		_history_detail_open = false

	var online := bool(_data.get("online", false))
	var pending := bool(_data.get("pending", false))
	var connecting := bool(_data.get("connecting", false))
	var compact_feedback := _feedback.visible and _lobby_resume.visible
	_egg_wallet.visible = page == "lobby" and bool(_data.get("wallet_available", false))
	var eggs := int(_data.get("egg_balance", -1))
	_egg_wallet.text = "鸡蛋 %d" % eggs if eggs >= 0 else "查询鸡蛋余额"
	_lobby_back.tooltip_text = "返回游客身份" if _account.get("kind") == "guest" else "返回登录"
	_header_avatar.texture = MODAL.VILLAGE_GUEST if _account.get("kind") == "guest" else PROFILE_ICON
	_lobby_back.disabled = pending
	_lobby_exit.disabled = pending
	_lobby_resume.visible = page == "lobby" and _room_collapsed
	_lobby_resume.disabled = not online or pending
	_connection.text = "●  服务在线" if online else "●  连接中" if connecting else "●  连接未就绪"
	_connection.add_theme_color_override("font_color", (Color("#356841") if online else Color("#8d582f")) if page == "lobby" else (Color("#c5e899") if online else Color("#ffe1b7")))
	_identity.text = _account_name()
	_identity.add_theme_color_override("font_color", INK if page == "lobby" else CREAM)
	var account_kind := "游客" if _account.get("kind") == "guest" else "账号"
	var identifier := str(_account.get("account_id", "")).strip_edges()
	var account_details := account_kind if identifier.is_empty() else "%s · %s" % [account_kind, identifier]
	_identity.tooltip_text = "%s\n%s" % [_identity.text, account_details]
	_profile_avatar_button.tooltip_text = "个人中心\n" + account_details
	_message.text = str(_data.get("message", ""))
	_message.tooltip_text = _message.text
	_message.autowrap_mode = TextServer.AUTOWRAP_OFF if page == "lobby" else TextServer.AUTOWRAP_WORD_SMART
	_message.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if page == "lobby" else TextServer.OVERRUN_NO_TRIMMING
	_message.visible = not _message.text.is_empty() and not showing_room_menu
	_retry.visible = not online and not connecting
	_retry.disabled = pending
	_feedback.visible = page not in ["account", "guided"] and (_message.visible or _retry.visible)
	_feedback_shell.visible = _feedback.visible
	if page == "lobby" and compact_feedback != (_feedback.visible and _lobby_resume.visible):
		_fit_content()
	_room_pages.apply(_data)

	_presets = _data.get("presets", [])
	if has_room:
		_render_room(status, online, pending)
	else:
		_render_lobby(online, pending)
	if returning_to_directory: _refresh_returned_directory.call_deferred()


func _render_lobby(online: bool, pending: bool) -> void:
	var idle: bool = _state.get("status", "idle") == "idle"
	var selected: Dictionary = _data.get("selected", {})
	var index := _rule_index(selected)
	var can_start := idle and online and not pending and index >= 0
	var friend_and_training_only: bool = index >= 0 and _presets[index].get("quick_match", true) == false
	_quick.disabled = not can_start or friend_and_training_only
	_quick.tooltip_text = "当前玩法开放好友房与人机训练，可在训练场切换玩法" if friend_and_training_only else "与其他玩家匹配"
	_create.disabled = not idle or not online or pending or _presets.is_empty()
	_open_join.disabled = pending or not online or not idle
	_room_list_button.disabled = pending or not online or not idle
	_custom_rules.disabled = _create.disabled
	_training_hall_button.disabled = pending or not idle
	_history_open_button.disabled = pending or not idle
	_account_open_button.disabled = pending or not bool(_data.get("privacy", {}).get("available", false))
	_profile_avatar_button.disabled = _account_open_button.disabled or not idle
	_training.disabled = not can_start
	_practice.disabled = pending or not idle
	_guided_button.disabled = pending or not idle
	_training_rule.text = "当前玩法 · %s" % _rule_name(_presets[index]) if index >= 0 else "暂无可用训练玩法"
	_training_rule_select.visible = _presets.size() > 1
	_training_rule_select.disabled = pending or not idle
	for entry in _feature_contents:
		_feature_contents[entry].modulate.a = 0.66 if entry.disabled else 1.0


func _training_rule_menu() -> void:
	var menu := _training_rule_select.get_popup()
	menu.clear()
	var selected := _rule_index(_data.get("selected", {}))
	for index in range(_presets.size()):
		menu.add_radio_check_item(_rule_name(_presets[index]), index)
		menu.set_item_checked(index, index == selected)


func _select_training_rule(index: int) -> void:
	if index < 0 or index >= _presets.size(): return
	var rule: Dictionary = _presets[index]
	action_requested.emit("select", {"rule_set_id":rule.rule_set_id, "rule_version":rule.rule_version})


func _render_room(status: String, online: bool, pending: bool) -> void:
	var playing := status == "playing"
	var next_hand := int(_state.get("completed_rounds", 0)) > 0 or not str(_state.get("previous_match_id", "")).is_empty()
	var kind := str(_state.get("kind", ""))
	var admission_paused := kind == "friend" and not playing and bool(_state.get("admission_paused", false))
	_room_title.text = "牌局进行中" if playing else "暂停入座" if admission_paused else "下一局准备" if next_hand else "开局准备" if status == "matched" else "等待牌友入座"
	_room_mode.text = str(ROOM_MODES.get(kind, "麻将房间"))
	var room_id := str(_state.get("room_id", ""))
	_room_code.text = room_id if not room_id.is_empty() else "— — — —"
	_room_copy.visible = not playing
	_room_copy.disabled = room_id.is_empty()
	var index := _rule_index(_state)
	var locked_rule: Dictionary = _state.get("rule", {})
	if locked_rule.is_empty() and index >= 0:
		locked_rule = _presets[index]
	var fallback_rule := {"name": "贵阳麻将", "rule_version": _state.get("rule_version", "")}
	_room_details.text = _rule_name(locked_rule if not locked_rule.is_empty() else fallback_rule)
	var round_limit := int(_state.get("round_limit", 0))
	if round_limit > 0:
		_room_details.text += " · %d/%d 局" % [int(_state.get("completed_rounds", 0)) + 1, round_limit]
	if int(_state.get("turn_timeout_seconds", 0)) > 0:
		_room_details.text += " · 出牌 %d 秒" % int(_state.turn_timeout_seconds)
	_room_details.tooltip_text = _room_details.text
	_room_rule_details.text = "暂无玩法说明" if locked_rule.is_empty() else _room_rule_text(locked_rule)
	_room_rule_details.visible = not playing and not _quick_room
	var eggs := int(_data.get("egg_balance", -1))
	_room_wallet.text = "鸡蛋 %d" % eggs if eggs >= 0 else "鸡蛋 —"
	_room_wallet.tooltip_text = _room_wallet.text
	_room_wallet.visible = bool(_data.get("wallet_available", false))
	_seating.visible = not playing
	_ready_count.visible = not playing
	_quick_footer.visible = _quick_room and not playing
	_room_controls.visible = not playing
	_watch_permission.visible = not playing and kind == "friend" and bool(_state.get("allow_spectators", false))
	_watch_permission.disabled = not online or pending
	var open_to_watch := bool(_state.get("spectator_allowed", false))
	_watch_permission.text = "关闭本座观战" if open_to_watch else "开放本座观战"
	if bool(_state.get("spectator_occupied", false)): _watch_permission.text += " · 1人"
	_resume.visible = playing
	_resume.disabled = not online or pending
	_leave_button.tooltip_text = "回到大厅，稍后可返回牌桌" if playing else "离开房间并返回上一页"
	_leave_button.disabled = pending or (not playing and not online)
	if playing:
		return

	var players: Array = _state.get("player_account_ids", [])
	var ready_players: Array = _state.get("ready_account_ids", [])
	var reconnecting_players: Array = _state.get("reconnecting_account_ids", [])
	var own_id := str(_account.get("account_id", ""))
	var capacity := maxi(1, int(_state.get("capacity", 4)))
	var ready_count := clampi(int(_state.get("ready_players", ready_players.size())), 0, capacity)
	var room_full := players.size() == capacity
	var waiting_friend := kind == "friend" and status == "waiting"
	var own_ready := not own_id.is_empty() and own_id in ready_players
	_seat_count.text = "%d / %d" % [players.size(), capacity]
	_ready_count.text = "已准备 %d / %d" % [ready_count, capacity]
	_ready_progress.max_value = capacity
	_ready_progress.set_value_no_signal(ready_count)
	for slot in range(_seat_frames.size()):
		var id := str(players[slot]) if slot < players.size() else ""
		_render_seat(slot, id, own_id, id in ready_players, id in reconnecting_players)
	_room_note.text = "已准备，等待其他牌友" if own_ready else "全部准备后开始下一局" if next_hand else "全部准备后开局"
	if not room_full:
		_room_note.text = "满四位且全部准备后开局" if waiting_friend else "等待其他牌友入座"
	if admission_paused:
		_room_note.text = "已准备，等待恢复入座" if own_ready else "已入座的牌友可继续准备"
	_ready_button.text = "取消准备" if own_ready else "准备"
	_ready_button.disabled = not online or pending or own_id not in players or not (waiting_friend or (status == "matched" and room_full))


func _render_seat(slot: int, id: String, own_id: String, is_ready: bool, reconnecting: bool) -> void:
	var empty := id.is_empty()
	var is_self := not empty and id == own_id
	var ready_badge := is_ready and not reconnecting
	var fill := Color("#f1dfbd") if empty else Color("#c8dfb9") if ready_badge else Color("#d7e6c8") if is_self else Color("#e1ebd4")
	var border := Color("#c9aa79") if empty else Color("#7e9b6d") if is_self or ready_badge else Color("#a1b590")
	if _quick_room:
		_seat_frames[slot].add_theme_stylebox_override("panel", MODAL.paper_frame(Vector4(9, 8, 9, 9)))
		_fit_quick_card_inset(_seat_frames[slot])
	else:
		_seat_frames[slot].add_theme_stylebox_override("panel", _surface(fill, border, 16, 10))
	var account_name := _account_name()
	var player_name := "你" if account_name.is_empty() else "%s（你）" % account_name
	_seat_names[slot].text = "空座" if empty else player_name if is_self else "牌友 · %s" % id.right(5)
	_seat_names[slot].tooltip_text = _seat_names[slot].text
	_seat_names[slot].add_theme_color_override("font_color", MUTED if empty else INK)
	_seat_statuses[slot].text = "等待加入" if empty else "重连中" if reconnecting else "已准备" if is_ready else "未准备"
	if _quick_room: _seat_statuses[slot].text = "●  " + _seat_statuses[slot].text
	_seat_statuses[slot].add_theme_color_override("font_color", (Color("#2b460e") if _quick_room else Color("#fff8e9")) if ready_badge else MUTED)
	_seat_badges[slot].add_theme_stylebox_override("panel", _surface(
		(Color("#e6edaa") if _quick_room else OLIVE) if ready_badge else Color("#e9d8c0"),
		(Color("#8e9f43") if _quick_room else Color("#4d6340")) if ready_badge else Color("#d8c1a5"), 14, 5))
	var avatar: Texture2D = RURAL.BRAND if empty else _seat_portraits[slot]
	if _quick_room and not empty:
		avatar = MODAL.VILLAGE_GUEST if is_self and _account.get("kind") == "guest" else VILLAGE_SEATS[slot]
	_seat_icons[slot].texture = avatar
	_seat_ready_bars[slot].set_value_no_signal(1.0 if is_ready else 0.0)


func _fit_quick_card_inset(frame: PanelContainer) -> void:
	if not is_instance_valid(frame) or not _quick_room:
		return
	var skin := frame.get_theme_stylebox("panel")
	if not skin.has_method("border_scale_for_size"):
		return
	# The bamboo and its shadow extend 88 source pixels into each side.
	var inset := ceilf(88.0 * float(skin.call("border_scale_for_size", frame.size)) + 3.0)
	for side in [SIDE_LEFT, SIDE_RIGHT]:
		if not is_equal_approx(skin.get_content_margin(side), inset):
			skin.set_content_margin(side, inset)


func _rule_index(selection: Dictionary) -> int:
	for index in range(_presets.size()):
		var preset: Dictionary = _presets[index]
		if str(preset.get("rule_set_id", "")) == str(selection.get("rule_set_id", "")) and str(preset.get("rule_version", "")) == str(selection.get("rule_version", "")):
			return index
	return -1


func _rule_name(preset: Dictionary) -> String:
	var title := str(preset.get("name", "贵阳麻将"))
	var version := str(preset.get("rule_version", ""))
	return title if version.is_empty() else "%s  ·  %s" % [title, version]


func _rule_description(preset: Dictionary) -> String:
	var summary := str(preset.get("summary", "")).strip_edges()
	if not summary.is_empty():
		return summary
	var rules := PackedStringArray([
		"可吃" if preset.get("allow_chi", false) else "不可吃",
		"捉鸡" if preset.get("chicken", false) else "不捉鸡",
		"本人完成杠后可接炮胡" if preset.get("requires_kong_to_claim", false) else "接炮胡不要求开杠",
	])
	return "  ·  ".join(rules)


func _room_rule_text(rule: Dictionary) -> String:
	var summary := _rule_description(rule)
	var version := str(rule.get("options", {}).get("version", ""))
	if version == "2.0.0" and rule.get("dingque") == true:
		var options: Dictionary = rule.options
		var chicken := "计鸡分" if options.get("chicken") == true else "不计鸡分"
		var rob := "可抢补杠胡" if options.get("rob_kong") == true else "关闭抢杠胡"
		return summary + "\n定缺 · 无需先杠 · %s · %s" % [chicken, rob]
	if version != "1.0.0":
		return summary
	var options: Dictionary = rule["options"]
	var settings := PackedStringArray()
	for key in ROOM_PAGES.OPTIONS:
		var caption: String = ROOM_PAGES.OPTIONS[key][1]
		if key in ["charge_chicken", "black_eight"]:
			if bool(options.get(key, false)):
				settings.append(caption)
		else:
			settings.append(caption if bool(options.get(key, false)) else "不" + caption)
	return summary + "\n" + " · ".join(settings)


func _account_name() -> String:
	return str(_account.get("display_name", "")).strip_edges()


func _button(parent: Control, node_name: String, caption: String, primary: bool, height: int, font_size: int = 23) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = caption
	button.custom_minimum_size.y = height
	_touch_sizes[button] = height
	_skin_button(button, primary, font_size)
	parent.add_child(button)
	return button


func _command_button(parent: Control, node_name: String, caption: String, command: String, primary: bool, height: int, font_size: int = 23) -> Button:
	var button := _button(parent, node_name, caption, primary, height, font_size)
	button.pressed.connect(func() -> void: action_requested.emit(command, {}))
	return button


func _skin_button(button: Button, primary: bool, font_size: int) -> void:
	RURAL.skin_button(button, primary)
	button.add_theme_font_size_override("font_size", font_size)


func _skin_tinted_button(button: Button, fill: Color, border: Color, text: Color) -> void:
	var normal := _surface(fill, border, 21, 11)
	normal.border_width_bottom = 3
	normal.shadow_color = Color("#26150952")
	normal.shadow_offset = Vector2(0, 3)
	normal.shadow_size = 5
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", _surface(fill.lightened(0.12), border.lightened(0.13), 21, 11))
	button.add_theme_stylebox_override("pressed", _surface(fill.darkened(0.16), border, 21, 11))
	for state_name in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state_name, text)


func _paper_board(parent: Control) -> VBoxContainer:
	var board := PanelContainer.new()
	board.add_theme_stylebox_override("panel", MODAL.paper_frame(Vector4(24, 26, 24, 26)))
	parent.add_child(board)
	return _column(board, 10)


func _surface(fill: Color, border: Color, radius: int, padding: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, padding)
	return style


func _column(parent: Control, separation: int) -> VBoxContainer:
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", separation)
	parent.add_child(layout)
	return layout


func _row(parent: Control, separation: int) -> HBoxContainer:
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", separation)
	parent.add_child(layout)
	return layout


func _label(parent: Control, caption: String, font_size: int, color: Color, wrap: bool = false) -> Label:
	var label := Label.new()
	label.text = caption
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _label_centered(parent: Control, caption: String, font_size: int, color: Color) -> void:
	var label := _label(parent, caption, font_size, color, true)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _picture(texture: Texture2D, mode: TextureRect.StretchMode) -> TextureRect:
	var picture := TextureRect.new()
	picture.texture = texture
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = mode
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return picture


func _crop_image(texture: Texture2D, region: Rect2) -> AtlasTexture:
	if texture == null:
		return null
	var crop := AtlasTexture.new()
	crop.atlas = texture
	crop.region = region
	crop.filter_clip = true
	return crop


func _gradient(top: Color, bottom: Color) -> TextureRect:
	var colors := Gradient.new()
	colors.colors = PackedColorArray([top, bottom])
	var texture := GradientTexture2D.new()
	texture.gradient = colors
	texture.fill_to = Vector2(0, 1)
	return _picture(texture, TextureRect.STRETCH_SCALE)


func _texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return null
	return ImageTexture.create_from_image(image)
