extends Container
## Places a noninteractive title plaque across the upper border of a panel.

var _plate: PanelContainer
var _frame: PanelContainer


func setup(plate: PanelContainer, frame: PanelContainer) -> void:
	_plate = plate
	_frame = frame
	mouse_filter = MOUSE_FILTER_IGNORE
	size_flags_horizontal = SIZE_SHRINK_CENTER
	_plate.mouse_filter = MOUSE_FILTER_IGNORE
	_plate.z_index = 1
	add_child(_plate)
	_plate.minimum_size_changed.connect(_title_layout_changed)
	_frame.item_rect_changed.connect(_title_layout_changed)
	item_rect_changed.connect(queue_sort)
	_title_layout_changed()


func _get_minimum_size() -> Vector2:
	if _plate == null:
		return Vector2.ZERO
	var plate_size := _plate.get_combined_minimum_size()
	var frame_inset := _frame.get_theme_stylebox("panel").get_content_margin(SIDE_TOP)
	var border_offset := float(_frame.get_meta("title_border_offset", 0))
	return Vector2(plate_size.x, maxf(0.0, border_offset + plate_size.y * 0.5 - frame_inset))


func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN or _plate == null:
		return
	var plate_size := _plate.get_combined_minimum_size()
	var frame_rect := _frame.get_global_rect()
	var border_offset := float(_frame.get_meta("title_border_offset", 0))
	var target_center := Vector2(frame_rect.get_center().x, frame_rect.position.y + border_offset)
	var local_origin := get_global_transform().affine_inverse() * target_center - plate_size * 0.5
	fit_child_in_rect(_plate, Rect2(local_origin, plate_size))


func _title_layout_changed() -> void:
	update_minimum_size()
	queue_sort()
