extends SceneTree
## The HTTP fixture records request intent and delivers response events to the real product UI.

class AppFixture:
	extends "res://scripts/main.gd"
	var requests: Array[Dictionary] = []
	var admitted := false
	var connections := 0
	var named_requests: Array[Dictionary] = []
	var initial_login := false
	var initially_unavailable := false
	var fixture_health_response := false

	func _request_health() -> void:
		initial_login = _state == "login" and is_instance_valid(_guest_button)
		initially_unavailable = _guest_button.disabled
		if fixture_health_response: super._request_health()
		else: _show_login()

	func _send_session_request(kind: String, url: String, token: String) -> Error:
		requests.append({"kind": kind, "url": url, "authenticated": not token.is_empty()})
		return OK

	func _start_lobby_connection() -> void:
		admitted = true
		connections += 1

	func _send_named_request(registering: bool, username: String, password: String) -> Error:
		named_requests.append({"registering": registering, "username": username, "untrimmed": password == "  aB1cD2! "})
		return OK

const SERVER_A := "http://127.0.0.1:31080"
const SERVER_B := "https://example.invalid/mahjong"

var _failures: Array[String] = []
var _fixture_directory := "user://mahjong-session-smoke-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, failure: String) -> void:
	if not condition: _failures.append(failure)


func _client(server: String) -> AppFixture:
	var app := AppFixture.new()
	app.session_store_path = _fixture_directory
	app.account_preferences_path = _fixture_directory + "/remembered-account.cfg"
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(app)
	app._api.set_base_url(server, false)
	app._show_login()
	return app


func _respond(app: AppFixture, code: int, payload: Dictionary = {}) -> void:
	app._http.request_completed.emit(HTTPRequest.RESULT_SUCCESS, code, PackedStringArray(), JSON.stringify(payload).to_utf8_buffer())


func _publish_assignment(app: AppFixture, state: Dictionary) -> void:
	app._lobby_socket.packet_received.emit(JSON.stringify({"type": "mahjong_lobby_state", "state": state, "presets": []}))


func _run() -> void:
	# Synthetic only. The harness writes no real credentials or process environment.
	var token_a := "AbC_1-".repeat(7) + "A"
	var token_b := "ZbC_1-".repeat(7) + "A"
	var requested_override := OS.get_environment("XBD_SERVER_URL")
	OS.set_environment("XBD_SERVER_URL", SERVER_B)
	var health := AppFixture.new()
	health.fixture_health_response = true
	health.session_store_path = _fixture_directory
	root.add_child(health)
	OS.set_environment("XBD_SERVER_URL", requested_override)
	var configured := str(ProjectSettings.get_setting("xiaobandeng/network/default_server_url", health.DEFAULT_SERVER_URL)).trim_suffix("/")
	_check(health._api.base_url == configured and health.requests[0].url == configured + "/health", "login uses the fixed package origin even if an environment override exists")
	_check(health.initial_login and health._guest_button.disabled and health.requests[0].kind == "health", "login view is present during initial health request")
	_respond(health, 503)
	_check(health._state == "login" and health._guest_button.disabled and "连接失败" in health._status.text, "failed health leaves the login and retry affordance visible")
	_check(health._connect_button.is_visible_in_tree(), "the fixed host can be retried on failure")
	health._error_dialog.find_child("MahjongErrorRetryButton", true, false).pressed.emit()
	_respond(health, 200)
	_check(health._state == "login" and not health._guest_button.disabled and health.requests.size() == 2, "successful retry enables login without requesting a guest")
	health.queue_free()
	var first := _client(SERVER_A)
	_check(first.initial_login and first.initially_unavailable, "initial view is login before health is resolved")
	_check(first._http.max_redirects == 0, "HTTP redirects must be disabled for authenticated requests")
	_check(first._guest_button.text == "游客登录", "first launch offers guest login")
	first._login()
	first._login()
	_check(first.requests.size() == 1 and first.requests[0].kind == "login" and not first.requests[0].authenticated, "new account submitted once")
	_respond(first, 200, {"account_id": "original-seat", "display_name": "牌友", "session_token": token_a})
	_check(first._state == "guest_identity" and not first.admitted and first._lobby_entry.visible, "real guest identity shown before lobby admission")
	_check(first._screen.find_child("MahjongGuestNickname", true, false).text == "牌友", "guest identity uses the server nickname")
	first._lobby_entry.pressed.emit()
	first._enter_guest_lobby()
	_check(first.connections == 1, "explicit lobby click opens just one connection")
	_check(first.admitted and first._account.get("account_id") == "original-seat" and not first._account.has("session_token"), "separate authenticated identity and credential")
	var active_room := {
		"status":"playing", "start":true, "kind":"friend", "room_id":"0421", "seat_index":1,
		"player_account_ids":["a","original-seat","b","c"], "capacity":4,
		"rule_set_id":"guiyang", "rule_version":"2.0.0",
	}
	_publish_assignment(first, {"status":"idle"})
	_publish_assignment(first, active_room)
	_check(first._state == "lobby", "an idle admission must not auto-enter an assignment that appears later without a local join")
	_check(first._sessions.save(SERVER_B, token_b) == OK, "save independent server session")
	first.queue_free()
	await process_frame
	await create_timer(0.06).timeout

	var restarted := _client(SERVER_A)
	restarted._auto_flow = true
	restarted._show_login()
	await process_frame
	_check(restarted.requests.is_empty(), "saved session never starts an automatic request")
	_check(restarted._guest_button.text == "继续游戏", "restart offers to verify saved identity")
	restarted._login()
	_check(restarted.requests.size() == 1 and restarted.requests[0].kind == "restore" and restarted.requests[0].authenticated, "restore sends bearer instead of guest creation")
	_respond(restarted, 503)
	_check(restarted._guest_button.text == "继续游戏" and restarted._sessions.read(SERVER_A) == token_a, "5xx keeps original session for retry")
	restarted._error_dialog.find_child("MahjongErrorCloseButton", true, false).pressed.emit()
	restarted._login()
	_respond(restarted, 200, {"account_id": "original-seat", "display_name": "牌友"})
	_check(restarted._state == "guest_identity" and not restarted.admitted, "restored client must still confirm lobby entry")
	restarted._guest_identity_back()
	_check(restarted._state == "login" and restarted._sessions.read(SERVER_A) == token_a, "back retains original authentication token")
	restarted._login()
	_respond(restarted, 200, {"account_id": "original-seat", "display_name": "牌友"})
	restarted._lobby_entry.pressed.emit()
	_check(restarted.admitted and restarted._account.get("account_id") == "original-seat", "restored identity remains authored by the server")
	_publish_assignment(restarted, active_room)
	var resumed_board: Control = restarted._game
	_check(restarted._state == "game" and is_instance_valid(resumed_board), "restored guest must automatically return to the active table")
	if is_instance_valid(resumed_board):
		_check(resumed_board.match_context.get("room_id") == "0421" and int(resumed_board.match_context.get("seat_index", -1)) == 1,
			"automatic return must use the room and seat from the authenticated assignment")
		_check(not resumed_board._actions_ready(), "a reopened table must wait for a new private snapshot before accepting moves")
		_publish_assignment(restarted, active_room)
		_check(restarted._game == resumed_board, "another lobby update must keep the restored board")
		resumed_board.request_return_to_lobby.emit()
		_publish_assignment(restarted, active_room)
		_check(restarted._state == "lobby" and restarted._game == null, "explicit temporary leave must keep the player in the lobby")
	_check(restarted._sessions.save(SERVER_A, token_a) == OK, "existing session can be atomically refreshed")
	restarted._lobby_socket.session_expired.emit()
	_check(restarted._state == "login" and restarted._account.is_empty() and restarted._sessions.read(SERVER_A).is_empty(), "live-session expiry returns to login and releases the active client identity")
	_check(restarted._sessions.save(SERVER_A, token_a) == OK, "seed restore-expiry response fixture")
	restarted.queue_free()
	await process_frame
	await create_timer(0.06).timeout

	var expired := _client(SERVER_A)
	expired._login()
	_respond(expired, 401)
	_check(expired.requests.size() == 1 and expired._guest_button.text == "游客登录" and "已失效" in expired._status.text, "401 does not create a guest without a second action")
	_check(expired._sessions.read(SERVER_A).is_empty() and expired._sessions.read(SERVER_B) == token_b, "expiry removes only the active server session")
	_check(expired._screen.find_child("MahjongServerAddress", true, false) == null, "players cannot enter an alternate host")
	var transport = expired.TRANSPORT.new()
	root.add_child(transport)
	_check(transport.endpoint(SERVER_B) == "wss://example.invalid/mahjong/api/v1/mahjong/ws", "secure mailbox uses a dedicated Mahjong URL")
	transport.start("ws://127.0.0.1:31080/ws", token_a)
	_check(not transport.is_processing(), "legacy WebSocket URL is never dialed")
	transport.start(transport.endpoint(SERVER_A), "")
	_check(not transport.is_processing(), "anonymous WebSocket is never dialed")
	transport.queue_free()
	var error: Error = expired._sessions.remove(SERVER_B, token_b)
	_check(error == OK, "fixture session removed")
	expired.queue_free()
	var named := _client(SERVER_A)
	_check(named._state == "login" and named._login_secret.secret, "normal entry exposes an interactive account form with a concealed password")
	named._login_secret.get_parent().get_node("MahjongTogglePasswordVisibility").pressed.emit()
	_check(not named._login_secret.secret, "password visibility toggles the actual input")
	named._login_identifier.text = "  Bambu_31  "
	named._login_secret.text = "  aB1cD2! "
	named._remember_identifier.button_pressed = true
	named._submit_account.pressed.emit()
	_check(named.named_requests == [{"registering": false, "username": "Bambu_31", "untrimmed": true}], "named sign-in trims only username and submits once")
	_check(named._login_secret.text.is_empty() and not named.admitted, "password field clears, admission still requires valid server response")
	_respond(named, 401, {"error": "internal non-public authentication detail"})
	_check(not named.admitted and "internal" not in named._status.text, "named failure displays generic text without admission")
	named._error_dialog.find_child("MahjongErrorConfirmButton", true, false).pressed.emit()
	named._login_secret.text = "  aB1cD2! "
	named._submit_account.pressed.emit()
	_respond(named, 200, {"account_id": "named-account", "display_name": "Bambu_31", "session_token": token_b})
	_check(named.admitted and named._account.get("account_id") == "named-account", "named login admits server-issued identity")
	var named_room := active_room.duplicate(true)
	named_room.player_account_ids[1] = "named-account"
	_publish_assignment(named, named_room)
	_check(named._state == "game" and is_instance_valid(named._game), "password login must also return to the active table")
	if is_instance_valid(named._game):
		named._game.request_return_to_lobby.emit()
	var privacy := preload("res://modules/games/mahjong/guiyang/mahjong_account_view.gd").new()
	root.add_child(privacy)
	privacy.apply({"account_kind": named._account.kind, "display_name": named._account.display_name})
	_check("游客" not in privacy._identity.text and "只记住用户名" in privacy._stored_data.text, "named account renders accurate personal-center privacy information")
	privacy.apply({"account_kind": "guest", "display_name": "测试牌友"})
	_check("游客账号" in privacy._identity.text and "游客登录凭据" in privacy._stored_data.text, "guest privacy mentions its own credential retention")
	privacy.queue_free()
	var saved_named := FileAccess.get_file_as_string(named.account_preferences_path)
	_check("Bambu_31" in saved_named and "aB1cD2!" not in saved_named and token_b not in saved_named, "named settings persist only username")
	named._show_account_login()
	_check(named._login_identifier.text == "Bambu_31" and named._login_secret.text.is_empty(), "named form autofills username only")
	named._show_account_registration()
	named._login_identifier.text = "NewName_1"
	named._login_secret.text = "  aB1cD2! "
	named._remember_identifier.button_pressed = false
	named._submit_account.pressed.emit()
	_check(named.named_requests.back().registering and named.named_requests.back().username == "NewName_1", "register dispatch is distinct from sign-in")
	_respond(named, 201, {"account_id": "registered-account", "display_name": "NewName_1", "session_token": token_b})
	_check(named._account.get("account_id") == "registered-account" and not FileAccess.file_exists(named.account_preferences_path), "unchecking clears remembered username after named registration")
	named.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_fixture_directory))
	await process_frame
	await create_timer(0.2).timeout
	for failure in _failures: push_error(failure)
	print("MAHJONG_GUEST_SESSION_SMOKE_OK=", _failures.is_empty())
	quit(0 if _failures.is_empty() else 1)
