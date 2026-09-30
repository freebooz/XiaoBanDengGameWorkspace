extends Control
## GuiyangMahjong3DScreen（贵阳麻将三维表现基线）
## 第一期先建立可复用的 3D 牌桌、麻将牌模型、PBR 材质和俯视摄像机。
## 正式贵阳麻将联网流程后续继续复用同一个 Tabletop3D 公共表现层。

const STAGE_SCRIPT = preload("res://modules/game_framework/tabletop3d/tabletop_stage.gd")
const PBR_FACTORY = preload("res://modules/game_framework/tabletop3d/pbr_material_factory.gd")

var product: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_3d_world()
	_build_hud()


func _build_3d_world() -> void:
	var world := Node3D.new()
	world.name = "Mahjong3DWorld"
	add_child(world)

	var stage = STAGE_SCRIPT.new()
	stage.name = "TabletopStage"
	world.add_child(stage)
	stage.configure(16.8, Vector3(0.0, 13.8, 9.8), Vector3(0.0, 0.0, 0.3))

	var table_material := PBR_FACTORY.create_material(Color("#184d3a"), 0.72, 0.0)
	_create_box(world, "MahjongTable", Vector3(12.2, 0.7, 12.2), Vector3(0.0, -0.45, 0.0), table_material)

	var rail_material := PBR_FACTORY.create_material(Color("#6a351d"), 0.40, 0.06)
	_create_box(world, "RailTop", Vector3(12.6, 0.42, 0.42), Vector3(0.0, -0.02, -6.1), rail_material)
	_create_box(world, "RailBottom", Vector3(12.6, 0.42, 0.42), Vector3(0.0, -0.02, 6.1), rail_material)
	_create_box(world, "RailLeft", Vector3(0.42, 0.42, 12.6), Vector3(-6.1, -0.02, 0.0), rail_material)
	_create_box(world, "RailRight", Vector3(0.42, 0.42, 12.6), Vector3(6.1, -0.02, 0.0), rail_material)

	_build_player_hand(world)
	_build_tile_walls(world)


func _build_player_hand(parent: Node3D) -> void:
	var labels := ["一萬", "二萬", "三萬", "三萬", "四萬", "五萬", "六萬", "七萬", "八萬", "二筒", "三筒", "四筒", "五筒"]
	var start_x := -4.8
	for index in range(labels.size()):
		var tile := _create_tile(labels[index])
		tile.position = Vector3(start_x + float(index) * 0.80, 0.18, 4.55)
		parent.add_child(tile)


func _build_tile_walls(parent: Node3D) -> void:
	for index in range(14):
		var top_tile := _create_tile("")
		top_tile.position = Vector3(-5.2 + float(index) * 0.80, 0.16, -4.7)
		parent.add_child(top_tile)

		var left_tile := _create_tile("")
		left_tile.rotation_degrees.y = 90.0
		left_tile.position = Vector3(-5.0, 0.16, -4.0 + float(index) * 0.62)
		parent.add_child(left_tile)

		var right_tile := _create_tile("")
		right_tile.rotation_degrees.y = 90.0
		right_tile.position = Vector3(5.0, 0.16, -4.0 + float(index) * 0.62)
		parent.add_child(right_tile)


func _create_tile(face_text: String) -> Node3D:
	var root := Node3D.new()

	var tile_mesh := BoxMesh.new()
	tile_mesh.size = Vector3(0.68, 0.30, 0.92)
	var tile_body := MeshInstance3D.new()
	tile_body.mesh = tile_mesh
	tile_body.material_override = PBR_FACTORY.create_material(Color("#f4ead4"), 0.24, 0.0)
	root.add_child(tile_body)

	var back_mesh := BoxMesh.new()
	back_mesh.size = Vector3(0.62, 0.08, 0.86)
	var back := MeshInstance3D.new()
	back.mesh = back_mesh
	back.position.y = -0.18
	back.material_override = PBR_FACTORY.create_material(Color("#2f8d68"), 0.34, 0.02)
	root.add_child(back)

	if face_text != "":
		var label := Label3D.new()
		label.text = face_text
		label.font_size = 48
		label.outline_size = 4
		label.pixel_size = 0.006
		label.position.y = 0.17
		label.rotation_degrees.x = -90.0
		label.modulate = Color("#9d2f25")
		label.outline_modulate = Color("#fff5de")
		root.add_child(label)

	return root


func _build_hud() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	panel.custom_minimum_size = Vector2(360, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var title := Label.new()
	title.text = "小板凳麻将 · 贵阳麻将 · 3D PBR"
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)

	var status := Label.new()
	status.text = "三维牌桌表现基线：麻将牌/牌桌/PBR材质/俯视摄像机已启用。\n联网摸牌、出牌、碰杠胡将在同一3D框架继续实现。"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(330, 72)
	box.add_child(status)


func _create_box(
	parent: Node3D,
	node_name: String,
	size: Vector3,
	position_value: Vector3,
	material: Material
) -> MeshInstance3D:
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = box_mesh
	instance.position = position_value
	instance.material_override = material
	parent.add_child(instance)
	return instance
