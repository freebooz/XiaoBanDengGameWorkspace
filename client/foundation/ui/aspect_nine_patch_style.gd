extends StyleBox
## Nine-slice artwork with independent source cuts and uniformly scaled corners.
## Native Button text, focus, input and minimum touch sizes remain unscaled.

@export var texture: Texture2D
@export var source_margins := Vector4(24, 24, 24, 24)
@export var region_rect := Rect2()
@export var modulate_color := Color.WHITE
@export var draw_center := true
@export var preserve_aspect := false
@export var aspect_max_extent := 0.0
## Panels specify a border scale independently of the height of their contents.
@export var corner_scale := 0.0
@export var tile_edges := false


func patch_layout(rect: Rect2) -> Array[Dictionary]:
	var patches: Array[Dictionary] = []
	if texture == null or rect.size.x <= 0 or rect.size.y <= 0:
		return patches
	var source := region_rect if region_rect.has_area() else Rect2(Vector2.ZERO, texture.get_size())
	if preserve_aspect:
		var available := rect.size.min(Vector2.ONE * aspect_max_extent) if aspect_max_extent > 0.0 else rect.size
		var fitted := source.size * minf(available.x / source.size.x, available.y / source.size.y)
		rect = Rect2(rect.get_center() - fitted * 0.5, fitted)
	var left := clampf(source_margins.x, 1.0, source.size.x * 0.49)
	var right := clampf(source_margins.z, 1.0, source.size.x * 0.49)
	var top := clampf(source_margins.y, 1.0, source.size.y * 0.49)
	var bottom := clampf(source_margins.w, 1.0, source.size.y * 0.49)
	# Width may extend the middle only. On extremely narrow controls, shrink all
	# four corners uniformly, then allow the side strips to fill the height.
	var factor := minf(rect.size.y / source.size.y, rect.size.x / (left + right + 1.0))
	if corner_scale > 0.0:
		factor = minf(corner_scale, minf(rect.size.y / (top + bottom + 1.0), rect.size.x / (left + right + 1.0)))
	var sx := [source.position.x, source.position.x + left, source.end.x - right, source.end.x]
	var sy := [source.position.y, source.position.y + top, source.end.y - bottom, source.end.y]
	var dx := [rect.position.x, rect.position.x + left * factor, rect.end.x - right * factor, rect.end.x]
	var dy := [rect.position.y, rect.position.y + top * factor, rect.end.y - bottom * factor, rect.end.y]
	for row in 3:
		for column in 3:
			if not draw_center and row == 1 and column == 1:
				continue
			patches.append({
				"source": Rect2(sx[column], sy[row], sx[column + 1] - sx[column], sy[row + 1] - sy[row]),
				"destination": Rect2(dx[column], dy[row], dx[column + 1] - dx[column], dy[row + 1] - dy[row]),
			})
	return patches


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	for patch in patch_layout(rect):
		var source: Rect2 = patch.source
		var destination: Rect2 = patch.destination
		var artwork := region_rect if region_rect.has_area() else Rect2(Vector2.ZERO, texture.get_size())
		var horizontal := is_equal_approx(source.position.x, artwork.position.x + source_margins.x)
		var vertical := is_equal_approx(source.position.y, artwork.position.y + source_margins.y)
		if not tile_edges or horizontal == vertical:
			texture.draw_rect_region(to_canvas_item, destination, source, modulate_color)
			continue
		# Repeating an edge strip keeps its bamboo joints from stretching into bars.
		var span := source.size.x * destination.size.y / source.size.y if horizontal else source.size.y * destination.size.x / source.size.x
		var length := destination.size.x if horizontal else destination.size.y
		var count := maxi(1, roundi(length / maxf(span, 1.0)))
		for index in count:
			var section := destination
			if horizontal:
				section.position.x += length * index / count
				section.size.x = length / count
			else:
				section.position.y += length * index / count
				section.size.y = length / count
			texture.draw_rect_region(to_canvas_item, section, source, modulate_color)
