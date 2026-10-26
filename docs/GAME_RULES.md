# Chuchula game rules

Chuchula is a four-player Nepali card game played with one standard
52-card deck (no jokers). This page describes the rules as the app plays
them. A few rules were not fully specified and use **interim
interpretations**. Each one is a switch in
`lib/game/rules/rule_config.dart` (mirrored in
`functions/src/engine/rules.ts`), so changing one does not touch the engine.

## A round

1. **Deal.** The dealer deals all 52 cards one at a time, starting with
   the player after the dealer. Each player gets 13 cards. The dealer
   rotates one seat each round.
2. **Arrange.** Each player secretly splits their 13 cards into four
   groups: three groups of 3 cards and one group of 4 cards. Groups 1 to 3
   can be in any order. The 4-card group is always played last. Press
   **Ready** to lock the arrangement.
3. **Play.** Once all four players are ready, group 1 is played. The
   player after the dealer reveals first, then the others in turn. The
   strongest group wins the point and its owner leads the next group.
   This repeats for groups 2, 3 and the 4-card group.
4. **Score.** Points are added (see below) and the next round is dealt.

The match ends when a player reaches the target score (20).

## Ranking a 3-card group (strongest first)

| Rank | Name | Example |
|---|---|---|
| 1 | Trail (three of a kind) | A♠ A♥ A♦ |
| 2 | Pure sequence (run in one suit) | Q♥ J♥ 10♥ |
| 3 | Sequence (run) | 9♣ 8♦ 7♠ |
| 4 | Color (same suit) | K♠ 9♠ 4♠ |
| 5 | Pair | 8♥ 8♣ K♦ |
| 6 | High card | A♦ 10♣ 6♥ |

## Ranking a 4-card group (strongest first)

| Rank | Name | Example |
|---|---|---|
| 1 | Four of a kind | 7♠ 7♥ 7♦ 7♣ |
| 2 | Pure sequence | J♦ 10♦ 9♦ 8♦ |
| 3 | Trail | Q♠ Q♥ Q♣ 3♦ |
| 4 | Sequence | 6♣ 5♥ 4♠ 3♦ |
| 5 | Color | A♣ J♣ 8♣ 2♣ |
| 6 | Two pair | K♠ K♦ 4♥ 4♣ |
| 7 | Pair | 9♠ 9♦ A♥ 5♣ |
| 8 | High card | A♠ Q♦ 8♥ 3♣ |

The 4-card ranking follows how rare each hand is. Four of a kind is
rarer than a pure sequence, which is rarer than a trail.

**Sequences.** Aces are high or low. A-K-Q (A-K-Q-J) is the highest run,
A-2-3 (A-2-3-4) is second, then K-Q-J and so on down to 4-3-2. Runs do not
wrap around (K-A-2 is not a run).

**Equal categories.** Compare the deciding ranks in order: the trail or
pair rank first, then the kickers from high to low. For sequences, compare
the run's position.

**Exact ties.** If two groups have identical ranks, the suit of the
highest card decides: spades > hearts > diamonds > clubs. Every card is
unique, so there is always a winner. *(Interim.)*

## Scoring

| Event | Points |
|---|---|
| Win a group | 1 |
| Win all four groups in a round (sweep) | 5 in total *(interim: replaces the four 1-point wins)* |
| Four of a kind in your 13 cards | 4 (each one) |
| Six pairs in your 13 cards | 6 |
| Three trails ("three trials") in your 13 cards | 9 |
| One card of every rank, A to K ("all thirteen different") | Instant match win |

Bonus details *(interim)*:

- Bonuses are judged on the **dealt hand**, not on how it is arranged,
  and they **stack** with group points.
- For six pairs, a four of a kind counts as two pairs and a trail as one.
- "Three trials" is read as three *trails* (three separate
  three-of-a-kinds).
- If two players are dealt all thirteen ranks in the same deal, the deal
  is void and redealt.

## Winning *(interim)*

- The first player to reach **20 or more** wins.
- If several players pass 20 in the same round, the highest total wins.
- If the highest totals are tied, another round is played.
- As a safety valve the match stops after 100 rounds (highest score wins).

## Open questions for confirmation

These follow the interim answers above until confirmed:

1. "Three trials": is it three trails (three of a kind)? Is 9 the right value?
2. "All thirteen different": one of every rank, instant win?
3. Does a sweep's 5 points replace the four group points or add to them?
4. Do bonuses stack with group points, and are they judged on the dealt hand?
5. Is the target "20 or more"? What happens with a tie above 20?
6. Must groups 1 to 3 be in a set order (for example weakest first)?
7. Are exact ties broken by suit, or is the point split?

## Rule switches

| Switch | Default | Meaning |
|---|---|---|
| `targetScore` | 20 | Points to win |
| `targetIsExact` | false | Must hit the target exactly (overshooting scores 0 that round) |
| `groupWinPoints` | 1 | Points per group won |
| `sweepPoints` | 5 | Sweep value |
| `sweepReplacesGroupPoints` | true | Sweep is 5 in total instead of 4 + 5 |
| `fourOfAKindPoints` | 4 | Bonus per four of a kind |
| `sixPairsPoints` | 6 | Six pairs bonus |
| `threeTrailsPoints` | 9 | Three trails bonus |
| `bonusesStackWithGroupPoints` | true | If false, a player gets the larger of bonus or group points |
| `allRanksInstantWin` | true | All thirteen ranks wins the match |
| `requireAscendingStrength` | false | Groups 1 to 3 must not get weaker |
| `maxRounds` | 100 | Safety limit |
