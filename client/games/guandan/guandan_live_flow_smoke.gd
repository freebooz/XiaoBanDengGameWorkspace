extends SceneTree
## Real local service: guest login -> lobby -> training -> play -> lobby.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var before_design := root.content_scale_size
	var app = load("res://scripts/main.gd").new()
	root.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var deadline := Time.get_ticks_msec()+20000
	var login_sent := false
	while app._state != "training":
		await process_frame
		if app._state == "login" and not login_sent:
			login_sent = true
			app._login()
		elif app._state == "lobby": app._enter_training()
		if Time.get_ticks_msec()>deadline:
			push_error("Login/lobby/training did not complete: "+str(app._state))
			quit(1)
			return
	var game = app._screen.get_child(app._screen.get_child_count()-1)
	while game._hand_nodes.size()!=27:
		await process_frame
		if Time.get_ticks_msec()>deadline:
			quit(2)
			return
	game._send({"type":"guandan_action","action":"hint"})
	while game._selected.is_empty():
		await process_frame
		if Time.get_ticks_msec()>deadline:
			quit(3)
			return
	game._send_play()
	while int(game._state.get("epoch",1))<=1:
		await process_frame
		if Time.get_ticks_msec()>deadline:
			quit(4)
			return
	for frame in range(24): await process_frame
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screen-out="):
			root.get_texture().get_image().save_png(arg.trim_prefix("--screen-out="))
	if game._hand_nodes.size()!=26 or int(game._state.get("turn",-1))!=0:
		push_error("Human play or bot response failed")
		quit(5)
		return
	game._request_leave()
	await process_frame
	if app._state!="lobby" or root.content_scale_size!=before_design:
		quit(6)
		return
	print("GUANDAN_LIVE_FLOW_OK guest_login=true lobby=true training_cards=27 human_play=true bots=true return_lobby=true")
	quit()
