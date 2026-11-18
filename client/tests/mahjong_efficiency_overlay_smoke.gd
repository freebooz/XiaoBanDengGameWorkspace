extends SceneTree

const OVERLAY := preload("res://modules/games/mahjong/guiyang/mahjong_efficiency_overlay.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error(message)


func _run() -> void:
	Engine.max_fps = 0
	if DisplayServer.get_name() != "headless": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.content_scale_size = Vector2i.ZERO
	var overlay := OVERLAY.new()
	root.add_child(overlay)
	var capture_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preview="): capture_path = arg.trim_prefix("--preview=")
	var rank_one := {"shanten": {"minimum": 0}, "ukeireCount": 3, "ukeire": [
		{"tile": 21, "count": 1}, {"tile": 24, "count": 2},
	], "rank": 1, "legalWaits": "not_checked", "risk": {"level": "high"}}
	var rank_two := {"shanten": {"minimum": 1}, "ukeireCount": 31, "ukeire": [], "rank": 2,
		"analysisMode": "discard", "lookAheadEvaluated": true, "q": 160,
		"riskReasons": PackedStringArray(["elevated", "supply_blocked", "unknown"]), "rankingReason": "k", "k": 286}
	var rank_three := {"shanten": {"minimum": 1}, "ukeireCount": 16, "ukeire": [], "rank": 3}
	var result := {1: rank_one, 2: rank_two, 3: rank_one, 4: rank_three, 14: {"shanten": {"minimum": 0}, "ukeireCount": -2}}
	for entry in [{"id":5,"shanten":2}, {"id":6,"shanten":3}, {"id":7,"shanten":4}, {"id":8,"shanten":8}, {"id":9,"shanten":1}]:
		# A valid analysis without ranking metadata must still use shanten color.
		result[entry.id] = {"shanten":{"minimum":entry.shanten},"ukeireCount":12,"ukeire":[]}
	var green := Color("#59c989")
	var yellow_green := Color("#afd254")
	var yellow := Color("#f1cc61")
	for viewport_size: Vector2 in [Vector2(1280, 720), Vector2(1600, 720), Vector2(1280, 800), Vector2(1200, 900)]:
		root.size = Vector2i(viewport_size)
		overlay.size = viewport_size
		await process_frame
		var tiles: Array = []
		var origin := Vector2(viewport_size.x * 0.075, viewport_size.y * 0.80)
		var stride := viewport_size.x * 0.06
		for index in 14:
			var y := -23.0 if index == 0 else 0.0
			tiles.append({"id": index + 1, "rect": Rect2(origin + Vector2(index * stride, y), Vector2(stride + 3.0, 84.0))})
		overlay.present(tiles, result, 1)
		_expect(overlay.get_child_count() == 15, "exactly one overlay badge per tile")
		var previous := Rect2()
		for id in range(1, 15):
			var badge: Control = overlay.get_node("MahjongEfficiencyBadge%d" % id)
			var global_badge: Rect2 = Rect2(badge.position + badge.badge_rect.position, badge.badge_rect.size)
			var face: Rect2 = tiles[id - 1].rect
			_expect(is_equal_approx(global_badge.size.y, 64.0 / 3.0), "Badge height must be two thirds of its original 32 units")
			_expect(badge.mouse_filter == Control.MOUSE_FILTER_IGNORE, "badge must not intercept touch")
			_expect(Rect2(Vector2.ZERO, viewport_size).encloses(global_badge), "badge stays in screen")
			_expect(not previous.intersects(global_badge), "adjacent compact badges stay separate")
			_expect(global_badge.position.y > face.end.y and is_equal_approx(global_badge.get_center().x, face.get_center().x),
				"badge is centered below the tile, including after selection lifts it")
			for tile in tiles:
				_expect(not global_badge.intersects(tile.rect), "no badge can cover a tile")
			previous = global_badge
		var best: Control = overlay.get_node("MahjongEfficiencyBadge1")
		var second: Control = overlay.get_node("MahjongEfficiencyBadge2")
		var duplicate: Control = overlay.get_node("MahjongEfficiencyBadge3")
		var last: Control = overlay.get_node("MahjongEfficiencyBadge4")
		var invalid: Control = overlay.get_node("MahjongEfficiencyBadge14")
		_expect(best.text == "0·3" and best.badge_color == green, "zero shanten uses green")
		_expect(second.text == "1·31" and second.badge_color == yellow_green, "one shanten uses yellow-green")
		_expect(last.text == "1·16" and last.badge_color == second.badge_color,
			"equal shanten uses the same color despite different ranks and ukeire counts")
		_expect(overlay.get_node("MahjongEfficiencyBadge5").badge_color == yellow, "two shanten uses yellow without rank metadata")
		_expect(overlay.get_node("MahjongEfficiencyBadge6").badge_color == Color("#f29c45"), "three shanten uses orange")
		_expect(overlay.get_node("MahjongEfficiencyBadge7").badge_color == Color("#c84242")
			and overlay.get_node("MahjongEfficiencyBadge8").badge_color == Color("#c84242"), "four and higher shanten use red")
		_expect(overlay.get_node("MahjongEfficiencyBadge7").text_color == Color.WHITE,
			"red badges use readable white text")
		_expect(overlay.get_node("MahjongEfficiencyBadge9").badge_color == yellow_green,
			"missing recommendation rank does not hide valid shanten color")
		_expect(best.recommended and best.selected and not second.recommended, "recommendation follows rank independently of selection")
		_expect(best.text == duplicate.text and best.badge_color == duplicate.badge_color,
			"identical ranks share the same value and color")
		_expect(not best.high_risk and invalid.text == "—", "unverified risk absent, invalid counts unavailable")
		var detail: Control = overlay.get_node("MahjongEfficiencyDetail")
		_expect(not detail.visible, "selecting the tile does not open the detail panel")
		await _click(best.get_node("Inspect"))
		_expect(detail.visible and detail._tile_root.get_child_count() == 2, "badge opens a shared 3D viewport with both effective tiles")
		var first: Node3D = detail._tile_root.get_node("MahjongEffectiveTile_tiao_4")
		var face := first.find_child("TileFace", true, false) as MeshInstance3D
		var body := first.find_child("TileBody", true, false) as MeshInstance3D
		_expect(face != null and face.mesh != null and face.material_override.resource_name == "Mahjong50Face_1:4"
			and body != null and body.mesh != null, "preview uses the live table's engraved face and full 3D tile body")
		_expect(detail._captions[0].text == "四条  1 张" and detail._captions[1].text == "七条  2 张",
			"each actual model has the correct unseen count")
		_expect("和牌资格未校验" in detail._note.text and detail.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"structure alone does not claim legal win; the overlay does not block the screen")
		_expect(not "Q=" in detail._note.text, "Uncomputed look-ahead must not display a misleading zero score")
		var frame: Rect2 = detail._frame.get_global_rect()
		_expect(frame.get_center().distance_to(viewport_size * 0.5) <= 2.0, "detail opens at screen center")
		if not capture_path.is_empty() and viewport_size.x == 1280 and viewport_size.y == 720 and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			_expect(root.get_texture().get_image().save_png(capture_path) == OK, "3D preview screenshot saves")
		await _click(detail.find_child("MahjongCloseEfficiencyDetail", true, false))
		_expect(not detail.visible and best.selected, "closing the detail leaves the selected hand unchanged")
		await _click(second.get_node("Inspect"))
		_expect("靠张改良 286" in detail._note.text and "信息不足 1 家" in detail._note.text,
			"Details explain the contextual tie-break and identify incomplete opponent information")
		_expect("推荐第 2" in detail._summary.text and "Q=160" in detail._note.text
			and "K=286" in detail._note.text and "非胡牌概率" in detail._note.text,
			"Details expose the computed native ranking and both tie metrics without inventing win probability")
		_expect(Rect2(Vector2.ZERO, viewport_size).encloses(detail._frame.get_global_rect()),
			"Contextual reasons fit in the details at every tested aspect ratio")
		if not capture_path.is_empty() and viewport_size.x == 1280 and viewport_size.y == 720 and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			_expect(root.get_texture().get_image().save_png(capture_path.get_basename() + "_tie.png") == OK,
				"Contextual recommendation screenshot saves")
		await _click(detail.find_child("MahjongCloseEfficiencyDetail", true, false))
		overlay.present(tiles, {1: rank_one}, 0)
		_expect(best.badge_color == green and last.text == "—" and last.badge_color == invalid.badge_color,
			"a sole legal candidate stays green and stale data clears")
	overlay.clear()
	_expect(overlay.get_child_count() == 1 and not overlay.get_child(0).visible, "decision end removes all badges immediately")
	if not _failed:
		print("MAHJONG_EFFICIENCY_OVERLAY_OK fixed_shanten_colors=true landscape_4x3_through_20x9=true centered_glb_tiles=true true_counts=true")
	quit(int(_failed))


func _click(button: Button) -> void:
	if DisplayServer.get_name() == "headless":
		button.pressed.emit()
	else:
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = button.get_global_rect().get_center()
			event.pressed = pressed
			root.push_input(event, true)
	for frame in 5: await process_frame
