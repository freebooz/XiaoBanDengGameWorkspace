extends SceneTree
## Four real product shells: login, matchmaking, ready, private 3D hands, play, leave.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var apps: Array = []
	var games: Array = []
	for seat in range(4):
		var app = load("res://scripts/main.gd").new()
		root.add_child(app)
		app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		app.visible = seat == 0
		apps.append(app)
	var deadline := Time.get_ticks_msec()+25000
	while games.size()!=4:
		games.clear()
		for app in apps:
			if app._state == "game":
				var game = app._screen.get_child(app._screen.get_child_count()-1)
				if game._hand_nodes.size()==27 and game._state.get("status","")=="playing": games.append(game)
		await process_frame
		if Time.get_ticks_msec()>deadline:
			push_error("Four clients did not enter the game")
			quit(1)
			return
	var room_id: String = games[0].match_context.get("room_id", "")
	for index in range(4):
		apps[index]._auto_flow = false
		if games[index].match_context.get("room_id", "")!=room_id or games[index]._hand_nodes.size()!=27:
			quit(2)
			return
		for other in range(index):
			if games[index]._viewport.find_world_3d()==games[other]._viewport.find_world_3d():
				push_error("Client lights and private models share the same world")
				quit(7)
				return
	var turn: int = int(games[0]._state.get("turn", -1))
	var actor = null
	for game in games:
		if int(game._state.get("your_seat",-2))==turn: actor=game
	actor._send({"type":"guandan_action","action":"hint"})
	while actor._selected.is_empty():
		await process_frame
		if Time.get_ticks_msec()>deadline:
			quit(3)
			return
	actor._send_play()
	while int(games[0]._state.get("epoch",1))<=1:
		await process_frame
		if Time.get_ticks_msec()>deadline:
			quit(4)
			return
	for frame in range(24): await process_frame
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screen-out="):
			root.get_texture().get_image().save_png(arg.trim_prefix("--screen-out="))
	actor._send({"type":"guandan_action","action":"leave"})
	var finished := false
	while not finished:
		await process_frame
		finished = true
		for game in games: finished = finished and game._state.get("phase","")=="finished"
		if Time.get_ticks_msec()>deadline:
			quit(5)
			return
	for app in apps: app._return_to_lobby()
	await process_frame
	print("GUANDAN_ROOM_FLOW_OK clients=4 room=",room_id," login=true lobby=true matching=true ready=true cards=108 play=true leave=true")
	quit()
