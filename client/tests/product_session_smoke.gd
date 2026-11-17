extends SceneTree
## Verify the three /ws products' guest session at the HTTP and socket boundaries.

const TOKEN := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const ACCOUNT := {"account_id": "audit-guest", "display_name": "牌友"}
const ROOM := {"room_id": "audit-room", "status": "matched", "seat_color": "red", "seat_index": 0}

var _listener := TCPServer.new()
var _socket_peer: StreamPeerTCP
var _chess := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var product: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://product.json"))
	if product.game_id not in ["chinese_chess", "landlord", "guandan"] or _listener.listen(0, "127.0.0.1") != OK:
		_fail("Matchmaking session smoke requires a /ws product and an isolated loopback listener")
		return
	_chess = product.game_id == "chinese_chess"
	OS.set_environment("XBD_SERVER_URL", "http://127.0.0.1:%d" % _listener.get_local_port())
	var app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	if not await _exchange("GET /health", 200, {}): return
	if not await _wait_for(func(): return _in_login(app)):
		_fail("Health response did not open login")
		return
	_press_login(app)
	if not await _exchange("POST /api/v1/auth/guest", 201, ACCOUNT): return
	if not await _wait_for(func(): return _login_available(app) or _in_lobby(app)) or not _in_login(app):
		_fail("Guest response with no session token did not restore the login form")
		return
	_press_login(app)
	var guest := ACCOUNT.duplicate()
	guest["session_token"] = TOKEN
	if not await _exchange("POST /api/v1/auth/guest", 201, guest): return
	if not await _wait_for(func(): return _in_lobby(app)):
		_fail("Successful guest session did not enter the lobby")
		return
	if app._account.has("session_token"):
		_fail("Guest session token was retained in the public account data")
		return
	_start_match(app)
	if not await _exchange("POST /api/v1/matchmaking/quick", 401, {}, true): return
	if not await _wait_for(func(): return _login_available(app)):
		_fail("Expired matchmaking session did not return to the login form")
		return
	_press_login(app)
	if not await _exchange("POST /api/v1/auth/guest", 201, guest): return
	if not await _wait_for(func(): return _in_lobby(app)):
		_fail("Guest login after expiry did not open the lobby")
		return
	_start_match(app)
	var cancel_during_match: bool = product.game_id == "landlord"
	var before_match_response := Callable(app, "_cancel") if cancel_during_match else Callable()
	if not await _exchange("POST /api/v1/matchmaking/quick", 200, ROOM, true, before_match_response): return
	if not cancel_during_match:
		if not await _wait_for(func(): return _in_room(app)):
			_fail("Matched response did not open the preparation room")
			return
		if _chess: app._on_cancel_flow()
		else: app._cancel()
	if not await _exchange("POST /api/v1/matchmaking/cancel", 200, {}, true): return
	if not await _wait_for(func(): return _in_lobby(app)):
		_fail("Cancelled match did not return to the lobby")
		return
	_start_match(app)
	if not await _exchange("POST /api/v1/matchmaking/quick", 200, ROOM, true): return
	if not await _wait_for(func(): return _in_room(app)):
		_fail("Matched response did not open the preparation room")
		return
	if _chess: app._on_room_ready()
	else: app._ready_up()
	if not await _exchange("POST /api/v1/matchmaking/ready", 200, {"start": true}, true): return
	if "--reject-upgrade" in OS.get_cmdline_user_args():
		if not await _exchange("GET /ws", 401, {}, true): return
		if not await _exchange("GET /api/v1/auth/session", 401, {}, true): return
	else:
		if "--retry-upgrade" in OS.get_cmdline_user_args():
			if not await _exchange("GET /ws", 503, {}, true): return
			if not await _exchange("GET /api/v1/auth/session", 200, ACCOUNT, true): return
		if not await _exchange("GET /ws", 101, {}, true): return
		var screen = (app._screen_root if _chess else app._screen).get_child(-1)
		if not await _wait_for(func(): return screen._socket.get_ready_state() == WebSocketPeer.STATE_OPEN):
			_fail("WebSocket upgrade did not open the client socket")
			return
		var reason := "session_expired".to_ascii_buffer()
		var close_frame := PackedByteArray([0x88, 2 + reason.size(), 0x03, 0xF0]) + reason
		if _socket_peer.put_data(close_frame) != OK:
			_fail("Could not deliver the WebSocket session expiry frame")
			return
		var live_socket: WebSocketPeer = screen._socket
		if not await _wait_for(func(): return live_socket.get_ready_state() != WebSocketPeer.STATE_OPEN):
			_fail("Client socket did not receive the server close frame")
			return
		_socket_peer.disconnect_from_host()
	if not await _wait_for(func(): return _login_available(app)) or not app._api.authorization_headers().is_empty():
		_fail("Expired socket session did not clear the guest and return to login")
		return
	app.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("PRODUCT_SESSION_SMOKE_OK product=%s missing_session_rejected=true expiry_recovery=true match=true ready=true cancel=true websocket=true socket_expiry=true" % product.game_id)
	quit()


func _press_login(app) -> void:
	if _chess:
		app._terms_checkbox.button_pressed = true
		app._on_guest_login()
	else:
		app._login()


func _start_match(app) -> void:
	if _chess: app._on_quick_match()
	else: app._start_match()


func _in_login(app) -> bool:
	return app._state == (app.FlowState.LOGIN if _chess else "login")


func _login_available(app) -> bool:
	if not _in_login(app): return false
	if _chess: return not app._primary_button.disabled
	return not app._login_pending


func _in_lobby(app) -> bool:
	return app._state == (app.FlowState.LOBBY if _chess else "lobby")


func _in_room(app) -> bool:
	return app._state == (app.FlowState.ROOM if _chess else "room")


func _wait_for(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while not condition.call():
		if Time.get_ticks_msec() >= deadline: return false
		await process_frame
	return true


func _exchange(route: String, status: int, response: Dictionary, authenticated := false, before_response := Callable()) -> bool:
	if not await _wait_for(_listener.is_connection_available): return _fail("No request reached " + route)
	var peer := _listener.take_connection()
	var request := ""
	var deadline := Time.get_ticks_msec() + 5000
	while not "\r\n\r\n" in request:
		peer.poll()
		var available := peer.get_available_bytes()
		if available > 0: request += peer.get_utf8_string(available)
		if Time.get_ticks_msec() >= deadline: return _fail("Incomplete request for " + route)
		await process_frame
	var headers := request.get_slice("\r\n\r\n", 0).split("\r\n")
	if not headers[0].begins_with(route + " "): return _fail("Unexpected request route, expected " + route)
	var bearer := ""
	var websocket_key := ""
	for header in headers.slice(1):
		match header.get_slice(":", 0).to_lower():
			"authorization": bearer = header.get_slice(":", 1).strip_edges()
			"sec-websocket-key": websocket_key = header.get_slice(":", 1).strip_edges()
	if bearer != ("Bearer " + TOKEN if authenticated else ""):
		return _fail("Unexpected bearer header for " + route)
	if before_response.is_valid(): before_response.call()
	if status == 101:
		if websocket_key.is_empty(): return _fail("Missing WebSocket upgrade key")
		var accept := Marshalls.raw_to_base64((websocket_key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").sha1_buffer())
		var upgrade := "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n\r\n" % accept
		_socket_peer = peer
		if peer.put_data(upgrade.to_ascii_buffer()) != OK: return _fail("Could not upgrade WebSocket")
		return true
	var body := JSON.stringify(response).to_utf8_buffer()
	var reply := "HTTP/1.1 %d Test\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [status, body.size()]
	if peer.put_data(reply.to_ascii_buffer() + body) != OK: return _fail("Could not respond to " + route)
	peer.disconnect_from_host()
	return true


func _fail(message: String) -> bool:
	push_error(message)
	quit(1)
	return false
