extends SceneTree
## Native GLB/color-channel/PBR checks and a runtime product close-up.

const TILE_SCENE = preload("res://modules/games/mahjong/guiyang/assets/models/mahjong_tile.glb")
const MODEL = preload("res://modules/games/mahjong/guiyang/real_tile_model.gd")
const MATERIALS = preload("res://modules/games/mahjong/guiyang/real_tile_materials.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.content_scale_size = Vector2i(1440, 810)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.msaa_3d = Viewport.MSAA_4X
	var materials := MATERIALS.new()
	var stage := Node3D.new()
	root.add_child(stage)
	var prototype := TILE_SCENE.instantiate() as Node3D
	var body := prototype.find_child("TileBody", true, false) as MeshInstance3D
	var face := prototype.find_child("TileFace", true, false) as MeshInstance3D
	assert(body != null and face != null and prototype.find_child("TileBack", true, false) == null)
	var bounds := body.get_aabb()
	assert(bounds.size.is_equal_approx(Vector3(0.039, 0.028, 0.056)))
	var colors: PackedColorArray = body.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var minimum := 1.0
	var maximum := 0.0
	for color in colors:
		minimum = minf(minimum, color.r)
		maximum = maxf(maximum, color.r)
	assert(minimum < 0.01 and maximum > 0.99, "Authored green mask must be COLOR_0")
	prototype.free()
	var live := MODEL.build(materials, {"suit":"wan","rank":5})
	stage.add_child(live)
	for part in ["TileBody", "TileFace"]:
		var mesh := live.find_child(part, true, false) as MeshInstance3D
		assert(mesh.global_basis.is_equal_approx(Basis.IDENTITY), "The native size must survive the full scene hierarchy")
	live.free()
	var first_texture: Texture2D
	for suit in ["wan", "tiao", "tong"]:
		for rank in range(1, 10):
			var mat: StandardMaterial3D = materials.face({"suit":suit,"rank":rank})
			assert(mat.normal_enabled and mat.ao_enabled and mat.clearcoat_enabled)
			assert(mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED)
			assert(mat.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GREEN)
			assert(is_same(mat, materials.face({"suit":suit,"rank":rank})))
			if first_texture == null: first_texture = mat.albedo_texture
			assert(is_same(first_texture, mat.albedo_texture), "Tiles must share atlas, not copy 27 textures")
	assert(materials.face({}).albedo_texture == null)
	assert(materials.face({"suit":"wan","rank":10}).albedo_texture == null)
	print("REAL_MAHJONG_NATIVE_PBR_OK height_width_thickness_mm=56x39x28 unit_scale=true mask_COLOR0=true shared_27_faces=true hidden_face_blank=true")
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#233e39")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#eef5ee")
	env.ambient_light_energy = 0.4
	env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	env_node.environment = env
	stage.add_child(env_node)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55,-30,0)
	key.light_energy = 0.9
	key.shadow_enabled = true
	stage.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0.1,0.15,0.1)
	fill.omni_range = 1.0
	fill.light_energy = 0.16
	stage.add_child(fill)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(2,2)
	var ground := MeshInstance3D.new()
	ground.mesh = floor_mesh
	var felt := StandardMaterial3D.new()
	felt.albedo_color = Color("#236744")
	felt.roughness = 0.92
	ground.material_override = felt
	ground.position.y = -0.0002
	stage.add_child(ground)
	for index in range(4):
		var tile := TILE_SCENE.instantiate() as Node3D
		stage.add_child(tile)
		tile.position = [Vector3(-0.055,0,0.005),Vector3(0,0,-0.015),Vector3(0.055,0,0.005),Vector3(0.005,MODEL.SIZE.y,-0.08)][index]
		tile.rotation_degrees.y = [-9,2,8,-7][index]
		(tile.find_child("TileBody", true, false) as MeshInstance3D).material_override = materials.body()
		(tile.find_child("TileFace", true, false) as MeshInstance3D).material_override = materials.face([{"suit":"wan","rank":5},{"suit":"tiao","rank":9},{"suit":"tong","rank":1},{}][index])
		if index == 3: tile.rotation.x = PI
	var camera := Camera3D.new()
	camera.position = Vector3(0.08,0.20,0.23)
	camera.fov = 36
	camera.near = 0.005
	stage.add_child(camera)
	camera.look_at(Vector3(0,0.01,-0.028))
	for frame in range(6): await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		assert(not picture.is_empty())
		picture.save_png("res://../../../artifacts/mahjong_models/real_mahjong_native_closeup.png")
	print("REAL_MAHJONG_NATIVE_SMOKE_OK")
	quit(0)
