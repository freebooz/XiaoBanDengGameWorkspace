extends Node3D
## A table-space wind dial. Seat indices are absolute and the near plate is seat 0 relative to the viewer.

const TIMBER := preload("res://modules/games/mahjong/guiyang/assets/ui/series/battle_wood.png")
const WINDS := ["南", "东", "北", "西"] # Near, right, far and left in the displayed table.
const TIMER_SURFACE_Y := 0.031
const PROFILE_HEIGHT_SCALE := 0.72
const FOOTPRINT_SCALE := 0.72
const CIRCLE_SEGMENTS := 96

var _viewer := 0
var _dealer := -1
var _plates: Array[MeshInstance3D] = []
var _winds: Array[Label3D] = []
var _ivory: StandardMaterial3D
var _dealer_gold: StandardMaterial3D


func _ready() -> void:
	name = "MahjongWindDial3D"
	scale = Vector3(1.0, PROFILE_HEIGHT_SCALE, 1.0) * FOOTPRINT_SCALE
	_build()
	_apply_winds()


func set_winds(viewer_seat: int, dealer_seat: int) -> void:
	_viewer = clampi(viewer_seat, 0, 3)
	_dealer = dealer_seat
	_apply_winds()


func get_timer_position() -> Vector3:
	return global_transform * Vector3(0.0, TIMER_SURFACE_Y, 0.0)


func _build() -> void:
	var wood := _material(Color("#ffd7a7"), 0.40)
	wood.albedo_texture = TIMBER
	wood.clearcoat_enabled = true
	wood.clearcoat = 0.31
	wood.clearcoat_roughness = 0.35
	var brass := _material(Color("#ffbd68"), 0.29, 0.41)
	var well := _material(Color("#101010"), 0.62)
	_ivory = _material(Color("#ffe7bc"), 0.39)
	_dealer_gold = _material(Color("#ffca30"), 0.32)
	_dealer_gold.emission_enabled = true
	_dealer_gold.emission = Color("#ffae32")
	_dealer_gold.emission_energy_multiplier = 0.29
	var plate_base := _material(Color("#b66d34"), 0.49)

	_build_circle("WoodenBody", [
		Vector2(0.133, 0.001), Vector2(0.145, 0.006), Vector2(0.147, 0.011),
		Vector2(0.147, 0.017), Vector2(0.141, 0.024), Vector2(0.135, 0.026),
		Vector2(0.080, 0.026), Vector2(0.074, 0.020), Vector2(0.071, 0.014)
	], wood, false, true)
	_build_circle("OuterBrassEdge", [
		Vector2(0.1448, 0.020), Vector2(0.1430, 0.0242), Vector2(0.1405, 0.0268),
		Vector2(0.1373, 0.0275), Vector2(0.1346, 0.0256)
	], brass)
	_build_circle("TimerWell", [Vector2(0.0709, 0.0139), Vector2(0.0709, 0.0146)], well, true, true)
	_build_circle("InnerBrassEdge", [
		Vector2(0.0830, 0.0257), Vector2(0.0815, 0.0289), Vector2(0.0780, 0.0301),
		Vector2(0.0746, 0.0282), Vector2(0.0724, 0.0240), Vector2(0.0716, 0.0162)
	], brass)

	var font := preload("res://modules/foundation/ui/fonts/NotoSansCJKsc-Bold.otf")
	var outline := PackedVector2Array([
		Vector2(-0.030, -0.023), Vector2(0.030, -0.023), Vector2(0.036, -0.019),
		Vector2(0.044, 0.018), Vector2(0.038, 0.023), Vector2(-0.038, 0.023),
		Vector2(-0.044, 0.018), Vector2(-0.036, -0.019)
	])
	for relative in range(4):
		var yaw := float(relative) * PI * 0.5
		var socket := Vector3(0.0, 0.0, 0.107).rotated(Vector3.UP, yaw)
		var bezel := _loft("WindPlateBase%d" % relative, _profile(outline, [
			Vector2(1.02, 0.025), Vector2(1.0, 0.0275), Vector2(0.96, 0.0295)
		]), plate_base, true)
		bezel.rotation.y = yaw
		bezel.position = socket
		var plate := _loft("WindPlate%d" % relative, _profile(outline, [
			Vector2(0.965, 0.0286), Vector2(0.955, 0.0317), Vector2(0.88, 0.034)
		]), _ivory, true)
		plate.rotation.y = yaw
		plate.position = socket
		_plates.append(plate)

		var glyph := Label3D.new()
		glyph.name = "WindGlyph%d" % relative
		glyph.font = font
		glyph.font_size = 92
		glyph.pixel_size = 0.00042
		glyph.outline_size = 2
		glyph.modulate = Color("#4d260d")
		glyph.outline_modulate = glyph.modulate
		glyph.rotation_degrees.x = -90.0
		glyph.position = socket + Vector3(0.0, 0.0356, 0.0)
		add_child(glyph)
		_winds.append(glyph)


func _apply_winds() -> void:
	for relative in range(_plates.size()):
		var seat := (_viewer + relative) % WINDS.size()
		_winds[relative].text = WINDS[relative]
		_plates[relative].material_override = _dealer_gold if _dealer == seat else _ivory


func _build_circle(node_name: String, profile: Array[Vector2], material: Material, cap_top := false, cap_bottom := false) -> void:
	var outline := PackedVector2Array()
	for segment in range(CIRCLE_SEGMENTS):
		var angle := TAU * float(segment) / float(CIRCLE_SEGMENTS)
		outline.append(Vector2(cos(angle), sin(angle)))
	var sections := _profile(outline, profile)
	# Share normals around the circumference and across the bevel profile.
	# Caps keep their own flat normals so they do not round the bottom or timer well.
	var profile_normals: Array[Vector2] = []
	for level in range(profile.size()):
		var tangent := Vector2.ZERO
		if level > 0: tangent += (profile[level] - profile[level - 1]).normalized()
		if level + 1 < profile.size(): tangent += (profile[level + 1] - profile[level]).normalized()
		profile_normals.append(Vector2(tangent.y, -tangent.x).normalized())
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for level in range(sections.size() - 1):
		for corner in range(CIRCLE_SEGMENTS):
			var next := (corner + 1) % CIRCLE_SEGMENTS
			var lower: PackedVector3Array = sections[level]
			var upper: PackedVector3Array = sections[level + 1]
			var lower_a := _circle_normal(outline[corner], profile_normals[level])
			var lower_b := _circle_normal(outline[next], profile_normals[level])
			var upper_a := _circle_normal(outline[corner], profile_normals[level + 1])
			var upper_b := _circle_normal(outline[next], profile_normals[level + 1])
			_triangle(surface, lower[corner], lower[next], upper[corner], [lower_a, lower_b, upper_a])
			_triangle(surface, lower[next], upper[next], upper[corner], [lower_b, upper_b, upper_a])
	if cap_top: _cap(surface, sections.back(), false)
	if cap_bottom: _cap(surface, sections.front(), true)
	_finish_mesh(node_name, surface, material)


func _circle_normal(radial: Vector2, profile_normal: Vector2) -> Vector3:
	return Vector3(radial.x * profile_normal.x, profile_normal.y, radial.y * profile_normal.x)


func _profile(outline: PackedVector2Array, levels: Array[Vector2]) -> Array[PackedVector3Array]:
	var sections: Array[PackedVector3Array] = []
	for level in levels:
		var section := PackedVector3Array()
		for point in outline:
			section.append(Vector3(point.x * level.x, level.y, point.y * level.x))
		sections.append(section)
	return sections


func _loft(node_name: String, sections: Array[PackedVector3Array], material: Material, cap_top: bool, cap_bottom := false) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(sections.size() - 1):
		var lower := sections[index]
		var upper := sections[index + 1]
		for corner in range(lower.size()):
			var next := (corner + 1) % lower.size()
			_triangle(surface, lower[corner], lower[next], upper[corner])
			_triangle(surface, lower[next], upper[next], upper[corner])
	if cap_top: _cap(surface, sections.back(), false)
	if cap_bottom: _cap(surface, sections.front(), true)
	return _finish_mesh(node_name, surface, material)


func _cap(surface: SurfaceTool, perimeter: PackedVector3Array, reverse: bool) -> void:
	var center := Vector3.ZERO
	for point in perimeter:
		center += point
	center /= float(perimeter.size())
	for corner in range(perimeter.size()):
		var a := perimeter[corner]
		var b := perimeter[(corner + 1) % perimeter.size()]
		_triangle(surface, center, b if reverse else a, a if reverse else b)


func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normals: Array[Vector3] = []) -> void:
	var normal := (c - a).cross(b - a).normalized()
	var vertices := [a, b, c]
	for index in range(vertices.size()):
		var vertex: Vector3 = vertices[index]
		surface.set_normal(normal if normals.is_empty() else normals[index])
		surface.set_uv(Vector2(vertex.x * 3.37 + 0.5, (vertex.z - vertex.y) * 3.37 + 0.5))
		surface.add_vertex(vertex)


func _finish_mesh(node_name: String, surface: SurfaceTool, material: Material) -> MeshInstance3D:
	surface.index()
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = surface.commit()
	instance.material_override = material
	add_child(instance)
	return instance


func _material(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	material.metallic_specular = 0.43
	return material
