extends SceneTree

class AppFixture:
	extends "res://scripts/main.gd"
	var requests: Array[Dictionary] = []

	func _request_health() -> void: _show_login()
	func _start_lobby_connection() -> void: pass
	func _refresh_history() -> void: pass

	func _send_session_request(_kind: String, _url: String, _token: String) -> Error: return OK

	func _send_account_request(_request: HTTPRequest, url: String, token: String) -> Error:
		requests.append({"url": url, "token": token})
		return OK

const LIVE_APP := preload("res://scripts/main.gd")

const SERVER := "http://127.0.0.1:31808"
const TOKEN := "AbC_1-AbC_1-AbC_1-AbC_1-AbC_1-AbC_1-AbC_1-A"
const ACCOUNT := "account-fixture"
const RECEIPT := "f801b819-1c65-4cee-8889-8b537129ec85"

var _failures: Array[String] = []
var _session_directory := "user://mahjong-account-smoke-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]


func _initialize() -> void: call_deferred("_run")


func _check(condition: bool, detail: String) -> void:
	if not condition: _failures.append(detail)


func _button(app: Control, node_name: String) -> Button:
	return app._screen.find_child(node_name, true, false) as Button


func _sign_in(app: AppFixture) -> void:
	app._login()
	app._http.request_completed.emit(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({
		"account_id": ACCOUNT, "display_name": "测试牌友", "session_token": TOKEN,
	}).to_utf8_buffer())
	app._enter_guest_lobby()


func _respond(app: AppFixture, code: int, payload: Dictionary = {}) -> void:
	app._account_http.request_completed.emit(HTTPRequest.RESULT_SUCCESS, code, PackedStringArray(), JSON.stringify(payload).to_utf8_buffer())


func _check_layout(app: AppFixture) -> void:
	for dimensions in [Vector2i(540, 960), Vector2i(1180, 820)]:
		root.size = dimensions
		await process_frame
		await process_frame
		await process_frame
		var lobby: Control = app._lobby_view
		var button := _button(app, "MahjongAccountConfirmDeleteButton")
		var rect := button.get_global_rect()
		_check(button.is_visible_in_tree() and rect.size.y >= 56.0 and rect.position.x >= 0.0 and rect.end.x <= lobby.size.x and rect.end.y <= lobby.size.y,
			"touch confirmation stays on screen at %s (button=%s view=%s)" % [str(dimensions), str(rect), str(lobby.size)])


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server-url="):
			await _run_live(arg.trim_prefix("--server-url="))
			return
	await _run_fixture()


func _run_fixture() -> void:
	var app := AppFixture.new()
	app.session_store_path = _session_directory
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(app)
	app._api.set_base_url(SERVER, false)
	app._show_login()
	_sign_in(app)
	await process_frame
	var entry := _button(app, "MahjongAccountOpenButton")
	if entry == null or entry.disabled:
		push_error("missing account and privacy entry")
		quit(1)
		return
	entry.pressed.emit()
	var delete := _button(app, "MahjongAccountDeleteButton")
	delete.pressed.emit()
	var confirm := _button(app, "MahjongAccountConfirmDeleteButton")
	confirm.pressed.emit()
	_check(confirm.is_visible_in_tree() and confirm.disabled and app.requests.is_empty(), "deletion requires separate acknowledgment and submission")
	await _check_layout(app)
	_button(app, "MahjongAccountBackButton").pressed.emit()
	_check(delete.is_visible_in_tree() and app.requests.is_empty(), "back cancels deletion intent without a request")
	delete.pressed.emit()
	_button(app, "MahjongAccountAcknowledgeDeletion").set_pressed_no_signal(true)
	_button(app, "MahjongAccountAcknowledgeDeletion").toggled.emit(true)
	_check(not confirm.disabled, "explicit acknowledgment enables delete confirmation")
	confirm.pressed.emit()
	confirm.pressed.emit()
	_check(app.requests.size() == 1 and app.requests[0] == {"url": SERVER + "/api/v1/auth/delete-request", "token": TOKEN}, "authenticated delete submits once")
	_respond(app, 409)
	_check(app._state == "lobby" and app._sessions.read(SERVER) == TOKEN and confirm.is_visible_in_tree() and not confirm.disabled, "failed deletion retains identity and allows retry")
	confirm.pressed.emit()
	app._lobby_socket.session_expired.emit()
	_check(app._state == "lobby" and is_instance_valid(app._account_http), "early realtime revocation preserves the in-flight HTTP receipt")
	_respond(app, 202, {"request_id": RECEIPT, "account_id": ACCOUNT, "status": "pending_retention_review", "requested_at": "2026-11-14T01:00:00Z"})
	_check(app._state == "login" and app._sessions.read(SERVER).is_empty() and RECEIPT in app._status.text and "待审核" in app._status.text, "accepted request closes account locally and shows the server receipt")
	await process_frame
	_sign_in(app)
	await process_frame
	_button(app, "MahjongAccountOpenButton").pressed.emit()
	_button(app, "MahjongAccountLogoutButton").pressed.emit()
	_check(app.requests.back().url == SERVER + "/api/v1/auth/logout" and app.requests.back().token == TOKEN, "server logout authenticates current session")
	_respond(app, 204)
	_check(app._state == "login" and app._sessions.read(SERVER).is_empty() and "已退出" in app._status.text, "204 returns to login and removes the saved session")
	await process_frame
	_sign_in(app)
	await process_frame
	_button(app, "MahjongAccountOpenButton").pressed.emit()
	_button(app, "MahjongAccountLogoutButton").pressed.emit()
	_respond(app, 401)
	_check(app._state == "login" and app._sessions.read(SERVER).is_empty() and "已失效" in app._status.text, "401 takes the expired-session path")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_session_directory))
	app.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	_finish("MAHJONG_ACCOUNT_SMOKE_OK")


func _run_live(server: String) -> void:
	var app := LIVE_APP.new()
	app.session_store_path = _session_directory
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(app)
	server = server.strip_edges().trim_suffix("/")
	_check(app._api.base_url == server, "live client uses the requested server URL")
	if not await _wait_until(func() -> bool: return app._state == "login" and not app._guest_button.disabled, "server health"):
		_finish("MAHJONG_ACCOUNT_LIVE_SMOKE_OK")
		return
	_button(app, "MahjongGuestLoginButton").pressed.emit()
	if not await _confirm_live_guest(app): return
	if not await _wait_until(func() -> bool: return app._state == "lobby" and app._lobby_synced, "create first live guest and sync lobby"):
		_finish("MAHJONG_ACCOUNT_LIVE_SMOKE_OK")
		return
	var former_identity: String = app._account.account_id
	_button(app, "MahjongAccountOpenButton").pressed.emit()
	_button(app, "MahjongAccountLogoutButton").pressed.emit()
	if not await _wait_until(func() -> bool: return app._state == "login" and "已退出" in app._status.text, "server logout returns to login"):
		_finish("MAHJONG_ACCOUNT_LIVE_SMOKE_OK")
		return
	_check(app._sessions.read(server).is_empty(), "real logout removes the saved credential")
	await process_frame
	_button(app, "MahjongGuestLoginButton").pressed.emit()
	if not await _confirm_live_guest(app): return
	if not await _wait_until(func() -> bool: return app._state == "lobby" and app._lobby_synced, "create fresh live guest and sync lobby"):
		_finish("MAHJONG_ACCOUNT_LIVE_SMOKE_OK")
		return
	_check(app._account.account_id != former_identity, "fresh sign-in creates a different server identity")
	_button(app, "MahjongAccountOpenButton").pressed.emit()
	_button(app, "MahjongAccountDeleteButton").pressed.emit()
	_button(app, "MahjongAccountAcknowledgeDeletion").button_pressed = true
	_button(app, "MahjongAccountConfirmDeleteButton").pressed.emit()
	await _wait_until(func() -> bool: return app._state == "login" and "申请编号" in app._status.text and "待审核" in app._status.text, "server deletion receipt shows on login")
	_check(app._sessions.read(server).is_empty(), "real deletion removes the saved credential")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_session_directory))
	app.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	_finish("MAHJONG_ACCOUNT_LIVE_SMOKE_OK")


func _confirm_live_guest(app: Control) -> bool:
	if not await _wait_until(func() -> bool: return app._state == "guest_identity" and app._lobby_entry != null, "guest identity"):
		_finish("MAHJONG_ACCOUNT_LIVE_SMOKE_OK")
		return false
	_button(app, "MahjongGuestEnterLobbyButton").pressed.emit()
	return true


func _wait_until(condition: Callable, detail: String) -> bool:
	var deadline := Time.get_ticks_msec() + 12000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	var succeeded: bool = condition.call()
	_check(succeeded, detail)
	return succeeded


func _finish(marker: String) -> void:
	for failure in _failures: push_error(failure)
	print(marker, "=", _failures.is_empty())
	quit(0 if _failures.is_empty() else 1)
