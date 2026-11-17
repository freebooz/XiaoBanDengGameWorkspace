extends Control
## Post-authentication identity confirmation. The app owns the session and navigation.

const RURAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_theme.gd")
const MODAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_modal.gd")
const UI := "res://modules/games/mahjong/guiyang/assets/ui/"
const ENTRY_ICON := preload(UI + "harvest/icon_person_cream.svg")
const FEATURES := [
	["快速体验", preload(UI + "harvest/icon_lightning.svg")],
	["免注册畅玩", preload(UI + "harvest/icon_gamepad.svg")],
	["体验全部玩法", preload(UI + "harvest/icon_gift.svg")],
]

var enter_button: Button
var _background: TextureRect
var _shell: MarginContainer
var _header: HBoxContainer
var _body: VBoxContainer
var _space: Control
var _portrait: TextureRect
var _features: GridContainer
var _title: Label
var _nickname: Label
var _panel: PanelContainer
var _content: VBoxContainer
var _sections: BoxContainer
var _identity: VBoxContainer
var _actions: VBoxContainer
var _info: Label
var _footer_art: TextureRect


func build(display_name: String, saved: bool, go_back: Callable, enter_lobby: Callable) -> void:
	_background = _art(self, MODAL.VILLAGE_PORTRAIT)
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_footer_art = _art(self, MODAL.VILLAGE_TILES)
	_shell = MarginContainer.new()
	_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_shell)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	_shell.add_child(column)
	_header = MODAL.village_header(column, "MahjongGuestIdentityBackButton", go_back)
	var scroll := ScrollContainer.new()
	scroll.name = "MahjongGuestIdentityScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	_body = VBoxContainer.new()
	center.add_child(_body)
	_space = Control.new()
	_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_space)

	var panel := MODAL.village_panel(_body, Vector4(23, 20, 23, 25))
	_panel = panel
	var content := VBoxContainer.new()
	_content = content
	content.add_theme_constant_override("separation", 8)
	panel.add_child(content)
	_title = MODAL.village_title(content, "游客身份", panel)
	_sections = BoxContainer.new()
	_sections.vertical = true
	_sections.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sections.add_theme_constant_override("separation", 14)
	content.add_child(_sections)
	_identity = VBoxContainer.new()
	_identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_identity.alignment = BoxContainer.ALIGNMENT_CENTER
	_sections.add_child(_identity)
	_actions = VBoxContainer.new()
	_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_actions.add_theme_constant_override("separation", 14)
	_sections.add_child(_actions)
	_portrait = _art(_identity, MODAL.VILLAGE_GUEST)
	_portrait.name = "MahjongGuestAvatar"
	_portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_nickname = _caption(_identity, display_name, 28)
	_nickname.name = "MahjongGuestNickname"
	_nickname.tooltip_text = display_name
	_nickname.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_nickname.add_theme_font_override("font", MODAL.village_font())
	_nickname.add_theme_stylebox_override("normal", MODAL.capsule_frame(Vector4(20, 3, 20, 8)))
	_nickname.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var feature_card := PanelContainer.new()
	var feature_style := MODAL.list_row()
	feature_style.bg_color = Color("#fff0d5b0")
	feature_style.border_color = Color("#fff9e8")
	feature_style.set_corner_radius_all(24)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		feature_style.set_content_margin(side, 8)
	feature_card.add_theme_stylebox_override("panel", feature_style)
	_actions.add_child(feature_card)
	_features = GridContainer.new()
	_features.columns = FEATURES.size()
	_features.add_theme_constant_override("h_separation", 4)
	feature_card.add_child(_features)
	for item in FEATURES:
		var feature := VBoxContainer.new()
		feature.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		feature.add_theme_constant_override("separation", 1)
		_features.add_child(feature)
		_art(feature, item[1]).custom_minimum_size.y = 30
		_caption(feature, item[0], 16).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	enter_button = Button.new()
	enter_button.name = "MahjongGuestEnterLobbyButton"
	enter_button.text = "游客登录"
	enter_button.icon = ENTRY_ICON
	enter_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	enter_button.add_theme_color_override("icon_normal_color", MODAL.CREAM)
	enter_button.expand_icon = true
	enter_button.add_theme_constant_override("icon_max_width", 28)
	enter_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_actions.add_child(enter_button)
	MODAL.village_button(enter_button, true)
	enter_button.add_theme_font_override("font", MODAL.village_font())
	enter_button.pressed.connect(enter_lobby)

	var info := _caption(_actions, "本设备保存登录凭据，下次可继续使用此游客身份。" if saved else "当前登录有效，本设备无法保存此游客身份。", 15)
	_info = info
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_color_override("font_color", MODAL.MUTED if saved else MODAL.NEGATIVE)
	resized.connect(_fit)
	_fit.call_deferred()


func navigate_back() -> bool:
	var back := _header.get_child(-1) as Button
	if not back.is_visible_in_tree() or back.disabled:
		return false
	back.pressed.emit()
	return true


func _fit() -> void:
	var safe := RURAL.safe_insets(self)
	var available := size - Vector2(safe.x + safe.z, safe.y + safe.w)
	var wide := available.x >= available.y * 1.5
	var edge := roundi(clampf(size.x * 0.024, 10.0, 32.0))
	_shell.add_theme_constant_override("margin_left", safe.x + edge)
	_shell.add_theme_constant_override("margin_right", safe.z + edge)
	_shell.add_theme_constant_override("margin_top", safe.y + edge)
	_shell.add_theme_constant_override("margin_bottom", safe.w + edge)
	var width := maxf(0, available.x - edge * 2)
	var touch := RURAL.touch_extent(self)
	MODAL.fit_village_header(_header, width, size.y)
	_background.texture = MODAL.VILLAGE_LANDSCAPE if available.x >= available.y * 0.85 else MODAL.LOGIN_BACKDROP
	# Keep the reference scale for artwork and control heights as the panel widens.
	var design_width := minf(width - 12.0, 1180.0 if wide else minf(900.0, maxf(360.0, available.y * 900.0 / 1672.0)))
	var content_width := minf(width - 12.0, maxf(design_width, RURAL.tablet_panel_min_width(available)))
	var unit := clampf(design_width / 884.0, 0.40, 1.0)
	if wide: unit = clampf(available.y / 941.0, 0.48, 1.0)
	_body.custom_minimum_size.x = maxf(0, content_width)
	_sections.vertical = not wide
	_sections.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_sections.add_theme_constant_override("separation", roundi(28.0 * unit if wide else 14.0 * unit))
	_identity.size_flags_stretch_ratio = 0.8 if wide else 1.0
	_space.custom_minimum_size.y = 10.0 if wide else maxf(8.0, 494.0 * unit - edge - _header.get_combined_minimum_size().y - 5.0)
	_panel.custom_minimum_size.y = 500.0 * unit if wide else 940.0 * unit
	_content.add_theme_constant_override("separation", roundi(14.0 * unit))
	_identity.add_theme_constant_override("separation", roundi(4.0 * unit))
	_actions.add_theme_constant_override("separation", roundi(18.0 * unit))
	var portrait_size := maxf(100.0, 280.0 * unit)
	_portrait.custom_minimum_size = Vector2.ONE * portrait_size
	_title.get_parent().custom_minimum_size = Vector2(maxf(190.0, 540.0 * unit), maxf(51.0, 114.0 * unit))
	_title.add_theme_font_size_override("font_size", roundi(maxf(27.0, 55.0 * unit)))
	_nickname.custom_minimum_size.y = maxf(38.0, 86.0 * unit)
	_nickname.custom_minimum_size.x = minf(content_width - 64, 390.0 * unit)
	_nickname.add_theme_font_size_override("font_size", roundi(maxf(22.0, 49.0 * unit)))
	for feature in _features.get_children():
		feature.get_child(0).custom_minimum_size.y = maxf(30.0, 68.0 * unit)
		feature.get_child(1).add_theme_font_override("font", MODAL.village_font())
		feature.get_child(1).add_theme_font_size_override("font_size", roundi(maxf(14.0, 32.0 * unit)))
		feature.get_child(1).custom_minimum_size.y = maxf(40.0, 48.0 * unit)
	var action_inset := 96.0 if wide else 64.0
	var action_ratio := 1.8 if wide else 1.0
	var action_width := (content_width - action_inset) / action_ratio
	var action_unit := minf(unit, (design_width - action_inset) / (740.0 * action_ratio))
	_features.get_child(2).get_child(1).text = "体验\n全部玩法" if action_width < 350 else "体验全部玩法"
	enter_button.custom_minimum_size.y = maxf(touch, maxf(56.0, 156.0 * action_unit))
	enter_button.add_theme_font_size_override("font_size", roundi(maxf(24.0, 60.0 * action_unit)))
	enter_button.add_theme_constant_override("icon_max_width", roundi(maxf(28.0, 68.0 * action_unit)))
	enter_button.add_theme_constant_override("h_separation", 20)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		enter_button.get_theme_stylebox(state).set_content_margin(SIDE_LEFT, clampf(action_width * 0.18, 35, 155))
		enter_button.get_theme_stylebox(state).set_content_margin(SIDE_RIGHT, clampf(action_width * 0.10, 24, 90))
	_info.add_theme_font_size_override("font_size", roundi(maxf(14.0, 22.0 * unit)))
	_footer_art.visible = false # Portrait scenery already contains the approved tray and tiles.
	_footer_art.size = Vector2(270, 190)
	_footer_art.position = size - _footer_art.size - Vector2(24, 10)


func _art(parent: Control, texture: Texture2D) -> TextureRect:
	var picture := TextureRect.new()
	picture.texture = texture
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(picture)
	return picture


func _caption(parent: Control, value: String, font_size: int) -> Label:
	var text := Label.new()
	text.text = value
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_color_override("font_color", MODAL.INK)
	text.add_theme_font_size_override("font_size", font_size)
	parent.add_child(text)
	return text
