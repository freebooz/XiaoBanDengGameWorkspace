extends SceneTree

const APP := preload("res://scripts/main.gd")

class AppFixture extends APP:
	var health_requests := 0
	func _request_health() -> void:
		health_requests += 1
		_connected_server = _api.base_url
		_update_login_request_state()
		_set_login_status("")

var app: AppFixture

func _initialize() -> void:
	call_deferred("_run")

func _frames() -> void:
	for frame in 6: await process_frame

func _click(control: Button) -> void:
	assert(control.is_visible_in_tree() and not control.disabled)
	assert(root.get_visible_rect().encloses(control.get_global_rect()), "The actual clickable button is inside the native viewport")
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = control.get_global_rect().get_center()
		event.pressed = pressed
		root.push_input(event, true)
	await _frames()

func _run() -> void:
	root.size = Vector2i(941, 1672)
	app = AppFixture.new()
	# Match the normal scenes/main.tscn root; a bare Control otherwise stays 0x0.
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(app)
	await _frames()
	assert(app.size.is_equal_approx(Vector2(root.size)) and app._screen.size.is_equal_approx(app.size), "Fixture uses the same full-viewport layout as the normal entry")
	app._login_identifier.text = "draft_user"
	app._login_secret.text = "draft_password"
	app._login_identifier.grab_focus()
	app._set_login_status("网络连接异常，请检查网络后重试。", true, "NET-001", app._request_health)
	await _frames()
	assert(is_instance_valid(app._error_dialog))
	var before := app.health_requests
	await _click(app._error_dialog.find_child("MahjongErrorRetryButton", true, false))
	assert(app.health_requests == before + 1, "Retry invokes existing network action exactly once")
	assert(not is_instance_valid(app._error_dialog))
	assert(app._login_identifier.text == "draft_user" and app._login_secret.text == "draft_password", "Retry preserves the form")
	app._present_error("房间密码不正确，请重新输入。", "room_password_invalid")
	await _frames()
	assert(app._error_dialog.find_child("MahjongErrorRetryButton", true, false) == null, "Rejected command is not resubmitted automatically")
	assert("room_password_invalid" in app._error_dialog.find_child("MahjongErrorCode", true, false).text)
	await _click(app._error_dialog.find_child("MahjongErrorConfirmButton", true, false))
	assert(root.gui_get_focus_owner() == app._login_identifier, "Dismiss restores form focus")
	app._present_error("网络连接异常，请检查网络后重试。", "NET-001", app._request_health)
	await _frames()
	var late_retry: Callable = app._error_dialog._retry
	app._show_account_registration()
	await _frames()
	assert(not is_instance_valid(app._error_dialog), "Navigation clears the modal")
	late_retry.call()
	assert(app.health_requests == before + 1, "Old-page retry cannot mutate a new page")
	app._show_login()
	await _frames()
	app._present_error("网络连接异常，请检查网络后重试。", "NET-001", app._request_health)
	await _frames()
	app._request_kind = "health"
	app._request_server = app._api.base_url
	app._on_response(HTTPRequest.RESULT_SUCCESS, 200, [], "{}".to_utf8_buffer())
	await _frames()
	assert(not is_instance_valid(app._error_dialog), "Successful recovery closes the connection error")
	print("MAHJONG_ERROR_FLOW_OK native_click=true retry_once=true form_preserved=true stale_retry_rejected=true recovery=true")
	app.queue_free()
	await _frames()
	quit()
