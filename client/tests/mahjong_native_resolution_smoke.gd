extends SceneTree
## Native pixels, resize events and actual 3D projection; no network or saved player settings.

class Board:
	extends "res://modules/games/mahjong/guiyang/guiyang_3d_screen.gd"
	var submitted: Array = []
	func _connect_socket() -> void: pass
	func _actions_ready() -> bool: return true
	func _send_action(kind: String, tile_id: int = 0, _source_key: Array = [], _suit: String = "") -> void:
		submitted.append([kind, tile_id])

var _failed := false
var _records: Array = []
var _output := ""

func _initialize() -> void: call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error(message)

func _settle() -> void:
	for frame in 5: await process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func _native(area: Control, viewport: SubViewport, label: String) -> void:
	var canvas := area.get_viewport_transform() * area.get_global_transform()
	var physical := area.size * Vector2(canvas.x.length(), canvas.y.length())
	var target := Vector2i(physical.ceil())
	_check(viewport.size == target, "%s renders %s but occupies %s physical pixels" % [label, viewport.size, target])
	_check(is_equal_approx(viewport.scaling_3d_scale, 1.0), "%s must not upscale its internal 3D buffer" % label)
	if DisplayServer.get_name() != "headless":
		_check(Vector2i(viewport.get_texture().get_size()) == target, "%s GPU texture must match the physical display area" % label)
	_records.append({"case":label,"window":root.size,"display_px":target,"render_px":viewport.size,"scale":viewport.scaling_3d_scale})


func _verify_felt_coverage(board: Board, label: String) -> void:
	var felt := board._board_viewport.find_child("Mahjong_Felt_Surface", true, false) as MeshInstance3D
	_check(is_instance_valid(felt), "%s must render a real 3D felt surface" % label)
	if not is_instance_valid(felt): return
	var bounds: AABB = felt.global_transform * felt.get_aabb()
	_check(Vector2(bounds.size.x, bounds.size.z).is_equal_approx(Vector2(5.35, 5.35))
		and Vector2(bounds.get_center().x, bounds.get_center().z).is_zero_approx(),
		"%s must extend the 1.35 m table by exactly 2 m on each side" % label)
	var frame := board._board_viewport.find_child("SM_Mahjong_Table_Frame_RoundedAlloy", true, false) as MeshInstance3D
	_check(frame == null or not frame.is_visible_in_tree(), "%s must not render the table frame" % label)
	_check(board._board_view.get_rect().is_equal_approx(Rect2(Vector2.ZERO, board.size)),
		"%s must render the felt behind the entire window, including the header" % label)
	# The rendering projection can move the screen centre away from the node's forward axis.
	var center := board._camera.get_camera_projection().inverse() * Vector4(0, 0, 0, 1)
	var local_ray := Vector3(center.x, center.y, center.z) / center.w
	var rendered_ray := (board._camera.get_camera_transform().basis * local_ray).normalized()
	var pitch := rad_to_deg(asin(-rendered_ray.y))
	_check(absf(pitch - 35.0) <= 0.1, "%s rendered centre must look down at 35 degrees (got %.2f)" % [label, pitch])
	var pick_ray := board._camera.project_ray_normal(Vector2(board._board_viewport.size) * 0.5)
	_check(pick_ray.is_equal_approx(rendered_ray), "%s picking and rendering must agree at the screen centre" % label)
	var projection := board._camera.get_camera_projection()
	var focal_mm := 18.0 * minf(projection.x.x, projection.y.y)
	_check(is_equal_approx(focal_mm, 50.0), "%s must preserve a 50 mm lens on the 36 mm long edge of the film gate" % label)

	var plane := Plane(Vector3.UP, bounds.end.y)
	var width := board._board_viewport.size.x
	var height := board._board_viewport.size.y
	var corners := [Vector2(0.5, 0.5), Vector2(width - 0.5, 0.5),
		Vector2(0.5, height - 0.5), Vector2(width - 0.5, height - 0.5)]
	for corner: Vector2 in corners:
		var hit: Variant = plane.intersects_ray(board._camera.project_ray_origin(corner), board._camera.project_ray_normal(corner))
		_check(hit is Vector3 and hit.x >= bounds.position.x and hit.x <= bounds.end.x
			and hit.z >= bounds.position.z and hit.z <= bounds.end.z,
			"%s uncovered viewport corner %s" % [label, corner])
	if DisplayServer.get_name() != "headless":
		var rendered := board._board_viewport.get_texture().get_image()
		for corner: Vector2 in corners:
			var pixel := rendered.get_pixel(int(corner.x), int(corner.y))
			_check(pixel.a >= 0.98 and pixel.g > pixel.r, "%s corner %s must render green felt" % [label, corner])


func _verify_physical_tile(model: Node3D) -> void:
	var body := model.find_child("TileBody", true, false) as MeshInstance3D
	var axes := Transform3D(model.global_basis.orthonormalized(), model.global_position)
	var bounds: AABB = (axes.affine_inverse() * body.global_transform) * body.get_aabb()
	_check(bounds.size.is_equal_approx(Vector3(0.039, 0.028, 0.056)), "%s body measures %s metres" % [model.name, bounds.size])


func _verify_full_hand_framing(board: Board) -> void:
	for model: Node3D in board._pieces_root.get_children():
		if not model.is_queued_for_deletion(): _verify_physical_tile(model)
	var span: float = board._hand_models.back().global_position.x - board._hand_models.front().global_position.x + 0.039
	_check(is_equal_approx(span, 0.546), "The 14-tile hand must span 546 mm at every aspect ratio")
	var safe_area := Rect2(board._safe.x, board._safe.y, board.size.x - board._safe.x - board._safe.z, board.size.y - board._safe.y - board._safe.w)
	if safe_area.size.aspect() < 1.67: return
	var bounds := board._projected_tile_rect(board._hand_models[0], &"TileBody")
	for model: Node3D in board._hand_models: bounds = bounds.merge(board._projected_tile_rect(model, &"TileBody"))
	var tile_width := bounds.size.x / 14.0
	var left := bounds.position.x / tile_width
	var right := (board.size.x - bounds.end.x) / tile_width
	var pixels := (board.get_viewport_transform() * board.get_global_transform()).y.length()
	var bottom_px := (safe_area.end.y - bounds.end.y) * pixels
	var bottom_tiles := (safe_area.end.y - bounds.end.y) / tile_width
	var minimum_margin := maxf(board.size.x * 2.97 / (14.0 + 2.0 * 2.97), maxf(board._safe.x, board._safe.z))
	var north_top := INF
	for tile: Node3D in board._pieces_root.find_children("MahjongConcealedHand2_*", "Node3D", false, false):
		if tile.is_queued_for_deletion(): continue
		var north := board._projected_tile_rect(tile, &"TileBody")
		_check(safe_area.encloses(north), "The entire north hand must be within the safe frame")
		north_top = minf(north_top, north.position.y)
	var margin_px := (bounds.position.x - minimum_margin) * pixels
	_check(margin_px >= -2.0 and absf(bounds.position.x - (board.size.x - bounds.end.x)) * pixels < 2.0
		and (margin_px < 2.0 or (north_top - safe_area.position.y) * pixels <= 2.0)
		and safe_area.encloses(bounds), "Both rows must fit with centred south margins: %.3f / %.3f" % [left, right])
	var bottom_inset := board.HAND_BOTTOM_INSET * pixels
	_check(bottom_px >= bottom_inset - 0.01 and bottom_px <= bottom_inset + 3.0,
		"Resting hand must keep the camera's bottom inset: %.2f native pixels" % bottom_px)
	var selected := board._selected_id
	for index in [0, 13]:
		var resting: Transform3D = board._hand_models[index].global_transform
		board._select_tile(board._hand_ids[index])
		var lifted: Transform3D = board._hand_models[index].global_transform
		_check(lifted.basis.is_equal_approx(resting.basis) and (lifted.origin - resting.origin).is_equal_approx(Vector3.UP * board.OWN_HAND_LIFT),
			"Selecting either end tile must only lift it vertically")
		_verify_physical_tile(board._hand_models[index])
	board._selected_id = selected
	board._render_hand_only()
	_records.append({"case":"full_hand_framing","window":root.size,"hand_width_metres":span,"width_fraction":bounds.size.x/board.size.x,"left_tiles":left,"right_tiles":right,"bottom_tiles":bottom_tiles,"bottom_px":bottom_px,"vertical_fov_deg":board._camera.fov})


func _verify_tile_lighting(board: Board, quality: int) -> void:
	var frame := root.get_texture().get_image()
	var canvas := board._board_view.get_viewport_transform() * board._board_view.get_global_transform()
	# The upright hand, nearest river and farthest river face the lights at different angles.
	var models: Array[Node3D] = [board._hand_models[7], board._pieces_root.get_node("MahjongDiscard0_4"),
		board._pieces_root.get_node("MahjongDiscard2_5")]
	for model in models:
		var interior := Rect2i(canvas * board._projected_tile_rect(model)).grow(-3)
		if not interior.has_area() or not Rect2i(Vector2i.ZERO, frame.get_size()).encloses(interior):
			_check(false, "Lit tile face must be on screen")
			continue
		var luminance := PackedFloat32Array()
		var clipped := 0
		for y in range(interior.position.y, interior.end.y):
			for x in range(interior.position.x, interior.end.x):
				var pixel := frame.get_pixel(x, y)
				luminance.append(pixel.srgb_to_linear().get_luminance())
				if minf(pixel.r, minf(pixel.g, pixel.b)) >= 254.0 / 255.0: clipped += 1
		luminance.sort()
		var contrast := (luminance[luminance.size() * 9 / 10] + 0.05) / (luminance[luminance.size() / 10] + 0.05)
		var clipped_fraction := float(clipped) / luminance.size()
		var label := "%s quality %d" % [model.name, quality]
		_check(contrast > 2.5, "%s tile ink lost contrast (%.2f)" % [label, contrast])
		_check(clipped_fraction < 0.02, "%s ivory highlights clipped (%.1f%%)" % [label, 100.0 * clipped_fraction])
		_records.append({"case":label, "p90_p10_contrast":contrast, "clipped_fraction":clipped_fraction})


func _verify_hud_layout(board: Board) -> void:
	var heading := board._header.get_global_rect()
	var opposite := board._seat_panels[2].get_global_rect()
	var expected_left := board._safe.x + board._horizontal_screen_pixels(10.0)
	var expected_right := board.size.x - board._safe.z - board._horizontal_screen_pixels(10.0)
	var factor := minf(board.size.x / 1440.0, board.size.y / 810.0)
	var corner_inset := 12.0 * factor
	_check(board.find_child("MahjongTableBrandMark", true, false) == null, "The battle HUD must omit the logo")
	_check(is_equal_approx(heading.position.x, expected_left)
		and board._header.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT
		and is_equal_approx(heading.position.y, opposite.position.y),
		"Room heading must start at the top-left safe inset")
	for relative in 4:
		_check(board._wind_dial._winds[relative].text == ["南", "东", "北", "西"][relative], "Projected table directions must follow the screen")
		var nickname := board._seat_panels[relative].get_node("MahjongSeatNickname") as Label
		var previous_size := roundi(20 * factor)
		while previous_size > 10 and nickname.get_theme_font("font").get_height(previous_size) > 25 * factor: previous_size -= 1
		_check(nickname.get_theme_font_size("font_size") == maxi(10, previous_size - 2) + 2, "All four nicknames must gain exactly two points")
	var north_portrait := board._avatar_portraits[2].get_global_rect()
	var north_name := board._seat_panels[2].get_node("MahjongSeatNickname") as Label
	_check(is_equal_approx(opposite.end.x, expected_right) and is_equal_approx(opposite.position.y, board._safe.y + corner_inset)
		and north_portrait.end.x >= opposite.end.x - 5.1 * factor and north_name.get_global_rect().end.x <= north_portrait.position.x,
		"North portrait must hug the safe top-right corner with its name to the left")
	var toolbar := board._toolbar.get_global_rect()
	_check(not heading.intersects(opposite) and toolbar.position.y > opposite.end.y and is_equal_approx(toolbar.end.x, expected_right),
		"Room heading and north portrait must share the top edge with the tools below the portrait")
	var left := board._seat_panels[3].get_global_rect()
	var right := board._seat_panels[1].get_global_rect()
	var center_y := (board._safe.y + board.size.y - board._safe.w) * 0.5
	_check(is_equal_approx(left.position.x, expected_left) and is_equal_approx(right.end.x, expected_right)
		and is_equal_approx(left.get_center().y, center_y) and is_equal_approx(right.get_center().y, center_y),
		"Side players' cards must be centered vertically along the safe edges")
	for relative in [1, 2, 3]:
		var seat := board._seat_panels[relative].get_global_rect()
		for tile in board._pieces_root.find_children("MahjongConcealedHand%d_*" % relative, "Node3D", false, false):
			if tile.is_queued_for_deletion(): continue
			var body := board._projected_tile_rect(tile, &"TileBody")
			_check(not seat.grow(-1.0).intersects(body), "Portrait must clear %s at %s: %s and %s" % [tile.name, root.size, seat, body])
	var own_seat := board._seat_panels[0].get_global_rect()
	var south_portrait := board._avatar_portraits[0].get_global_rect()
	var south_balance := board._seat_panels[0].get_node("MahjongSeatEggs") as Label
	_check(is_equal_approx(own_seat.position.x, expected_left) and is_equal_approx(own_seat.end.y, board.size.y - board._safe.w - corner_inset)
		and south_portrait.end.y >= own_seat.end.y - 5.1 * factor and not own_seat.intersects(left),
		"South portrait must hug the safe bottom-left corner")
	_check(south_balance.get_global_rect().end.y <= south_portrait.position.y,
		"South captions must stack above its portrait to leave room for left-side public melds")
	for model in board._hand_models:
		_check(not own_seat.grow(-1.0).intersects(board._projected_tile_rect(model, &"TileBody")), "South portrait must clear all local hand tiles")
	_check(not board._turn_label.visible and board._turn_label.text.is_empty(), "Local discard turn must have no reminder text")
	var saved_turn: int = board._state.turn
	var deadline := board._deadline_tick
	board._deadline_tick = Time.get_ticks_msec() + 10000
	for seat in [0, 2]:
		board._state.turn = seat
		board._position_avatar_clock()
		_check(board._remaining_number.visible and board._avatar_portraits[seat].get_global_rect().grow(1.0).encloses(board._remaining_number.get_global_rect()),
			"The countdown must follow the active avatar to its corner")
	board._deadline_tick = deadline
	board._state.turn = 1
	board._update_context_labels()
	var turn := board._turn_label.get_global_rect()
	_check(board._turn_label.visible and board._turn_label.text == "等待牌友" and turn.end.y <= own_seat.position.y and turn.position.y >= board._safe.y
		and is_equal_approx(turn.get_center().x, own_seat.get_center().x),
		"Waiting status must return above the local portrait when the turn changes")
	board._state.turn = saved_turn
	board._update_context_labels()
	var tools := board._side_tools.get_global_rect()
	var mic := board._own_mic.get_global_rect()
	var beside := is_equal_approx(tools.end.y, mic.end.y) and tools.end.x < mic.position.x
	var above := is_equal_approx(tools.end.x, mic.end.x) and tools.end.y < mic.position.y
	_check(is_equal_approx(mic.end.x, expected_right) and (beside or above)
		and mic.end.y <= board.size.y - board._safe.w,
		"Chat, emoji and microphone must share the bottom-right safe area")
	# Refit a long room ID against the same bounds used by an ordinary snapshot.
	var room_id: Variant = board._state.room_id
	board._state.room_id = "1234567890123456"
	board._state.round_limit = 24
	board._state.completed_rounds = 23
	board._update_context_labels()
	var font := board._header.get_theme_font("font")
	var pixels := font.get_string_size(board._header.text, HORIZONTAL_ALIGNMENT_LEFT, -1, board._header.get_theme_font_size("font_size"))
	_check(board._header.get_global_rect().is_equal_approx(heading) and pixels.x <= heading.size.x and pixels.y <= heading.size.y,
		"A long room ID, round and wall count must fit without moving the heading")
	board._state.room_id = room_id
	board._state.erase("round_limit")
	board._state.erase("completed_rounds")
	board._update_context_labels()


func _run() -> void:
	Engine.max_fps = 0
	if DisplayServer.get_name() != "headless": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): _output = arg.trim_prefix("--output=")
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1440, 810)
	root.size = Vector2i(2560, 1440)
	var board := Board.new()
	board.preserve_window_size = true
	board.preference_file = "user://native-resolution-fixture.cfg"
	board.match_context = {"room_id":"3481","seat_index":0}
	root.add_child(board)
	var hand: Array = []
	for i in 14: hand.append({"id":i+1,"suit":["wan","tong","tiao"][i%3],"rank":i%9+1})
	var discards: Array = []
	for seat in 4:
		for i in 6: discards.append({"seat":seat,"tile":{"id":100+seat*6+i,"suit":["wan","tong","tiao"][i%3],"rank":i+1},"claimed":false})
	board._state = {"room_id":"3481","match_id":"native-resolution","status":"playing","phase":"turn","your_seat":0,"turn":0,"dealer":2,
		"players":["me","east","north","west"],"player_names":["村口阿牛","田埂阿梅","稻香大叔","河湾老张"],"egg_counts":[500,500,500,500],
		"hand":hand,"hand_counts":[14,13,13,13],"melds":[[],[],[],[]],"discards":discards,"remaining":46,"options":[{"type":"play"}],"drawn_tile_id":14}
	board._render()
	var well := board._wind_dial.get_node("TimerWell") as MeshInstance3D
	var well_material := well.material_override as StandardMaterial3D
	var rim := board._wind_dial.get_node("WoodenBody") as MeshInstance3D
	var rim_box := rim.global_transform * rim.get_aabb()
	_check(absf(rim_box.size.x - 0.294 * 0.72) < 0.0001 and is_equal_approx(rim_box.size.x, rim_box.size.z),
		"Wind dial must keep a round 72 percent footprint in world space")
	_check(well_material.albedo_color.is_equal_approx(Color("#101010"))
		and board._wind_dial.get_timer_position().y < 0.025,
		"Wind dial must have a black center and lower projection height")
	for dimensions in [Vector2i(720,1280),Vector2i(1280,720),Vector2i(1920,864),Vector2i(1920,1200),Vector2i(1600,1200),Vector2i(2560,1440)]:
		root.size = dimensions
		await _settle()
		for quality in 3:
			board._set_quality(quality)
			await _settle()
			_native(board._board_view, board._board_viewport, "board_%dx%d_q%d" % [dimensions.x,dimensions.y,quality])
			if dimensions == Vector2i(1280,720) and DisplayServer.get_name() != "headless":
				_verify_tile_lighting(board, quality)
			var display := board._board_surface.get_viewport_transform() * board._board_surface.get_global_transform()
			_check(display.get_scale().is_equal_approx(Vector2.ONE) and not board._board_surface.stretch, "Board must present each rendered pixel at 1:1")
		_verify_full_hand_framing(board)
		_verify_felt_coverage(board, "%dx%d" % [dimensions.x, dimensions.y])
		_verify_hud_layout(board)
		board._select_tile(0)
		var tap := InputEventScreenTouch.new()
		tap.pressed = true
		tap.position = board._board_view.get_viewport_transform() * board._board_view.get_global_transform() * board._projected_tile_rect(board._hand_models[5]).get_center()
		Input.parse_input_event(tap)
		await process_frame
		_check(board._selected_id == 6, "Native resize must preserve actual GUI tile picking at %s" % dimensions)
		tap.pressed = false
		Input.parse_input_event(tap)
		if not _output.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			_check(root.get_texture().get_image().save_png(_output.path_join("board_%dx%d.png" % [dimensions.x,dimensions.y])) == OK, "Native capture saves")
	board._apply_camera_impact(0.11, 5.0)
	await _settle()
	_verify_felt_coverage(board, "play effect")
	board._stop_camera_impact()
	board.match_context.merge({"spectating":true,"watch_seat":0}, true)
	board._state.hand = []
	board._render()
	for dimensions in [Vector2i(800,450), Vector2i(1600,720)]:
		root.size = dimensions
		await _settle()
		var near_row := board._pieces_root.find_children("MahjongConcealedHand0_*", "Node3D", false, false)
		_check(near_row.size() == 14, "Spectating must render all fourteen near tile backs")
		for tile: Node3D in near_row:
			_check(board._board_view.get_rect().encloses(board._projected_tile_rect(tile, &"TileBody")),
				"Spectator camera must include the full near tile back at %s" % [dimensions])
	board.queue_free()
	await _settle()
	root.content_scale_size = Vector2i(1440,810)
	root.size = Vector2i(2560,1440)
	var guided = load("res://modules/games/mahjong/guiyang/mahjong_guided_view.gd").new()
	guided.size = Vector2(760,700)
	root.add_child(guided)
	await _settle()
	_native(guided._preview, guided._viewport, "guided_scaled_canvas")
	for model: Node3D in guided._pieces.get_children(): _verify_physical_tile(model)
	guided.scale = Vector2.ONE * 1.25
	await _settle()
	_native(guided._preview, guided._viewport, "guided_parent_scale")
	guided.queue_free()
	await _settle()
	var detail = load("res://modules/games/mahjong/guiyang/mahjong_efficiency_detail.gd").new()
	root.add_child(detail)
	var entries: Array[Dictionary] = [{"suit":"wan","rank":3,"title":"三万","count":4},{"suit":"tong","rank":8,"title":"八筒","count":3}]
	detail.show_result("进张明细", entries, "", Rect2(Vector2.ZERO,root.get_visible_rect().size))
	await _settle()
	_native(detail._tray, detail._viewport, "detail_scaled_canvas")
	for model: Node3D in detail._models: _verify_physical_tile(model)
	detail.hide()
	root.size = Vector2i(1920,1080)
	await _settle()
	detail.show_result("进张明细", entries, "", Rect2(Vector2.ZERO,root.get_visible_rect().size))
	await _settle()
	_native(detail._tray, detail._viewport, "detail_hidden_resize_restore")
	detail.queue_free()
	await _settle()
	# A legacy host's viewport stretch would resample even a full-size 3D target.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = Vector2i(1440,810)
	root.size = Vector2i(2560,1440)
	var legacy := Board.new()
	legacy.preserve_window_size = true
	legacy.preference_file = "user://native-resolution-fixture.cfg"
	root.add_child(legacy)
	await _settle()
	_check(root.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS, "3D views must prevent final-window image upscaling")
	_native(legacy._board_view, legacy._board_viewport, "legacy_host_board")
	legacy.queue_free()
	await _settle()
	_check(root.content_scale_mode == Window.CONTENT_SCALE_MODE_VIEWPORT, "Last 3D view must restore its host's display policy")
	if not _output.is_empty():
		FileAccess.open(_output.path_join("resolution.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":not _failed,"cases":_records,"renderer":RenderingServer.get_current_rendering_method(),"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode()},"\t"))
	print("MAHJONG_NATIVE_RESOLUTION_OK" if not _failed else "MAHJONG_NATIVE_RESOLUTION_FAILED")
	quit(int(_failed))
