extends SceneTree
## Real login, training and UI button intents through the running websocket.
var _deadline := 0

func _initialize() -> void:
	call_deferred("_run")

func _wait(test: Callable, message: String) -> bool:
	while not test.call():
		await process_frame
		if Time.get_ticks_msec()>_deadline:
			push_error(message)
			return false
	return true

func _press(parent: Node, text: String) -> bool:
	for button in parent.find_children("*","Button",true,false):
		if button.text==text and not button.disabled and button.is_visible_in_tree():
			button.pressed.emit()
			return true
	push_error("Unavailable actual UI button: "+text)
	return false

func _run() -> void:
	var before_design := root.content_scale_size
	_deadline = Time.get_ticks_msec()+25000
	var app = load("res://scripts/main.gd").new()
	root.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not await _wait(func(): return app._state=="login","Guest login page unavailable"): quit(1); return
	app._login()
	if not await _wait(func(): return app._state=="lobby","Guest login failed"): quit(2); return
	app._enter_training()
	var game = app._screen.get_child(app._screen.get_child_count()-1)
	if not await _wait(func(): return game._state.get("phase","")=="bid" and game._hand_nodes.size()==17,"Real training deal failed"): quit(3); return
	if not _press(game._action_layer,"抢地主"): quit(4); return
	await process_frame
	if not _press(game._overlay_layer,"叫 3 分"): quit(5); return
	if not await _wait(func(): return game._state.get("phase","")=="double" and game._hand_nodes.size()==20,"Bid UI did not enter doubling"): quit(6); return
	if not _press(game._action_layer,"加倍 ×2"): quit(7); return
	if not await _wait(func(): return game._state.get("phase","")=="play" and int(game._state.get("multiplier",0))==2,"Double UI did not change authoritative multiplier"): quit(8); return
	if not _press(game._action_layer,"提示"): quit(9); return
	if not await _wait(func(): return not game._selected.is_empty(),"Server did not return a legal hint"): quit(10); return
	if not _press(game._action_layer,"出牌"): quit(11); return
	if not await _wait(func(): return game._hand_nodes.size()==19,"Play UI did not consume a card"): quit(12); return
	game._open_tool("chat")
	await process_frame
	if not _press(game._overlay_layer,game.CHAT_TEXTS[0]): quit(13); return
	if not await _wait(func(): return game._social_events.has(0),"Room chat was not acknowledged/displayed"): quit(14); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screen-out=") and DisplayServer.get_name()!="headless":
			for frame in range(16): await process_frame
			root.get_texture().get_image().save_png(arg.trim_prefix("--screen-out="))
	game._request_leave()
	if not await _wait(func(): return app._state=="lobby","Training did not return to lobby"): quit(15); return
	await process_frame
	if root.content_scale_size!=before_design:
		push_error("Landlord did not restore lobby display")
		quit(16)
		return
	app.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("LANDLORD_LIVE_FLOW_OK login=true lobby=true training=true bid_button=true double_button=true hint_button=true play_button=true chat_echo=true lobby_restored=true")
	quit()
