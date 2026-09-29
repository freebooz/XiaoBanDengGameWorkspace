extends RefCounted
class_name XbdChineseChessRules
## XbdChineseChessRules（中国象棋客户端规则辅助）
## 客户端只用于交互提示；最终合法性必须由Go服务端权威规则再次校验。

const RED := "red"
const BLACK := "black"


func is_inside_board(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x <= 8 and pos.y >= 0 and pos.y <= 9


func soldier_can_move(color: String, from: Vector2i, to: Vector2i) -> bool:
	if not is_inside_board(to):
		return false
	var dx := abs(to.x - from.x)
	var dy := to.y - from.y
	var forward := -1 if color == RED else 1
	var crossed := from.y <= 4 if color == RED else from.y >= 5
	if dy == forward and dx == 0:
		return true
	return crossed and dy == 0 and dx == 1


func horse_can_move(from: Vector2i, to: Vector2i) -> bool:
	var dx := abs(to.x - from.x)
	var dy := abs(to.y - from.y)
	return (dx == 1 and dy == 2) or (dx == 2 and dy == 1)