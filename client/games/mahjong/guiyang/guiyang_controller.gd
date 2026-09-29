extends RefCounted
## GuiyangMahjongController（贵阳麻将产品控制器）
## 展示麻将公共核心与贵阳规则集被按层组合，而不是复制另一套麻将工程。


func demo_summary() -> String:
	var core_script = load("res://modules/game_framework/tile/mahjong_core.gd")
	var core = core_script.new()
	var rules_script = load("res://modules/games/mahjong/guiyang/guiyang_rules.gd")
	var rules = rules_script.new()
	var wall: Array = core.build_standard_wall()
	var tile := {"suit": "wan", "rank": 3}
	var hand: Array = [tile.duplicate(), tile.duplicate(), {"suit": "tong", "rank": 2}]
	return "贵阳麻将规则演示：基础牌墙=%d张；两张3万可碰=%s。完整贵阳番型按正式规则文档继续补齐。" % [
		wall.size(),
		str(rules.can_peng(hand, tile))
	]