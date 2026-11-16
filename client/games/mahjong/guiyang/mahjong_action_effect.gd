extends Control
## Table-center presentation for an action already confirmed by the game.

const THEME := preload("res://modules/games/mahjong/guiyang/mahjong_rural_theme.gd")
const NAMES := {"peng": "碰", "ming_gang": "杠", "an_gang": "杠", "bu_gang": "杠", "gang": "杠", "hu": "胡"}
const DURATIONS := {"碰": 0.88, "杠": 1.04, "胡": 1.22}
const GANG_NAMES := {"ming_gang": "明杠", "an_gang": "暗杠", "bu_gang": "补杠"}
const IVORY := Color("#fff4d4")
const YELLOW := Color("#ffe899")
const GOLD := Color("#ffc35d")
const ORANGE := Color("#ff913e")
const VERMILION := Color("#ec532c")
const INK := Color("#21110d")

static var _glow_texture: GradientTexture2D

var _caption := ""
var _detail := ""
var _font: Font
var _progress := 0.0


func show_action(action: String) -> void:
	_caption = NAMES.get(action, "")
	if _caption.is_empty():
		queue_free()
		return
	_detail = GANG_NAMES.get(action, "")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := FontVariation.new()
	font.base_font = THEME.title_font()
	font.variation_embolden = 1.0
	_font = font
	if _glow_texture == null:
		_glow_texture = _make_glow_texture()
	_update_progress(0.0)
	var animation := create_tween()
	animation.tween_method(_update_progress, 0.0, 1.0, float(DURATIONS[_caption]))
	animation.tween_callback(queue_free)


func _update_progress(progress: float) -> void:
	_progress = progress
	queue_redraw()


func _draw() -> void:
	if _caption.is_empty() or _font == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var reveal := smoothstep(0.0, 0.14, _progress)
	var opacity := reveal * (1.0 - smoothstep(0.62, 1.0, _progress))
	var unit := minf(size.x / 260.0, size.y / 166.0)
	var drift := -5.0 * smoothstep(0.58, 1.0, _progress)
	draw_set_transform(size * 0.5 + Vector2(0, drift * unit), 0.0, Vector2.ONE * unit)
	match _caption:
		"碰":
			_draw_peng(reveal, opacity)
		"杠":
			_draw_gang(reveal, opacity)
		"胡":
			_draw_hu(reveal, opacity)


func _draw_peng(reveal: float, opacity: float) -> void:
	# Two gold bands converge, then recoil into a matched pair of impact arcs.
	var strike := smoothstep(0.025, 0.16, _progress)
	var recoil := smoothstep(0.15, 0.58, _progress)
	var distance := lerpf(117.0, 48.0, strike) + 25.0 * recoil
	var edge := opacity * (1.0 - 0.62 * recoil)
	_glow(Color("#ffb329"), Vector2(98, 57), 0.90 * opacity)
	for side: float in [-1.0, 1.0]:
		var transform := Vector2(side, 1)
		var sweep := PackedVector2Array([Vector2(distance + 31, 23), Vector2(distance + 8, 22),
			Vector2(distance - 18, 13), Vector2(distance - 26, 0), Vector2(distance - 18, -13),
			Vector2(distance + 8, -22), Vector2(distance + 31, -23)])
		_line_mirrored(sweep, transform, Color(ORANGE, edge * 0.49), 11.0)
		_line_mirrored(sweep, transform, Color(YELLOW, edge), 3.4)
		var core := PackedVector2Array([Vector2(distance + 10, 5), Vector2(distance - 16, 2), Vector2(distance + 1, -5)])
		_line_mirrored(core, transform, Color(IVORY, edge * 0.86), 1.6)
		var arc_start := -0.70 if side > 0 else PI - 0.70
		_arc(Vector2.ZERO, Vector2(64 + 51 * recoil, 34 + 19 * recoil),
			arc_start, 1.40, Color(GOLD, opacity * (0.86 - 0.60 * recoil)), 2.2)
	_medallion(46.0 * lerpf(0.82, 1.0, strike), 8, PI / 8, Color("#ad6419", opacity * 0.97), Color(YELLOW, opacity))
	_text(Vector2.ZERO, 72, reveal, opacity, YELLOW, Color("#74350e"))


func _draw_gang(reveal: float, opacity: float) -> void:
	var climb := smoothstep(0.05, 0.49, _progress)
	var wave := smoothstep(0.17, 0.86, _progress)
	_glow(ORANGE, Vector2(84, 76), 0.90 * opacity)
	for side: float in [-1.0, 1.0]:
		for rail in range(2):
			var rise := smoothstep(0.05 + 0.045 * rail, 0.39 + 0.06 * rail, _progress)
			var spread := 48.0 + 20.0 * rail + 11.0 * wave
			var apex := lerpf(36.0, -66.0 + rail * 17.0, rise)
			var column := PackedVector2Array([Vector2(spread + 17, 46), Vector2(spread + 4, 22),
				Vector2(spread, -7 * rise), Vector2(spread + 10, apex)])
			_line_mirrored(column, Vector2(side, 1), Color(ORANGE, opacity * 0.48 * rise), 9.0)
			_line_mirrored(column, Vector2(side, 1), Color(YELLOW, opacity * 0.89 * rise), 2.3)
			var crest := [Vector2(spread + 10, apex - 5), Vector2(spread + 15, apex + 2), Vector2(spread + 10, apex + 9), Vector2(spread + 5, apex + 2)]
			_shape(crest, Vector2(side, 1), 1.0, Color(GOLD, opacity * rise), Color(IVORY, opacity * 0.4 * rise))
	for index in range(2):
		var expansion := 1.0 + 0.34 * wave + 0.12 * index
		_arc(Vector2(0, 39 + index * 5), Vector2(67, 18) * expansion,
			0.27, 2.60, Color(GOLD, opacity * (0.77 - index * 0.34) * (1.0 - 0.72 * wave)), 1.6)
	_medallion(50.0 * lerpf(0.80, 1.0, reveal), 4, 0.0, Color("#ab4615", opacity * 0.96), Color(GOLD, opacity))
	_text(Vector2(0, -2 - 4 * climb), 73, reveal, opacity, IVORY, Color("#702607"))
	if not _detail.is_empty():
		var detail_opacity := opacity * smoothstep(0.12, 0.29, _progress)
		var tracking := _font.get_string_size(_detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		var badge := Rect2(-tracking * 0.5 - 12, 42, tracking + 24, 23)
		draw_rect(badge, Color("#492615", detail_opacity * 0.9))
		draw_rect(badge, Color(GOLD, detail_opacity * 0.75), false, 1.0)
		draw_string(_font, Vector2(-tracking * 0.5, 59), _detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(IVORY, detail_opacity))


func _draw_hu(reveal: float, opacity: float) -> void:
	var open := smoothstep(0.05, 0.42, _progress)
	var wave := smoothstep(0.17, 0.91, _progress)
	_glow(VERMILION, Vector2(108, 65), opacity)
	var petals := PackedVector2Array()
	for i in range(48):
		var angle := i * TAU / 48.0 - PI / 2.0
		var radius := lerpf(42.0, 64.0, open) + 15.0 * pow(sin(angle * 4.0), 2)
		petals.append(Vector2(cos(angle), sin(angle) * 0.84) * radius)
	draw_colored_polygon(petals, Color("#c74723", opacity * 0.96))
	_closed_line(petals, Color(GOLD, opacity * 0.91), 2.2)
	for side: float in [-1.0, 1.0]:
		var wing := PackedVector2Array([Vector2(51, 16), Vector2(74, 10),
			Vector2(99 + 18 * open, -18), Vector2(122 + 7 * open, -23)])
		_line_mirrored(wing, Vector2(side, 1), Color(VERMILION, opacity * 0.68), 8.2)
		_line_mirrored(wing, Vector2(side, 1), Color(GOLD, opacity * 0.86), 1.65)
		for index in range(2):
			var dimensions := Vector2(82 + 29 * wave + 8 * index, 37 + 20 * wave + 6 * index)
			var curve_color := Color(GOLD if index == 0 else VERMILION, opacity * (0.78 - 0.31 * index) * (1.0 - 0.44 * wave))
			_arc(Vector2.ZERO, dimensions, (0.15 if side > 0 else PI + 0.15) - 0.2 * wave, 1.26, curve_color, 1.65)
	for index in range(8):
		var angle := (index + 0.45) * TAU / 8.0
		var ray := Vector2.from_angle(angle)
		var distance := lerpf(42.0, 104.0, open + 0.22 * wave)
		var spark := ray * distance * Vector2(1.0, 0.62)
		draw_line(spark - ray * 6.0, spark + ray * 6.0, Color(YELLOW, opacity * open * (1.0 - 0.71 * wave)), 2.1, true)
	var star_y := 49.0 + 16.0 * open
	var stars := PackedVector2Array([Vector2(0, -star_y - 8), Vector2(5, -star_y), Vector2(0, -star_y + 8), Vector2(-5, -star_y)])
	draw_colored_polygon(stars, Color(GOLD, opacity * 0.95))
	_medallion(54.0 * lerpf(0.84, 1.0, reveal), 8, PI / 8, Color("#97201a", opacity * 0.98), Color(GOLD, opacity * 0.98))
	_text(Vector2(0, -2), 87, reveal, opacity, Color("#fff2b4"), Color("#711c10"))


func _glow(color: Color, radii: Vector2, opacity: float) -> void:
	var half := radii * 1.42
	draw_texture_rect(_glow_texture, Rect2(-half, half * 2.0), false, Color(color, opacity))


static func _make_glow_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.40, 0.72, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0.36), Color(1, 1, 1, 0.27), Color(1, 1, 1, 0.10), Color(1, 1, 1, 0)])
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
	var texture := GradientTexture2D.new()
	texture.width = 128
	texture.height = 128
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture


func _medallion(radius: float, sides: int, phase: float, fill: Color, trim: Color) -> void:
	var points := PackedVector2Array()
	var inset := PackedVector2Array()
	for i in sides:
		var point := Vector2.from_angle(i * TAU / sides + phase - PI / 2.0)
		points.append(point * radius)
		inset.append(point * (radius - 4.0))
	draw_colored_polygon(points, fill)
	_closed_line(points, Color(INK, trim.a * 0.64), 5.0)
	_closed_line(points, trim, 1.7)
	_closed_line(inset, Color(trim, trim.a * 0.36), 1.0)


func _shape(source: Array, mirror: Vector2, scale_factor: float, fill: Color, trim: Color) -> void:
	var points := PackedVector2Array()
	for point: Vector2 in source:
		points.append(point * mirror * lerpf(0.85, 1.0, scale_factor))
	draw_colored_polygon(points, fill)
	_closed_line(points, trim, 1.4)


func _line_mirrored(source: PackedVector2Array, mirror: Vector2, color: Color, weight: float) -> void:
	var points := PackedVector2Array()
	for point in source:
		points.append(point * mirror)
	draw_polyline(points, color, weight, true)


func _closed_line(points: PackedVector2Array, color: Color, weight: float) -> void:
	var path := points.duplicate()
	path.append(points[0])
	draw_polyline(path, color, weight, true)


func _arc(center: Vector2, radii: Vector2, start: float, sweep: float, color: Color, weight: float) -> void:
	var points := PackedVector2Array()
	for step in range(33):
		var angle := start + sweep * step / 32.0
		points.append(center + Vector2.from_angle(angle) * radii)
	draw_polyline(points, color, weight, true)


func _text(center: Vector2, font_size: int, reveal: float, opacity: float, fill: Color, stroke: Color) -> void:
	var scale_factor := lerpf(0.77, 1.0, reveal) + 0.075 * sin(PI * smoothstep(0.08, 0.39, _progress))
	var amount := maxi(1, roundi(font_size * scale_factor))
	var text_width := _font.get_string_size(_caption, HORIZONTAL_ALIGNMENT_LEFT, -1, amount).x
	var baseline := center.y + (_font.get_ascent(amount) - _font.get_descent(amount)) * 0.5
	var origin := Vector2(center.x - text_width * 0.5, baseline)
	draw_string_outline(_font, origin + Vector2(0, 3), _caption, HORIZONTAL_ALIGNMENT_LEFT, -1, amount, 9, Color(INK, opacity * 0.72))
	draw_string_outline(_font, origin, _caption, HORIZONTAL_ALIGNMENT_LEFT, -1, amount, 5, Color(stroke, opacity))
	draw_string(_font, origin, _caption, HORIZONTAL_ALIGNMENT_LEFT, -1, amount, Color(fill, opacity))
