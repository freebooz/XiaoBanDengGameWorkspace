extends SceneTree
## 在手机、平板和 PC 窗口尺寸下验证登录入口及产品的服务器配置。

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
	var login := app.find_child("MahjongGuestLoginButton", true, false) as Button
	if login != null:
		if not app.get_global_rect().grow(1.0).encloses(login.get_global_rect()) or app.find_child("MahjongServerAddress", true, false) != null:
			push_error("麻将登录入口超出视口或暴露了服务器设置")
			quit(1)
			return
	else:
		var server_field: LineEdit = app._server_field
		if server_field == null or server_field.text.is_empty() or not app.get_global_rect().grow(1.0).encloses(server_field.get_global_rect()):
			push_error("服务器地址不可用或超出实际视口")
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
	print("LOGIN_LAYOUT_SMOKE_OK window=" + str(DisplayServer.window_get_size()))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--screenshot="):
				var path := arg.trim_prefix("--screenshot=")
				var image := root.get_viewport().get_texture().get_image()
				print("LOGIN_SCREENSHOT_RESULT=" + str(image.save_png(path)))
				break
	quit(0)
