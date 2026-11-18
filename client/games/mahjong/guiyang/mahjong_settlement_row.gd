extends Button

const ART := preload("res://modules/games/mahjong/guiyang/mahjong_settlement_theme.gd")
const HAND := preload("res://modules/games/mahjong/guiyang/mahjong_settlement_hand.gd")
const PORTRAIT_MASK := preload("res://modules/games/mahjong/guiyang/settlement_portrait.gdshader")
const HUD := preload("res://modules/games/mahjong/guiyang/mahjong_battle_art.gd")

var _winner := false
var _portrait: TextureRect
var _nickname: Label
var _delta: Label
var _balance: Label
var _delta_egg: TextureRect
var _balance_egg: TextureRect
var _badge: Control
var _method: Label
var _hand: Control
var _rule: ColorRect
var _selected_style: StyleBox
var _others_style: StyleBox

func setup(row: Dictionary, materials: RefCounted) -> void:
	var seat := int(row.get("seat", -1))
	name = "MahjongSettlementRow%d" % seat
	_winner = bool(row.get("winner", false))
	accessibility_name = "%s，%s，查看本家计分" % [row.name, row.result]
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	clip_contents = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_stretch_ratio = 1.14 if _winner else 1.0
	_selected_style = ART.patch(ART.WINNER, Vector4(24, 27, 24, 27))
	_others_style = StyleBoxEmpty.new()
	add_theme_stylebox_override("normal", _selected_style if _winner else _others_style)
	var hover := ART.surface(Color("#ffd47e65"), Color("#d39943"), 13, 1)
	for state in [&"hover",&"pressed",&"hover_pressed"]: add_theme_stylebox_override(state, hover)
	add_theme_stylebox_override("focus", ART.surface(Color.TRANSPARENT, Color("#bf7c25"), 14, 2))
	_portrait = ART.picture(self, HUD.player_portrait(int(row.get("relative",seat))))
	_portrait.stretch_mode = TextureRect.STRETCH_SCALE
	var mask := ShaderMaterial.new()
	mask.shader = PORTRAIT_MASK
	_portrait.material = mask
	_nickname = ART.label(self, "自己" if row.get("own", false) else str(row.name), 22)
	_nickname.name = "MahjongSettlementPlayer%d" % seat
	_nickname.tooltip_text = str(row.name)
	var delta: Variant = row.get("egg_delta")
	var counts := bool(row.get("counts_eggs", true))
	var delta_text := "%+d 鸡蛋" % int(delta) if delta != null else "— 鸡蛋" if counts else "不计鸡蛋"
	_delta = ART.label(self, delta_text, 19, ART.GAIN if delta != null and delta > 0 else ART.LOSS if delta != null and delta < 0 else ART.MUTED)
	_delta.name = "MahjongSettlementEggDelta%d" % seat
	_delta.tooltip_text = "本局实际鸡蛋收支  " + delta_text
	var amount: Variant = row.get("balance")
	_balance = ART.label(self, str(int(amount)) if amount != null else "—", 17)
	_balance.name = "MahjongSettlementBalance%d" % seat
	_balance.tooltip_text = "鸡蛋余额  " + _balance.text
	_delta_egg = ART.picture(self, ART.EGG)
	_balance_egg = ART.picture(self, ART.EGG)
	_balance_egg.visible = counts
	_balance.visible = counts
	_delta_egg.visible = counts
	_rule = ColorRect.new()
	_rule.color = Color("#c795616b")
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rule)
	if _winner:
		_badge = ART.picture(self, ART.CROWN)
		_method = ART.label(self, str(row.get("method","胡牌")), 19, ART.LOSS, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		var tag := Panel.new()
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.add_theme_stylebox_override("panel", ART.surface(Color("#f4cf9b"), Color("#dfac73"), 18, 1))
		add_child(tag)
		_badge = tag
		_method = ART.label(tag, str(row.get("status",row.result)), 17, ART.INK, HORIZONTAL_ALIGNMENT_CENTER)
		_method.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var tiles: Array = row.get("tiles", [])
	if not tiles.is_empty():
		var strip := HAND.new()
		strip.name = "MahjongSettlementHand%d" % seat
		strip.setup(tiles, materials)
		_hand = strip
		add_child(strip)
	else:
		_hand = ART.label(self, "手牌未公开", 15, ART.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_arrange)

func set_selected(chosen: bool) -> void:
	if not _winner:
		add_theme_stylebox_override("normal", ART.surface(Color("#ffe2aa84"), Color("#daa566"), 12, 1) if chosen else _others_style)

func _draw() -> void:
	if not _winner:
		draw_line(Vector2(10,size.y-1), Vector2(size.x-10,size.y-1), Color("#be8a464a"), 1)

func _arrange() -> void:
	if not is_instance_valid(_hand) or size.x <= 0 or size.y <= 0: return
	var stacked := size.x < 455
	var info_h := minf(86.0, size.y * 0.57) if stacked else size.y
	var unit := clampf(size.x / (500.0 if stacked else 920.0), 0.58, 1.16)
	var pad := maxf(4, 9 * unit)
	var portrait := minf(info_h * 0.83, 100.0 * unit)
	_portrait.position = Vector2(pad, (info_h-portrait)*0.5)
	_portrait.size = Vector2.ONE * portrait
	var left := _portrait.position.x + portrait + pad
	var slot := maxf(77, 123 * unit) if not stacked else size.x * 0.40
	var font_size := clampi(roundi(25*unit), 15, 29)
	var line := maxf(ceilf(ART.FONT.get_height(font_size)),minf(info_h*0.27,font_size*1.5))
	var top := (info_h - line * 3.0) * 0.5
	_nickname.position = Vector2(left, top)
	_nickname.size = Vector2(slot, line)
	_nickname.add_theme_font_size_override("font_size",font_size)
	var egg := minf(30.0 * unit, line)
	for i in 2:
		var icon := _delta_egg if i == 0 else _balance_egg
		var number := _delta if i == 0 else _balance
		var ypos := top + (i+1) * line
		icon.position = Vector2(left, ypos + (line-egg)*0.5)
		icon.size = Vector2(egg,egg)
		var indent := egg+2 if icon.visible else 0.0
		number.position = Vector2(left+indent,ypos)
		number.size = Vector2(slot-indent, line)
		number.add_theme_font_size_override("font_size",maxi(12,roundi((21 if i == 0 else 20)*unit)))
	var divider := left+slot+pad*0.5
	_rule.position = Vector2(divider,info_h*0.19)
	_rule.size = Vector2(1,info_h*0.62)
	var badge_w := clampf(size.x*0.106, 46, 102)
	if stacked: badge_w = minf(size.x-divider-2*pad, 88)
	var badge_x := divider+pad
	_method.add_theme_font_size_override("font_size",clampi(roundi(24*unit), 14, 29))
	if _winner:
		var mark_h := minf(badge_w*0.69,info_h*0.49)
		_badge.position = Vector2(badge_x,info_h*0.49-mark_h*0.73)
		_badge.size = Vector2(badge_w,mark_h)
		_method.position = Vector2(badge_x, _badge.position.y+mark_h-1)
		_method.size = Vector2(badge_w, line)
	else:
		var tag_h := minf(info_h*0.44,maxf(28,41*unit))
		_badge.position = Vector2(badge_x,(info_h-tag_h)*0.5)
		_badge.size = Vector2(badge_w,tag_h)
	var hand_x := pad*1.5 if stacked else badge_x+badge_w+pad
	_hand.position = Vector2(hand_x,info_h if stacked else size.y*0.09)
	_hand.size = Vector2(maxf(1,size.x-hand_x-pad),maxf(1,size.y-info_h-pad*0.5 if stacked else size.y*0.82))
