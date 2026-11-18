extends RefCounted
## The borderless felt surface and lighting for the Mahjong table.

const FELT_SHADER := preload("res://modules/games/mahjong/guiyang/club_felt.gdshader")
const FELT_PILE := preload("res://modules/games/mahjong/guiyang/assets/models/textures/T_Mahjong_Felt_Pile.png")
const CREAM := Color("#fff0d7")
const MUTED := Color("#e0c3a0")
const BRASS := Color("#ab7f50")
const FELT_SIZE_METRES := Vector2.ONE * (1.35 + 2.0 * 2.0)
const FELT_COLOR := Color("#223b2b")
const KEY_POSITION := Vector3(-0.65, 1.29, 0.54)
const KEY_WARM_WHITE := Color("#ffefdc")
const FILL_WHITE := Color("#f3f8ff")
const RIM_COOL_DAYLIGHT := Color("#d5eaff")
const KEY_ENERGY := 1.43
const FILL_ENERGY := 0.50
const RIM_ENERGY := 0.40
static var _reflection_panorama: ImageTexture
static var _reflection_skies: Dictionary = {}


static func configure_stage(stage: Node3D, quality: int) -> void:
	var compatibility := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	# The compatibility backend has less headroom before ivory highlights clip.
	var local_energy := 0.33 if compatibility else 1.0
	var environment := (stage.get_node("WorldEnvironment") as WorldEnvironment).environment
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#e4edf5")
	environment.ambient_light_energy = 0.14 if compatibility else 0.25
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.sky = _studio_reflection(quality)
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR if compatibility else Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.0 if compatibility else 1.02
	environment.tonemap_white = 2.22
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
	# The front fill opens the upright hand. The cooler rear light catches its bevels.
	_configure_fill(stage, "FillLight", Vector3(0.06, 0.53, 0.98), FILL_WHITE, FILL_ENERGY * local_energy, 1.80, 0.12)
	_configure_fill(stage, "NortheastSeatLight", Vector3(0.65, 0.63, -0.64), RIM_COOL_DAYLIGHT, (RIM_ENERGY if quality > 0 else 0.0) * local_energy, 1.86, 0.30)
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
	# All tiers keep native pixels. Budget changes affect shadows/MSAA only.
	viewport.scaling_3d_scale = 1.0
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = false
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
	spot.light_color = KEY_WARM_WHITE
	spot.light_energy = KEY_ENERGY * energy_scale
	spot.light_specular = 0.18
	spot.spot_range = 2.7
	spot.spot_angle = 60.0
	spot.spot_attenuation = 0.52
	spot.spot_angle_attenuation = 0.50
	spot.light_size = 0.0 # Explicit PCF, no per-fragment PCSS search on mobile.
	spot.shadow_enabled = true
	spot.shadow_blur = 1.58 if quality > 0 else 1.20
	spot.shadow_opacity = 0.70
	spot.shadow_bias = 0.012
	spot.shadow_normal_bias = 0.16


static func _configure_fill(stage: Node3D, light_name: String, location: Vector3, tint: Color, energy: float, radius: float, specular: float) -> void:
	var light := stage.get_node_or_null(light_name) as OmniLight3D
	if light == null:
		light = OmniLight3D.new()
		light.name = light_name
		stage.add_child(light)
	light.position = location
	light.omni_range = radius
	light.omni_attenuation = 1.20
	light.light_color = tint
	light.light_energy = energy
	light.light_specular = specular
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


static func create_felt_surface() -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = FELT_SIZE_METRES
	var textile := ShaderMaterial.new()
	textile.shader = FELT_SHADER
	textile.set_shader_parameter("felt_color", FELT_COLOR)
	textile.set_shader_parameter("pile_map", FELT_PILE)
	var felt := MeshInstance3D.new()
	felt.name = "Mahjong_Felt_Surface"
	felt.mesh = plane
	felt.material_override = textile
	felt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return felt
