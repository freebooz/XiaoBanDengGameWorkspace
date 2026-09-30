extends RefCounted
## 金丝楠木棋子：比例参考直径 32 mm、厚度 10 mm，材质与红黑刻字独立可调。


static func create_piece(symbol: String, is_red: bool, face_black_player: bool, wood_texture: Texture2D, radius: float, piece_name: String) -> Node3D:
	var piece := Node3D.new()
	piece.name = piece_name
	var half_height := radius * 10.0 / 32.0

	var lacquer := StandardMaterial3D.new()
	lacquer.albedo_color = Color("#e3ad50")
	lacquer.albedo_texture = wood_texture
	lacquer.roughness = 0.23
	lacquer.metallic = 0.025
	var body := MeshInstance3D.new()
	body.name = "RoundedNanmuBody"
	body.mesh = _rounded_disc_mesh(radius, half_height)
	body.material_override = lacquer
	piece.add_child(body)

	var top_material := StandardMaterial3D.new()
	top_material.albedo_color = Color("#f5d7a5")
	top_material.albedo_texture = wood_texture
	top_material.roughness = 0.31
	var top := MeshInstance3D.new()
	top.name = "PolishedTop"
	var top_mesh := CylinderMesh.new()
	top_mesh.top_radius = radius * 0.84
	top_mesh.bottom_radius = radius * 0.84
	top_mesh.height = 0.010
	top_mesh.radial_segments = 48
	top.mesh = top_mesh
	top.material_override = top_material
	top.position.y = half_height + 0.004
	piece.add_child(top)

	var ring := MeshInstance3D.new()
	ring.name = "CarvedCinnabarRing"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = radius * 0.735
	ring_mesh.outer_radius = radius * 0.765
	ring_mesh.rings = 48
	ring_mesh.ring_segments = 8
	ring.mesh = ring_mesh
	ring.position.y = half_height + 0.011
	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = Color("#a93320")
	ring_material.roughness = 0.43
	ring.material_override = ring_material
	piece.add_child(ring)

	var glyph := Label3D.new()
	glyph.name = "EngravedGlyph"
	glyph.text = symbol
	glyph.font_size = 62
	glyph.pixel_size = 0.0050
	glyph.outline_size = 2
	glyph.position.y = half_height + 0.018
	glyph.rotation_degrees.x = -90.0
	if face_black_player:
		glyph.rotation_degrees.y = 180.0
	glyph.modulate = Color("#ab2119") if is_red else Color("#17120e")
	glyph.outline_modulate = Color("#e9c27e")
	piece.add_child(glyph)
	return piece


static func _rounded_disc_mesh(radius: float, half_height: float) -> ArrayMesh:
	# 回转剖面形成连续圆角木身，避免多个圆柱叠放留下接缝。
	var profile: Array[Vector2] = [
		Vector2(0.0, -half_height),
		Vector2(radius * 0.85, -half_height),
		Vector2(radius * 0.95, -half_height * 0.88),
		Vector2(radius, -half_height * 0.55),
		Vector2(radius, half_height * 0.45),
		Vector2(radius * 0.96, half_height * 0.82),
		Vector2(radius * 0.86, half_height),
		Vector2(0.0, half_height)
	]
	var segments := 48
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for j in range(profile.size()):
		var previous := profile[maxi(j - 1, 0)]
		var following := profile[mini(j + 1, profile.size() - 1)]
		var tangent := (following - previous).normalized()
		var profile_normal := Vector2(tangent.y, -tangent.x).normalized()
		for i in range(segments + 1):
			var angle := TAU * float(i) / float(segments)
			var radial := Vector2(cos(angle), sin(angle))
			vertices.append(Vector3(radial.x * profile[j].x, profile[j].y, radial.y * profile[j].x))
			normals.append(Vector3(radial.x * profile_normal.x, profile_normal.y, radial.y * profile_normal.x))
			uvs.append(Vector2(float(i) / float(segments), float(j) / float(profile.size() - 1)))
	for j in range(profile.size() - 1):
		for i in range(segments):
			var a := j * (segments + 1) + i
			var b := a + 1
			var c := a + segments + 1
			var d := c + 1
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
