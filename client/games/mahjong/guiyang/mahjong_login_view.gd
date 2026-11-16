extends Control
## Native account-entry controls; authentication and navigation remain in the app.

const RURAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_theme.gd")
const MODAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_modal.gd")
const ICON_BASE := "res://modules/games/mahjong/guiyang/assets/ui/login_rural/"
const EYE := preload(ICON_BASE + "icon_eye.svg")
const EYE_OFF := preload(ICON_BASE + "icon_eye_off.svg")
const WECHAT := preload(ICON_BASE + "icon_wechat.svg")
const PERSON := preload("res://modules/games/mahjong/guiyang/assets/ui/harvest/icon_person_cream.svg")

var identifier: LineEdit
var secret: LineEdit
var remember: CheckBox
var submit: Button
var guest: Button
var wechat: Button
var exit_button: Button
var register_button: Button
var retry: Button
var status: Label
var logo: TextureRect
var background: TextureRect
var footer: Label
var form: PanelContainer
var scroll: ScrollContainer
var _margin: MarginContainer
var _center: CenterContainer
var _layout: BoxContainer
var _header: VBoxContainer
var _column: VBoxContainer
var _title: Label
var _fields: Array[PanelContainer] = []
var _field_labels: Array[Label] = []
var _helpers: HBoxContainer
var _forgot: Button
var _bottom: HBoxContainer
var _bottom_separator: Label
var _eye: Button
var _checked: Texture2D
var _unchecked: Texture2D


func build(remembered: String, actions: Dictionary) -> void:
	background = TextureRect.new()
	background.name = "MahjongLoginArtwork"
	background.texture = MODAL.LOGIN_BACKDROP
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin = MarginContainer.new()
	add_child(_margin)
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll = ScrollContainer.new()
	scroll.name = "MahjongLoginScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_margin.add_child(scroll)
	var center := CenterContainer.new()
	_center = center
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll.add_child(center)
	_layout = BoxContainer.new()
	_layout.vertical = true
	_layout.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	center.add_child(_layout)
	_header = VBoxContainer.new()
	_header.name = "MahjongLoginScenery"
	_layout.add_child(_header)
	logo = TextureRect.new()
	logo.name = "MahjongLoginBrandLogo"
	logo.texture = MODAL.VILLAGE_BRAND
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(logo)
	form = PanelContainer.new()
	form.name = "MahjongLoginTray"
	form.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_layout.add_child(form)
	_column = VBoxContainer.new()
	form.add_child(_column)
	_title = MODAL.village_title(_column, "账号登录")
	_title.get_parent().add_theme_stylebox_override("panel", MODAL.button_frame(MODAL.LOGIN_TITLE, Vector4(85, 8, 85, 10)))
	identifier = _field("账号", "请输入账号", false)
	identifier.name = "MahjongAccountLoginUsername"
	identifier.max_length = 32
	identifier.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	identifier.text = remembered
	secret = _field("密码", "请输入密码", true)
	secret.name = "MahjongAccountLoginPassword"
	secret.max_length = 128
	secret.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
	identifier.text_submitted.connect(func(_text: String): secret.grab_focus())
	secret.text_submitted.connect(func(_text: String): actions.submit.call())
	_helpers = HBoxContainer.new()
	_column.add_child(_helpers)
	remember = CheckBox.new()
	remember.name = "MahjongRememberAccount"
	remember.text = "记住账号"
	remember.set_pressed_no_signal(true)
	remember.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	remember.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	remember.add_theme_font_override("font", MODAL.village_font())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		remember.add_theme_color_override(state, MODAL.INK)
	_helpers.add_child(remember)
	_forgot = Button.new()
	_forgot.name = "MahjongForgotPasswordButton"
	_forgot.text = "忘记密码"
	_forgot.flat = true
	MODAL.village_button(_forgot)
	for state in ["normal", "hover", "pressed"]:
		_forgot.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_forgot.pressed.connect(actions.forgot)
	_helpers.add_child(_forgot)
	var underline := ColorRect.new()
	underline.name = "LinkUnderline"
	underline.color = MODAL.INK
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_forgot.add_child(underline)
	underline.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	underline.offset_top = -4
	underline.offset_bottom = -2
	underline.offset_left = 4
	underline.offset_right = -4
	status = Label.new()
	status.name = "MahjongLoginStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.visible = false
	_column.add_child(status)
	retry = Button.new()
	retry.name = "MahjongRetryLoginConnection"
	retry.text = "重试连接"
	MODAL.village_button(retry)
	retry.pressed.connect(actions.retry)
	_column.add_child(retry)
	var pad_icon := _svg('<svg xmlns="http://www.w3.org/2000/svg" width="88" height="72" viewBox="0 0 88 72"><path d="M24 13Q44 9 64 13Q76 17 80 50Q81 66 67 59L54 47H34L21 59Q7 66 8 50Q12 17 24 13Z" fill="#fff4dd" stroke="#b96515" stroke-width="2"/><path d="M28 22v21M18 32h21" stroke="#a44612" stroke-width="6" stroke-linecap="round"/><g fill="#a44612"><circle cx="62" cy="24" r="4"/><circle cx="71" cy="32" r="4"/><circle cx="54" cy="32" r="4"/><circle cx="62" cy="40" r="4"/></g></svg>')
	submit = _action("MahjongAccountLoginSubmit", "登录游戏", "orange", pad_icon, actions.submit)
	wechat = _action("MahjongWechatLoginButton", "微信登录", "green", WECHAT, actions.wechat)
	guest = _action("MahjongGuestLoginButton", "游客登录", "blue", PERSON, actions.guest)
	_bottom = HBoxContainer.new()
	_bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	_bottom.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_column.add_child(_bottom)
	var power_ink := _svg('<svg xmlns="http://www.w3.org/2000/svg" width="44" height="44" viewBox="0 0 44 44"><g stroke="#462818" stroke-width="4" fill="none" stroke-linecap="round"><path d="M22 3v19M11 10A17 17 0 1 0 33 10"/></g></svg>')
	exit_button = _secondary("MahjongLoginExitButton", "退出游戏", power_ink, actions.exit)
	_bottom_separator = Label.new()
	_bottom_separator.text = "│"
	_bottom_separator.add_theme_color_override("font_color", MODAL.MUTED)
	_bottom.add_child(_bottom_separator)
	var register_icon := _svg('<svg xmlns="http://www.w3.org/2000/svg" width="48" height="44" viewBox="0 0 48 44"><g fill="none" stroke="#462818" stroke-width="4" stroke-linecap="round"><circle cx="19" cy="12" r="8"/><path d="M5 36v-4c0-7 6-11 14-11 3 0 5 1 7 2M5 36h19M36 25v15M29 33h15"/></g></svg>')
	register_button = _secondary("MahjongRegisterButton", "注册账号", register_icon, actions.register)
	footer = Label.new()
	footer.name = "MahjongLoginCopyright"
	footer.text = "© 2026 Freeboozstudio 工作室  |  小板凳麻将"
	var application_version := str(ProjectSettings.get_setting("application/config/version", ""))
	if not application_version.is_empty():
		footer.text += " Ver" + application_version
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_theme_color_override("font_color", MODAL.CREAM)
	var footer_skin := StyleBoxFlat.new()
	footer_skin.bg_color = Color("#261b16d9")
	footer.add_theme_stylebox_override("normal", footer_skin)
	add_child(footer)
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	resized.connect(_fit)
	_fit.call_deferred()


func _field(title: String, placeholder: String, hidden: bool) -> LineEdit:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", MODAL.capsule_frame(Vector4(42, 5, 32, 7)))
	_column.add_child(card)
	_fields.append(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 13)
	card.add_child(row)
	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", MODAL.village_font())
	label.add_theme_color_override("font_color", MODAL.INK)
	row.add_child(label)
	_field_labels.append(label)
	var divider := ColorRect.new()
	divider.color = Color("#a26a36")
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider.custom_minimum_size.x = 2
	divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(divider)
	var input := LineEdit.new()
	input.placeholder_text = placeholder
	input.secret = hidden
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.expand_to_text_length = false
	input.custom_minimum_size.x = 0
	input.add_theme_constant_override("minimum_character_width", 1)
	input.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	input.add_theme_stylebox_override("read_only", StyleBoxEmpty.new())
	var focus := RURAL.frame(Color.TRANSPARENT, Color("#ba7c32"), 9, 1)
	focus.shadow_size = 0
	input.add_theme_stylebox_override("focus", focus)
	input.add_theme_color_override("font_color", MODAL.INK)
	input.add_theme_color_override("font_placeholder_color", Color("#99896d"))
	input.add_theme_color_override("caret_color", MODAL.INK)
	input.add_theme_color_override("selection_color", Color("#edc580"))
	row.add_child(input)
	if hidden:
		_eye = Button.new()
		_eye.name = "MahjongTogglePasswordVisibility"
		_eye.icon = EYE
		_eye.expand_icon = true
		_eye.flat = true
		_eye.tooltip_text = "显示密码"
		_eye.pressed.connect(func():
			input.secret = not input.secret
			_eye.icon = EYE if input.secret else EYE_OFF
			_eye.tooltip_text = "显示密码" if input.secret else "隐藏密码")
		row.add_child(_eye)
	return input


func _action(node_name: String, title: String, role: String, icon: Texture2D, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = title
	button.icon = icon
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.expand_icon = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MODAL.login_button(button, role)
	var divider := ColorRect.new()
	divider.name = "CaptionDivider"
	divider.color = MODAL.CREAM
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(divider)
	button.pressed.connect(action)
	_column.add_child(button)
	return button


func _secondary(node_name: String, title: String, icon: Texture2D, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = title
	button.icon = icon
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.expand_icon = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MODAL.village_button(button)
	button.pressed.connect(action)
	_bottom.add_child(button)
	return button


func _svg(source: String) -> Texture2D:
	var bitmap := Image.new()
	bitmap.load_svg_from_string(source)
	return ImageTexture.create_from_image(bitmap)


func _check_icon(extent: int, checked: bool) -> Texture2D:
	return _svg('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 56 56"><defs><linearGradient id="g" x2="0" y2="1"><stop stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient></defs><rect x="2" y="2" width="52" height="52" rx="9" fill="url(#g)" stroke="#d99922" stroke-width="2"/><rect x="5" y="5" width="46" height="46" rx="7" fill="none" stroke="#fff4cf" stroke-width="1.5"/>%s</svg>' % [extent, extent, "#90d81c" if checked else "#fff5df", "#3d8c08" if checked else "#ecd0a3", '<path d="M13 28l10 10 22-24" stroke="#fffbe8" stroke-width="7" fill="none" stroke-linecap="square"/>' if checked else ""])


func _fit() -> void:
	if not is_instance_valid(form): return
	var safe := RURAL.safe_insets(self)
	var touch := RURAL.touch_extent(self)
	var available := size - Vector2(safe.x + safe.z, safe.y + safe.w)
	# Near-square desktop windows keep the approved centered composition. A
	# short tablet uses two bounded columns so neither group needs stretching.
	var wide := available.x >= 900.0 and (available.x >= available.y * 1.5 or available.y < 1100.0)
	var landscape_art := available.x >= available.y * 0.85
	background.texture = MODAL.VILLAGE_LANDSCAPE if landscape_art else MODAL.LOGIN_BACKDROP
	form.add_theme_stylebox_override("panel", MODAL._slice(MODAL.VILLAGE_PAPER, Vector4.ZERO, Vector4(16, 12, 16, 12)) if landscape_art else StyleBoxEmpty.new())
	var edge := clampf(available.x * 0.025, 12.0, 32.0)
	var footer_height := clampf(available.y * 0.029, 30.0, 49.0)
	var top := clampf(available.y * 0.025, 12.0, 43.0)
	var width := minf(740.0, available.x - edge * 2.0)
	if wide:
		# Native font metrics and integer row sizes need a little more room than
		# the reference's 952 px artwork-only column on short landscape screens.
		var height_scale := minf(1.0, (available.y - top - footer_height - 40.0) / 980.0)
		width = minf(740.0 * height_scale, (available.x - edge * 3.0 - 32.0) * 0.57)
	var unit := minf(width / 740.0, 1.0)
	_margin.add_theme_constant_override("margin_left", roundi(safe.x + edge))
	_margin.add_theme_constant_override("margin_right", roundi(safe.z + edge))
	_margin.add_theme_constant_override("margin_top", roundi(safe.y + top))
	_margin.add_theme_constant_override("margin_bottom", roundi(safe.w + footer_height + 8))
	_layout.vertical = not wide
	_center.size_flags_vertical = Control.SIZE_EXPAND_FILL if wide else Control.SIZE_SHRINK_BEGIN
	_layout.custom_minimum_size = Vector2.ZERO
	_layout.add_theme_constant_override("separation", roundi(18.0 * unit if not wide else edge))
	form.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	form.custom_minimum_size.x = width + (32.0 if landscape_art else 0.0)
	_header.size_flags_vertical = Control.SIZE_SHRINK_CENTER if wide else Control.SIZE_FILL
	_header.custom_minimum_size = Vector2(width * 0.72, 0.0) if wide else Vector2(width, 0.0)
	var logo_width := minf(540.0, width * 0.72) if wide else minf(600.0, width * 600.0 / 740.0)
	logo.custom_minimum_size = Vector2(logo_width, logo_width / MODAL.VILLAGE_BRAND.get_size().aspect())
	_column.add_theme_constant_override("separation", roundi(18.0 * unit))
	var title_width := width * 700.0 / 740.0
	_title.get_parent().custom_minimum_size = Vector2(title_width, title_width / MODAL.LOGIN_TITLE.get_size().aspect())
	_title.add_theme_font_size_override("font_size", roundi(maxf(32.0, 70.0 * unit)))
	for index in _fields.size():
		_fields[index].size_flags_vertical = Control.SIZE_FILL
		_fields[index].custom_minimum_size.y = maxf(touch, maxf(54.0, 90.0 * unit))
		var field_skin := _fields[index].get_theme_stylebox("panel")
		field_skin.set_content_margin(SIDE_LEFT, maxf(20.0, 42.0 * unit))
		field_skin.set_content_margin(SIDE_RIGHT, maxf(20.0, 32.0 * unit))
		field_skin.set_content_margin(SIDE_TOP, 5.0 * unit)
		field_skin.set_content_margin(SIDE_BOTTOM, 7.0 * unit)
		_field_labels[index].custom_minimum_size.x = maxf(50.0, 138.0 * unit)
		_field_labels[index].add_theme_font_size_override("font_size", roundi(maxf(24.0, 51.0 * unit)))
		var row := _fields[index].get_child(0) as HBoxContainer
		row.add_theme_constant_override("separation", roundi(18.0 * unit))
		(row.get_child(1) as Control).custom_minimum_size.y = 48.0 * unit
	for input in [identifier, secret]: input.add_theme_font_size_override("font_size", roundi(maxf(20.0, 35.0 * unit)))
	_eye.custom_minimum_size.x = maxf(touch, maxf(44.0, 65.0 * unit))
	_eye.add_theme_constant_override("icon_max_width", roundi(52.0 * unit))
	_helpers.custom_minimum_size.y = maxf(touch, maxf(44.0, 64.0 * unit))
	remember.add_theme_font_size_override("font_size", roundi(maxf(19.0, 39.0 * unit)))
	remember.add_theme_constant_override("h_separation", roundi(12.0 * unit))
	var check_extent := roundi(maxf(29.0, 52.0 * unit))
	if _checked == null or _checked.get_width() != check_extent:
		_checked = _check_icon(check_extent, true)
		_unchecked = _check_icon(check_extent, false)
		remember.add_theme_icon_override("checked", _checked)
		remember.add_theme_icon_override("unchecked", _unchecked)
	_forgot.custom_minimum_size.x = width * 0.28
	_forgot.add_theme_font_size_override("font_size", roundi(maxf(19.0, 39.0 * unit)))
	for button in [submit, wechat, guest]:
		button.size_flags_vertical = Control.SIZE_FILL
		button.custom_minimum_size.y = maxf(touch, maxf(60.0, 116.0 * unit))
		button.add_theme_font_size_override("font_size", roundi(maxf(29.0, 63.0 * unit)))
		button.add_theme_constant_override("icon_max_width", roundi(82.0 * unit))
		button.add_theme_constant_override("h_separation", roundi(32.0 * unit))
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var skin: StyleBox = button.get_theme_stylebox(state)
			skin.set_content_margin(SIDE_LEFT, 150.0 * unit)
			skin.set_content_margin(SIDE_RIGHT, 84.0 * unit)
		var divider := button.get_node("CaptionDivider") as ColorRect
		divider.anchor_top = 0.5
		divider.anchor_bottom = 0.5
		divider.offset_left = 248.0 * unit
		divider.offset_right = divider.offset_left + maxf(1.0, 2.0 * unit)
		divider.offset_top = -30.0 * unit
		divider.offset_bottom = 30.0 * unit
	_bottom.add_theme_constant_override("separation", roundi(26.0 * unit))
	_bottom.custom_minimum_size.x = width * 0.84
	_bottom.custom_minimum_size.y = maxf(touch, maxf(48.0, 74.0 * unit))
	_bottom_separator.add_theme_font_size_override("font_size", roundi(38.0 * unit))
	for button in [exit_button, register_button]:
		button.size_flags_vertical = Control.SIZE_FILL
		button.custom_minimum_size.y = maxf(touch, maxf(48.0, 74.0 * unit))
		button.add_theme_font_size_override("font_size", roundi(maxf(19.0, 34.0 * unit)))
		button.add_theme_constant_override("icon_max_width", roundi(39.0 * unit))
		button.add_theme_constant_override("h_separation", roundi(9.0 * unit))
	retry.custom_minimum_size.y = maxf(touch, maxf(44.0, 56.0 * unit))
	status.add_theme_font_size_override("font_size", roundi(maxf(16.0, 22.0 * unit)))
	footer.add_theme_font_size_override("font_size", roundi(clampf(available.x * 0.029, 12.0, minf(28.0, footer_height * 0.60))))
	footer.offset_left = safe.x
	footer.offset_right = -safe.z
	footer.offset_top = -safe.w - footer_height
	footer.offset_bottom = -safe.w
	if not wide:
		var scene_budget := available.y - top - footer_height - 8.0 - _layout.get_theme_constant("separation") - form.get_combined_minimum_size().y
		_header.custom_minimum_size.y = maxf(logo.custom_minimum_size.y, minf(400.0 * unit, scene_budget))
