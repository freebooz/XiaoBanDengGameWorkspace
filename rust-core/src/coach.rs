use std::{cmp::Reverse, collections::HashMap};

mod context;
pub use context::{
    CoachContext, ContextCandidate, ContextHand, Opponent, Risk, analyze_discards_with_context,
    analyze_hand_with_context,
};

pub const TILE_TYPES: usize = 34;
pub type Counts = [u8; TILE_TYPES];

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct EffectiveTile {
    pub tile: usize,
    pub count: u8,
}

#[derive(Debug, PartialEq, Eq)]
pub struct Candidate {
    pub discard: usize,
    pub shanten: i8,
    pub ukeire_count: u16,
    pub ukeire: Vec<EffectiveTile>,
}

#[derive(Debug, PartialEq, Eq)]
pub struct HandAnalysis {
    pub shanten: i8,
    pub ukeire_count: u16,
    pub ukeire: Vec<EffectiveTile>,
}

#[derive(Debug, PartialEq, Eq)]
pub enum AnalysisError {
    InvalidHandSize,
    InvalidTileTotal,
    KnownExceedsTotal,
    InvalidDiscard,
    InvalidContext,
}

impl AnalysisError {
    pub fn code(&self) -> &'static str {
        match self {
            Self::InvalidHandSize => "invalid_hand_size",
            Self::InvalidTileTotal => "invalid_tile_total",
            Self::KnownExceedsTotal => "known_exceeds_total",
            Self::InvalidDiscard => "invalid_discard",
            Self::InvalidContext => "invalid_context",
        }
    }
}

/// One decision on the current player's visible table. The concealed hand is
/// counted before simulating discards, so the discarded tile remains known.
pub fn analyze_all(
    hand: &Counts,
    visible: &Counts,
    totals: &Counts,
    meld_count: usize,
    legal: &[usize],
) -> Result<Vec<Candidate>, AnalysisError> {
    analyze_discards(hand, visible, totals, meld_count, &[0; TILE_TYPES], legal)
}

/// Own completed meld tiles are unavailable to the remaining concealed shape.
/// Other public tiles reduce ukeire only: shanten remains structural, not a
/// knowledge-dependent distance that changes when opponents reveal a tile.
pub fn analyze_discards(
    hand: &Counts,
    visible: &Counts,
    totals: &Counts,
    meld_count: usize,
    own_meld_tiles: &Counts,
    legal: &[usize],
) -> Result<Vec<Candidate>, AnalysisError> {
    validate_hand_size(hand, meld_count, 14)?;
    let (unseen, shape_totals) = supplies(hand, visible, totals, own_meld_tiles)?;
    let eligible = discard_allowlist(hand, legal)?;
    let mut candidates = evaluate_discards(
        hand,
        &unseen,
        &shape_totals,
        meld_count,
        eligible,
        &mut PatternCache::default(),
    );
    candidates.sort_by_key(|item| (item.shanten, Reverse(item.ukeire_count), item.discard));
    Ok(candidates)
}

fn discard_allowlist(hand: &Counts, legal: &[usize]) -> Result<[bool; TILE_TYPES], AnalysisError> {
    let mut eligible = [false; TILE_TYPES];
    for &tile in legal {
        if tile >= TILE_TYPES || hand[tile] == 0 {
            return Err(AnalysisError::InvalidDiscard);
        }
        eligible[tile] = true;
    }
    Ok(eligible)
}

fn evaluate_discards(
    hand: &Counts,
    unseen: &Counts,
    shape_totals: &Counts,
    meld_count: usize,
    eligible: [bool; TILE_TYPES],
    pattern_cache: &mut PatternCache,
) -> Vec<Candidate> {
    let mut after = *hand;
    let mut candidates = Vec::new();
    for (discard, allowed) in eligible.into_iter().enumerate() {
        if !allowed {
            continue;
        }
        after[discard] -= 1;
        let result = evaluate(&after, unseen, shape_totals, meld_count, pattern_cache);
        after[discard] += 1;
        candidates.push(Candidate {
            discard,
            shanten: result.shanten,
            ukeire_count: result.ukeire_count,
            ukeire: result.ukeire,
        });
    }
    candidates
}

/// Analyze the current 13-equivalent hand between turns; no fictitious discard.
pub fn analyze_hand(
    hand: &Counts,
    visible: &Counts,
    totals: &Counts,
    meld_count: usize,
    own_meld_tiles: &Counts,
) -> Result<HandAnalysis, AnalysisError> {
    validate_hand_size(hand, meld_count, 13)?;
    let (unseen, shape_totals) = supplies(hand, visible, totals, own_meld_tiles)?;
    Ok(evaluate(
        hand,
        &unseen,
        &shape_totals,
        meld_count,
        &mut PatternCache::default(),
    ))
}

fn validate_hand_size(
    hand: &Counts,
    meld_count: usize,
    equivalent: usize,
) -> Result<(), AnalysisError> {
    let held = hand.iter().map(|&n| usize::from(n)).sum::<usize>();
    if meld_count > 4 || held != equivalent - 3 * meld_count {
        return Err(AnalysisError::InvalidHandSize);
    }
    Ok(())
}

fn supplies(
    hand: &Counts,
    visible: &Counts,
    totals: &Counts,
    own_meld_tiles: &Counts,
) -> Result<(Counts, Counts), AnalysisError> {
    let mut unseen = [0; TILE_TYPES];
    let mut shape_totals = *totals;
    for tile in 0..TILE_TYPES {
        if totals[tile] > 4 {
            return Err(AnalysisError::InvalidTileTotal);
        }
        let known = u16::from(hand[tile]) + u16::from(visible[tile]);
        if known > u16::from(totals[tile]) || own_meld_tiles[tile] > visible[tile] {
            return Err(AnalysisError::KnownExceedsTotal);
        }
        unseen[tile] = totals[tile] - known as u8;
        shape_totals[tile] -= own_meld_tiles[tile];
    }
    Ok((unseen, shape_totals))
}

fn evaluate(
    hand: &Counts,
    unseen: &Counts,
    totals: &Counts,
    meld_count: usize,
    cache: &mut PatternCache,
) -> HandAnalysis {
    let shanten = cache.shanten(hand, totals, meld_count);
    let ukeire =
        effective_tiles(hand, unseen, totals, meld_count, shanten, cache).collect::<Vec<_>>();
    HandAnalysis {
        shanten,
        ukeire_count: ukeire.iter().map(|tile| u16::from(tile.count)).sum(),
        ukeire,
    }
}

fn effective_tiles<'a>(
    hand: &Counts,
    unseen: &'a Counts,
    totals: &'a Counts,
    meld_count: usize,
    shanten: i8,
    cache: &'a mut PatternCache,
) -> impl Iterator<Item = EffectiveTile> + 'a {
    let mut after = *hand;
    unseen.iter().enumerate().filter_map(move |(tile, &count)| {
        // Look-ahead caches may pass the pre-draw unseen supply. A branch can
        // already hold its fourth copy; never form a fifth-copy hand or feed
        // a digit above four into the suit cache's base-five key.
        if count == 0 || after[tile] >= totals[tile] {
            return None;
        }
        after[tile] += 1;
        let improves = cache.shanten(&after, totals, meld_count) < shanten;
        after[tile] -= 1;
        improves.then_some(EffectiveTile { tile, count })
    })
}

// Exact minimum missing-tile distance to a legal 4-meld-and-head target.
// Meld/taatsu counts lose copy constraints: a pung plus a singleton head can
// incorrectly need a fifth identical tile. Build legal targets rank by rank.
// Each cache lives for one analysis, so its immutable supply is not a key.
const INF: u8 = 40;
type Costs = [[u8; 2]; 5];

#[derive(Default)]
struct PatternCache {
    suited: [HashMap<u32, Costs>; 3],
    honors: HashMap<u32, Costs>,
    shanten_by_hand: HashMap<Counts, i8>,
}

impl PatternCache {
    fn shanten(&mut self, hand: &Counts, totals: &Counts, open_melds: usize) -> i8 {
        if let Some(&cached) = self.shanten_by_hand.get(hand) {
            return cached;
        }
        let mut combined = [[INF; 2]; 5];
        combined[0][0] = 0;
        for (suit, cache) in self.suited.iter_mut().enumerate() {
            let start = suit * 9;
            if totals[start..start + 9].iter().all(|&limit| limit == 0) {
                continue;
            }
            combined = merge_costs(
                combined,
                component(
                    &hand[start..start + 9],
                    &totals[start..start + 9],
                    true,
                    cache,
                ),
            );
        }
        if totals[27..].iter().any(|&limit| limit > 0) {
            combined = merge_costs(
                combined,
                component(&hand[27..], &totals[27..], false, &mut self.honors),
            );
        }
        let mut minimum = combined[4 - open_melds][1] as i8 - 1;
        if open_melds == 0 {
            // Guiyang/basic_108 allow a quad as two pairs. Riichi's distinct
            // seven-pair formula is not applicable to these server rules.
            let mut pair_slots = 0;
            let mut complete = 0;
            let mut partial = 0;
            for (&held, &limit) in hand.iter().zip(totals) {
                let slots = limit / 2;
                let held_pairs = (held / 2).min(slots);
                pair_slots += slots;
                complete += held_pairs;
                partial += u8::from(held % 2 == 1 && held_pairs < slots);
            }
            if pair_slots >= 7 {
                // Each additional pair of a kind costs at least as much as
                // the one before it, so take full pairs, singles, then blanks.
                let needed = 7u8.saturating_sub(complete);
                let from_singles = needed.min(partial);
                let missing = 2 * needed - from_singles;
                minimum = minimum.min(missing as i8 - 1);
            }
        }
        self.shanten_by_hand.insert(*hand, minimum);
        minimum
    }
}

fn merge_costs(left: Costs, right: Costs) -> Costs {
    let mut result = [[INF; 2]; 5];
    for m in 0..=4 {
        for p in 0..=1 {
            for n in 0..=4 - m {
                for q in 0..=1 - p {
                    result[m + n][p + q] =
                        result[m + n][p + q].min(left[m][p].saturating_add(right[n][q]));
                }
            }
        }
    }
    result
}

fn component(hand: &[u8], totals: &[u8], suited: bool, cache: &mut HashMap<u32, Costs>) -> Costs {
    let key = hand.iter().fold(0, |key, &n| key * 5 + u32::from(n));
    if let Some(&cost) = cache.get(&key) {
        return cost;
    }
    // [sequences started one rank ago][two ranks ago][melds][head]
    let mut dp = [[[[INF; 2]; 5]; 5]; 5];
    dp[0][0][0][0] = 0;
    for rank in 0..hand.len() {
        let mut next = [[[[INF; 2]; 5]; 5]; 5];
        for a in 0..=4 {
            for b in 0..=4 {
                for m in 0..=4 {
                    for p in 0..=1 {
                        let prior = dp[a][b][m][p];
                        if prior == INF {
                            continue;
                        }
                        for triplet in 0..=1usize {
                            for head in 0..=1 - p {
                                let max_runs = if suited && rank + 2 < hand.len() {
                                    4 - m
                                } else {
                                    0
                                };
                                for runs in 0..=max_runs {
                                    let melds = m + triplet + runs;
                                    let need = a + b + 3 * triplet + 2 * head + runs;
                                    if melds > 4 || need > usize::from(totals[rank]) {
                                        continue;
                                    }
                                    let cost = prior + (need as u8).saturating_sub(hand[rank]);
                                    next[runs][a][melds][p + head] =
                                        next[runs][a][melds][p + head].min(cost);
                                }
                            }
                        }
                    }
                }
            }
        }
        dp = next;
    }
    let result = dp[0][0];
    cache.insert(key, result);
    result
}
#[cfg(test)]
mod tests {
    use super::*;

    fn wall() -> Counts {
        let mut counts = [0; TILE_TYPES];
        counts[..27].fill(4);
        counts
    }

    fn hand_with(tiles: &[usize]) -> Counts {
        let mut counts = [0; TILE_TYPES];
        for &tile in tiles {
            counts[tile] += 1;
        }
        counts
    }

    fn sample() -> Counts {
        hand_with(&[0, 1, 2, 3, 4, 5, 8, 15, 16, 17, 19, 19, 22, 23])
    }

    #[test]
    fn basic_108_table_example_prefers_the_stronger_shape_improvement() {
        // 1456m 12289p 15579s, with 1m and 1s tied at 2 shanten / 16 ukeire.
        let hand = hand_with(&[0, 3, 4, 5, 9, 10, 10, 16, 17, 18, 22, 22, 24, 26]);
        let ranking = analyze_discards_with_context(
            &hand,
            &[0; TILE_TYPES],
            &wall(),
            0,
            &[0; TILE_TYPES],
            &[0, 18, 18],
            &CoachContext {
                requires_kong_to_claim: Some(false),
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(ranking.len(), 2);
        assert_eq!(
            (
                ranking[0].candidate.shanten,
                ranking[0].candidate.ukeire_count
            ),
            (2, 16)
        );
        assert_eq!(
            (
                ranking[1].candidate.shanten,
                ranking[1].candidate.ukeire_count
            ),
            (2, 16)
        );
        assert_eq!(ranking[0].candidate.discard, 18);
        assert_eq!((ranking[0].q, ranking[1].q), (160, 160));
        assert_eq!((ranking[0].k, ranking[1].k), (286, 254));
        assert_eq!(ranking[0].reason, "k");
    }

    #[test]
    fn strict_guiyang_table_example_prefers_the_supply_blocked_discard() {
        // 245699m 23p 235669s. Three 9s are visible, and a seat with
        // 8888s / 555p / 777p has completed a kong and has three melds.
        let hand = hand_with(&[1, 3, 4, 5, 8, 8, 10, 11, 19, 20, 22, 23, 23, 26]);
        let visible = hand_with(&[26, 26, 26, 25, 25, 25, 25, 13, 13, 13, 15, 15, 15]);
        let ranking = analyze_discards_with_context(
            &hand,
            &visible,
            &wall(),
            0,
            &[0; TILE_TYPES],
            &[1, 26],
            &CoachContext {
                requires_kong_to_claim: Some(true),
                remaining: Some(20),
                opponents: [
                    Some(Opponent {
                        meld_count: 3,
                        completed_kong: true,
                        ..Default::default()
                    }),
                    None,
                    None,
                ],
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(
            (
                ranking[0].candidate.shanten,
                ranking[0].candidate.ukeire_count
            ),
            (2, 24)
        );
        assert_eq!(
            (
                ranking[1].candidate.shanten,
                ranking[1].candidate.ukeire_count
            ),
            (2, 24)
        );
        assert_eq!(ranking[0].candidate.discard, 26);
        assert_eq!(
            ranking[0].risk,
            [Risk::SupplyBlocked, Risk::Unknown, Risk::Unknown]
        );
        assert_eq!(ranking[1].risk[0], Risk::Elevated);
        assert_eq!(ranking[0].reason, "elevated_risk");
    }

    #[test]
    fn no_kong_blocks_the_strict_claim_but_does_not_block_gift_kong() {
        let hand = sample();
        // An earlier 9m discard is visible in addition to the candidate's 9m.
        let visible = hand_with(&[8]);
        let opponent = Some(Opponent::default());
        let mut context = CoachContext {
            requires_kong_to_claim: Some(true),
            own_has_kong: Some(false),
            remaining: Some(8),
            opponents: [opponent, None, None],
            ..Default::default()
        };
        let analyze = |visible: &Counts, context: &CoachContext| {
            analyze_discards_with_context(
                &hand,
                visible,
                &wall(),
                0,
                &[0; TILE_TYPES],
                &[8],
                context,
            )
            .unwrap()
            .pop()
            .unwrap()
        };

        let strict = analyze(&[0; TILE_TYPES], &context);
        assert_eq!(
            strict.risk,
            [Risk::RuleBlocked, Risk::Unknown, Risk::Unknown]
        );
        assert_eq!(strict.gift_kong_risk, 1);
        assert_eq!(strict.claim_ukeire, Some(vec![]));

        context.requires_kong_to_claim = Some(false);
        let basic = analyze(&visible, &context);
        assert_eq!(basic.risk[0], Risk::Elevated);
        assert_eq!(basic.gift_kong_risk, 0);
        assert_eq!(
            basic
                .claim_ukeire
                .as_ref()
                .unwrap()
                .iter()
                .map(|tile| tile.count)
                .sum::<u8>(),
            8
        );

        context.requires_kong_to_claim = None;
        let unknown = analyze(&visible, &context);
        assert_eq!(unknown.risk[0], Risk::Unknown);
        assert_eq!(unknown.claim_ukeire, None);
    }

    #[test]
    fn dingque_constrains_win_shape_without_removing_known_tiles() {
        // 123m 456m 789m 22p 55s is an ordinary wait, but not without s.
        let hand = hand_with(&[0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 10, 22, 22]);
        let context = CoachContext {
            own_missing_suit: Some(2),
            requires_kong_to_claim: Some(false),
            ..Default::default()
        };
        let ordinary = analyze_hand(&hand, &[0; TILE_TYPES], &wall(), 0, &[0; TILE_TYPES]).unwrap();
        let constrained = analyze_hand_with_context(
            &hand,
            &[0; TILE_TYPES],
            &wall(),
            0,
            &[0; TILE_TYPES],
            &context,
        )
        .unwrap();
        assert_eq!(ordinary.shanten, 0);
        assert_eq!(constrained.hand.shanten, 2);
        assert!(constrained.hand.ukeire.iter().all(|tile| tile.tile < 18));
        assert_eq!(constrained.claim_ukeire, Some(vec![]));
        let mut too_many_known = [0; TILE_TYPES];
        too_many_known[22] = 3;
        assert!(matches!(
            analyze_hand_with_context(
                &hand,
                &too_many_known,
                &wall(),
                0,
                &[0; TILE_TYPES],
                &context,
            ),
            Err(AnalysisError::KnownExceedsTotal)
        ));
    }

    #[test]
    fn four_identical_tiles_cannot_wait_for_a_fifth_copy() {
        // After discarding 9s: 1111m 111444p 111s. A fifth 1m is
        // impossible; reaching a real winning shape needs two new tiles.
        let hand = hand_with(&[0, 0, 0, 0, 9, 9, 9, 12, 12, 12, 18, 18, 18, 26]);
        let result = analyze_all(&hand, &[0; TILE_TYPES], &wall(), 0, &[26]).unwrap();
        assert_eq!(result[0].shanten, 1);
    }

    #[test]
    fn whole_hand_updates_public_supply_and_rejects_fake_discard_size() {
        let mut hand = sample();
        hand[8] -= 1;
        let mut visible = hand_with(&[8]);
        let baseline = analyze_hand(&hand, &visible, &wall(), 0, &[0; TILE_TYPES]).unwrap();
        assert_eq!((baseline.shanten, baseline.ukeire_count), (0, 8));
        for seat in 0..3 {
            visible[21] += 1;
            let fresh = analyze_hand(&hand, &visible, &wall(), 0, &[0; TILE_TYPES]).unwrap();
            assert_eq!((fresh.shanten, fresh.ukeire_count), (0, 7 - seat));
        }
        assert_eq!(
            analyze_all(&hand, &visible, &wall(), 0, &[0]),
            Err(AnalysisError::InvalidHandSize)
        );
        assert_eq!(
            analyze_hand(&sample(), &visible, &wall(), 0, &[0; TILE_TYPES]),
            Err(AnalysisError::InvalidHandSize)
        );
    }

    #[test]
    fn own_pung_cannot_supply_fifth_copy_as_concealed_head() {
        let hand = hand_with(&[0, 12, 12, 12]);
        let own = hand_with(&[0, 0, 0, 9, 9, 9, 10, 10, 10]);
        let result = analyze_hand(&hand, &own, &wall(), 3, &own).unwrap();
        assert_eq!(result.shanten, 1);
        assert!(!result.ukeire.iter().any(|draw| draw.tile == 0));
    }

    #[test]
    fn external_cross_suit_regression_and_guiyang_quad_pairs() {
        // Published ordinary-hand regression: https://github.com/Agony5757/mahjong/issues/30
        let hand = hand_with(&[1, 3, 4, 4, 5, 7, 10, 12, 13, 13, 14, 16, 24, 24]);
        assert_eq!(PatternCache::default().shanten(&hand, &wall(), 0), 2);
        let dragon_pairs = hand_with(&[0, 0, 0, 0, 3, 3, 6, 6, 10, 10, 13, 13, 25, 25]);
        assert_eq!(
            PatternCache::default().shanten(&dragon_pairs, &wall(), 0),
            -1
        );
        let mut waiting = dragon_pairs;
        waiting[25] -= 1;
        let result =
            analyze_hand(&waiting, &[0; TILE_TYPES], &wall(), 0, &[0; TILE_TYPES]).unwrap();
        assert_eq!(result.shanten, 0);
        assert!(
            result
                .ukeire
                .contains(&EffectiveTile { tile: 25, count: 3 })
        );
    }

    #[test]
    fn exact_rank_dp_matches_independent_target_enumeration() {
        // Test oracle constructs all complete suit targets by adding melds in
        // nondecreasing order, independently of production's rank/carry DP.
        fn visit(
            target: [u8; 9],
            melds: usize,
            start: usize,
            out: &mut Vec<([u8; 9], usize, usize)>,
        ) {
            out.push((target, melds, 0));
            for pair in 0..9 {
                if target[pair] <= 2 {
                    let mut next = target;
                    next[pair] += 2;
                    out.push((next, melds, 1));
                }
            }
            if melds == 4 {
                return;
            }
            for kind in start..16 {
                let mut next = target;
                if kind < 9 {
                    next[kind] += 3;
                } else {
                    for rank in kind - 9..kind - 6 {
                        next[rank] += 1;
                    }
                }
                if next.iter().all(|&n| n <= 4) {
                    visit(next, melds + 1, kind, out);
                }
            }
        }
        let mut targets = Vec::new();
        visit([0; 9], 0, 0, &mut targets);
        let mut seed = 0x87b9_u64;
        for sample in 0..600 {
            let mut hand = [0u8; 9];
            let mut supply = [4u8; 9];
            // Include reduced supply from our own melds and removed tile kinds.
            if sample % 3 == 0 {
                supply[sample % 9] = (sample % 4) as u8;
            }
            for _ in 0..sample % 15 {
                seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1);
                let tile = (seed >> 32) as usize % 9;
                if hand[tile] < supply[tile] {
                    hand[tile] += 1;
                }
            }
            let mut expected = [[INF; 2]; 5];
            for (target, melds, head) in &targets {
                if target.iter().zip(supply).any(|(&n, cap)| n > cap) {
                    continue;
                }
                let needed = target
                    .iter()
                    .zip(hand)
                    .map(|(&n, held)| n.saturating_sub(held))
                    .sum::<u8>();
                expected[*melds][*head] = expected[*melds][*head].min(needed);
            }
            assert_eq!(
                component(&hand, &supply, true, &mut HashMap::new()),
                expected,
                "sample={sample} hand={hand:?} caps={supply:?}"
            );
        }
        eprintln!(
            "ORACLE_OK 600 suit states x 10 target families; enumerated_targets={}",
            targets.len()
        );
    }

    #[test]
    fn known_tiles_reduce_two_waits_from_eight_to_three() {
        let hand = sample();
        let empty = [0; TILE_TYPES];
        let all = analyze_all(&hand, &empty, &wall(), 0, &[8]).unwrap();
        assert_eq!(all[0].shanten, 0);
        assert_eq!(all[0].ukeire_count, 8);
        assert_eq!(
            all[0].ukeire,
            [
                EffectiveTile { tile: 21, count: 4 },
                EffectiveTile { tile: 24, count: 4 },
            ]
        );
        let visible = hand_with(&[21, 21, 21, 24, 24]);
        let all = analyze_all(&hand, &visible, &wall(), 0, &[8]).unwrap();
        assert_eq!(all[0].ukeire_count, 3);
        assert_eq!(
            all[0].ukeire,
            [
                EffectiveTile { tile: 21, count: 1 },
                EffectiveTile { tile: 24, count: 2 },
            ]
        );
    }

    #[test]
    fn candidates_are_unique_and_ranked_by_structure_before_count() {
        let hand = sample();
        let all = analyze_all(&hand, &[0; TILE_TYPES], &wall(), 0, &[8, 19, 0, 19]).unwrap();
        assert_eq!(all.len(), 3);
        assert_eq!(all[0].discard, 8);
        for pair in all.windows(2) {
            assert!(pair[0].shanten <= pair[1].shanten);
            if pair[0].shanten == pair[1].shanten {
                assert!(pair[0].ukeire_count >= pair[1].ukeire_count);
            }
        }
    }

    #[test]
    fn recognizes_open_hand_and_seven_pairs() {
        let hand = hand_with(&[3, 4, 5, 8, 15, 16, 17, 19, 19, 22, 23]);
        let open = analyze_all(&hand, &[0; TILE_TYPES], &wall(), 1, &[8]).unwrap();
        assert_eq!((open[0].shanten, open[0].ukeire_count), (0, 8));
        let hand = hand_with(&[0, 0, 0, 0, 2, 2, 4, 4, 8, 8, 12, 12, 20, 26]);
        let pairs = analyze_all(&hand, &[0; TILE_TYPES], &wall(), 0, &[26]).unwrap();
        assert_eq!(pairs[0].ukeire, [EffectiveTile { tile: 20, count: 3 }]);
    }

    #[test]
    fn simulated_discard_remains_known_when_it_is_also_an_effective_draw() {
        let hand = hand_with(&[0, 0, 0, 1, 2, 3, 5, 6, 7, 9, 10, 11, 19, 19]);
        let candidate = analyze_all(&hand, &[0; TILE_TYPES], &wall(), 0, &[0]).unwrap();
        assert_eq!(candidate[0].shanten, 0);
        assert!(
            candidate[0]
                .ukeire
                .contains(&EffectiveTile { tile: 0, count: 1 })
        );
    }

    #[test]
    fn rejects_invalid_counts_and_discard_without_negative_supply() {
        let mut visible = [0; TILE_TYPES];
        visible[21] = 5;
        assert_eq!(
            analyze_all(&sample(), &visible, &wall(), 0, &[8]),
            Err(AnalysisError::KnownExceedsTotal)
        );
        assert_eq!(
            analyze_all(&sample(), &[0; TILE_TYPES], &wall(), 0, &[33]),
            Err(AnalysisError::InvalidDiscard)
        );
        assert_eq!(
            analyze_all(&sample(), &[0; TILE_TYPES], &wall(), 1, &[8]),
            Err(AnalysisError::InvalidHandSize)
        );
        visible[21] = 4;
        visible[24] = 4;
        let all = analyze_all(&sample(), &visible, &wall(), 0, &[8]).unwrap();
        assert_eq!((all[0].shanten, all[0].ukeire_count), (0, 0));
    }
}
