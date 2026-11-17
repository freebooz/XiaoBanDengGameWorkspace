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
	for dimensions in [Vector2i(1280,720),Vector2i(1920,864),Vector2i(1920,1200),Vector2i(1600,1200),Vector2i(2560,1440)]:
		root.size = dimensions
		await _settle()
		for quality in 3:
			board._set_quality(quality)
			await _settle()
			_native(board._board_view, board._board_viewport, "board_%dx%d_q%d" % [dimensions.x,dimensions.y,quality])
			var display := board._board_surface.get_viewport_transform() * board._board_surface.get_global_transform()
			_check(display.get_scale().is_equal_approx(Vector2.ONE) and not board._board_surface.stretch, "Board must present each rendered pixel at 1:1")
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
	board.queue_free()
	await _settle()
	root.content_scale_size = Vector2i(1440,810)
	root.size = Vector2i(2560,1440)
	var guided = load("res://modules/games/mahjong/guiyang/mahjong_guided_view.gd").new()
	guided.size = Vector2(760,700)
	root.add_child(guided)
	await _settle()
	_native(guided._preview, guided._viewport, "guided_scaled_canvas")
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
