extends SceneTree
## Real packet -> board -> session -> lobby wallet projection, isolated from live rooms.

class AppFixture:
	extends "res://scripts/main.gd"
	func _request_health() -> void: _show_login()
	func _refresh_history() -> void: pass
	func _refresh_eggs() -> void: pass

class HttpFixture:
	extends "res://scripts/main.gd"
	func _request_health() -> void: _show_login()
	func _refresh_history() -> void: pass
	func _send_egg_request(_request: HTTPRequest, _url: String, _token: String) -> Error: return OK

var failures: Array[String] = []

func _initialize() -> void: call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _packet(balance: Variant, epoch: int = 2) -> Dictionary:
	return {"type":"mahjong_state", "room_id":"wallet-fixture", "match_id":"wallet-hand",
		"epoch":epoch, "status":"finished", "phase":"finished", "your_seat":0, "turn":0,
		"players":["wallet-host","peer-1","peer-2","peer-3"], "player_names":["田埂阿牛","村口阿福","稻田阿贵","河边阿喜"],
		"egg_counts":[balance,130,120,120], "egg_deltas":[-30,13,9,8], "scores":[-70,30,20,20], "hand":[], "hand_counts":[0,0,0,0],
		"melds":[[],[],[],[]], "discards":[], "remaining":0, "options":[], "winners":[1], "reason":"fixture"}

func _run() -> void:
	var app := AppFixture.new()
	root.add_child(app)
	app._account = {"account_id":"wallet-host", "display_name":"田埂阿牛"}
	app._session_token = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
	app._session_server = "https://127.0.0.1:1"
	app._egg_balance = 100
	var board: Control = app._make_game(false, {"room_id":"wallet-fixture", "kind":"friend", "seat_index":0})
	board._joined = true
	board._handle_packet(JSON.stringify(_packet(30)))
	_check(app._egg_balance == 30, "Committed settlement egg_counts must update the session wallet while the board is open")
	_check(board.match_context.get("own_egg_balance") == 30, "Reconnect fallback must use the latest authoritative balance")
	_check((board._seat_panels[0].get_node("MahjongSeatEggs") as Label).text == "30", "Seat must display wallet amount, not a score delta")
	var actual_delta := board.find_child("MahjongSettlementEggDelta0", true, false) as Label
	var points := board.find_child("MahjongSettlementScore0", true, false) as Label
	var net := board.find_child("MahjongSettlementNet0", true, false) as Label
	_check(actual_delta != null and actual_delta.text == "-30 鸡蛋" and points != null and "-70 分" in points.text,
		"Settlement must distinguish collected eggs from gameplay scores")
	_check(net != null and net.is_visible_in_tree() and net.text == "-30", "The egg icon in the summary must show the collected amount")
	# The commit/recovery refresh can reuse a gameplay epoch; zero is a real balance.
	board._handle_packet(JSON.stringify(_packet(0)))
	_check(app._egg_balance == 0, "Same-epoch committed wallet refresh must accept zero without adding/subtracting scores")
	var foreign := _packet(999, 3)
	foreign.room_id = "other-room"
	board._handle_packet(JSON.stringify(foreign))
	board._handle_packet(JSON.stringify(_packet(888, 1)))
	_check(app._egg_balance == 0, "Foreign-room and stale-epoch packets cannot replace a newer wallet")
	board._handle_packet(JSON.stringify(_packet(null, 3)))
	_check(app._egg_balance == -1 and not board.match_context.has("own_egg_balance"), "An explicit unknown balance must clear stale session and seat fallback values")
	_check((board._seat_panels[0].get_node("MahjongSeatEggs") as Label).text == "—", "Unknown authoritative balance must not show the pre-settlement wallet")
	board._handle_packet(JSON.stringify(_packet(42, 4)))
	var older := _packet(42, 4)
	older.erase("egg_deltas")
	board._handle_packet(JSON.stringify(older))
	actual_delta = board.find_child("MahjongSettlementEggDelta0", true, false) as Label
	_check(actual_delta != null and actual_delta.text == "— 鸡蛋", "Older snapshots without egg_deltas must not claim that score equals collected eggs")
	net = board.find_child("MahjongSettlementNet0", true, false) as Label
	_check(net != null and net.text == "—", "Unknown egg settlements must remain distinguishable from zero in the summary")
	app._show_lobby()
	var balance_button := app.find_child("MahjongEggBalanceButton", true, false) as Button
	_check(balance_button != null and balance_button.text == "鸡蛋 42", "Returning to lobby must immediately project the latest committed balance")
	# A queued old board callback after navigation may not contaminate a new view.
	board._handle_packet(JSON.stringify(_packet(999, 5)))
	_check(app._egg_balance == 42, "An inactive board must not mutate the session wallet")
	var next_board: Control = app._make_game(false, {"room_id":"next-wallet-room", "kind":"friend", "seat_index":0})
	_check(next_board.match_context.get("own_egg_balance") == 42, "Next round must start with the last authoritative wallet snapshot")
	app.queue_free()
	await process_frame
	_check_http_callbacks()
	_check_lobby_wallet_notifications()
	await process_frame
	await process_frame
	if failures.is_empty(): print("MAHJONG_WALLET_SYNC_OK settlement=true actual_delta=true same_epoch_zero=true stale_board=false next_round=true unknown=true http_session_guard=true lobby_invalidation=true reconnect=true")
	quit(0 if failures.is_empty() else 1)

func _wallet_response(request: HTTPRequest, amount: Variant, account := "wallet-host") -> void:
	var body := JSON.stringify({"account_id":account, "asset_id":"xbd_egg", "scope":"family", "amount":amount}).to_utf8_buffer()
	request.request_completed.emit(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), body)

func _check_http_callbacks() -> void:
	var app := HttpFixture.new()
	root.add_child(app)
	app._account = {"account_id":"wallet-host", "display_name":"田埂阿牛"}
	app._session_token = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
	app._session_server = "https://127.0.0.1:1"
	app._refresh_eggs()
	_wallet_response(app._egg_request, 100)
	_check(app._egg_balance == 100, "HTTP first snapshot must establish the wallet")
	app._refresh_eggs()
	var old_http: HTTPRequest = app._egg_request
	var board: Control = app._make_game(false, {"room_id":"wallet-fixture", "kind":"friend", "seat_index":0})
	board._joined = true
	board._handle_packet(JSON.stringify(_packet(0)))
	_wallet_response(old_http, 100)
	_check(app._egg_balance == 0, "A pre-settlement HTTP response cannot overwrite a newer board wallet event")
	app._refresh_eggs()
	var old_token: HTTPRequest = app._egg_request
	app._session_token = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
	_wallet_response(old_token, 91)
	_check(app._egg_balance == 0, "An earlier session token cannot supply the current account wallet")
	app._refresh_eggs()
	var old_server: HTTPRequest = app._egg_request
	app._session_server = "https://127.0.0.1:2"
	_wallet_response(old_server, 92)
	_check(app._egg_balance == 0, "An earlier server cannot supply the current account wallet")
	# Reject malformed wallet amounts rather than flooring fractions or showing debt.
	for amount in [-1, 12.5, "50", null]:
		app._refresh_eggs()
		_wallet_response(app._egg_request, amount)
		_check(app._egg_balance == 0, "Malformed or negative wallet amount must not replace a known balance")
	app._refresh_eggs()
	var old_session: HTTPRequest = app._egg_request
	app._clear_live_session()
	app._account = {"account_id":"wallet-host", "display_name":"田埂阿牛"}
	app._session_token = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
	app._session_server = "https://127.0.0.1:2"
	app._refresh_eggs()
	_wallet_response(old_session, 93)
	_check(app._egg_balance == -1, "Logout and re-login with the same identity must reject the old request generation")
	_wallet_response(app._egg_request, 0)
	_check(app._egg_balance == 0, "A fresh zero wallet snapshot remains valid after re-login")
	board.wallet_snapshot_received.emit({"account_id":"wallet-host", "amount":999})
	_check(app._egg_balance == 0, "An old board session cannot mutate a new login even if credentials match")
	var history := _packet(0)
	history["rule"] = {"name":"贵阳捉鸡"}
	history["kind"] = "friend"
	var row: Dictionary = app._history_summary(history)
	_check(row.get("egg_delta") == -30 and row.get("score") == -70, "History retains actual egg delta separately from the game score")
	app.queue_free()


func _check_lobby_wallet_notifications() -> void:
	var app := HttpFixture.new()
	root.add_child(app)
	app._account = {"account_id":"wallet-host", "display_name":"田埂阿牛"}
	app._session_token = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
	app._session_server = "https://127.0.0.1:1"
	app._show_lobby()
	var old_request: HTTPRequest = app._egg_request
	app._on_lobby_packet(JSON.stringify({"type":"mahjong_wallet_changed", "account_id":"other"}))
	_check(app._egg_request == old_request, "Another account's wallet notification cannot invalidate this player")
	app._on_lobby_packet(JSON.stringify({"type":"mahjong_wallet_changed", "account_id":"wallet-host"}))
	var refreshed := is_instance_valid(app._egg_request) and app._egg_request != old_request
	_check(refreshed, "An own-account notification must replace an earlier wallet request")
	if not refreshed:
		app.queue_free()
		return
	_wallet_response(old_request, 100)
	_wallet_response(app._egg_request, 125)
	var balance := app.find_child("MahjongEggBalanceButton", true, false) as Button
	_check(app._egg_balance == 125 and balance != null and balance.text == "鸡蛋 125", "Lobby should refresh the visible balance without reopening")
	app._lobby_synced = false
	app._on_lobby_state({"status":"waiting", "kind":"friend", "room_id":"6812", "player_account_ids":["wallet-host"]}, [])
	_check(is_instance_valid(app._egg_request), "Initial lobby snapshot after reconnect must recover a missed wallet event")
	if is_instance_valid(app._egg_request): _wallet_response(app._egg_request, 150)
	var room_balance := app.find_child("MahjongRoomEggBalance", true, false) as Label
	_check(room_balance != null and room_balance.is_visible_in_tree() and room_balance.text == "鸡蛋 150", "Waiting room should display the refreshed own balance")
	app.queue_free()
