extends Panel

const RURAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_theme.gd")
const MODAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_modal.gd")


class VictorySeal extends Control:
	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x * 0.43, size.y * 0.49)
		if radius <= 0.0: return
		draw_set_transform(center, -0.12, Vector2(1.18, 0.91))
		draw_circle(Vector2(0, 5), radius, Color("#85140830"), true, -1, true)
		draw_circle(Vector2.ZERO, radius * 0.86, Color("#a91910"), true, -1, true)
		draw_arc(Vector2.ZERO, radius * 0.84, -0.38, 5.8, 80, Color("#c92012"), radius * 0.24, true)
		var brush := PackedColorArray([Color("#eb421d"), Color("#b32111"), Color("#d92b13"), Color("#fb6c27"), Color("#e33316"), Color("#b82b18")])
		for index in brush.size():
			var start := index * 0.74 - 0.2
			var width := radius * (0.11 - index * 0.014)
			draw_arc(Vector2.ZERO, radius * (0.93 + index * 0.018), start, start + 3.2, 50, brush[index], maxf(width, 1.0), true)
		draw_arc(Vector2.ZERO, radius * 0.92, 0.76, 2.22, 36, Color("#ffc33d"), maxf(1, radius * 0.028), true)
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
var _close: Button


func setup(data: Dictionary, leave: Callable, next_round: Callable, rules: Callable, dismiss := Callable()) -> void:
	name = "MahjongSettlement"
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var frame := MODAL.village_panel(self, Vector4(32, 22, 32, 28))
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	frame.add_child(body)
	_heading = MODAL.village_title(body, "本局结算", frame)
	_heading.get_parent().name = "MahjongSettlementBrandMark"
	_room = _label(body, str(data.get("room", "")), 16, "muted")
	_room.name = "MahjongSettlementRoom"
	_room.tooltip_text = _room.text
	_room.visible = not _room.text.is_empty()

	var scroll := ScrollContainer.new()
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
	_middle.vertical = compact
	_actions.vertical = size.x < 428.0
	var short := size.y < 470.0
	_heading.add_theme_font_size_override("font_size", 30 if short else 36 if compact else 56)
	var title_plaque := _heading.get_parent() as Control
	title_plaque.custom_minimum_size = Vector2(clampf(size.x * 0.41, 158.0, 505.0), 50 if short else 63 if compact else 91)
	_room.add_theme_font_size_override("font_size", 13 if short else 16)
	_badge.custom_minimum_size.y = clampf(size.y * (0.27 if short else 0.345), 96.0, 286.0)
	_fit_outcome.call_deferred()
	var tile_height := clampf(size.y * 0.16, 46.0, 70.0 if compact else 130.0)
	if is_instance_valid(_indicator):
		_indicator.custom_minimum_size = Vector2(tile_height * 0.77, tile_height)
		_indicator_caption.add_theme_font_size_override("font_size", roundi(clampf(size.x * 0.027, 16.0, 34.0)))
	for index in _score_cards.size():
		_score_cards[index].custom_minimum_size.y = 55 if short else clampf(size.y * 0.104, 61.0, 94.0)
		_score_values[index].add_theme_font_size_override("font_size", 24 if compact or short else 32 if _score_values[index].text.length() > 7 else 46)
	for action: Button in _actions.get_children():
		action.custom_minimum_size.y = 44 if short or compact else clampf(size.y * 0.119, 54.0, 88.0)
		action.add_theme_font_size_override("font_size", 20 if compact or short else 35)
	if is_instance_valid(_close):
		var touch := RURAL.touch_extent(self) if is_inside_tree() else 0.0
		var hit := maxf(touch, 50.0 if short else 59.0)
		_close.offset_left = -hit - 14
		_close.offset_right = -14
		_close.offset_top = 12
		_close.offset_bottom = hit + 12


func _fit_outcome() -> void:
	if not is_instance_valid(_result) or not is_instance_valid(_badge) or _badge.size.x <= 0 or _badge.size.y <= 0:
		return
	var font := _result.get_theme_font("font")
	var outline := _result.get_theme_constant("outline_size") * 2.0
	var shadow := absf(float(_result.get_theme_constant("shadow_offset_y")))
	var available := _badge.size - Vector2(outline + 16.0, outline + shadow + 12.0)
	var desired := roundi(clampf(_badge.size.y * 0.57, 16.0, 155.0))
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
	var caption := "胡牌" if outcome == "win" else "本局未胡" if outcome == "loss" else "流局"
	if outcome == "win":
		for row: Dictionary in data.get("rows", []):
			if bool(row.get("own", false)) and str(row.get("result", "")).get_slice(" · ", 0) == "自摸":
				caption = "自摸"
				break
		_badge = VictorySeal.new()
		_badge.resized.connect(_badge.queue_redraw)
	else:
		var neutral := TextureRect.new()
		neutral.texture = MODAL.result_badge(outcome)
		neutral.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		neutral.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_badge = neutral
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_badge)
	_result = _label(_badge, caption, 55, "title")
	_result.name = "MahjongSettlementOutcome"
	_result.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result.add_theme_font_override("font", MODAL.village_font())
	_result.add_theme_color_override("font_color", Color("#ffe08a") if outcome == "win" else Color("#70441b"))
	_result.add_theme_color_override("font_outline_color", Color("#7e1609") if outcome == "win" else Color("#fff1d2"))
	_result.add_theme_constant_override("outline_size", 13 if outcome == "win" else 3)
	_result.add_theme_constant_override("shadow_offset_y", 5)
	_result.add_theme_color_override("font_shadow_color", Color("#710b066a"))
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
	var surface := MODAL.list_row(own)
	surface.set_corner_radius_all(27)
	surface.set_border_width_all(2)
	surface.border_color = Color("#c68830") if own else Color("#cbac7d")
	surface.bg_color = Color("#ffe09a") if own else Color("#fff1d8")
	surface.shadow_color = Color("#542e1b33")
	surface.shadow_size = 3
	surface.set_content_margin(SIDE_LEFT, 18)
	surface.set_content_margin(SIDE_RIGHT, 19)
	surface.set_content_margin(SIDE_TOP, 5)
	surface.set_content_margin(SIDE_BOTTOM, 5)
	panel.add_theme_stylebox_override("panel", surface)
	parent.add_child(panel)
	_score_cards.append(panel)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	panel.add_child(line)
	var mark := _label(line, "●", 18, "success" if own else "muted")
	mark.add_theme_color_override("font_color", Color("#348312") if own else Color("#9b8a75"))
	mark.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	var caption := VBoxContainer.new()
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.alignment = BoxContainer.ALIGNMENT_CENTER
	caption.add_theme_constant_override("separation", 0)
	line.add_child(caption)
	var nickname := str(row.get("name", ""))
	var player := _label(caption, nickname, 23)
	player.add_theme_font_override("font", MODAL.village_font())
	player.name = "MahjongSettlementPlayer%d" % seat_index
	player.tooltip_text = nickname
	player.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var details_line := HBoxContainer.new()
	details_line.add_theme_constant_override("separation", 8)
	caption.add_child(details_line)
	var result := _label(details_line, str(row.get("result", "—")), 14, "muted")
	result.name = "MahjongSettlementResult%d" % seat_index
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	result.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	if row.has("details"):
		var detail := _label(details_line, str(row["details"]), 13, "muted")
		detail.name = "MahjongSettlementBreakdown%d" % seat_index
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		detail.tooltip_text = detail.text
	var score := int(row.get("score", 0))
	var score_label := _label(caption, "本局牌分 %+d 分" % score, 14, "muted")
	score_label.name = "MahjongSettlementScore%d" % seat_index
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	score_label.tooltip_text = "牌分按玩法计算；鸡蛋按实际收支结算，余额最低为 0"
	var delta: Variant = row.get("egg_delta")
	var known := (delta is int or delta is float) and is_finite(float(delta)) and float(delta) == floorf(float(delta))
	var counts_eggs := bool(row.get("counts_eggs", true))
	var caption_text := "%+d 鸡蛋" % int(delta) if known else "— 鸡蛋" if counts_eggs else "不计鸡蛋"
	var points := _label(line, caption_text, 29, "negative" if known and int(delta) > 0 else "body")
	points.add_theme_font_override("font", MODAL.village_font())
	points.name = "MahjongSettlementEggDelta%d" % seat_index
	points.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	points.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	points.tooltip_text = "本局实际鸡蛋收支：" + points.text if known else "鸡蛋结算记录暂不可用" if counts_eggs else "练习不计鸡蛋"
	_score_values.append(points)


func _add_indicator(parent: VBoxContainer, texture: Texture2D, face: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(row)
	_indicator_caption = MODAL.village_title(row, "翻鸡指示牌")
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
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_stretch_ratio = 1.24 if primary else 1.0
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	MODAL.village_button(button, primary)
	button.pressed.connect(action)
	parent.add_child(button)
