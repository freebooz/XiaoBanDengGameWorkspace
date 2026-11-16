extends SceneTree

class ScreenFixture:
	extends "res://modules/games/mahjong/guiyang/guiyang_3d_screen.gd"
	func _load_quality() -> void:
		_music_enabled = false
	func _connect_socket() -> void: pass

var _failures := 0
var _next_round := 0
var _returned := 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _run() -> void:
	var board := ScreenFixture.new()
	board.match_context = {"room_id":"4826", "kind":"friend", "seat_index":0, "rule_set_id":"guiyang", "rule_version":"2.0.0"}
	board.request_return_to_lobby.connect(func(): _returned += 1)
	if board.has_signal("request_next_round"):
		board.connect("request_next_round", func(): _next_round += 1)
	root.add_child(board)
	board._handle_packet(JSON.stringify({"type":"mahjong_joined", "room_id":"4826", "your_seat":0}))
	var result := {
		"type":"mahjong_state", "room_id":"4826", "match_id":"first-round", "kind":"friend",
		"status":"finished", "phase":"finished", "rule_set_id":"guiyang", "rule_version":"2.0.0",
		"rule":{"name":"贵阳捉鸡", "chicken":true}, "your_seat":0, "winners":[0], "scores":[9,-3,-3,-3],
		"flipped_ji":{"suit":"tong", "rank":9}, "can_rematch":true,
	}
	board._handle_packet(JSON.stringify(result))
	var room := board.find_child("MahjongSettlementRoom", true, false) as Label
	var score := board.find_child("MahjongSettlementScore0", true, false) as Label
	_expect(room != null and "4826" in room.text and "2.0.0" in room.text, "结算应显示服务端房号和规则版本")
	_expect(score != null and "+9" in score.text, "结算应使用服务器分差")
	_expect(board.find_child("MahjongSettlementIndicator", true, false) != null, "翻鸡指示牌应显示服务器牌面")
	var rules := board.find_child("MahjongSettlementRulesButton", true, false) as Button
	_expect(rules != null, "结算缺少查看规则入口")
	if rules != null:
		rules.pressed.emit()
		_expect(board.find_child("MahjongToolPanel_rules", true, false) != null, "查看规则应打开本桌规则")
		board._close_tool()
	result["can_rematch"] = false
	result["kind"] = "quick"
	result.erase("flipped_ji")
	board._handle_packet(JSON.stringify(result))
	_expect(board.find_child("MahjongNextRoundButton", true, false) == null, "快配结算不应提供同房再来")
	_expect(board.find_child("MahjongSettlementIndicator", true, false) == null, "缺少翻鸡数据时不应绘制假牌")
	result["can_rematch"] = true
	result["kind"] = "friend"
	board._handle_packet(JSON.stringify(result))
	var again := board.find_child("MahjongNextRoundButton", true, false) as Button
	_expect(again != null, "好友房结算缺少同房再来入口")
	if again != null:
		again.pressed.emit()
		again.pressed.emit()
		_expect(_next_round == 1 and _returned == 0, "同房再来只能发出一次续局通知")
	board.queue_free()
	await process_frame
	if _failures == 0:
		print("MAHJONG_SERIES_UI_OK authoritative_scores=true indicator=true rules=true rematch=true")
	quit(0 if _failures == 0 else 1)
