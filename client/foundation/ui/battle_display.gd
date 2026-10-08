extends RefCounted
## 对局使用横屏；最后一个对局退出时恢复进入前的大厅显示设置。

static func enter(owner: Control) -> void:
	var window := owner.get_window()
	var users: Dictionary = window.get_meta("xbd_battle_users", {})
	if users.has(owner.get_instance_id()): return
	if users.is_empty():
		window.set_meta("xbd_before_battle", {"design":window.content_scale_size, "aspect":window.content_scale_aspect, "window":window.size})
		window.content_scale_size = Vector2i(1440,810)
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		if OS.has_feature("mobile"):
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
		elif window.size.x < window.size.y:
			window.size = Vector2i(window.size.y, window.size.x)
	users[owner.get_instance_id()] = true
	window.set_meta("xbd_battle_users", users)

static func leave(owner: Control) -> void:
	var window := owner.get_window()
	var users: Dictionary = window.get_meta("xbd_battle_users", {})
	if not users.has(owner.get_instance_id()): return
	users.erase(owner.get_instance_id())
	window.set_meta("xbd_battle_users", users)
	if not users.is_empty(): return
	var previous: Dictionary = window.get_meta("xbd_before_battle", {})
	if previous.is_empty(): return
	window.content_scale_size = previous.design
	window.content_scale_aspect = previous.aspect
	if OS.has_feature("mobile"):
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)
	elif DisplayServer.get_name() != "headless": window.size = previous.window
