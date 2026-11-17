extends RefCounted
## Hosts existing portrait page coordinates inside any expanded window.

const DESIGN := Vector2(720, 1280)


static func fit(host: Control, page: Control, full_window := false) -> void:
	var available := host.size
	if available.x <= 0.0 or available.y <= 0.0:
		return
	if full_window:
		page.scale = Vector2.ONE
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return
	page.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var region := Rect2(Vector2.ZERO, available)
	if OS.has_feature("mobile"):
		var display_area := DisplayServer.get_display_safe_area()
		if display_area.has_area():
			var window := host.get_window()
			var ratio := available / Vector2(window.size)
			var safe := Rect2(Vector2(display_area.position - window.position) * ratio, Vector2(display_area.size) * ratio)
			region = region.intersection(safe)
	if not region.has_area():
		region = Rect2(Vector2.ZERO, available)
	var fit_scale := minf(1.0, minf(region.size.x / DESIGN.x, region.size.y / DESIGN.y))
	page.size = DESIGN
	page.scale = Vector2.ONE * fit_scale
	page.position = (region.get_center() - DESIGN * fit_scale * 0.5).round()
