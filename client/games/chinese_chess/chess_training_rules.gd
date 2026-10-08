extends RefCounted
## 双人同机练习的基础走子规则，与服务端一期 ValidateMove 对齐。

static func validate(pieces: Dictionary, from: Vector2i, target: Vector2i, turn: String) -> String:
	if not pieces.has(from):
		return "起点没有棋子"
	var piece: Dictionary = pieces[from]
	if str(piece.get("color", "")) != turn:
		return "请选择当前回合的棋子"
	if target.x < 0 or target.x > 8 or target.y < 0 or target.y > 9 or target == from:
		return "目标位置无效"
	var occupied: Dictionary = pieces.get(target, {})
	if not occupied.is_empty() and str(occupied.get("color", "")) == turn:
		return "不能吃自己的棋子"
	var dx := absi(target.x - from.x)
	var dy := absi(target.y - from.y)
	match str(piece.get("type", "")):
		"chariot":
			if dx != 0 and dy != 0 or _blockers(pieces, from, target) != 0:
				return "车须沿无阻挡直线走"
		"cannon":
			if dx != 0 and dy != 0:
				return "炮须沿直线走"
			var blockers := _blockers(pieces, from, target)
			if occupied.is_empty() and blockers != 0 or not occupied.is_empty() and blockers != 1:
				return "炮吃子须隔一子，平移不能隔子"
		"horse":
			if not (dx == 1 and dy == 2 or dx == 2 and dy == 1):
				return "马须走日字"
			var leg := from + (Vector2i(_sign(target.x - from.x), 0) if dx == 2 else Vector2i(0, _sign(target.y - from.y)))
			if pieces.has(leg):
				return "马腿被挡"
		"elephant":
			if dx != 2 or dy != 2:
				return "象须斜走两格"
			if turn == "red" and target.y < 5 or turn == "black" and target.y > 4:
				return "象不能过河"
			if pieces.has(Vector2i(int((from.x + target.x) / 2), int((from.y + target.y) / 2))):
				return "象眼被挡"
		"advisor":
			if dx != 1 or dy != 1 or not _inside_palace(turn, target):
				return "士须在九宫斜走一格"
		"general":
			if dx + dy != 1 or not _inside_palace(turn, target):
				return "将须在九宫横竖走一格"
		"soldier":
			var forward := -1 if turn == "red" else 1
			var crossed := from.y <= 4 if turn == "red" else from.y >= 5
			if not (target.y - from.y == forward and dx == 0 or crossed and target.y == from.y and dx == 1):
				return "兵须前进一步，过河后可横走"
		_:
			return "未知棋子"
	return ""


static func _inside_palace(color: String, pos: Vector2i) -> bool:
	if pos.x < 3 or pos.x > 5:
		return false
	return pos.y >= 7 and pos.y <= 9 if color == "red" else pos.y >= 0 and pos.y <= 2


static func _sign(value: int) -> int:
	return -1 if value < 0 else 1


static func _blockers(pieces: Dictionary, from: Vector2i, target: Vector2i) -> int:
	var count := 0
	if from.x == target.x:
		var step := _sign(target.y - from.y)
		for y in range(from.y + step, target.y, step):
			if pieces.has(Vector2i(from.x, y)):
				count += 1
	elif from.y == target.y:
		var step := _sign(target.x - from.x)
		for x in range(from.x + step, target.x, step):
			if pieces.has(Vector2i(x, from.y)):
				count += 1
	else:
		return -1
	return count
