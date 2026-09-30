extends Node3D
class_name XbdTabletop3DStage
## XbdTabletop3DStage（小板凳三维桌面舞台）
## 为象棋、麻将、扑克、围棋、军棋等桌面游戏提供统一的三维环境、俯视摄像机与灯光。
## 各具体游戏只创建自己的牌桌/棋盘/棋子模型，不重复搭建渲染基础设施。

const PBR_FACTORY = preload("res://modules/game_framework/tabletop3d/pbr_material_factory.gd")

var camera: Camera3D


func configure(
	view_size: float = 14.0,
	camera_position: Vector3 = Vector3(0.0, 11.5, 8.0),
	camera_target: Vector3 = Vector3.ZERO,
	use_perspective: bool = true,
	fov_degrees: float = 38.0
) -> Camera3D:
	_build_environment()
	_build_lighting()
	_build_floor()

	camera = Camera3D.new()
	camera.name = "TopDownCamera"
	if use_perspective:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = fov_degrees
	else:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = view_size
	camera.position = camera_position
	camera.near = 0.1
	camera.far = 80.0
	add_child(camera)
	camera.look_at(camera_target, Vector3.UP)
	camera.current = true
	return camera


func set_orbit_view(
	azimuth_degrees: float,
	radius: float,
	height: float,
	target: Vector3 = Vector3.ZERO
) -> void:
	# set_orbit_view（环绕俯视视角）用于桌面对坐类游戏。
	# 象棋红/黑双方使用相差180度的方位；麻将四人位可直接使用0/90/180/270度。
	if camera == null:
		return
	var angle := deg_to_rad(azimuth_degrees)
	camera.position = Vector3(
		sin(angle) * radius,
		height,
		cos(angle) * radius
	)
	camera.look_at(target, Vector3.UP)


func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#080706")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#d8c8b8")
	environment.ambient_light_energy = 0.58
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	world_environment.environment = environment
	add_child(world_environment)


func _build_lighting() -> void:
	var key_light := DirectionalLight3D.new()
	key_light.name = "KeyLight"
	key_light.light_color = Color("#fff3d8")
	key_light.light_energy = 2.0
	key_light.shadow_enabled = true
	key_light.rotation_degrees = Vector3(-58.0, -32.0, 0.0)
	add_child(key_light)

	var fill_light := OmniLight3D.new()
	fill_light.name = "FillLight"
	fill_light.light_color = Color("#cfe6ff")
	fill_light.light_energy = 1.0
	fill_light.omni_range = 18.0
	fill_light.position = Vector3(-4.5, 7.5, 4.0)
	add_child(fill_light)


func _build_floor() -> void:
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(36.0, 36.0)

	var floor := MeshInstance3D.new()
	floor.name = "Floor"
	floor.mesh = floor_mesh
	floor.material_override = PBR_FACTORY.create_material(Color("#140d0b"), 0.86, 0.0)
	floor.position.y = -0.72
	add_child(floor)
