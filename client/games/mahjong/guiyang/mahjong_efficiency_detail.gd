extends Control
## One preview camera renders the table's actual tile meshes for this detail panel.

signal dismissed

const MODAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_modal.gd")
const TILE_MODEL := preload("res://modules/games/mahjong/guiyang/real_tile_model.gd")
const MATERIALS := preload("res://modules/games/mahjong/guiyang/real_tile_materials.gd")
const CELL := Vector2(97, 112)
const WORLD_PER_PIXEL := 0.00090

var tile_materials: RefCounted
var _frame: PanelContainer
var _summary: Label
var _note: Label
var _scroll: ScrollContainer
var _tray: Control
var _viewport: SubViewport
var _camera: Camera3D
var _tile_root: Node3D
var _models: Array[Node3D] = []
var _captions: Array[Label] = []
var _entries: Array[Dictionary] = []
var _area := Rect2()


func _ready() -> void:
	name = "MahjongEfficiencyDetail"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tile_materials == null: tile_materials = MATERIALS.new()
	_frame = MODAL.village_panel(self)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	_frame.add_child(content)
	var heading := HBoxContainer.new()
	content.add_child(heading)
	var balance := Control.new()
	heading.add_child(balance)
	var title_area := CenterContainer.new()
	title_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title_area)
	MODAL.village_title(title_area, "进张明细", _frame)
	var close := Button.new()
	close.name = "MahjongCloseEfficiencyDetail"
	close.accessibility_name = "关闭进张明细"
	close.tooltip_text = close.accessibility_name
	MODAL.close_button(close)
	heading.add_child(close)
	balance.custom_minimum_size.x = MODAL.size_icon_button(close, close)
	close.pressed.connect(_dismiss)

	_summary = _label(content, 18)
	_summary.name = "MahjongEfficiencySummary"
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	content.add_child(_scroll)
	_tray = Control.new()
	_tray.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tray.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(_tray)
	_build_preview()
	_note = _label(content, 15)
	_note.add_theme_color_override("font_color", MODAL.MUTED)
	_frame.minimum_size_changed.connect(func(): _place_panel.call_deferred())
	_tray.resized.connect(func(): _place_tiles.call_deferred())
	hide()


func show_result(summary: String, entries: Array[Dictionary], note: String, area: Rect2) -> void:
	_area = area
	_summary.text = summary
	_note.text = note
	_note.visible = not note.is_empty()
	_scroll.visible = not entries.is_empty()
	if entries != _entries:
		_set_tiles(entries)
	show()
	_place_panel()
	_place_tiles.call_deferred()


func _dismiss() -> void:
	hide()
	dismissed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel", false):
		get_viewport().set_input_as_handled()
		_dismiss()


func _label(parent: Control, font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", MODAL.village_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", MODAL.INK)
	parent.add_child(label)
	return label


func _build_preview() -> void:
	var projection := preload("res://modules/game_framework/tabletop3d/native_3d_view.gd").new()
	projection.name = "MahjongEffectiveTilePreview"
	projection.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tray.add_child(projection)
	projection.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport = projection.viewport
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	projection.projection_resized.connect(_place_tiles)

	_camera = Camera3D.new()
	_camera.position = Vector3(0, 0, 1)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	_viewport.add_child(_camera)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-24, -33, 0)
	key.light_color = Color("#fff4df")
	key.light_energy = 1.0
	_viewport.add_child(key)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("#f7efdd")
	environment.environment.ambient_light_energy = 0.82
	_viewport.add_child(environment)
	_tile_root = Node3D.new()
	_tile_root.name = "MahjongEffectiveTileModels"
	_viewport.add_child(_tile_root)


func _set_tiles(entries: Array[Dictionary]) -> void:
	for item in _models:
		_tile_root.remove_child(item)
		item.queue_free()
	for caption in _captions:
		_tray.remove_child(caption)
		caption.queue_free()
	_models.clear()
	_captions.clear()
	_entries = entries.duplicate(true)
	for entry in entries:
		var model := TILE_MODEL.build(tile_materials, entry)
		model.name = "MahjongEffectiveTile_%s_%d" % [entry.suit, entry.rank]
		model.rotation_degrees = Vector3(76, -11, -5)
		model.scale = Vector3.ONE * 1.04
		_tile_root.add_child(model)
		_models.append(model)
		var count := _label(_tray, 15)
		count.name = "EffectiveTileCount%d" % _captions.size()
		count.text = "%s  %d 张" % [entry.title, entry.count]
		_captions.append(count)
	_scroll.scroll_vertical = 0


func _place_panel() -> void:
	if not visible or not _area.has_area(): return
	var width := minf(_area.size.x - 22.0, clampf(_area.size.x * 0.58, 400.0, 720.0))
	var columns := _column_count(width - 92.0)
	var rows := ceili(float(_entries.size()) / columns)
	_scroll.custom_minimum_size.y = minf(rows * CELL.y, maxf(CELL.y, minf(2 * CELL.y, _area.size.y * 0.33)))
	_frame.size = Vector2(maxf(1.0, width), 0.0)
	_frame.position = _area.get_center() - _frame.size * 0.5


func _column_count(width: float) -> int:
	return clampi(floori(width / CELL.x), 1, 6)


func _place_tiles() -> void:
	if not visible or _models.is_empty() or _tray.size.x <= 1.0: return
	var columns := _column_count(_tray.size.x)
	var height := ceili(float(_models.size()) / columns) * CELL.y
	_tray.custom_minimum_size.y = height
	_camera.size = maxf(CELL.y, height) * WORLD_PER_PIXEL
	for index in _models.size():
		var row := floori(float(index) / columns)
		var in_row := mini(columns, _models.size() - row * columns)
		var start := (_tray.size.x - in_row * CELL.x) * 0.5
		var cell := Vector2(start + (index % columns) * CELL.x, row * CELL.y)
		var center := cell + Vector2(CELL.x * 0.5, 46.0)
		_models[index].position = Vector3((center.x - _tray.size.x * 0.5) * WORLD_PER_PIXEL,
			(height * 0.5 - center.y) * WORLD_PER_PIXEL, 0)
		_captions[index].position = cell + Vector2(0, 86)
		_captions[index].size = Vector2(CELL.x, 24)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
