extends SceneTree
## Real packet/update/command path; no server or hidden hands are consulted.

class Fixture:
	extends "res://modules/games/mahjong/guiyang/guiyang_3d_screen.gd"
	var sent: Array[Dictionary] = []
	var transport_open := true
	var option_diagnostics: Array[Dictionary] = []
	func _debug_rejected_action_options() -> Dictionary:
		var diagnostic: Dictionary=super._debug_rejected_action_options()
		if not diagnostic.is_empty(): option_diagnostics.append(diagnostic)
		return diagnostic
	func _connect_socket() -> void: pass
	func _transport_open() -> bool: return transport_open
	func _play_sound(_cue: String = "discard") -> void: pass
	func _play_callout(_cue: String, _tile: Dictionary = {}) -> void: pass
	func _send(packet: Dictionary) -> void:
		_last_send_error = OK
		if packet.get("type") == "mahjong_action": sent.append(packet.duplicate(true))
	func _build_audio() -> void:
		super._build_audio()
		_music_enabled = false
		_sound_enabled = false

var _failed := false
var _epoch := 0
var _cases: Array[String] = []
var _output := ""

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failed = true
		push_error(message)

func _packet(phase := "turn", turn := 0) -> Dictionary:
	var hand: Array = []
	for kind in [["wan",1],["wan",1],["wan",1],["wan",2],["wan",3],["wan",4],["tong",1],["tong",2],["tong",3],["tiao",1],["tiao",2],["tiao",3],["tong",5],["tong",5]]:
		hand.append({"id":hand.size()+1,"suit":kind[0],"rank":kind[1]})
	if phase=="reaction": hand.pop_back()
	var last := {"id":90,"suit":"wan","rank":1}
	return {"type":"mahjong_state","room_id":"legal","match_id":"legal-hand","epoch":0,"status":"playing","phase":phase,"turn":turn,"your_seat":0,"players":["a","b","c","d"],"player_names":["田埂阿牛","河湾阿梅","村口阿旺","稻香大叔"],"egg_counts":[100,100,100,100],"hand":hand,"hand_counts":[hand.size(),13,13,13],"melds":[[],[],[],[]],"discards":[{"seat":turn,"tile":last,"claimed":false}] if phase=="reaction" else [],"last_discard":last if phase=="reaction" else {},"remaining":48,"options":[{"type":"play"}] if phase=="turn" else [{"type":"pass"}],"rule_set_id":"guiyang","rule_version":"2.0.0","dealer":0}

func _push(screen, packet: Dictionary) -> void:
	_epoch+=1
	packet.epoch=_epoch
	screen._clear_pending_command()
	screen.sent.clear()
	screen._handle_packet(JSON.stringify(packet))
	for frame in 2: await process_frame

func _reject_gang(screen, packet: Dictionary, label: String) -> void:
	await _push(screen,packet)
	_check(screen._legal_options("gang").is_empty(),label+": illegal option escaped filtering")
	_check(not screen._response_buttons.gang.is_visible_in_tree(),label+": unavailable kong was displayed")
	screen._on_response("gang")
	_check(screen.sent.is_empty(),label+": unavailable kong was sent")
	_cases.append(label)

func _tap(control: Control) -> void:
	var event:=InputEventScreenTouch.new()
	event.position=control.get_viewport_transform()*control.get_global_transform()*(control.size*0.5)
	event.pressed=true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	for frame in 2: await process_frame
	event.pressed=false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	for frame in 2: await process_frame

func _capture(suffix: String) -> void:
	if _output.is_empty() or DisplayServer.get_name()=="headless": return
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(_output.path_join(suffix+".png"))==OK,"Native action screenshot must be saved")

func _run() -> void:
	Engine.max_fps=0
	if DisplayServer.get_name()!="headless": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): _output=arg.trim_prefix("--output=")
		if arg.begins_with("--coach-extension="):
			GDExtensionManager.unload_extension("res://modules/games/mahjong/guiyang/native/mahjong_coach.gdextension")
			_check(GDExtensionManager.load_extension(arg.trim_prefix("--coach-extension="))==GDExtensionManager.LOAD_STATUS_OK,"Current native coach must load before the action fixture")
	var screen:=Fixture.new()
	screen.match_context={"room_id":"legal","seat_index":0}
	root.add_child(screen)
	await process_frame
	screen._handle_packet(JSON.stringify({"type":"mahjong_joined","room_id":"legal","match_id":"legal-hand","your_seat":0}))
	var packet:=_packet()
	await _reject_gang(screen,packet,"ordinary hand has no kong")
	_check(screen.option_diagnostics.is_empty(),"Fully legal options must not generate rejection diagnostics")
	await _capture("ordinary-no-kong")
	packet=_packet()
	packet.hand[3]={"id":4,"suit":"wan","rank":1}
	await _reject_gang(screen,packet,"four matching tiles cannot invent a missing server option")
	packet.options=[{"type":"gang"}]
	await _reject_gang(screen,packet,"bare UI alias is not a server action")
	_check(screen.option_diagnostics.size()==1,"One accepted rejected-options snapshot must emit one diagnostic")
	if not screen.option_diagnostics.is_empty():
		var diagnostic: Dictionary=screen.option_diagnostics.back()
		_check(diagnostic.size()==6 and diagnostic.has_all(["phase","turn","own_seat","epoch","received","accepted"]),"Action diagnostic fields must be an explicit non-sensitive allowlist")
		_check(diagnostic.phase=="turn" and diagnostic.turn==0 and diagnostic.own_seat==0 and diagnostic.epoch==_epoch and diagnostic.received==["gang"] and diagnostic.accepted==[],"Action diagnostic must describe the accepted private snapshot's rejected subtype")
	for call in 3: screen._legal_options("gang")
	_check(screen.option_diagnostics.size()==1,"Repeated UI legality queries must not emit duplicate diagnostic lines")
	packet.options=[{"type":"DIAGNOSTIC_PRIVATE_SENTINEL","account":"DIAGNOSTIC_PRIVATE_SENTINEL","hand":packet.hand,"token":"DIAGNOSTIC_PRIVATE_SENTINEL"},{"type":"play"}]
	await _push(screen,packet)
	_check(screen.option_diagnostics.size()==2 and screen.option_diagnostics.back().received==["unknown","play"] and screen.option_diagnostics.back().accepted==["play"],"Unknown subtype must be redacted while retaining accepted types")
	_check(not JSON.stringify(screen.option_diagnostics).contains("DIAGNOSTIC_PRIVATE_SENTINEL"),"Action diagnostic leaked an arbitrary string, account, token, or hidden hand")
	_cases.append("event-only redacted action diagnostics")
	packet=_packet("turn",1)
	packet.hand[3]={"id":4,"suit":"wan","rank":1}
	packet.options=[{"type":"an_gang","tile_id":1}]
	await _reject_gang(screen,packet,"another player's turn cannot expose own concealed kong")
	packet=_packet("reaction",1)
	packet.hand[3]={"id":4,"suit":"wan","rank":1}
	packet.options=[{"type":"an_gang","tile_id":1}]
	await _reject_gang(screen,packet,"reaction cannot expose concealed kong")
	packet=_packet()
	packet.options=[{"type":"ming_gang"}]
	await _reject_gang(screen,packet,"own turn cannot claim a discard kong")
	packet.options=[{"type":"an_gang","tile_id":1}]
	await _reject_gang(screen,packet,"three held copies cannot become a concealed kong")
	for invalid_id in [0,999,1.5,"1",-1]:
		packet=_packet()
		packet.hand[3]={"id":4,"suit":"wan","rank":1}
		packet.options=[{"type":"an_gang","tile_id":invalid_id}]
		await _reject_gang(screen,packet,"invalid concealed-kong tile ID %s"%str(invalid_id))
	packet=_packet()
	packet.hand[3]={"id":1,"suit":"wan","rank":1}
	packet.options=[{"type":"an_gang","tile_id":1}]
	await _reject_gang(screen,packet,"duplicate physical IDs cannot invent four held tiles")
	packet.hand[3].id=4
	packet.remaining=0
	await _reject_gang(screen,packet,"concealed kong requires a replacement wall tile")
	packet=_packet()
	packet.hand[3]={"id":4,"suit":"wan","rank":1}
	packet.options=[{"type":"play"},{"type":"an_gang","tile_id":2}]
	await _push(screen,packet)
	_check(screen._response_buttons.gang.is_visible_in_tree(),"Valid concealed kong is hidden")
	await _tap(screen._response_buttons.gang)
	_check(screen.sent.size()==1 and screen.sent[0].action=="an_gang" and screen.sent[0].tile_id==2,"Concealed kong must send the precise server-provided physical ID")
	screen._on_response("gang")
	screen._send_action("an_gang",2)
	_check(screen.sent.size()==1,"Repeated clicks or callbacks must not submit a pending action twice")
	_cases.append("pending command sends once")
	packet=_packet()
	packet.options=[{"type":"bu_gang","tile_id":1}]
	await _reject_gang(screen,packet,"upgrade requires an existing own pong")
	packet=_packet()
	packet.hand.remove_at(2)
	packet.hand.remove_at(1)
	packet.hand.pop_back()
	packet.hand_counts[0]=packet.hand.size()
	packet.melds[0]=[{"kind":"peng","tiles":[{"id":31,"suit":"wan","rank":1},{"id":32,"suit":"wan","rank":1},{"id":33,"suit":"wan","rank":1}],"from_seat":1}]
	packet.options=[{"type":"play"},{"type":"bu_gang","tile_id":1}]
	packet.remaining=0
	await _reject_gang(screen,packet,"pong upgrade requires a replacement wall tile")
	packet.remaining=48
	await _push(screen,packet)
	_check(screen._response_buttons.gang.is_visible_in_tree(),"Own fourth held tile must still allow a pong upgrade")
	await _tap(screen._response_buttons.gang)
	_check(screen.sent.size()==1 and screen.sent[0].action=="bu_gang" and screen.sent[0].tile_id==1,"Pong upgrade mapped to the wrong action or physical ID")
	packet.phase="reaction"
	packet.turn=1
	packet.last_discard={"id":90,"suit":"wan","rank":1}
	packet.discards=[{"seat":1,"tile":packet.last_discard,"claimed":false}]
	packet.hand.erase(packet.hand[0])
	packet.options=[{"type":"pass"},{"type":"ming_gang"},{"type":"bu_gang","tile_id":90}]
	await _reject_gang(screen,packet,"an exposed pong cannot use another player's fourth discard")
	packet=_packet("reaction",1)
	packet.options=[{"type":"peng"},{"type":"ming_gang"},{"type":"hu"},{"type":"pass"}]
	packet.remaining=0
	await _reject_gang(screen,packet,"discard kong requires a replacement wall tile")
	packet.remaining=48
	await _push(screen,packet)
	_check(screen._response_buttons.gang.is_visible_in_tree() and screen._response_buttons.peng.is_visible_in_tree() and screen._response_buttons.hu.is_visible_in_tree(),"Server-authorized reaction options must remain available")
	_check(not screen._play_button.visible,"Reaction phase must expose pass without an unavailable discard button")
	await _capture("legal-discard-kong")
	await _tap(screen._response_buttons.gang)
	_check(screen.sent.size()==1 and screen.sent[0].action=="ming_gang" and screen.sent[0].tile_id==0,"Discard kong must use the canonical zero-ID reaction contract")
	packet.hand[2]={"id":3,"suit":"wan","rank":9}
	await _reject_gang(screen,packet,"only two held copies cannot claim a discard kong")
	_check(screen._response_buttons.peng.is_visible_in_tree(),"Valid pong must survive rejecting an invalid kong")
	await _tap(screen._response_buttons.peng)
	_check(screen.sent.size()==1 and screen.sent[0].action=="peng" and screen.sent[0].tile_id==0,"Legal pong must submit the canonical reaction action")
	_cases.append("legal pong sends canonical action")
	for phase in ["turn","reaction"]:
		packet=_packet(phase,0 if phase=="turn" else 1)
		packet.options=[{"type":"hu"}]
		await _push(screen,packet)
		await _tap(screen._response_buttons.hu)
		_check(screen.sent.size()==1 and screen.sent[0].action=="hu" and screen.sent[0].tile_id==0,"Authoritative hu must submit in "+phase)
		_cases.append("authoritative hu in "+phase)
	packet=_packet("reaction",1)
	packet.options=[{"type":"pass"}]
	screen._response_buttons.pass.position=Vector2.ZERO
	await _push(screen,packet)
	var pass_button: Button=screen._response_buttons.pass
	_check(pass_button.is_visible_in_tree() and not pass_button.disabled,"Pass-only response must remain independently reachable")
	_check(screen.get_global_rect().encloses(pass_button.get_global_rect()),"Pass-only button must fit the screen")
	_check(not pass_button.get_global_rect().intersects(screen._brand_logo.get_global_rect()),"First pass-only response must be laid out away from the brand corner")
	for panel: Control in screen._seat_panels:
		_check(not pass_button.get_global_rect().intersects(panel.get_global_rect()),"Pass-only button must not cover a player card")
	await _tap(pass_button)
	_check(screen.sent.size()==1 and screen.sent[0].action=="pass" and screen.sent[0].tile_id==0,"Pass-only touch must submit a real pass")
	_cases.append("pass only response touch")
	packet=_packet("reaction",1)
	packet.options=[{"type":"ming_gang"},{"type":"pass"}]
	packet.discards[0].claimed=true
	await _reject_gang(screen,packet,"an already claimed discard cannot be claimed again")
	packet=_packet("reaction",1)
	packet.options=[{"type":"ming_gang","tile_id":999},{"type":"pass"}]
	await _reject_gang(screen,packet,"reaction rejects a stale explicit tile ID")
	packet=_packet()
	packet.options=[{"type":"peng"},{"type":"pass"},{"type":"play"}]
	await _push(screen,packet)
	_check(not screen._response_buttons.peng.visible and not screen._response_buttons.pass.visible,"Pong/pass must not leak into the own-discard phase")
	_check(screen._play_button.visible,"Own legal discard must stay reachable")
	packet=_packet("turn",1)
	packet.options=[{"type":"hu"},{"type":"play"}]
	await _push(screen,packet)
	_check(not screen._response_buttons.hu.visible and not screen._play_button.visible,"Another player's turn must not expose own hu/play")
	packet=_packet("reaction",1)
	packet.options=[]
	await _push(screen,packet)
	for button: Button in screen._response_buttons.values(): _check(not button.visible,"Empty server options must hide all response buttons")
	_check(not screen._play_button.visible,"Empty options must also hide play")
	var stale:=_packet("reaction",1)
	stale.epoch=_epoch-1
	stale.options=[{"type":"ming_gang"}]
	var prior_diagnostics := screen.option_diagnostics.size()
	screen._handle_packet(JSON.stringify(stale))
	_check(not screen._response_buttons.gang.visible,"Late older snapshot revived a kong button")
	_check(screen.option_diagnostics.size()==prior_diagnostics,"Rejected stale packets must not produce accepted-snapshot diagnostics")
	packet=_packet("reaction",1)
	packet.options=[{"type":"ming_gang"}]
	packet.saving=true
	await _push(screen,packet)
	_check(not screen._response_buttons.gang.visible,"Saving snapshots must suppress every action")
	packet.saving=false
	packet.status="finished"
	await _reject_gang(screen,packet,"finished hand suppresses stale kong options")
	screen._snapshot_ready=false
	screen._refresh_connection_actions()
	_check(not screen._response_buttons.gang.visible,"Reconnect without a private snapshot must suppress every action")
	# A popup's bound action belongs to the exact accepted private snapshot,
	# even when a reconnect refresh carries the same game epoch.
	packet=_packet()
	packet.hand=[{"id":1,"suit":"wan","rank":1},{"id":2,"suit":"wan","rank":1},{"id":3,"suit":"wan","rank":1},{"id":4,"suit":"wan","rank":1},{"id":5,"suit":"tong","rank":2},{"id":6,"suit":"tong","rank":2},{"id":7,"suit":"tong","rank":2},{"id":8,"suit":"tong","rank":2},{"id":9,"suit":"tiao","rank":1},{"id":10,"suit":"tiao","rank":2},{"id":11,"suit":"tiao","rank":3},{"id":12,"suit":"tiao","rank":4},{"id":13,"suit":"tiao","rank":5},{"id":14,"suit":"tiao","rank":6}]
	packet.options=[{"type":"play"},{"type":"an_gang","tile_id":1},{"type":"an_gang","tile_id":5}]
	await _push(screen,packet)
	screen._on_response("gang")
	var choices:=screen._overlay_root.find_children("MahjongGangChoice*","Button",true,false)
	_check(choices.size()==2,"Two valid kongs require a real choice popup")
	var stale_choice: Callable=choices[1].pressed.get_connections()[0].callable
	var old_key: Array=screen._action_snapshot_key()
	screen._handle_packet(JSON.stringify(packet))
	_check(screen._action_snapshot_key()!=old_key,"Same-epoch authoritative refresh must still retire old popup callbacks")
	stale_choice.call()
	_check(screen.sent.is_empty(),"A stale popup callback submitted against a replacement snapshot")
	choices=screen._overlay_root.find_children("MahjongGangChoice*","Button",true,false)
	var disconnected_choice: Callable=choices[0].pressed.get_connections()[0].callable
	screen.transport_open=false
	screen._refresh_connection_actions()
	for button: Button in screen._overlay_root.find_children("MahjongGangChoice*","Button",true,false): _check(button.disabled,"Disconnected kong choice remains enabled")
	disconnected_choice.call()
	_check(screen.sent.is_empty(),"A disconnected popup sent an action")
	screen.transport_open=true
	screen._handle_packet(JSON.stringify(packet))
	disconnected_choice.call()
	_check(screen.sent.is_empty(),"An old connection's popup survived a fresh snapshot")
	choices=screen._overlay_root.find_children("MahjongGangChoice*","Button",true,false)
	await _tap(choices[1])
	_check(screen.sent.size()==1 and screen.sent[0].action=="an_gang" and screen.sent[0].tile_id==5,"Fresh multi-kong choice lost its precise subtype/ID")
	print("ACTION_LEGALITY_RESULT="+str(not _failed)+" cases="+str(_cases.size()+16))
	screen.queue_free()
	await process_frame
	quit(1 if _failed else 0)
