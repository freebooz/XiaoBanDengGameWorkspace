extends SceneTree
## Three real product shells, real buttons, full game and received settlements.
var _apps: Array = []
var _games: Array = []
var _deadline := 0
var _hint_replies: Dictionary = {}

func _record_hint(_ids: Array, game: Node) -> void:
	var id := game.get_instance_id()
	_hint_replies[id] = int(_hint_replies.get(id,0))+1

func _initialize() -> void:
	call_deferred("_run")

func _wait(check: Callable, message: String) -> bool:
	while not check.call():
		await process_frame
		if Time.get_ticks_msec()>_deadline:
			push_error(message)
			return false
	return true

func _press(game: Control, parent: Node, text: String) -> bool:
	for index in range(_games.size()): _apps[index].visible = _games[index]==game
	for button in parent.find_children("*","Button",true,false):
		if button.text==text and not button.disabled:
			button.pressed.emit()
			return true
	push_error("Room UI button unavailable: "+text)
	return false

func _actor():
	var turn := int(_games[0]._state.get("turn",-1))
	for game in _games:
		if int(game._state.get("your_seat",-2))==turn: return game
	return null

func _all_epoch(epoch: int) -> bool:
	for game in _games:
		if int(game._state.get("epoch",0))<epoch: return false
	return true

func _run() -> void:
	var before_design := root.content_scale_size
	_deadline = Time.get_ticks_msec()+55000
	for index in range(3):
		var app = load("res://scripts/main.gd").new()
		root.add_child(app)
		app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		app.visible = index==0
		_apps.append(app)
	if not await _wait(func():
		_games.clear()
		for app in _apps:
			if app._state=="game":
				var game = app._screen.get_child(app._screen.get_child_count()-1)
				if game._state.get("status","")=="playing" and game._hand_nodes.size()==17: _games.append(game)
		return _games.size()==3,"Three product clients failed login/match/ready/deal"): quit(1); return
	var room := str(_games[0].match_context.room_id)
	var dealt := {}
	for index in range(3):
		_apps[index]._auto_flow = false
		var game = _games[index]
		game.history_file = "user://landlord_room_flow_%d.json" % index
		game._history.clear()
		game.hint_received.connect(_record_hint.bind(game))
		if str(game.match_context.room_id)!=room or str(game._state.get("rule_version",""))!="2.0.0": quit(2); return
		for other in range(index):
			if game._viewport.find_world_3d()==_games[other]._viewport.find_world_3d(): quit(3); return
		for card in game._state.hand:
			var id := int(card.id)
			if dealt.has(id): quit(4); return
			dealt[id] = true
	var actor = _actor()
	if not _press(actor,actor._action_layer,"抢地主"): quit(5); return
	await process_frame
	if not _press(actor,actor._overlay_layer,"叫 3 分"): quit(6); return
	if not await _wait(func(): return _all_epoch(2),"Bid did not broadcast"): quit(7); return
	for decision in range(3):
		actor = _actor()
		var epoch := int(actor._state.epoch)
		if not _press(actor,actor._action_layer,"加倍 ×2" if decision==0 else "不加倍"): quit(8); return
		if not await _wait(func(): return _all_epoch(epoch+1),"Double UI did not broadcast"): quit(9); return
	if _games[0]._state.phase!="play" or int(_games[0]._state.multiplier)!=2: quit(10); return
	actor = _actor()
	actor._open_tool("chat")
	await process_frame
	if not _press(actor,actor._overlay_layer,actor.CHAT_TEXTS[0]): quit(11); return
	var sender := int(actor._state.your_seat)
	if not await _wait(func():
		for game in _games:
			if not game._social_events.has(sender): return false
		return true,"Real room chat did not reach all clients"): quit(12); return
	for actions in range(240):
		if _games[0]._state.phase=="finished": break
		actor = _actor()
		var epoch := int(actor._state.epoch)
		var actor_id: int = actor.get_instance_id()
		var replies := int(_hint_replies.get(actor_id,0))
		actor._clear_selection()
		if not _press(actor,actor._action_layer,"提示"): quit(13); return
		if not await _wait(func(): return int(_hint_replies.get(actor_id,0))>replies,"Server did not answer the actual hint button"): quit(20); return
		var action := "出牌" if not actor._selected.is_empty() else "不出"
		if not _press(actor,actor._action_layer,action): quit(14); return
		if not await _wait(func(): return _all_epoch(epoch+1),"Hint/play/pass did not advance the full match"): quit(15); return
	if _games[0]._state.phase!="finished": quit(16); return
	for game in _games:
		if game._history.size()!=1 or not FileAccess.file_exists(game.history_file): quit(17); return
		if not _press(game,game._overlay_layer,"返回大厅"): quit(18); return
	await process_frame
	if root.content_scale_size!=before_design: quit(19); return
	await create_timer(0.5).timeout
	print("LANDLORD_ROOM_FLOW_OK clients=3 room=",room," login=true ready=true private_cards=51 worlds=3 bid=true double=true chat_broadcast=true hint_play_pass=true settlement_history=true lobby_restored=true")
	quit()
