extends Panel
## Presents immediate preferences. Owners apply and store their values.

const MODAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_modal.gd")
const TABS := ["基础设置", "音效设置", "画面设置", "玩法规则"]
const DESIGN_SIZE := Vector2(714, 530)
const STACKED_TABS_WIDTH := 560.0

var _tab_buttons: Array[Button] = []
var _pages: Array[VBoxContainer] = []
var _quality_buttons: Array[Button] = []
var _quality_row: BoxContainer
var _navigation: GridContainer
var _scroll: ScrollContainer
var _music: Button
var _effects: Button
var _coach: Button
var _voice: OptionButton
var _rules: Label
var _dismiss: Button
var _done: Button
var _active_quality := -1
var _close: Callable


func setup(close: Callable, set_music: Callable, set_effects: Callable, set_quality: Callable,
		voice: OptionButton, set_coach := Callable()) -> void:
	name = "MahjongToolPanel_settings"
	mouse_filter = Control.MOUSE_FILTER_STOP
	_close = close
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var paper := MODAL.village_panel(self, Vector4(29, 24, 29, 24))
	paper.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 11)
	paper.add_child(layout)

	var header := HBoxContainer.new()
	layout.add_child(header)
	var balance := Control.new()
	balance.custom_minimum_size.x = 47
	balance.mouse_filter = MOUSE_FILTER_IGNORE
	header.add_child(balance)
	var plaque_slot := CenterContainer.new()
	plaque_slot.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(plaque_slot)
	var title := MODAL.village_title(plaque_slot, "游戏设置", paper)
	title.add_theme_font_size_override("font_size", 32)
	_dismiss = Button.new()
	_dismiss.name = "MahjongSettingsClose"
	_dismiss.tooltip_text = "关闭游戏设置"
	_dismiss.accessibility_name = "关闭游戏设置"
	_dismiss.custom_minimum_size = Vector2(47, 47)
	_dismiss.size_flags_vertical = SIZE_SHRINK_CENTER
	header.add_child(_dismiss)
	MODAL.close_button(_dismiss)
	_dismiss.pressed.connect(close)

	_navigation = GridContainer.new()
	_navigation.name = "MahjongSettingsNavigation"
	_navigation.columns = TABS.size()
	_navigation.add_theme_constant_override("h_separation", 8)
	_navigation.add_theme_constant_override("v_separation", 7)
	layout.add_child(_navigation)
	var categories := ButtonGroup.new()
	for index in range(TABS.size()):
		var tab := Button.new()
		tab.name = "MahjongSettingsTab%d" % index
		tab.text = TABS[index]
		tab.toggle_mode = true
		tab.button_group = categories
		tab.custom_minimum_size.y = 44
		tab.size_flags_horizontal = SIZE_EXPAND_FILL
		_navigation.add_child(tab)
		_tab_buttons.append(tab)
		tab.pressed.connect(_show_tab.bind(index))

	var section := PanelContainer.new()
	section.name = "MahjongSettingsSection"
	section.size_flags_vertical = SIZE_EXPAND_FILL
	section.add_theme_stylebox_override("panel", MODAL.section())
	layout.add_child(section)
	_scroll = ScrollContainer.new()
	_scroll.name = "MahjongSettingsPages"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	section.add_child(_scroll)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = SIZE_EXPAND_FILL
	_scroll.add_child(pages)
	for category in TABS:
		var page := VBoxContainer.new()
		page.name = category
		page.add_theme_constant_override("separation", 9)
		pages.add_child(page)
		_pages.append(page)

	if set_coach.is_valid():
		_coach = _toggle(_pages[0], "向听 / 进张标签", "MahjongCoachToggle", set_coach)
		_help(_pages[0], "手牌下方显示向听数和有效进张数，最佳打牌由绿到黄排列。只按本人手牌及公开牌计算。")

	_music = _toggle(_pages[1], "背景音乐", "MahjongMusicToggle", set_music)
	_effects = _toggle(_pages[1], "牌声与语音", "MahjongEffectsToggle", set_effects)
	if voice != null:
		_voice = voice
		var voices := _row(_pages[1], "报牌嗓音")
		_voice.fit_to_longest_item = false
		_voice.custom_minimum_size.x = 144
		MODAL.village_button(_voice)
		voices.add_child(_voice)
	_help(_pages[1], "牌声与语音包括打牌、碰杠胡和牌桌语音。")

	_quality_row = _row(_pages[2], "画质档位")
	var tiers := HBoxContainer.new()
	tiers.size_flags_horizontal = SIZE_EXPAND_FILL
	tiers.add_theme_constant_override("separation", 7)
	_quality_row.add_child(tiers)
	var tier_group := ButtonGroup.new()
	for index in range(3):
		var tier := Button.new()
		tier.name = "MahjongQuality%d" % index
		tier.text = ["省电", "均衡", "高清"][index]
		tier.toggle_mode = true
		tier.button_group = tier_group
		tier.custom_minimum_size.y = 44
		tier.size_flags_horizontal = SIZE_EXPAND_FILL
		tier.size_flags_vertical = SIZE_SHRINK_CENTER
		tiers.add_child(tier)
		_quality_buttons.append(tier)
		tier.pressed.connect(set_quality.bind(index))
	_help(_pages[2], "画质档位调整渲染精度、抗锯齿和阴影。")

	_rules = _label(_pages[3], "")
	_rules.name = "MahjongSettingsRulesCopy"
	_rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rules.add_theme_constant_override("line_spacing", 8)

	var footer := CenterContainer.new()
	layout.add_child(footer)
	_done = Button.new()
	_done.name = "MahjongSettingsDone"
	_done.text = "完成"
	_done.tooltip_text = "修改即时保存"
	_done.custom_minimum_size = Vector2(210, 52)
	MODAL.village_button(_done, true)
	_done.add_theme_font_size_override("font_size", 24)
	footer.add_child(_done)
	_done.pressed.connect(close)
	_show_tab(0)
	_dismiss.grab_focus()


func fit(bounds: Rect2) -> void:
	var width := minf(DESIGN_SIZE.x, bounds.size.x)
	var ratio := DESIGN_SIZE.aspect()
	if width >= STACKED_TABS_WIDTH:
		width = minf(width, maxf(STACKED_TABS_WIDTH, bounds.size.y * ratio))
	var stacked := width < STACKED_TABS_WIDTH
	var height := maxf(width / ratio, 450.0 if stacked else 340.0)
	size = Vector2(width, minf(height, bounds.size.y))
	position = bounds.get_center() - size * 0.5
	if _navigation != null:
		_navigation.columns = 2 if stacked else TABS.size()
		_quality_row.vertical = stacked


func _input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel", false):
		if _voice != null and _voice.get_popup().visible:
			return
		get_viewport().set_input_as_handled()
		_close.call()


func sync(music: bool, effects: bool, quality: int, voice_index: int, rules: String, coach_enabled := true) -> void:
	_music.set_pressed_no_signal(music)
	_effects.set_pressed_no_signal(effects)
	if _coach != null:
		_coach.set_pressed_no_signal(coach_enabled)
	if _active_quality != quality:
		_active_quality = quality
		for index in range(_quality_buttons.size()):
			var tier := _quality_buttons[index]
			tier.set_pressed_no_signal(index == quality)
			MODAL.village_button(tier, index == quality)
			for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
				var box := tier.get_theme_stylebox(state)
				box.set_content_margin(SIDE_LEFT, 5)
				box.set_content_margin(SIDE_RIGHT, 5)
	if _voice != null and voice_index >= 0 and _voice.selected != voice_index:
		_voice.select(voice_index)
	var readable := PackedStringArray()
	for line in rules.split("\n", false):
		readable.append("•  " + line.strip_edges())
	var rules_copy := "\n".join(readable)
	if _rules.text != rules_copy:
		_rules.text = rules_copy


func _show_tab(index: int) -> void:
	for page_index in range(_pages.size()):
		var active := page_index == index
		_tab_buttons[page_index].set_pressed_no_signal(active)
		MODAL.village_button(_tab_buttons[page_index], active)
		_pages[page_index].visible = active
	var controls: Array[Control] = [_dismiss]
	for tab in _tab_buttons:
		controls.append(tab)
	for control in [_coach, _music, _effects, _voice]:
		if is_instance_valid(control) and control.is_visible_in_tree():
			controls.append(control)
	for tier in _quality_buttons:
		if tier.is_visible_in_tree():
			controls.append(tier)
	controls.append(_done)
	for control_index in range(controls.size()):
		var control := controls[control_index]
		control.focus_next = control.get_path_to(controls[(control_index + 1) % controls.size()])
		control.focus_previous = control.get_path_to(controls[posmod(control_index - 1, controls.size())])
	_scroll.scroll_vertical = 0


func _label(parent: Container, value: String) -> Label:
	var control := Label.new()
	control.text = value
	control.mouse_filter = MOUSE_FILTER_IGNORE
	MODAL.label(control)
	parent.add_child(control)
	return control


func _help(parent: Container, value: String) -> void:
	var control := _label(parent, value)
	MODAL.label(control, "muted")
	control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _row(parent: Container, title: String) -> BoxContainer:
	var line := PanelContainer.new()
	var background := MODAL.list_row()
	background.set_content_margin(SIDE_LEFT, 13.0)
	background.set_content_margin(SIDE_RIGHT, 13.0)
	line.add_theme_stylebox_override("panel", background)
	line.custom_minimum_size.y = 56
	parent.add_child(line)
	var row := BoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	line.add_child(row)
	var description := _label(row, title)
	description.size_flags_horizontal = SIZE_EXPAND_FILL
	description.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return row


func _toggle(parent: Container, title: String, node_name: String, setter: Callable) -> Button:
	var switch := Button.new()
	switch.name = node_name
	switch.tooltip_text = title
	switch.accessibility_name = title
	switch.toggle_mode = true
	switch.custom_minimum_size = Vector2(78, 42)
	switch.size_flags_vertical = SIZE_SHRINK_CENTER
	MODAL.toggle(switch)
	_row(parent, title).add_child(switch)
	switch.toggled.connect(setter)
	return switch
