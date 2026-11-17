extends Control
## Render into the actual output pixels. The inverse canvas scale only cancels
## HUD scaling; one rendered texel still occupies exactly one window pixel.

signal projection_resized

var surface: SubViewportContainer
var viewport: SubViewport
var _window: Window
var _host_viewport: Viewport
var _sync_queued := false
var _leaving := false


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface = SubViewportContainer.new()
	surface.name = "NativePixelSurface"
	surface.stretch = false
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(surface)
	viewport = SubViewport.new()
	viewport.name = "Native3DViewport"
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.scaling_3d_scale = 1.0
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	surface.add_child(viewport)


func _enter_tree() -> void:
	_leaving = false
	_window = get_window()
	_host_viewport = get_viewport()
	# A viewport-stretched root would resample the complete 3D result once more.
	# Share ownership across board/detail/lesson views and restore on final exit.
	var users: Dictionary = _window.get_meta("xbd_native_3d_users", {})
	if users.is_empty():
		_window.set_meta("xbd_before_native_3d_mode", _window.content_scale_mode)
	users[get_instance_id()] = true
	_window.set_meta("xbd_native_3d_users", users)
	if _window.content_scale_mode == Window.CONTENT_SCALE_MODE_VIEWPORT:
		_window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	_window.size_changed.connect(_queue_sync)
	if _host_viewport != _window: _host_viewport.size_changed.connect(_queue_sync)
	set_notify_transform(true)
	_queue_sync()


func _ready() -> void:
	resized.connect(_queue_sync)
	visibility_changed.connect(_queue_sync)
	sync_native_size()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED: _queue_sync()


func _queue_sync() -> void:
	if _leaving or not is_inside_tree() or _sync_queued: return
	_sync_queued = true
	sync_native_size.call_deferred()


func sync_native_size() -> void:
	_sync_queued = false
	if _leaving or not is_inside_tree() or size.x <= 0.0 or size.y <= 0.0: return
	var to_pixels := get_viewport_transform() * get_global_transform()
	var density := Vector2(to_pixels.x.length(), to_pixels.y.length())
	if density.x <= 0.0 or density.y <= 0.0: return
	var target := Vector2i((size * density).ceil()).max(Vector2i(2, 2))
	var inverse_density := Vector2.ONE / density
	var changed := viewport.size != target or not surface.scale.is_equal_approx(inverse_density)
	surface.stretch = false
	surface.stretch_shrink = 1
	viewport.scaling_3d_scale = 1.0
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	if viewport.size != target: viewport.size = target
	if surface.size != Vector2(target): surface.size = Vector2(target)
	if not surface.scale.is_equal_approx(inverse_density): surface.scale = inverse_density
	# Static previews redraw on geometry/visibility events. Live tables keep
	# UPDATE_ALWAYS for the real 3D animations, without polling UI/business data.
	if is_visible_in_tree() and viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if changed: projection_resized.emit()


func _exit_tree() -> void:
	_leaving = true
	if is_instance_valid(_host_viewport) and _host_viewport != _window and _host_viewport.size_changed.is_connected(_queue_sync):
		_host_viewport.size_changed.disconnect(_queue_sync)
	if not is_instance_valid(_window): return
	if _window.size_changed.is_connected(_queue_sync): _window.size_changed.disconnect(_queue_sync)
	var users: Dictionary = _window.get_meta("xbd_native_3d_users", {})
	users.erase(get_instance_id())
	_window.set_meta("xbd_native_3d_users", users)
	if users.is_empty():
		_window.content_scale_mode = int(_window.get_meta("xbd_before_native_3d_mode", Window.CONTENT_SCALE_MODE_CANVAS_ITEMS))
		_window.remove_meta("xbd_before_native_3d_mode")
