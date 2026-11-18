extends Control
## The badge buttons inspect analysis without selecting or playing a 3D tile.

const BADGE := preload("res://modules/games/mahjong/guiyang/tile_efficiency_badge.gd")
const DETAIL := preload("res://modules/games/mahjong/guiyang/mahjong_efficiency_detail.gd")
const NUMERALS := ["一", "二", "三", "四", "五", "六", "七", "八", "九"]
const SUITS := ["万", "筒", "条"]
const SUIT_IDS := ["wan", "tong", "tiao"]
const LABEL_HEIGHT := 32.0
const LABEL_GAP := 4.0

var tile_materials: RefCounted
var _badges: Dictionary = {}
var _detail: Control
var _inspected_id := 0
var _detail_results: Dictionary = {}
var _detail_area := Rect2()
var _unavailable_hint := "牌效数据暂不可用。"
var _snapshot_note := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_detail = DETAIL.new()
	_detail.tile_materials = tile_materials
	add_child(_detail)
	_detail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail.dismissed.connect(close_detail)


func clear() -> void:
	for badge in _badges.values():
		remove_child(badge)
		badge.queue_free()
	_badges.clear()
	close_detail()
	_detail_results = {}


func close_detail() -> void:
	_inspected_id = 0
	if is_instance_valid(_detail):
		_detail.hide()


func shift_badges(delta: Vector2) -> void:
	for badge: Control in _badges.values():
		badge.position += delta


func present(tiles: Array, results: Dictionary, selected_id: int, detail_area := Rect2(), unavailable_hint := "牌效数据暂不可用。", snapshot_note := "") -> void:
	_detail_area = detail_area
	_detail_results = results
	_unavailable_hint = unavailable_hint
	_snapshot_note = snapshot_note
	var last_rank := 1
	var label_top := 0.0
	var highest_tile := INF
	for tile in tiles:
		var rect: Rect2 = tile.get("rect", Rect2())
		if not rect.has_area():
			continue
		label_top = maxf(label_top, tile.get("bottom", rect.end.y) + LABEL_GAP)
		highest_tile = minf(highest_tile, tile.get("top", rect.position.y))
		var result: Variant = results.get(int(tile.get("id", 0)))
		if _valid_efficiency(result):
			last_rank = maxi(last_rank, _rank(result))
	if detail_area.has_area() and label_top + LABEL_HEIGHT > detail_area.end.y:
		label_top = highest_tile - LABEL_HEIGHT - LABEL_GAP
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
	_show_detail(results.get(_inspected_id))


func _inspect(id: int) -> void:
	_inspected_id = 0 if _inspected_id == id else id
	_show_detail(_detail_results.get(_inspected_id))


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


func _show_detail(result: Variant) -> void:
	if not is_instance_valid(_detail): return
	var area := _detail_area if _detail_area.has_area() else Rect2(Vector2.ZERO, size)
	if _inspected_id <= 0 or not area.has_area():
		_detail.hide()
		return
	var waits: Array[Dictionary] = []
	if not _valid_efficiency(result):
		_detail.show_result(_unavailable_hint, waits, _snapshot_note, area)
		return
	var incoming: Variant = result.get("ukeire")
	if incoming is Array:
		for entry in incoming:
			if not entry is Dictionary:
				continue
			var tile: Variant = entry.get("tile")
			var remaining: Variant = entry.get("count")
			if _count_is_valid(tile, 26) and _count_is_valid(remaining, 4) and remaining > 0:
				var suit := floori(float(tile) / 9.0)
				var rank := int(tile) % 9
				waits.append({"suit": SUIT_IDS[suit], "rank": rank + 1,
					"title": NUMERALS[rank] + SUITS[suit], "count": int(remaining)})
	var status := "和牌资格未校验"
	var legality: Variant = result.get("legalWaits")
	if legality is Dictionary and legality.get("verified") == true:
		status = "已通过和牌校验" if legality.get("legal") == true else "未通过和牌校验"
	if result.shanten.minimum > 0:
		status = "尚未结构听牌"
	elif result.has("claimUkeireCount"):
		var claim_count: Variant = result.claimUkeireCount
		status = "杠/定缺条件下接炮候选 %d 张；最终以合法动作为准" % int(claim_count) if _count_is_valid(claim_count, 108) else "接炮资格信息不足"
	var summary := "%s · 向听 %d · 有效进张 %d 张（未见牌）" % [_analysis_scope(result), int(result.shanten.minimum), int(result.ukeireCount)]
	if result.get("analysisMode") == "discard" and _rank(result) > 0:
		summary += " · 推荐第 %d" % _rank(result)
	var missing: Variant = result.get("ownMissingSuit")
	if _count_is_valid(missing, 2):
		summary += " · 定缺%s" % SUITS[int(missing)]
	var notes := PackedStringArray([status if not waits.is_empty() else status + " · 无未见有效牌"])
	# Only display search scores when this candidate was actually searched.
	# Zero can otherwise mean a unique efficiency row or an exhausted wall.
	if result.get("lookAheadEvaluated") == true and _count_is_valid(result.get("q"), 20000) and _count_is_valid(result.get("k"), 20000):
		notes.append("后续进张 Q=%d · 靠张改良 K=%d（加权指标，非胡牌概率）" % [int(result.q), int(result.k)])
	var risk := _risk_note(result.get("riskReasons"))
	if not risk.is_empty(): notes.append(risk)
	var reason := _ranking_note(result)
	if not reason.is_empty(): notes.append("同分依据　" + reason)
	if not _snapshot_note.is_empty(): notes.append(_snapshot_note)
	_detail.show_result(summary, waits, "\n".join(notes), area)


static func _risk_note(reasons: Variant) -> String:
	if not reasons is PackedStringArray or reasons.size() != 3: return ""
	var clues := PackedStringArray()
	for kind in ["elevated", "possible", "rule_blocked", "supply_blocked", "unknown"]:
		var count: int = reasons.count(kind)
		if count == 0: continue
		var label: String = {
			"elevated": "强威胁", "possible": "可能接炮", "rule_blocked": "规则阻断",
			"supply_blocked": "库存阻断", "unknown": "信息不足",
		}[kind]
		clues.append("%s %d 家" % [label, count])
	return "" if clues.is_empty() else "放铳线索　" + " · ".join(clues)


static func _ranking_note(result: Dictionary) -> String:
	match result.get("rankingReason"):
		"elevated_risk": return "强威胁对手较少"
		"claim_supply": return "可接炮进张较多"
		"q": return "后续进张质量 %d" % int(result.get("q", 0))
		"k": return "靠张改良 %d" % int(result.get("k", 0))
		"other_risk": return "其余可能接炮的对手较少"
		"gift_kong": return "可能接明杠的对手较少"
		"chicken_exposure": return "已知鸡牌转移风险较小"
		_: return ""


static func _analysis_scope(result: Dictionary) -> String:
	return "当前整手（非打出建议）" if result.get("analysisMode") == "hand" else "打出此牌后"


static func _valid_efficiency(value: Variant) -> bool:
	return value is Dictionary and value.get("shanten") is Dictionary and _count_is_valid(value.shanten.get("minimum"), 13) and _count_is_valid(value.get("ukeireCount"), 136)


static func _rank(result: Dictionary) -> int:
	var rank: Variant = result.get("rank")
	return int(rank) if _count_is_valid(rank, 34) else 0


static func _count_is_valid(value: Variant, maximum: int) -> bool:
	return (value is int or value is float) and value >= 0 and value <= maximum and value == floorf(value)
