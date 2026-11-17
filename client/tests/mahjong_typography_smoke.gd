extends SceneTree

const MODAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_modal.gd")
const RURAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_theme.gd")
const FONT := preload("res://modules/foundation/ui/fonts/NotoSansCJKsc-Bold.otf")
const SETTLEMENT := preload("res://modules/games/mahjong/guiyang/mahjong_settlement_view.gd")
var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _run() -> void:
	var host := Control.new()
	root.add_child(host)
	var ordinary := Label.new()
	ordinary.text = "小板凳麻将 向听 进张 鸡蛋 0123456789"
	host.add_child(ordinary)
	_expect(ordinary.get_theme_font("font") == FONT, "Shared project theme must use the bundled bold Chinese font")
	_expect(RURAL.title_font() == FONT and MODAL.village_font() == FONT, "Headings and body must share the same square bold family")
	for character in ordinary.text:
		_expect(FONT.has_char(character.unicode_at(0)), "Missing bundled Chinese glyph: " + character)
	var panel := MODAL.village_panel(host)
	var content := VBoxContainer.new()
	panel.add_child(content)
	var label := Label.new()
	label.text = "房间设置与玩法规则"
	content.add_child(label)
	var button := Button.new()
	button.text = "返回上一级"
	RURAL.skin_button(button, true)
	content.add_child(button)
	for extent in [Vector2(350, 400), Vector2(650, 550), Vector2(1100, 700)]:
		panel.size = extent
		for frame in 6: await process_frame
		var margin := panel.get_theme_stylebox("panel")
		var edge := float(panel.get_meta("title_border_offset"))
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			_expect(margin.get_margin(side) >= edge + 11.0, "Content must stay inside the nine-slice rim at " + str(extent))
		var inner := Rect2(panel.global_position + Vector2(margin.get_margin(SIDE_LEFT), margin.get_margin(SIDE_TOP)), panel.size - margin.get_minimum_size())
		_expect(inner.grow(1).encloses(content.get_global_rect()), "Responsive content must fit the padded panel at " + str(extent))
		var style := button.get_theme_stylebox("normal")
		var available := button.size.x - style.get_minimum_size().x - 2
		var caption_width := button.get_theme_font("font").get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x
		_expect(caption_width <= available, "Bold button caption must fit its decorated content area")
	var card := MODAL.paper_frame(Vector4(9, 8, 9, 9))
	_expect(card.get_margin(SIDE_LEFT) >= 14 and card.get_margin(SIDE_TOP) >= 12, "Small paper cards retain inner breathing room")
	for outcome in ["loss", "win", "draw"]:
		var settlement := SETTLEMENT.new()
		host.add_child(settlement)
		settlement.setup({"outcome":outcome, "rows":[{"own":true,"seat":0,"name":"稻香阿婆","result":"未胡","egg_delta":-10,"score":-10}]}, func(): pass, func(): pass, func(): pass)
		for extent in [Vector2(350, 650), Vector2(720, 470), Vector2(1050, 550)]:
			settlement.size = extent
			for frame in 6: await process_frame
			var result: Label = settlement.get("_result")
			var badge: Control = settlement.get("_badge")
			var actual_font := result.get_theme_font("font")
			var font_size := result.get_theme_font_size("font_size")
			var outline := result.get_theme_constant("outline_size") * 2
			_expect(actual_font.get_string_size(result.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + outline + 16 <= badge.size.x, "Settlement outcome must not truncate: " + result.text + " at " + str(extent))
			_expect(actual_font.get_height(font_size) + outline + 17 <= badge.size.y, "Settlement outcome line height must fit the actual badge")
		settlement.queue_free()
		await process_frame
	host.queue_free()
	await process_frame
	if _failures == 0: print("MAHJONG_TYPOGRAPHY_OK bundled_bold=true phone_tablet_desktop_padding=true captions_fit=true")
	quit(0 if _failures == 0 else 1)
