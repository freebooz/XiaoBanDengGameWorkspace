extends RefCounted
## Shared visual theme for the Mahjong settings and settlement surfaces.

const RURAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_theme.gd")
const NINE_PATCH := preload("res://modules/foundation/ui/aspect_nine_patch_style.gd")
const PANEL_SURFACE := preload("res://modules/foundation/ui/nine_patch_panel_style.gd")
const OVERLAPPING_TITLE := preload("res://modules/foundation/ui/overlapping_panel_title.gd")
const BASE := "res://modules/games/mahjong/guiyang/assets/ui/rural_modal/"
const PAPER_CARD := preload(BASE + "warm_kraft_card.png")
const SECTION := preload(BASE + "section.svg")
const CLOSE := preload("res://modules/games/mahjong/guiyang/assets/ui/harvest/round_button.png")
const HUD_ICON_EXTENT := 56.0
const ICON_VISUAL_RATIO := 0.90
const NAV := preload(BASE + "nav.svg")
const NAV_SELECTED := preload(BASE + "nav_selected.svg")
const TOGGLE_ON := preload(BASE + "toggle_on.png")
const TOGGLE_OFF := preload(BASE + "toggle_off.png")
const THUMB := preload(BASE + "thumb.svg")
const RESULT_WIN := preload(BASE + "result_badge.svg")
const RESULT_NEUTRAL := preload(BASE + "result_neutral.svg")
const ART := {
	"landscape": preload(BASE + "landscape.png"),
	"bamboo": preload(BASE + "bamboo.png"),
	"pottery": preload(BASE + "pottery.svg"),
	"stool": preload(BASE + "stool.png"),
	"plaque": preload(BASE + "plaque.png"),
}
const BUTTONS := {
	"primary": preload(BASE + "primary.png"),
	"secondary": preload(BASE + "secondary.png"),
	"auxiliary": preload(BASE + "auxiliary.png"),
}
const ICONS := {
	"close": preload(BASE + "icon_close.svg"),
	"settings": preload(BASE + "icon_settings.svg"),
	"audio": preload(BASE + "icon_audio.svg"),
	"display": preload(BASE + "icon_display.svg"),
	"rules": preload(BASE + "icon_rules.svg"),
	"back": preload(BASE + "icon_back.svg"),
	"refresh": preload(BASE + "icon_refresh.svg"),
}
const INK := Color("#462818")
const CREAM := Color("#fff4dd")
const MUTED := Color("#795841")
const SUCCESS := Color("#286a25")
const NEGATIVE := Color("#a13b22")
const FRAME_TEXTURE_MARGINS := Vector4(40, 40, 40, 40)
const FRAME_CONTENT_MARGINS := Vector4(28, 28, 28, 28)
const BUTTON_TEXTURE_MARGINS := Vector4(38, 0, 38, 0)
const NAV_TEXTURE_MARGINS := Vector4(14, 13, 14, 13)
const SECTION_TEXTURE_MARGINS := Vector4(19, 19, 19, 19)
const BUTTON_INSET := Vector4(14, 5, 14, 8)
const VILLAGE := "res://modules/games/mahjong/guiyang/assets/ui/harvest/"
const VILLAGE_BRAND := preload("res://modules/games/mahjong/guiyang/assets/ui/login_rural/sign.png")
const VILLAGE_PORTRAIT := preload(VILLAGE + "village_portrait.png")
const VILLAGE_LANDSCAPE := preload(VILLAGE + "village_landscape.png")
const VILLAGE_GUEST := preload(VILLAGE + "guest_portrait.png")
const VILLAGE_TILES := preload(VILLAGE + "start_game_tiles.png")
const VILLAGE_PAPER := preload(VILLAGE + "paper.png")
const VILLAGE_FRAME := preload(VILLAGE + "bamboo_frame_approved.png")
const VILLAGE_GOLD := preload(VILLAGE + "gold_button.png")
const VILLAGE_CREAM := preload(VILLAGE + "cream_capsule.png")
const VILLAGE_TITLE := preload(VILLAGE + "wood_title.png")
const VILLAGE_FLOWERS := preload(VILLAGE + "corner_flowers.png")
const VILLAGE_FONT := preload("res://modules/foundation/ui/fonts/NotoSansCJKsc-Bold.otf")
const LOGIN_BACKDROP := preload(VILLAGE + "login_backdrop.png")
const LOGIN_TITLE := preload(VILLAGE + "login_title.png")
const LOGIN_BUTTONS := {
	"orange": preload(VILLAGE + "login_orange.png"),
	"green": preload(VILLAGE + "login_green.png"),
	"blue": preload(VILLAGE + "login_blue.png"),
}
const VILLAGE_LEAVES := preload("res://modules/games/mahjong/guiyang/assets/ui/lobby_rural/room_leaves.svg")
static func village_font() -> Font:
	return VILLAGE_FONT


class VillagePanel extends PanelContainer:
	var surface: StyleBox
	var content: StyleBoxEmpty
	var requested_insets := Vector4.ZERO
	var _fitting_border := false
	var _border_refit_queued := false

	func fit_border() -> void:
		# StyleBox changes can synchronously raise this PanelContainer's minimum
		# size and emit resized before the other three margins have been updated.
		# Finish the complete inset update, then converge once on the next pass.
		if _fitting_border:
			if not _border_refit_queued:
				_border_refit_queued = true
				_refit_border.call_deferred()
			return
		_fitting_border = true
		if surface != null:
			var edge := float(surface.call("border_center_offset", size))
			set_meta("title_border_offset", edge)
			# Reserve the rendered rim plus breathing room. Narrow phones keep a
			# compact inset; large panels gain space without scaling their text.
			var breathing := 12.0 if size.x < 520 else 16.0 if size.x < 900 else 20.0
			var clearances := Vector4(maxf(26, edge + breathing), maxf(34, edge + breathing + 4), maxf(26, edge + breathing), maxf(36, edge + breathing + 6))
			if content != null:
				for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
					var inset := maxf(clearances[side], requested_insets[side])
					if not is_equal_approx(content.get_content_margin(side), inset):
						content.set_content_margin(side, inset)
		_fitting_border = false
		queue_redraw()

	func _refit_border() -> void:
		_border_refit_queued = false
		if is_inside_tree():
			fit_border()

	func _draw() -> void:
		if surface != null:
			draw_style_box(surface, Rect2(Vector2.ZERO, size))


static func village_header(parent: Control, back_name: String, action: Callable, brand_name := "MahjongVillageBrand", draw_brand := true) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "MahjongVillageHeader"
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var brand := TextureRect.new()
	brand.name = brand_name
	if draw_brand:
		brand.texture = VILLAGE_BRAND
	brand.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	brand.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(brand)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var back := Button.new()
	back.name = back_name
	back.tooltip_text = "返回上一级"
	back.accessibility_name = "返回"
	back.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_button(back)
	back.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	back.icon = icon("back")
	back.pressed.connect(action)
	row.add_child(back)
	return row


static func fit_village_header(header: HBoxContainer, width: float, height: float) -> void:
	var logo := header.get_child(0) as TextureRect
	var back := header.get_child(-1) as Button
	var span := minf(width * 0.46, clampf(height * 0.27, 120.0, 420.0))
	logo.custom_minimum_size = Vector2(span, span / VILLAGE_BRAND.get_size().aspect())
	size_icon_button(back, header)


static func village_panel(parent: Control, insets := Vector4(20, 18, 20, 18)) -> PanelContainer:
	var panel := VillagePanel.new()
	panel.set_meta("title_border_offset", 24.0)
	panel.name = "MahjongVillagePanel"
	var content := StyleBoxEmpty.new()
	panel.content = content
	panel.requested_insets = insets
	var rail_clearance := Vector4(26, 34, 26, 36)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		content.set_content_margin(side, maxf(rail_clearance[side], insets[side]))
	panel.add_theme_stylebox_override("panel", content)
	panel.surface = paper_frame(Vector4.ZERO)
	parent.add_child(panel)
	panel.resized.connect(panel.fit_border)
	panel.fit_border()
	return panel


static func village_title(parent: Control, title: String, frame: PanelContainer = null) -> Label:
	var plate := PanelContainer.new()
	plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	plate.custom_minimum_size.y = 61
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var surface := wood_plaque()
	surface.set_content_margin(SIDE_LEFT, 39)
	surface.set_content_margin(SIDE_RIGHT, 39)
	plate.add_theme_stylebox_override("panel", surface)
	if frame != null:
		var slot := OVERLAPPING_TITLE.new()
		parent.add_child(slot)
		slot.setup(plate, frame)
	else:
		parent.add_child(plate)
	var text := Label.new()
	text.text = title
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label(text, "title")
	text.add_theme_font_override("font", village_font())
	text.add_theme_font_size_override("font_size", 35)
	text.add_theme_color_override("font_color", CREAM)
	text.add_theme_color_override("font_shadow_color", Color("#7a300f"))
	text.add_theme_constant_override("shadow_offset_y", 2)
	text.add_theme_color_override("font_outline_color", Color("#77380e"))
	text.add_theme_constant_override("outline_size", 4)
	plate.add_child(text)
	return text


static func village_button(control: Button, primary := false) -> void:
	button(control, "auxiliary")
	control.add_theme_font_override("font", village_font())
	if not primary:
		_skin(control, VILLAGE_CREAM, Vector4(52, 0, 52, 0), BUTTON_INSET)
		return
	_skin(control, VILLAGE_GOLD, Vector4.ZERO, Vector4(22, 6, 22, 9))
	_ink_states(control, CREAM, CREAM)
	control.add_theme_color_override("font_outline_color", Color("#85420b"))
	control.add_theme_constant_override("outline_size", 3)
	control.add_theme_color_override("font_shadow_color", Color("#8b3d08"))
	control.add_theme_constant_override("shadow_offset_y", 2)


static func login_button(control: Button, role := "orange") -> void:
	village_button(control, true)
	_skin(control, LOGIN_BUTTONS.get(role, LOGIN_BUTTONS["orange"]), Vector4.ZERO, Vector4(24, 6, 24, 9))


static func decorate(panel: Panel, landscape := true) -> void:
	panel.add_theme_stylebox_override("panel", paper_frame())
	if landscape:
		var scene := ornament(panel, "landscape")
		scene.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		scene.offset_left = 27
		scene.offset_right = -27
		scene.offset_top = -173
		scene.offset_bottom = -26
		scene.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		scene.modulate.a = 0.52


static func heading(parent: Control, title: String) -> Control:
	var plate := Panel.new()
	plate.name = "RuralWoodHeading"
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.custom_minimum_size = Vector2(260, 70)
	plate.add_theme_stylebox_override("panel", wood_plaque())
	parent.add_child(plate)
	var brand := ornament(plate, "stool")
	brand.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	brand.anchor_left = 0.12
	brand.anchor_right = 0.31
	brand.offset_top = 3
	brand.offset_bottom = -13
	var text := Label.new()
	text.name = "RuralHeadingText"
	text.text = title
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label(text, "title")
	text.add_theme_font_size_override("font_size", 34)
	plate.add_child(text)
	text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text.anchor_left = 0.31
	text.anchor_right = 0.89
	text.offset_bottom = -7
	return plate


static func close_button(control: Button) -> void:
	_skin(control, CLOSE, Vector4.ZERO, Vector4.ZERO)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	control.icon = icon("close")
	control.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	control.expand_icon = true
	size_icon_button(control, control)
	_ink_states(control, Color.TRANSPARENT, Color.TRANSPARENT)


static func icon_button(control: Button, glyph: Texture2D, description: String) -> void:
	control.text = ""
	close_button(control)
	control.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	control.icon = glyph
	control.tooltip_text = description
	control.accessibility_name = description


static func icon_button_extent(owner: Control) -> float:
	return _icon_metrics(owner).y


static func _icon_metrics(owner: Control) -> Vector2:
	if not owner.is_inside_tree():
		return Vector2.ONE * HUD_ICON_EXTENT * ICON_VISUAL_RATIO
	var transform := owner.get_global_transform()
	var canvas := owner.get_viewport_transform() * transform
	var pixels_per_unit := maxf(0.01, minf(canvas.x.length(), canvas.y.length()))
	var local_scale := maxf(0.01, minf(transform.x.length(), transform.y.length()))
	var touch := RURAL.touch_extent(owner) / local_scale
	var visual := maxf(HUD_ICON_EXTENT / pixels_per_unit, touch) * ICON_VISUAL_RATIO
	return Vector2(visual, maxf(visual, touch))


static func size_icon_button(control: Button, owner: Control, compact_extent := 0.0) -> float:
	var metrics := _icon_metrics(owner)
	if compact_extent > 0.0:
		metrics = Vector2(compact_extent * ICON_VISUAL_RATIO, compact_extent)
	control.custom_minimum_size = Vector2.ONE * metrics.y
	for state in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
		control.get_theme_stylebox(state).set("aspect_max_extent", metrics.x)
	control.add_theme_constant_override("icon_max_width", maxi(1, roundi(metrics.x * 0.52)))
	control.queue_redraw()
	return metrics.y


static func button(control: Button, role := "secondary") -> void:
	var texture: Texture2D = VILLAGE_GOLD if role == "primary" else VILLAGE_CREAM
	_skin(control, texture, BUTTON_TEXTURE_MARGINS, BUTTON_INSET)
	var ink := CREAM if role == "primary" else INK
	_ink_states(control, ink, ink)
	control.add_theme_font_size_override("font_size", 22)
	if control is OptionButton:
		var menu: PopupMenu = control.get_popup()
		control.add_theme_icon_override("arrow", preload(BASE + "icon_chevron.svg"))
		control.add_theme_constant_override("arrow_margin", 7)
		menu.add_theme_stylebox_override("panel", section())
		menu.add_theme_stylebox_override("hover", list_row(true))
		for state in ["font_color", "font_hover_color", "font_accelerator_color"]:
			menu.add_theme_color_override(state, INK)
		menu.add_theme_color_override("font_disabled_color", MUTED)
		menu.add_theme_constant_override("v_separation", 10)


static func nav(control: Button, icon_name: String) -> void:
	_skin(control, NAV, NAV_TEXTURE_MARGINS, BUTTON_INSET, NAV_SELECTED, Color.WHITE)
	_ink_states(control, CREAM, Color("#593017"))
	control.add_theme_color_override("icon_pressed_color", Color("#814a20"))
	control.add_theme_color_override("icon_hover_pressed_color", Color("#814a20"))
	control.icon = icon(icon_name)
	control.alignment = HORIZONTAL_ALIGNMENT_LEFT
	control.expand_icon = true
	control.add_theme_constant_override("icon_max_width", 24)
	control.add_theme_constant_override("h_separation", 9)
	control.add_theme_font_size_override("font_size", 21)


static func toggle(control: Button) -> void:
	_skin(control, TOGGLE_OFF, Vector4.ZERO, Vector4.ZERO, TOGGLE_ON, Color.WHITE)
	_ink_states(control, Color.TRANSPARENT, Color.TRANSPARENT)
	control.add_theme_constant_override("outline_size", 0)
	control.custom_minimum_size = Vector2(76, 44)


static func slider(control: HSlider) -> void:
	control.add_theme_stylebox_override("slider", _track(Color("#cba673"), Color("#a0744a")))
	control.add_theme_stylebox_override("grabber_area", _track(Color("#57912e"), Color("#3e671f")))
	control.add_theme_stylebox_override("grabber_area_highlight", _track(Color("#6b9b35"), Color("#3e671f")))
	for state in ["grabber", "grabber_highlight", "grabber_disabled"]:
		control.add_theme_icon_override(state, THUMB)
	control.add_theme_constant_override("center_grabber", 1)


static func section() -> StyleBoxTexture:
	return _slice(SECTION, SECTION_TEXTURE_MARGINS, Vector4(21, 20, 21, 20))


static func paper_frame(insets := FRAME_CONTENT_MARGINS) -> StyleBox:
	var surface := PANEL_SURFACE.new()
	surface.paper = VILLAGE_PAPER
	surface.rim = VILLAGE_FRAME
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		# ZERO is explicitly used by VillagePanel's decorative surface; its
		# separate content style owns responsive padding. Other cards keep a
		# readable minimum even when a caller requests a very tight inset.
		var minimum := 14.0 if side == SIDE_LEFT or side == SIDE_RIGHT else 12.0
		surface.set_content_margin(side, 0.0 if insets == Vector4.ZERO else maxf(minimum, insets[side]))
	return surface


static func wood_plaque() -> StyleBox:
	return button_frame(VILLAGE_TITLE, Vector4(22, 6, 22, 9))


static func capsule_frame(insets := Vector4(24, 5, 24, 7)) -> StyleBox:
	return button_frame(VILLAGE_CREAM, insets)


static func button_frame(texture: Texture2D, insets: Vector4, tint := Color.WHITE, margins := Vector4.ZERO) -> StyleBox:
	var box := NINE_PATCH.new()
	box.texture = texture
	box.modulate_color = tint
	var extent := texture.get_size()
	var cap := minf(extent.x * 0.40, extent.y * 0.70)
	box.source_margins = Vector4(maxf(cap, margins.x), extent.y * 0.47, maxf(cap, margins.z), extent.y * 0.47)
	if texture == VILLAGE_GOLD:
		box.source_margins = Vector4(180, 92, 180, 92)
	elif LOGIN_BUTTONS.values().has(texture):
		box.source_margins = Vector4(135, 56, 135, 56)
	elif texture == VILLAGE_CREAM:
		box.source_margins = Vector4(66, 52, 66, 52)
	elif texture == LOGIN_TITLE:
		box.source_margins = Vector4(185, 75, 185, 75)
	elif texture == CLOSE:
		box.source_margins = Vector4(88, 88, 88, 88)
		box.preserve_aspect = true
	elif texture == TOGGLE_ON or texture == TOGGLE_OFF:
		box.preserve_aspect = true
	box.set_content_margin(SIDE_LEFT, insets.x)
	box.set_content_margin(SIDE_TOP, insets.y)
	box.set_content_margin(SIDE_RIGHT, insets.z)
	box.set_content_margin(SIDE_BOTTOM, insets.w)
	return box


static func list_row(local_player := false) -> StyleBoxFlat:
	var fill := Color("#ffe9a9") if local_player else Color("#fff0d5")
	var edge := Color("#d8aa69") if local_player else Color("#e1c59d")
	var style := RURAL.frame(fill, edge, 10, 1)
	style.shadow_size = 0
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, 12 if side == SIDE_LEFT or side == SIDE_RIGHT else 6)
	return style


static func result_badge(outcome := "draw") -> Texture2D:
	return RESULT_WIN if outcome == "win" else RESULT_NEUTRAL


static func label(control: Label, role := "body") -> void:
	var tint: Color = {"title": CREAM, "muted": MUTED, "success": SUCCESS, "negative": NEGATIVE}.get(role, INK)
	control.add_theme_color_override("font_color", tint)
	if role == "title":
		control.add_theme_color_override("font_outline_color", Color("#4d2513"))
		control.add_theme_constant_override("outline_size", 4)


static func icon(kind: String) -> Texture2D:
	return ICONS.get(kind)


static func art(kind: String) -> Texture2D:
	return ART.get(kind)


static func ornament(parent: Control, kind: String) -> TextureRect:
	var layer := TextureRect.new()
	layer.name = "Rural" + kind.capitalize()
	layer.texture = art(kind)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	parent.add_child(layer)
	return layer


static func _slice(texture: Texture2D, margins: Vector4, insets: Vector4, tint := Color.WHITE) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = texture
	box.modulate_color = tint
	box.texture_margin_left = margins.x
	box.texture_margin_top = margins.y
	box.texture_margin_right = margins.z
	box.texture_margin_bottom = margins.w
	box.set_content_margin(SIDE_LEFT, insets.x)
	box.set_content_margin(SIDE_TOP, insets.y)
	box.set_content_margin(SIDE_RIGHT, insets.z)
	box.set_content_margin(SIDE_BOTTOM, insets.w)
	return box


static func _skin(control: Button, normal: Texture2D, margins: Vector4, insets: Vector4, selected: Texture2D = null, press_tint := Color("#ddbf9f")) -> void:
	if selected == null:
		selected = normal
	control.add_theme_stylebox_override("normal", button_frame(normal, insets, Color.WHITE, margins))
	control.add_theme_stylebox_override("hover", button_frame(normal, insets, Color(1.07, 1.05, 1.02), margins))
	control.add_theme_stylebox_override("pressed", button_frame(selected, insets, press_tint, margins))
	control.add_theme_stylebox_override("hover_pressed", button_frame(selected, insets, press_tint, margins))
	control.add_theme_stylebox_override("disabled", button_frame(normal, insets, Color("#bcb0a092"), margins))
	var focus := RURAL.frame(Color.TRANSPARENT, Color("#895327"), 14, 2)
	focus.shadow_size = 0
	control.add_theme_stylebox_override("focus", focus)
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	RURAL.CAPTION.attach(control)


static func _ink_states(control: Button, normal: Color, pressed: Color) -> void:
	for state in ["font_color", "font_hover_color", "font_focus_color"]:
		control.add_theme_color_override(state, normal)
	for state in ["font_pressed_color", "font_hover_pressed_color"]:
		control.add_theme_color_override(state, pressed)
	control.add_theme_color_override("font_disabled_color", Color(normal, normal.a * 0.65))


static func _track(fill: Color, edge: Color) -> StyleBoxFlat:
	var style := RURAL.frame(fill, edge, 7, 1)
	style.shadow_size = 0
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style
