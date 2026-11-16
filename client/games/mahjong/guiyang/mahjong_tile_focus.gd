extends Node3D
## Presentation only: the screen binds this once per accepted board snapshot or
## selection event. No polling of the game state, transport or hidden hands.

const RESIN_SHADER := preload("res://modules/games/mahjong/guiyang/tile_resin.gdshader")
var marker: MeshInstance3D
var marker_identity := ""
var _marker_base := Vector3.ZERO
var _marker_animation: Tween
var _selected_tile: Node3D
var _selection_materials: Dictionary = {}
var _quality := -1


func _ready() -> void:
	name = "MahjongTileFocus"
	marker = MeshInstance3D.new()
	marker.name = "LastDiscardCrystal"
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visible = false
	add_child(marker)
	set_quality(1)


func set_quality(value: int) -> void:
	value = clampi(value, 0, 2)
	if _quality == value: return
	_quality = value
	marker.mesh = _crystal_mesh([4, 6, 8][_quality])
	var resin := StandardMaterial3D.new()
	resin.albedo_color = Color("#e8ffb3eb")
	resin.vertex_color_use_as_albedo = true
	resin.vertex_color_is_srgb = true
	resin.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	resin.metallic = 0.04
	resin.roughness = 0.16
	resin.metallic_specular = 0.65
	resin.clearcoat_enabled = _quality > 0
	resin.clearcoat = 0.7
	resin.clearcoat_roughness = 0.16
	resin.emission_enabled = true
	resin.emission = Color("#b5f52a")
	resin.emission_energy_multiplier = [0.40, 0.60, 0.78][_quality]
	marker.material_override = resin
	if marker.visible: _start_marker_breath()
	var selected := _selected_tile
	_clear_selection_materials()
	select_tile(selected)


func _crystal_mesh(facets: int) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in facets:
		var angle := float(side)*TAU/float(facets)
		var next := float(side+1)*TAU/float(facets)
		var a := Vector3(cos(angle)*0.014,0.021,sin(angle)*0.014)
		var b := Vector3(cos(next)*0.014,0.021,sin(next)*0.014)
		var tint := Color("#b8df46").lerp(Color("#e5f78b"),0.28 if side%2 else 0.0)
		_crystal_triangle(surface,a,Vector3(0,-0.021,0),b,tint)
		_crystal_triangle(surface,Vector3(0,0.021,0),a,b,Color("#f0ffaf"))
	var mesh := surface.commit()
	mesh.set_meta("facets",facets)
	return mesh


func _crystal_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, tint: Color) -> void:
	# Separate face normals make a polished crystal rather than a smooth cone.
	var normal := (c-a).cross(b-a).normalized()
	for vertex in [a,b,c]:
		surface.set_normal(normal)
		surface.set_color(tint)
		surface.add_vertex(vertex)


func bind_last_discard(tile: Node3D, identity: String) -> void:
	if not is_instance_valid(tile) or identity.is_empty():
		clear_marker()
		return
	var body := tile.find_child("TileBody", true, false) as MeshInstance3D
	if body == null:
		clear_marker()
		return
	var bounds: AABB = body.global_transform * body.get_aabb()
	var base := Vector3(bounds.get_center().x, bounds.end.y + 0.030, bounds.get_center().z)
	if marker.visible and marker_identity == identity and _marker_base.is_equal_approx(base): return
	marker_identity = identity
	_marker_base = base
	marker.visible = true
	_start_marker_breath()


func _start_marker_breath() -> void:
	if is_instance_valid(_marker_animation): _marker_animation.kill()
	marker.global_position = _marker_base
	var resin := marker.material_override as StandardMaterial3D
	var energy: float = [0.40, 0.60, 0.78][_quality]
	resin.emission_energy_multiplier = energy
	_marker_animation = create_tween().set_loops()
	_marker_animation.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_marker_animation.tween_property(marker, "global_position:y", _marker_base.y + 0.006, 0.85)
	_marker_animation.parallel().tween_property(resin,"emission_energy_multiplier",energy*1.18,0.85)
	_marker_animation.tween_property(marker, "global_position:y", _marker_base.y, 0.85)
	_marker_animation.parallel().tween_property(resin,"emission_energy_multiplier",energy,0.85)


func clear_marker() -> void:
	if is_instance_valid(_marker_animation): _marker_animation.kill()
	_marker_animation = null
	marker_identity = ""
	if is_instance_valid(marker): marker.hide()


func select_tile(tile: Node3D) -> void:
	if is_instance_valid(tile) and tile == _selected_tile and not _selection_materials.is_empty(): return
	_clear_selection_materials()
	if not is_instance_valid(tile): return
	var body := tile.find_child("TileBody", true, false) as MeshInstance3D
	if body == null: return
	_selected_tile = tile
	_selection_materials[body] = body.material_override
	var resin := body.material_override.duplicate() as ShaderMaterial
	resin.shader = RESIN_SHADER
	resin.set_shader_parameter("selection_strength", [0.76, 0.90, 1.0][_quality])
	body.material_override = resin
	var face := tile.find_child("TileFace", true, false) as MeshInstance3D
	if face != null and face.material_override is StandardMaterial3D:
		_selection_materials[face] = face.material_override
		var printed := face.material_override.duplicate() as StandardMaterial3D
		printed.albedo_color = Color("#dceb9b")
		printed.emission_enabled = true
		printed.emission = Color("#b5ed38")
		printed.emission_texture = printed.albedo_texture
		printed.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		printed.emission_energy_multiplier = [0.24, 0.31, 0.38][_quality]
		face.material_override = printed


func _clear_selection_materials() -> void:
	for mesh in _selection_materials:
		if is_instance_valid(mesh): mesh.material_override = _selection_materials[mesh]
	_selection_materials.clear()
	_selected_tile = null


func clear() -> void:
	clear_marker()
	_clear_selection_materials()


func _exit_tree() -> void:
	clear()
