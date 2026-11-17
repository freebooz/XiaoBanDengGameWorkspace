extends SceneTree
## layout_smoke.gd（象棋响应式布局烟测）
## 使用合成分辨率验证断点分类，不依赖真实窗口或网络。

const SCREEN = preload("res://modules/games/chinese_chess/chinese_chess_3d_screen.gd")


func _initialize() -> void:
	var screen = SCREEN.new()
	var cases := [
		[900.0, 500.0, SCREEN.LayoutMode.PHONE_LANDSCAPE],
		[1000.0, 450.0, SCREEN.LayoutMode.PHONE_LANDSCAPE],
		[1366.0, 1024.0, SCREEN.LayoutMode.TABLET_LANDSCAPE],
		[1440.0, 900.0, SCREEN.LayoutMode.DESKTOP],
		[2560.0, 1080.0, SCREEN.LayoutMode.WIDE_DESKTOP],
	]
	for item in cases:
		var actual: int = screen._resolve_layout_mode(float(item[0]), float(item[1]))
		var dimensions := Vector2(float(item[0]), float(item[1]))
		if actual != int(item[2]):
			push_error("LAYOUT_SMOKE failed: %s expected=%s actual=%s" % [dimensions, SCREEN.LayoutMode.keys()[item[2]], SCREEN.LayoutMode.keys()[actual]])
			screen.free()
			quit(1)
			return
		print("LAYOUT_SMOKE %s=%s" % [dimensions, SCREEN.LayoutMode.keys()[actual]])
	screen.free()
	quit(0)
