extends SceneTree
## Render all 27 real tile faces twice: hand PBR and river/meld PBR.
const MODEL := preload("res://modules/games/mahjong/guiyang/real_tile_model.gd")
const MATERIALS := preload("res://modules/games/mahjong/guiyang/real_tile_materials.gd")
const NATIVE := preload("res://modules/game_framework/tabletop3d/native_3d_view.gd")
var failed := false
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
func _run() -> void:
	Engine.max_fps = 0
	if DisplayServer.get_name() != "headless": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1800,1260)
	root.content_scale_size = Vector2i.ZERO
	var view := NATIVE.new()
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var world := Node3D.new()
	view.viewport.add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.65
	camera.position = Vector3(0,2,0.001)
	camera.look_at(Vector3.ZERO, Vector3(0,0,-1))
	camera.current = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("172b25")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-75,-20,0)
	light.light_energy = 0.8
	world.add_child(light)
	var mats := MATERIALS.new()
	var cases := []
	for group in 2:
		for row in 3:
			var suit: String = ["wan","tiao","tong"][row]
			for rank in range(1,10):
				var id := ["wan","tong","tiao"].find(suit)*36+(rank-1)*4+1
				var tile := {"id":id,"suit":suit,"rank":rank}
				var model := MODEL.build(mats,tile,false,group==1)
				world.add_child(model)
				model.position = Vector3((rank-5)*0.083,0,(group*3+row-2.5)*0.100)
				var hand: StandardMaterial3D = mats.face(tile)
				var river: ShaderMaterial = mats.tabletop_face(tile)
				var expected := Vector2((160.0+(rank-1)*896.0)/8192.0,row*0.25)
				_check(Vector2(hand.uv1_offset.x,hand.uv1_offset.y).is_equal_approx(expected),"Wrong hand cell: "+str(tile))
				_check(river.get_shader_parameter("atlas_origin").is_equal_approx(expected),"Wrong river cell: "+str(tile))
				var face := model.find_child("TileFace",true,false) as MeshInstance3D
				for surface in face.mesh.get_surface_count():
					for uv in face.mesh.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV]:
						_check(uv.x>=-0.001 and uv.x<=1.001 and uv.y>=-0.001 and uv.y<=1.001,"Face UV escapes its cell")
				cases.append({"mode":"hand" if group==0 else "river_meld","id":id,"suit":suit,"rank":rank,"origin":[expected.x,expected.y]})
	await process_frame
	view.sync_native_size()
	for group in 2:
		for row in 3:
			for rank in range(1,10):
				var label := Label.new()
				root.add_child(label)
				label.text = "%s %s%d" % ["HAND" if group==0 else "RIVER", ["wan","tiao","tong"][row],rank]
				label.add_theme_font_size_override("font_size",18)
				label.position = camera.unproject_position(Vector3((rank-5)*0.083,0.032,(group*3+row-2.5)*0.100+0.036))-Vector2(57,0)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			var path := arg.trim_prefix("--output=")
			if DisplayServer.get_name() != "headless":
				for frame in 5: await process_frame
				await RenderingServer.frame_post_draw
				_check(root.get_texture().get_image().save_png(path+".png")==OK,"Native gallery save failed")
			var file := FileAccess.open(path+".json",FileAccess.WRITE)
			file.store_string(JSON.stringify({"passed":not failed,"cases":cases,"render_size":str(view.viewport.size)},"\t"))
	print("MAHJONG_FACE_MAPPING_OK 27 kinds x 2 materials" if not failed else "MAHJONG_FACE_MAPPING_FAILED")
	view.queue_free()
	await process_frame
	quit(1 if failed else 0)
