extends SceneTree
## Exercise the supplied artwork on the real action controls and retain phase gating.

const CAPTURE = preload("res://modules/games/landlord/landlord_buttons_smoke.gd")

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> bool:
	if not value: push_error(message)
	return value

func _art(button: Button) -> TextureRect:
	return button.get_node_or_null("ActionArtwork") as TextureRect

func _visible_bounds(source: Image) -> Rect2:
	var min_x := source.get_width()
	var min_y := source.get_height()
	var max_x := 0
	var max_y := 0
	for y in range(source.get_height()):
		for x in range(source.get_width()):
			if source.get_pixel(x,y).a >= 0.01:
				min_x = mini(min_x,x)
				min_y = mini(min_y,y)
				max_x = maxi(max_x,x)
				max_y = maxi(max_y,y)
	return Rect2(min_x,min_y,max_x-min_x+1,max_y-min_y+1)

func _click(button: Button, touch: bool = false) -> bool:
	# Synthetic native events arrive in window pixels, as real mouse and touch events do.
	var point := root.get_final_transform() * button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	for frame in range(2): await process_frame
	var art := _art(button)
	if art != null and not button.disabled and not touch:
		if not _check(art.self_modulate.r > 1.0, "Artwork hover feedback missing: " + button.text): return false
	if touch:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.position = point
		event.pressed = true
		Input.parse_input_event(event)
		for frame in range(2): await process_frame
		if art != null and not button.disabled:
			if not _check(art.self_modulate.r < 1.0 and art.self_modulate.a == 1.0, "Artwork pressed feedback missing: " + button.text): return false
		event.pressed = false
		Input.parse_input_event(event)
	else:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = true
		Input.parse_input_event(event)
		for frame in range(2): await process_frame
		if art != null and not button.disabled:
			if not _check(art.self_modulate.r < 1.0 and art.self_modulate.a == 1.0, "Artwork pressed feedback missing: " + button.text): return false
		event.pressed = false
		Input.parse_input_event(event)
	await process_frame
	return true

func _run() -> void:
	var screen = CAPTURE.CaptureScreen.new()
	var suffix := str(Time.get_ticks_usec())
	screen.preference_file = "user://landlord_art_%s.cfg" % suffix
	screen.history_file = "user://landlord_art_%s.json" % suffix
	screen.training_mode = true
	screen.match_context = {"room_id":"训练", "account_id":"button-art"}
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.set_process(false)
	await process_frame
	var hand: Array = []
	for id in range(20):
		hand.append({"id":id, "rank":3 + id % 13, "suit":["spade", "heart", "club", "diamond"][id % 4]})
	screen._state = {"status":"playing", "phase":"bid", "your_seat":0, "turn":0, "players":["我","清风明月","墨韵知音"], "hand_counts":[20,17,17], "hand":hand, "bottom":[], "landlord":-1, "highest_bid":1, "multiplier":1, "room_id":"训练", "epoch":2, "deal_number":1}
	screen._render()
	await process_frame
	var buttons: Array[Node] = screen._action_layer.get_children()
	for index in [1,2,3,4,5]:
		var button: Button = buttons[index]
		var art := _art(button)
		if not _check(art != null and art.texture is AtlasTexture, "Supplied action artwork missing: " + button.text): quit(1); return
		var atlas := art.texture as AtlasTexture
		var source := atlas.atlas.get_image()
		if not _check(atlas.region.encloses(_visible_bounds(source)) and source.get_pixel(0,0).a == 0.0 and source.get_size() == Vector2i(2172,724), "Artwork must retain the original alpha and complete visible silhouette"): quit(2); return
		if not _check(art.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED and art.mouse_filter == Control.MOUSE_FILTER_IGNORE and button.get_theme_color("font_color").a == 0.0, "Artwork must keep aspect without repeated text or intercepted clicks"): quit(3); return
		if not _check(button.size.x >= 160 and button.size.y >= 58 and Rect2(Vector2.ZERO,screen.size).encloses(button.get_global_rect()), "Original touch target was reduced or clipped"): quit(4); return
		if index == 5 and not _check(art.position.y < 0 and Rect2(Vector2.ZERO,screen.size).encloses(art.get_global_rect()), "Raised 2x badge was reduced into the button body or clipped"): quit(17); return
		if button.disabled and not _check(art.self_modulate.a < 1.0, "Disabled artwork has no state feedback"): quit(5); return
	if not _check(_art(buttons[0]) == null and buttons[0].text == "抢地主", "Unsupplied bid button fallback lost"): quit(6); return
	if not await _click(buttons[1], true): quit(16); return
	if not _check(screen.sent.back().get("action") == "bid" and screen.sent.back().get("amount") == 0, "Touch on 不抢 did not reach its authoritative action"): quit(7); return
	screen._state["phase"] = "double"
	screen._render()
	await process_frame
	buttons = screen._action_layer.get_children()
	if not _check(_art(buttons[1]) == null and buttons[1].text == "不加倍", "Declining double must not display 不抢 artwork"): quit(8); return
	if not await _click(buttons[5]): quit(16); return
	if not _check(screen.sent.back().get("action") == "double" and screen.sent.back().get("enabled") == true, "Mouse on 加倍 did not reach its authoritative action"): quit(9); return
	if not await _click(buttons[1], true): quit(16); return
	if not _check(screen.sent.back().get("action") == "double" and screen.sent.back().get("enabled") == false, "Declining double callback lost"): quit(10); return
	screen._state["phase"] = "play"
	screen._state["landlord"] = 0
	screen._state["has_last_play"] = true
	screen._state["last_play"] = {"seat":1, "cards":[hand[0]], "pattern":{"kind":"single"}}
	screen._render()
	await process_frame
	buttons = screen._action_layer.get_children()
	if not await _click(buttons[3], true): quit(16); return
	if not _check(screen.sent.back().get("action") == "hint", "Touch on 提示 callback lost"): quit(11); return
	screen._handle_packet(JSON.stringify({"type":"landlord_hint", "card_ids":[0,4]}))
	if not await _click(buttons[4]): quit(16); return
	if not _check(screen.sent.back().get("action") == "play" and screen.sent.back().get("card_ids").size() == 2, "Mouse on 出牌 callback lost"): quit(12); return
	if not await _click(buttons[2], true): quit(16); return
	if not _check(screen.sent.back().get("action") == "pass", "Touch on 不出 callback lost"): quit(13); return
	for phase in ["bid", "double", "play"]:
		screen._state["phase"] = phase
		screen._render()
		for frame in range(12): await process_frame
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--preview-prefix=") and DisplayServer.get_name() != "headless":
				var path: String = arg.trim_prefix("--preview-prefix=") + "_" + phase + ".png"
				if root.get_texture().get_image().save_png(path) != OK: quit(14); return
				print("LANDLORD_BUTTON_ART_PREVIEW=", path)
	screen._state["turn"] = 1
	screen._render()
	await process_frame
	var sent_count: int = screen.sent.size()
	if not await _click(screen._action_layer.get_child(4), true): quit(16); return
	if not _check(screen.sent.size() == sent_count, "Disabled artwork submitted an action outside the player turn"): quit(15); return
	screen.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("LANDLORD_BUTTON_ART_SMOKE_OK alpha_original=true aspect=true no_duplicate_text=true targets_retained=true mouse=true touch=true hover=true pressed=true bid=true double=true decline=true hint=true play=true pass=true disabled_gated=true")
	quit()
