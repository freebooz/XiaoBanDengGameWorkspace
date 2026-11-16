extends SceneTree

const VIEW_PATH := "res://modules/games/mahjong/guiyang/mahjong_lobby_view.gd"
const PAPER_SURFACE := preload("res://modules/foundation/ui/nine_patch_panel_style.gd")

var _view: Control
var _host: Control
var _actions: Array[Dictionary] = []
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ResourceLoader.exists(VIEW_PATH):
		push_error("The native Mahjong lobby view has not been implemented.")
		quit(1)
		return
	var script := load(VIEW_PATH) as Script
	if script == null:
		quit(1)
		return
	_view = script.new()
	_view.connect("action_requested", func(action: String, payload: Dictionary) -> void:
		if action not in ["clear_room_message", "close_rooms"]:
			_actions.append({"action": action, "payload": payload}))
	var data := _fixture()
	_view.call("apply", data)
	_host = Control.new()
	_host.size = Vector2(720, 1280)
	root.add_child(_host)
	_host.add_child(_view)
	await process_frame
	await _check_adaptive_layout(data)
	_check_lobby(data)
	await _capture_guided_if_requested()
	_check_custom_rules(data)
	_check_waiting_room(data)
	_check_active_room(data)
	_host.queue_free()
	await process_frame
	if _failures.is_empty():
		print("MAHJONG_LOBBY_VIEW_SMOKE_PASS")
	quit(int(not _failures.is_empty()))


func _check_adaptive_layout(data: Dictionary) -> void:
	var layout := _node("MahjongLobbyFeaturedActions") as BoxContainer
	if layout == null:
		_check(false, "The lobby provides reflowable native layout.")
		return
	var secondary := _node("MahjongLobbySecondaryActions") as VBoxContainer
	_check(not layout.vertical and is_instance_valid(secondary) and secondary.get_child_count() == 3,
		"Phone portrait shows one featured action beside three stacked room actions.")
	_press("MahjongOpenJoinButton")
	_check_join_title_surface()
	var code := _node("MahjongJoinCode") as LineEdit
	code.text = "0802"
	code.text_changed.emit(code.text)
	code.grab_focus()
	await process_frame
	await _resize_host(Vector2(1366, 1024))
	_check_join_title_surface()
	_check(_view._scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO,
		"The join page retains local scrolling when its form requires it.")
	_check(_visible("MahjongJoinRoomPage") and not layout.is_visible_in_tree() and code.get_global_rect().end.x <= _host.size.x,
		"The separate join page keeps the original input inside the tablet's usable area.")
	_check(_node("MahjongJoinButton").get_global_rect().size.y >= 76.0, "Landscape tablet gives the join action a larger touch target.")
	_check(_node("MahjongJoinCode") == code and code.text == "0802" and code.has_focus(),
		"Tablet reflow keeps the same focused input and room number.")
	_press("MahjongCloseJoinButton")
	_check(not layout.vertical and secondary.get_global_rect().position.x > _node("MahjongQuickButton").get_global_rect().position.x,
		"The landscape lobby preserves the featured action and room action column.")
	_press("MahjongTrainingHallButton")
	var training := _node("MahjongTrainingLayout") as BoxContainer
	_check(training != null and not training.vertical, "Training uses two columns on a landscape tablet.")
	var card := _node("MahjongTrainingBotCard") as PanelContainer
	var backdrop := _view.find_child("MahjongLobbyLandscape", true, false) as Control
	await process_frame
	await process_frame
	_check(backdrop.is_visible_in_tree() and _view._portrait_scene.texture == _view.TRAINING_COURTYARD,
		"Training shows its courtyard backdrop in landscape.")
	var surface := card.get_theme_stylebox("panel") if card != null else null
	_check(surface is PAPER_SURFACE and surface.paper != null and surface.rim != null
		and surface.source_cuts.x > 0 and surface.source_cuts.y > 0
		and surface.get_content_margin(SIDE_LEFT) >= 14 and surface.get_content_margin(SIDE_TOP) >= 12,
		"The training card uses a separate paper fill and nine-slice rim with readable content padding.")
	if card != null:
		var wide_card := card.size
		await _resize_host(Vector2(420, 900))
		_check(training.vertical and _view._training_grid.columns == 1 and card.size.y < wide_card.y,
			"The narrow phone switches to a single column and adjusts the card height.")
		await _resize_host(Vector2(1366, 1024))
	_press("MahjongTrainingHallBackButton")
	data.state = {"status": "waiting", "kind": "friend", "room_id": "8043", "capacity": 4, "player_account_ids": ["peer"]}
	_view.call("apply", data)
	await process_frame
	await process_frame
	var room := _node("MahjongRoomLayout") as BoxContainer
	_check(room != null and not room.vertical, "The waiting room uses two columns on a landscape tablet.")
	var info := _node("MahjongRoomInfo") as Control
	var seats := _node("MahjongRoomSeats") as Control
	_check(info.get_global_rect().end.x < seats.global_position.x, "Room controls and seating occupy separate columns.")
	var occupied := (_node("MahjongSeat1") as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
	var vacant := (_node("MahjongSeat2") as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
	_check(occupied.bg_color != vacant.bg_color and occupied.border_color != vacant.border_color,
		"An occupied unready seat has a different card color from an empty seat.")
	_check(backdrop.is_visible_in_tree() and _view._portrait_scene.anchor_bottom == 1.0,
		"The waiting room background covers the whole landscape window.")
	var wide_room_width: float = _view._content.size.x
	_check(wide_room_width >= _host.size.x * 0.9, "The waiting room uses the landscape width inside its margins.")
	await _resize_host(Vector2(1024, 768))
	_check(_view._content.size.x < wide_room_width, "The waiting room shrinks with the window.")
	await _resize_host(Vector2(1366, 1024))
	_check(_node("MahjongReadyButton").get_global_rect().end.y < _host.get_global_rect().end.y,
		"The readiness control remains on the first screen on a landscape tablet.")
	await _resize_host(Vector2(720, 1280))
	_check(room.vertical and info.get_global_rect().end.y < seats.global_position.y,
		"The waiting room stacks controls above seating on a portrait phone.")
	data.state = {"status": "idle"}
	_view.call("apply", data)
	await _resize_host(Vector2(900, 1200))
	_check(not layout.vertical, "A portrait tablet keeps the featured action beside the room actions.")
	await _resize_host(Vector2(720, 1280))
	code.clear()
	code.text_changed.emit("")


func _check_join_title_surface() -> void:
	var title := _node("MahjongJoinTitle") as Label
	var card := _node("MahjongJoinPanel") as PanelContainer
	_check(is_instance_valid(title) and title.is_visible_in_tree() and title.text == "加入房间"
		and is_instance_valid(card) and card.is_ancestor_of(title) and not _view._room_pages._title_row.is_visible_in_tree(),
		"The join title shares the room-number panel surface.")


func _resize_host(new_size: Vector2) -> void:
	_host.size = new_size
	for frame in range(3):
		await process_frame


func _capture_guided_if_requested() -> void:
	var output := OS.get_environment("MAHJONG_GUIDED_PREVIEW_DIR")
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	_press("MahjongTrainingHallButton")
	_press("MahjongGuidedTrainingButton")
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var tiles := _node("MahjongGuidedTile4")
	var displayed_area := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	_check(displayed_area.encloses(tiles.get_global_rect()), "The last tile choice stays within the rendered viewport.")
	var file_name := "guided_%dx%d.png" % [root.size.x, root.size.y]
	_check(root.get_texture().get_image().save_png(output.path_join(file_name)) == OK, "Can save the rendered teaching view.")
	_press("MahjongGuidedBackButton")
	_press("MahjongTrainingHallBackButton")


func _fixture() -> Dictionary:
	return {
		"state": {"status": "idle"},
		"presets": [
			{"rule_set_id": "guiyang", "rule_version": "v1", "name": "贵阳捉鸡", "summary": "支持杠牌与捉鸡。", "allow_chi": false, "chicken": true, "requires_kong_to_claim": true,
				"options": {"version": "1.0.0", "chicken": true, "charge_chicken": false, "black_eight": false, "requires_kong_to_claim": true, "rob_kong": true}},
			{"rule_set_id": "guiyang", "rule_version": "v2", "name": "贵阳基础", "summary": "普通贵阳玩法。", "allow_chi": false, "chicken": false, "requires_kong_to_claim": false},
		],
		"selected": {"rule_set_id": "guiyang", "rule_version": "v1"},
		"account": {"account_id": "self", "display_name": "小雨"},
		"privacy": {"available": true},
		"online": true, "pending": false, "message": "", "recent": [],
	}


func _check_lobby(data: Dictionary) -> void:
	_check(_visible("MahjongLobbyLandscape") and _visible("MahjongLobbyBrandMark"), "Lobby has its landscape and reusable brand.")
	var logo := _node("MahjongLobbyBrandMark")
	var header := _node("MahjongFlowHeader")
	_check(logo != null and header != null and logo.get_parent().get_index() < header.get_index(), "The reusable brand bar is above the player header.")
	var identity := _node("MahjongLobbyAccountName") as Label
	var avatar := _node("MahjongLobbyProfileAvatar") as TextureRect
	_check(is_instance_valid(avatar) and avatar.is_visible_in_tree() and avatar.texture != null
		and is_instance_valid(identity) and identity.text == "小雨" and "账号 · self" in identity.tooltip_text,
		"The player card shows its avatar and name, with current account details bound to the profile tooltip.")
	_press("MahjongLobbyProfileOpenButton")
	_expect("account_open")
	_check(not _shows_label("最近战绩"), "Empty history does not take space in the lobby.")
	_check(_node("MahjongRuleSelect") == null and _node("MahjongRuleDetails") == null,
		"The lobby has no rule selector or rule summary.")
	_press("MahjongQuickButton")
	_expect("quick")
	_press("MahjongCreateButton")
	_check(_visible("MahjongCreateRoomPage") and _actions.is_empty(), "Create opens a dedicated room configuration page.")
	_press("MahjongCreateRuleSelector")
	var rules := _node("MahjongCreateRuleCards") as GridContainer
	var first := _node("MahjongCreateRuleCard_guiyang_v1") as Button
	var second := _node("MahjongCreateRuleCard_guiyang_v2") as Button
	_check(rules != null and rules.get_child_count() == 2 and first != null and second != null,
		"Creation presents every authoritative preset version as a card.")
	if is_instance_valid(first) and is_instance_valid(second):
		_check(first.button_pressed and first.accessibility_name == "贵阳捉鸡" and "v1" in first.accessibility_description,
			"The room defaults to the catalog preset and exposes its version to accessibility tools.")
		_check(_shows_label("普通贵阳玩法。") and second.get_parent().find_child("MahjongCreateRuleIllustration", true, false) != null,
			"Rule cards show their server descriptions and a visual illustration.")
		_press("MahjongCreateRuleCard_guiyang_v2")
		_check(second.button_pressed and not first.button_pressed and _actions.is_empty(),
			"Changing a create card selects only that exact version without changing the lobby default.")
		_press("MahjongCustomRulesCreateButton")
		_check(_actions.size() == 1 and _actions[0].action == "create" and _actions[0].payload.get("rule_set_id") == "guiyang"
			and _actions[0].payload.get("rule_version") == "v2", "Creation submits the chosen preset ID and version.")
		_actions.clear()
		_press("MahjongCreateRuleSelector")
		_press("MahjongCreateRuleCard_guiyang_v1")
	_press("MahjongCustomRulesBackButton")
	_check(_disabled("MahjongTrainingButton") and _disabled("MahjongPracticeButton"), "Training controls live on their own page.")
	_press("MahjongTrainingHallButton")
	_check(_visible("MahjongTrainingTableIcon") and _visible("MahjongPracticeTilesIcon"),
		"Training gives each mode a distinct illustration.")
	_check(_shows_label("当前玩法 · 贵阳捉鸡  ·  v1"), "The training hall shows the selected server rule.")
	_press("MahjongTrainingButton")
	_expect("training")
	_press("MahjongPracticeButton")
	_expect("practice")
	_press("MahjongGuidedTrainingButton")
	_check(_visible("MahjongGuidedPage") and not _visible("MahjongPracticeButton"), "The teaching route opens its own offline page.")
	if _visible("MahjongGuidedPage"):
		_check(_disabled("MahjongGuidedDiscardButton"), "Discard requires selection.")
		_press("MahjongGuidedTile1")
		_press("MahjongGuidedDiscardButton")
		_check(_shows_label("选牌与打出"), "Discarding the wrong example tile leaves the lesson on the same step.")
		_press("MahjongGuidedTile3")
		_check(_shows_label("选牌与打出"), "The first correct tile click selects without advancing the lesson.")
		_press("MahjongGuidedTile3")
		_check(_shows_label("碰牌"), "The second click on the same selected tile confirms the tutorial discard.")
		_press("MahjongGuidedPengButton")
		_check(_disabled("MahjongGuidedHuButton"), "The default Guiyang pass scenario cannot claim a win before a completed kong.")
		_press("MahjongGuidedPassButton")
		_press("MahjongGuidedGangButton")
		_press("MahjongGuidedHuButton")
		_check(_shows_label("教学完成") and _actions.is_empty(), "Actual inputs complete all offline steps without a network command.")
		_press("MahjongGuidedRestartButton")
		_check(_shows_label("选牌与打出"), "Restart resets the teaching sequence.")
		_press("MahjongGuidedBackButton")
		_check(_visible("MahjongTrainingButton") and _visible("MahjongPracticeButton"), "Return shows both original training options.")
	_press("MahjongTrainingHallBackButton")
	_check(not _disabled("MahjongQuickButton"), "Back returns to the lobby's native actions.")
	var code := _node("MahjongJoinCode") as LineEdit
	_check(code != null and not code.is_visible_in_tree(), "The four-digit form starts closed.")
	_press("MahjongOpenJoinButton")
	_check(code != null and code.is_visible_in_tree() and _disabled("MahjongJoinButton"), "The join entry reveals the form with invalid submission gated.")
	if code == null:
		return
	_check(_visible("MahjongPasteRoomCodeButton"), "The join form offers an explicit touch paste control.")
	_check_view_clipboard(code)
	code.grab_focus()
	code.text = " ０8a-027x"
	code.text_changed.emit(code.text)
	_check(code.text == "0802", "Room input normalizes pasted digits without losing leading zero.")
	data.pending = true
	_view.call("apply", data)
	_check(_node("MahjongJoinCode") == code and code.text == "0802" and code.has_focus(),
		"Snapshot updates preserve the existing input, contents and keyboard focus.")
	_check(not code.editable and _disabled("MahjongJoinButton") and _disabled("MahjongQuickButton") and _disabled("MahjongTrainingHallButton"),
		"Pending requests prevent duplicate joins, room starts and transitions to local practice.")
	data.pending = false
	_view.call("apply", data)
	code.text_submitted.emit(code.text)
	_expect("join", {"room_id": "0802"})
	data.message = "好友房不存在"
	_view.call("apply", data)
	_check(code.is_visible_in_tree() and code.editable and code.text == "0802" and _shows_label("好友房不存在"),
		"A failed room join keeps the form, code and error visible.")
	_press("MahjongCloseJoinButton")
	_check(not code.is_visible_in_tree(), "The four-digit form can be closed without leaving the lobby.")
	_press("MahjongOpenJoinButton")
	_check(code.is_visible_in_tree() and code.text == "0802", "The form can be reopened without discarding the code.")
	data.message = ""
	data.online = false
	data.connecting = true
	_view.call("apply", data)
	_check(_disabled("MahjongRetryButton"), "An in-progress connection cannot be restarted by the retry button.")
	data.connecting = false
	_view.call("apply", data)
	_check(_disabled("MahjongJoinButton") and _disabled("MahjongQuickButton"), "Offline snapshot gates network actions.")
	_press("MahjongCloseJoinButton")
	_press("MahjongTrainingHallButton")
	_check(_disabled("MahjongTrainingButton") and not _disabled("MahjongPracticeButton"),
		"Local practice remains available while the lobby is disconnected.")
	_press("MahjongTrainingHallBackButton")
	_check(code.text == "0802", "Visiting the training hall preserves the entered room code.")
	_press("MahjongRetryButton")
	_expect("retry")
	data.online = true
	data.recent = [{"name": "贵阳捉鸡", "kind": "friend", "result": "自摸", "score": 12}]
	_view.call("apply", data)
	_check(not _shows_label("最近战绩") and _visible("MahjongHistoryOpenButton"),
		"History has its own page and keeps the lobby compact.")


func _check_custom_rules(data: Dictionary) -> void:
	var settings := _node("MahjongSettingsButton") as Button
	_check(settings != null and settings.text == "设置", "The lobby exposes general settings.")
	_press("MahjongSettingsButton")
	_expect("settings")
	_press("MahjongCreateButton")
	var chicken := _node("MahjongRuleChicken") as CheckButton
	var charge := _node("MahjongRuleChargeChicken") as CheckButton
	var black := _node("MahjongRuleBlackEight") as CheckButton
	var kong := _node("MahjongRuleKongPass") as CheckButton
	if chicken == null or charge == null or black == null or kong == null:
		_check(false, "The host can edit original server presets.")
		return
	_check(chicken.button_pressed and not charge.button_pressed and not black.button_pressed, "Custom defaults match the selected server preset.")
	_check(kong.disabled and kong.button_pressed, "Guiyang friend rooms lock the completed-kong requirement.")
	charge.button_pressed = true
	black.button_pressed = true
	chicken.button_pressed = false
	_check(charge.disabled and black.disabled and not charge.button_pressed and not black.button_pressed,
		"Chicken-dependent options are disabled and visibly off while chicken scoring is off.")
	data.pending = true
	_view.call("apply", data)
	_check(_disabled("MahjongCustomRulesCreateButton") and _disabled("MahjongCreateRuleCard_guiyang_v1"), "Pending commands disable custom creation and rule selection.")
	data.pending = false
	_view.call("apply", data)
	chicken.button_pressed = true
	_check(charge.button_pressed and black.button_pressed, "Re-enabling the parent preserves prior dependency edits.")
	_press("MahjongCustomRulesBackButton")
	_press("MahjongCreateButton")
	_check(black.button_pressed, "Closing custom rules retains edits for the current preset.")
	_press("MahjongCustomRulesCreateButton")
	_expect_create({"version": "1.0.0", "chicken": true, "charge_chicken": true, "black_eight": true,
		"requires_kong_to_claim": true, "rob_kong": true})
	chicken.button_pressed = false
	_press("MahjongCustomRulesCreateButton")
	_expect_create({"version": "1.0.0", "chicken": false, "charge_chicken": false, "black_eight": false,
		"requires_kong_to_claim": true, "rob_kong": true})
	_press("MahjongCustomRulesBackButton")

func _expect_create(options: Dictionary) -> void:
	var payload: Dictionary = _actions[0].payload if _actions.size() == 1 else {}
	var code := str(payload.get("room_id", ""))
	_check(code.length() == 4 and code.is_valid_int() and payload.get("round_limit") == 8 and payload.get("options") == options
		and payload.get("rule_set_id") == "guiyang" and payload.get("rule_version") == "v1",
		"Creation sends the chosen code, round count, preset ID, version and host rules.")
	_actions.clear()

func _check_view_clipboard(code: LineEdit) -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		return
	var original := DisplayServer.clipboard_get()
	DisplayServer.clipboard_set(" ０８０２\n")
	_press("MahjongPasteRoomCodeButton")
	_check(code.text == "0802" and not _disabled("MahjongJoinButton") and _actions.is_empty(),
		"Clipboard paste preserves leading zeroes and waits for explicit confirmation.")
	DisplayServer.clipboard_set("12345")
	_press("MahjongPasteRoomCodeButton")
	_check(code.text == "0802" and _shows_label("剪贴板中没有有效的四位房号"),
		"An unsuitable clipboard value leaves the previous room code in place.")
	DisplayServer.clipboard_set(original)
	code.clear()
	code.text_changed.emit("")


func _check_waiting_room(data: Dictionary) -> void:
	data.selected = {"rule_set_id": "guiyang", "rule_version": "v2"}
	data.state = {
		"status": "waiting", "kind": "friend", "room_id": "8043",
		"rule_set_id": "guiyang", "rule_version": "v1", "capacity": 4, "start": false,
		"seat_index": 0, "ready_players": 0, "player_account_ids": ["self"], "ready_account_ids": [],
	}
	_view.call("apply", data)
	var rule_details := _node("MahjongRoomRuleDetails") as Label
	_check(_visible("MahjongRoomCodePlaque"), "The room shows the code plaque in its own scene.")
	_check(not _node("MahjongJoinCode").is_visible_in_tree(), "A successful room snapshot takes the join form off-screen.")
	var progress := _node("MahjongReadyProgress") as ProgressBar
	_check(progress != null and progress.max_value == 4 and progress.value == 0,
		"Room readiness progress starts at the server's 0 / 4.")
	_check(rule_details != null and rule_details.is_visible_in_tree() and rule_details.text.begins_with("支持杠牌与捉鸡。"),
		"Waiting room shows the locked rule summary even when the lobby's selected rule differs.")
	var presets: Array = data.presets
	data.presets = []
	_view.call("apply", data)
	_check(rule_details != null and rule_details.text == "暂无玩法说明", "Waiting room does not invent missing rules.")
	data.presets = presets
	_view.call("apply", data)
	data.state.rule = {"name": "房主定制", "rule_version": "v1", "summary": "服务端锁定规则。",
		"options": {"version": "1.0.0", "chicken": true, "charge_chicken": true, "black_eight": true,
			"requires_kong_to_claim": false, "rob_kong": false}}
	_view.call("apply", data)
	_check(_shows_label("房主定制  ·  v1") and rule_details != null and "黑八" in rule_details.text and "不抢杠胡" in rule_details.text,
		"The waiting room displays the server's locked custom rule rather than the lobby's selected preset.")
	for seat in range(1, 5):
		var seat_panel := _node("MahjongSeat%d" % seat)
		_check(seat_panel != null and seat_panel.is_visible_in_tree(), "Room renders all four actual seat slots.")
	_check(_shows_label("1 / 4") and _shows_label("等待加入"), "The partial room reflects the actual occupied count and shows vacancies.")
	_check(not _disabled("MahjongReadyButton"), "A seated player can prepare before the friend room fills.")
	_press("MahjongReadyButton")
	_expect("ready")
	data.state.ready_account_ids = ["self"]
	data.state.ready_players = 1
	_view.call("apply", data)
	_check(progress != null and progress.value == 1, "Partial readiness is rendered from the server snapshot.")
	_press("MahjongReadyButton")
	_expect("unready")
	_press("MahjongCopyButton")
	_expect("copy", {"room_id": "8043"})
	data.state.status = "matched"
	data.state.player_account_ids = ["self", "p2", "p3", "p4"]
	data.state.ready_account_ids = ["p2", "p3"]
	data.state.ready_players = 2
	_view.call("apply", data)
	_check(_shows_label("4 / 4") and _shows_label("已准备"), "The matched room shows the full seat count and remote readiness.")
	_check(progress != null and progress.max_value == 4 and progress.value == 2, "Room progress follows the ready count.")
	data.state.reconnecting_account_ids = ["p2"]
	_view.call("apply", data)
	_check(_seat_shows(2, "重连中") and _seat_shows(3, "已准备") and progress.value == 2,
		"Only the disconnected occupied seat shows reconnecting, with server readiness unchanged.")
	data.state.reconnecting_account_ids = []
	_view.call("apply", data)
	_check(_seat_shows(2, "已准备") and not _shows_label("重连中"), "The next snapshot restores the original readiness badge.")
	data.state.completed_rounds = 1
	_view.call("apply", data)
	_check(_shows_label("下一局准备"), "A completed hand changes the waiting room title before the next hand.")
	_press("MahjongReadyButton")
	_expect("ready")
	data.state.ready_account_ids.append("self")
	data.state.ready_players = 3
	_view.call("apply", data)
	var ready := _node("MahjongReadyButton") as Button
	_check(ready != null and ready.text == "取消准备" and not ready.disabled, "The waiting room lets each player revoke their preparation.")
	_press("MahjongReadyButton")
	_expect("unready")
	_press("MahjongLeaveButton")
	_expect("leave")


func _check_active_room(data: Dictionary) -> void:
	data.state.status = "playing"
	data.state.start = true
	_view.call("apply", data)
	_check(_disabled("MahjongQuickButton") and _disabled("MahjongTrainingButton"), "An active room prevents new starts.")
	_press("MahjongResumeButton")
	_expect("resume")


func _node(node_name: String) -> Control:
	return _view.find_child(node_name, true, false) as Control


func _visible(node_name: String) -> bool:
	var node := _node(node_name)
	return node != null and node.is_visible_in_tree()


func _shows_label(caption: String) -> bool:
	for label: Label in _view.find_children("*", "Label", true, false):
		if label.is_visible_in_tree() and label.text == caption:
			return true
	return false


func _seat_shows(seat: int, caption: String) -> bool:
	var frame := _node("MahjongSeat%d" % seat)
	for label: Label in frame.find_children("*", "Label", true, false):
		if label.is_visible_in_tree() and label.text == caption:
			return true
	return false


func _disabled(node_name: String) -> bool:
	var button := _node(node_name) as BaseButton
	return button == null or not button.is_visible_in_tree() or button.disabled


func _press(node_name: String) -> void:
	_check(not _disabled(node_name), "Expected usable native button " + node_name)
	if not _disabled(node_name):
		(_node(node_name) as BaseButton).pressed.emit()


func _expect(action: String, payload: Dictionary = {}) -> void:
	_check(_actions.size() == 1 and _actions[0] == {"action": action, "payload": payload},
		"Expected one %s action with %s, received %s." % [action, payload, _actions])
	_actions.clear()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)
