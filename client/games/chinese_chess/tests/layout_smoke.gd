extends SceneTree
## layout_smoke.gd（象棋响应式布局烟测）
## 使用合成分辨率验证断点分类，不依赖真实窗口或网络。

const SCREEN = preload("res://modules/games/chinese_chess/chinese_chess_3d_screen.gd")


func _initialize() -> void:
	var screen = SCREEN.new()
	var cases := [
		[450.0, 800.0, 0, "phone_portrait"],
		[1200.0, 1600.0, 1, "tablet_portrait"],
		[900.0, 500.0, 2, "phone_landscape"],
		[1366.0, 1024.0, 3, "tablet_landscape"],
		[1440.0, 900.0, 4, "desktop"],
		[2560.0, 1080.0, 5, "wide_desktop"],
	]
	for item in cases:
		var actual: int = screen._resolve_layout_mode(float(item[0]), float(item[1]))
		if actual != int(item[2]):
			push_error("LAYOUT_SMOKE failed: %s expected=%s actual=%s" % [str(item[3]), str(item[2]), str(actual)])
			screen.free()
			quit(1)
			return
		print("LAYOUT_SMOKE %s=%s" % [str(item[3]), str(actual)])
	screen.free()
	quit(0)
