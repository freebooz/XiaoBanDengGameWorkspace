extends SceneTree
## 在手机、平板和 PC 窗口尺寸下验证可见登录入口和服务器地址配置。

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var script = load("res://scripts/main.gd")
	if script == null:
		push_error("产品入口脚本无法加载")
		quit(1)
		return
	var app = script.new()
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(app)
	await process_frame
	app._show_login()
	await process_frame
	var server_field: LineEdit = app._server_field
	if server_field == null or server_field.text == "":
		push_error("登录界面缺少服务器地址设置")
		quit(1)
		return
	var bounds := server_field.get_global_rect()
	if bounds.position.x < 0.0 or bounds.position.y < 0.0 or bounds.end.x > 720.0 or bounds.end.y > 1280.0:
		push_error("服务器地址控件超出竖屏设计范围: " + str(bounds))
		quit(1)
		return
	var api = load("res://modules/foundation/network/api_client.gd").new()
	if api.set_base_url("ftp://invalid", false) or not api.set_base_url("http://192.168.1.10:8080", false):
		push_error("跨设备服务器地址校验失败")
		quit(1)
		return
	if api.websocket_url() != "ws://192.168.1.10:8080/ws":
		push_error("跨设备 WebSocket 地址错误")
		quit(1)
		return
	print("LOGIN_LAYOUT_SMOKE_OK window=" + str(DisplayServer.window_get_size()) + " server=" + server_field.text)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--screenshot="):
				var path := arg.trim_prefix("--screenshot=")
				var image := root.get_viewport().get_texture().get_image()
				print("LOGIN_SCREENSHOT_RESULT=" + str(image.save_png(path)))
				break
	quit(0)
