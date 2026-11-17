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
	board.match_context = {"room_id":"4826", "kind":"friend", "seat_index":0, "rule_set_id":"guiyang", "rule_version":"3.0.0"}
	board.request_return_to_lobby.connect(func(): _returned += 1)
	if board.has_signal("request_next_round"):
		board.connect("request_next_round", func(): _next_round += 1)
	root.add_child(board)
	board._handle_packet(JSON.stringify({"type":"mahjong_joined", "room_id":"4826", "your_seat":0}))
	var result := {
		"type":"mahjong_state", "room_id":"4826", "match_id":"first-round", "kind":"friend",
		"status":"finished", "phase":"finished", "rule_set_id":"guiyang", "rule_version":"3.0.0",
		"rule":{"name":"贵阳捉鸡", "chicken":true}, "your_seat":0, "winners":[0], "scores":[9,-3,-3,-3],
		"series_rounds":2, "series_total_rounds":3, "series_scores":[6,-1,-2,-3], "series_ranks":[1,2,3,4],
		"hu_details":[{"seat":0,"kind":"gang_shang_hua","pattern":"大对子","fan":7,"points":21}],
		"flipped_ji":{"suit":"tong", "rank":9}, "can_rematch":true,
	}
	board._handle_packet(JSON.stringify(result))
	var room := board.find_child("MahjongSettlementRoom", true, false) as Label
	var score := board.find_child("MahjongSettlementScore0", true, false) as Label
	_expect(room != null and "4826" in room.text and "3.0.0" in room.text, "结算应显示服务端房号和规则版本")
	_expect(score != null and "+9" in score.text, "结算应使用服务器分差")
	var series := board.find_child("MahjongSettlementSeries0", true, false) as Label
	var method := board.find_child("MahjongSettlementResult0", true, false) as Label
	_expect(series != null and "+6" in series.text and "第 1 名" in series.text and "2/3 局" in room.text, "累计牌分应与本局分差独立，并显示已有数据覆盖的局数")
	_expect(method != null and "杠上花" in method.text and "大对子 7 番" in method.text, "结算应投影服务端番型和胡法")
	var outcome := board.find_child("MahjongSettlementOutcome", true, false) as Label
	_expect(outcome != null and outcome.text == "杠上花", "主标题应显示服务端确认的和牌方式")
	_expect(board.find_child("MahjongSettlementIndicator", true, false) != null, "翻鸡指示牌应显示服务器牌面")
	var rules := board.find_child("MahjongSettlementRulesButton", true, false) as Button
	_expect(rules != null, "结算缺少查看规则入口")
	if rules != null:
		rules.pressed.emit()
		_expect(board.find_child("MahjongToolPanel_rules", true, false) != null, "查看规则应打开本桌规则")
		board._close_tool()
	result["can_rematch"] = false
	result["kind"] = "quick"
	result["winners"] = [1]
	result["win_kind"] = "zi_mo"
	result.erase("hu_details")
	result.erase("flipped_ji")
	board._handle_packet(JSON.stringify(result))
	_expect(board.find_child("MahjongNextRoundButton", true, false) == null, "快配结算不应提供同房再来")
	_expect(board.find_child("MahjongSettlementIndicator", true, false) == null, "缺少翻鸡数据时不应绘制假牌")
	outcome = board.find_child("MahjongSettlementOutcome", true, false) as Label
	_expect(outcome != null and outcome.text == "自摸", "其他玩家自摸时也应显示实际和牌方式")
	result["win_kind"] = "gang_shang_hua"
	board._handle_packet(JSON.stringify(result))
	method = board.find_child("MahjongSettlementResult1", true, false) as Label
	_expect(method != null and method.text == "杠上花", "没有番型明细时仍应显示服务端确认的杠上花")
	result["win_kind"] = "re_pao"
	result["win_from"] = 0
	board._handle_packet(JSON.stringify(result))
	method = board.find_child("MahjongSettlementResult1", true, false) as Label
	_expect(method != null and method.text == "热炮", "赢家座位应显示服务端确认的热炮")
	result["win_kind"] = "qiang_gang"
	result["robbed_tile"] = {"id": 28, "suit": "tong", "rank": 8}
	board._handle_packet(JSON.stringify(result))
	var summary := board.find_child("MahjongSettlementSummary", true, false) as Label
	_expect(summary != null and "抢杠牌 八筒" in summary.text, "结算应展示服务端确认的抢杠牌")
	result.erase("robbed_tile")
	result.erase("win_kind")
	result.erase("win_from")
	result["can_rematch"] = true
	result["kind"] = "friend"
	result["winners"] = []
	result["ready_seats"] = [1]
	result["hu_details"] = [{"seat":1,"kind":"cha_jiao","pattern":"平胡","fan":1,"points":3}]
	board._handle_packet(JSON.stringify(result))
	outcome = board.find_child("MahjongSettlementOutcome", true, false) as Label
	method = board.find_child("MahjongSettlementResult1", true, false) as Label
	_expect(outcome != null and outcome.text == "流局" and method != null and "查叫" in method.text, "黄庄必须按流局和查叫展示")
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
