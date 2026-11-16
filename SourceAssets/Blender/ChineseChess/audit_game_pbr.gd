extends SceneTree

func _initialize() -> void:
	call_deferred("inspect_asset")

func inspect_asset() -> void:
	var scene: PackedScene = load("res://modules/games/chinese_chess/assets/models/chess_pieces.glb")
	var library := scene.instantiate()
	root.add_child(library)
	var piece: MeshInstance3D = library.find_child("Piece_Red_General", true, false)
	for i in range(piece.mesh.get_surface_count()):
		var mat: StandardMaterial3D = piece.get_active_material(i)
		print("IMPORTED_PBR ", JSON.stringify({"name": mat.resource_name, "roughness": mat.roughness, "normal": mat.normal_enabled, "normal_scale": mat.normal_scale, "roughness_texture": mat.roughness_texture != null, "clearcoat_enabled": mat.clearcoat_enabled, "clearcoat": mat.clearcoat, "clearcoat_roughness": mat.clearcoat_roughness, "albedo_uses_uv2": mat.albedo_texture_force_srgb, "uv_scale": mat.uv1_scale}))
	var attributes := piece.mesh.surface_get_arrays(0)
	print("IMPORTED_UV vertices=", attributes[Mesh.ARRAY_VERTEX].size(), " uv0=", attributes[Mesh.ARRAY_TEX_UV].size(), " tangents=", attributes[Mesh.ARRAY_TANGENT].size())
	quit()
