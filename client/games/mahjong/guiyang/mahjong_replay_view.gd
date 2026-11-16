extends VBoxContainer
## Projects only the completed, public replay journal for presentation.

const RURAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_theme.gd")
const MOVE_NAMES := {
	"play": "打出", "peng": "碰", "ming_gang": "明杠", "an_gang": "暗杠",
	"bu_gang": "补杠", "hu": "胡牌", "wall_exhausted": "牌墙耗尽 · 流局",
}
const SUITS := {"wan": "万", "tong": "筒", "tiao": "条"}
const RANKS := ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

var _replay: Dictionary = {}
var _events: Array = []
var _step := 0
var _position: Label
var _move: Label
var _seats: Array[Label] = []
var _previous: Button
var _next: Button


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_position = _label(self, "MahjongReplayPosition", 22)
	_move = _label(self, "MahjongReplayMove", 25)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	add_child(grid)
	for seat in range(4):
		var frame := PanelContainer.new()
		frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var style := RURAL.frame(RURAL.CREAM, RURAL.GOLD, 14, 1)
		style.shadow_size = 0
		frame.add_theme_stylebox_override("panel", style)
		grid.add_child(frame)
		var padding := MarginContainer.new()
		for side in ["left", "right", "top", "bottom"]:
			padding.add_theme_constant_override("margin_" + side, 10)
		frame.add_child(padding)
		var copy := _label(padding, "MahjongReplaySeat%d" % (seat + 1), 18)
		copy.add_theme_constant_override("line_spacing", 4)
		copy.custom_minimum_size.y = 106
		_seats.append(copy)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	add_child(controls)
	_previous = _navigation(controls, "MahjongReplayPreviousButton", "‹  上一步", -1)
	_next = _navigation(controls, "MahjongReplayNextButton", "下一步  ›", 1)


func apply(replay: Dictionary) -> void:
	if replay == _replay: return
	_replay = replay
	_events = replay.get("events", [])
	_step = 0
	_project()


func _advance(offset: int) -> void:
	_step = clampi(_step + offset, 0, _events.size())
	_project()


func _project() -> void:
	var discards: Array[Dictionary] = []
	var melds := [{}, {}, {}, {}]
	var winners: Array[int] = []
	var latest := "开局"
	for index in range(_step):
		var event: Variant = _events[index]
		if not event is Dictionary:
			continue
		var kind := str(event.get("kind", ""))
		if kind == "wall_exhausted":
			latest = MOVE_NAMES[kind]
			continue
		var seat := int(event.get("seat", -1))
		if seat < 0 or seat > 3 or not MOVE_NAMES.has(kind):
			continue
		latest = "%d号座 · %s" % [seat + 1, MOVE_NAMES[kind]]
		if kind == "play":
			var tile := _tile_name(event.get("tile"))
			discards.append({"seat": seat, "tile": tile, "claimed": false})
			latest += " " + tile
			continue
		var discard_index := int(event.get("discard_index", -1))
		if discard_index >= 0 and discard_index < discards.size():
			discards[discard_index].claimed = true
		if kind == "hu":
			winners.append(seat)
			continue
		var meld: Variant = event.get("meld")
		var meld_index := int(event.get("meld_index", -1))
		if meld_index < 0 or not meld is Dictionary:
			continue
		var title := str(MOVE_NAMES[kind])
		# Public concealed kongs show their existence without tile faces.
		if kind != "an_gang":
			var tiles: Variant = meld.get("tiles")
			if tiles is Array and not tiles.is_empty():
				title += " " + _tile_name(tiles[0])
		melds[seat][meld_index] = title
	var remaining := [PackedStringArray(), PackedStringArray(), PackedStringArray(), PackedStringArray()]
	for discard in discards:
		if not discard.claimed:
			remaining[discard.seat].append(discard.tile)
	var dealer := int(_replay.get("dealer", -1))
	_position.text = "公开复盘  ·  %d / %d" % [_step, _events.size()]
	_move.text = latest
	for seat in range(4):
		var tail := remaining[seat] as PackedStringArray
		var end := tail.size()
		var text := "%d号座%s%s\n弃牌 %d" % [seat + 1, " · 庄家" if seat == dealer else "", " · 胡牌" if seat in winners else "", end]
		if end > 0:
			text += " · " + "、".join(tail.slice(maxi(0, end - 6), end))
		var open_melds := PackedStringArray(melds[seat].values())
		text += "\n副露 %d" % open_melds.size()
		if not open_melds.is_empty():
			text += " · " + "、".join(open_melds)
		_seats[seat].text = text
	_previous.disabled = _step <= 0
	_next.disabled = _step >= _events.size()


func _tile_name(value: Variant) -> String:
	if value is Dictionary:
		var rank := int(value.get("rank", 0))
		var suit := str(value.get("suit", ""))
		if SUITS.has(suit) and rank >= 1 and rank <= 9:
			return RANKS[rank] + str(SUITS[suit])
	return "牌背"


func _label(parent: Control, node_name: String, font_size: int) -> Label:
	var label := Label.new()
	label.name = node_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", RURAL.INK)
	parent.add_child(label)
	return label


func _navigation(parent: Control, node_name: String, text: String, offset: int) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size.y = 58
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	RURAL.skin_button(button)
	button.pressed.connect(_advance.bind(offset))
	parent.add_child(button)
	return button
