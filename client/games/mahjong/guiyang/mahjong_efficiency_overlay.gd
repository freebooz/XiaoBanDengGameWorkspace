extends Control
## The badge buttons inspect analysis without selecting or playing a 3D tile.

const BADGE := preload("res://modules/games/mahjong/guiyang/tile_efficiency_badge.gd")
const THEME := preload("res://modules/games/mahjong/guiyang/mahjong_rural_theme.gd")
const NUMERALS := ["一", "二", "三", "四", "五", "六", "七", "八", "九"]
const SUITS := ["万", "筒", "条"]
const HONORS := ["东", "南", "西", "北", "中", "发", "白"]
const LABEL_HEIGHT := 32.0
const LABEL_GAP := 4.0

var _badges: Dictionary = {}
var _detail: RichTextLabel
var _inspected_id := 0
var _detail_results: Dictionary = {}
var _detail_area := Rect2()
var _unavailable_hint := "牌效数据暂不可用。"
var _snapshot_note := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_detail = RichTextLabel.new()
	_detail.name = "MahjongEfficiencyDetail"
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.focus_mode = Control.FOCUS_NONE
	_detail.scroll_active = false
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_theme_color_override("default_color", Color("#fff5e4"))
	_detail.add_theme_font_size_override("normal_font_size", 15)
	var surface := THEME.frame(Color("#252019f5"), Color("#99744b"), 9, 1)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		surface.set_content_margin(side, 8.0)
	_detail.add_theme_stylebox_override("normal", surface)
	add_child(_detail)
	_detail.hide()


func clear() -> void:
	for badge in _badges.values():
		remove_child(badge)
		badge.queue_free()
	_badges.clear()
	_inspected_id = 0
	_detail_results = {}
	if is_instance_valid(_detail):
		_detail.hide()


func present(tiles: Array, results: Dictionary, selected_id: int, detail_area := Rect2(), unavailable_hint := "牌效数据暂不可用。", snapshot_note := "") -> void:
	_detail_area = detail_area
	_detail_results = results
	_unavailable_hint = unavailable_hint
	_snapshot_note = snapshot_note
	var last_rank := 1
	var label_top := 0.0
	for tile in tiles:
		var rect: Rect2 = tile.get("rect", Rect2())
		if not rect.has_area():
			continue
		label_top = maxf(label_top, tile.get("bottom", rect.end.y) + LABEL_GAP)
		var result: Variant = results.get(int(tile.get("id", 0)))
		if _valid_efficiency(result):
			last_rank = maxi(last_rank, _rank(result))
	var used := {}
	for tile_index in range(tiles.size()):
		var tile: Dictionary = tiles[tile_index]
		var id := int(tile.get("id", 0))
		var rect: Rect2 = tile.get("rect", Rect2())
		if id <= 0 or not rect.has_area() or used.has(id):
			continue
		used[id] = true
		var badge: Control = _badges.get(id)
		if not is_instance_valid(badge):
			badge = BADGE.new()
			badge.name = "MahjongEfficiencyBadge%d" % id
			_badges[id] = badge
			add_child(badge)
			var inspect := Button.new()
			inspect.name = "Inspect"
			inspect.accessibility_name = "查看向听进张详情"
			inspect.tooltip_text = "查看向听进张详情"
			inspect.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			for state in ["normal", "hover", "pressed", "disabled"]:
				inspect.add_theme_stylebox_override(state, StyleBoxEmpty.new())
			badge.add_child(inspect)
			inspect.pressed.connect(_inspect.bind(id))
		var result: Variant = results.get(id)
		var available := _valid_efficiency(result)
		var rank := _rank(result) if available else 0
		badge.set_available(available)
		badge.set_selected(id == selected_id)
		badge.set_recommended(rank == 1)
		var risk: Variant = result.get("risk") if available else null
		badge.set_risk_level(str(risk.get("level", "")) if risk is Dictionary else "", risk is Dictionary and risk.get("verified") == true)
		if available:
			badge.set_efficiency(int(result.shanten.minimum), int(result.ukeireCount), rank, last_rank)
		badge.position = rect.position
		badge.size = rect.size
		badge.badge_rect = _label_rect(tiles, tile_index, rect, label_top)
		var hit := badge.get_node("Inspect") as Button
		hit.position = badge.badge_rect.position
		hit.size = badge.badge_rect.size
		hit.visible = true
		hit.tooltip_text = "%s · 向听 %d · 有效进张 %d 张\n点击查看未见有效牌；0 向听不代表已满足本桌胡牌资格。" % [_analysis_scope(result), int(result.shanten.minimum), int(result.ukeireCount)] if available else unavailable_hint
		if not _snapshot_note.is_empty(): hit.tooltip_text += "\n" + _snapshot_note
		hit.accessibility_name = hit.tooltip_text
		badge.queue_redraw()
	for id in _badges.keys():
		if used.has(id):
			continue
		var obsolete: Control = _badges[id]
		remove_child(obsolete)
		obsolete.queue_free()
		_badges.erase(id)
	if not used.has(_inspected_id):
		_inspected_id = 0
	_show_detail(results.get(_inspected_id), detail_area)


func _inspect(id: int) -> void:
	_inspected_id = 0 if _inspected_id == id else id
	_show_detail(_detail_results.get(_inspected_id), _detail_area)


func _label_rect(tiles: Array, index: int, face: Rect2, label_top: float) -> Rect2:
	var width := face.size.x
	for neighbor_index in [index - 1, index + 1]:
		if neighbor_index < 0 or neighbor_index >= tiles.size():
			continue
		var neighbor: Rect2 = tiles[neighbor_index].get("rect", Rect2())
		if neighbor.has_area():
			width = minf(width, absf(face.get_center().x - neighbor.get_center().x) - 2.0)
	width = maxf(22.0, width - 2.0)
	return Rect2(Vector2((face.size.x - width) * 0.5, label_top - face.position.y), Vector2(width, LABEL_HEIGHT))


func _show_detail(result: Variant, area: Rect2) -> void:
	if not is_instance_valid(_detail):
		return
	var visible_area := area.intersection(Rect2(Vector2.ZERO, size))
	var display := visible_area.size.x >= 180.0 and visible_area.size.y >= 64.0 and _inspected_id > 0
	_detail.visible = display
	if not display:
		return
	_detail.position = visible_area.position
	_detail.size = visible_area.size
	if not _valid_efficiency(result):
		_detail.text = _unavailable_hint
		return
	var waits := PackedStringArray()
	var incoming: Variant = result.get("ukeire")
	if incoming is Array:
		for entry in incoming:
			if not entry is Dictionary:
				continue
			var name := _tile_name(entry.get("tile"))
			var remaining: Variant = entry.get("count")
			if not name.is_empty() and _count_is_valid(remaining, 4) and remaining > 0:
				waits.append("%s×%d" % [name, int(remaining)])
	var status := "和牌资格未校验"
	var legality: Variant = result.get("legalWaits")
	if legality is Dictionary and legality.get("verified") == true:
		status = "已通过和牌校验" if legality.get("legal") == true else "未通过和牌校验"
	if result.shanten.minimum > 0:
		status = "尚未结构听牌"
	_detail.text = "%s · 向听 %d · 有效进张 %d 张（未见牌） · %s\n%s" % [_analysis_scope(result), int(result.shanten.minimum), int(result.ukeireCount), status,
		"、".join(waits) if not waits.is_empty() else "无未见有效牌"]
	if not _snapshot_note.is_empty(): _detail.text += "\n" + _snapshot_note


static func _analysis_scope(result: Dictionary) -> String:
	return "当前整手（非打出建议）" if result.get("analysisMode") == "hand" else "打出此牌后"


static func _valid_efficiency(value: Variant) -> bool:
	return value is Dictionary and value.get("shanten") is Dictionary and _count_is_valid(value.shanten.get("minimum"), 13) and _count_is_valid(value.get("ukeireCount"), 136)


static func _rank(result: Dictionary) -> int:
	var rank: Variant = result.get("rank")
	return int(rank) if _count_is_valid(rank, 34) else 0


static func _count_is_valid(value: Variant, maximum: int) -> bool:
	return (value is int or value is float) and value >= 0 and value <= maximum and value == floorf(value)


static func _tile_name(value: Variant) -> String:
	if not _count_is_valid(value, 33):
		return ""
	var tile := int(value)
	if tile < 27:
		return NUMERALS[tile % 9] + SUITS[floori(tile / 9.0)]
	return HONORS[tile - 27]
