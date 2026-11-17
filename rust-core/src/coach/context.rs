use std::{cmp::Reverse, collections::HashMap};

use super::{
    AnalysisError, Candidate, Counts, EffectiveTile, HandAnalysis, PatternCache, TILE_TYPES,
    discard_allowlist, effective_tiles, evaluate, evaluate_discards, supplies, validate_hand_size,
};

#[derive(Default)]
pub struct CoachContext {
    pub own_missing_suit: Option<usize>,
    pub requires_kong_to_claim: Option<bool>,
    pub own_has_kong: Option<bool>,
    pub remaining: Option<usize>,
    pub opponents: [Option<Opponent>; 3],
    pub chicken_values: Option<[u32; TILE_TYPES]>,
}

#[derive(Clone, Copy, Default)]
pub struct Opponent {
    pub meld_count: usize,
    pub completed_kong: bool,
    pub missing_suit: Option<usize>,
    pub reported_ready: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Risk {
    Unknown,
    RuleBlocked,
    SupplyBlocked,
    Elevated,
    Possible,
}

impl Risk {
    pub fn code(self) -> &'static str {
        match self {
            Self::Unknown => "unknown",
            Self::RuleBlocked => "rule_blocked",
            Self::SupplyBlocked => "supply_blocked",
            Self::Elevated => "elevated",
            Self::Possible => "possible",
        }
    }
}

pub struct ContextCandidate {
    pub candidate: Candidate,
    pub q: u32,
    pub k: u32,
    pub look_ahead_evaluated: bool,
    pub claim_ukeire: Option<Vec<EffectiveTile>>,
    pub elevated_risk: u8,
    pub other_risk: u8,
    pub gift_kong_risk: u8,
    pub chicken_exposure: u32,
    pub risk: [Risk; 3],
    pub reason: &'static str,
}

pub struct ContextHand {
    pub hand: HandAnalysis,
    pub claim_ukeire: Option<Vec<EffectiveTile>>,
}

pub fn analyze_hand_with_context(
    hand: &Counts,
    visible: &Counts,
    totals: &Counts,
    meld_count: usize,
    own_meld_tiles: &Counts,
    context: &CoachContext,
) -> Result<ContextHand, AnalysisError> {
    validate_hand_size(hand, meld_count, 13)?;
    let (unseen, shape_totals) = supplies(hand, visible, totals, own_meld_tiles)?;
    let shape_totals = constrain_shape(shape_totals, own_meld_tiles, context)?;
    let hand = evaluate(
        hand,
        &unseen,
        &shape_totals,
        meld_count,
        &mut PatternCache::default(),
    );
    let claim_ukeire = claim_supply(hand.shanten, &hand.ukeire, context);
    Ok(ContextHand { hand, claim_ukeire })
}

pub fn analyze_discards_with_context(
    hand: &Counts,
    visible: &Counts,
    totals: &Counts,
    meld_count: usize,
    own_meld_tiles: &Counts,
    legal: &[usize],
    context: &CoachContext,
) -> Result<Vec<ContextCandidate>, AnalysisError> {
    validate_hand_size(hand, meld_count, 14)?;
    let (unseen, shape_totals) = supplies(hand, visible, totals, own_meld_tiles)?;
    let shape_totals = constrain_shape(shape_totals, own_meld_tiles, context)?;
    let eligible = discard_allowlist(hand, legal)?;
    let mut cache = PatternCache::default();
    let mut candidates = evaluate_discards(
        hand,
        &unseen,
        &shape_totals,
        meld_count,
        eligible,
        &mut cache,
    );
    candidates.sort_by_key(efficiency);
    let mut look_ahead = LookAhead {
        unseen: &unseen,
        totals: &shape_totals,
        meld_count,
        missing_suit: context.own_missing_suit,
        cache: &mut cache,
        next_supply: HashMap::new(),
    };

    let mut ranked = Vec::with_capacity(candidates.len());
    let mut candidates = candidates.into_iter().peekable();
    let mut previous = None;
    while let Some(candidate) = candidates.next() {
        let this = efficiency(&candidate);
        let tied = previous == Some(this)
            || candidates
                .peek()
                .is_some_and(|next| efficiency(next) == this);
        previous = Some(this);

        let mut row = risk_row(candidate, &unseen, context);
        if tied && context.remaining != Some(0) {
            let mut after = *hand;
            after[row.candidate.discard] -= 1;
            (row.q, row.k) = look_ahead.evaluate(&after, &row.candidate);
            row.look_ahead_evaluated = true;
        }
        ranked.push(row);
    }

    ranked.sort_by_key(|row| (ranking_values(row), row.candidate.discard));
    for index in 0..ranked.len().saturating_sub(1) {
        let leading = ranking_values(&ranked[index]);
        let following = ranking_values(&ranked[index + 1]);
        if let Some(position) = leading.iter().zip(following).position(|(a, b)| *a != b) {
            ranked[index].reason = match position {
                0 | 1 => "efficiency",
                2 => "elevated_risk",
                3 if ranked[index].candidate.shanten == 0 => "claim_supply",
                3 => "q",
                4 => "k",
                5 => "other_risk",
                6 => "gift_kong",
                _ => "chicken_exposure",
            };
        }
    }
    Ok(ranked)
}

fn efficiency(candidate: &Candidate) -> (i8, Reverse<u16>) {
    (candidate.shanten, Reverse(candidate.ukeire_count))
}

fn constrain_shape(
    mut totals: Counts,
    own_meld_tiles: &Counts,
    context: &CoachContext,
) -> Result<Counts, AnalysisError> {
    if let Some(suit) = context.own_missing_suit {
        if suit >= 3 {
            return Err(AnalysisError::InvalidContext);
        }
        let missing = suit * 9..suit * 9 + 9;
        if own_meld_tiles[missing.clone()]
            .iter()
            .any(|&count| count != 0)
        {
            return Err(AnalysisError::InvalidContext);
        }
        totals[missing].fill(0);
    }
    Ok(totals)
}

fn claim_supply(
    shanten: i8,
    ukeire: &[EffectiveTile],
    context: &CoachContext,
) -> Option<Vec<EffectiveTile>> {
    if shanten != 0 || ukeire.is_empty() {
        return Some(Vec::new());
    }
    let allowed = !context.requires_kong_to_claim? || context.own_has_kong?;
    Some(if allowed { ukeire.to_vec() } else { Vec::new() })
}

fn ranking_values(row: &ContextCandidate) -> [i64; 8] {
    let quality = if row.candidate.shanten == 0 {
        row.claim_ukeire.as_ref().map_or(0, |tiles| {
            tiles.iter().map(|tile| i64::from(tile.count)).sum()
        })
    } else {
        i64::from(row.q)
    };
    [
        i64::from(row.candidate.shanten),
        -i64::from(row.candidate.ukeire_count),
        i64::from(row.elevated_risk),
        -quality,
        -i64::from(row.k),
        i64::from(row.other_risk),
        i64::from(row.gift_kong_risk),
        i64::from(row.chicken_exposure),
    ]
}

fn risk_row(candidate: Candidate, unseen: &Counts, context: &CoachContext) -> ContextCandidate {
    let tile = candidate.discard;
    let claim_ukeire = claim_supply(candidate.shanten, &candidate.ukeire, context);
    let mut row = ContextCandidate {
        candidate,
        q: 0,
        k: 0,
        look_ahead_evaluated: false,
        claim_ukeire,
        elevated_risk: 0,
        other_risk: 0,
        gift_kong_risk: 0,
        chicken_exposure: 0,
        risk: [Risk::Unknown; 3],
        reason: "stable",
    };
    let mut may_change_chicken_owner = false;
    for (risk, opponent) in row.risk.iter_mut().zip(context.opponents) {
        let Some(opponent) = opponent.filter(|seat| {
            seat.meld_count <= 4
                && (!seat.completed_kong || seat.meld_count > 0)
                && seat.missing_suit.is_none_or(|suit| suit < 3)
        }) else {
            continue;
        };

        let excludes_tile = opponent.missing_suit == Some(tile / 9);
        let can_peng = !excludes_tile
            && opponent.meld_count < 4
            && !opponent.reported_ready
            && unseen[tile] >= 2;
        if can_peng && unseen[tile] >= 3 && context.remaining.is_some_and(|remaining| remaining > 0)
        {
            row.gift_kong_risk += 1;
        }
        *risk = if excludes_tile {
            Risk::RuleBlocked
        } else if let Some(requires_kong) = context.requires_kong_to_claim {
            if requires_kong && !opponent.completed_kong {
                Risk::RuleBlocked
            } else if !has_tile_role(tile, unseen, opponent.meld_count) {
                Risk::SupplyBlocked
            } else if opponent.reported_ready
                || opponent.meld_count >= 3
                || context.remaining.is_some_and(|remaining| remaining <= 8)
            {
                row.elevated_risk += 1;
                Risk::Elevated
            } else {
                row.other_risk += 1;
                Risk::Possible
            }
        } else {
            Risk::Unknown
        };
        may_change_chicken_owner |= can_peng || matches!(*risk, Risk::Elevated | Risk::Possible);
    }
    if may_change_chicken_owner {
        row.chicken_exposure = context.chicken_values.map_or(0, |values| values[tile]);
    }
    row
}

// With the offered tile reserved, another copy is required to act as a head
// (or a pair in seven pairs). A pung and sequence additionally require an
// available closed meld slot. If any role survives, hidden hands are unknown.
fn has_tile_role(tile: usize, unseen: &Counts, meld_count: usize) -> bool {
    if unseen[tile] > 0 {
        return true;
    }
    if meld_count == 4 || tile >= 27 {
        return false;
    }
    let rank = tile % 9;
    let suit = tile - rank;
    (rank.saturating_sub(2)..=rank.min(6))
        .any(|start| (suit + start..suit + start + 3).all(|part| part == tile || unseen[part] > 0))
}

struct LookAhead<'a> {
    unseen: &'a Counts,
    totals: &'a Counts,
    meld_count: usize,
    missing_suit: Option<usize>,
    cache: &'a mut PatternCache,
    next_supply: HashMap<Counts, NextSupply>,
}

#[derive(Default)]
struct NextSupply {
    count: u16,
    tiles: u64,
}

impl LookAhead<'_> {
    fn evaluate(&mut self, hand: &Counts, candidate: &Candidate) -> (u32, u32) {
        let mut q = 0;
        let mut k = 0;
        let mut after_draw = *hand;
        for (tile, &copies) in self.unseen.iter().enumerate() {
            if copies == 0 || self.totals[tile] == 0 {
                continue;
            }
            let improves = candidate.ukeire.iter().any(|draw| draw.tile == tile);
            if improves && candidate.shanten == 0 {
                continue;
            }
            after_draw[tile] += 1;
            let (next_shanten, next_ukeire) = self.best_after_draw(&after_draw, tile);
            if improves {
                q += u32::from(copies) * u32::from(next_ukeire);
            } else if next_shanten == candidate.shanten {
                k += u32::from(copies)
                    * u32::from(next_ukeire.saturating_sub(candidate.ukeire_count));
            }
            after_draw[tile] -= 1;
        }
        (q, k)
    }

    fn best_after_draw(&mut self, hand: &Counts, drawn: usize) -> (i8, u16) {
        let forced_suit = self
            .missing_suit
            .filter(|&suit| hand[suit * 9..suit * 9 + 9].iter().any(|&count| count > 0));
        // A non-winning 14-equivalent hand has at least one tile outside
        // its closest target. Discarding an excluded suit tile also preserves
        // that distance, so the best legal discard can attain this shanten.
        let best_shanten = self.cache.shanten(hand, self.totals, self.meld_count);
        let mut after_discard = *hand;
        let mut best_ukeire = 0;
        for (tile, &count) in hand.iter().enumerate() {
            if count == 0 || forced_suit.is_some_and(|suit| tile / 9 != suit) {
                continue;
            }
            after_discard[tile] -= 1;
            if self
                .cache
                .shanten(&after_discard, self.totals, self.meld_count)
                == best_shanten
            {
                // Different sequences of first and second discards can reach
                // the same shape. Cache its base ukeire, then subtract exactly
                // the copy drawn by this branch if it is still an effective tile.
                let supply = self.next_supply.entry(after_discard).or_insert_with(|| {
                    let mut supply = NextSupply::default();
                    for waiting in effective_tiles(
                        &after_discard,
                        self.unseen,
                        self.totals,
                        self.meld_count,
                        best_shanten,
                        self.cache,
                    ) {
                        supply.count += u16::from(waiting.count);
                        supply.tiles |= 1 << waiting.tile;
                    }
                    supply
                });
                let consumed = u16::from(supply.tiles & (1 << drawn) != 0);
                best_ukeire = best_ukeire.max(supply.count - consumed);
            }
            after_discard[tile] += 1;
        }
        (best_shanten, best_ukeire)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn counts(tiles: &[usize]) -> Counts {
        let mut result = [0; TILE_TYPES];
        for &tile in tiles {
            result[tile] += 1;
        }
        result
    }

    fn wall() -> Counts {
        let mut result = [0; TILE_TYPES];
        result[..27].fill(4);
        result
    }

    #[test]
    fn look_ahead_never_simulates_an_unavailable_fifth_copy() {
        // A first draw can bring 111m up to four copies. The original unseen
        // supply still contains that draw for shared shape caching; no branch
        // may then send a fictitious fifth 1m into the base-five pattern cache.
        let hand = counts(&[0, 0, 0, 3, 4, 5, 9, 10, 11, 19, 20, 22, 23, 26]);
        let totals = wall();
        let (unseen, shape) = supplies(&hand, &[0; TILE_TYPES], &totals, &[0; TILE_TYPES]).unwrap();
        let mut cache = PatternCache::default();
        let mut after = hand;
        after[26] -= 1;
        let baseline = evaluate(&after, &unseen, &shape, 0, &mut cache);
        let candidate = Candidate {
            discard: 26,
            shanten: baseline.shanten,
            ukeire_count: baseline.ukeire_count,
            ukeire: baseline.ukeire,
        };
        LookAhead {
            unseen: &unseen,
            totals: &shape,
            meld_count: 0,
            missing_suit: None,
            cache: &mut cache,
            next_supply: HashMap::new(),
        }
        .evaluate(&after, &candidate);
        assert!(
            cache
                .shanten_by_hand
                .keys()
                .all(|hand| { hand.iter().zip(shape).all(|(&held, limit)| held <= limit) }),
            "look-ahead must never simulate more copies than the shape allows"
        );
    }

    // Deliberately separate from LookAhead/effective_tiles: consume each draw
    // before enumerating every legal next discard and its effective draws.
    // Fresh caches avoid validating shared-cache mistakes with the same cache.
    fn oracle_quality(
        hand: &Counts,
        unseen: &Counts,
        totals: &Counts,
        meld_count: usize,
        missing_suit: Option<usize>,
        candidate: &Candidate,
    ) -> (u32, u32) {
        let shanten = |hand: &Counts| PatternCache::default().shanten(hand, totals, meld_count);
        let mut q = 0;
        let mut k = 0;
        for drawn in 0..TILE_TYPES {
            if unseen[drawn] == 0 || totals[drawn] == 0 {
                continue;
            }
            let mut branch = *hand;
            branch[drawn] += 1;
            let improves = shanten(&branch) < candidate.shanten;
            if improves && candidate.shanten == 0 {
                continue;
            }
            let mut remaining = *unseen;
            remaining[drawn] -= 1;
            let forced =
                missing_suit.filter(|&suit| branch[suit * 9..suit * 9 + 9].iter().any(|&n| n > 0));
            let mut best = (i8::MAX, Reverse(0u16));
            for discard in 0..TILE_TYPES {
                if branch[discard] == 0 || forced.is_some_and(|suit| discard / 9 != suit) {
                    continue;
                }
                branch[discard] -= 1;
                let distance = shanten(&branch);
                let mut supply = 0;
                for second in 0..TILE_TYPES {
                    if remaining[second] == 0 || branch[second] >= totals[second] {
                        continue;
                    }
                    branch[second] += 1;
                    if shanten(&branch) < distance {
                        supply += u16::from(remaining[second]);
                    }
                    branch[second] -= 1;
                }
                best = best.min((distance, Reverse(supply)));
                branch[discard] += 1;
            }
            if improves {
                q += u32::from(unseen[drawn]) * u32::from(best.1.0);
            } else if best.0 == candidate.shanten {
                k += u32::from(unseen[drawn])
                    * u32::from(best.1.0.saturating_sub(candidate.ukeire_count));
            }
        }
        (q, k)
    }

    #[test]
    fn shared_look_ahead_matches_exhaustive_consumed_supply_branches() {
        let fixtures = [
            (
                counts(&[0, 3, 4, 5, 9, 10, 10, 16, 17, 18, 22, 22, 24, 26]),
                0,
                None,
            ),
            (
                counts(&[0, 0, 0, 3, 4, 5, 9, 10, 11, 19, 20, 22, 23, 26]),
                0,
                None,
            ),
            (counts(&[0, 1, 2, 4, 4, 10, 11, 18, 19, 22, 23]), 1, Some(2)),
        ];
        for (hand, melds, missing_suit) in fixtures {
            let totals = wall();
            let mut visible = [0; TILE_TYPES];
            let mut own = [0; TILE_TYPES];
            if melds == 1 {
                visible[9] = 3;
                own[9] = 3;
            }
            // Small inventories keep the independent, uncached oracle bounded.
            for tile in 0..27 {
                visible[tile] = visible[tile].max(totals[tile].saturating_sub(hand[tile] + 1));
            }
            let context = CoachContext {
                own_missing_suit: missing_suit,
                ..Default::default()
            };
            let (unseen, shape) = supplies(&hand, &visible, &totals, &own).unwrap();
            let shape = constrain_shape(shape, &own, &context).unwrap();
            let legal: Vec<_> = (0..TILE_TYPES)
                .filter(|&tile| hand[tile] > 0 && missing_suit.is_none_or(|suit| tile / 9 == suit))
                .collect();
            let mut cache = PatternCache::default();
            let candidates = evaluate_discards(
                &hand,
                &unseen,
                &shape,
                melds,
                discard_allowlist(&hand, &legal).unwrap(),
                &mut cache,
            );
            let mut search = LookAhead {
                unseen: &unseen,
                totals: &shape,
                meld_count: melds,
                missing_suit,
                cache: &mut cache,
                next_supply: HashMap::new(),
            };
            for candidate in candidates {
                let mut after = hand;
                after[candidate.discard] -= 1;
                assert_eq!(
                    search.evaluate(&after, &candidate),
                    oracle_quality(&after, &unseen, &shape, melds, missing_suit, &candidate),
                    "hand={hand:?} discard={} missing_suit={missing_suit:?}",
                    candidate.discard,
                );
            }
        }
    }

    #[test]
    fn published_two_draw_example_prefers_the_flexible_wait() {
        // Let's Play Mahjong! (2019), section 5 example 3: 123789m222p12359s.
        // This is an abstract four-tile inventory, not a real table win rate.
        let hand = counts(&[0, 1, 2, 6, 7, 8, 10, 10, 10, 18, 19, 20, 22, 26]);
        let unseen = counts(&[19, 21, 22, 26]);
        let totals = wall();
        let mut visible = [0; TILE_TYPES];
        for tile in 0..TILE_TYPES {
            visible[tile] = totals[tile] - hand[tile] - unseen[tile];
        }
        let ranking = analyze_discards_with_context(
            &hand,
            &visible,
            &totals,
            0,
            &[0; TILE_TYPES],
            &[22, 26],
            &CoachContext {
                requires_kong_to_claim: Some(false),
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(ranking[0].candidate.discard, 26);
        assert_eq!(
            (
                ranking[0].candidate.shanten,
                ranking[0].candidate.ukeire_count
            ),
            (0, 1)
        );
        assert_eq!(
            (
                ranking[1].candidate.shanten,
                ranking[1].candidate.ukeire_count
            ),
            (0, 1)
        );
        assert_eq!((ranking[0].q, ranking[1].q), (0, 0));
        assert_eq!((ranking[0].k, ranking[1].k), (1, 0));
        assert_eq!(ranking[0].reason, "k");
        // Enumerate all 4 * 3 ordered draws. A discard decision after the
        // first draw must maximize over the *unseen* second draw, not peek it.
        let successful_sequences = |discard: usize| {
            let mut base = hand;
            base[discard] -= 1;
            let mut successful = 0u32;
            for first in 0..TILE_TYPES {
                if unseen[first] == 0 {
                    continue;
                }
                let mut drawn = base;
                drawn[first] += 1;
                if PatternCache::default().shanten(&drawn, &totals, 0) == -1 {
                    successful += 3;
                    continue;
                }
                let mut best = 0;
                for next_discard in 0..TILE_TYPES {
                    if drawn[next_discard] == 0 {
                        continue;
                    }
                    drawn[next_discard] -= 1;
                    let mut wins = 0;
                    for second in 0..TILE_TYPES {
                        if unseen[second] == 0 || first == second {
                            continue;
                        }
                        drawn[second] += 1;
                        wins +=
                            u32::from(PatternCache::default().shanten(&drawn, &totals, 0) == -1);
                        drawn[second] -= 1;
                    }
                    best = best.max(wins);
                    drawn[next_discard] += 1;
                }
                successful += best;
            }
            successful
        };
        assert_eq!((successful_sequences(26), successful_sequences(22)), (7, 6));
    }

    #[test]
    fn look_ahead_status_distinguishes_zero_quality_from_unsearched_rows() {
        let hand = counts(&[0, 1, 2, 6, 7, 8, 10, 10, 10, 18, 19, 20, 22, 26]);
        let unseen = counts(&[19, 21, 22, 26]);
        let totals = wall();
        let mut visible = [0; TILE_TYPES];
        for tile in 0..TILE_TYPES {
            visible[tile] = totals[tile] - hand[tile] - unseen[tile];
        }
        let analyze = |legal: &[usize], remaining| {
            analyze_discards_with_context(
                &hand,
                &visible,
                &totals,
                0,
                &[0; TILE_TYPES],
                legal,
                &CoachContext {
                    remaining,
                    ..Default::default()
                },
            )
            .unwrap()
        };
        let ranked = analyze(&[22, 26], Some(4));
        assert!(ranked.iter().all(|row| row.look_ahead_evaluated));
        assert_eq!((ranked[1].q, ranked[1].k), (0, 0));
        let exhausted = analyze(&[22, 26], Some(0));
        assert!(
            exhausted
                .iter()
                .all(|row| !row.look_ahead_evaluated && row.q == 0 && row.k == 0)
        );
        assert!(!analyze(&[26], Some(4))[0].look_ahead_evaluated);
        assert!(
            analyze(&[22, 26], None)
                .iter()
                .all(|row| row.look_ahead_evaluated)
        );
    }
}
