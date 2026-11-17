extends Control
## Small native form glyphs scale with the form and never intercept input.
var kind := "phone"
var revealed := false

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var s := minf(size.x,size.y)/48.0
	var ink := Color("#8b5936")
	draw_set_transform((size-Vector2.ONE*48*s)*.5,0,Vector2.ONE*s)
	match kind:
		"phone":
			var box:=StyleBoxFlat.new()
			box.bg_color=ink
			box.set_corner_radius_all(3)
			draw_style_box(box,Rect2(13,3,22,42))
			draw_rect(Rect2(16,7,16,29),Color("#f5e9d3"))
			draw_circle(Vector2(24,40),2,Color("#f5e9d3"))
		"lock":
			draw_arc(Vector2(24,17),10,PI,TAU,30,ink,5,true)
			var box:=StyleBoxFlat.new()
			box.bg_color=ink
			box.set_corner_radius_all(3)
			draw_style_box(box,Rect2(8,18,32,27))
			draw_circle(Vector2(24,29),3,Color("#f7eedb"))
			draw_line(Vector2(24,29),Vector2(24,37),Color("#f7eedb"),3,true)
		"eye":
			var points:=PackedVector2Array()
			for index in range(33):
				var a:=float(index)/32*TAU
				points.append(Vector2(24+18*cos(a),24+10*sin(a)))
			draw_polyline(points,ink,3,true)
			draw_circle(Vector2(24,24),5,ink)
			if not revealed: draw_line(Vector2(9,40),Vector2(40,8),ink,4,true)
		"guest":
			draw_circle(Vector2(24,13),10,Color("#56320c"))
			var box:=StyleBoxFlat.new()
			box.bg_color=Color("#56320c")
			box.set_corner_radius_all(12)
			draw_style_box(box,Rect2(7,26,34,21))
		"wechat":
			draw_circle(Vector2(18,19),16,Color("#20bb42"))
			draw_colored_polygon(PackedVector2Array([Vector2(5,27),Vector2(4,38),Vector2(15,30)]),Color("#20bb42"))
			draw_circle(Vector2(34,31),13,Color("#16a937"))
			for point in [Vector2(12,15),Vector2(23,15),Vector2(29,28),Vector2(38,28)]: draw_circle(point,2,Color.WHITE)
