extends Control
## Draws the recommendation and one compact read-only label for one tile.

const SHANTEN_COLORS := [
	Color("#59c989"), # 0: green
	Color("#afd254"), # 1: yellow-green
	Color("#f1cc61"), # 2: yellow
	Color("#f29c45"), # 3: orange
	Color("#c84242"), # 4 and above: red
]
const RANKED_TEXT := Color("#17291e")
const UNAVAILABLE := Color("#56585e")
const RECOMMENDED := Color("#e8bd62")
const HIGH_RISK := Color("#d85b51")

var badge_rect := Rect2()
var text := "—"
var badge_color := UNAVAILABLE
var text_color := Color.WHITE
var recommended := false
var high_risk := false
var selected := false
var shanten_value := -1
var ukeire_value := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE


func set_efficiency(shanten: int, ukeire_count: int, _rank: int, _last_rank: int) -> void:
	if shanten < 0 or ukeire_count < 0:
		set_available(false)
		return
	shanten_value = shanten
	ukeire_value = ukeire_count
	text = "%d·%d" % [shanten, ukeire_count]
	# Background expresses distance to a complete hand. Recommendation rank
	# remains an independent outline, never a different meaning for this color.
	badge_color = SHANTEN_COLORS[mini(shanten, 4)]
	text_color = Color.WHITE if shanten >= 4 else RANKED_TEXT
	queue_redraw()


func set_available(available: bool) -> void:
	if not available:
		shanten_value = -1
		ukeire_value = -1
		text = "—"
		badge_color = UNAVAILABLE
		text_color = Color.WHITE
		queue_redraw()


func set_waiting(_waiting: bool) -> void:
	if shanten_value < 0:
		# Compatibility for older callers: never replace real values with "待".
		text = "—"
		queue_redraw()


func set_risk_level(level: String, verified: bool) -> void:
	high_risk = verified and level == "high"
	queue_redraw()


func set_recommended(is_best: bool) -> void:
	recommended = is_best
	queue_redraw()


func set_selected(is_selected: bool) -> void:
	selected = is_selected
	queue_redraw()


func _draw() -> void:
	if not badge_rect.has_area():
		return
	var font := get_theme_default_font()
	var font_size := clampi(roundi(badge_rect.size.y - 12.0), 12, 19)
	var fill := StyleBoxFlat.new()
	fill.bg_color = badge_color
	fill.set_corner_radius_all(5)
	if recommended:
		# Recommendation belongs to the label below the tile. Keep the entire
		# tile free of 2D rectangles; its own PBR material shows selection.
		fill.set_border_width_all(1)
		fill.border_color = RECOMMENDED
	draw_style_box(fill, badge_rect)
	if shanten_value >= 0 and badge_rect.size.x >= 44.0 and badge_rect.size.y >= 28.0:
		var heading_size := 9
		var half_width := badge_rect.size.x * 0.5
		for column in range(2):
			var center_x := badge_rect.position.x + half_width * (column + 0.5)
			var heading := "向听" if column == 0 else "进张"
			var value := str(shanten_value if column == 0 else ukeire_value)
			var heading_x := center_x - font.get_string_size(heading, HORIZONTAL_ALIGNMENT_LEFT, -1, heading_size).x * 0.5
			draw_string(font, Vector2(heading_x, badge_rect.position.y + 10), heading, HORIZONTAL_ALIGNMENT_LEFT, -1, heading_size, text_color)
			var number_size := font_size
			while number_size > 10 and font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, number_size).x > half_width - 4:
				number_size -= 1
			var value_x := center_x - font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, number_size).x * 0.5
			draw_string(font, Vector2(value_x, badge_rect.end.y - 3), value, HORIZONTAL_ALIGNMENT_LEFT, -1, number_size, text_color)
	else:
		while font_size > 10 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > badge_rect.size.x - 4:
			font_size -= 1
		_draw_compact(font, font_size)
	if high_risk:
		draw_circle(Vector2(size.x - 6.0, 6.0), 3.0, HIGH_RISK, true, -1.0, true)


func _draw_compact(font: Font, font_size: int) -> void:
	var line := badge_rect.get_center()
	line.y += (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	line.x -= font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x * 0.5
	draw_string(font, line, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, text_color)
