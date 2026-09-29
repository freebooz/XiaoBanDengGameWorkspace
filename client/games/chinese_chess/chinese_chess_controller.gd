extends RefCounted
## ChineseChessController（小板凳象棋产品控制器）
## 演示客户端公共棋盘规则已经被正确组合进独立产品工程。


func demo_summary() -> String:
	var rules_script = load("res://modules/game_framework/board/chinese_chess_rules.gd")
	var rules = rules_script.new()
	var soldier_ok: bool = rules.soldier_can_move("red", Vector2i(0, 6), Vector2i(0, 5))
	var horse_ok: bool = rules.horse_can_move(Vector2i(1, 9), Vector2i(2, 7))
	return "小板凳象棋规则演示：红兵前进一步=%s；红马走日=%s。正式对局仍以Go服务端判定为准。" % [
		str(soldier_ok),
		str(horse_ok)
	]