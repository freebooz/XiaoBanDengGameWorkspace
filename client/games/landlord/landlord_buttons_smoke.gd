extends SceneTree
## Validate the garden screen's actual controls and local preferences without simulating server success.

class CaptureScreen:
	extends "res://modules/games/landlord/landlord_3d_screen.gd"
	var sent: Array[Dictionary] = []
	func _actions_ready() -> bool:
		return true
	func _send(payload: Dictionary) -> void:
		_last_send_error = OK
		sent.append(payload.duplicate(true))
	func _submit_social(payload: Dictionary) -> bool:
		sent.append(payload.duplicate(true))
		return true


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> bool:
	if not condition: push_error(message)
	return condition


func _run() -> void:
	var screen := CaptureScreen.new()
	var suffix := str(Time.get_ticks_usec())
	screen.preference_file = "user://landlord_buttons_%s.cfg" % suffix
	screen.history_file = "user://landlord_buttons_%s.json" % suffix
	screen.training_mode = true
	screen.match_context = {"room_id":"训练", "account_id":"button-smoke"}
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.set_process(false)
	await process_frame
	var hand: Array = []
	for id in range(20): hand.append({"id":id, "rank":3 + id % 13, "suit":["spade", "heart", "club", "diamond"][id % 4]})
	screen._state = {"status":"playing", "phase":"bid", "your_seat":0, "turn":0, "players":["我", "牌友一", "牌友二"], "hand_counts":[20,17,17], "hand":hand, "bottom":[], "landlord":-1, "highest_bid":1, "multiplier":1, "room_id":"训练", "epoch":2, "deal_number":1}
	screen._layout_ui()
	screen._render()
	if not _require(screen._action_layer.get_child_count() >= 6, "Six reference actions missing"): quit(1); return
	screen._send_bid(1)
	if not _require(screen.sent.is_empty(), "Invalid bid must not be sent"): quit(2); return
	screen._open_tool("bid")
	await process_frame
	var bid_buttons: Array[Button] = []
	for node in screen._overlay_layer.find_children("*", "Button", true, false):
		if node.text.begins_with("叫 "): bid_buttons.append(node)
	if not _require(bid_buttons.size() == 3 and bid_buttons[0].disabled and not bid_buttons[1].disabled, "Bid chooser ignores highest bid"): quit(3); return
	screen._send_bid(2)
	if not _require(screen.sent.back().get("action") == "bid" and screen.sent.back().get("amount") == 2, "Bid action payload incorrect"): quit(4); return
	screen._state["phase"] = "double"
	screen._render()
	screen._send_double(true)
	if not _require(screen.sent.back().get("action") == "double" and screen.sent.back().get("enabled") == true, "Double action payload incorrect"): quit(5); return
	screen._send_double(false)
	if not _require(screen.sent.back().get("enabled") == false, "Decline doubling unavailable"): quit(6); return
	screen._state["phase"] = "play"
	screen._state["landlord"] = 0
	screen._state["has_last_play"] = true
	screen._state["last_play"] = {"seat":1, "cards":[hand[0]], "pattern":{"kind":"single"}}
	screen._render()
	screen._request_hint()
	if not _require(screen.sent.back().get("action") == "hint", "Hint action missing"): quit(7); return
	screen._handle_packet(JSON.stringify({"type":"landlord_hint", "card_ids":[0,4]}))
	if not _require(screen._selected.has(0) and screen._selected.has(4), "Hint response does not select actual card IDs"): quit(8); return
	screen._send_play()
	if not _require(screen.sent.back().get("action") == "play" and screen.sent.back().get("card_ids").size() == 2, "Play selection payload incorrect"): quit(9); return
	screen._send_pass()
	if not _require(screen.sent.back().get("action") == "pass", "Pass action unavailable"): quit(10); return
	screen._sort_hand()
	if not _require(screen._selected.has(0) and screen._selected.has(4), "Sort loses ID selection"): quit(11); return
	screen._toggle_hand()
	if not _require(screen._selected.is_empty() and not screen._hand_nodes[0].visible, "Collapse must really hide modeled hand"): quit(12); return
	screen._toggle_hand()
	if not _require(screen._hand_nodes[0].visible, "Expand must restore modeled hand"): quit(13); return
	screen._choose_back("jade")
	screen._choose_table("jade")
	screen._toggle_music()
	screen._toggle_sound()
	var preferences := ConfigFile.new()
	if not _require(preferences.load(screen.preference_file) == OK and preferences.get_value("appearance", "back") == "jade" and preferences.get_value("appearance", "table") == "jade" and not screen._music.playing, "Appearance/audio settings are not actually applied and saved"): quit(14); return
	screen._send_social_choice("chat", "quick_chat", "hello")
	if not _require(screen.sent.back().get("quick_chat") == "hello", "Chat payload incorrect"): quit(15); return
	screen._send_social_choice("emote", "emote", "smile")
	screen._send_prop("flower", 2)
	if not _require(screen.sent.back().get("prop") == "flower" and screen.sent.back().get("target_seat") == 2, "Prop target incorrect"): quit(16); return
	screen._receive_social({"type":"landlord_social", "action":"chat", "seat":1, "text":"牌友发来的聊天"})
	if not _require(screen._social_events.has(1), "Received chat is not displayed"): quit(17); return
	var settlement := screen._state.duplicate(true)
	settlement["type"] = "landlord_state"
	settlement["phase"] = "finished"
	settlement["winner"] = 0
	settlement["scores"] = [20,-10,-10]
	settlement["epoch"] = 42
	screen._handle_packet(JSON.stringify(settlement))
	screen._handle_packet(JSON.stringify(settlement))
	if not _require(screen._history.size() == 1 and screen._history[0].get("training") == true and FileAccess.file_exists(screen.history_file), "Actual received settlement must persist once and mark training"): quit(18); return
	screen._open_tool("history")
	await process_frame
	for tool in ["settings", "backpack", "rules", "chat", "emote", "prop", "history"]:
		screen._open_tool(tool)
		await process_frame
		for button in screen._overlay_layer.find_children("*", "Button", true, false):
			if not _require(Rect2(Vector2.ZERO, screen.size).encloses(button.get_global_rect()), "Tool button extends outside screen: " + button.text): quit(19); return
	screen._close_tool()
	screen.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://landlord_buttons_%s.cfg" % suffix))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://landlord_buttons_%s.json" % suffix))
	print("LANDLORD_BUTTONS_SMOKE_OK bid_legal=true double=true decline=true hint=true play=true pass=true sort=true collapse=true appearance_saved=true sound_applied=true social_intents=true received_chat=true received_result_dedup=true tools_visible=true teardown=true")
	quit()
