extends RefCounted
## Keeps native button captions inside their decorated content area as layouts reflow.

const FIT_KEY := &"_mahjong_caption_fit"


static func attach(button: Button) -> void:
	if button.has_meta(FIT_KEY):
		return
	if button is OptionButton:
		# A long item must not set a fixed-width selector's initial size.
		button.fit_to_longest_item = false
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var caption := Caption.new(button)
	button.set_meta(FIT_KEY, caption)
	button.resized.connect(caption.queue_fit)
	button.theme_changed.connect(caption.queue_fit)
	button.draw.connect(caption.caption_changed)
	caption.queue_fit()


class Caption extends RefCounted:
	var _button: WeakRef
	var _queued := false
	var _initialized := false
	var _text := ""
	var _icon: Texture2D
	var _preferred_size := 0
	var _applied_size := 0

	func _init(button: Button) -> void:
		_button = weakref(button)

	func queue_fit() -> void:
		if _queued:
			return
		_queued = true
		_fit.call_deferred()

	func caption_changed() -> void:
		var button := _button.get_ref() as Button
		if button != null and (button.text != _text or button.icon != _icon):
			queue_fit()

	func _fit() -> void:
		var button := _button.get_ref() as Button
		if button == null:
			return
		if not _initialized:
			_initialized = true
			if button.get_parent() is Container:
				if button.custom_minimum_size.x <= 0.0 and (button.size_flags_horizontal & Control.SIZE_EXPAND) == 0:
					button.custom_minimum_size.x = minf(button.get_combined_minimum_size().x, 112.0)
				button.custom_minimum_size = button.custom_minimum_size.max(Vector2(44, 44))
			button.clip_text = true
			button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_text = button.text
		_icon = button.icon
		var current := button.get_theme_font_size("font_size")
		if _preferred_size <= 0 or current != _applied_size:
			_preferred_size = current
		if not _text.is_empty() and button.size.x > 0.0 and button.size.y > 0.0:
			var available := _caption_area(button)
			var font := button.get_theme_font("font")
			var desired := _preferred_size
			var readable := mini(_preferred_size, 15)
			while desired > readable and (font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, desired).x > available.x or font.get_height(desired) > available.y):
				desired -= 1
			while desired > 8 and font.get_height(desired) > available.y:
				desired -= 1
			_applied_size = desired
			if desired != current:
				button.add_theme_font_size_override("font_size", desired)
		_queued = false

	func _caption_area(button: Button) -> Vector2:
		var horizontal := 0.0
		var vertical := 0.0
		for state in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
			var style := button.get_theme_stylebox(state)
			horizontal = maxf(horizontal, style.get_margin(SIDE_LEFT) + style.get_margin(SIDE_RIGHT))
			vertical = maxf(vertical, style.get_margin(SIDE_TOP) + style.get_margin(SIDE_BOTTOM))
		var outline := float(button.get_theme_constant("outline_size"))
		var inset := Vector2(maxf(horizontal, minf(30.0, button.size.x * 0.12)),
			maxf(vertical, minf(30.0, button.size.y * 0.24)))
		var available := button.size - inset - Vector2.ONE * (outline * 2.0 + 2.0)
		var gap := float(button.get_theme_constant("h_separation"))
		if _icon != null:
			var icon_width := float(_icon.get_width())
			var cap := float(button.get_theme_constant("icon_max_width"))
			if button.expand_icon and _icon.get_height() > 0:
				icon_width *= maxf(0.0, available.y) / float(_icon.get_height())
			if cap > 0.0:
				icon_width = minf(icon_width, cap)
			available.x -= icon_width + gap
		if button is OptionButton:
			var arrow := button.get_theme_icon("arrow")
			if arrow != null:
				available.x -= arrow.get_width() + button.get_theme_constant("arrow_margin")
		elif button is CheckBox or button is CheckButton:
			var mark := button.get_theme_icon("checked")
			if mark != null:
				available.x -= mark.get_width() + gap
		return available
