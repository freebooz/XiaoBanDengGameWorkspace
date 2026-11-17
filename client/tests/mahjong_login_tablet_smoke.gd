extends SceneTree

const APP := preload("res://scripts/main.gd")
const RURAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_theme.gd")
const MODAL := preload("res://modules/games/mahjong/guiyang/mahjong_rural_modal.gd")
const TABLET_SIZES := [Vector2i(1024, 768), Vector2i(1280, 800), Vector2i(2024, 1620),
	Vector2i(2048, 1536), Vector2i(2560, 1600)]

class AppFixture extends APP:
	var quit_requested := false
	func _request_health() -> void: _show_login()
	func _quit_game() -> void: quit_requested = true

var _failed := false
var _measurements: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if condition: return
	_failed = true
	push_error(message)

func _settle() -> void:
	for frame in range(10): await process_frame

func _run() -> void:
	var app := AppFixture.new()
	app.session_store_path = "user://tablet-layout-smoke"
	app.account_preferences_path = "user://login-layout-preferences.cfg"
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(app)
	await _settle()
	var logo: TextureRect = app._login_logo
	var submit: Button = app._submit_account
	var wechat := app.find_child("MahjongWechatLoginButton", true, false) as Button
	var exit_button := app.find_child("MahjongLoginExitButton", true, false) as Button
	var copyright: Label = app._login_footer
	_expect(app._state == "login" and app._login_identifier != null and app._login_secret.secret,
		"The normal entry directly presents the actual username and concealed password controls")
	_expect(app._entry_buttons.size() == 3 and wechat != null and not wechat.disabled,
		"Account, WeChat and guest actions use the three approved native buttons")
	_expect(app.find_child("MahjongServerAddress", true, false) == null and app.find_child("MahjongConnectionSettingsButton", true, false) == null,
		"The login screen retains the fixed gateway")
	for example in [[Vector2i(941,1672), "approved_login_941x1672.png"], [Vector2i(390,844), "phone_login_390x844.png"],
		[Vector2i(2024,1620), "near_square_login_2024x1620.png"],
		[Vector2i(1600,720), "phone_20_9_login.png"], [Vector2i(1280,720), "phone_16_9_login.png"],
		[Vector2i(1024,768), "tablet_4_3_login.png"], [Vector2i(1280,800), "tablet_16_10_login.png"],
		[Vector2i(2048,1536), "tablet_2048x1536_login.png"], [Vector2i(2560,1600), "tablet_2560x1600_login.png"],
		[Vector2i(1440,810), "desktop_login.png"], [Vector2i(1920,1080), "desktop_large_login.png"],
		[Vector2i(2560,1080), "desktop_ultrawide_login.png"]]:
		root.size = example[0]
		await _settle()
		var bounds := app._screen.get_global_rect()
		_expect(app._login_logo == logo, "Resizing keeps the same controls")
		for control in [logo, app._login_identifier, app._login_secret, app._remember_identifier, submit, wechat, app._guest_button, exit_button]:
			_expect(control.is_visible_in_tree() and bounds.encloses(control.get_global_rect()),
				"%s is visible and reachable at %s: %s" % [control.name, str(example[0]), str(control.get_global_rect())])
		for button: Button in app._entry_buttons:
			_expect(is_equal_approx(button.size.x, submit.size.x) and absf(button.size.y - submit.size.y) <= 1.0 and button.size.y >= 56.0 and button.get_theme_font_size("font_size") >= 24,
				"The three sign-in actions retain identical, readable touch areas: %s %s vs %s at %s" % [button.name, button.size, submit.size, root.size])
		_expect(app._login_secret.get_global_rect().end.y <= submit.get_global_rect().position.y,
			"Password entry and the primary action do not overlap")
		_expect(exit_button.get_global_rect().end.y <= copyright.get_global_rect().position.y,
			"Exit stays above the footer")
		# The fixture's immediate health reply replaces the initial view in the
		# same frame; the queued old sibling may temporarily reserve its name.
		var entry: Control = app._login_art.get_parent()
		var composition: BoxContainer = entry._layout
		var safe := RURAL.safe_insets(app._screen)
		var safe_width := bounds.size.x - safe.x - safe.z
		var form_width: float = entry.form.get_global_rect().size.x
		if root.size in TABLET_SIZES:
			_expect(form_width >= safe_width * 0.5 - 1.0,
				"Login paper occupies at least half of the safe width at %s: %.0f / %.0f" % [root.size, form_width, safe_width])
		var safe_center_x := (bounds.position.x + safe.x + bounds.end.x - safe.z) * 0.5
		_expect(absf(composition.get_global_rect().get_center().x - safe_center_x) <= 2.0,
			"The complete login composition is centered in the safe area at %s: %s" % [root.size, composition.get_global_rect()])
		var scroll_bounds: Rect2 = entry.scroll.get_global_rect()
		if composition.size.y <= scroll_bounds.size.y:
			_expect(absf(composition.get_global_rect().get_center().y - scroll_bounds.get_center().y) <= 2.0,
				"The whole composition is vertically centered above the footer at %s" % root.size)
		if root.size == Vector2i(2024,1620) or root.size.x < root.size.y:
			_expect(composition.vertical and absf(submit.get_global_rect().get_center().x - safe_center_x) <= 2.0,
				"Portrait and near-square windows center the form beneath the logo")
		var unit := minf(1.0, submit.size.x / 740.0)
		var touch := RURAL.touch_extent(app._screen)
		var primary_height := maxf(touch, maxf(60.0, 116.0 * unit))
		var field_height := maxf(touch, maxf(54.0, 90.0 * unit))
		var secondary_height := maxf(touch, maxf(48.0, 74.0 * unit))
		_expect(absf(submit.size.y - primary_height) <= 2.0,
			"Primary action retains the reference 116/740 proportion with a touch floor at %s: %s expected height %s" % [root.size, submit.size, primary_height])
		for field: PanelContainer in entry._fields:
			_expect(absf(field.size.y - field_height) <= 2.0,
				"Input capsule retains the reference 90/740 proportion with a touch floor at %s: %s expected height %s" % [root.size, field.size, field_height])
		for secondary: Button in [entry.exit_button, entry.register_button]:
			_expect(absf(secondary.size.y - secondary_height) <= 2.0 and absf(secondary.size.y / submit.size.y - secondary_height / primary_height) < 0.025,
				"Secondary actions retain the reference 74/116 height relative to primary actions at %s: %s vs %s" % [root.size, secondary.size, submit.size])
		_expect(absf(logo.size.aspect() - logo.texture.get_size().aspect()) < 0.02,
			"Logo control keeps the approved texture aspect ratio")
		var title: Control = entry._title.get_parent()
		_expect(absf(title.size.y - title.size.x / MODAL.LOGIN_TITLE.get_size().aspect()) <= 1.0,
			"Login title preserves the approved plaque aspect ratio at %s: %s" % [root.size, title.size])
		_measurements.append({"viewport": str(root.size), "composition": str(composition.get_global_rect()), "input": str(entry._fields[0].size),
			"primary": str(submit.size), "secondary": str(exit_button.size), "logo": str(logo.size), "title": str(title.size),
			"form_width": form_width, "safe_width": safe_width})
		if example[0] == Vector2i(941,1672):
			_expect(absf(logo.get_global_rect().get_center().x - 470.5) < 3,
				"Approved portrait centers the shared logo above the form")
			_expect(submit.size.is_equal_approx(Vector2(740.0, 116.0)) and exit_button.size.is_equal_approx(Vector2(265.0, 74.0)),
				"Approved portrait retains the reference action sizes")
		_expect(copyright.text.contains("Freeboozstudio") and is_equal_approx(copyright.get_global_rect().end.y, bounds.end.y),
			"Copyright stays on the safe bottom edge")
		await _capture(example[1])
		await _activate(exit_button)
		var confirmation: Control = app._exit_dialog
		_expect(confirmation != null and confirmation.visible, "Exit opens the shared rural confirmation")
		await _activate(confirmation.call("get_cancel_button") as Button)
		_expect((not is_instance_valid(confirmation) or not confirmation.visible) and not app.quit_requested, "Cancel preserves the login screen")
	var compact_sizes := [Vector2i(640,360), Vector2i(800,360), Vector2i(800,500)]
	for dims in compact_sizes:
		root.size = dims
		await _settle()
		var login_scroll := app.find_child("MahjongLoginScroll", true, false) as ScrollContainer
		var register := app.find_child("MahjongRegisterButton", true, false) as Button
		var forgot := app.find_child("MahjongForgotPasswordButton", true, false) as Button
		var eye := app.find_child("MahjongTogglePasswordVisibility", true, false) as Button
		for field in [app._login_identifier, app._login_secret, submit, wechat, app._guest_button, exit_button, register, forgot, eye]:
			_expect(login_scroll.get_global_rect().encloses(field.get_global_rect()),
				"%s is fully visible without scrolling at %s" % [field.name, dims])
			_expect(field.get_combined_minimum_size().x >= 44 and field.get_combined_minimum_size().y >= 44,
				"%s preserves a 44 × 44 minimum in compact entry" % field.name)
		_expect(submit.size.is_equal_approx(Vector2(280.0, 52.0)) and register.size.is_equal_approx(Vector2(126.0, 48.0)),
			"Compact primary and secondary buttons hold their sizes when the window grows")
		await _activate(forgot)
		var message := app._error_dialog.find_child("MahjongErrorMessage", true, false) as Label
		var message_scroll := message.get_parent().get_parent() as ScrollContainer
		_expect(message_scroll.get_global_rect().encloses(message.get_global_rect()),
			"The error message fits without scrolling at %s" % str(dims))
		var confirmation := app._error_dialog.find_child("MahjongErrorConfirmButton", true, false) as Button
		_expect(confirmation.size.is_equal_approx(Vector2(224.0, 46.0)),
			"The error button holds its size as the dialog expands")
		await _activate(app._error_dialog.find_child("MahjongErrorConfirmButton", true, false))
		app._set_login_status("")
	root.size = Vector2i(390,844)
	await _settle()
	var eye := app.find_child("MahjongTogglePasswordVisibility", true, false) as Button
	await _activate(eye)
	_expect(not app._login_secret.secret, "Eye changes the actual password visibility")
	await _activate(eye)
	_expect(app._login_secret.secret, "Second eye click restores concealment")
	var before: bool = app._remember_identifier.button_pressed
	await _activate(app._remember_identifier)
	_expect(app._remember_identifier.button_pressed != before, "Remember-account is a real toggle")
	await _activate(wechat)
	_expect(app._state == "login" and app._status.is_visible_in_tree() and app._status.text.contains("未配置微信"),
		"WeChat reports its actual unconfigured state instead of pretending to authenticate")
	await _settle()
	await _capture("phone_wechat_unavailable.png")
	_expect(is_instance_valid(app._error_dialog), "Unavailable login method opens the shared error dialog")
	await _activate(app._error_dialog.find_child("MahjongErrorConfirmButton", true, false))
	_expect(not is_instance_valid(app._error_dialog), "Acknowledging the dialog restores the login controls")
	app._set_login_status("")
	await _activate(submit)
	_expect(app._request_kind.is_empty() and app._status.text.contains("用户名"), "Empty account input shows validation without sending a request")
	await _activate(app._error_dialog.find_child("MahjongErrorConfirmButton", true, false))
	app._set_login_status("")
	await _enter_text(app._login_identifier, "bamboo_fixture")
	_expect(app._login_identifier.text == "bamboo_fixture", "Native keyboard text reaches the focused username field")
	for dims in [Vector2i(941,1672), Vector2i(390,844), Vector2i(1600,720), Vector2i(1024,768)]:
		root.size = dims
		await _settle()
		_expect(app._login_identifier.text == "bamboo_fixture" and app._login_identifier.has_focus(),
			"Orientation changes preserve form data and focus")
	await _activate(app.find_child("MahjongRegisterButton", true, false))
	_expect(app._state == "account_register" and app._login_secret.secret, "Register opens the real registration form")
	for example in [[Vector2i(941,1672), "registration_941x1672.png"], [Vector2i(390,844), "registration_390x844.png"],
		[Vector2i(2024,1620), "registration_2024x1620.png"],
		[Vector2i(640,360), "registration_640x360.png"], [Vector2i(800,360), "registration_800x360.png"],
		[Vector2i(1280,720), "registration_1280x720.png"], [Vector2i(2560,1080), "registration_ultrawide.png"]]:
		root.size = example[0]
		await _settle()
		var back: Button = app._login_form_back
		_expect(back.is_visible_in_tree() and back.get_global_rect().end.x <= root.size.x and back.get_global_rect().position.x > root.size.x * 0.65,
			"Registration uses the common return button in the top-right safe area")
		var brand: TextureRect = app._login_logo
		var safe := RURAL.safe_insets(app._screen)
		_expect(brand.is_visible_in_tree() and brand.position.is_equal_approx(Vector2(safe.x + 12, safe.y + 8)),
			"Registration brand stays at the upper-left safe edge at %s" % root.size)
		_expect(app._screen.get_global_rect().encloses(app._submit_account.get_global_rect()), "Registration submit stays reachable in portrait")
		var group: Rect2 = app._login_tray.get_global_rect()
		if app._login_header.visible:
			group = group.merge(app._login_header.get_global_rect())
		if example[0] in compact_sizes:
			var scroll := app.find_child("MahjongLoginScroll", true, false) as ScrollContainer
			for field in [app._login_identifier, app._login_secret, app._submit_account, app._login_form_title.get_parent()]:
				_expect(scroll.get_global_rect().encloses(field.get_global_rect()),
					"%s remains fully visible in compact registration at %s" % [field.name, root.size])
			_expect(app._submit_account.size.is_equal_approx(Vector2(224.0, 52.0)),
				"The registration button holds its size in compact landscape")
		_expect(absf(group.get_center().x - root.size.x * 0.5) <= 2.0,
			"Registration centers the bounded logo/form group at %s: %s" % [root.size, group])
		_expect(app._login_tray.size.x <= 741.0 and app._submit_account.size.y <= 117.0,
			"Registration controls do not grow unbounded with screen height or width")
		if root.size == Vector2i(390,844):
			var hint_width := app._login_secret.get_theme_font("font").get_string_size(app._login_secret.placeholder_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, app._login_secret.get_theme_font_size("font_size")).x
			_expect(app._login_secret.placeholder_text == "8–128位" and hint_width <= app._login_secret.size.x - 4.0,
				"The compact password length hint is complete rather than misleadingly clipped")
		for child in app._login_form_fields.get_children():
			if child is PanelContainer and child.has_meta("account_field"):
				_expect(child.size.y <= 91.0, "Registration input capsules keep bounded design heights")
		await _capture(example[1])
	await _activate(app._login_form_back)
	_expect(app._state == "login", "The shared top-right back button returns to the unified login screen")
	root.size = Vector2i(1440,810)
	await _settle()
	exit_button = app.find_child("MahjongLoginExitButton", true, false)
	await _activate(exit_button)
	await _capture("desktop_exit_confirmation.png")
	await _activate(app._exit_dialog.call("get_ok_button") as Button)
	_expect(app.quit_requested, "Exit confirmation uses the real quit action")
	app._account = {"account_id": "test-only", "display_name": "松风竹影"}
	app._show_guest_identity()
	for dims in [Vector2i(540,960), Vector2i(1280,800)]:
		root.size = dims
		await _settle()
		_expect(app._screen.get_global_rect().encloses(app._lobby_entry.get_global_rect()), "Guest confirmation remains reachable")
	app._guest_identity_back()
	_expect(app._state == "login" and app._login_identifier != null, "Guest back returns to the new account entry")
	app._show_lobby()
	await _settle()
	app.find_child("MahjongSettingsButton", true, false).pressed.emit()
	var panel := app.find_child("MahjongToolPanel_settings", true, false) as Control
	_expect(panel != null, "Lobby retains the shared settings entry")
	for dims in [Vector2i(390,844), Vector2i(1600,720), Vector2i(1024,768)]:
		root.size = dims
		await _settle()
		_expect(panel.get_global_rect().get_center().is_equal_approx(app._screen.get_global_rect().get_center()), "Settings remains centered")
	_expect(Engine.max_fps == 0, "Debug validation keeps the frame cap disabled")
	if DisplayServer.get_name() != "headless":
		_expect(DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED, "Debug validation does not use vertical sync to cap frames")
	app.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preview-dir="):
			var report := FileAccess.open(arg.trim_prefix("--preview-dir=").path_join("login_proportions.json"), FileAccess.WRITE)
			if report != null: report.store_string(JSON.stringify(_measurements, "\t"))
	if not _failed: print("MAHJONG_LOGIN_TABLET_SMOKE_OK direct_account=true three_colors=true sizes=%d near_square_centered=true design_proportions=true real_pointer=%s keyboard_input=true focus_preserved=true unconfigured_wechat=true guest_back=true exit_cancel_confirm=true max_fps=0 vsync_disabled=true" % [_measurements.size(), str(DisplayServer.get_name() != "headless")])
	quit(int(_failed))

func _activate(button: Button) -> void:
	if DisplayServer.get_name() == "headless":
		if button.toggle_mode: button.button_pressed = not button.button_pressed
		button.pressed.emit()
	else:
		var ancestor := button.get_parent()
		while ancestor != null:
			if ancestor is ScrollContainer:
				ancestor.ensure_control_visible(button)
				await process_frame
			ancestor = ancestor.get_parent()
		var position := button.get_global_rect().get_center()
		var dialog := button.get_window()
		if dialog != root:
			await process_frame
			position = Vector2(dialog.position) + button.get_global_rect().get_center()
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			event.position = position
			root.push_input(event, true)
	await _settle()

func _enter_text(field: LineEdit, value: String) -> void:
	field.clear()
	field.grab_focus()
	if DisplayServer.get_name() == "headless":
		field.text = value
	else:
		for character in value:
			for down in [true, false]:
				var key := InputEventKey.new()
				key.pressed = down
				key.unicode = character.unicode_at(0)
				root.push_input(key, true)
	await _settle()

func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--preview-dir="): continue
		await RenderingServer.frame_post_draw
		var path := arg.trim_prefix("--preview-dir=").path_join(filename)
		_expect(root.get_texture().get_image().save_png(path) == OK, "Native screenshot was written")
