extends Control

const MODAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_modal.gd")
const RURAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_theme.gd")
const ERROR_ART := preload("res://modules/games/mahjong/guiyang/assets/ui/harvest/error_network.png")

var _frame: PanelContainer
var _heading: Label
var _art: TextureRect
var _message: Label
var _code: Label
var _code_plate: PanelContainer
var _actions: BoxContainer
var _close: Button
var _cancel: Button
var _confirm: Button
var _retry: Callable
var _dismiss: Callable
var _safe_area := Rect2()
var _dialog_size := Vector2.ZERO
var _height_ratio := 0.87
var _show_art := true
var _finished := false


func build(message: String, code: String, retry: Callable, on_dismiss: Callable, options := {}) -> void:
	name = "MahjongErrorModal"
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	_retry = retry
	_dismiss = on_dismiss
	_height_ratio = clampf(float(options.get("height_ratio", 0.87)), 0.28, 1.1)
	_show_art = bool(options.get("show_art", true))

	var shade := ColorRect.new()
	shade.color = Color("#24170fcc")
	shade.mouse_filter = MOUSE_FILTER_STOP
	add_child(shade)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	_frame = MODAL.village_panel(self, Vector4(34, 35, 34, 53))
	_frame.name = "MahjongErrorPanel"
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 11)
	_frame.add_child(body)
	_heading = MODAL.village_title(body, str(options.get("title", "错误提示")), _frame)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_child(scroll)
	var contents := VBoxContainer.new()
	contents.size_flags_horizontal = SIZE_EXPAND_FILL
	contents.size_flags_vertical = SIZE_EXPAND_FILL
	contents.alignment = BoxContainer.ALIGNMENT_CENTER
	contents.add_theme_constant_override("separation", 12)
	scroll.add_child(contents)

	_art = TextureRect.new()
	_art.name = "MahjongErrorIllustration"
	_art.texture = ERROR_ART
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.mouse_filter = MOUSE_FILTER_IGNORE
	_art.visible = _show_art
	contents.add_child(_art)

	_message = Label.new()
	_message.name = "MahjongErrorMessage"
	_message.text = message
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	MODAL.label(_message)
	_message.add_theme_font_override("font", MODAL.village_font())
	contents.add_child(_message)

	_code_plate = PanelContainer.new()
	_code_plate.size_flags_horizontal = SIZE_SHRINK_CENTER
	var code_style := MODAL.list_row()
	code_style.bg_color = Color("#e4b57b68")
	code_style.border_color = Color("#cc9952b0")
	code_style.set_content_margin(SIDE_LEFT, 12)
	code_style.set_content_margin(SIDE_RIGHT, 12)
	code_style.set_content_margin(SIDE_TOP, 4)
	code_style.set_content_margin(SIDE_BOTTOM, 4)
	_code_plate.add_theme_stylebox_override("panel", code_style)
	_code_plate.visible = not code.is_empty()
	contents.add_child(_code_plate)
	_code = Label.new()
	_code.name = "MahjongErrorCode"
	_code.text = "错误码  " + code
	_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	MODAL.label(_code)
	_code_plate.add_child(_code)

	_actions = BoxContainer.new()
	_actions.add_theme_constant_override("separation", 13)
	_actions.size_flags_horizontal = SIZE_SHRINK_CENTER
	body.add_child(_actions)
	if _retry.is_valid():
		_cancel = _action("MahjongErrorCancelButton", str(options.get("cancel_text", "取消")), dismiss, false)
		_confirm = _action("MahjongErrorRetryButton", str(options.get("primary_text", "重新连接")), _finish.bind(true), true)
	else:
		_confirm = _action("MahjongErrorConfirmButton", str(options.get("primary_text", "确定")), dismiss, true)

	_close = Button.new()
	_close.name = "MahjongErrorCloseButton"
	_close.tooltip_text = "关闭错误提示"
	_close.accessibility_name = "关闭错误提示"
	_close.z_index = 2
	MODAL.close_button(_close)
	_close.pressed.connect(dismiss)
	add_child(_close)
	resized.connect(_fit)
	_frame.minimum_size_changed.connect(_place_frame)
	_activate.call_deferred()


func get_ok_button() -> Button:
	return _confirm


func get_cancel_button() -> Button:
	return _cancel


func dismiss() -> void:
	_finish(false)


func _input(event: InputEvent) -> void:
	if _finished or not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		dismiss()


func _activate() -> void:
	_fit()
	var controls: Array[Button] = [_confirm, _close]
	if is_instance_valid(_cancel):
		controls.append(_cancel)
	for index in controls.size():
		var control := controls[index]
		var previous := control.get_path_to(controls[posmod(index - 1, controls.size())])
		var next := control.get_path_to(controls[(index + 1) % controls.size()])
		control.focus_previous = previous
		control.focus_next = next
		control.focus_neighbor_left = previous
		control.focus_neighbor_top = previous
		control.focus_neighbor_right = next
		control.focus_neighbor_bottom = next
	_confirm.grab_focus()


func _fit() -> void:
	if not is_instance_valid(_frame) or not is_inside_tree():
		return
	var safe := RURAL.safe_insets(self)
	_safe_area = Rect2(Vector2(safe.x, safe.y), size - Vector2(safe.x + safe.z, safe.y + safe.w))
	var available := Vector2(maxf(1.0, _safe_area.size.x - 24.0), maxf(1.0, _safe_area.size.y - 112.0))
	var width := minf(874.0, minf(available.x, maxf(available.y / _height_ratio, 320.0)))
	var narrow := width < 460.0
	var target_height := clampf(width * _height_ratio, 350.0 if _show_art else 247.0, 776.0)
	var height := minf(target_height, available.y)
	_dialog_size = Vector2(width, height)
	var compact := height < 460.0
	# Short dialogs reserve the scroll area for the message and error code.
	_art.visible = _show_art and height >= 350.0
	var touch := RURAL.touch_extent(self)
	var hit := MODAL.size_icon_button(_close, self)
	_close.size = Vector2.ONE * hit
	var plaque := _heading.get_parent() as Control
	plaque.custom_minimum_size = Vector2(minf(width * 0.54, 464.0), 58.0 if compact else 102.0)
	_heading.add_theme_font_size_override("font_size", roundi(clampf(width * 0.070, 26.0, 61.0)))
	_art.custom_minimum_size.y = clampf(height * (0.31 if compact else 0.46), 68.0, 326.0)
	_message.add_theme_font_size_override("font_size", roundi(clampf(width * 0.043, 16.0, 37.0)))
	_code.add_theme_font_size_override("font_size", roundi(clampf(width * 0.031, 13.0, 26.0)))
	_code.custom_minimum_size.x = clampf(width * 0.35, 124.0, 362.0)
	var pair := is_instance_valid(_cancel)
	_actions.vertical = width < 350.0 and pair
	var paired_row := pair and not _actions.vertical
	var max_button_width := floorf((width - 92.0 - 13.0) * 0.5) if paired_row else width - 78.0
	var button_width := 120.0 if paired_row and narrow else (176.0 if paired_row else 224.0)
	if not paired_row and not narrow: button_width = 280.0
	var button_height := 46.0 if narrow or compact else 60.0
	for button: Button in _actions.get_children():
		button.custom_minimum_size = Vector2(maxf(touch, minf(button_width, max_button_width)), maxf(touch, button_height))
		button.add_theme_font_size_override("font_size", 18 if narrow or compact else 26)
	_place_frame.call_deferred()


func _place_frame() -> void:
	if _dialog_size == Vector2.ZERO:
		return
	_frame.size = _dialog_size
	var inset := float(_frame.get_meta("title_border_offset", 0))
	var top := _safe_area.get_center().y - _frame.size.y * 0.5
	_frame.position = Vector2(_safe_area.get_center().x - _frame.size.x * 0.5, maxf(_safe_area.position.y + 48.0, top))
	_close.position = _frame.position + Vector2(_frame.size.x - _close.size.x - 12.0, inset - _close.size.y * 0.62)


func _action(id: String, caption: String, callback: Callable, primary: bool) -> Button:
	var button := Button.new()
	button.name = id
	button.text = caption
	button.size_flags_horizontal = SIZE_SHRINK_CENTER
	button.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	if id == "MahjongErrorRetryButton" and _art.visible:
		MODAL.login_button(button, "orange")
	else:
		MODAL.village_button(button, primary)
	button.pressed.connect(callback)
	_actions.add_child(button)
	return button


func _finish(should_retry: bool) -> void:
	if _finished:
		return
	_finished = true
	hide()
	queue_free()
	if _dismiss.is_valid():
		_dismiss.call()
	if should_retry and _retry.is_valid():
		_retry.call()
