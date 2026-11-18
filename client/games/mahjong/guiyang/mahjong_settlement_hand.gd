extends "res://modules/game_framework/tabletop3d/native_3d_view.gd"
## A static, native-pixel view of one player's reported hand and melds.

const TILE_MODEL := preload("res://modules/games/mahjong/guiyang/real_tile_model.gd")
const TILE_MATERIALS := preload("res://modules/games/mahjong/guiyang/real_tile_materials.gd")
const TILE_GAP := 0.0008
const GROUP_GAP := 0.0045
const TILE_TILT := 59.0
const EDGE_PADDING := 0.002
const FULL_HAND_WIDTH := 14.0 * TILE_MODEL.SIZE.x + 13.0 * TILE_GAP
const TILE_HEIGHT := TILE_MODEL.SIZE.z * sin(deg_to_rad(TILE_TILT)) + TILE_MODEL.SIZE.y * cos(deg_to_rad(TILE_TILT))

var _tiles: Array = []
var _materials: RefCounted
var _green_body: ShaderMaterial
var _models: Node3D
var _camera: Camera3D
var _shadows: MultiMesh
var _hand_width := 0.0


func setup(tiles: Array, materials: RefCounted) -> void:
	if materials == null:
		materials = _materials if _materials != null else TILE_MATERIALS.new()
	if materials != _materials:
		_materials = materials
		# Keep this finish local to the settlement; the live table shares its own resin.
		_green_body = materials.body().duplicate() as ShaderMaterial
		_green_body.set_shader_parameter("blue_color", Color("#219363"))
	elif _tiles == tiles:
		return
	_tiles = tiles.duplicate(true)
	if is_node_ready():
		_build_hand()


func _ready() -> void:
	super._ready()
	_models = Node3D.new()
	_models.name = "SettlementTiles"
	viewport.add_child(_models)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.position.z = 0.5
	_camera.far = 1.0
	var environment := Environment.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#fff8f0")
	environment.ambient_light_energy = 0.60
	_camera.environment = environment
	viewport.add_child(_camera)
	_camera.current = true
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-33, -24, 0)
	key.light_color = Color("#fff8ef")
	key.light_energy = 0.62
	viewport.add_child(key)
	_build_contact_shadows()
	projection_resized.connect(_fit_camera)
	_build_hand()


func _build_hand() -> void:
	for model in _models.get_children():
		_models.remove_child(model)
		model.queue_free()
	_hand_width = 0.0
	var previous_group := 0
	_shadows.instance_count = _tiles.size()
	for tile in _tiles:
		if not tile is Dictionary or tile.is_empty():
			continue
		var group := int(tile.get("group", 0))
		if _hand_width > 0.0:
			_hand_width += TILE_GAP
			if group != previous_group:
				_hand_width += GROUP_GAP
		var concealed := bool(tile.get("concealed", false))
		# The table's small-face material preserves the engraved pigment in distant mip levels.
		var model := TILE_MODEL.build(_materials, tile, concealed, true)
		var body := model.find_child("TileBody", true, false) as MeshInstance3D
		body.material_override = _green_body
		model.rotation_degrees.x = TILE_TILT + (180.0 if concealed else 0.0)
		# The imported mesh's origin lies on its back. Rotate each face about the solid's center.
		var center_x := _hand_width + TILE_MODEL.SIZE.x * 0.5
		model.position = Vector3(center_x, 0, 0) - model.basis.y * TILE_MODEL.SIZE.y * 0.5
		var contact := Vector3(center_x, -TILE_HEIGHT * 0.5 - 0.0006, -0.05)
		_shadows.set_instance_transform(_models.get_child_count(), Transform3D(Basis.IDENTITY, contact))
		_models.add_child(model)
		_hand_width += TILE_MODEL.SIZE.x
		previous_group = group
	_shadows.visible_instance_count = _models.get_child_count()
	_fit_camera()


func _build_contact_shadows() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.56, 1.0])
	gradient.colors = PackedColorArray([Color("#69401c78"), Color("#69401c4d"), Color("#69401c00")])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 16
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = texture
	var quad := QuadMesh.new()
	quad.size = Vector2(TILE_MODEL.SIZE.x * 1.2, 0.012)
	quad.material = material
	_shadows = MultiMesh.new()
	_shadows.transform_format = MultiMesh.TRANSFORM_3D
	_shadows.mesh = quad
	var shadow_row := MultiMeshInstance3D.new()
	shadow_row.multimesh = _shadows
	shadow_row.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	viewport.add_child(shadow_row)


func _fit_camera() -> void:
	var aspect := Vector2(viewport.size).aspect()
	var width := maxf(FULL_HAND_WIDTH, _hand_width) + 2.0 * EDGE_PADDING
	_camera.size = maxf(TILE_HEIGHT + 0.012, width / aspect)
	_camera.position.x = _camera.size * aspect * 0.5 - EDGE_PADDING
	if is_visible_in_tree():
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
