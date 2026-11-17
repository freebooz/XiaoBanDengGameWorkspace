extends RefCounted
## Builds the Rust input strictly from the recipient's hand and public tile instances.

const SUITS := ["wan", "tong", "tiao"]
const DINGQUE_RULE := "zunyi_dingque"
const RULE_VERSIONS := {"guiyang": ["2.0.0", "3.0.0"], "basic_108": ["1.0.0"], DINGQUE_RULE: ["1.0.0"]}


static func analyze(state: Dictionary, bridge: Object) -> Dictionary:
	if not is_instance_valid(bridge) or not bridge.has_method("analyze_discards") or not bridge.has_method("analyze_hand") or not state.get("hand") is Array or not state.get("discards") is Array:
		return {}
	if state.get("phase", "turn") not in ["turn", "reaction"]: return {}
	var identity := _rule_identity(state)
	var rule_id: String = identity[0]
	var version: String = identity[1]
	# Local practice and legacy fixtures without a descriptor use the same wall.
	if not rule_id.is_empty() and (not RULE_VERSIONS.has(rule_id) or (not version.is_empty() and version not in RULE_VERSIONS[rule_id])):
		return {}
	var seat_value: Variant = state.get("your_seat")
	if not _whole(seat_value) or seat_value < 0 or seat_value >= 4: return {}
	var own_seat := int(seat_value)
	var melds: Variant = state.get("melds")
	if not melds is Array or melds.size() != 4: return {}
	var missing_suits := PackedInt32Array([-1, -1, -1, -1])
	if rule_id == DINGQUE_RULE:
		if version not in RULE_VERSIONS[DINGQUE_RULE]: return {}
		missing_suits = _published_missing_suits(state.get("missing_suits"))
		if missing_suits.is_empty(): return {}
	var totals := PackedInt32Array()
	totals.resize(34)
	for kind in range(27):
		totals[kind] = 4
	var counts := PackedInt32Array()
	var visible := PackedInt32Array()
	var own_meld_tiles := PackedInt32Array()
	counts.resize(34)
	visible.resize(34)
	own_meld_tiles.resize(34)
	var known := {}
	var claimed_ids := {}
	var own_tiles := {}
	var completed_kongs := [false, false, false, false]
	for tile in state.hand:
		if not _record(tile, "hand", known, counts, visible, totals, false):
			return {}
		own_tiles[int(tile.id)] = _kind(tile)
	for seat in range(4):
		if not melds[seat] is Array: return {}
		for meld in melds[seat]:
			if not meld is Dictionary or not meld.get("tiles") is Array: return {}
			var meld_kind := str(meld.get("kind", ""))
			if meld_kind not in ["peng","ming_gang","an_gang","bu_gang"]: return {}
			if meld.tiles.size() != (3 if meld_kind == "peng" else 4): return {}
			if meld_kind != "peng": completed_kongs[seat] = true
			if seat != own_seat and meld_kind == "an_gang":
				for tile in meld.tiles:
					if not _hidden_tile(tile): return {}
				continue
			if not meld.tiles[0] is Dictionary: return {}
			var kind := _kind(meld.tiles[0])
			for tile in meld.tiles:
				if not tile is Dictionary or _kind(tile) != kind: return {}
				if not _record(tile, "meld", known, counts, visible, totals, false): return {}
				if seat == own_seat: own_meld_tiles[kind] += 1
	for discard in state.discards:
		if not discard is Dictionary or not discard.get("tile") is Dictionary: return {}
		var tile: Dictionary = discard.tile
		var claimed: Variant = discard.get("claimed", false)
		if not claimed is bool: return {}
		if claimed:
			if not _whole(tile.get("id")) or claimed_ids.has(int(tile.id)): return {}
			claimed_ids[int(tile.id)] = true
		if not _record(tile, "river", known, counts, visible, totals, claimed):
			return {}
	# last_discard and ji_events mirror river/meld entries rather than represent more tiles.
	var indicator: Variant = state.get("flipped_ji", {})
	if not _hidden_tile(indicator):
		if not _record(indicator, "indicator", known, counts, visible, totals, false): return {}
	var context := _context(state, rule_id, version, own_seat, melds, completed_kongs, missing_suits, indicator)
	# Between turns the concealed hand is 13-equivalent: analyze it as a whole.
	# Every label carries the same baseline, never a fictitious 12-tile discard.
	var meld_count: int = melds[own_seat].size()
	if state.hand.size() == 13 - 3 * meld_count:
		var baseline: Variant
		if bridge.has_method("analyze_hand_with_context"):
			baseline = bridge.call("analyze_hand_with_context", counts, visible, totals, meld_count, own_meld_tiles, context)
		elif rule_id != DINGQUE_RULE:
			baseline = bridge.call("analyze_hand", counts, visible, totals, meld_count, own_meld_tiles)
		if not baseline is Dictionary or baseline.get("ok") != true or not baseline.get("hand") is Dictionary: return {}
		var current := {}
		for id in own_tiles: current[id] = baseline.hand
		return current
	var eligible := _legal_tiles(state, own_tiles)
	if eligible.is_empty(): return {}
	var legal := PackedInt32Array()
	for kind in eligible.values():
		if not legal.has(kind): legal.append(kind)
	var response: Variant
	if bridge.has_method("analyze_discards_with_context"):
		response = bridge.call("analyze_discards_with_context", counts, visible, totals, meld_count, own_meld_tiles, legal, context)
	elif rule_id != DINGQUE_RULE:
		response = bridge.call("analyze_discards", counts, visible, totals, meld_count, own_meld_tiles, legal)
	if not response is Dictionary or not response.get("ok", false) or not response.get("candidates") is Array:
		return {}
	var by_kind := {}
	for candidate in response.candidates:
		if candidate is Dictionary and candidate.get("discard") is int:
			by_kind[candidate.discard] = candidate
	var result := {}
	for id in eligible:
		if by_kind.has(eligible[id]): result[id] = by_kind[eligible[id]]
	return result


static func _rule_identity(state: Dictionary) -> Array:
	var rule_id := str(state.get("rule_set_id", ""))
	var version := str(state.get("rule_version", ""))
	var rule: Variant = state.get("rule", {})
	if rule is Dictionary:
		rule_id = str(rule.get("rule_set_id", "")) if rule_id.is_empty() else rule_id
		version = str(rule.get("rule_version", "")) if version.is_empty() else version
	return [rule_id, version]


static func _published_missing_suits(value: Variant) -> PackedInt32Array:
	var suits := PackedInt32Array()
	if not value is Array or value.size() != 4: return suits
	for suit in value:
		var kind := SUITS.find(suit)
		if kind < 0: return PackedInt32Array()
		suits.append(kind)
	return suits


static func _context(state: Dictionary, rule_id: String, version: String, own_seat: int, melds: Array, completed_kongs: Array, missing_suits: PackedInt32Array, indicator: Dictionary) -> Dictionary:
	var remaining: Variant = state.get("remaining")
	var context := {
		"own_missing_suit": missing_suits[own_seat],
		"own_has_kong": completed_kongs[own_seat],
		"remaining": int(remaining) if _whole(remaining) and remaining >= 0 and remaining <= 108 else -1,
	}
	var opponents: Array = []
	var reported: Variant = state.get("reported_ready")
	for seat in range(4):
		if seat == own_seat: continue
		var opponent := {"meld_count":melds[seat].size(), "completed_kong":completed_kongs[seat], "missing_suit":missing_suits[seat]}
		if reported is Array and reported.size() == 4 and reported[seat] is bool:
			opponent["reported_ready"] = reported[seat]
		elif not state.has("reported_ready") and version in RULE_VERSIONS.get(rule_id, []):
			# None of these preset versions requires or publishes a ready declaration.
			opponent["reported_ready"] = false
		opponents.append(opponent)
	context["opponents"] = opponents
	var descriptor: Variant = state.get("rule")
	if not descriptor is Dictionary or descriptor.get("rule_set_id", rule_id) != rule_id or descriptor.get("rule_version", version) != version:
		return context
	if version not in RULE_VERSIONS.get(rule_id, []): return context
	var options: Variant = descriptor.get("options")
	var options_version := "2.0.0" if rule_id == DINGQUE_RULE else "1.0.0"
	if not options is Dictionary or options.get("version") != options_version: return context
	var kong_gate: Variant = descriptor.get("requires_kong_to_claim") if rule_id == DINGQUE_RULE else options.get("requires_kong_to_claim")
	if kong_gate is bool:
		context["requires_kong_to_claim"] = kong_gate
	if options.get("chicken") == true:
		var chicken_values := PackedInt32Array()
		chicken_values.resize(34)
		chicken_values[18] = 1 # 1 tiao.
		if options.get("black_eight") == true: chicken_values[16] = 2
		if not _hidden_tile(indicator):
			var suit := SUITS.find(indicator.suit)
			var flipped_kind := suit * 9 + int(indicator.rank) % 9
			chicken_values[flipped_kind] = maxi(1, chicken_values[flipped_kind])
		context["chicken_values"] = chicken_values
	return context


static func _legal_tiles(state: Dictionary, own_tiles: Dictionary) -> Dictionary:
	if state.get("phase", "turn") != "turn" or state.get("saving", false): return {}
	if state.has("turn") and state.get("turn") != state.get("your_seat"): return {}
	# The legacy counts-only fixture omits options. The authoritative snapshot always includes them.
	if not state.has("options"): return {} if state.has("phase") else own_tiles
	if not state.options is Array: return {}
	var eligible := {}
	var any_tile := false
	for option in state.options:
		if not option is Dictionary: return {}
		if option.get("type", "") != "play": continue
		var id: Variant = option.get("tile_id", 0)
		if not _whole(id) or id < 0: return {}
		if id == 0:
			any_tile = true
			continue
		var key := int(id)
		if not own_tiles.has(key): return {}
		eligible[key] = own_tiles[key]
	return own_tiles if any_tile else eligible


static func _hidden_tile(tile: Variant) -> bool:
	return tile is Dictionary and tile.get("id", 0) == 0 and tile.get("suit", "") == "" and tile.get("rank", 0) == 0


static func _kind(tile: Dictionary) -> int:
	var suit := SUITS.find(tile.get("suit"))
	var rank: Variant = tile.get("rank")
	if suit < 0 or not _whole(rank) or rank < 1 or rank > 9: return -1
	return suit * 9 + int(rank) - 1


static func _whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value))


static func _record(tile: Variant, source: String, known: Dictionary, counts: PackedInt32Array, visible: PackedInt32Array, totals: PackedInt32Array, claimed: bool) -> bool:
	if not tile is Dictionary: return false
	var kind := _kind(tile)
	var id: Variant = tile.get("id")
	if kind < 0 or not _whole(id) or id <= 0: return false
	var key := int(id)
	if known.has(key):
		var existing: Array = known[key]
		return claimed and existing[0] == kind and existing[1] == "meld"
	if claimed: return false
	known[key] = [kind,source]
	if source == "hand": counts[kind] += 1
	else: visible[kind] += 1
	return counts[kind] + visible[kind] <= totals[kind]
