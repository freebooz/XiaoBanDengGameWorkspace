extends SceneTree
## Drives the production Mahjong views with isolated account and room snapshots.

const APP := preload("res://scripts/main.gd")
const REFERENCE_SIZE := Vector2i(941, 1672)
const WINDOW_SIZES := [
	REFERENCE_SIZE, Vector2i(390, 844), Vector2i(1280, 720), Vector2i(1600, 720),
	Vector2i(1024, 768), Vector2i(1280, 800), Vector2i(1440, 900), Vector2i(2024, 1620),
]
const PREVIEW_SIZES := [REFERENCE_SIZE, Vector2i(390, 844), Vector2i(1600, 720), Vector2i(2024, 1620)]

class AppFixture extends APP:
	var lobby_entries := 0
	var commands: Array[Dictionary] = []

	func _request_health() -> void:
		_show_login()

	func _send_session_request(_kind: String, _url: String, _token: String) -> Error:
		return OK

	func _start_lobby_connection() -> void:
		lobby_entries += 1

	func _refresh_history() -> void:
		pass

	func _refresh_eggs() -> void:
		pass

	func _send_lobby_packet(packet: Dictionary) -> Error:
		commands.append(packet)
		return OK

var _app: AppFixture
var _failures: Array[String] = []
var _preview_dir := ""
var _previews := 0
var _layouts := 0
var _settings_layouts := 0
var _brand: Texture2D


func _initialize() -> void:
	call_deferred("_run")


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)


func _node(name: String) -> Control:
	return _app.find_child(name, true, false) as Control


func _visible(name: String) -> bool:
	var target := _node(name)
	return target != null and target.is_visible_in_tree()


func _frames() -> void:
	for _index in range(5):
		await process_frame


func _reveal(control: Control) -> void:
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(control)
			await _frames()
		ancestor = ancestor.get_parent()


func _inside_clipped_area(control: Control, point: Vector2) -> bool:
	if not _app._screen.get_global_rect().has_point(point):
		return false
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is Control and ancestor.clip_contents and not ancestor.get_global_rect().has_point(point):
			return false
		ancestor = ancestor.get_parent()
	return true


func _press(name: String) -> void:
	var button := _node(name) as Button
	if button == null or not button.is_visible_in_tree() or button.disabled:
		_failures.append("Unavailable button: " + name)
		return
	if DisplayServer.get_name() == "headless":
		button.pressed.emit()
	else:
		await _reveal(button)
		var point := button.get_global_rect().get_center()
		if not _inside_clipped_area(button, point):
			_failures.append("Button cannot be reached by scrolling: " + name + " at " + str(root.size))
			return
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = point
			event.pressed = pressed
			root.push_input(event, true)
	await _frames()


func _header(back_id: String) -> void:
	var back := _node(back_id)
	if back == null or not back.is_visible_in_tree():
		_expect(false, "Missing page back: " + back_id)
		return
	var header := back.get_parent()
	_expect(header.name == "MahjongVillageHeader", "Back uses common header: " + back_id)
	var logo := header.get_child(0) as TextureRect
	_expect(logo != null and logo.is_visible_in_tree() and logo.texture != null, "Shared header has a brand texture")
	if logo != null:
		if _brand == null:
			_brand = logo.texture
		_expect(logo.texture == _brand, "These pages share a single brand texture: " + back_id)
		_expect(logo.get_global_rect().end.x <= back.get_global_rect().position.x, "Brand is left of the back button")
		_expect(_app._screen.get_global_rect().grow(1.0).encloses(logo.get_global_rect()),
			"Brand fits the window at %s: %s" % [root.size, back_id])
	_expect(_inside_clipped_area(back, back.get_global_rect().get_center()),
		"Back is reachable at %s: %s" % [root.size, back_id])


func _check_layouts(page: String, back_id: String, action_id: String) -> void:
	for dimensions in WINDOW_SIZES:
		root.size = dimensions
		await _frames()
		_expect(root.size == dimensions, "Window reached the requested dimensions at %s on %s" % [dimensions, page])
		_header(back_id)
		if page in ["03_create", "04_join", "05_directory"]:
			var rooms: Control = _app._lobby_view._room_pages
			var title: Label = rooms._join_title if page == "04_join" else rooms._plaque
			_title_overlap(title.get_parent(), rooms._frame, str([page, dimensions]))
		_check_room_control_heights(page, dimensions)
		if page == "01_guest":
			_check_guest_proportions(dimensions)
		var action := _node(action_id)
		_expect(action != null and action.is_visible_in_tree(), "Visible primary control on " + page)
		if action != null:
			var control := action.get_global_rect()
			var screen := _app._screen.get_global_rect().grow(1.0)
			_expect(control.position.x >= screen.position.x and control.end.x <= screen.end.x,
				"Primary control fits horizontally on %s at %s: %s" % [page, dimensions, control])
			_expect(control.size.x > 0 and control.size.y > 0, "Primary control has a hit area on " + page)
		_layouts += 1
		print("MAHJONG_HARVEST_LAYOUT page=%s requested=%dx%d window=%dx%d" %
			[page, dimensions.x, dimensions.y, root.size.x, root.size.y])
		if not _preview_dir.is_empty() and dimensions in PREVIEW_SIZES:
			await RenderingServer.frame_post_draw
			var shot := root.get_texture().get_image()
			_expect(shot != null and shot.get_size() == dimensions,
				"Native capture has requested dimensions on %s at %s" % [page, dimensions])
			if shot != null and shot.get_size() == dimensions:
				var filename := "%s_%dx%d.png" % [page, dimensions.x, dimensions.y]
				var result := shot.save_png(_preview_dir.path_join(filename))
				_expect(result == OK, "Native capture saved: " + filename)
				if result == OK:
					_previews += 1
		if action != null:
			await _reveal(action)
			_expect(_inside_clipped_area(action, action.get_global_rect().get_center()),
				"Primary control is reachable at %s on %s" % [dimensions, page])
		var back := _node(back_id)
		if back != null:
			await _reveal(back)
	root.size = REFERENCE_SIZE
	await _frames()
	_check_room_control_heights(page, REFERENCE_SIZE)


func _check_guest_proportions(dimensions: Vector2i) -> void:
	var button := _node("MahjongGuestEnterLobbyButton")
	var guest: Control = _app._guest_identity_view
	_expect(guest != null, "Guest page remains a native container composition")
	if guest == null: return
	var panel: Control = guest._panel
	_expect(absf(panel.get_global_rect().get_center().x - dimensions.x * 0.5) <= 2.0,
		"Guest paper panel stays centered: " + str(dimensions))
	_expect(button.size.y <= button.custom_minimum_size.y + 1.0,
		"Guest action does not absorb spare viewport height: " + str(dimensions))
	var avatar: Control = guest._portrait
	_expect(absf(avatar.size.x - avatar.size.y) < 1.0, "Guest portrait stays square")
	if dimensions == REFERENCE_SIZE:
		_expect(button.size.y >= 145 and button.size.y <= 160, "Guest action follows the approved 156px reference height")
		_expect(panel.get_global_rect().position.y >= 480 and panel.get_global_rect().position.y <= 520,
			"Guest panel keeps the reference scenery-to-form balance")


func _check_room_control_heights(page: String, dimensions: Vector2i) -> void:
	if page not in ["03_create", "04_join", "05_directory"]:
		return
	var rooms: Control = _app._lobby_view._room_pages
	var panel: Control = rooms._frame
	_expect(panel.size.x <= (910.0 if page == "05_directory" else 1080.0) + 1.0,
		"Room panel keeps its designed width at " + str(dimensions))
	_expect(absf(panel.get_global_rect().get_center().x - rooms.get_global_rect().get_center().x) <= 1.0,
		"Room panel remains centered in its scrollable content at " + str(dimensions))
	if page != "05_directory":
		var submit: Button = rooms._create_submit if page == "03_create" else rooms._join_submit
		_expect(submit.size.aspect() >= 2.8 and submit.size.aspect() <= 5.25,
			"Room action keeps button proportions at %s: %s" % [dimensions, submit.size])
	if dimensions not in PREVIEW_SIZES or OS.has_feature("mobile"):
		return
	var large_portrait := dimensions == REFERENCE_SIZE or dimensions == Vector2i(2024, 1620)
	var field_height := 91.0 if large_portrait else 49.0
	if page == "03_create":
		for id in ["MahjongCreateRoomPassword", "MahjongCreateRoomCodeValue", "MahjongTurnTimeoutSeconds",
				"MahjongRoomRounds8", "MahjongRoomRounds16", "MahjongRoomRounds24"]:
			_expect_control_height(_node(id), field_height, id)
	elif page == "04_join":
		var code_height := 120.0 if large_portrait else 60.0 if dimensions.x == 390 else 65.0
		var key_height := 99.0 if large_portrait else 53.0
		_expect_control_height(_node("MahjongJoinCode"), code_height, "room code input")
		_expect_control_height(_node("MahjongJoinRoomPassword"), field_height, "join password")
		for digit: Label in rooms._code_digits:
			_expect_control_height(digit.get_parent(), code_height, "room code digit slot")
		for suffix in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "Clear", "Backspace"]:
			_expect_control_height(_node("MahjongRoomKey" + suffix), key_height, "keypad " + suffix)


func _expect_control_height(control: Control, expected: float, name: String) -> void:
	_expect(control != null and is_equal_approx(control.custom_minimum_size.y, expected) and control.size.y >= expected - 1.0,
		"%s preserves its designed height at %s: expected %s, got %s" %
		[name, root.size, expected, control.custom_minimum_size.y if control != null else "missing"])


func _last_command(action: String) -> Dictionary:
	for index in range(_app.commands.size() - 1, -1, -1):
		var packet := _app.commands[index]
		if packet.get("action") == action:
			return packet
	return {}


func _title_overlap(plate: Control, frame: Control, context: String) -> void:
	var title_rect := plate.get_global_rect()
	var panel_rect := frame.get_global_rect()
	var border_y := panel_rect.position.y + float(frame.get_meta("title_border_offset", 0))
	_expect(title_rect.get_center().distance_to(Vector2(panel_rect.get_center().x, border_y)) < 1.1,
		"Title centers on the visible upper bamboo edge: " + context)
	_expect(_app._screen.get_global_rect().grow(1.0).encloses(title_rect), "Title fits the screen: " + context)


func _check_settings() -> void:
	await _press("MahjongSettingsButton")
	var panel := _node("MahjongToolPanel_settings")
	_expect(panel != null, "Real lobby settings entry opens the shared modal")
	var coach := _node("MahjongCoachToggle") as Button
	_expect(coach != null and not coach.button_pressed, "Efficiency cues default off")
	await _press("MahjongCoachToggle")
	_expect(coach.button_pressed, "Mouse enables actual efficiency cues")
	await _press("MahjongCoachToggle")
	var pages := ["basic", "audio", "graphics", "rules"]
	for dimensions in WINDOW_SIZES:
		root.size = dimensions
		await _frames()
		for index in pages.size():
			var id := "MahjongSettingsTab%d" % index
			await _press(id)
			_expect((_node(id) as Button).button_pressed, "Settings category is selected: " + id)
			_expect(_app._screen.get_global_rect().grow(1.0).encloses(panel.get_global_rect()), "Settings fits: " + str(dimensions))
			var frame := panel.get_child(0) as PanelContainer
			var title := frame.find_children("*", "Label", true, false).filter(func(label: Label) -> bool: return label.text == "游戏设置").front() as Label
			_title_overlap(title.get_parent(), frame, "settings " + str(dimensions))
			_settings_layouts += 1
			if not _preview_dir.is_empty() and dimensions in PREVIEW_SIZES:
				await RenderingServer.frame_post_draw
				var filename := "settings_%s_%dx%d.png" % [pages[index], dimensions.x, dimensions.y]
				var result := root.get_texture().get_image().save_png(_preview_dir.path_join(filename))
				_expect(result == OK, "Native settings capture saved: " + filename)
				if result == OK: _previews += 1
	root.size = REFERENCE_SIZE
	await _frames()
	await _press("MahjongSettingsTab1")
	var music := _node("MahjongMusicToggle") as Button
	var previous_music := music.button_pressed
	await _press("MahjongMusicToggle")
	_expect(music.button_pressed != previous_music, "Music preference changes on click")
	await _press("MahjongMusicToggle")
	await _press("MahjongSettingsTab2")
	await _press("MahjongQuality2")
	_expect((_node("MahjongQuality2") as Button).button_pressed, "Rendering preference changes on click")
	await _escape()
	_expect(not _visible("MahjongToolPanel_settings"), "Escape closes settings")


func _reject(action: String, message: String, code: String) -> void:
	var packet := _last_command(action)
	if not packet.is_empty():
		_app._on_lobby_result(str(packet.command_id), false, message, code)
	await _frames()
	if is_instance_valid(_app._error_dialog):
		_expect(code in _node("MahjongErrorCode").text, "Server rejection keeps its actual code")
		await _press("MahjongErrorConfirmButton")


func _escape() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.pressed = pressed
		root.push_input(event, true)
	await _frames()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preview-dir="):
			_preview_dir = arg.trim_prefix("--preview-dir=")
	if not _preview_dir.is_empty():
		if DisplayServer.get_name() == "headless":
			push_error("Native preview requires a graphics display driver.")
			quit(1)
			return
		if DirAccess.make_dir_recursive_absolute(_preview_dir) != OK:
			push_error("Cannot make preview directory.")
			quit(1)
			return
	root.size = REFERENCE_SIZE
	_app = AppFixture.new()
	_app.session_store_path = "user://harvest-ui-smoke-%d" % OS.get_process_id()
	_app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_app)
	await _frames()
	await _press("MahjongGuestLoginButton")
	_app._http.request_completed.emit(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(),
		JSON.stringify({"account_id":"harvest-self", "display_name":"小板凳验收牌友", "session_token":"AbC_1-".repeat(7) + "A"}).to_utf8_buffer())
	await _frames()
	_expect(_app._state == "guest_identity", "Guest login opens the guest identity page")
	var guest_name := _node("MahjongGuestNickname") as Label
	_expect(guest_name != null and guest_name.text == "小板凳验收牌友", "Guest title uses the server identity")
	await _check_layouts("01_guest", "MahjongGuestIdentityBackButton", "MahjongGuestEnterLobbyButton")
	await _press("MahjongGuestEnterLobbyButton")
	_expect(_app.lobby_entries == 1, "The guest action enters the lobby exactly once")
	var rules := [{"rule_set_id":"guiyang","rule_version":"2.0.0","name":"贵阳捉鸡","summary":"四人贵阳捉鸡"},
		{"rule_set_id":"basic_108","rule_version":"1.0.0","name":"基础 108","summary":"四人基础麻将"}]
	_app._room_directory_available = true
	_app._egg_balance = 1280
	_app._on_lobby_state({"status":"idle"}, rules)
	await _frames()
	await _check_layouts("02_lobby", "MahjongLobbyBackButton", "MahjongQuickButton")
	await _check_settings()
	await _press("MahjongCreateButton")
	_expect(_visible("MahjongCreateRuleSelector") and not _visible("MahjongCreateRuleCards"),
		"Room creation shows a compact rule selector first")
	await _press("MahjongCreateRuleSelector")
	_expect(_visible("MahjongCreateRuleCard_guiyang_2_0_0") and _visible("MahjongCreateRuleCard_basic_108_1_0_0"),
		"Opening the rule selector displays the exact server presets")
	await _press("MahjongCreateRuleCard_guiyang_2_0_0")
	_expect(not _visible("MahjongCreateRuleCards"), "Selecting a rule returns to the compact create form")
	await _check_layouts("03_create", "MahjongCustomRulesBackButton", "MahjongCustomRulesCreateButton")
	await _press("MahjongRoomRounds16")
	await _press("MahjongCustomRulesCreateButton")
	var create := _last_command("create")
	_expect(create.get("round_limit") == 16 and str(create.get("room_id", "")).length() == 4,
		"Create forwards the chosen round limit and a real four-digit room code")
	await _reject("create", "该房号已被使用", "room_conflict")
	_expect(_visible("MahjongCreateRuleSelector"), "Create remains on its form after a server error")
	await _press("MahjongCustomRulesBackButton")
	await _press("MahjongOpenJoinButton")
	for key in ["4", "8", "2", "6"]:
		await _press("MahjongRoomKey" + key)
	var code := _node("MahjongJoinCode") as LineEdit
	_expect(code != null and code.text == "4826", "The native keypad updates the code")
	await _check_layouts("04_join", "MahjongCloseJoinButton", "MahjongJoinButton")
	_expect(is_instance_valid(code) and code == _node("MahjongJoinCode") and code.text == "4826",
		"Changing window size preserves entered room code")
	await _press("MahjongJoinButton")
	_expect(_last_command("join").get("room_id") == "4826", "Join sends the room code typed on the keypad")
	await _reject("join", "房间需要密码", "room_password_required")
	var password := _node("MahjongJoinRoomPassword") as LineEdit
	_expect(password != null and password.is_visible_in_tree() and password.secret,
		"A password request reveals the secure input")
	if password != null and password.is_visible_in_tree():
		password.text = "1379"
		password.text_changed.emit(password.text)
		await _press("MahjongJoinButton")
		_expect(_last_command("join").get("password") == "1379", "Retry sends the password with the same room code")
		await _reject("join", "房间密码错误", "room_password_invalid")
	await _press("MahjongCloseJoinButton")
	await _press("MahjongRoomListButton")
	_expect(_app.commands.any(func(item): return item.get("type") == "mahjong_room_directory" and item.get("open")),
		"Opening the directory subscribes to public rooms")
	var public_rooms := [
		{"room_id":"4826", "rule_set_id":"guiyang", "rule_name":"贵阳捉鸡", "players":2, "capacity":4, "round_limit":8,"joinable":true},
		{"room_id":"1738", "rule_set_id":"basic_108", "rule_name":"基础 108", "players":3, "capacity":4, "round_limit":16,"joinable":true},
		{"room_id":"6135", "rule_set_id":"guiyang", "rule_name":"贵阳捉鸡", "players":1, "capacity":4, "round_limit":24,"joinable":true},
	]
	_app._on_lobby_packet(JSON.stringify({
		"type": "mahjong_lobby_state", "state": {"status":"idle"}, "presets": rules,
		"room_directory": true, "room_directory_requests": true,
		"directory_request_id": str(_app._room_directory_request), "public_rooms": public_rooms,
	}))
	await _frames()
	_expect(_visible("MahjongDirectoryJoin4826"), "The directory shows the room received from the server")
	await _check_layouts("05_directory", "MahjongRoomPageBackButton", "MahjongDirectoryJoin4826")
	await _press("MahjongDirectoryJoin1738")
	_expect(_last_command("join").get("room_id") == "1738", "Clicking join on a directory row sends that row's room code")
	await _reject("join", "这个房间已经满了", "room_full")
	await _escape()
	_expect(_visible("MahjongQuickButton"), "Escape uses the directory's back route")
	_expect(_app.commands.any(func(item): return item.get("type") == "mahjong_room_directory" and not item.get("open")),
		"Leaving the directory unsubscribes from public rooms")
	await _press("MahjongQuickButton")
	_expect(_app.commands.any(func(item): return item.get("action") == "quick"), "Start sends the real quick command schema")
	var matched := {"status":"matched", "kind":"quick", "room_id":"1238", "rule_set_id":"guiyang",
		"rule_version":"2.0.0", "capacity":4, "player_account_ids":["harvest-self","peer-b","peer-c","peer-d"],
		"ready_account_ids":["peer-b","peer-c"]}
	_app._on_lobby_result(str(_last_command("quick").get("command_id", "")), true, "", "", matched)
	await _frames()
	_expect(_visible("MahjongQuickMatchPanel"), "Quick matchmaking has its approved dedicated layout")
	await _check_layouts("06_quick", "MahjongLeaveButton", "MahjongReadyButton")
	await _press("MahjongReadyButton")
	var ready := _last_command("ready")
	_expect(ready.get("room_id") == "1238", "Ready addresses the server's matched room")
	matched.ready_account_ids.append("harvest-self")
	_app._on_lobby_result(str(ready.get("command_id", "")), true, "", "", matched)
	await _frames()
	var ready_button := _node("MahjongReadyButton") as Button
	_expect(ready_button != null and ready_button.text == "取消准备", "A ready snapshot updates the native control")
	_app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _frames()
	var leave := _last_command("leave")
	_expect(leave.get("room_id") == "1238", "System back uses the same quick-room leave route")
	for failure in _failures:
		push_error(failure)
	if _failures.is_empty():
		print("MAHJONG_HARVEST_UI_SMOKE_OK layouts=%d settings_layouts=%d native_pngs=%d driver=%s" %
			[_layouts, _settings_layouts, _previews, DisplayServer.get_name()])
	_app.queue_free()
	await process_frame
	quit(int(not _failures.is_empty()))
