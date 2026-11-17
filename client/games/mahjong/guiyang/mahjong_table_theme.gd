extends RefCounted
## Felt and varnished wood on the imported Mahjong table.

const WOOD_SHADER := preload("res://modules/games/mahjong/guiyang/rural_wood.gdshader")
const FELT_SHADER := preload("res://modules/games/mahjong/guiyang/club_felt.gdshader")
const WOOD_ALBEDO := preload("res://modules/games/mahjong/guiyang/assets/models/textures/T_Mahjong_WalnutRail_BaseColor.png")
const CREAM := Color("#fff0d7")
const MUTED := Color("#e0c3a0")
const BRASS := Color("#ab7f50")
const FELT_SCALE := 0.689 / 0.6675
const FELT_COLOR := Color("#192f1e")
const KEY_POSITION := Vector3(-0.60, 1.20, 0.42)
# Approximate white points in sRGB for the project's unitless light mode.
const KEY_4800K := Color("#ffe5cb")
const FILL_6000K := Color("#fff7ef")
const RIM_COOL_DAYLIGHT := Color("#e6efff")
const KEY_ENERGY := 1.46
const FILL_ENERGY := 0.45
const RIM_ENERGY := 0.36
const CORNER_STEPS := 12
# Half-width, height and corner radius of the closed wooden rail, in GLB metres.
const RAIL_PROFILE := [
	Vector3(0.744, -0.059525, 0.048), Vector3(0.749, -0.056, 0.051),
	Vector3(0.750, -0.052, 0.052), Vector3(0.750, 0.001, 0.052),
	Vector3(0.7493, 0.0045, 0.0515), Vector3(0.7466, 0.008, 0.0495),
	Vector3(0.742, 0.010, 0.046), Vector3(0.691, 0.010, 0.033),
	Vector3(0.6872, 0.0088, 0.030), Vector3(0.6845, 0.0058, 0.0285),
	Vector3(0.683, 0.0015, 0.027), Vector3(0.683, -0.059525, 0.027),
]
static var _rail_mesh: ArrayMesh
static var _reflection_panorama: ImageTexture
static var _reflection_skies: Dictionary = {}


static func configure_stage(stage: Node3D, quality: int) -> void:
	var compatibility := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	# Linear tone mapping has less highlight headroom on the energy-saving tier.
	var local_energy := 0.66 if compatibility else (0.86 if quality == 0 else 1.0)
	var environment := (stage.get_node("WorldEnvironment") as WorldEnvironment).environment
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#ebeff4")
	environment.ambient_light_energy = 0.14 if compatibility else 0.17
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.sky = _studio_reflection(quality)
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC if quality > 0 and not compatibility else Environment.TONE_MAPPER_LINEAR
	environment.tonemap_exposure = 1.08 if quality > 0 and not compatibility else 1.0
	environment.tonemap_white = 1.75
	(stage.get_node("Floor") as MeshInstance3D).hide()

	# The angled spot is now the only shadow caster. Retire the former
	# directional and duplicate northwest fill instead of stacking more lamps.
	var key := stage.get_node("KeyLight") as DirectionalLight3D
	key.light_energy = 0.0
	key.shadow_enabled = false
	key.hide()
	var old_northwest := stage.get_node_or_null("NorthwestSeatLight") as Light3D
	if old_northwest != null:
		old_northwest.light_energy = 0.0
		old_northwest.shadow_enabled = false
		old_northwest.hide()
	# The upright hand faces away from the broad key. Lift the front fill
	# there so the engraved pips remain legible on smaller displays.
	_configure_fill(stage, "FillLight", Vector3(0.0, 0.30, 0.82), FILL_6000K, FILL_ENERGY * local_energy, 1.48)
	_configure_fill(stage, "NortheastSeatLight", Vector3(0.64, 0.44, -0.64), RIM_COOL_DAYLIGHT, (RIM_ENERGY if quality > 0 else 0.0) * local_energy, 1.72)
	_configure_overhead(stage, quality, local_energy)
	# This filter is global in Godot. Restore the renderer's platform default
	# when the Mahjong stage exits, rather than leaking it into another game.
	if not stage.has_meta("mahjong_shadow_filter_owner"):
		stage.set_meta("mahjong_shadow_filter_owner", true)
		var previous := int(ProjectSettings.get_setting_with_override("rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality"))
		stage.tree_exiting.connect(func(): RenderingServer.positional_soft_shadow_filter_set_quality(previous))
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW if quality == 0 else RenderingServer.SHADOW_QUALITY_SOFT_LOW)


static func configure_viewport(viewport: SubViewport, quality: int) -> void:
	quality = clampi(quality, 0, 2)
	viewport.msaa_3d = [Viewport.MSAA_2X, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]
	viewport.anisotropic_filtering_level = Viewport.ANISOTROPY_8X if quality == 2 else Viewport.ANISOTROPY_4X
	viewport.positional_shadow_atlas_size = [1024, 2048, 4096][quality]
	# One quadrant / one map => actual spot resolution 512 / 1024 / 2048.
	viewport.positional_shadow_atlas_quad_0 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_1
	viewport.positional_shadow_atlas_quad_1 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_DISABLED
	viewport.positional_shadow_atlas_quad_2 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_DISABLED
	viewport.positional_shadow_atlas_quad_3 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_DISABLED


static func _configure_overhead(stage: Node3D, quality: int, energy_scale: float) -> void:
	var spot := stage.get_node_or_null("OverheadTableLight") as SpotLight3D
	if spot == null:
		spot = SpotLight3D.new()
		spot.name = "OverheadTableLight"
		stage.add_child(spot)
	spot.position = KEY_POSITION
	spot.look_at(Vector3(0.0, 0.0, 0.0))
	spot.light_color = KEY_4800K
	spot.light_energy = KEY_ENERGY * energy_scale
	spot.light_specular = 0.39
	spot.spot_range = 2.7
	spot.spot_angle = 55.0
	spot.spot_attenuation = 0.45
	spot.spot_angle_attenuation = 0.55
	spot.light_size = 0.0 # Explicit PCF, no per-fragment PCSS search on mobile.
	spot.shadow_enabled = true
	spot.shadow_blur = 1.30 if quality > 0 else 1.12
	spot.shadow_opacity = 0.64
	spot.shadow_bias = 0.012
	spot.shadow_normal_bias = 0.16


static func _configure_fill(stage: Node3D, light_name: String, location: Vector3, tint: Color, energy: float, radius: float) -> void:
	var light := stage.get_node_or_null(light_name) as OmniLight3D
	if light == null:
		light = OmniLight3D.new()
		light.name = light_name
		stage.add_child(light)
	light.position = location
	light.omni_range = radius
	light.omni_attenuation = 1.30
	light.light_color = tint
	light.light_energy = energy
	light.light_specular = 0.32
	light.shadow_enabled = false
	light.visible = energy > 0.0


static func _studio_reflection(quality: int) -> Sky:
	var resolution := 256 if quality == 2 else 128
	if _reflection_skies.has(resolution): return _reflection_skies[resolution]
	if _reflection_panorama == null:
		# Two broad softboxes and a subdued ceiling; this is static HDR lighting
		# data, not a captured scene. No moving cards or per-frame probe updates.
		var pixels := Image.create(256, 128, false, Image.FORMAT_RGBF)
		for y in 128:
			for x in 256:
				var uv := Vector2((x + 0.5) / 256.0, (y + 0.5) / 128.0)
				var ceiling := 1.0 - smoothstep(0.35, 0.65, uv.y)
				var warm_box := exp(-pow((uv.x-0.22)/0.12,4.0)-pow((uv.y-0.31)/0.13,4.0))
				var cool_box := exp(-pow((uv.x-0.72)/0.16,4.0)-pow((uv.y-0.24)/0.09,4.0))
				pixels.set_pixel(x,y,Color(0.035,0.030,0.025).lerp(Color(0.16,0.18,0.21),ceiling)+Color(1.20,1.04,0.84)*warm_box+Color(0.50,0.59,0.72)*cool_box)
		_reflection_panorama = ImageTexture.create_from_image(pixels)
	var material := PanoramaSkyMaterial.new()
	material.panorama = _reflection_panorama
	var sky := Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_256 if quality == 2 else Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	sky.sky_material = material
	_reflection_skies[resolution] = sky
	return sky


static func finish_table(table: Node3D) -> void:
	var frame := table.find_child("SM_Mahjong_Table_Frame_RoundedAlloy", true, false) as MeshInstance3D
	var felt := table.find_child("Mahjong_Felt_Surface", true, false) as MeshInstance3D
	if frame != null:
		var wood := ShaderMaterial.new()
		wood.shader = WOOD_SHADER
		wood.set_shader_parameter("wood_albedo", WOOD_ALBEDO)
		# Preserve the RGB of the user's walnut reference. Lighting/clearcoat
		# supplies the volume; no orange tint is mixed back into the wood.
		wood.set_shader_parameter("wood_color", Color.WHITE)
		frame.mesh = _wooden_rail_mesh()
		frame.material_override = wood

	if felt != null:
		var textile := ShaderMaterial.new()
		textile.shader = FELT_SHADER
		textile.set_shader_parameter("felt_color", FELT_COLOR)
		felt.scale = Vector3(FELT_SCALE, 1.0, FELT_SCALE)
		felt.material_override = textile

	var inlay := table.find_child("Frame_GoldInlay_RoundedContinuous", true, false) as MeshInstance3D
	if inlay != null:
		inlay.hide()

	# The UI projects live wind labels and timer over the center of the table.
	for controller in table.find_children("Controller_*", "MeshInstance3D", true, false):
		controller.hide()


static func _wooden_rail_mesh() -> ArrayMesh:
	if _rail_mesh != null:
		return _rail_mesh
	var rings: Array[PackedVector3Array] = []
	for cross_section: Vector3 in RAIL_PROFILE:
		var ring := PackedVector3Array()
		var center := cross_section.x - cross_section.z
		for corner: Vector2 in [Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]:
			var start := corner.angle() - PI * 0.25
			for step in range(CORNER_STEPS + 1):
				var angle := start + float(step) * PI * 0.5 / float(CORNER_STEPS)
				var edge := corner * center + Vector2.from_angle(angle) * cross_section.z
				ring.append(Vector3(edge.x, cross_section.y, edge.y))
		rings.append(ring)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(rings.size()):
		var current := rings[index]
		var following := rings[(index + 1) % rings.size()]
		for point in range(current.size()):
			var next := (point + 1) % current.size()
			for vertex in [current[point], current[next], following[point], current[next], following[next], following[point]]:
				surface.add_vertex(vertex)
	surface.generate_normals()
	surface.index()
	_rail_mesh = surface.commit()
	return _rail_mesh
