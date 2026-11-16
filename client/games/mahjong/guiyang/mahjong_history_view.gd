extends VBoxContainer

const MODAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_modal.gd")

signal action_requested(action: String, payload: Dictionary)

const RURAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_theme.gd")
const REPLAY_VIEW := preload("res://modules/games/mahjong/guiyang/mahjong_replay_view.gd")
const MODES := {"quick": "快速匹配", "friend": "好友房", "training": "人机训练"}

var _list: VBoxContainer
var _rows_box: VBoxContainer
var _rows: Array = []
var _detail: VBoxContainer
var _summary: Label
var _breakdown: Label
var _message: Label
var _retry: Button
var _more: Button
var _replay_button: Button
var _replay_view: Control
var _replay_back: Button
var _replay_page: VBoxContainer


func _ready() -> void:
	name = "MahjongHistoryPage"
	add_theme_constant_override("separation", 10)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	add_child(header)
	_button(header, "MahjongHistoryBackButton", "‹  返回大厅", "history_back")
	var title := _label(header, "个人战绩", 34, RURAL.CREAM)
	title.add_theme_font_override("font", RURAL.title_font())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MODAL.paper_frame(Vector4(21, 20, 21, 20)))
	add_child(panel)
	var padding := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		padding.add_theme_constant_override("margin_" + side, 19)
	panel.add_child(padding)
	var body := _column(padding, 12)
	_list = _column(body, 10)
	_rows_box = _column(_list, 7)
	_more = _button(_list, "MahjongHistoryMoreButton", "加载更多", "history_more")
	_detail = _column(body, 13)
	var back := _button(_detail, "MahjongHistoryDetailBackButton", "‹  返回战绩", "history_detail_back")
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_summary = _label(_detail, "", 27, RURAL.INK)
	_breakdown = _label(_detail, "", 22, RURAL.INK)
	_breakdown.name = "MahjongHistoryBreakdown"
	_breakdown.add_theme_constant_override("line_spacing", 10)
	_replay_button = _button(_detail, "MahjongHistoryReplayButton", "逐步复盘   ›", "history_replay")
	_replay_page = _column(body, 12)
	_replay_back = _button(_replay_page, "MahjongReplayBackButton", "‹  返回单局明细", "history_replay_back")
	_replay_back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_replay_view = REPLAY_VIEW.new()
	_replay_page.add_child(_replay_view)
	_message = _label(body, "", 19, Color("#815431"))
	_retry = _button(body, "MahjongHistoryRetryButton", "重试", "history_retry")


func apply(data: Dictionary) -> void:
	var match_id := str(data.get("match_id", ""))
	var loading := bool(data.get("loading", false))
	var error := str(data.get("error", ""))
	var rows: Array = data.get("rows", [])
	var replay_open := bool(data.get("replay_open", false))
	_list.visible = match_id.is_empty()
	_detail.visible = not _list.visible and not replay_open
	_replay_page.visible = replay_open
	var replay: Dictionary = data.get("replay", {})
	_replay_view.visible = replay_open and not replay.is_empty()
	_replay_view.apply(replay if _replay_view.visible else {})
	if rows != _rows:
		_set_rows(rows)
	_more.visible = bool(data.get("more", false))
	_more.disabled = loading
	var detail: Dictionary = data.get("detail", {})
	_summary.visible = _detail.visible and not detail.is_empty()
	_breakdown.visible = _summary.visible
	_replay_button.visible = _summary.visible
	if _summary.visible:
		_summary.text = "%s  ·  %s\n%s   %s 分" % [detail.name, MODES.get(detail.kind, "麻将"), detail.result, _signed(detail.score)]
		_summary.text += "\n实际鸡蛋收支  %s 鸡蛋" % _signed(int(detail.egg_delta)) if detail.has("egg_delta") else "\n未记录鸡蛋收支" if detail.kind != "training" else "\n练习不计鸡蛋"
		if not str(detail.get("finished_at", "")).is_empty():
			_summary.text += "\n" + _time_label(detail.finished_at)
		var scores: Dictionary = detail.get("breakdown", {})
		_breakdown.text = "这局没有分项记录" if scores.is_empty() else "胡分  %s\n杠分  %s\n鸡分  %s" % [
			_signed(scores.hu), _signed(scores.gang), _signed(scores.ji)]
	_message.text = "加载中……" if loading else error if not error.is_empty() else "还没有已结算的牌局" if _list.visible and rows.is_empty() else ""
	_message.visible = not _message.text.is_empty()
	_retry.visible = not loading and not error.is_empty()


func _set_rows(rows: Array) -> void:
	_rows = rows
	for child in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	for record: Dictionary in rows:
		var id := str(record.match_id)
		var row := _button(_rows_box, "MahjongHistoryMatch_" + id.validate_node_name(), "", "history_match", {"match_id": id})
		row.custom_minimum_size.y = 80
		var padding := MarginContainer.new()
		padding.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(padding)
		padding.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side in ["left", "right", "top", "bottom"]:
			padding.add_theme_constant_override("margin_" + side, 13)
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		padding.add_child(line)
		var copy := _column(line, 4)
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var title := _label(copy, str(record.get("name", "贵阳麻将")), 21, RURAL.INK)
		title.autowrap_mode = TextServer.AUTOWRAP_OFF
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var subtitle := "%s · %s" % [MODES.get(record.get("kind"), "麻将"), record.get("result", "已结算")]
		if record.has("egg_delta"): subtitle += " · 鸡蛋 " + _signed(int(record.egg_delta))
		if not str(record.get("finished_at", "")).is_empty():
			subtitle += " · " + _time_label(record.finished_at)
		var meta := _label(copy, subtitle, 16, Color("#6e543d"))
		meta.autowrap_mode = TextServer.AUTOWRAP_OFF
		meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var points := _label(line, "%s 分  ›" % _signed(int(record.get("score", 0))), 23, Color("#596e4c"))
		points.autowrap_mode = TextServer.AUTOWRAP_OFF


func _button(parent: Control, node_name: String, caption: String, action: String, payload: Dictionary = {}) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = caption
	button.custom_minimum_size.y = 57
	RURAL.skin_button(button)
	button.pressed.connect(func() -> void: action_requested.emit(action, payload))
	parent.add_child(button)
	return button


func _column(parent: Control, spacing: int) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", spacing)
	parent.add_child(column)
	return column


func _label(parent: Control, caption: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = caption
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _time_label(value: String) -> String:
	return value.left(16).replace("T", " ") + " UTC" if value.ends_with("Z") else value


func _signed(score: int) -> String:
	return "+%d" % score if score > 0 else str(score)
