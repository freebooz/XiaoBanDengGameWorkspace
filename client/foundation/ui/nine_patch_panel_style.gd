extends StyleBox
## Independent, tiled paper fill and a transparent nine-slice ornamental rim.

const PATCH := preload("res://modules/foundation/ui/aspect_nine_patch_style.gd")

var paper: Texture2D
var rim: Texture2D
var source_region := Rect2(0, 0, 1254, 1200)
var source_cuts := Vector4(360, 260, 320, 280)


func border_scale_for_size(extent: Vector2) -> float:
	return clampf(minf(extent.x, extent.y) * 0.00075, 0.14, 0.46)


func border_center_offset(extent: Vector2) -> float:
	return 62.0 * border_scale_for_size(extent)


func _draw(canvas: RID, rect: Rect2) -> void:
	if paper == null or rim == null or not rect.has_area():
		return
	var factor := border_scale_for_size(rect.size)
	var fill := Rect2(rect.position + Vector2(50, 62) * factor, rect.size - Vector2(100, 114) * factor)
	_draw_paper(canvas, fill, minf(110 * factor, minf(fill.size.x, fill.size.y) * 0.45))
	var border := PATCH.new()
	border.texture = rim
	border.region_rect = source_region
	border.source_margins = source_cuts
	border.corner_scale = factor
	border.draw_center = false
	border.tile_edges = true
	border.draw(canvas, rect)


func _draw_paper(canvas: RID, rect: Rect2, radius: float) -> void:
	if not rect.has_area():
		return
	var outline := PackedVector2Array()
	var centers := [rect.position + Vector2(radius, radius), Vector2(rect.end.x - radius, rect.position.y + radius), rect.end - Vector2.ONE * radius, Vector2(rect.position.x + radius, rect.end.y - radius)]
	for corner in 4:
		for step in 9:
			var angle := PI + corner * PI * 0.5 + step * PI / 16.0
			outline.append(centers[corner] + Vector2(cos(angle), sin(angle)) * radius)
	# Tile at native density. Clip only the fill; border artwork keeps its original RGB/alpha.
	var tile_size := paper.get_size()
	for y in ceili(rect.size.y / tile_size.y):
		for x in ceili(rect.size.x / tile_size.x):
			var origin := rect.position + Vector2(x, y) * tile_size
			var tile := Rect2(origin, tile_size)
			var tile_polygon := PackedVector2Array([tile.position, Vector2(tile.end.x, tile.position.y), tile.end, Vector2(tile.position.x, tile.end.y)])
			for clipped: PackedVector2Array in Geometry2D.intersect_polygons(outline, tile_polygon):
				var uv := PackedVector2Array()
				for point in clipped:
					uv.append((point - origin) / tile_size)
				RenderingServer.canvas_item_add_polygon(canvas, clipped, PackedColorArray([Color.WHITE]), uv, paper.get_rid())
