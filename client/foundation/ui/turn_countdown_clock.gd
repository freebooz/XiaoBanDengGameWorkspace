extends Control
class_name XbdTurnCountdownClock
## XbdTurnCountdownClock（小板凳单步超时倒计时时钟）
## 通用桌面游戏倒计时表现组件。进入超时阶段后显示圆形进度环、剩余秒数和当前执棋方。
## 组件只负责表现，不参与规则判定；时间来源必须由服务端权威时间戳计算。

var _remaining_seconds: int = 0
var _total_seconds: int = 30
var _side_text: String = ""
var _timed_out: bool = false
var _pulse_time: float = 0.0

var _title_label: Label
var _number_label: Label
var _hint_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(230, 230)
	_build_labels()
	visible = false
	set_process(true)


func _process(delta: float) -> void:
	if not visible:
		return
	_pulse_time += delta
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _title_label != null:
		_layout_labels()


func _build_labels() -> void:
	_title_label = Label.new()
	_title_label.text = "超时倒计时"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.add_theme_color_override("font_color", Color("#ffd9a0"))
	_title_label.add_theme_color_override("font_shadow_color", Color("#000000bb"))
	_title_label.add_theme_constant_override("shadow_offset_x", 1)
	_title_label.add_theme_constant_override("shadow_offset_y", 2)
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_label)

	_number_label = Label.new()
	_number_label.text = "30"
	_number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_number_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_number_label.add_theme_font_size_override("font_size", 68)
	_number_label.add_theme_color_override("font_color", Color("#ffffff"))
	_number_label.add_theme_color_override("font_shadow_color", Color("#7b1300dd"))
	_number_label.add_theme_constant_override("shadow_offset_x", 2)
	_number_label.add_theme_constant_override("shadow_offset_y", 3)
	_number_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_number_label)

	_hint_label = Label.new()
	_hint_label.text = "请尽快落子"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 16)
	_hint_label.add_theme_color_override("font_color", Color("#ffd2b0"))
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint_label)

	_layout_labels()


func _layout_labels() -> void:
	var w := size.x
	var h := size.y
	_title_label.position = Vector2(w * 0.15, h * 0.18)
	_title_label.size = Vector2(w * 0.70, h * 0.16)
	_number_label.position = Vector2(w * 0.10, h * 0.34)
	_number_label.size = Vector2(w * 0.80, h * 0.34)
	_hint_label.position = Vector2(w * 0.12, h * 0.70)
	_hint_label.size = Vector2(w * 0.76, h * 0.13)


func show_countdown(remaining_seconds: int, total_seconds: int, side_text: String) -> void:
	_remaining_seconds = maxi(remaining_seconds, 0)
	_total_seconds = maxi(total_seconds, 1)
	_side_text = side_text
	_timed_out = false
	_title_label.text = "%s超时倒计时" % side_text
	_number_label.text = str(_remaining_seconds)
	_hint_label.text = "请尽快落子"
	visible = true
	move_to_front()
	queue_redraw()


func show_timeout(side_text: String) -> void:
	_remaining_seconds = 0
	_total_seconds = maxi(_total_seconds, 1)
	_side_text = side_text
	_timed_out = true
	_title_label.text = "%s思考超时" % side_text
	_number_label.text = "0"
	_hint_label.text = "等待规则处理"
	visible = true
	move_to_front()
	queue_redraw()


func hide_clock() -> void:
	visible = false
	_timed_out = false
	_pulse_time = 0.0


func _draw() -> void:
	if not visible:
		return

	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.39
	var pulse := 0.5 + sin(_pulse_time * 5.0) * 0.5

	# 半透明暗底使倒计时在复杂三维棋盘上仍然清晰。
	draw_circle(center, radius + 17.0, Color(0.02, 0.01, 0.01, 0.76))
	draw_circle(center, radius + 7.0, Color(0.22, 0.035, 0.02, 0.92))
	draw_circle(center, radius - 2.0, Color(0.055, 0.025, 0.02, 0.96))

	# 12个时钟刻度增强“钟表”识别，而不是普通提示弹窗。
	for index in range(12):
		var angle := -PI * 0.5 + TAU * float(index) / 12.0
		var inner := center + Vector2(cos(angle), sin(angle)) * (radius - 8.0)
		var outer := center + Vector2(cos(angle), sin(angle)) * (radius + 1.0)
		draw_line(inner, outer, Color("#d8a05f"), 2.0, true)

	var ratio := clampf(float(_remaining_seconds) / float(_total_seconds), 0.0, 1.0)
	var end_angle := -PI * 0.5 + TAU * ratio
	var ring_color := Color("#ffb12b")
	if _remaining_seconds <= 10:
		ring_color = Color("#ff4938")
	if _timed_out:
		ring_color = Color("#ff1c1c")

	# 主进度环 + 呼吸光晕。
	draw_arc(center, radius, -PI * 0.5, end_angle, 96, ring_color, 9.0, true)
	draw_arc(
		center,
		radius + 7.0 + pulse * 2.0,
		-PI * 0.5,
		TAU - PI * 0.5,
		96,
		Color(ring_color.r, ring_color.g, ring_color.b, 0.16 + pulse * 0.18),
		3.0,
		true
	)
