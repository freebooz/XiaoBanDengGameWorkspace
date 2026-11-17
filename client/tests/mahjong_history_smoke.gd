extends SceneTree

const APP := preload("res://scripts/main.gd")

class HistoryFixture extends APP:
	var requests: Array[Dictionary] = []
	func _request_health() -> void:
		_show_login()
	func _send_history_request(request: HTTPRequest, url: String, token: String) -> Error:
		requests.append({"url": url, "authenticated": GUEST_SESSIONS.valid_token(token), "redirects": request.max_redirects})
		return OK

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if condition: return
	_failed = true
	push_error(message)


func _reply(app: HistoryFixture, code: int, matches: Array, cursor: String = "") -> void:
	var payload := JSON.stringify({"matches": matches, "next_cursor": cursor}).to_utf8_buffer()
	app._history_http.request_completed.emit(HTTPRequest.RESULT_SUCCESS, code, PackedStringArray(), payload)


func _row(id: String, seat: int, winners: Array, scores: Array) -> Dictionary:
	return {"match_id": id, "kind": "friend", "rule": {"name": "贵阳捉鸡"}, "your_seat": seat, "winners": winners, "scores": scores}


func _run() -> void:
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var app := HistoryFixture.new()
	app.session_store_path = "user://mahjong-history-smoke-%d" % OS.get_process_id()
	root.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	app._refresh_history()
	_expect(app.requests.is_empty(), "anonymous history must not do I/O")
	var token := "a".repeat(43)
	app._account = {"account_id": "history-client", "display_name": "小雨"}
	app._session_token = token
	app._session_server = "https://history.invalid"
	app._show_lobby()
	app._lobby_synced = true
	app._lobby_message = ""
	_expect(app.requests.size() == 1 and app.requests[0].url == "https://history.invalid/api/v1/mahjong/history?limit=12" and app.requests[0].authenticated and app.requests[0].redirects == 0, "lobby requests authenticated history without redirect")
	app._record_result({"match_id": "new", "name": "贵阳捉鸡", "kind": "friend", "score": 5, "result": "胡牌"})
	_expect(app._recent.size() == 1 and app.requests.size() == 1, "fresh local result appears at once and refresh coalesces")
	_reply(app, 200, [_row("old", 1, [], [0, 0, 0, 0]), _row("bad-seat", -1, [], [0, 0, 0, 0])])
	_expect(app._recent.size() == 2 and app._recent[0].match_id == "new" and app._recent[1].result == "流局", "fresh results survive asynchronous persistence")
	_expect(app.requests.size() == 2, "one event-triggered follow-up handles concurrent completion")
	_reply(app, 200, [_row("new", 1, [1], [-3, 9, -3, -3]), _row("old", 1, [], [0, 0, 0, 0])], "next_key")
	_expect(app._local_recent.is_empty() and app._recent.size() == 2 and app._recent[0].score == 9 and app._recent[0].result == "胡牌", "persisted result replaces same local ID and reads own score")
	var open := app.find_child("MahjongHistoryOpenButton", true, false) as Button
	_expect(open != null, "The lobby has a personal record entry.")
	if open != null:
		open.pressed.emit()
		_expect(app.find_child("MahjongHistoryMoreButton", true, false).is_visible_in_tree(), "A server cursor enables load more.")
		app.find_child("MahjongHistoryMoreButton", true, false).pressed.emit()
		_expect(app.requests.back().url.ends_with("?limit=12&cursor=next_key"), "The next request uses the opaque server cursor.")
		var page: HTTPRequest = app.get("_history_page_http")
		page.request_completed.emit(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(
			{"matches": [_row("old", 1, [], [0, 0, 0, 0]), _row("older", 0, [], [0, 0, 0, 0])]}).to_utf8_buffer())
		_expect(app._recent.size() == 2 and app.find_child("MahjongHistoryMatch_older", true, false) != null,
			"Pagination appends to the personal page without changing the recent lobby rows.")
		await _capture_if_requested("personal_history_list")
		app.find_child("MahjongHistoryMatch_new", true, false).pressed.emit()
		_expect(app.requests.back().url.ends_with("/api/v1/mahjong/history/new"), "Details load from the authorized match endpoint.")
		var detail := _row("new", 1, [], [-4, 7, -3, 0])
		detail.rule = {"name":"遵义定缺","rule_set_id":"zunyi_dingque","rule_version":"1.0.0","dingque":true}
		detail.score_breakdown = {"hu": [0, 0, 0, 0], "gang": [-1, 1, 0, 0], "ji": [0, 0, 0, 0], "cha_jiao": [-3, 6, -3, 0]}
		page = app.get("_history_page_http")
		page.request_completed.emit(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"match": detail}).to_utf8_buffer())
		var breakdown := app.find_child("MahjongHistoryBreakdown", true, false) as Label
		_expect(breakdown != null and "杠分  +1" in breakdown.text and "查叫  +6" in breakdown.text,
			"Zunyi details read the authenticated player's kong and wall-exhaustion wait scores.")
		await _capture_if_requested("personal_history_detail")
		var replay_button := app.find_child("MahjongHistoryReplayButton", true, false) as Button
		_expect(replay_button != null and replay_button.is_visible_in_tree(), "The match detail provides a replay action.")
		if replay_button != null:
			replay_button.pressed.emit()
			_expect(app.requests.back().url.ends_with("/api/v1/mahjong/history/new/replay"), "Replay is requested from the owning match endpoint.")
			var discard := {"id": 1, "suit": "wan", "rank": 1}
			var events := [
				{"seat": -1, "kind": "dingque", "missing_suits": ["tong","wan","tiao","wan"]},
				{"sequence": 1, "seat": 0, "kind": "play", "tile": discard, "discard_index": 0},
				{"sequence": 2, "seat": 1, "kind": "peng", "discard_index": 0, "meld_index": 0,
					"meld": {"kind": "peng", "from_seat": 0, "tiles": [discard, discard, discard]}},
				{"sequence": 3, "seat": 1, "kind": "bu_gang", "meld_index": 0,
					"meld": {"kind": "bu_gang", "from_seat": 0, "tiles": [discard, discard, discard, discard]}},
				{"sequence": 4, "seat": 2, "kind": "an_gang", "meld_index": 0,
					"meld": {"kind": "an_gang", "from_seat": 2, "tiles": [{}, {}, {}, {}]}},
				{"sequence": 5, "seat": -1, "kind": "wall_exhausted"},
			]
			page = app.get("_history_page_http")
			var transfers := [
				{"payer":0, "receiver":1, "category":"cha_jiao", "amount":3, "reason":"wall_exhausted"},
				{"payer":2, "receiver":1, "category":"cha_jiao", "amount":3, "reason":"wall_exhausted"},
			]
			page.request_completed.emit(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(
				{"replay": {"version": 1, "dealer": 0, "events": events, "score_transfers":transfers}}).to_utf8_buffer())
			var replay_seat := app.find_child("MahjongReplaySeat1", true, false) as Label
			_expect(replay_seat != null and "弃牌 0" in replay_seat.text and "缺 筒" not in replay_seat.text,
				"Step zero contains neither public discards nor future missing suit choices.")
			app.find_child("MahjongReplayNextButton", true, false).pressed.emit()
			_expect("缺 筒" in replay_seat.text, "Replay publishes the four choices together at the authoritative dingque event.")
			app.find_child("MahjongReplayNextButton", true, false).pressed.emit()
			_expect("弃牌 1" in replay_seat.text and "一万" in replay_seat.text, "The next step shows the committed discard.")
			app.find_child("MahjongReplayNextButton", true, false).pressed.emit()
			_expect("弃牌 0" in replay_seat.text, "A committed claim removes the visible discard.")
			app.find_child("MahjongReplayNextButton", true, false).pressed.emit()
			var second_seat := app.find_child("MahjongReplaySeat2", true, false) as Label
			_expect("副露 1 · 补杠 一万" in second_seat.text, "Upgrading a pong replaces the public meld in its original position.")
			app.find_child("MahjongReplayNextButton", true, false).pressed.emit()
			var third_seat := app.find_child("MahjongReplaySeat3", true, false) as Label
			_expect(third_seat.text.ends_with("副露 1 · 暗杠"), "A public replay shows only the concealed kong's existence.")
			await _capture_if_requested("personal_history_replay")
			app.find_child("MahjongReplayNextButton", true, false).pressed.emit()
			var ledger := app.find_child("MahjongReplayScoreTransfers", true, false) as Label
			_expect(ledger != null and ledger.is_visible_in_tree() and "查叫 · 1号座 → 2号座 · 3 分" in ledger.text
				and "查叫 · 3号座 → 2号座 · 3 分" in ledger.text, "The last committed replay step shows the payer and receiver of each exact transfer.")
			app.find_child("MahjongReplayPreviousButton", true, false).pressed.emit()
			_expect(ledger == null or not ledger.is_visible_in_tree(), "Rewinding hides the still-future score transfers.")
			app.find_child("MahjongReplayPreviousButton", true, false).pressed.emit()
			_expect(third_seat.text.ends_with("副露 0"), "Previous truncates the public replay prefix.")
			app.find_child("MahjongReplayBackButton", true, false).pressed.emit()
		app.find_child("MahjongHistoryDetailBackButton", true, false).pressed.emit()
		app.find_child("MahjongHistoryMatch_old", true, false).pressed.emit()
		page = app.get("_history_page_http")
		page.request_completed.emit(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(
			{"match": _row("old", 1, [], [0, 0, 0, 0])}).to_utf8_buffer())
		_expect(breakdown.text == "这局没有分项记录", "Older records keep their score total and report the missing breakdown.")
		app.find_child("MahjongHistoryDetailBackButton", true, false).pressed.emit()
		app.find_child("MahjongHistoryMatch_new", true, false).pressed.emit()
		page = app.get("_history_page_http")
		app.find_child("MahjongHistoryDetailBackButton", true, false).pressed.emit()
		page.request_completed.emit(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"match": detail}).to_utf8_buffer())
		_expect(not breakdown.is_visible_in_tree(), "A canceled single-match completion cannot reopen details.")
		app.find_child("MahjongHistoryBackButton", true, false).pressed.emit()
	app._return_to_lobby()
	_reply(app, 503, [])
	_expect(app._recent.size() == 2 and app._session_token == token, "temporarily unavailable history leaves last good results and valid session")
	app._refresh_history()
	var stale := app._history_http
	app._expire_live_session()
	stale.request_completed.emit(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"matches": [_row("leak", 0, [], [0, 0, 0, 0])]}).to_utf8_buffer())
	_expect(app._recent.is_empty() and app._account.is_empty(), "cleared session ignores stale history responses")
	await create_timer(0.06).timeout
	app.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	if not _failed: print("MAHJONG_HISTORY_SMOKE_OK")
	quit(int(_failed))


func _capture_if_requested(name: String) -> void:
	var output := OS.get_environment("MAHJONG_HISTORY_PREVIEW_DIR")
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var file_name := "%s_%dx%d.png" % [name, root.size.x, root.size.y]
	root.get_texture().get_image().save_png(output.path_join(file_name))
