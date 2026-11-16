extends RefCounted
## Art for the match HUD. Buttons keep their native text, focus and input.

const TABLE_THEME := preload("res://modules/games/mahjong/guiyang/mahjong_table_theme.gd")
const RURAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_theme.gd")
const NINE_PATCH := preload("res://modules/foundation/ui/aspect_nine_patch_style.gd")
const ART := "res://modules/games/mahjong/guiyang/assets/ui/jade_hud/"
const RICE_HUD := "res://modules/games/mahjong/guiyang/assets/ui/rice_field_hud/"
const TOOL := preload(RICE_HUD + "walnut.png")
const SEAT := preload(RICE_HUD + "seat_cream.png")
const CHIP := preload(RICE_HUD + "walnut_badge.png")
const ONLINE := preload(RICE_HUD + "online.png")
const WIND := preload(ART + "wind.svg")
const WIND_ACTIVE := preload(ART + "wind_active.svg")
const PORTRAIT := preload(RICE_HUD + "avatar_ring.png")
const PORTRAITS := [
	preload(RICE_HUD + "portrait_self.png"),
	preload(RICE_HUD + "portrait_right.png"),
	preload(RICE_HUD + "portrait_far.png"),
	preload(RICE_HUD + "portrait_left.png"),
]
const SEAT_FOLIAGE := preload(ART + "seat_foliage.svg")
const FOOTER := preload(ART + "footer_trim.svg")
const COMPASS := preload(ART + "compass.svg")
const SOCIAL := preload(RICE_HUD + "social.png")
const TASSEL := preload(ART + "brand_tassel.svg")
const REACTION_FINISH := {
	"chi": preload(RICE_HUD + "action_peng.png"),
	"peng": preload(RICE_HUD + "action_peng.png"),
	"gang": preload(RICE_HUD + "action_gang.png"),
	"hu": preload(RICE_HUD + "action_hu.png"),
	"pass": preload(RICE_HUD + "action_pass.png"),
	"play": preload(RICE_HUD + "action_play.png"),
}
const ICONS := {
	"rules": preload(ART + "icon_rules.svg"),
	"settings": preload(ART + "icon_settings.svg"),
	"leave": preload("res://modules/games/mahjong/guiyang/assets/ui/rural_modal/icon_back.svg"),
	"chat": preload(ART + "icon_chat.svg"),
	"emote": preload(ART + "icon_emote.svg"),
	"mic": preload(ART + "icon_mic.svg"),
	"muted": preload(ART + "icon_muted.svg"),
}
const BUTTON_TINTS := {
	"normal": Color.WHITE,
	"hover": Color(1.12, 1.10, 1.04),
	"pressed": Color("#cdbb9f"),
	"hover_pressed": Color("#cdbb9f"),
	"disabled": Color("#a29684"),
}


static func _slice(texture: Texture2D, cap := 0.0) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = texture
	box.texture_margin_left = cap
	box.texture_margin_right = cap
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		box.set_content_margin(side, 0)
	return box


static func lacquer(button: Button, action: String = "") -> void:
	var finish: Texture2D = REACTION_FINISH.get(action, TOOL)
	_button_skin(button, finish, false)
	var font := FontVariation.new()
	font.base_font = RURAL.title_font()
	font.variation_embolden = 0.48
	button.add_theme_font_override("font", font)


static func _button_skin(button: Button, texture: Texture2D, circular: bool) -> void:
	var face_tint := Color("#a16f4e") if circular else Color.WHITE
	for state in BUTTON_TINTS:
		var box := NINE_PATCH.new()
		box.texture = texture
		box.preserve_aspect = circular
		var extent := texture.get_size()
		var cap := minf(extent.x * 0.40, extent.y * 0.75)
		box.source_margins = Vector4(cap, extent.y * 0.47, cap, extent.y * 0.47)
		box.modulate_color = BUTTON_TINTS[state] * face_tint
		box.set_content_margin(SIDE_LEFT, 5 if circular else 11)
		box.set_content_margin(SIDE_RIGHT, 5 if circular else 11)
		button.add_theme_stylebox_override(state, box)
	var focus := RURAL.frame(Color.TRANSPARENT, Color("#fff4ca"), 24, 2)
	focus.shadow_size = 0
	button.add_theme_stylebox_override("focus", focus)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, TABLE_THEME.CREAM)
	button.add_theme_color_override("font_disabled_color", Color("#d2c4ad"))
	button.add_theme_color_override("font_outline_color", Color("#201307dd"))
	button.add_theme_constant_override("outline_size", 2)


static func tool(button: Button, kind: String) -> void:
	lacquer(button)
	button.icon = icon(kind)
	button.add_theme_constant_override("icon_max_width", 20)
	button.add_theme_constant_override("h_separation", 6)
	button.expand_icon = true


static func social(button: Button, kind: String) -> void:
	_button_skin(button, SOCIAL, true)
	button.icon = icon(kind)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 28)
	button.add_theme_constant_override("outline_size", 0)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		button.add_theme_color_override(state, Color.TRANSPARENT)


static func microphone(button: Button) -> void:
	social(button, "mic")


static func room() -> StyleBox:
	# The approved walnut artwork is 352 x 112. Preserve the complete rounded
	# gold caps and bevel height; only the undecorated middle changes width.
	var box := NINE_PATCH.new()
	box.texture = TOOL
	box.source_margins = Vector4(62, 22, 62, 22)
	box.set_content_margin(SIDE_LEFT, 32)
	box.set_content_margin(SIDE_RIGHT, 32)
	box.set_content_margin(SIDE_TOP, 5)
	box.set_content_margin(SIDE_BOTTOM, 5)
	return box


static func fit_room_heading(control: Label, preferred_size := 0) -> void:
	if preferred_size > 0:
		control.set_meta("room_heading_preferred_size", preferred_size)
	if control.size.x <= 0 or control.size.y <= 0:
		return
	var surface := control.get_theme_stylebox("normal")
	var ratio := minf(control.size.y / TOOL.get_height(), control.size.x / 125.0)
	var horizontal := 62.0 * ratio + clampf(control.size.y * 0.12, 3.0, 8.0)
	var vertical := clampf(control.size.y * 0.10, 3.0, 7.0)
	for side in [SIDE_LEFT, SIDE_RIGHT]: surface.set_content_margin(side, horizontal)
	for side in [SIDE_TOP, SIDE_BOTTOM]: surface.set_content_margin(side, vertical)
	var outline := float(control.get_theme_constant("outline_size")) * 2.0
	var available := control.size - surface.get_minimum_size() - Vector2.ONE * (outline + 2.0)
	var font := control.get_theme_font("font")
	var desired := int(control.get_meta("room_heading_preferred_size", control.get_theme_font_size("font_size")))
	while desired > 12 and (font.get_string_size(control.text, HORIZONTAL_ALIGNMENT_LEFT, -1, desired).x > available.x or font.get_height(desired) > available.y):
		desired -= 1
	if desired != control.get_theme_font_size("font_size"):
		control.add_theme_font_size_override("font_size", desired)
	control.autowrap_mode = TextServer.AUTOWRAP_OFF
	control.tooltip_text = control.text


static func seat(active: bool = false) -> StyleBoxTexture:
	var box := _slice(SEAT)
	box.modulate_color = Color.WHITE if active else Color("#fff4dd")
	return box


static func seat_name() -> StyleBoxTexture:
	return _slice(TOOL)


static func presence_dot(online: bool = true) -> StyleBoxTexture:
	var box := _slice(ONLINE if online else SOCIAL)
	box.modulate_color = Color.WHITE if online else Color("#a09682")
	return box


static func wall() -> StyleBoxTexture:
	return _slice(CHIP)


static func count() -> StyleBoxTexture:
	return _slice(CHIP)


static func wind(active: bool = false) -> StyleBoxTexture:
	return _slice(WIND_ACTIVE if active else WIND)


static func icon(kind: String) -> Texture2D:
	return ICONS.get(kind)


static func portrait_ring() -> Texture2D:
	return PORTRAIT


static func player_portrait(relative: int) -> Texture2D:
	return PORTRAITS[posmod(relative, PORTRAITS.size())]


static func seat_foliage() -> Texture2D:
	return SEAT_FOLIAGE


static func footer() -> Texture2D:
	return FOOTER


static func stool() -> Texture2D:
	return RURAL.BRAND


static func compass() -> Texture2D:
	return COMPASS


static func tassel() -> Texture2D:
	return TASSEL
