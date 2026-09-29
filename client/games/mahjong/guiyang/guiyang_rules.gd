extends RefCounted
class_name XbdGuiyangMahjongRules
## XbdGuiyangMahjongRules（贵阳麻将客户端规则适配）
## 只实现UI提示需要的基础响应，正式胡牌/番型/结算由服务端RuleSet权威执行。


func can_peng(hand: Array, target: Dictionary) -> bool:
	var core_script = load("res://modules/game_framework/tile/mahjong_core.gd")
	var core = core_script.new()
	return core.count_tile(hand, target) >= 2


func can_gang_from_discard(hand: Array, target: Dictionary) -> bool:
	var core_script = load("res://modules/game_framework/tile/mahjong_core.gd")
	var core = core_script.new()
	return core.count_tile(hand, target) >= 3