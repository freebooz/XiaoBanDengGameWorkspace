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
	return wall


func count_tile(hand: Array, target: Dictionary) -> int:
	var count := 0
	for tile in hand:
		if tile.get("suit") == target.get("suit") and tile.get("rank") == target.get("rank"):
			count += 1
	return count


## Necessary 108-tile hand structure only. Server options still own eligibility,
## local-rule restrictions, response priority and settlement; this never grants hu.
static func has_complete_hand(hand: Array, melds: Array) -> bool:
	if melds.size() > 4 or hand.size() != 14 - 3 * melds.size(): return false
	var counts := PackedInt32Array()
	var totals := PackedInt32Array()
	counts.resize(27)
	totals.resize(27)
	var ids := {}
	for tile in hand:
		var kind := _shape_tile(tile, ids, totals)
		if kind < 0: return false
		counts[kind] += 1
	for meld in melds:
		if not meld is Dictionary or not meld.get("tiles") is Array: return false
		var kind: Variant = meld.get("kind")
		if kind not in ["peng", "ming_gang", "an_gang", "bu_gang"]: return false
		if meld.tiles.size() != (3 if kind == "peng" else 4): return false
		var first := -1
		for tile in meld.tiles:
			var tile_kind := _shape_tile(tile, ids, totals)
			if tile_kind < 0 or (first >= 0 and tile_kind != first): return false
			first = tile_kind
	if melds.is_empty():
		var pairs := 0
		for count in counts: pairs += count / 2
		if pairs == 7: return true
	for pair in range(27):
		if counts[pair] < 2: continue
		counts[pair] -= 2
		if _shape_melds(counts, 4 - melds.size()): return true
		counts[pair] += 2
	return false


static func _shape_tile(tile: Variant, ids: Dictionary, totals: PackedInt32Array) -> int:
	if not tile is Dictionary: return -1
	var id: Variant = tile.get("id")
	var rank: Variant = tile.get("rank")
	if not _shape_integer(id) or id <= 0 or ids.has(int(id)): return -1
	if not _shape_integer(rank) or rank < 1 or rank > 9: return -1
	var suit := ["wan", "tong", "tiao"].find(tile.get("suit"))
	if suit < 0: return -1
	var kind := suit * 9 + int(rank) - 1
	ids[int(id)] = true
	totals[kind] += 1
	return kind if totals[kind] <= 4 else -1


static func _shape_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value))


static func _shape_melds(counts: PackedInt32Array, remaining: int) -> bool:
	var first := -1
	for kind in range(27):
		if counts[kind] > 0:
			first = kind
			break
	if remaining == 0: return first == -1
	if first == -1: return false
	if counts[first] >= 3:
		counts[first] -= 3
		var complete := _shape_melds(counts, remaining - 1)
		counts[first] += 3
		if complete: return true
	if first % 9 <= 6 and counts[first + 1] > 0 and counts[first + 2] > 0:
		for kind in range(first, first + 3): counts[kind] -= 1
		var complete := _shape_melds(counts, remaining - 1)
		for kind in range(first, first + 3): counts[kind] += 1
		if complete: return true
	return false
