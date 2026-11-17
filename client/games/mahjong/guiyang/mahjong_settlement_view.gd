extends Panel

const RURAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_theme.gd")
const MODAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_modal.gd")
const SEAL_FONT := preload("res://modules/games/mahjong/guiyang/assets/ui/fonts/FandolKai-Regular.otf")


class OutcomeSeal extends Control:
	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x * 0.40, size.y * 0.48)
		if radius <= 0.0: return
		draw_set_transform(center, -0.13, Vector2(1.25, 0.92))
		draw_circle(Vector2(2, 6), radius * 0.97, Color("#85140828"), true, -1, true)
		draw_circle(Vector2.ZERO, radius * 0.90, Color("#b01b0d"), true, -1, true)
		draw_arc(Vector2.ZERO, radius * 0.80, -2.5, 0.9, 54, Color("#da2c15"), radius * 0.25, true)
		draw_arc(Vector2.ZERO, radius * 0.88, 0.58, 3.85, 50, Color("#c52513"), radius * 0.15, true)
		draw_arc(Vector2.ZERO, radius * 0.95, 0.28, 3.75, 54, Color("#df3916"), radius * 0.066, true)
		draw_arc(Vector2(0, 3), radius * 0.98, -3.0, -0.10, 48, Color("#be2614"), radius * 0.045, true)
		draw_arc(Vector2(-4, 0), radius * 1.01, -3.4, -1.50, 36, Color("#d72812"), maxf(1, radius * 0.021), true)
		draw_arc(Vector2(0, 1), radius * 1.04, -2.3, -0.37, 28, Color("#d03717"), maxf(1, radius * 0.012), true)
		draw_arc(Vector2.ZERO, radius * 1.017, 0.50, 2.93, 40, Color("#ef5822"), maxf(1, radius * 0.024), true)
		draw_arc(Vector2.ZERO, radius * 0.96, 0.73, 2.18, 30, Color("#ffb93b"), maxf(1, radius * 0.024), true)
		draw_set_transform(Vector2.ZERO)


var _middle: BoxContainer
var _actions: BoxContainer
var _heading: Label
var _room: Label
var _badge: Control
var _result: Label
var _indicator: TextureRect
var _indicator_caption: Label
var _score_cards: Array[PanelContainer] = []
var _score_values: Array[Label] = []
var _player_labels: Array[Label] = []
var _secondary_labels: Array[Label] = []
var _close: Button
var _calligraphy: FontVariation


func setup(data: Dictionary, leave: Callable, next_round: Callable, rules: Callable, dismiss := Callable()) -> void:
	name = "MahjongSettlement"
	mouse_filter = Control.MOUSE_FILTER_STOP
	oversampling_with_scale = CanvasItem.OVERSAMPLING_WITH_SCALE_ENABLED
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_calligraphy = FontVariation.new()
	_calligraphy.base_font = SEAL_FONT
	_calligraphy.variation_embolden = 0.62
	var frame := MODAL.village_panel(self, Vector4(32, 22, 32, 28))
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	frame.add_child(body)
	_heading = MODAL.village_title(body, "本局结算", frame)
	_heading.add_theme_font_override("font", _calligraphy)
	_heading.get_parent().name = "MahjongSettlementBrandMark"
	_room = _label(body, str(data.get("room", "")), 16, "muted")
	_room.name = "MahjongSettlementRoom"
	_room.tooltip_text = _room.text
	_room.visible = not _room.text.is_empty()

	var scroll := ScrollContainer.new()
	scroll.name = "MahjongSettlementContent"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	body.add_child(scroll)
	_middle = BoxContainer.new()
	_middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_middle.add_theme_constant_override("separation", 24)
	scroll.add_child(_middle)
	_add_outcome(_middle, data)
	_add_scores(_middle, data.get("rows", []))

	_actions = BoxContainer.new()
	_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_actions.add_theme_constant_override("separation", 16)
	body.add_child(_actions)
	_add_button(_actions, "MahjongSettlementRulesButton", "查看规则", rules)
	var rematch := bool(data.get("rematch", false))
	if rematch:
		_add_button(_actions, "MahjongNextRoundButton", "再来一局", next_round, true)
	_add_button(_actions, "MahjongSettlementLobbyButton", str(data.get("return_caption", "返回大厅")), leave, not rematch)

	if dismiss.is_valid():
		_close = Button.new()
		_close.name = "MahjongSettlementCloseButton"
		_close.z_index = 2
		_close.tooltip_text = "关闭结算"
		_close.accessibility_name = "关闭结算"
		_close.pressed.connect(dismiss)
		MODAL.close_button(_close)
		add_child(_close)
		_close.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	resized.connect(_fit)
	tree_entered.connect(_fit, CONNECT_DEFERRED | CONNECT_ONE_SHOT)
	_fit()


func _fit() -> void:
	var compact := size.x < 700.0
	var narrow := size.x < 460.0
	_middle.vertical = compact
	_middle.add_theme_constant_override("separation", 8 if compact else 24)
	_actions.vertical = size.x < 388.0
	_actions.add_theme_constant_override("separation", 6 if narrow else 16)
	var short := size.y < 470.0
	_heading.add_theme_font_size_override("font_size", 31 if short else 40 if compact else 66)
	var title_plaque := _heading.get_parent() as Control
	title_plaque.custom_minimum_size = Vector2(clampf(size.x * 0.45, 158.0, 560.0), 50 if short else 63 if compact else 98)
	_room.add_theme_font_size_override("font_size", 13 if short else 16)
	_badge.custom_minimum_size.y = clampf(size.y * (0.143 if narrow else 0.21 if compact else 0.34 if short else 0.394), 86.0, 324.0)
	_fit_outcome.call_deferred()
	var tile_height := clampf(size.y * (0.12 if short else 0.15), 46.0, 55.0 if narrow else 100.0 if compact else 126.0)
	if is_instance_valid(_indicator):
		_indicator.custom_minimum_size = Vector2(tile_height * 0.77, tile_height)
		_indicator_caption.add_theme_font_size_override("font_size", roundi(clampf(size.x * 0.031, 16.0, 39.0)))
		(_indicator_caption.get_parent() as Control).custom_minimum_size.y = maxf(38.0, tile_height * 0.55)
	var row_width := size.x - 76.0 if compact else (size.x - 120.0) * 0.55
	for index in _score_cards.size():
		var card := _score_cards[index]
		card.custom_minimum_size.y = 57 if short or narrow else clampf(size.y * 0.117, 63.0, 86.0)
		var surface := card.get_theme_stylebox("panel")
		surface.set_content_margin(SIDE_LEFT, 14.0 if narrow else 42.0)
		surface.set_content_margin(SIDE_RIGHT, 16.0 if narrow else 47.0)
		surface.set_content_margin(SIDE_TOP, 6.0 if narrow else 10.0)
		surface.set_content_margin(SIDE_BOTTOM, 8.0 if narrow else 13.0)
		var points := _score_values[index]
		var font := points.get_theme_font("font")
		var point_size := 32 if compact or short else 51
		while point_size > 18 and font.get_string_size(points.text, HORIZONTAL_ALIGNMENT_LEFT, -1, point_size).x > row_width * 0.38:
			point_size -= 1
		points.add_theme_font_size_override("font_size", point_size)
	for player in _player_labels:
		player.add_theme_font_size_override("font_size", 22 if short or compact else 28)
	for detail in _secondary_labels:
		detail.add_theme_font_size_override("font_size", 12 if narrow or short else 15)
	var touch := RURAL.touch_extent(self) / get_global_transform().get_scale().y if is_inside_tree() else 0.0
	for action: Button in _actions.get_children():
		var is_next := action.name == &"MahjongNextRoundButton"
		var button_width := 188.0 if _actions.vertical else (
			(106.0 if is_next else 90.0) if narrow else
			(150.0 if is_next else 118.0) if compact or short else (240.0 if is_next else 184.0))
		var desired := 48.0 if short or compact else 60.0
		action.custom_minimum_size = Vector2(button_width, maxf(touch, desired))
		action.add_theme_font_size_override("font_size", 18 if narrow else 22 if compact or short else 30)
		var margin := 7.0 if narrow else 22.0 if is_next else 14.0
		for state in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
			var surface := action.get_theme_stylebox(state)
			surface.set_content_margin(SIDE_LEFT, margin)
			surface.set_content_margin(SIDE_RIGHT, margin)
	if is_instance_valid(_close):
		var hit := MODAL.size_icon_button(_close, _close)
		_close.offset_left = -hit - 14
		_close.offset_right = -14
		_close.offset_top = 4
		_close.offset_bottom = hit + 4


func _fit_outcome() -> void:
	if not is_instance_valid(_result) or not is_instance_valid(_badge) or _badge.size.x <= 0 or _badge.size.y <= 0:
		return
	var font := _result.get_theme_font("font")
	var outline := _result.get_theme_constant("outline_size") * 2.0
	var shadow := absf(float(_result.get_theme_constant("shadow_offset_y")))
	var available := _badge.size - Vector2(outline + 35.0, outline + shadow + 20.0)
	var desired := roundi(clampf(_badge.size.y * 0.61, 16.0, 182.0))
	while desired > 12 and (font.get_string_size(_result.text, HORIZONTAL_ALIGNMENT_LEFT, -1, desired).x > available.x or font.get_height(desired) > available.y):
		desired -= 1
	if desired != _result.get_theme_font_size("font_size"):
		_result.add_theme_font_size_override("font_size", desired)


func _add_outcome(parent: BoxContainer, data: Dictionary) -> void:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = 0.87
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 7)
	parent.add_child(column)
	var outcome := str(data.get("outcome", "draw"))
	var caption := str(data.get("outcome_title", "流局" if outcome == "draw" else "胡牌"))
	_badge = OutcomeSeal.new()
	_badge.resized.connect(_badge.queue_redraw)
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_badge)
	_result = _label(_badge, caption, 55, "title")
	_result.name = "MahjongSettlementOutcome"
	_result.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result.add_theme_font_override("font", _calligraphy)
	_result.add_theme_color_override("font_color", Color("#fff195"))
	_result.add_theme_color_override("font_outline_color", Color("#8c1c0b"))
	_result.add_theme_constant_override("outline_size", 11)
	_result.add_theme_constant_override("shadow_offset_y", 6)
	_result.add_theme_color_override("font_shadow_color", Color("#670c09b0"))
	_badge.resized.connect(_fit_outcome, CONNECT_DEFERRED)
	var summary := _label(column, str(data.get("summary", "")), 15, "muted")
	summary.name = "MahjongSettlementSummary"
	summary.tooltip_text = summary.text
	summary.visible = not summary.text.is_empty()
	var indicator: Texture2D = data.get("indicator")
	if indicator != null:
		_add_indicator(column, indicator, str(data.get("indicator_title", "")))


func _add_scores(parent: BoxContainer, rows: Array) -> void:
	var scores := VBoxContainer.new()
	scores.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scores.size_flags_stretch_ratio = 1.13
	scores.alignment = BoxContainer.ALIGNMENT_CENTER
	scores.add_theme_constant_override("separation", 9)
	parent.add_child(scores)
	for row: Dictionary in rows:
		if bool(row.get("own", false)):
			_add_score(scores, row)
	for row: Dictionary in rows:
		if not bool(row.get("own", false)):
			_add_score(scores, row)
	if rows.is_empty():
		_label(scores, "暂无结算明细", 21, "muted")


func _add_score(parent: VBoxContainer, row: Dictionary) -> void:
	var seat_index := int(row.get("seat", -1))
	var own := bool(row.get("own", false))
	var panel := PanelContainer.new()
	var insets := Vector4(42, 10, 47, 13)
	var surface := MODAL.button_frame(MODAL.VILLAGE_GOLD, insets, Color("#fff1b4")) if own else MODAL.capsule_frame(insets)
	panel.add_theme_stylebox_override("panel", surface)
	parent.add_child(panel)
	_score_cards.append(panel)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	panel.add_child(line)
	var mark := _label(line, "●", 18, "success" if own else "muted")
	mark.add_theme_color_override("font_color", Color("#367c23") if own else Color("#af987e"))
	mark.add_theme_color_override("font_outline_color", Color("#fff6cd"))
	mark.add_theme_constant_override("outline_size", 2)
	mark.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	var caption := VBoxContainer.new()
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.alignment = BoxContainer.ALIGNMENT_CENTER
	caption.add_theme_constant_override("separation", 0)
	line.add_child(caption)
	var nickname := str(row.get("name", ""))
	var player := _label(caption, nickname, 23)
	player.add_theme_font_override("font", _calligraphy)
	player.name = "MahjongSettlementPlayer%d" % seat_index
	player.tooltip_text = nickname
	player.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_player_labels.append(player)
	var details_line := HBoxContainer.new()
	details_line.add_theme_constant_override("separation", 8)
	caption.add_child(details_line)
	_add_row_detail(details_line, "MahjongSettlementResult%d" % seat_index, str(row.get("result", "—")))
	if row.has("details"):
		_add_row_detail(details_line, "MahjongSettlementBreakdown%d" % seat_index, str(row["details"]))
	var extras := HBoxContainer.new()
	extras.add_theme_constant_override("separation", 8)
	caption.add_child(extras)
	var delta: Variant = row.get("egg_delta")
	var known := (delta is int or delta is float) and is_finite(float(delta)) and float(delta) == floorf(float(delta))
	var counts_eggs := bool(row.get("counts_eggs", true))
	var egg_text := "%+d 鸡蛋" % int(delta) if known else "— 鸡蛋" if counts_eggs else "不计鸡蛋"
	var eggs := _add_row_detail(extras, "MahjongSettlementEggDelta%d" % seat_index, egg_text)
	eggs.tooltip_text = "本局实际鸡蛋收支 " + egg_text if known else "鸡蛋结算记录暂不可用" if counts_eggs else "练习不计鸡蛋"
	if row.has("series"):
		_add_row_detail(extras, "MahjongSettlementSeries%d" % seat_index, str(row.series))
	var score := int(row.get("score", 0))
	var points := _label(line, "%+d 分" % score, 32)
	points.add_theme_font_override("font", MODAL.village_font())
	points.name = "MahjongSettlementScore%d" % seat_index
	points.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	points.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	points.tooltip_text = "本局牌分 " + points.text
	if score > 0:
		points.add_theme_color_override("font_color", Color("#ba230f"))
		points.add_theme_color_override("font_outline_color", Color("#fff0b2"))
		points.add_theme_constant_override("outline_size", 3)
	_score_values.append(points)


func _add_row_detail(parent: HBoxContainer, id: String, value: String) -> Label:
	var detail := _label(parent, value, 14, "muted")
	detail.name = id
	detail.tooltip_text = value
	detail.add_theme_color_override("font_color", Color("#50301c"))
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.size_flags_stretch_ratio = maxf(1.0, float(value.length()))
	_secondary_labels.append(detail)
	return detail


func _add_indicator(parent: VBoxContainer, texture: Texture2D, face: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", -8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(row)
	_indicator_caption = MODAL.village_title(row, "翻鸡指示牌")
	_indicator_caption.add_theme_font_override("font", _calligraphy)
	(_indicator_caption.get_parent() as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_indicator_caption.tooltip_text = face
	_indicator = TextureRect.new()
	_indicator.name = "MahjongSettlementIndicator"
	_indicator.texture = texture
	_indicator.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_indicator.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_indicator)


func _label(parent: Control, value: String, font_size: int, role := "body") -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	MODAL.label(label, role)
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _add_button(parent: BoxContainer, id: String, value: String, action: Callable, primary := false) -> void:
	var button := Button.new()
	button.name = id
	button.text = value
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	MODAL.village_button(button, primary)
	button.add_theme_font_override("font", _calligraphy)
	button.pressed.connect(action)
	parent.add_child(button)
