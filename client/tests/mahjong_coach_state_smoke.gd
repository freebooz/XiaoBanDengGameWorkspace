extends SceneTree

const COACH := preload("res://modules/games/mahjong/guiyang/mahjong_coach_state.gd")


func _initialize() -> void:
	call_deferred("_run")


func _tile(id: int, suit: String, rank: int) -> Dictionary:
	return {"id": id, "suit": suit, "rank": rank}


func _run() -> void:
	if not ClassDB.class_exists("MahjongCoachBridge"):
		push_error("Missing native coach")
		quit(1)
		return
	var bridge: Object = ClassDB.instantiate("MahjongCoachBridge")
	var hand: Array[Dictionary] = []
	for rank in [1,2,3,4,5,6,9]:
		hand.append(_tile(hand.size()+1,"wan",rank))
	for rank in [7,8,9]:
		hand.append(_tile(hand.size()+1,"tong",rank))
	for rank in [2,2,5,6]:
		hand.append(_tile(hand.size()+1,"tiao",rank))
	var state := {"hand":hand,"your_seat":0,"melds":[[],[],[],[]],"discards":[]}
	var base := COACH.analyze(state,bridge)
	if base.size() != 14 or base[7].shanten.minimum != 0 or base[7].ukeireCount != 8 or base[11] != base[12]:
		push_error("Invalid 0·8 or same-kind result: " + str(base.get(7)))
		quit(1)
		return
	var first := _tile(21,"tiao",4)
	state.melds[1].append({"kind":"peng","tiles":[first,_tile(22,"tiao",4),_tile(23,"tiao",4)]})
	state.discards.append({"seat":2,"claimed":true,"tile":first})
	state.discards.append({"seat":1,"claimed":false,"tile":_tile(24,"tiao",7)})
	state.discards.append({"seat":2,"claimed":false,"tile":_tile(25,"tiao",7)})
	var hidden := _tile(0,"",0)
	state.melds[2].append({"kind":"an_gang","tiles":[hidden,hidden,hidden,hidden]})
	state["last_discard"] = first
	state["ji_events"] = [{"tile":first}]
	var exposed := COACH.analyze(state,bridge)
	if exposed.get(7,{}).get("ukeireCount") != 3:
		push_error("Claim or concealed meld miscounted")
		quit(1)
		return
	# The player's discarded 9m remains public. Other players' plays update the
	# same 13-tile baseline, without inventing a discard or reading hidden hands.
	var waiting := state.duplicate(true)
	var own_discard: Dictionary = waiting.hand.pop_at(6)
	waiting.discards.append({"seat":0,"claimed":false,"tile":own_discard})
	waiting["options"] = []
	var whole := COACH.analyze(waiting, bridge)
	if whole.size() != 13 or whole[1].analysisMode != "hand" or whole[1].rank != 0 or whole[1].shanten.minimum != 0 or whole[1].ukeireCount != 3:
		push_error("13-tile hand must retain real whole-hand analysis between turns")
		quit(1)
		return
	waiting.discards.append({"seat":3,"claimed":false,"tile":_tile(28,"tiao",7)})
	if COACH.analyze(waiting, bridge)[1].ukeireCount != 2:
		push_error("Other player's public discard must reduce the whole-hand unseen count")
		quit(1)
		return
	if not _check_snapshot_guards(state, bridge):
		quit(1)
		return
	state.discards.append({"seat":1,"claimed":false,"tile":_tile(26,"tiao",4)})
	state.discards.append({"seat":2,"claimed":false,"tile":_tile(27,"tiao",4)})
	if not COACH.analyze(state,bridge).is_empty():
		push_error("An impossible fifth copy produced a normal efficiency label")
		quit(1)
		return
	print("MAHJONG_COACH_STATE_SMOKE_OK candidates=14 waits=8,3 duplicate_meld=true concealed=true overcount_rejected=true public_indicator=true rules=true legal_ids=true")
	quit()


func _check_snapshot_guards(state: Dictionary, bridge: Object) -> bool:
	var snapshot := state.duplicate(true)
	snapshot["rule_set_id"] = "basic_108"
	snapshot["rule_version"] = "1.0.0"
	snapshot["options"] = [{"type":"play", "tile_id":11}]
	var restricted := COACH.analyze(snapshot, bridge)
	if restricted.keys() != [11]:
		push_error("Only the permitted physical instance of the duplicate tile should be analyzed")
		return false
	snapshot["options"] = [{"type":"hu"}]
	if not COACH.analyze(snapshot, bridge).is_empty():
		push_error("A hand without legal discard options produced a recommendation")
		return false
	snapshot["options"] = [{"type":"play"}]
	snapshot["flipped_ji"] = _tile(26,"tiao",4)
	if COACH.analyze(snapshot, bridge).get(7,{}).get("ukeireCount") != 2:
		push_error("Public indicator should consume one extra visible four tiao")
		return false
	snapshot["rule_version"] = "99.0.0"
	if not COACH.analyze(snapshot, bridge).is_empty():
		push_error("Unknown rule version should hide the analysis")
		return false
	snapshot["rule_version"] = "1.0.0"
	snapshot["rule_set_id"] = "unknown"
	if not COACH.analyze(snapshot, bridge).is_empty():
		push_error("Unknown rule should hide the analysis")
		return false
	snapshot["rule_set_id"] = "basic_108"
	snapshot.melds[2][0].tiles[2] = _tile(27,"wan",1)
	if not COACH.analyze(snapshot, bridge).is_empty():
		push_error("A partially exposed concealed kong unexpectedly passed validation")
		return false
	snapshot.melds[2][0].tiles[2] = _tile(0,"",0)
	snapshot.melds[1][0].tiles[2] = _tile(23,"tiao",3)
	if not COACH.analyze(snapshot, bridge).is_empty():
		push_error("A mixed-kind peng unexpectedly passed validation")
		return false
	return true
