extends RefCounted
class_name XbdMahjongCore
## XbdMahjongCore（麻将公共核心）
## 这里只包含可复用的牌张/牌墙/手牌能力；地方番型由具体RuleSet实现。


func build_standard_wall() -> Array[Dictionary]:
	var wall: Array[Dictionary] = []
	for suit in ["wan", "tong", "tiao"]:
		for rank in range(1, 10):
			for _copy in range(4):
				wall.append({"suit": suit, "rank": rank})
	for rank in range(1, 8):
		for _copy in range(4):
			wall.append({"suit": "honor", "rank": rank})
	return wall


func count_tile(hand: Array, target: Dictionary) -> int:
	var count := 0
	for tile in hand:
		if tile.get("suit") == target.get("suit") and tile.get("rank") == target.get("rank"):
			count += 1
	return count