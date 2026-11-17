extends VBoxContainer
## Native create, join and public-room pages share the lobby's authoritative events.

signal action_requested(action: String, payload: Dictionary)

const UI := "res://modules/games/mahjong/guiyang/assets/ui/"
const RURAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_theme.gd")
const MODAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_modal.gd")
const HOME := preload(UI + "lobby_rural/room_home.svg")
const TILES := preload(UI + "lobby_rural/icon_tiles.svg")
const GUIYANG_ART := preload(UI + "series/rural_training_v2.png")
const EYE := preload(UI + "login_rural/icon_eye.svg")
const EYE_OFF := preload(UI + "login_rural/icon_eye_off.svg")
const INK := Color("#603b22")
const SUBTLE := Color("#80644d")
const GREEN := Color("#2e5728")
const GOLD_EDGE := Color("#d99b4c")
const ERROR_INK := Color("#a13c28")
const PORTRAIT_PANEL_WIDTH := 910.0
const LANDSCAPE_PANEL_WIDTH := 1080.0
const LANDSCAPE_FORM_BREAKPOINT := 900.0
const OPTIONS := {
	"chicken": ["MahjongRuleChicken", "计鸡分"],
	"charge_chicken": ["MahjongRuleChargeChicken", "冲锋鸡"],
	"black_eight": ["MahjongRuleBlackEight", "黑八（八筒）"],
	"requires_kong_to_claim": ["MahjongRuleKongPass", "先杠后接炮胡"],
	"rob_kong": ["MahjongRuleRobKong", "抢杠胡"],
}

var page := ""
var _data: Dictionary = {}
var _presets: Array = []
var _header: HBoxContainer
var _back: Button
var _home: Button
var _scene_gap: Control
var _title_row: HBoxContainer
var _plaque: Label
var _join_title: Label
var _create: VBoxContainer
var _create_columns: BoxContainer
var _create_details: VBoxContainer
var _create_options: VBoxContainer
var _join: VBoxContainer
var _join_columns: BoxContainer
var _join_code_area: VBoxContainer
var _join_actions: VBoxContainer
var _directory: VBoxContainer
var _notice: Label
var _frame: PanelContainer
var _settings: GridContainer
var _rule_selector: Button
var _rule_cards: GridContainer
var _rule_picker_open := false
var _rules_loading: Label
var _rule_buttons: Array[Button] = []
var _rule_frames: Array[PanelContainer] = []
var _rule_indicators: Array[Label] = []
var _create_rows: Array[BoxContainer] = []
var _create_labels: Array[Label] = []
var _rule_frame := _preset_surface(false)
var _rule_frame_selected := _preset_surface(true)
var _create_selection := {}
var _toggles: Dictionary[String, CheckButton] = {}
var _option_rows: Dictionary[String, PanelContainer] = {}
var _drafts: Dictionary = {}
var _round_limit := 8
var _round_buttons: Array[Button] = []
var _seats: Label
var _turn_timeout: LineEdit
var _preview := ""
var _preview_value: Label
var _create_password: LineEdit
var _create_spectators: CheckButton
var _create_eye: Button
var _generate: Button
var _create_submit: Button
var _join_instruction: Label
var _code: LineEdit
var _code_digits: Array[Label] = []
var _keys: Array[Button] = []
var _join_secret_border: BoxContainer
var _join_secret_label: Label
var _join_password: LineEdit
var _join_eye: Button
var _join_submit: Button
var _join_watch_row: HBoxContainer
var _join_watch_seat: OptionButton
var _join_watch: Button
var _join_paste: Button
var _join_pad: GridContainer
var _refresh: Button
var _tabs: HFlowContainer
var _people: OptionButton
var _round_filter: OptionButton
var _filter_arrow: Texture2D
var _compact_filter_arrow: AtlasTexture
var _list_scroll: ScrollContainer
var _list: VBoxContainer
var _empty: Label
var _row_buttons: Array[Button] = []
var _narrow_directory := false
var _portrait_reference := false
var _directory_signature: Array = []
var _filter_id := ""
var _filter_version := ""
var _filter_legacy_name := ""
var _prompt_password := false
var _join_intent := "join"
var _local_notice := ""
var _handled_password_result := false

func _ready() -> void:
	name = "MahjongRoomPages"
	add_theme_constant_override("separation", 6)
	_header = MODAL.village_header(self, "MahjongRoomPageBackButton",
		func() -> void: action_requested.emit("page_back", {}), "MahjongRoomBrandSpace", false)
	_back = _header.get_child(-1) as Button
	_home = _icon_button(_header, "MahjongRoomPageHomeButton", HOME, "返回大厅")
	_header.move_child(_home, _back.get_index())
	_home.pressed.connect(func() -> void: action_requested.emit("page_home", {}))
	_scene_gap = Control.new()
	_scene_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scene_gap)
	_frame = MODAL.village_panel(self)
	_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var contents := _column(_frame, 10)
	_title_row = _row(contents, 0)
	_title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_plaque = MODAL.village_title(_title_row, "", _frame)
	_build_create(contents)
	_build_join(contents)
	_build_directory(contents)
	_notice = _label(contents, "", 21, ERROR_INK)
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.hide()
	hide()

func set_page(next: String, compact: bool, available_width: float, direct_home := false, minimum_panel_width := 0.0) -> void:
	var changed := page != next
	page = next
	visible = not next.is_empty()
	if not visible:
		return
	if changed:
		_rule_picker_open = false
	name = {"create":"MahjongCreateRoomPage", "join":"MahjongJoinRoomPage", "directory":"MahjongRoomDirectoryPage"}.get(page, "MahjongRoomPages")
	_back.name = "MahjongCloseJoinButton" if page == "join" else "MahjongCustomRulesBackButton" if page == "create" else "MahjongRoomPageBackButton"
	var design_width := LANDSCAPE_PANEL_WIDTH if compact and page != "directory" else PORTRAIT_PANEL_WIDTH
	var layout_width := minf(available_width, maxf(design_width, minimum_panel_width))
	var tall_join := page == "join" and not compact
	var narrow_join := tall_join and layout_width < 430.0
	var touch := RURAL.touch_extent(self)
	var usable_height := get_viewport_rect().size.y
	var short_directory := page == "directory" and usable_height <= 480.0 and available_width >= usable_height * 1.5
	var compact_directory := page == "directory" and (compact or short_directory)
	_portrait_reference = not compact and layout_width >= 650.0 and usable_height >= 1320.0
	var split := compact and layout_width >= LANDSCAPE_FORM_BREAKPOINT
	var form_width := layout_width * 0.47 if split else layout_width
	_frame.custom_minimum_size.x = layout_width
	_create_columns.vertical = not split
	_join_columns.vertical = not split
	_join_actions.alignment = BoxContainer.ALIGNMENT_CENTER if split else BoxContainer.ALIGNMENT_BEGIN
	var panel_style := _frame.get_theme_stylebox("panel")
	var panel_inset := 42.0 if page != "directory" and layout_width > 535.0 else 26.0
	panel_style.set_content_margin(SIDE_LEFT, panel_inset)
	panel_style.set_content_margin(SIDE_RIGHT, panel_inset)
	MODAL.fit_village_header(_header, available_width, usable_height)
	var scene_fraction := 0.14 if page == "directory" else 0.055 if page == "create" else 0.082
	_scene_gap.custom_minimum_size.y = 4 if short_directory else 8 if compact else 18 if narrow_join else clampf(usable_height * scene_fraction, 20.0, 240.0 if _portrait_reference else 118.0)
	for title in [_plaque, _join_title]:
		title.get_parent().custom_minimum_size = Vector2(clampf(layout_width * 0.55, 190, 475), 106 if _portrait_reference else 62 if compact or compact_directory else 84)
		title.add_theme_font_size_override("font_size", 58 if _portrait_reference else clampi(roundi(layout_width * 0.06), 30, 42))
	_title_row.visible = page != "join"
	_rule_cards.columns = 1 if form_width < 574 else 2
	_settings.columns = 1 if form_width < 430 else 2
	for row in _create_rows:
		row.vertical = form_width < 410
	for caption in _create_labels:
		caption.custom_minimum_size.x = 245.0 if _portrait_reference else clampf(form_width * 0.23, 100.0, 176.0)
		caption.custom_minimum_size.y = 91 if _portrait_reference else 34 if form_width < 410 else 49
		caption.add_theme_font_size_override("font_size", 34 if _portrait_reference else 23)
	_join_secret_border.vertical = form_width < 428
	_narrow_directory = layout_width < 574
	for room_button in _row_buttons:
		_fit_directory_row(room_button, touch)
	for filter in [_people, _round_filter]:
		filter.add_theme_constant_override("arrow_margin", 3 if _narrow_directory else 7)
		filter.add_theme_font_size_override("font_size", 30 if _portrait_reference else 14 if _narrow_directory else 22)
		filter.add_theme_icon_override("arrow", _compact_filter_arrow if _narrow_directory else _filter_arrow)
	_set_button_padding(_people, 6 if _narrow_directory else 14)
	_set_button_padding(_round_filter, 6 if _narrow_directory else 14)
	_list_scroll.custom_minimum_size.y = 470.0 if _portrait_reference else 205.0 if compact_directory else clampf(usable_height * 0.35, 225.0, 450.0)
	_list.add_theme_constant_override("separation", 19 if _portrait_reference else 9)
	var create_gap := 19 if _portrait_reference else 12
	for group in [_create, _create_details, _create_options]:
		group.add_theme_constant_override("separation", create_gap)
	_create_columns.add_theme_constant_override("separation", 24 if split else create_gap)
	var join_gap := 18 if _portrait_reference else 8 if narrow_join else 12
	for group in [_join, _join_code_area, _join_actions]:
		group.add_theme_constant_override("separation", join_gap)
	_join_columns.add_theme_constant_override("separation", 24 if split else join_gap)
	_join_pad.add_theme_constant_override("v_separation", 14 if _portrait_reference else 12 if tall_join and not narrow_join else 8)
	var code_height := 120.0 if _portrait_reference else clampf(layout_width * 0.13, 60.0, 86.0) if tall_join else 65.0
	_code.custom_minimum_size.y = RURAL.form_control_height(code_height, touch)
	_code.custom_minimum_size.x = 528.0 if _portrait_reference else maxf(124.0, touch)
	_code.size_flags_horizontal = Control.SIZE_FILL if _portrait_reference else Control.SIZE_EXPAND_FILL
	_join_instruction.add_theme_font_size_override("font_size", 44 if _portrait_reference else 24)
	for digit in _code_digits:
		digit.get_parent().custom_minimum_size.y = _code.custom_minimum_size.y
		digit.add_theme_font_size_override("font_size", 60 if _portrait_reference else 34)
	var key_height := 99.0 if _portrait_reference else clampf(layout_width * 0.108, 53, 77) if tall_join else 53.0
	for key in _keys:
		key.custom_minimum_size.x = maxf(48.0, touch)
		key.custom_minimum_size.y = RURAL.form_control_height(key_height, touch)
		key.add_theme_font_size_override("font_size", 44 if _portrait_reference else 28 if not key.text.is_valid_int() else 36)
	var field_height := RURAL.form_control_height(91.0 if _portrait_reference else 49.0, touch)
	for target: Control in [_join_password, _join_eye, _rule_selector, _create_password, _create_eye, _generate, _turn_timeout, _preview_value, _seats]:
		target.custom_minimum_size.y = field_height
	_join_paste.custom_minimum_size = Vector2(maxf(touch, 154.0 if _portrait_reference else 48.0),
		maxf(touch, 82.0 if _portrait_reference else field_height))
	_join_paste.add_theme_font_size_override("font_size", 33 if _portrait_reference else 18)
	_join_secret_label.custom_minimum_size = Vector2(220.0, field_height) if _portrait_reference else Vector2.ZERO
	_join_secret_label.add_theme_font_size_override("font_size", 38 if _portrait_reference else 22)
	for field in [_join_password, _create_password, _turn_timeout]:
		field.add_theme_font_size_override("font_size", 34 if _portrait_reference else 22)
	for eye in [_join_eye, _create_eye]:
		eye.custom_minimum_size.x = maxf(touch, 84.0 if _portrait_reference else 49.0)
		eye.add_theme_constant_override("icon_max_width", 42 if _portrait_reference else 23)
	_rule_selector.add_theme_font_size_override("font_size", 36 if _portrait_reference else 25)
	var generate_font_size := 31 if _portrait_reference else 18
	var generate_style := _generate.get_theme_stylebox("normal")
	var generate_text_width := _generate.get_theme_font("font").get_string_size(_generate.text, HORIZONTAL_ALIGNMENT_LEFT, -1, generate_font_size).x
	var generate_width := ceilf(generate_text_width + generate_style.get_margin(SIDE_LEFT) + generate_style.get_margin(SIDE_RIGHT) + 4.0)
	_generate.custom_minimum_size.x = maxf(touch, maxf(generate_width, 195.0 if _portrait_reference else 48.0))
	_generate.add_theme_font_size_override("font_size", generate_font_size)
	_preview_value.add_theme_font_size_override("font_size", 40 if _portrait_reference else 30)
	_seats.add_theme_font_size_override("font_size", 35 if _portrait_reference else 25)
	for toggle in _toggles.values():
		toggle.custom_minimum_size.y = 75 if _portrait_reference else 44
		toggle.get_parent().get_child(0).add_theme_font_size_override("font_size", 28 if _portrait_reference else 20)
	_create_spectators.custom_minimum_size.y = maxf(touch, 75.0 if _portrait_reference else 48.0)
	_create_spectators.add_theme_font_size_override("font_size", 28 if _portrait_reference else 20)
	_join_submit.custom_minimum_size.y = maxf(touch, 131.0 if _portrait_reference else 85.0 if tall_join else 77.0)
	_create_submit.custom_minimum_size.y = maxf(touch, 131.0 if _portrait_reference else 72.0)
	for submit in [_join_submit, _create_submit]:
		submit.custom_minimum_size.x = minf(layout_width * 0.83, submit.custom_minimum_size.y * 5.2)
		submit.add_theme_font_size_override("font_size", 48 if _portrait_reference else 32)
	var filter_height := maxf(touch, 70.0 if _portrait_reference else 52.0)
	MODAL.size_icon_button(_refresh, self)
	for filter in [_people, _round_filter]:
		filter.custom_minimum_size = Vector2(maxf(84.0, touch), filter_height)
	MODAL.size_icon_button(_home, self)
	_home.visible = direct_home
	_create.visible = page == "create"
	_join.visible = page == "join"
	_directory.visible = page == "directory"
	_plaque.text = {"create":"创建房间", "directory":"房间列表"}.get(page, "")
	if page == "create" and _preview.is_empty():
		_random_code()
	if changed and page == "join" and not OS.has_feature("mobile"):
		_code.grab_focus.call_deferred()
	_update()


func navigate_back() -> bool:
	if not is_visible_in_tree() or _back.disabled:
		return false
	_back.pressed.emit()
	return true

func apply(data: Dictionary) -> void:
	_data = data
	var presets: Array = data.get("presets", [])
	if presets != _presets:
		_presets = presets
		_rebuild_rule_cards()
		_tabs.get_child(0).button_pressed = true
		_filter_id = ""
		_filter_version = ""
		_filter_legacy_name = ""
		for child in _tabs.get_children().slice(1):
			_tabs.remove_child(child)
			child.queue_free()
		var version_counts := {}
		for preset: Dictionary in _presets:
			var id := str(preset.get("rule_set_id", ""))
			version_counts[id] = int(version_counts.get(id, 0)) + 1
		for preset: Dictionary in _presets:
			var id := str(preset.get("rule_set_id", ""))
			var version := str(preset.get("rule_version", ""))
			var title := str(preset.get("name", "麻将"))
			var short_title := title.get_slice("·", 0)
			var multiple_versions: bool = version_counts[id] > 1
			var caption := "%s %s" % [preset.get("region", short_title), version] if multiple_versions else title
			_add_tab(id, caption, version, caption if multiple_versions else short_title, title if multiple_versions else "")
		_directory_signature.clear()
	var password_required: bool = data.get("command_error", "") == "room_password_required" and page == "join"
	if password_required and not _handled_password_result:
		_prompt_password = true
		_join_password.grab_focus.call_deferred()
	_handled_password_result = password_required
	if visible:
		_update()

func clear_credentials() -> void:
	_create_password.clear()
	_create_password.secret = true
	_create_eye.icon = EYE
	_join_password.clear()
	_join_password.secret = true
	_join_eye.icon = EYE
	_prompt_password = false
	_join_intent = "join"
	_handled_password_result = false
	_local_notice = ""


func prefill_watch(room_id: String, seat: int) -> void:
	_code.text = room_id
	_code_changed(room_id)
	_join_watch_seat.select(_join_watch_seat.get_item_index(seat))
	_join_intent = "watch"

func _build_create(parent: Control) -> void:
	_create = _column(parent, 12)
	_create_columns = _reflow_columns(_create)
	_create_details = _column(_create_columns, 12)
	_create_options = _column(_create_columns, 12)
	for group in [_create_details, _create_options]:
		group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var gameplay := _create_row(_create_details, 8)
	_create_field_label(gameplay, "房间玩法")
	_rule_selector = _button(gameplay, "MahjongCreateRuleSelector", "", false, 49, 25)
	_rule_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rule_selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_rule_selector.pressed.connect(func() -> void:
		_rule_picker_open = not _rule_picker_open
		_update())
	_rule_cards = GridContainer.new()
	_rule_cards.name = "MahjongCreateRuleCards"
	_rule_cards.add_theme_constant_override("h_separation", 12)
	_rule_cards.add_theme_constant_override("v_separation", 10)
	_create_details.add_child(_rule_cards)
	_rules_loading = _label(_create_details, "正在读取服务端玩法", 18, SUBTLE)
	var seats := _create_row(_create_details, 8)
	_create_field_label(seats, "人数")
	_seats = _label(seats, "4 人", 25)
	_seats.add_theme_font_override("font", MODAL.village_font())
	_seats.tooltip_text = "当前玩法为四人麻将"
	_seats.add_theme_stylebox_override("normal", MODAL.capsule_frame(Vector4(10, 4, 10, 4)))
	_seats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seats.custom_minimum_size.x = 106
	_seats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seats.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var round_row := _create_row(_create_details, 8)
	_create_field_label(round_row, "局数")
	var round_options := _row(round_row, 8)
	round_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for limit in [8, 16, 24]:
		var choice := _button(round_options, "MahjongRoomRounds%d" % limit, "%d 局" % limit, false, 49, 21)
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.pressed.connect(func() -> void:
			_round_limit = limit
			_update())
		_round_buttons.append(choice)
	var timing := _create_row(_create_details, 8)
	_create_field_label(timing, "出牌时限")
	var seconds := _row(timing, 8)
	seconds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_turn_timeout = _field(seconds, "MahjongTurnTimeoutSeconds", "1–60", false)
	_turn_timeout.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_timeout.text = "15"
	_turn_timeout.text_changed.connect(func(_value: String) -> void: _update())
	var unit := _label(seconds, "秒（1–60）", 18, SUBTLE)
	unit.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var settings_card := PanelContainer.new()
	settings_card.add_theme_stylebox_override("panel", _card_surface(Vector4(10, 5, 10, 5)))
	_create_options.add_child(settings_card)
	_settings = GridContainer.new()
	_settings.columns = 2
	_settings.add_theme_constant_override("h_separation", 10)
	_settings.add_theme_constant_override("v_separation", 5)
	settings_card.add_child(_settings)
	var blank := ImageTexture.create_from_image(Image.create_empty(1, 1, false, Image.FORMAT_RGBA8))
	for key in OPTIONS:
		var option := PanelContainer.new()
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.add_theme_stylebox_override("panel", MODAL.capsule_frame(Vector4(12, 4, 12, 4)))
		_settings.add_child(option)
		var row := _row(option, 6)
		var caption := _label(row, OPTIONS[key][1], 20)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var toggle := CheckButton.new()
		toggle.name = OPTIONS[key][0]
		toggle.tooltip_text = OPTIONS[key][1]
		toggle.accessibility_name = OPTIONS[key][1]
		MODAL.toggle(toggle)
		for icon in ["checked", "unchecked", "checked_disabled", "unchecked_disabled", "checked_mirrored", "unchecked_mirrored", "checked_disabled_mirrored", "unchecked_disabled_mirrored"]:
			toggle.add_theme_icon_override(icon, blank)
		row.add_child(toggle)
		toggle.toggled.connect(_toggle.bind(key))
		_toggles[key] = toggle
		_option_rows[key] = option
	_create_spectators = CheckButton.new()
	_create_spectators.name = "MahjongAllowSpectators"
	_create_spectators.text = "允许观战"
	_create_spectators.tooltip_text = "开启后，每位牌友可开放自己的座位，每座限一人观战"
	RURAL.skin_button(_create_spectators)
	_create_spectators.add_theme_font_override("font", MODAL.village_font())
	_create_options.add_child(_create_spectators)
	var password := _create_row(_create_options, 10)
	_create_field_label(password, "房间密码")
	var password_input := _row(password, 8)
	password_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_create_password = _field(password_input, "MahjongCreateRoomPassword", "可选 · 四位数字", true)
	_create_password.tooltip_text = "留空时，房间会显示在公开列表中"
	_create_password.text_changed.connect(_password_changed.bind(_create_password))
	_create_eye = _eye_button(password_input, _create_password)
	var code_row := _create_row(_create_options, 8)
	_create_field_label(code_row, "房间号")
	var code_controls := _row(code_row, 6)
	code_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_value = _label(code_controls, "", 30)
	_preview_value.name = "MahjongCreateRoomCodeValue"
	_preview_value.add_theme_stylebox_override("normal", MODAL.capsule_frame(Vector4(12, 4, 12, 4)))
	_preview_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_generate = _button(code_controls, "MahjongRegenerateRoomCodeButton", "随机生成", false, 46, 18)
	_generate.pressed.connect(_random_code)
	_create_submit = _button(_create, "MahjongCustomRulesCreateButton", "创建房间", true, 70, 32)
	_create_submit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_create_submit.pressed.connect(_submit_create)


func _create_row(parent: Control, separation: int) -> BoxContainer:
	var row := BoxContainer.new()
	row.add_theme_constant_override("separation", separation)
	parent.add_child(row)
	_create_rows.append(row)
	return row

func _create_field_label(parent: Control, caption: String) -> void:
	var label := _row_label(parent, caption)
	_create_labels.append(label)


func _rebuild_rule_cards() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	var focus_name := focused.name if _rule_buttons.has(focused) else &""
	for card in _rule_cards.get_children():
		_rule_cards.remove_child(card)
		card.queue_free()
	_rule_buttons.clear()
	_rule_frames.clear()
	_rule_indicators.clear()
	var group := ButtonGroup.new()
	for index in _presets.size():
		var preset: Dictionary = _presets[index]
		var title := str(preset.get("name", "麻将"))
		var version := str(preset.get("rule_version", ""))
		var summary := str(preset.get("summary", ""))
		var frame := PanelContainer.new()
		frame.custom_minimum_size.y = 112
		frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		frame.add_theme_stylebox_override("panel", _rule_frame)
		_rule_cards.add_child(frame)
		_rule_frames.append(frame)

		var inset := MarginContainer.new()
		frame.add_child(inset)
		for side in ["left", "top", "right", "bottom"]:
			inset.add_theme_constant_override("margin_" + side, 10)
		var row := _row(inset, 11)
		var illustration := _art(row, _preset_illustration(str(preset.get("rule_set_id", ""))), Vector2(88, 90))
		illustration.name = "MahjongCreateRuleIllustration"
		var words := _column(row, 3)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.alignment = BoxContainer.ALIGNMENT_CENTER
		var headline := _row(words, 6)
		var name_label := _label(headline, title, 25)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var chosen := _label(headline, "已选", 17, GREEN)
		chosen.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_rule_indicators.append(chosen)
		var version_label := _label(words, "版本 " + version, 15, SUBTLE)
		version_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var description := _label(words, summary, 17, INK)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.visible = not summary.is_empty()

		var button := Button.new()
		button.name = ("MahjongCreateRuleCard_%s_%s" % [preset.get("rule_set_id", ""), version.replace(".", "_")]).validate_node_name()
		button.toggle_mode = true
		button.button_group = group
		button.accessibility_name = title
		button.accessibility_description = version_label.text + "。 " + summary
		button.tooltip_text = title + " · " + version + "\n" + summary
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		var focus := RURAL.frame(Color.TRANSPARENT, Color("#467942"), 14, 3)
		focus.draw_center = false
		focus.shadow_size = 0
		button.add_theme_stylebox_override("focus", focus)
		frame.add_child(button)
		button.pressed.connect(_select_rule.bind(index))
		_rule_buttons.append(button)
		if button.name == focus_name:
			button.grab_focus.call_deferred()
	_rules_loading.visible = _presets.is_empty()


func _preset_illustration(rule_id: String) -> Texture2D:
	if rule_id != "guiyang":
		return TILES
	var portrait := AtlasTexture.new()
	portrait.atlas = GUIYANG_ART
	portrait.region = Rect2(660, 311, 596, 620)
	portrait.filter_clip = true
	return portrait


func _preset_surface(selected: bool) -> StyleBoxFlat:
	var fill := Color("#ffe3a6") if selected else Color("#fff2d8")
	var edge := Color("#c17e28") if selected else Color("#c7a471")
	var box := RURAL.frame(fill, edge, 14, 2 if selected else 1)
	box.shadow_size = 3
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		box.set_content_margin(side, 0)
	return box

func _build_join(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.name = "MahjongJoinPanel"
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	parent.add_child(panel)
	_join = _column(panel, 12)
	var heading := _row(_join, 0)
	heading.alignment = BoxContainer.ALIGNMENT_CENTER
	_join_title = MODAL.village_title(heading, "加入房间", _frame)
	_join_title.name = "MahjongJoinTitle"
	_join_columns = _reflow_columns(_join)
	_join_code_area = _column(_join_columns, 12)
	_join_actions = _column(_join_columns, 12)
	for group in [_join_code_area, _join_actions]:
		group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_instruction = _label(_join_code_area, "请输入 4 位房间号", 27)
	_join_instruction.add_theme_font_override("font", MODAL.village_font())
	_join_instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_join_instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var input_row := _row(_join_code_area, 9)
	input_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_code = _field(input_row, "MahjongJoinCode", "", false)
	_code.virtual_keyboard_enabled = false
	_code.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code.custom_minimum_size.y = 66
	_code.text_changed.connect(_code_changed)
	_code.text_submitted.connect(func(_text: String) -> void: _submit_room(_join_intent))
	# The editable field spans the four cells, so cursor, IME and keyboard shortcuts remain native.
	var digit_layer := HBoxContainer.new()
	digit_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	digit_layer.add_theme_constant_override("separation", 8)
	_code.add_child(digit_layer)
	digit_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_code_digits = _digit_boxes(digit_layer, 62, 34)
	for theme_color in ["font_color", "font_selected_color", "font_uneditable_color", "font_placeholder_color", "caret_color", "selection_color"]:
		_code.add_theme_color_override(theme_color, Color.TRANSPARENT)
	_code.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_code.add_theme_stylebox_override("read_only", StyleBoxEmpty.new())
	_join_paste = _button(input_row, "MahjongPasteRoomCodeButton", "粘贴", false, 47, 20)
	_join_paste.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_join_paste.pressed.connect(_paste)
	_join_pad = GridContainer.new()
	_join_pad.name = "MahjongRoomKeypad"
	_join_pad.columns = 3
	_join_pad.add_theme_constant_override("h_separation", 12)
	_join_code_area.add_child(_join_pad)
	for entry: String in ["1","2","3","4","5","6","7","8","9","清空","0","⌫"]:
		var suffix := "Clear" if entry == "清空" else "Backspace" if entry == "⌫" else entry
		var key := _button(_join_pad, "MahjongRoomKey" + suffix, entry, false, 58, 28 if suffix.length() > 1 else 36)
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		key.pressed.connect(_append_key.bind(entry))
		_keys.append(key)
	_join_secret_border = BoxContainer.new()
	_join_secret_border.add_theme_constant_override("separation", 9)
	_join_actions.add_child(_join_secret_border)
	_join_secret_label = _row_label(_join_secret_border, "房间密码")
	var password_row := _row(_join_secret_border, 8)
	password_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_password = _field(password_row, "MahjongJoinRoomPassword", "选填 · 四位数字", true)
	_join_password.text_changed.connect(_password_changed.bind(_join_password))
	_join_password.text_submitted.connect(func(_text: String) -> void: _submit_room(_join_intent))
	_join_eye = _eye_button(password_row, _join_password)
	_join_submit = _button(_join_actions, "MahjongJoinButton", "加入房间", true, 76, 34)
	_join_submit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_join_submit.pressed.connect(_submit_room.bind("join"))
	_join_watch_row = _row(_join_actions, 8)
	_join_watch_seat = OptionButton.new()
	_join_watch_seat.name = "MahjongWatchSeat"
	_join_watch_seat.tooltip_text = "选择要观战的座位"
	_join_watch_seat.accessibility_name = "要观战的座位"
	_join_watch_seat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for seat in range(4):
		_join_watch_seat.add_item("%d 号位" % (seat + 1), seat)
	MODAL.village_button(_join_watch_seat)
	_join_watch_row.add_child(_join_watch_seat)
	_join_watch = _button(_join_watch_row, "MahjongWatchRoomButton", "观战", false, 53, 22)
	_join_watch.pressed.connect(_submit_room.bind("watch"))

func _build_directory(parent: Control) -> void:
	_directory = _column(parent, 10)
	_tabs = HFlowContainer.new()
	_tabs.alignment = FlowContainer.ALIGNMENT_CENTER
	_tabs.add_theme_constant_override("h_separation", 5)
	_tabs.add_theme_constant_override("v_separation", 5)
	_directory.add_child(_tabs)
	_add_tab("", "全部房间")
	_tabs.get_child(0).button_pressed = true
	var filters := HFlowContainer.new()
	filters.alignment = FlowContainer.ALIGNMENT_CENTER
	filters.add_theme_constant_override("h_separation", 7)
	filters.add_theme_constant_override("v_separation", 7)
	_directory.add_child(filters)
	_people = _filter_menu(filters, "MahjongRoomPeopleFilter", "人数", ["全部", "1 人", "2 人", "3 人", "4 人"])
	_round_filter = _filter_menu(filters, "MahjongRoomRoundsFilter", "局数", ["全部", "8 局", "16 局", "24 局", "不限"])
	_filter_arrow = _people.get_theme_icon("arrow")
	_compact_filter_arrow = AtlasTexture.new()
	_compact_filter_arrow.atlas = _filter_arrow
	_compact_filter_arrow.region = Rect2(0, 0, 17, _filter_arrow.get_height())
	_refresh = _icon_button(filters, "MahjongRefreshRoomsButton", MODAL.icon("refresh"), "刷新房间列表")
	_refresh.pressed.connect(func() -> void: action_requested.emit("refresh_rooms", {}))
	_list_scroll = ScrollContainer.new()
	_list_scroll.name = "MahjongRoomDirectoryScroll"
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_scroll.follow_focus = true
	_directory.add_child(_list_scroll)
	_list = _column(_list_scroll, 12)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_empty = _label(_list, "", 20, SUBTLE)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.custom_minimum_size.y = 152
	var footer := _row(_directory, 10)
	var create := _button(footer, "MahjongDirectoryCreateButton", "创建房间", true, 61, 25)
	var join := _button(footer, "MahjongDirectoryJoinButton", "加入房间", false, 61, 25)
	for control in [create, join]:
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create.pressed.connect(func() -> void: action_requested.emit("open_create", {}))
	join.pressed.connect(func() -> void: action_requested.emit("open_join", {}))

func _update() -> void:
	var pending := bool(_data.get("pending", false))
	var online := bool(_data.get("online", false))
	_back.disabled = pending
	_home.disabled = pending
	for key in _keys:
		key.disabled = pending
	_code.editable = not pending
	_join_paste.disabled = pending
	_join_password.editable = not pending
	_join_eye.disabled = pending
	_join_password.placeholder_text = "请输入四位数字密码" if _prompt_password else "选填 · 四位数字"
	var password_length := _join_password.text.length()
	var password_valid := password_length == 4 or (password_length == 0 and not _prompt_password)
	_join_submit.disabled = not online or pending or _code.text.length() != 4 or not password_valid
	var spectator_supported := bool(_data.get("spectator_supported", false))
	_create_spectators.visible = spectator_supported
	_create_spectators.disabled = pending
	_join_watch_row.visible = spectator_supported
	_join_watch_seat.disabled = _join_submit.disabled
	_join_watch.disabled = _join_submit.disabled
	var watch_height := maxf(53.0, RURAL.touch_extent(self))
	_join_watch.custom_minimum_size = Vector2(maxf(72.0, watch_height), watch_height)
	_join_watch_seat.custom_minimum_size = Vector2(maxf(90.0, watch_height), watch_height)
	_draw_digits(_code_digits, _code.text)
	if page == "create":
		_update_create(online, pending)
	elif page == "directory":
		_update_directory()
	var message := _local_notice if not _local_notice.is_empty() else str(_data.get("message", ""))
	_notice.text = message
	_notice.visible = not message.is_empty()

func _update_create(online: bool, pending: bool) -> void:
	var preset := _selected_preset()
	var version := str(preset.get("options", {}).get("version", ""))
	var rule_name := str(preset.get("name", "选择玩法"))
	_rule_selector.text = "%s  %s" % [rule_name, "▴" if _rule_picker_open else "▾"]
	_rule_selector.disabled = pending or _presets.is_empty()
	_rule_cards.visible = _rule_picker_open and not _presets.is_empty()
	for index in _rule_buttons.size():
		var selected: bool = _presets[index] == preset
		_rule_buttons[index].disabled = pending
		_rule_buttons[index].set_pressed_no_signal(selected)
		_rule_frames[index].add_theme_stylebox_override("panel", _rule_frame_selected if selected else _rule_frame)
		_rule_indicators[index].visible = selected
	var draft := _draft(preset) if version in ["1.0.0", "2.0.0"] else {}
	for key in _toggles:
		var toggle := _toggles[key]
		var shown := version != "2.0.0" or _is_v2_option(preset, key)
		_option_rows[key].visible = shown
		var allowed := not draft.is_empty() and shown and (key not in ["charge_chicken", "black_eight"] or bool(draft.get("chicken", false)))
		toggle.set_pressed_no_signal(allowed and bool(draft.get(key, false)))
		toggle.disabled = pending or not allowed or _locked(preset, key)
	var round_height := RURAL.form_control_height(91.0 if _portrait_reference else 49.0, RURAL.touch_extent(self))
	for index in _round_buttons.size():
		var choice := _round_buttons[index]
		_style_button(choice, (index + 1) * 8 == _round_limit, round_height, 36 if _portrait_reference else 21)
		choice.disabled = pending
	_turn_timeout.editable = not pending
	_create_password.editable = not pending
	_create_eye.disabled = pending
	_generate.disabled = pending
	_create_submit.disabled = not online or pending or preset.is_empty() or _turn_timeout_seconds() == 0 or _create_password.text.length() not in [0, 4]

func _turn_timeout_seconds() -> int:
	var value := _turn_timeout.text.strip_edges()
	if value.length() > 2 or not value.is_valid_int():
		return 0
	var seconds := value.to_int()
	return seconds if seconds >= 1 and seconds <= 60 else 0

func _selected_preset() -> Dictionary:
	var draft := _find_preset(_create_selection)
	if not draft.is_empty():
		return draft
	var selection: Dictionary = _data.get("selected", {})
	return _find_preset(selection)


func _find_preset(selection: Dictionary) -> Dictionary:
	for preset: Dictionary in _presets:
		if preset.get("rule_set_id") == selection.get("rule_set_id") and preset.get("rule_version") == selection.get("rule_version"):
			return preset
	return {}

func _select_rule(index: int) -> void:
	if bool(_data.get("pending", false)) or index < 0 or index >= _presets.size():
		return
	var preset: Dictionary = _presets[index]
	_create_selection = {"rule_set_id":preset.rule_set_id, "rule_version":preset.rule_version}
	_rule_picker_open = false
	_update_create(bool(_data.get("online", false)), false)
	_rule_selector.grab_focus()

func _draft(preset: Dictionary) -> Dictionary:
	var key := "%s/%s" % [preset.rule_set_id, preset.rule_version]
	if not _drafts.has(key):
		_drafts[key] = preset.get("options", {}).duplicate(true)
		if _locked(preset, "requires_kong_to_claim"):
			_drafts[key]["requires_kong_to_claim"] = true
	return _drafts[key]

func _locked(preset: Dictionary, key: String) -> bool:
	return key == "requires_kong_to_claim" and preset.get("rule_set_id") == "guiyang"

func _is_v2_option(preset: Dictionary, key: String) -> bool:
	var fields: Variant = preset.get("mutable_options")
	return key in ["chicken", "rob_kong"] and fields is Array and fields.has(key)

func _toggle(enabled: bool, key: String) -> void:
	var preset := _selected_preset()
	var version := str(preset.get("options", {}).get("version", ""))
	if version not in ["1.0.0", "2.0.0"] or _locked(preset, key) or (version == "2.0.0" and not _is_v2_option(preset, key)):
		return
	_draft(preset)[key] = enabled
	_update()

func _random_code() -> void:
	var previous := _preview
	while _preview.is_empty() or _preview == previous:
		_preview = str(randi_range(1000, 9999))
	_preview_value.text = _preview

func _submit_create() -> void:
	if _create_submit.disabled:
		return
	var preset := _selected_preset()
	var payload := {"room_id":_preview, "round_limit":_round_limit, "turn_timeout_seconds":_turn_timeout_seconds(),
		"rule_set_id":preset.rule_set_id, "rule_version":preset.rule_version}
	if _create_spectators.visible: payload["allow_spectators"] = _create_spectators.button_pressed
	if not _create_password.text.is_empty():
		payload["password"] = _create_password.text
	var version := str(preset.get("options", {}).get("version", ""))
	if version == "1.0.0":
		var options := _draft(preset).duplicate()
		if not bool(options.get("chicken", false)):
			options["charge_chicken"] = false
			options["black_eight"] = false
		payload["options"] = options
	elif version == "2.0.0":
		var options := {"version":version}
		var draft := _draft(preset)
		for key in OPTIONS:
			if _is_v2_option(preset, key) and draft.get(key) is bool:
				options[key] = draft[key]
		payload["options"] = options
	action_requested.emit("create", payload)

func _code_changed(input: String) -> void:
	var digits := _digits(input)
	if digits != input:
		_code.text = digits
		_code.caret_column = digits.length()
	_prompt_password = false
	_join_intent = "join"
	_join_password.clear()
	_local_notice = ""
	action_requested.emit("clear_room_message", {})
	_update()

func _append_key(value: String) -> void:
	if value == "清空":
		_code.text = ""
	elif value == "⌫":
		_code.text = _code.text.left(maxi(0, _code.text.length() - 1))
	else:
		_code.text += value if _code.text.length() < 4 else ""
	_code_changed(_code.text)
	_code.caret_column = _code.text.length()

func _paste() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		_local_notice = "当前设备无法读取剪贴板"
	else:
		var source := DisplayServer.clipboard_get().strip_edges()
		if source.length() == 4 and _digits(source).length() == 4:
			_code.text = _digits(source)
			_code_changed(_code.text)
			return
		_local_notice = "剪贴板中没有有效的四位房号"
	_update()

func _password_changed(input: String, field: LineEdit) -> void:
	var digits := _digits(input)
	if digits != input:
		field.text = digits
		field.caret_column = digits.length()
	_update()

func _submit_room(intent: String) -> void:
	var button := _join_watch if intent == "watch" else _join_submit
	if button.disabled or not button.is_visible_in_tree(): return
	var payload := {"room_id": _code.text}
	if intent == "watch":
		payload["watch_seat"] = _join_watch_seat.get_selected_id()
	if not _join_password.text.is_empty(): payload["password"] = _join_password.text
	_join_intent = intent
	action_requested.emit(intent, payload)

func _add_tab(id: String, caption: String, version := "", compact_caption := "", legacy_name := "") -> void:
	var tab_name := ("MahjongRoomFilterTab_%s_%s" % [id, version.replace(".", "_")]).validate_node_name()
	var tab := _button(_tabs, tab_name, caption, id.is_empty(), 47, 19)
	tab.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tab.set_meta("rule_id", id)
	tab.set_meta("rule_version", version)
	tab.set_meta("caption", caption)
	tab.set_meta("compact_caption", compact_caption if not compact_caption.is_empty() else caption)
	tab.tooltip_text = caption
	tab.accessibility_name = caption
	tab.pressed.connect(func() -> void:
		_filter_id = id
		_filter_version = version
		_filter_legacy_name = legacy_name
		_list_scroll.scroll_vertical = 0
		_update_directory())

func _filter_menu(parent: Control, id: String, category: String, choices: Array) -> OptionButton:
	var filter := OptionButton.new()
	filter.name = id
	filter.fit_to_longest_item = false
	filter.accessibility_name = category
	parent.add_child(filter)
	for caption: String in choices:
		filter.add_item("%s·%s" % [category, caption])
	_style_button(filter, false, 43, 18)
	filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter.item_selected.connect(func(_index: int) -> void:
		_list_scroll.scroll_vertical = 0
		_update_directory())
	return filter

func _update_directory() -> void:
	for tab: Button in _tabs.get_children():
		tab.text = tab.get_meta("compact_caption") if _narrow_directory else tab.get_meta("caption")
		var selected: bool = _filter_id == tab.get_meta("rule_id") and _filter_version == tab.get_meta("rule_version")
		var font_size := 16 if _narrow_directory else 19
		var padding := 8.0 if _narrow_directory else 12.0
		_style_button(tab, selected, maxf(47.0, RURAL.touch_extent(self)), font_size)
		_set_button_padding(tab, padding)
		var text_width := tab.get_theme_font("font").get_string_size(tab.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		tab.custom_minimum_size.x = ceilf(text_width + padding * 2.0 + 4.0)
	var pending := bool(_data.get("pending", false))
	var online := bool(_data.get("online", false))
	var available := bool(_data.get("directory_available", false))
	var loaded := bool(_data.get("directory_loaded", false))
	_refresh.disabled = not online or not available or pending
	var rooms: Array = _data.get("public_rooms", []) if online and available and loaded else []
	var signature := [rooms, _filter_id, _filter_version, _people.selected, _round_filter.selected, online, available, loaded, _data.get("directory_error", ""), _data.get("spectator_supported", false)]
	var restore_focus: StringName = &""
	if signature != _directory_signature:
		var focused := get_viewport().gui_get_focus_owner() as Button
		if focused in _row_buttons: restore_focus = focused.name
		_directory_signature = signature
		_render_rows(rooms)
	for button in _row_buttons:
		button.disabled = not online or pending or not bool(button.get_meta("available", false))
		if button.name == restore_focus and button.is_visible_in_tree() and not button.disabled:
			button.grab_focus()

func _render_rows(rooms: Array) -> void:
	for child in _list.get_children():
		if child != _empty:
			_list.remove_child(child)
			child.queue_free()
	_row_buttons.clear()
	var people := _people.selected
	var rounds: int = [0, 8, 16, 24, 0][_round_filter.selected]
	for item: Dictionary in rooms:
		if not _filter_id.is_empty():
			if item.get("rule_set_id", "") != _filter_id: continue
			var version := str(item.get("rule_version", ""))
			if not version.is_empty() and not _filter_version.is_empty() and version != _filter_version: continue
			if version.is_empty() and not _filter_legacy_name.is_empty() and item.get("rule_name", "") != _filter_legacy_name: continue
		if people > 0 and int(item.get("players", 0)) != people:
			continue
		if _round_filter.selected > 0 and int(item.get("round_limit", 0)) != rounds:
			continue
		_add_room_row(item)
	var count := _row_buttons.size()
	_empty.visible = count == 0
	if count > 0:
		return
	if not _data.get("online", false):
		_empty.text = "大厅未连接"
	elif not _data.get("directory_available", false):
		_empty.text = "当前服务器暂未提供房间列表"
	elif not str(_data.get("directory_error", "")).is_empty():
		_empty.text = str(_data.directory_error)
	elif not _data.get("directory_loaded", false):
		_empty.text = "正在读取房间列表…"
	else:
		_empty.text = "没有符合条件的公开房间"

func _add_room_row(item: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _card_surface(Vector4(9, 13, 9, 13)))
	panel.custom_minimum_size.y = 91
	_list.add_child(panel)
	var room_row := _row(panel, 9)
	var code := str(item.get("room_id", ""))
	var admission_paused := bool(item.get("admission_paused", false))
	var joinable := bool(item.get("joinable", false)) and not admission_paused
	var status := _label(room_row, "●", 16, GREEN if joinable else SUBTLE)
	status.name = "RoomStatus"
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var room_number := _label(room_row, code, 28)
	room_number.name = "RoomNumber"
	room_number.add_theme_font_override("font", MODAL.village_font())
	room_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	room_number.tooltip_text = "房间号 " + code
	var details := BoxContainer.new()
	details.name = "RoomDetails"
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.vertical = _narrow_directory
	details.alignment = BoxContainer.ALIGNMENT_CENTER
	details.add_theme_constant_override("separation", 6)
	room_row.add_child(details)
	var limit := int(item.get("round_limit", 0))
	var rule := str(item.get("rule_name", "麻将"))
	var rule_chip := _label(details, rule, 17 if _narrow_directory else 23)
	rule_chip.name = "RoomRule"
	rule_chip.add_theme_font_override("font", MODAL.village_font())
	rule_chip.add_theme_stylebox_override("normal", MODAL.capsule_frame(Vector4(6, 3, 6, 3)))
	rule_chip.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rule_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rule_chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rule_chip.tooltip_text = rule
	var players := int(item.get("players", 0))
	var capacity := int(item.get("capacity", 4))
	var stats := _label(details, "%d/%d  ·  %s" % [players, capacity, "%d 局" % limit if limit > 0 else "局数不限"], 18, SUBTLE)
	stats.name = "RoomStats"
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var free_seats: Variant = item.get("watchable_seats", [])
	var has_watch_slot: bool = _data.get("spectator_supported", false) and free_seats is Array and not free_seats.is_empty()
	var actions := _column(room_row, 4)
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if joinable or admission_paused or not has_watch_slot:
		var join_text := "加入" if joinable else "暂停入座" if admission_paused else "已满" if players >= capacity else "对局中"
		var join := _button(actions, "MahjongDirectoryJoin" + code, join_text, not admission_paused, 51, 22)
		if admission_paused:
			join.add_theme_color_override("font_disabled_color", SUBTLE)
		join.set_meta("available", joinable)
		join.pressed.connect(func() -> void: action_requested.emit("join", {"room_id": code}))
	if has_watch_slot:
		var watch := _button(actions, "MahjongDirectoryWatch" + code, "观战", not joinable, 51, 22)
		watch.set_meta("available", true)
		watch.pressed.connect(func() -> void:
			action_requested.emit("open_watch", {"room_id": code, "watch_seat": int(free_seats[0])}))
	for child in actions.get_children():
		var button := child as Button
		_set_button_padding(button, 6)
		_fit_directory_row(button, RURAL.touch_extent(self))
		_row_buttons.append(button)

func _fit_directory_row(button: Button, touch: float) -> void:
	var row := button.get_parent().get_parent() as HBoxContainer
	var panel := row.get_parent() as PanelContainer
	var details := row.get_node("RoomDetails") as BoxContainer
	var chip := details.get_node("RoomRule") as Label
	var stats := details.get_node("RoomStats") as Label
	panel.custom_minimum_size.y = 142.0 if _portrait_reference else 91.0
	row.get_node("RoomStatus").add_theme_font_size_override("font_size", 22 if _portrait_reference else 16)
	row.get_node("RoomNumber").add_theme_font_size_override("font_size", 46 if _portrait_reference else 28)
	details.vertical = _narrow_directory
	details.add_theme_constant_override("separation", 14 if _portrait_reference else 6)
	chip.custom_minimum_size = Vector2(180.0, 63.0) if _portrait_reference else Vector2.ZERO
	chip.size_flags_horizontal = Control.SIZE_FILL if _portrait_reference else Control.SIZE_EXPAND_FILL
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_theme_font_size_override("font_size", 29 if _portrait_reference else 17 if _narrow_directory else 23)
	stats.add_theme_font_size_override("font_size", 27 if _portrait_reference else 18)
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if _narrow_directory else TextServer.AUTOWRAP_OFF
	var compact_caption := _narrow_directory and button.text.length() >= 4
	var font_size := (28 if compact_caption else 34) if _portrait_reference else (17 if compact_caption else 22)
	var text_width := button.get_theme_font("font").get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var button_width := maxf(166.0 if _portrait_reference else 71.0, ceilf(text_width + 20.0))
	button.custom_minimum_size = Vector2(maxf(touch, button_width),
		maxf(touch, 80.0 if _portrait_reference else 52.0))
	button.add_theme_font_size_override("font_size", font_size)

func _digits(source: String) -> String:
	var text := ""
	for index in source.length():
		var digit := source.unicode_at(index)
		if digit >= 0xff10 and digit <= 0xff19:
			digit -= 0xff10 - 0x30
		if digit >= 0x30 and digit <= 0x39:
			text += String.chr(digit)
			if text.length() == 4:
				break
	return text

func _digit_boxes(parent: Control, height: int, font_size: int) -> Array[Label]:
	var digits: Array[Label] = []
	for index in 4:
		var chip := PanelContainer.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var style := _card_surface(Vector4(2, 1, 2, 2))
		chip.add_theme_stylebox_override("panel", style)
		chip.custom_minimum_size = Vector2(25, height)
		parent.add_child(chip)
		var digit := _label(chip, "", font_size)
		digit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		digit.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		digits.append(digit)
	return digits

func _draw_digits(labels: Array[Label], value: String) -> void:
	for index in labels.size():
		labels[index].text = value.substr(index, 1) if index < value.length() else "–"

func _row_label(parent: Control, caption: String) -> Label:
	var label := _label(parent, caption, 23)
	label.add_theme_font_override("font", MODAL.village_font())
	label.add_theme_stylebox_override("normal", MODAL.capsule_frame(Vector4(10, 2, 10, 2)))
	label.custom_minimum_size.x = 100
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

func _field(parent: Control, id: String, hint: String, secret: bool) -> LineEdit:
	var field := LineEdit.new()
	field.name = id
	field.placeholder_text = hint
	field.secret = secret
	field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.custom_minimum_size = Vector2(100, 50)
	field.add_theme_font_size_override("font_size", 21)
	field.add_theme_color_override("font_color", INK)
	field.add_theme_color_override("font_placeholder_color", SUBTLE)
	var fill := MODAL.capsule_frame(Vector4(18, 4, 18, 5))
	field.add_theme_stylebox_override("normal", fill)
	var focus := RURAL.frame(Color.TRANSPARENT, Color("#6f873e"), 11, 2)
	focus.shadow_size = 0
	field.add_theme_stylebox_override("focus", focus)
	parent.add_child(field)
	return field

func _eye_button(parent: Control, field: LineEdit) -> Button:
	var button := _button(parent, field.name + "Visibility", "", false, 48, 18)
	button.icon = EYE
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 23)
	button.custom_minimum_size.x = 49
	button.tooltip_text = "显示或隐藏密码"
	button.pressed.connect(func() -> void:
		field.secret = not field.secret
		button.icon = EYE if field.secret else EYE_OFF)
	return button

func _icon_button(parent: Control, id: String, texture: Texture2D, hint: String) -> Button:
	var button := Button.new()
	button.name = id
	parent.add_child(button)
	MODAL.icon_button(button, texture, hint)
	return button

func _button(parent: Control, id: String, caption: String, primary: bool, height: int, font_size: int) -> Button:
	var button := Button.new()
	button.name = id
	button.text = caption
	parent.add_child(button)
	_style_button(button, primary, height, font_size)
	return button

func _style_button(button: Button, primary: bool, height: float, font_size: int) -> void:
	MODAL.village_button(button, primary)
	button.custom_minimum_size.y = height
	button.add_theme_font_size_override("font_size", font_size)

func _set_button_padding(button: Button, horizontal: float) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var box := button.get_theme_stylebox(state)
		box.set_content_margin(SIDE_LEFT, horizontal)
		box.set_content_margin(SIDE_RIGHT, horizontal)

func _card_surface(padding: Vector4) -> StyleBoxFlat:
	var style := RURAL.frame(Color("#fff1d5"), GOLD_EDGE, 16, 2)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, padding[side])
	return style

func _art(parent: Control, texture: Texture2D, minimum: Vector2) -> TextureRect:
	var image := TextureRect.new()
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.texture = texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = minimum
	parent.add_child(image)
	return image

func _label(parent: Control, caption: String, font_size: int, ink: Color = INK) -> Label:
	var label := Label.new()
	label.text = caption
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", ink)
	parent.add_child(label)
	return label

func _column(parent: Control, gap: int) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", gap)
	parent.add_child(column)
	return column

func _reflow_columns(parent: Control) -> BoxContainer:
	var columns := BoxContainer.new()
	columns.vertical = true
	parent.add_child(columns)
	return columns

func _row(parent: Control, gap: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", gap)
	parent.add_child(row)
	return row
