extends Control
## Native cut-corner chrome, projected compass and hand outline; no input capture.
const COMPASS_TEXTURE := preload("res://modules/games/mahjong/guiyang/assets/ui/jade_hud/compass.svg")

var kind := "panel"
var accent := Color("#00d889")
var active := false
var directions := ["西", "北", "东", "南"]
var active_direction := -1
var selection_arrow_offset := -8.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _outline(rect: Rect2, cut: float) -> PackedVector2Array:
	var p := rect.position
	var e := rect.end
	return PackedVector2Array([p+Vector2(cut,0),Vector2(e.x-cut,p.y),Vector2(e.x,p.y+cut),e-Vector2(0,cut),e-Vector2(cut,0),Vector2(p.x+cut,e.y),Vector2(p.x,e.y-cut),p+Vector2(0,cut)])

func _draw() -> void:
	if size.x <= 0 or size.y <= 0: return
	var s := minf(size.y / 90.0, 1.7)
	var font := get_theme_default_font()
	if kind == "microphone":
		var center := size*.5
		var color := Color("#e8ede9") if active else Color("#77867e")
		var line_width := maxf(1.0, minf(size.x, size.y) * 0.046)
		var capsule := StyleBoxFlat.new()
		capsule.bg_color=color
		capsule.set_corner_radius_all(roundi(size.x*.11))
		draw_style_box(capsule,Rect2(Vector2(size.x*.40,size.y*.22),Vector2(size.x*.20,size.y*.37)))
		draw_arc(center+Vector2(0,size.y*.03),size.x*.19,0,PI,24,color,line_width,true)
		draw_line(Vector2(size.x*.31,size.y*.43),Vector2(size.x*.31,size.y*.54),color,line_width,true)
		draw_line(Vector2(size.x*.69,size.y*.43),Vector2(size.x*.69,size.y*.54),color,line_width,true)
		draw_line(Vector2(size.x*.5,size.y*.72),Vector2(size.x*.5,size.y*.82),color,line_width,true)
		draw_line(Vector2(size.x*.38,size.y*.82),Vector2(size.x*.62,size.y*.82),color,line_width,true)
		if not active: draw_line(Vector2(size.x*.25,size.y*.2),Vector2(size.x*.75,size.y*.85),Color("#dca47b"),line_width,true)
		return
	if kind == "selection":
		_draw_selection()
		return
	if kind == "compass":
		_draw_compass(s, font)
		return
	var points := _outline(Rect2(Vector2.ONE*2,size-Vector2.ONE*4),minf(14*s,size.y*.19))
	draw_colored_polygon(points,Color("#32261dee"))
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed,Color(accent,0.13),6*s,true)
	draw_polyline(closed,Color(accent,0.80 if active else 0.48),1.2*s,true)
	draw_line(Vector2(18*s,size.y-3),Vector2(size.x*.48,size.y-3),Color(accent,.55),1.1*s,true)


func _draw_selection() -> void:
	var unit := clampf(size.x / 78.0, 0.70, 1.45)
	var face := Rect2(Vector2.ONE * 3.0 * unit, size - Vector2.ONE * 6.0 * unit)
	var halo := StyleBoxFlat.new()
	halo.bg_color = Color.TRANSPARENT
	halo.set_corner_radius_all(roundi(7.0 * unit))
	halo.corner_detail = 10
	for distance in range(7, 0, -1):
		halo.set_border_width_all(maxi(1, roundi((distance + 1) * unit)))
		halo.border_color = Color(1.0, 0.65, 0.16, 0.020 + 0.010 * float(7 - distance))
		draw_style_box(halo, face.grow(float(distance) * 0.67 * unit))
	halo.set_border_width_all(maxi(1, roundi(2.0 * unit)))
	halo.border_color = Color("#fff1ac")
	halo.border_blend = true
	draw_style_box(halo, face)
	var arrow_center := Vector2(size.x * 0.5, selection_arrow_offset * unit)
	var arrow := PackedVector2Array([arrow_center + Vector2(-10, 4)*unit, arrow_center + Vector2(0,-4)*unit, arrow_center + Vector2(10,4)*unit])
	draw_polyline(arrow, Color("#ffc15270"), 7.0*unit, true)
	draw_polyline(arrow, Color("#fff2bf"), 2.6*unit, true)


func _draw_compass(unit: float, font: Font) -> void:
	var center := size*.5
	var radius := minf(size.x, size.y) * 0.48
	var extent := Vector2(1.153, 1.0)*radius*2.0
	draw_texture_rect(COMPASS_TEXTURE, Rect2(center - extent*0.5, extent), false)
	var font_size := maxi(1, roundi(14.0 * unit))
	var axes := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
	var relative_seats := [2,1,0,3]
	for index in range(axes.size()):
		var word: String = directions[index]
		var pos: Vector2 = center + axes[index] * radius * 0.71
		var is_turn: bool = relative_seats[index] == active_direction
		if is_turn:
			draw_circle(pos, radius * 0.19, Color("#d8ac71"), true, -1.0, true)
		pos.x -= font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5
		pos.y += (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
		draw_string(font, pos, word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#38251b") if is_turn else Color("#f3d6ac"))
