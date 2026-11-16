extends SceneTree
## Real form and product callbacks; only HTTP transport is replaced.

class LoginFixture:
	extends "res://scripts/main.gd"
	var sent: Array[Dictionary] = []
	var health_requests: Array[String] = []
	var health_error: Error = OK
	func _health_get(url: String) -> Error:
		health_requests.append(url)
		return health_error
	func _post(url: String, payload: Dictionary) -> void:
		sent.append({"url":url,"payload":payload.duplicate(true)})

var _failures: Array[String] = []
func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var app := LoginFixture.new()
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(app)
	if not app.has_method("_on_health_response"):
		push_error("连接重试没有隔离旧的健康检查响应")
		quit(1)
		return
	var boot_page := app.find_child("LandlordReferenceLogin",true,false) as Control
	_check(boot_page!=null, "启动连接阶段没有使用同一参考登录界面")
	if boot_page!=null:
		_check(boot_page.guest_button.disabled and not boot_page.connection_button.disabled, "连接阶段没有保留地址配置或过早允许登录")
		boot_page.phone_field.text="13800138000"
	var stale_serial: int=app._health_serial
	var stale_url: String=app._api.base_url
	boot_page.server_field.text="http://127.0.0.1:18080"
	boot_page.server_dialog.confirmed.emit()
	_check(app.health_requests.size()==2 and app._health_pending, "启动期间更换地址没有替换健康检查")
	app._on_health_response(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),"{}".to_utf8_buffer(),stale_serial,stale_url)
	_check(app._state=="boot" and boot_page.guest_button.disabled, "旧地址响应错误开放了新地址登录")
	app._http.request_completed.emit(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),"{}".to_utf8_buffer())
	await process_frame
	var page := app.find_child("LandlordReferenceLogin",true,false) as Control
	if page == null:
		push_error("斗地主登录页没有使用用户提供的乡村夜景设计")
		quit(1)
		return
	_check(page.phone_field.placeholder_text == "请输入手机号", "缺少真实手机号输入框")
	_check(page==boot_page and page.phone_field.text=="13800138000", "连接成功重建了表单并丢失当前输入")
	_check(page.password_field.secret, "密码默认没有隐藏")
	page.phone_field.text="13800138000"
	page.password_field.text="ui-fixture-password"
	if DisplayServer.get_name()!="headless": await _click(page.password_toggle,false)
	else: page.password_toggle.pressed.emit()
	_check(not page.password_field.secret and page.password_field.text == "ui-fixture-password", "密码可见切换丢失了输入")
	page.password_toggle.pressed.emit()
	_check(page.password_field.secret, "密码不能重新隐藏")
	for button in [page.account_button,page.wechat_button,page.register_button,page.forgot_button]:
		button.pressed.emit()
		_check(app.sent.is_empty() and app._state == "login", "未开放的账号入口错误调用游客认证")
		_check(page.notice.visible, "账号入口没有说明当前开放状态")
		_check_dialog_fit(page.notice,"账号说明")
		page.notice.hide()
	for dimensions in [Vector2(720,1280),Vector2(1024,768),Vector2(1440,900)]:
		page.size=dimensions
		page._layout()
		for control in [page.phone_field,page.password_field,page.password_toggle,page.account_button,page.wechat_button,page.guest_button,page.register_button,page.forgot_button,page.connection_button]:
			_check(Rect2(Vector2.ZERO,dimensions).grow(1).encloses(control.get_rect()), "可操作登录控件超出窗口")
		_check(not page.password_field.get_rect().intersects(page.guest_button.get_rect()), "登录控件互相遮挡")
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	page._layout()
	_check(page.password_field.get_rect().encloses(page.password_toggle.get_rect()), "密码显示图标超出输入框")
	page.connection_button.pressed.emit()
	_check(page.server_dialog.visible and app._server_field == page.server_field, "连接设置没有保留实际服务器字段")
	_check_dialog_fit(page.server_dialog,"连接设置")
	var committed_url: String=app._api.base_url
	page.server_field.text="http://127.0.0.1:18888"
	page.server_dialog.canceled.emit()
	_check(page.server_field.text==committed_url and app._api.base_url==committed_url, "取消连接设置仍应用了草稿地址")
	page.server_dialog.hide()
	page.server_field.text="http://127.0.0.1:18081"
	page.server_dialog.confirmed.emit()
	app._login()
	_check(app.sent.is_empty() and app._request_kind=="health" and page.guest_button.disabled, "重新连接期间游客登录抢占了健康请求")
	app._http.request_completed.emit(HTTPRequest.RESULT_CANT_CONNECT,0,PackedStringArray(),PackedByteArray())
	_check(page.guest_button.disabled, "连接失败后仍允许向未检查地址登录")
	app.health_error=ERR_CANT_CONNECT
	app._retry_server()
	_check(not app._health_pending and page.guest_button.disabled, "请求无法启动时没有恢复可重试连接状态")
	app.health_error=OK
	app._retry_server()
	app._http.request_completed.emit(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),"{}".to_utf8_buffer())
	_check(page==app._login_view and page.phone_field.text=="13800138000" and page.password_field.text=="ui-fixture-password", "重新连接成功丢失了输入")
	if DisplayServer.get_name()!="headless": await _click(page.guest_button,true)
	else: page.guest_button.pressed.emit()
	page.guest_button.pressed.emit()
	_check(app.sent.size() == 1 and app.sent[0].url=="http://127.0.0.1:18081/api/v1/auth/guest" and app.sent[0].payload.is_empty(), "游客登录没有使用确认过的地址或重复提交")
	_check(page.guest_button.disabled, "提交期间未禁用登录")
	app._on_response(HTTPRequest.RESULT_SUCCESS,401,PackedStringArray(),JSON.stringify({"error":"测试拒绝"}).to_utf8_buffer())
	_check(not page.guest_button.disabled and "测试拒绝" in app._status.text, "登录失败没有恢复可重试状态")
	_check(page.phone_field.text=="13800138000" and page.password_field.text=="ui-fixture-password", "游客登录失败丢失了当前输入")
	# Capture the final designed page before exercising the lobby transition.
	page.phone_field.clear()
	page.password_field.clear()
	page.status_label.text="当前开放游客登录"
	await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--screenshot="):
				_check(root.get_texture().get_image().save_png(arg.trim_prefix("--screenshot="))==OK,"登录截图保存失败")
	page.guest_button.pressed.emit()
	app._on_response(HTTPRequest.RESULT_SUCCESS,201,PackedStringArray(),JSON.stringify({"account_id":"login-fixture","display_name":"牌友"}).to_utf8_buffer())
	_check(app._state=="lobby" and app._account.get("account_id")=="login-fixture", "真实登录响应没有进入现有大厅")
	app.queue_free()
	await process_frame
	await process_frame
	if not _failures.is_empty(): quit(1); return
	print("LANDLORD_LOGIN_REFERENCE_OK input=true secret_toggle=true guest_only=true pending_guard=true failure_retry=true lobby=true adaptive_layout=true health_identity=true cancel_discards_draft=true reconnect_preserves_input=true")
	quit(0)

func _click(button: Control, touch: bool) -> void:
	var point: Vector2=button.get_viewport_transform()*button.get_global_transform()*(button.size*.5)
	var emulate:=Input.emulate_mouse_from_touch
	Input.emulate_mouse_from_touch=true
	var event: InputEvent
	if touch:
		var tap:=InputEventScreenTouch.new()
		tap.index=0
		tap.position=point
		tap.pressed=true
		event=tap
	else:
		var click:=InputEventMouseButton.new()
		click.position=point
		click.global_position=point
		click.button_index=MOUSE_BUTTON_LEFT
		click.pressed=true
		event=click
	Input.parse_input_event(event)
	await process_frame
	event.pressed=false
	Input.parse_input_event(event)
	await process_frame
	Input.emulate_mouse_from_touch=emulate

func _check_dialog_fit(dialog: Window, label: String) -> void:
	# Embedded Window positions/sizes use the stretched viewport, not OS pixels.
	var bounds:=Rect2(Vector2.ZERO,root.get_visible_rect().size) if dialog.is_embedded() else Rect2(root.position,root.size)
	_check(bounds.encloses(Rect2(dialog.position,dialog.size)),"%s超出窗口 dialog=%s bounds=%s"%[label,Rect2(dialog.position,dialog.size),bounds])
