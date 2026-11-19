extends Panel

const ART := preload("res://modules/games/mahjong/guiyang/mahjong_settlement_theme.gd")
const PLAYER_ROW := preload("res://modules/games/mahjong/guiyang/mahjong_settlement_row.gd")
const MATERIALS := preload("res://modules/games/mahjong/guiyang/real_tile_materials.gd")
const SHARE := preload("res://modules/games/mahjong/guiyang/mahjong_settlement_share.gd")
const RURAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_theme.gd")

var _data: Dictionary
var _main := Control.new()
var _header := Control.new()
var _room_caption: Label
var _tools := HBoxContainer.new()
var _scroll := ScrollContainer.new()
var _columns := BoxContainer.new()
var _player_margin := MarginContainer.new()
var _aside_margin := MarginContainer.new()
var _players := VBoxContainer.new()
var _aside := VBoxContainer.new()
var _fan_card: Panel
var _score_card: Panel
var _fan_title: Label
var _fan_lines := VBoxContainer.new()
var _score_lines := VBoxContainer.new()
var _actions := HBoxContainer.new()
var _feedback: Label
var _details: ColorRect
var _details_button: Button
var _active_seat := -1
var _frame := ART.patch(ART.FRAME, Vector4(86, 3, 86, 142))
var _banner_rect := Rect2()
var _footer_height := 70.0
var _action_rect := Rect2()
var _canvas_scale := Vector2.ZERO

func setup(data: Dictionary, leave: Callable, next_round: Callable, rules: Callable, dismiss := Callable(), return_room := Callable(), materials: RefCounted = null) -> void:
	name = "MahjongSettlement"
	mouse_filter = Control.MOUSE_FILTER_STOP
	oversampling_with_scale = CanvasItem.OVERSAMPLING_WITH_SCALE_ENABLED
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_data = data
	add_child(_main)
	_main.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.name = "MahjongSettlementBrandMark"
	_header.accessibility_name = "小板凳乡村麻将 · 对局结算"
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main.add_child(_header)
	_room_caption = ART.label(_header, str(data.get("round_caption", data.get("room",""))), 19, ART.INK, HORIZONTAL_ALIGNMENT_CENTER)
	_room_caption.name = "MahjongSettlementRoundCaption"
	_main.add_child(_tools)
	_tools.alignment = BoxContainer.ALIGNMENT_END
	_details_button = _tool("MahjongSettlementDetailsButton", "明细", _open_details)
	_tool("MahjongSettlementRulesButton", "规则", rules)
	var retained := bool(data.get("rematch", false))
	if retained and return_room.is_valid():
		_tool("MahjongSettlementLobbyButton", "离房", leave).tooltip_text = "离开房间，返回大厅"
	if dismiss.is_valid():
		var close := _tool("MahjongSettlementCloseButton", "×", dismiss)
		close.tooltip_text = "关闭结算，查看牌桌"
		close.accessibility_name = close.tooltip_text

	_scroll.name = "MahjongSettlementContent"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_main.add_child(_scroll)
	_columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_columns)
	_players.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_players.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_players.add_theme_constant_override("separation", 2)
	_player_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_player_margin.size_flags_stretch_ratio = 2.43
	_columns.add_child(_player_margin)
	_player_margin.add_child(_players)
	var rows: Array = data.get("rows", [])
	if materials == null: materials = MATERIALS.new()
	for row: Dictionary in rows:
		var player := PLAYER_ROW.new()
		player.setup(row, materials)
		player.pressed.connect(_select_seat.bind(int(row.seat)))
		_players.add_child(player)
	if rows.is_empty(): ART.label(_players, "暂无结算明细", 20, ART.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_aside.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_aside.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_aside_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_columns.add_child(_aside_margin)
	_aside_margin.add_child(_aside)
	_fan_card = _card(_fan_lines, "番型计算")
	_fan_title = _fan_card.get_node("Plaque/Caption")
	_score_card = _card(_score_lines, "本局得失")
	for row: Dictionary in rows:
		var counts_eggs := bool(row.get("counts_eggs", true))
		var amount: Variant = row.get("egg_delta") if counts_eggs else row.score
		var value := "—"
		var ink := ART.MUTED
		if amount != null:
			value = ("%+d" if counts_eggs else "%+d 分") % int(amount)
			if amount != 0: ink = ART.GAIN if amount > 0 else ART.LOSS
		_add_line(_score_lines, "自己" if row.get("own",false) else str(row.name), value, ink,
			"MahjongSettlementNet%d" % int(row.seat), row.get("own",false), counts_eggs)
	var initial_seat := int(rows[0].seat) if not rows.is_empty() else -1
	for row: Dictionary in rows:
		if row.get("winner",false):
			initial_seat = int(row.seat)
			break
	_select_seat(initial_seat)

	_main.add_child(_actions)
	_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_actions.minimum_size_changed.connect(_place_actions, CONNECT_DEFERRED)
	if retained: ART.action(_actions,"MahjongNextRoundButton","再来一局",0,next_round)
	ART.action(_actions,"MahjongSettlementShareButton","分享战绩",1,_share)
	if retained and return_room.is_valid():
		ART.action(_actions,"MahjongSettlementRoomButton","返回房间",2,return_room)
	else:
		ART.action(_actions,"MahjongSettlementLobbyButton",str(data.get("return_caption","返回大厅")),2,leave)
	_feedback = ART.label(_main,"",15,Color("#fff5d8"),HORIZONTAL_ALIGNMENT_CENTER)
	_feedback.add_theme_stylebox_override("normal", ART.surface(Color("#49301aee"), Color("#efc27d"), 10, 1))
	_feedback.hide()
	_build_details()
	resized.connect(_fit)
	if is_inside_tree(): _fit.call_deferred()
	else: tree_entered.connect(_fit, CONNECT_DEFERRED | CONNECT_ONE_SHOT)
	_fit()

func _tool(id: String, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = id
	button.tooltip_text = caption
	button.accessibility_name = caption
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in [&"normal",&"hover",&"pressed",&"hover_pressed"]:
		var fill := Color("#754723") if state == &"normal" else Color("#955e2f")
		button.add_theme_stylebox_override(state, ART.surface(fill,Color("#e6b77e"),12,1))
	button.add_theme_stylebox_override("focus",ART.surface(Color.TRANSPARENT,Color("#ffe49f"),12,2))
	var label := ART.label(button,caption,15,Color("#fff5d9"),HORIZONTAL_ALIGNMENT_CENTER)
	label.name = "Caption"
	label.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	button.pressed.connect(action)
	_tools.add_child(button)
	return button

func _card(lines: VBoxContainer, title: String) -> Panel:
	var card := Panel.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var paper := ART.surface(Color("#ffebcf"), Color("#cc985d"), 16, 2)
	paper.shadow_color = Color("#79471932")
	paper.shadow_size = 3
	paper.shadow_offset = Vector2(0,2)
	card.add_theme_stylebox_override("panel",paper)
	_aside.add_child(card)
	var plaque := ART.picture(card,ART.SCORE_PLAQUE if title == "本局得失" else ART.FAN_PLAQUE)
	plaque.name = "Plaque"
	plaque.accessibility_name = title
	var heading := ART.label(plaque,title,22,Color("#fff2d7"),HORIZONTAL_ALIGNMENT_CENTER)
	heading.name = "Caption"
	heading.add_theme_font_override("font", ART.KAI)
	heading.hide()
	heading.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	card.add_child(lines)
	lines.add_theme_constant_override("separation", 3)
	card.resized.connect(_fit_card.bind(card,lines))
	lines.minimum_size_changed.connect(_fit_card.bind(card,lines), CONNECT_DEFERRED)
	return card

func _fit_card(card: Panel, lines: VBoxContainer) -> void:
	if card.size.x < 1: return
	var unit := clampf(card.size.x/378.0, 0.60, 1.12)
	var plaque := card.get_node("Plaque") as TextureRect
	var label := plaque.get_node("Caption") as Label
	var w := minf(card.size.x*0.74,228*unit)
	var h := w * ART.PLAQUE.get_height() / ART.PLAQUE.get_width()
	plaque.position = Vector2((card.size.x-w)*0.5,-h*0.28)
	plaque.size = Vector2(w,h)
	label.add_theme_font_size_override("font_size",clampi(roundi(h*0.60),16,32))
	var pad := maxf(6, 14*unit)
	var top := h*0.79
	var available := maxf(1, card.size.y-top-pad)
	var count := maxi(1,lines.get_child_count())
	var desired := minf(available, count * (47 if lines == _score_lines else 44) * unit)
	var font_size := clampi(roundi(minf(24*unit, (desired/count-3)*0.62)),12,28)
	for chip: PanelContainer in lines.get_children():
		var line := chip.get_child(0) as HBoxContainer
		for node in line.get_children():
			if node is Label:
				var actual_size := roundi(font_size*1.18) if chip.has_meta("total") else font_size
				if node.get_theme_font_size("font_size") != actual_size: node.add_theme_font_size_override("font_size",actual_size)
			elif node is TextureRect: node.custom_minimum_size = Vector2(font_size*1.12,0)
	lines.position = Vector2(pad, top+(available-desired)*0.5)
	lines.size = Vector2(maxf(1,card.size.x-pad*2),desired)

func _add_line(parent: VBoxContainer, title: String, value: String, ink: Color, id := "", highlight := false, show_egg := false, total := false) -> void:
	var chip := PanelContainer.new()
	chip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var surface: StyleBox = ART.patch(ART.BRUSH,Vector4(40,16,40,16)) if total else ART.surface(Color("#dce6a1") if highlight else Color("#f8dcb5"),Color.TRANSPARENT,10)
	if total: chip.set_meta("total",true)
	surface.set_content_margin(SIDE_LEFT,8)
	surface.set_content_margin(SIDE_RIGHT,8)
	chip.add_theme_stylebox_override("panel", surface)
	parent.add_child(chip)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 3)
	chip.add_child(line)
	var key := ART.label(line,title,17,Color("#fff5cc") if total else ART.INK)
	if total:
		line.alignment = BoxContainer.ALIGNMENT_CENTER
		line.add_theme_constant_override("separation",8)
		key.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	else: key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if show_egg:
		var icon := ART.picture(line, ART.EGG)
		icon.tooltip_text = "本局鸡蛋得失"
	var number := ART.label(line,value,17,Color("#ffe770") if total else ink,HORIZONTAL_ALIGNMENT_RIGHT)
	if not id.is_empty(): number.name = id
	number.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	number.tooltip_text = "本局鸡蛋得失  "+value if show_egg else value

func _select_seat(seat: int) -> void:
	_active_seat = seat
	for child in _fan_lines.get_children():
		_fan_lines.remove_child(child)
		child.queue_free()
	var selected := {}
	for row: Dictionary in _data.get("rows",[]):
		if int(row.seat) == seat: selected = row
	for player in _players.get_children():
		if player is Button: player.set_selected(player.name == StringName("MahjongSettlementRow%d" % seat))
	if selected.is_empty():
		_add_line(_fan_lines,"暂无计分明细","",ART.MUTED)
		return
	var items: Array = selected.get("fan_items",[])
	var has_fan := selected.has("fan_total")
	_fan_title.text = "番型计算" if has_fan else "计分明细"
	var plaque := _fan_title.get_parent() as TextureRect
	plaque.texture = ART.FAN_PLAQUE if has_fan else ART.PLAQUE
	plaque.accessibility_name = _fan_title.text
	_fan_title.visible = not has_fan
	if has_fan:
		for item: Dictionary in items: _add_line(_fan_lines,str(item.name),"%d 番" % int(item.fan),ART.LOSS)
	else:
		for item: Dictionary in selected.get("score_items",[]):
			_add_line(_fan_lines,str(item.name),"%+d 分" % int(item.points),ART.INK)
		if _fan_lines.get_child_count() == 0: _add_line(_fan_lines,str(selected.get("status","本局牌分")),"",ART.MUTED)
	var value := "%d 番" % int(selected.fan_total) if has_fan else "%+d 分" % int(selected.score)
	_add_line(_fan_lines,"合计",value,ART.GAIN,"MahjongSettlementFanTotal",false,false,true)
	_fan_card.size_flags_stretch_ratio = clampf((_fan_lines.get_child_count()+1.3)/5.1,0.74,1.35)
	_fit_card(_fan_card,_fan_lines)
	if is_node_ready(): _fit.call_deferred()

func _build_details() -> void:
	_details = ColorRect.new()
	_details.name = "MahjongSettlementDetails"
	_details.color = Color("#25190fc9")
	_details.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_details)
	_details.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var sheet := PanelContainer.new()
	sheet.name = "Sheet"
	var paper := ART.surface(Color("#ffebcd"),Color("#ba8649"),14,2)
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: paper.set_content_margin(side,12)
	sheet.add_theme_stylebox_override("panel",paper)
	_details.add_child(sheet)
	var body := VBoxContainer.new()
	sheet.add_child(body)
	ART.label(body,"结算明细",23,ART.INK,HORIZONTAL_ALIGNMENT_CENTER)
	var scroll := ScrollContainer.new()
	scroll.name = "DetailScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	_detail(list,"MahjongSettlementRoom",str(_data.get("room","")))
	_detail(list,"MahjongSettlementOutcome",str(_data.get("outcome_title","流局" if _data.get("outcome","draw") == "draw" else "胡牌")))
	_detail(list,"MahjongSettlementSummary",str(_data.get("summary","")))
	if _data.get("indicator") is Texture2D:
		var indicator_line := HBoxContainer.new()
		list.add_child(indicator_line)
		ART.label(indicator_line,"翻鸡指示牌  "+str(_data.get("indicator_title","")),17)
		var tile := ART.picture(indicator_line,_data.indicator)
		tile.name = "MahjongSettlementIndicator"
		tile.custom_minimum_size = Vector2(30,40)
	for row: Dictionary in _data.get("rows",[]):
		var name_line := ART.label(list,str(row.name),18)
		name_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail(list,"MahjongSettlementScore%d" % int(row.seat),"本局牌分  %+d 分" % int(row.score))
		_detail(list,"MahjongSettlementResult%d" % int(row.seat),str(row.get("result","")))
		if row.has("details"): _detail(list,"MahjongSettlementBreakdown%d" % int(row.seat),str(row.details))
		if row.has("series"): _detail(list,"MahjongSettlementSeries%d" % int(row.seat),str(row.series))
	var close := ART.action(body,"MahjongSettlementDetailsClose","返回结算",2,_close_details)
	close.custom_minimum_size = Vector2(150,44)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.add_theme_font_size_override("font_size",17)
	close.add_theme_constant_override("icon_max_width",19)
	_details.hide()

func _detail(parent: Control, id: String, value: String) -> void:
	var line := ART.label(parent,value,16,ART.MUTED)
	line.name = id
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.visible = not value.is_empty()

func _open_details() -> void:
	_main.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	_details.show()
	(_details.find_child("MahjongSettlementDetailsClose",true,false) as Button).grab_focus()

func _close_details() -> void:
	_details.hide()
	_main.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
	_details_button.grab_focus()

func navigation_snapshot() -> Dictionary:
	var focus := get_viewport().gui_get_focus_owner()
	return {"seat":_active_seat,"details":_details.visible,"scroll":_scroll.scroll_vertical,
		"detail_scroll":(_details.find_child("DetailScroll",true,false) as ScrollContainer).scroll_vertical,
		"focus":str(focus.name) if is_instance_valid(focus) and is_ancestor_of(focus) else ""}

func restore_navigation(previous: Dictionary) -> void:
	for row: Dictionary in _data.get("rows",[]):
		if int(row.seat) == int(previous.seat):
			_select_seat(int(row.seat))
			break
	if previous.details: _open_details()
	if not str(previous.focus).is_empty():
		var focus := find_child(str(previous.focus),true,false) as Control
		if is_instance_valid(focus) and focus.is_visible_in_tree(): focus.grab_focus()
	_scroll.set_deferred("scroll_vertical", previous.scroll)
	_details.find_child("DetailScroll",true,false).set_deferred("scroll_vertical",previous.detail_scroll)

func _unhandled_key_input(event: InputEvent) -> void:
	if is_instance_valid(_details) and _details.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close_details()

func _share() -> void:
	var lines := PackedStringArray(["小板凳乡村麻将 · 对局结算",str(_data.get("round_caption",_data.get("room","")))])
	for row: Dictionary in _data.get("rows",[]):
		lines.append("%s  %+d 分  %s" % [row.name,int(row.score),str(row.get("result",""))])
	_feedback.text = SHARE.share_text("\n".join(lines))
	_feedback.visible = true
	_fit()

func _place_actions() -> void:
	if _action_rect.has_area():
		_actions.position = _action_rect.position
		_actions.size = _action_rect.size

func _refresh_text_scale() -> void:
	if not is_inside_tree(): return
	var canvas_scale := get_viewport_transform().get_scale()
	if _canvas_scale.is_equal_approx(canvas_scale): return
	_canvas_scale = canvas_scale
	# Fixed-size controls retain their draw cache when the window's canvas scale
	# changes. Reapply the sampling policy after the new transform is in place.
	_main.oversampling_with_scale = CanvasItem.OVERSAMPLING_WITH_SCALE_DISABLED
	_main.oversampling_with_scale = CanvasItem.OVERSAMPLING_WITH_SCALE_ENABLED

func _fit() -> void:
	if not is_instance_valid(_details) or size.x < 1 or size.y < 1: return
	var narrow := size.x < 705
	var portrait := size.y > size.x
	var banner_scale := maxf(size.x / ART.HEADER.get_width(),0.60 if portrait else 0.40)
	var banner_size := ART.HEADER.get_size() * banner_scale
	_banner_rect = Rect2(Vector2((size.x-banner_size.x)*0.5,0),banner_size)
	_header.position = Vector2.ZERO
	_header.size = Vector2(size.x,banner_size.y)
	_room_caption.position = _banner_rect.position + Vector2(500,104)*banner_scale
	_room_caption.size = Vector2(387,45)*banner_scale
	_room_caption.add_theme_font_size_override("font_size",clampi(roundi(24*banner_scale),12,29))
	var real_touch := 0.0
	if is_inside_tree(): real_touch = RURAL.touch_extent(self) / maxf(0.01,get_global_transform().y.length())
	_footer_height = clampf(size.y*0.151,54,134)
	if portrait: _footer_height = maxf(63, real_touch+20)
	var action_h := maxf(real_touch,clampf(_footer_height*0.69,38,86))
	_footer_height = maxf(_footer_height,action_h+14)
	_frame.corner_scale = _footer_height/130.0
	var pad := clampf(size.x*0.024,12,39)
	var bottom_gap := clampf(size.y*0.019,4,18)
	var y := _banner_rect.end.y + 1
	_scroll.position = Vector2(pad,y)
	_scroll.size = Vector2(maxf(1,size.x-2*pad),maxf(1,size.y-_footer_height-bottom_gap-y))
	_columns.vertical = narrow
	_player_margin.add_theme_constant_override("margin_top", 6 if narrow else clampi(roundi(size.y*0.022),9,22))
	_aside_margin.add_theme_constant_override("margin_top",clampi(roundi(size.x*0.010),8,15))
	_aside_margin.add_theme_constant_override("margin_bottom",4)
	_columns.add_theme_constant_override("separation", 16 if narrow else maxi(8,roundi(size.x*0.011)))
	_aside.add_theme_constant_override("separation",clampi(roundi(size.y*0.03),14,24))
	var projected_left := _scroll.size.x if narrow else (_scroll.size.x-14)*0.706
	var stacked_rows := projected_left < 455
	var min_row := 142 if stacked_rows else clampi(roundi(projected_left*0.104),58,98)
	for row in _players.get_children():
		if row is Button: row.custom_minimum_size.y = min_row
	var aside_width := _scroll.size.x if narrow else _scroll.size.x*0.287
	var line_h := clampf(aside_width*0.087,19,37)
	var head_h := clampf(aside_width*0.112,27,48)
	_fan_card.custom_minimum_size.y = head_h + _fan_lines.get_child_count()*line_h + 12
	_score_card.custom_minimum_size.y = head_h + _score_lines.get_child_count()*line_h + 12
	var gap := clampi(roundi(size.x*0.026),5,40) if not portrait else 4
	_actions.add_theme_constant_override("separation",gap)
	_action_rect = Rect2(pad,size.y-_footer_height+(_footer_height-action_h)*0.40,size.x-2*pad,action_h)
	var count := _actions.get_child_count()
	var button_w := minf(size.x*0.239,(_action_rect.size.x-(count-1)*gap)/maxi(1,count))
	if narrow: button_w = minf(230,(_action_rect.size.x-(count-1)*gap)/maxi(1,count))
	for button: Button in _actions.get_children():
		button.custom_minimum_size = Vector2(floorf(button_w),action_h)
		var font_size := clampi(roundi(minf(action_h*0.43,button_w*0.145)),13,36)
		button.add_theme_font_size_override("font_size",font_size)
		var icon_size := clampi(roundi(font_size*1.12),14,45)
		button.add_theme_constant_override("icon_max_width",icon_size)
		button.add_theme_constant_override("h_separation",maxi(2,roundi(font_size*0.20)))
		var side := maxf(3,(button_w-(font_size*button.text.length()+icon_size+font_size*0.32))*0.5)
		for state in [&"normal",&"hover",&"pressed",&"hover_pressed",&"disabled"]:
			button.get_theme_stylebox(state).set_content_margin(SIDE_LEFT,side)
			button.get_theme_stylebox(state).set_content_margin(SIDE_RIGHT,side)
	_place_actions()
	# The banner has open sky above the village on the right. On narrow screens
	# reserve a row below the sign to keep every utility hit target reachable.
	var utility_h := maxf(real_touch,clampf(32*banner_scale,30,37))
	_tools.add_theme_constant_override("separation",4)
	for tool: Button in _tools.get_children():
		var caption := tool.get_node("Caption") as Label
		var font_size := maxi(13,roundi(utility_h*0.47))
		caption.add_theme_font_size_override("font_size",font_size)
		tool.custom_minimum_size = Vector2(maxf(utility_h,caption.text.length()*font_size+12),utility_h)
	_tools.size = _tools.get_combined_minimum_size()
	if narrow:
		_tools.position = Vector2(size.x-pad-_tools.size.x,_banner_rect.end.y)
		_scroll.position.y += utility_h+4
		_scroll.size.y = maxf(1,_scroll.size.y-utility_h-4)
	else:
		_tools.position = Vector2(size.x*0.86-_tools.size.x,0)
	_feedback.position = Vector2(pad, _action_rect.position.y-27)
	_feedback.size = Vector2(size.x-2*pad,25)
	var sheet := _details.get_node("Sheet") as Control
	sheet.size = Vector2(minf(580,size.x-24),minf(570,size.y-24))
	sheet.position = (size-sheet.size)*0.5
	_refresh_text_scale.call_deferred()
	queue_redraw()

func _draw() -> void:
	if not _banner_rect.has_area(): return
	var start := _banner_rect.end.y-1
	draw_style_box(_frame,Rect2(0,start,size.x,maxf(1,size.y-start)))
	# On a phone, crop the village on both sides to keep the central title legible.
	var dest := _banner_rect.intersection(Rect2(Vector2.ZERO,size))
	var scale_factor := _banner_rect.size.x/ART.HEADER.get_width()
	var region := Rect2((dest.position-_banner_rect.position)/scale_factor,dest.size/scale_factor)
	draw_texture_rect_region(ART.HEADER,dest,region)
