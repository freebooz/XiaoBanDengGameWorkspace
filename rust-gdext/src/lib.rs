use godot::prelude::*;
use mahjong_coach_core::coach::{Counts, TILE_TYPES, analyze_all, analyze_discards, analyze_hand};

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
                let mut result = VarDictionary::new();
                result.set("ok", true);
                let mut row = analysis_row(value.shanten, value.ukeire_count, value.ukeire);
                row.set("analysisMode", "hand");
                row.set("rank", 0);
                result.set("hand", &row);
                result
            }
            Err(error) => failure(error.code()),
        }
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
        let Ok(legal) = legal
            .as_slice()
            .iter()
            .copied()
            .map(usize::try_from)
            .collect::<Result<Vec<_>, _>>()
        else {
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
        let Ok(legal) = legal
            .as_slice()
            .iter()
            .copied()
            .map(usize::try_from)
            .collect::<Result<Vec<_>, _>>()
        else {
            return failure("invalid_discard");
        };
        let candidates = match analyze_all(&hand, &visible, &totals, meld_count, &legal) {
            Ok(candidates) => candidates,
            Err(error) => return failure(error.code()),
        };
        candidate_rows(candidates)
    }
}

fn candidate_rows(candidates: Vec<mahjong_coach_core::coach::Candidate>) -> VarDictionary {
    let mut output = VarArray::new();
    for (index, candidate) in candidates.into_iter().enumerate() {
        let mut row = analysis_row(candidate.shanten, candidate.ukeire_count, candidate.ukeire);
        row.set("discard", candidate.discard as i64);
        row.set("analysisMode", "discard");
        row.set("rank", index as i64 + 1);
        output.push(&row.to_variant());
    }
    let mut result = VarDictionary::new();
    result.set("ok", true);
    result.set("candidates", &output);
    result
}

fn analysis_row(
    minimum: i8,
    count: u16,
    tiles: Vec<mahjong_coach_core::coach::EffectiveTile>,
) -> VarDictionary {
    let mut ukeire = VarArray::new();
    for waiting in tiles {
        let mut tile = VarDictionary::new();
        tile.set("tile", waiting.tile as i64);
        tile.set("count", i64::from(waiting.count));
        ukeire.push(&tile.to_variant());
    }
    let mut shanten = VarDictionary::new();
    shanten.set("minimum", i64::from(minimum));
    let mut row = VarDictionary::new();
    row.set("shanten", &shanten);
    row.set("ukeireCount", i64::from(count));
    row.set("ukeire", &ukeire);
    row.set("legalWaits", "not_checked");
    row
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
