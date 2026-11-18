extends RefCounted
## Cropped, unlettered controls from the supplied settlement artwork.

const DIR := "res://modules/games/mahjong/guiyang/assets/ui/settlement/"
const HEADER := preload(DIR + "village_header.png")
const FRAME := preload(DIR + "ledger_frame.png")
const WINNER := preload(DIR + "winner_row.png")
const CROWN := preload(DIR + "win_crown.png")
const EGG := preload(DIR + "egg.png")
const PLAQUE := preload(DIR + "section_plaque.png")
const FAN_PLAQUE := preload(DIR + "fan_plaque.png")
const SCORE_PLAQUE := preload(DIR + "score_plaque.png")
const BRUSH := preload(DIR + "total_brush.png")
const FINISHES := [preload(DIR + "action_honey.png"), preload(DIR + "action_leaf.png"), preload(DIR + "action_cream.png")]
const ICONS := [preload(DIR + "again.png"), preload(DIR + "share.png"), preload(DIR + "home.png")]
const PATCH := preload("res://modules/foundation/ui/aspect_nine_patch_style.gd")
const FONT := preload("res://modules/foundation/ui/fonts/NotoSansCJKsc-Bold.otf")
const KAI := preload("res://modules/games/mahjong/guiyang/assets/ui/fonts/FandolKai-Regular.otf")
const INK := Color("#45230f")
const MUTED := Color("#805537")
const GAIN := Color("#20711a")
const LOSS := Color("#af2b18")

static func label(parent: Control, value: String, font_size: int, color := INK, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var node := Label.new()
	node.text = value
	node.tooltip_text = value
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.horizontal_alignment = align
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	node.add_theme_font_override("font", FONT)
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	parent.add_child(node)
	return node

static func picture(parent: Control, texture: Texture2D) -> TextureRect:
	var image := TextureRect.new()
	image.texture = texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(image)
	return image

static func patch(texture: Texture2D, margins: Vector4) -> StyleBox:
	var style := PATCH.new()
	style.texture = texture
	style.source_margins = margins
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: style.set_content_margin(side, 0)
	return style

static func surface(fill: Color, border := Color.TRANSPARENT, radius := 12, stroke := 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_corner_radius_all(radius)
	box.set_border_width_all(stroke)
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: box.set_content_margin(side, 0)
	return box

static func action(parent: Control, id: String, caption: String, index: int, callback: Callable) -> Button:
	var button := Button.new()
	button.name = id
	button.text = caption
	button.icon = ICONS[index]
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.accessibility_name = caption
	button.add_theme_font_override("font", FONT)
	var ink := Color("#fff9dc") if index == 1 else Color("#542601")
	for state in [&"font_color", &"font_focus_color", &"font_pressed_color", &"font_hover_color", &"font_hover_pressed_color"]:
		button.add_theme_color_override(state, ink)
	for state in [&"normal",&"hover",&"pressed",&"hover_pressed",&"disabled"]:
		var box := patch(FINISHES[index], Vector4(44, 32, 44, 32))
		box.modulate_color = Color("#e3c69b") if state in [&"pressed",&"hover_pressed"] else Color(1.07,1.05,1.01) if state == &"hover" else Color.WHITE
		button.add_theme_stylebox_override(state, box)
	button.add_theme_stylebox_override("focus", surface(Color.TRANSPARENT, Color("#fff1a5"), 32, 2))
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
