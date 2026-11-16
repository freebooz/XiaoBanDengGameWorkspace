extends RefCounted

const CAPTION := preload("res://modules/games/mahjong/guiyang/mahjong_button_caption.gd")
const NINE_PATCH := preload("res://modules/foundation/ui/aspect_nine_patch_style.gd")
const UI_FONT := preload("res://modules/foundation/ui/fonts/NotoSansCJKsc-Bold.otf")
const SATIN_WOOD := preload("res://modules/games/mahjong/guiyang/assets/ui/series/rural_satin_wood.png")
const BRAND := preload("res://modules/foundation/ui/battle_assets/stool.png")
const MAHJONG_BRAND := preload("res://modules/games/mahjong/guiyang/assets/ui/series/xbd_mahjong_brand.png")
const COURTYARD := preload("res://modules/games/mahjong/guiyang/assets/ui/series/rural_lobby_v2.png")
const INK := Color("#453326")
const CREAM := Color("#fff8ed")
const PAPER := Color("#faf1e4")
const GOLD := Color("#c6a47e")


static func form_control_height(base_height: float, touch_height := 0.0) -> float:
	# The approved artwork defines the height. Accessibility is a lower bound,
	# never an extra multiplier or a share of unused viewport height.
	return maxf(base_height, touch_height)


static func safe_insets(root: Control) -> Vector4i:
	if not OS.has_feature("mobile"): return Vector4i.ZERO
	var window := root.get_window()
	var safe := DisplayServer.get_display_safe_area()
	if not safe.has_area(): return Vector4i.ZERO
	var start := safe.position - window.position
	var end := start + safe.size
	var scale := root.size / Vector2(maxi(1, window.size.x), maxi(1, window.size.y))
	return Vector4i(
		ceili(maxi(0, start.x) * scale.x), ceili(maxi(0, start.y) * scale.y),
		ceili(maxi(0, window.size.x - end.x) * scale.x), ceili(maxi(0, window.size.y - end.y) * scale.y)
	)


static func touch_extent(root: Control) -> float:
	if not OS.has_feature("mobile"): return 0.0
	var window := root.get_window()
	var viewport := window.get_visible_rect().size
	var content_scale := viewport.y / float(maxi(1, window.size.y))
	var pixels := 48.0 * float(DisplayServer.screen_get_dpi()) / 160.0
	return clampf(ceilf(pixels * content_scale), 56.0, maxf(56.0, minf(viewport.x, viewport.y) * 0.15))


static func frame(fill: Color, edge: Color, radius: int = 14, width: int = 2) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	box.shadow_color = Color("#30201641")
	box.shadow_size = 7
	box.shadow_offset = Vector2(0, 3)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box


static func wood_button_style(shade: Color = Color.WHITE) -> StyleBox:
	var box := NINE_PATCH.new()
	box.texture = SATIN_WOOD
	box.region_rect = Rect2(0, 151, 2172, 424)
	box.source_margins = Vector4(210, 194, 210, 194)
	box.modulate_color = shade
	for side in [SIDE_LEFT, SIDE_RIGHT]: box.set_content_margin(side, 8.0)
	for side in [SIDE_TOP, SIDE_BOTTOM]: box.set_content_margin(side, 6.0)
	return box


static func skin_button(button: Button, primary: bool = false) -> void:
	var edge := Color("#cdb495")
	button.add_theme_stylebox_override("normal", wood_button_style() if primary else _ivory_button_style(PAPER, edge, 3))
	button.add_theme_stylebox_override("hover", wood_button_style(Color(1.05, 1.05, 1.05)) if primary else _ivory_button_style(CREAM, Color("#b5916b"), 4))
	var pressed: StyleBox = wood_button_style(Color("#e3c7a6")) if primary else _ivory_button_style(Color("#eee0cd"), edge, 1)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover_pressed", pressed)
	var disabled := _ivory_button_style(Color("#e9dfd3"), Color("#d5c4af"), 0)
	button.add_theme_stylebox_override("disabled", disabled)
	var focus := frame(Color.TRANSPARENT, Color("#817653"), 14)
	focus.shadow_size = 0
	button.add_theme_stylebox_override("focus", focus)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, INK)
	button.add_theme_color_override("font_disabled_color", Color("#74685e"))
	button.add_theme_font_size_override("font_size", 22)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	CAPTION.attach(button)
	if primary:
		var shadow := Panel.new()
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shadow.show_behind_parent = true
		var surface := frame(Color.TRANSPARENT, Color.TRANSPARENT, 48, 0)
		surface.shadow_color = Color("#38271927")
		surface.shadow_size = 9
		surface.shadow_offset = Vector2(0, 4)
		shadow.add_theme_stylebox_override("panel", surface)
		button.add_child(shadow)
		shadow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shadow.offset_left = 3
		shadow.offset_right = -3
		shadow.offset_top = 4
		shadow.offset_bottom = -2
		button.draw.connect(func(): shadow.visible = not button.disabled)


static func _ivory_button_style(fill: Color, edge: Color, depth: int) -> StyleBoxFlat:
	var box := frame(fill, edge, 13, 1)
	box.border_width_bottom = maxi(1, depth)
	box.border_blend = true
	box.shadow_size = depth + 2 if depth > 0 else 0
	box.shadow_offset = Vector2(0, depth)
	for side in [SIDE_LEFT, SIDE_RIGHT]: box.set_content_margin(side, 10.0)
	for side in [SIDE_TOP, SIDE_BOTTOM]: box.set_content_margin(side, 6.0)
	return box


static func title_font() -> Font:
	return UI_FONT


static func seat_portrait(index: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = COURTYARD
	atlas.region = [Rect2(774,442,151,151), Rect2(101,431,155,155), Rect2(320,428,151,151), Rect2(573,441,153,153)][index]
	atlas.filter_clip = true
	return atlas
