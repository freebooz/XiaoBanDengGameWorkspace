extends SceneTree
## Keep cached-state buttons gated until the current connection has a fresh snapshot.

class GateScreen:
	extends "res://modules/games/landlord/landlord_3d_screen.gd"
	var wire_open := false
	var fail_send := false
	var sent: Array[Dictionary] = []
	func _socket_open() -> bool:
		return wire_open
	func _send(payload: Dictionary) -> void:
		_last_send_error = ERR_OUT_OF_MEMORY if fail_send else OK
		if fail_send:
			_status.text = "模拟发送失败"
		else: sent.append(payload.duplicate(true))


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> bool:
	if not value: push_error(message)
	return value


func _run() -> void:
	var screen := GateScreen.new()
	var suffix := str(Time.get_ticks_usec())
	screen.preference_file = "user://landlord_connection_%s.cfg" % suffix
	screen.history_file = "user://landlord_connection_%s.json" % suffix
	screen.training_mode = true
	screen.match_context = {"room_id":"训练"}
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.set_process(false)
	await process_frame
	if not _check(screen._socket.inbound_buffer_size >= 262144 and screen._socket.outbound_buffer_size >= 262144, "Voice transport buffers too small"): quit(1); return
	var snapshot := {"type":"landlord_state", "status":"playing", "phase":"bid", "turn":0, "your_seat":0, "players":["我","甲","乙"], "hand_counts":[17,17,17], "hand":[{"id":0,"rank":3,"suit":"spade"}], "highest_bid":1, "landlord":-1, "multiplier":1, "room_id":"训练"}
	screen._state = snapshot.duplicate(true)
	screen._joined = true
	screen._fresh_state = true
	screen._render()
	if not _check(not screen._actions_ready() and not screen._is_turn("bid"), "Cached state must not enable disconnected actions"): quit(2); return
	screen._send_bid(2)
	if not _check(screen.sent.is_empty() and screen._status.text.contains("连接恢复"), "Disconnected bid was sent or recovery feedback lost"): quit(3); return
	await process_frame
	for button in screen._action_layer.get_children():
		if button is Button and not _check(button.disabled, "Disconnected action button is still enabled"): quit(4); return
	screen.wire_open = true
	screen._joined = false
	screen._fresh_state = false
	if not _check(not screen._actions_ready(), "Open connection before join must stay gated"): quit(5); return
	screen._handle_packet(JSON.stringify({"type":"landlord_joined", "your_seat":0, "room_id":"训练"}))
	if not _check(screen._joined and not screen._fresh_state and not screen._actions_ready(), "Joined acknowledgement must wait for a fresh snapshot"): quit(6); return
	screen._send_bid(2)
	if not _check(screen.sent.is_empty(), "Join acknowledgement unlocked cached bid"): quit(7); return
	screen._handle_packet(JSON.stringify(snapshot))
	if not _check(screen._actions_ready() and screen._is_turn("bid"), "Fresh authoritative state did not unlock actions"): quit(8); return
	screen._open_tool("bid")
	screen.fail_send = true
	screen._send_bid(2)
	if not _check(screen._last_send_error != OK and screen._tool_open == "bid" and screen.sent.is_empty(), "Failed bid silently closed chooser"): quit(9); return
	screen._tool_open = "chat"
	var old_send := screen._last_social_send
	var accepted := screen._submit_social({"type":"landlord_social", "action":"chat", "quick_chat":"hello"})
	if not _check(not accepted and screen._tool_open == "chat" and screen._last_social_send == old_send, "Failed social send was reported successful"): quit(10); return
	screen.fail_send = false
	accepted = screen._submit_social({"type":"landlord_social", "action":"chat", "quick_chat":"hello"})
	if not _check(accepted and screen.sent.back().has("message_id") and screen._tool_open.is_empty(), "Successful social submit missing message ID"): quit(11); return
	var received: Array = []
	screen.hint_received.connect(func(ids: Array): received.append(ids.duplicate()))
	screen._handle_packet(JSON.stringify({"type":"landlord_hint", "card_ids":[]}))
	if not _check(received.size() == 1 and received[0].is_empty() and screen._status.text.contains("不出"), "Empty hint must emit completion and clear feedback"): quit(12); return
	screen.wire_open = false
	screen._update_selected()
	if not _check(screen._status.text.contains("连接恢复"), "Picking a cached model erased connection recovery feedback"): quit(13); return
	screen.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("LANDLORD_CONNECTION_SMOKE_OK buffers=262144 cached_offline_disabled=true open_before_join_disabled=true joined_without_snapshot_disabled=true fresh_state_unlocks=true send_error_preserved=true social_failure_false=true empty_hint_signal=true")
	quit()
