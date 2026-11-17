use godot::{builtin::AnyArray, prelude::*};
use mahjong_coach_core::coach::{
    CoachContext, Counts, EffectiveTile, Opponent, TILE_TYPES, analyze_all, analyze_discards,
    analyze_discards_with_context, analyze_hand, analyze_hand_with_context,
};

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
struct MahjongCoachBridge {
    base: Base<RefCounted>,
}

#[godot_api]
impl MahjongCoachBridge {
    #[func]
    fn analyze_hand(
        &self,
        hand: PackedInt32Array,
        visible: PackedInt32Array,
        totals: PackedInt32Array,
        meld_count: i32,
        own_meld_tiles: PackedInt32Array,
    ) -> VarDictionary {
        let (Some(hand), Some(visible), Some(totals), Some(own_meld_tiles)) = (
            to_counts(&hand),
            to_counts(&visible),
            to_counts(&totals),
            to_counts(&own_meld_tiles),
        ) else {
            return failure("invalid_counts");
        };
        let Ok(meld_count) = usize::try_from(meld_count) else {
            return failure("invalid_hand_size");
        };
        match analyze_hand(&hand, &visible, &totals, meld_count, &own_meld_tiles) {
            Ok(value) => {
                let row = analysis_row(value.shanten, value.ukeire_count, value.ukeire);
                hand_result(row)
            }
            Err(error) => failure(error.code()),
        }
    }

    #[func]
    fn analyze_hand_with_context(
        &self,
        hand: PackedInt32Array,
        visible: PackedInt32Array,
        totals: PackedInt32Array,
        meld_count: i32,
        own_meld_tiles: PackedInt32Array,
        context: VarDictionary,
    ) -> VarDictionary {
        let (Some(hand), Some(visible), Some(totals), Some(own_meld_tiles)) = (
            to_counts(&hand),
            to_counts(&visible),
            to_counts(&totals),
            to_counts(&own_meld_tiles),
        ) else {
            return failure("invalid_counts");
        };
        let Ok(meld_count) = usize::try_from(meld_count) else {
            return failure("invalid_hand_size");
        };
        let context = read_context(&context);
        match analyze_hand_with_context(
            &hand,
            &visible,
            &totals,
            meld_count,
            &own_meld_tiles,
            &context,
        ) {
            Ok(value) => {
                let mut row = analysis_row(
                    value.hand.shanten,
                    value.hand.ukeire_count,
                    value.hand.ukeire,
                );
                set_claim_supply(&mut row, value.claim_ukeire, context.own_missing_suit);
                hand_result(row)
            }
            Err(error) => failure(error.code()),
        }
    }

    #[func]
    fn analyze_discards_with_context(
        &self,
        hand: PackedInt32Array,
        visible: PackedInt32Array,
        totals: PackedInt32Array,
        meld_count: i32,
        own_meld_tiles: PackedInt32Array,
        legal: PackedInt32Array,
        context: VarDictionary,
    ) -> VarDictionary {
        let (Some(hand), Some(visible), Some(totals), Some(own_meld_tiles)) = (
            to_counts(&hand),
            to_counts(&visible),
            to_counts(&totals),
            to_counts(&own_meld_tiles),
        ) else {
            return failure("invalid_counts");
        };
        let Ok(meld_count) = usize::try_from(meld_count) else {
            return failure("invalid_hand_size");
        };
        let Some(legal) = to_legal(&legal) else {
            return failure("invalid_discard");
        };
        let context = read_context(&context);
        let ranked = match analyze_discards_with_context(
            &hand,
            &visible,
            &totals,
            meld_count,
            &own_meld_tiles,
            &legal,
            &context,
        ) {
            Ok(ranked) => ranked,
            Err(error) => return failure(error.code()),
        };
        let mut output = VarArray::new();
        for (index, item) in ranked.into_iter().enumerate() {
            let mut row = discard_row(item.candidate, index);
            set_claim_supply(&mut row, item.claim_ukeire, context.own_missing_suit);
            row.set("q", i64::from(item.q));
            row.set("k", i64::from(item.k));
            row.set("lookAheadEvaluated", item.look_ahead_evaluated);
            row.set("elevatedRiskCount", i64::from(item.elevated_risk));
            row.set("otherRiskCount", i64::from(item.other_risk));
            row.set("giftKongRiskCount", i64::from(item.gift_kong_risk));
            row.set("chickenExposure", i64::from(item.chicken_exposure));
            let mut reasons = PackedStringArray::new();
            for risk in item.risk {
                reasons.push(risk.code());
            }
            row.set("riskReasons", &reasons);
            row.set("rankingReason", item.reason);
            output.push(&row.to_variant());
        }
        discard_result(output)
    }

    #[func]
    fn analyze_discards(
        &self,
        hand: PackedInt32Array,
        visible: PackedInt32Array,
        totals: PackedInt32Array,
        meld_count: i32,
        own_meld_tiles: PackedInt32Array,
        legal: PackedInt32Array,
    ) -> VarDictionary {
        let (Some(hand), Some(visible), Some(totals), Some(own_meld_tiles)) = (
            to_counts(&hand),
            to_counts(&visible),
            to_counts(&totals),
            to_counts(&own_meld_tiles),
        ) else {
            return failure("invalid_counts");
        };
        let Ok(meld_count) = usize::try_from(meld_count) else {
            return failure("invalid_hand_size");
        };
        let Some(legal) = to_legal(&legal) else {
            return failure("invalid_discard");
        };
        match analyze_discards(
            &hand,
            &visible,
            &totals,
            meld_count,
            &own_meld_tiles,
            &legal,
        ) {
            Ok(candidates) => candidate_rows(candidates),
            Err(error) => failure(error.code()),
        }
    }

    #[func]
    fn analyze_all(
        &self,
        hand: PackedInt32Array,
        visible: PackedInt32Array,
        totals: PackedInt32Array,
        meld_count: i32,
        legal: PackedInt32Array,
    ) -> VarDictionary {
        let (Some(hand), Some(visible), Some(totals)) =
            (to_counts(&hand), to_counts(&visible), to_counts(&totals))
        else {
            return failure("invalid_counts");
        };
        let Ok(meld_count) = usize::try_from(meld_count) else {
            return failure("invalid_hand_size");
        };
        let Some(legal) = to_legal(&legal) else {
            return failure("invalid_discard");
        };
        let candidates = match analyze_all(&hand, &visible, &totals, meld_count, &legal) {
            Ok(candidates) => candidates,
            Err(error) => return failure(error.code()),
        };
        candidate_rows(candidates)
    }
}

fn read_context(context: &VarDictionary) -> CoachContext {
    let mut opponents = [None; 3];
    if let Some(seats) = context
        .get("opponents")
        .and_then(|value| value.try_to::<AnyArray>().ok())
    {
        if seats.len() == opponents.len() {
            for (profile, value) in opponents.iter_mut().zip(seats.iter_shared()) {
                *profile = value
                    .try_to::<VarDictionary>()
                    .ok()
                    .and_then(|seat| read_opponent(&seat));
            }
        }
    }
    let chicken_values = context
        .get("chicken_values")
        .and_then(|value| value.try_to::<PackedInt32Array>().ok())
        .and_then(|array| {
            let raw: &[i32; TILE_TYPES] = array.as_slice().try_into().ok()?;
            raw.iter()
                .all(|&value| value >= 0)
                .then(|| raw.map(|value| value as u32))
        });
    CoachContext {
        own_missing_suit: read_suit(context, "own_missing_suit").flatten(),
        requires_kong_to_claim: read_bool(context, "requires_kong_to_claim"),
        own_has_kong: read_bool(context, "own_has_kong"),
        remaining: read_int(context, "remaining")
            .and_then(|remaining| usize::try_from(remaining).ok()),
        opponents,
        chicken_values,
    }
}

fn read_opponent(seat: &VarDictionary) -> Option<Opponent> {
    Some(Opponent {
        meld_count: usize::try_from(read_int(seat, "meld_count")?).ok()?,
        completed_kong: read_bool(seat, "completed_kong")?,
        missing_suit: read_suit(seat, "missing_suit")?,
        reported_ready: read_bool(seat, "reported_ready")?,
    })
}

fn read_bool(dict: &VarDictionary, key: &str) -> Option<bool> {
    dict.get(key)?.try_to::<bool>().ok()
}

fn read_int(dict: &VarDictionary, key: &str) -> Option<i64> {
    dict.get(key)?.try_to::<i64>().ok()
}

fn read_suit(dict: &VarDictionary, key: &str) -> Option<Option<usize>> {
    match read_int(dict, key)? {
        -1 => Some(None),
        suit @ 0..=2 => Some(Some(suit as usize)),
        _ => None,
    }
}

fn set_claim_supply(
    row: &mut VarDictionary,
    claim: Option<Vec<EffectiveTile>>,
    missing_suit: Option<usize>,
) {
    let count = claim.as_ref().map_or(-1, |tiles| {
        tiles.iter().map(|tile| i64::from(tile.count)).sum()
    });
    row.set("claimUkeireCount", count);
    row.set("claimUkeire", &wait_rows(claim.unwrap_or_default()));
    row.set(
        "ownMissingSuit",
        missing_suit.map_or(-1, |suit| suit as i64),
    );
}

fn hand_result(mut row: VarDictionary) -> VarDictionary {
    row.set("analysisMode", "hand");
    row.set("rank", 0);
    let mut result = VarDictionary::new();
    result.set("ok", true);
    result.set("hand", &row);
    result
}

fn candidate_rows(candidates: Vec<mahjong_coach_core::coach::Candidate>) -> VarDictionary {
    let mut output = VarArray::new();
    for (index, candidate) in candidates.into_iter().enumerate() {
        output.push(&discard_row(candidate, index).to_variant());
    }
    discard_result(output)
}

fn discard_row(candidate: mahjong_coach_core::coach::Candidate, index: usize) -> VarDictionary {
    let mut row = analysis_row(candidate.shanten, candidate.ukeire_count, candidate.ukeire);
    row.set("discard", candidate.discard as i64);
    row.set("analysisMode", "discard");
    row.set("rank", index as i64 + 1);
    row
}

fn discard_result(output: VarArray) -> VarDictionary {
    let mut result = VarDictionary::new();
    result.set("ok", true);
    result.set("candidates", &output);
    result
}

fn analysis_row(minimum: i8, count: u16, tiles: Vec<EffectiveTile>) -> VarDictionary {
    let mut shanten = VarDictionary::new();
    shanten.set("minimum", i64::from(minimum));
    let mut row = VarDictionary::new();
    row.set("shanten", &shanten);
    row.set("ukeireCount", i64::from(count));
    row.set("ukeire", &wait_rows(tiles));
    row.set("legalWaits", "not_checked");
    row
}

fn wait_rows(tiles: Vec<EffectiveTile>) -> VarArray {
    let mut ukeire = VarArray::new();
    for waiting in tiles {
        let mut tile = VarDictionary::new();
        tile.set("tile", waiting.tile as i64);
        tile.set("count", i64::from(waiting.count));
        ukeire.push(&tile.to_variant());
    }
    ukeire
}

fn to_legal(values: &PackedInt32Array) -> Option<Vec<usize>> {
    values
        .as_slice()
        .iter()
        .copied()
        .map(|tile| usize::try_from(tile).ok())
        .collect()
}

fn to_counts(values: &PackedInt32Array) -> Option<Counts> {
    let source = values.as_slice();
    if source.len() != TILE_TYPES {
        return None;
    }
    let mut counts = [0; TILE_TYPES];
    for (result, value) in counts.iter_mut().zip(source) {
        *result = u8::try_from(*value).ok()?;
    }
    Some(counts)
}

fn failure(error: &str) -> VarDictionary {
    let mut result = VarDictionary::new();
    result.set("ok", false);
    result.set("error", error);
    result.set("candidates", &VarArray::new());
    result
}

struct MahjongCoachExtension;

#[gdextension]
unsafe impl ExtensionLibrary for MahjongCoachExtension {}
