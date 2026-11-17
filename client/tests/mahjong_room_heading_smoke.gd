extends SceneTree

const ART := preload("res://modules/games/mahjong/guiyang/mahjong_battle_art.gd")
const RURAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_theme.gd")
var _failed := false

func _initialize() -> void: call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error(message)

func _run() -> void:
	var header := Label.new()
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_theme_stylebox_override("normal", ART.room())
	header.add_theme_font_override("font", RURAL.title_font())
	header.add_theme_constant_override("outline_size", 2)
	root.add_child(header)
	for viewport in [Vector2(1440,810), Vector2(1600,720), Vector2(1280,800), Vector2(1200,900)]:
		var factor := minf(viewport.x / 1440, viewport.y / 810)
		header.size = Vector2(490, 51) * factor
		for caption in ["房间4826 │ 3/8局 │ 余牌 46", "房间9999 │ 24/24局 │ 余牌 108", "本地练习 │ 训练 · 贵阳捉鸡 │ 余牌 46"]:
			header.text = caption
			ART.fit_room_heading(header, roundi(28 * factor))
			await process_frame
			var surface := header.get_theme_stylebox("normal")
			var patches: Array = surface.call("patch_layout", Rect2(Vector2.ZERO, header.size))
			_expect(patches.size() == 9, "Room heading must use nine independent patches")
			for index in [0, 2, 6, 8]:
				var source: Rect2 = patches[index].source
				var destination: Rect2 = patches[index].destination
				_expect(absf(source.size.aspect() - destination.size.aspect()) < 0.001, "Gold rounded corners must scale uniformly at " + str(viewport))
			var font := header.get_theme_font("font")
			var font_size := header.get_theme_font_size("font_size")
			var available := header.size - surface.get_minimum_size() - Vector2.ONE * 6
			_expect(font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= available.x + 0.1, "Native room/round/remaining text must fit the gold rim at " + str(viewport))
			_expect(font.get_height(font_size) <= available.y + 0.1, "Bold room heading must fit the actual line height")
			_expect(header.text == caption, "Resize must not substitute static room data")
	header.queue_free()
	await process_frame
	if not _failed: print("MAHJONG_ROOM_HEADING_OK nine_patch=true corners_uniform=true native_dynamic_text=true ratios=4 captions=3")
	quit(1 if _failed else 0)
