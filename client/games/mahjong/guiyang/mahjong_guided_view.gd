extends VBoxContainer

const MODAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_modal.gd")

signal back_requested

const RURAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_theme.gd")
const TILE_SCENE := preload("res://modules/games/mahjong/guiyang/assets/models/mahjong_tile.glb")
const TILE_MATERIALS := preload("res://modules/games/mahjong/guiyang/real_tile_materials.gd")
const ACTION_LABELS := {"discard": "打出", "peng": "碰", "gang": "杠", "hu": "胡", "pass": "过"}
const LESSONS := [
	{
		"title": "选牌与打出", "example": "当前轮到你 · 手牌节选",
		"hint": "先点击选中八筒，再点一次八筒或点「打出」。第一次点击只选牌。",
		"hand": ["二万", "五条", "八筒", "九万"],
		"tiles": [{"suit":"wan","rank":2}, {"suit":"tiao","rank":5}, {"suit":"tong","rank":8}, {"suit":"wan","rank":9}],
		"choice": "discard",
	},
	{
		"title": "碰牌", "example": "其他玩家打出 · 三筒",
		"hint": "你手里有两张三筒，可以碰这张牌。碰后亮出三张同样的牌，再由你打出一张。贵阳麻将不吃牌。",
		"hand": ["三筒", "三筒"], "tiles": [{"suit":"tong","rank":3}, {"suit":"tong","rank":3}],
		"choice": "peng",
	},
	{
		"title": "选择过牌", "example": "其他玩家打出 · 六万",
		"hint": "你手上有一对六万，可以碰。即使来牌凑齐胡牌，默认贵阳捉鸡也要求先完成一个杠才能点炮胡。这次选择「过」。自摸无需先杠。",
		"hand": ["六万", "六万"], "tiles": [{"suit":"wan","rank":6}, {"suit":"wan","rank":6}],
		"choice": "pass",
	},
	{
		"title": "完成暗杠", "example": "当前轮到你 · 四张七条",
		"hint": "四张同样的七条都在自己手中。选择「杠」完成暗杠，实际牌局会补一张牌。",
		"hand": ["七条", "七条", "七条", "七条"],
		"tiles": [{"suit":"tiao","rank":7}, {"suit":"tiao","rank":7}, {"suit":"tiao","rank":7}, {"suit":"tiao","rank":7}],
		"choice": "gang",
	},
	{
		"title": "点炮胡牌", "example": "其他玩家打出 · 五筒",
		"hint": "这次你已经完成了杠。其他玩家打出的五筒补齐了将牌，选择「胡」完成练习。",
		"hand": ["五筒"], "tiles": [{"suit":"tong","rank":5}],
		"choice": "hu",
	},
]

var _step := 0
var _selected := -1
var _feedback_text := ""
var _progress: Label
var _title: Label
var _instruction: Label
var _example: Label
var _feedback: Label
var _preview: SubViewportContainer
var _viewport: SubViewport
var _pieces: Node3D
var _tiles_row: HBoxContainer
var _tile_buttons: Array[Button] = []
var _actions: Dictionary[String, Button] = {}
var _restart: Button
var _materials := TILE_MATERIALS.new()


func _ready() -> void:
	name = "MahjongGuidedPage"
	add_theme_constant_override("separation", 12)
	var toolbar := HBoxContainer.new()
	add_child(toolbar)
	_button(toolbar, "MahjongGuidedBackButton", "‹  返回训练场", false).pressed.connect(func() -> void: back_requested.emit())
	_progress = _label(toolbar, "", 21)
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_progress.add_theme_color_override("font_color", RURAL.CREAM)

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", MODAL.paper_frame(Vector4(19, 19, 19, 19)))
	add_child(frame)
	var padding := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		padding.add_theme_constant_override("margin_" + side, 18)
	frame.add_child(padding)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 11)
	padding.add_child(content)
	_title = _label(content, "", 32)
	_title.add_theme_font_override("font", RURAL.title_font())
	_instruction = _label(content, "", 23)
	_example = _label(content, "", 20)
	_example.add_theme_color_override("font_color", Color("#5a654b"))
	_build_preview(content)
	_tiles_row = HBoxContainer.new()
	_tiles_row.add_theme_constant_override("separation", 9)
	content.add_child(_tiles_row)
	for index in range(4):
		var tile_button := _button(_tiles_row, "MahjongGuidedTile%d" % (index + 1), "", false)
		tile_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile_button.toggle_mode = true
		tile_button.pressed.connect(_select.bind(index))
		_tile_buttons.append(tile_button)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	content.add_child(controls)
	for action: String in ACTION_LABELS:
		var button := _button(controls, "MahjongGuided%sButton" % action.capitalize(), ACTION_LABELS[action], true)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_perform.bind(action))
		_actions[action] = button
	_feedback = _label(content, "", 20)
	_feedback.add_theme_color_override("font_color", Color("#865335"))
	_restart = _button(content, "MahjongGuidedRestartButton", "再练一次", true)
	_restart.pressed.connect(restart)
	_render()


func _build_preview(parent: Control) -> void:
	var inset := PanelContainer.new()
	inset.add_theme_stylebox_override("panel", RURAL.frame(Color("#35523d"), Color("#a58664"), 15, 1))
	parent.add_child(inset)
	_preview = SubViewportContainer.new()
	_preview.name = "MahjongGuidedTilePreview"
	_preview.stretch = true
	_preview.custom_minimum_size.y = 174
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_child(_preview)
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_preview.add_child(_viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 0.092
	_viewport.add_child(camera)
	camera.position = Vector3(0, 0.34, 0.17)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-57, -19, 0)
	light.light_color = Color("#fff5e7")
	light.light_energy = 1.23
	_viewport.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("#eee7d9")
	environment.environment.ambient_light_energy = 0.75
	_viewport.add_child(environment)
	_pieces = Node3D.new()
	_viewport.add_child(_pieces)
	_preview.resized.connect(_refresh_camera.bind(camera))
	_refresh_camera(camera)


func _refresh_camera(camera: Camera3D) -> void:
	var aspect := maxf(0.2, _preview.size.x / maxf(1.0, _preview.size.y))
	camera.size = maxf(0.092, 0.25 / aspect)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func restart() -> void:
	_step = 0
	_selected = -1
	_feedback_text = ""
	_render()


func _select(index: int) -> void:
	if _step != 0: return
	if index == _selected:
		_perform("discard")
		return
	_selected = index
	_feedback_text = "已选 %s，再点此牌或点「打出」确认。" % LESSONS[0].hand[index]
	_render()


func _perform(action: String) -> void:
	if _step >= LESSONS.size() or _actions[action].disabled or not _actions[action].is_visible_in_tree():
		return
	var lesson: Dictionary = LESSONS[_step]
	if action != lesson.choice:
		_feedback_text = "碰牌是可选操作。这一步练习放弃响应，请点「过」。"
		_render()
		return
	if action == "discard" and _selected != 2:
		_feedback_text = "这一步请打出八筒。重新选一张牌试试。"
		_render()
		return
	var completed := ["已打出八筒。", "已碰三筒。", "已选择过牌。", "已完成暗杠。", "已完成点炮胡牌。"]
	_feedback_text = completed[_step]
	_step += 1
	_selected = -1
	_render()


func _render() -> void:
	var finished := _step >= LESSONS.size()
	_progress.text = "贵阳捉鸡 · %d / %d" % [mini(_step + 1, LESSONS.size()), LESSONS.size()]
	_restart.visible = finished
	_feedback.text = _feedback_text
	_feedback.visible = not _feedback_text.is_empty()
	var lesson: Dictionary = {} if finished else LESSONS[_step]
	_title.text = str(lesson.get("title", "教学完成"))
	_instruction.text = str(lesson.get("hint", "你已练习选牌、打出、碰、过、杠和胡。现在可以回训练场摸打练习，或与电脑牌友完成一局。"))
	_example.text = str(lesson.get("example", ""))
	_example.visible = not finished
	_tiles_row.visible = not finished
	_preview.get_parent().visible = not finished
	var hand: Array = lesson.get("hand", [])
	for index in range(_tile_buttons.size()):
		var tile := _tile_buttons[index]
		tile.visible = index < hand.size()
		if tile.visible:
			tile.text = hand[index]
			tile.disabled = _step != 0
			tile.set_pressed_no_signal(index == _selected)
	for action: String in _actions:
		var visible_actions: Array = ["peng", "hu", "pass"] if _step == 2 else [lesson.get("choice", "")]
		var button := _actions[action]
		button.visible = action in visible_actions
		button.disabled = (action != lesson.get("choice", "") and not (_step == 2 and action == "peng")) or (action == "discard" and _selected < 0)
	_render_tiles(lesson.get("tiles", []))


func _render_tiles(tiles: Array) -> void:
	for child in _pieces.get_children():
		_pieces.remove_child(child)
		child.queue_free()
	for index in range(tiles.size()):
		var model := TILE_SCENE.instantiate() as Node3D
		model.position = Vector3((float(index) - (tiles.size() - 1) * 0.5) * 0.055, 0.008 if _selected == index else 0.0, 0)
		_pieces.add_child(model)
		var face := model.find_child("TileFace", true, false) as MeshInstance3D
		if face != null: face.material_override = _materials.face(tiles[index])
		var body := model.find_child("TileBody", true, false) as MeshInstance3D
		if body != null: body.material_override = _materials.body()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _label(parent: Control, caption: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = caption
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", RURAL.INK)
	parent.add_child(label)
	return label


func _button(parent: Control, node_name: String, caption: String, primary: bool) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = caption
	button.custom_minimum_size.y = 61
	RURAL.skin_button(button, primary)
	parent.add_child(button)
	return button
