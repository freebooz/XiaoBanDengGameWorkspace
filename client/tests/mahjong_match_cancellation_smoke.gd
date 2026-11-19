extends SceneTree

const ROOM := "4608"
const MATCH_ID := "original-match"
const REASON := "有玩家断线超过5分钟，本局已解散"
const END := {"type":"mahjong_match_cancelled", "room_id":ROOM, "match_id":MATCH_ID, "reason":"disconnect_timeout", "message":REASON}
const DENIAL := {"type":"mahjong_error", "operation":"join", "code":"match_unavailable", "room_id":ROOM, "match_id":MATCH_ID}

class App extends "res://scripts/main.gd":
	func _request_health() -> void: _show_login()
	func _refresh_history() -> void: pass
	func _refresh_eggs() -> void: pass

class BoardWire extends Node:
	signal connection_lost(message: String)
	var opened := true
	var sent: Array[Dictionary] = []
	var retries := 0
	func is_open() -> bool: return opened
	func send(packet: Dictionary) -> Error:
		sent.append(packet.duplicate(true))
		return OK
	func stop() -> void: opened = false
	func _lose(message: String) -> void:
		opened = false
		retries += 1
		connection_lost.emit(message)

var failed := false

func _initialize() -> void: call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _run() -> void:
	for ingress in ["board", "lobby", "rejoin", "denial"]:
		await _released(ingress)
	await _normal_finish()
	await _detached_lobby()
	await _predeal_and_watcher()
	if not failed: print("MAHJONG_MATCH_CANCELLATION_OK board=true lobby=true reconnect=true exact_match=true resources_stopped=true notice_once=true finished_retained=true")
	quit(1 if failed else 0)

func _app() -> App:
	var app := App.new()
	root.add_child(app)
	app._account = {"account_id":"seat-a","display_name":"牌友"}
	app._egg_balance = 72
	app._recent.append({"match_id":"earlier-result"})
	app._match = {"status":"playing","start":true,"room_id":ROOM,"kind":"friend","seat_index":0}
	app._lobby_synced = true
	return app

func _board(app: App, spectating := false) -> Control:
	var context: Dictionary = app._match.duplicate(true)
	context["spectating"] = spectating
	var board: Control = app._make_game(false, context)
	var old: Node = board._transport
	old.stop()
	board.remove_child(old)
	old.queue_free()
	var wire := BoardWire.new()
	board.add_child(wire)
	wire.connection_lost.connect(board._board_lost)
	board._transport = wire
	return board

func _packet(board: Control, value: Dictionary) -> void:
	board._handle_packet(JSON.stringify(value))

func _deal(board: Control, id := MATCH_ID) -> void:
	_packet(board, {"type":"mahjong_joined","room_id":ROOM,"match_id":id,"your_seat":0})
	_packet(board, {"type":"mahjong_state","room_id":ROOM,"match_id":id,"your_seat":0,"status":"playing","phase":"turn",
		"turn":0,"dealer":0,"epoch":1,"remaining":55,"hand":[],"hand_counts":[14,13,13,13],"options":[]})

func _released(ingress: String) -> void:
	var app := _app()
	var board := _board(app)
	_deal(board)
	var wire: BoardWire = board._transport
	var old_room := END.duplicate()
	old_room.room_id = "4699"
	var old_match := END.duplicate()
	old_match.match_id = "another-hand"
	_packet(board, old_room)
	app._on_lobby_packet(JSON.stringify(old_match))
	_packet(board, {"type":"mahjong_match_cancelled", "reason":"disconnect_timeout", "room_id":ROOM})
	_packet(board, DENIAL)
	_check(app._game == board and not board._exiting, "Old, incomplete or late join packets must not cancel an admitted board")
	if ingress in ["rejoin", "denial"]:
		wire._lose("暂时掉线")
		app._on_lobby_state({"status":"idle"}, [])
		_check(app._game == board and not board._exiting, "A transient disconnect or idle lobby snapshot is insufficient to cancel a dealt match")
		wire.opened = true
		board._join_board()
		_check(wire.sent[-1].get("match_id") == MATCH_ID and wire.sent[-1].get("room_id") == ROOM, "A reconnect must claim the original room and match")
		_packet(board, {"type":"mahjong_error", "operation":"join", "message":"服务正在交接，请稍后重连"})
		_check(wire.retries == 2 and app._game == board, "Transient join denial must retry without releasing the active match")
		wire.opened = true
		board._join_board()
		var stale_denial := DENIAL.duplicate()
		stale_denial.match_id = "unrelated"
		_packet(board, stale_denial)
		_check(app._game == board, "A denial for a different match must not affect the rejoining board")
	board._pending_command = "command-in-flight"
	board._pending_action = true
	board._deadline_tick = Time.get_ticks_msec() + 15000
	board._voice_deadline.start(5)
	board._bubble_deadline.start(4)
	board._report_timeout.start(6)
	if ingress == "lobby":
		app._on_lobby_packet(JSON.stringify(END))
	else:
		_packet(board, DENIAL if ingress == "denial" else END)
	_check(app._state == "lobby" and app._game == null and app._lobby_view.is_lobby_page(), "A released board must return to the lobby instead of the stale room")
	_check(not wire.is_open() and board._exiting and not board._actions_ready() and board._pending_command.is_empty() and not board._pending_action,
		"Cancelled board must stop transport and forget pending actions")
	_check(board._voice_deadline.is_stopped() and board._bubble_deadline.is_stopped() and board._report_timeout.is_stopped() and board._deadline_tick == 0,
		"Cancelled board must stop its timers")
	if not is_instance_valid(app._error_dialog):
		_check(false, "Returning to lobby must present one readable reason")
		app.queue_free()
		await process_frame
		return
	var dialog: Control = app._error_dialog
	var label := dialog.find_child("MahjongErrorMessage", true, false) as Label
	var expected := "原对局已结束，可在大厅重新开局。" if ingress == "denial" else REASON
	_check(label != null and label.text == expected, "Display exactly the reason warranted by the authoritative event")
	app._on_lobby_packet(JSON.stringify(END))
	_packet(board, END)
	_packet(board, {"type":"mahjong_action_result", "command_id":"command-in-flight", "ok":true})
	if ingress in ["board", "lobby"]:
		app._on_lobby_state({"status":"playing","room_id":ROOM,"kind":"friend","start":true}, [])
		_check(app._state == "lobby" and app._lobby_view.is_lobby_page(), "A queued playing snapshot must not revive the released table's resume button")
	app._on_lobby_state({"status":"idle"}, [])
	_check(app._error_dialog == dialog and app._state == "lobby" and app._match.status == "idle", "A duplicate event or late result must not republish the reason")
	_check(app._egg_balance == 72 and app._account.account_id == "seat-a" and app._recent.size() == 1, "Releasing the match must preserve the signed-in account, balance and history")
	app.queue_free()
	await process_frame

func _normal_finish() -> void:
	var app := _app()
	var board := _board(app)
	_deal(board)
	_packet(board, {"type":"mahjong_state","room_id":ROOM,"match_id":MATCH_ID,"your_seat":0,"kind":"friend",
		"status":"finished","phase":"finished","epoch":2,"winners":[],"scores":[0,0,0,0],"can_rematch":true})
	app._on_lobby_state({"status":"matched","room_id":ROOM,"kind":"friend","previous_match_id":MATCH_ID,"completed_rounds":1}, [])
	app._on_lobby_packet(JSON.stringify(END))
	_check(app._game == board and board.finished_friend_match_id() == MATCH_ID, "A completed retained round must keep its settlement and rematch route")
	app.queue_free()
	await process_frame

func _detached_lobby() -> void:
	for next_room in [false, true]:
		var app := _app()
		var board := _board(app)
		_deal(board)
		board._return_now()
		await process_frame
		_check(app._game == null and app._detached_match.get("match_id") == MATCH_ID, "A voluntary return keeps the identity of the resumable board")
		app._on_lobby_state({"status":"idle"}, [])
		if next_room:
			app._on_lobby_state({"status":"waiting","kind":"friend","room_id":"9294"}, [])
		var stale := END.duplicate()
		stale.match_id = "older"
		app._on_lobby_packet(JSON.stringify(stale))
		_check(not is_instance_valid(app._error_dialog), "An unrelated lobby event cannot report a different match")
		app._on_lobby_packet(JSON.stringify(END))
		if next_room:
			_check(not is_instance_valid(app._error_dialog) and app._match.get("room_id") == "9294", "An old cancellation must not disturb a newly assigned room")
		else:
			var dialog: Control = app._error_dialog
			_check(is_instance_valid(dialog) and app._detached_match.is_empty(), "An already returned participant must receive the reason once")
			app._on_lobby_packet(JSON.stringify(END))
			_check(app._error_dialog == dialog, "Duplicate cancellation after a voluntary return must be ignored")
		app.queue_free()
		await process_frame

func _predeal_and_watcher() -> void:
	var app := _app()
	var board := _board(app)
	_packet(board, END)
	_check(app._game == board, "An unbound board cannot accept another match's timeout")
	app._on_lobby_state({"status":"matched","room_id":ROOM,"start":false}, [])
	_check(app._game == null, "Pre-deal loss of the original assignment must still return from the board")
	app._match = {"status":"playing","start":true,"room_id":ROOM,"kind":"friend"}
	board = _board(app, true)
	_packet(board, {"type":"mahjong_watch_joined","room_id":ROOM,"watch_seat":0})
	_packet(board, {"type":"mahjong_watch_state","room_id":ROOM,"match_id":MATCH_ID,"watch_seat":0,"phase":"turn","status":"playing","turn":1})
	_packet(board, END)
	app._on_lobby_packet(JSON.stringify(END))
	_packet(board, {"type":"mahjong_watch_ended","room_id":ROOM,"match_id":"old-watch","reason":"disconnect_timeout"})
	_check(app._game == board, "Spectators must ignore participant cancellations on both channels")
	_packet(board, {"type":"mahjong_watch_ended","room_id":ROOM,"match_id":MATCH_ID,"reason":"disconnect_timeout","message":"本局观战已结束"})
	_check(app._state == "lobby" and app._game == null, "The authoritative watch-ended event still closes the spectator board")
	app.queue_free()
	await process_frame
