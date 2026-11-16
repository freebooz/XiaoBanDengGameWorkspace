extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ClassDB.can_instantiate("MahjongCoachBridge"):
		push_error("Native MahjongCoachBridge is not registered")
		quit(1)
		return
	var bridge: RefCounted = ClassDB.instantiate("MahjongCoachBridge")
	var hand := _empty_counts()
	for tile in [0, 1, 2, 3, 4, 5, 8, 15, 16, 17, 19, 19, 22, 23]:
		hand[tile] += 1
	var visible := _empty_counts()
	var totals := _empty_counts()
	for tile in range(27):
		totals[tile] = 4
	var legal := PackedInt32Array([0, 1, 2, 3, 4, 5, 8, 15, 16, 17, 19, 22, 23])
	var base: Dictionary = bridge.analyze_all(hand, visible, totals, 0, legal)
	if base.get("ok") != true or base.candidates.size() != legal.size() or not _expected(base.candidates[0], 8, 4, 4):
		push_error("Bridge did not return all candidates or expected 0·8 wait")
		quit(1)
		return
	visible[21] = 3
	visible[24] = 2
	var reduced: Dictionary = bridge.analyze_all(hand, visible, totals, 0, legal)
	if reduced.get("ok") != true or not _expected(reduced.candidates[0], 3, 1, 2):
		push_error("Bridge did not reduce the visible waits to 0·3")
		quit(1)
		return
	var own := _empty_counts()
	hand[8] -= 1
	visible[8] = 1
	var current: Dictionary = bridge.analyze_hand(hand, visible, totals, 0, own)
	if current.get("ok") != true or current.hand.analysisMode != "hand" or current.hand.rank != 0 or current.hand.ukeireCount != 3 or current.hand.has("discard"):
		push_error("Whole-hand native result must have real values without a discard recommendation")
		quit(1)
		return
	hand[8] += 1
	visible[8] = 0
	var exact: Dictionary = bridge.analyze_discards(hand, visible, totals, 0, own, legal)
	if exact != reduced:
		push_error("New own-meld-aware API must agree with legacy API for a closed hand")
		quit(1)
		return
	var before := Time.get_ticks_usec()
	for attempt in range(100):
		bridge.analyze_discards(hand, visible, totals, 0, own, legal)
	print("COACH_DESKTOP_BENCH full_candidates_average_us=", (Time.get_ticks_usec()-before)/100)
	visible[21] = 5
	var invalid: Dictionary = bridge.analyze_all(hand, visible, totals, 0, legal)
	if invalid.get("ok") != false or invalid.error != "known_exceeds_total" or not invalid.candidates.is_empty():
		push_error("Bridge accepted impossible visible counts")
		quit(1)
		return
	print("MAHJONG_COACH_BRIDGE_OK all_legal=true waits=8,3 checked=false invalid_rejected=true")
	quit()


func _empty_counts() -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize(34)
	return result


func _expected(row: Dictionary, count: int, first: int, second: int) -> bool:
	return (row.discard == 8 and row.rank == 1 and row.shanten.minimum == 0 and row.ukeireCount == count
		and row.legalWaits == "not_checked" and row.ukeire == [{"tile": 21, "count": first}, {"tile": 24, "count": second}])
