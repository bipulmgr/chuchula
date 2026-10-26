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
   groups: three groups of 3 cards and one group of 4 cards. Cards can be
   swapped one at a time, and whole groups can be swapped by dragging (or
   tapping) a group's label. Press **Ready** to lock the arrangement.
3. **Order.** Groups are always played **strongest first**: group 1 is
   the player's strongest group, group 4 the weakest. The 4-card group
   goes wherever it ranks (a 4-card trail goes first). The app puts the
   groups in this order when Ready is pressed, and the engine and server
   enforce it.
4. **Play.** Once all four players are ready, everyone's group 1 is
   played. The player after the dealer reveals first, then the others in
   turn. The strongest group wins the point and its owner leads the next
   group. This repeats for groups 2, 3 and 4. A turn can mix 3-card and
   4-card groups; they compare on the one ladder below.
5. **Score.** Points are added (see below) and the next round is dealt.

The match ends when a player reaches the target score (20).

## Ranking groups (strongest first)

3-card and 4-card groups are ranked on one ladder. A 4-card group counts
as the best hand inside it: three spades and a heart make a Color, and
5-6-7 with a K is a Run.

| Rank | Name | Example |
|---|---|---|
| 1 | Four of a kind | 7♠ 7♥ 7♦ 7♣ |
| 2 | Trail (three of a kind) | A♠ A♥ A♦ |
| 3 | Double run (pure sequence: a run in one suit) | Q♥ J♥ 10♥ |
| 4 | Run (sequence) | 9♣ 8♦ 7♠ |
| 5 | Color (same suit) | K♠ 9♠ 4♠ |
| 6 | Two pair (4 cards only) | K♠ K♦ 4♥ 4♣ |
| 7 | Pair | 8♥ 8♣ K♦ |
| 8 | High card | A♦ 10♣ 6♥ |

**4-card hands.** When all four cards make the hand (a 4-card double
run, run or color), it beats every 3-card hand of the same kind,
whatever the high card. A 4-card color with 8 high beats a 3-card color
with A high. To beat a 4-card color you need a stronger 4-card color, or
a higher kind: a run, double run, trail or four of a kind. The same
holds for 4-card runs and double runs. The app labels these "4-card
Color", "4-card Run" and so on.

**Within a kind.** Compare the deciding ranks of the hand. If those are
equal, a 4-card group's extra card counts as one more kicker, so it beats
a 3-card group with the same three cards.

**Sequences.** Aces are high or low. A-K-Q (A-K-Q-J) is the highest run,
A-2-3 (A-2-3-4) is second, then K-Q-J and so on down to 4-3-2. Runs do not
wrap around (K-A-2 is not a run).

**Equal categories.** Compare the deciding ranks in order: the trail or
pair rank first, then the kickers from high to low. For sequences, compare
the run's position.

**Exact ties.** If two groups have identical ranks, the suit of the
highest card decides: spades > hearts > diamonds > clubs. Every card is
unique, so there is always a winner. *(Interim.)*

*(Interim: the order of kinds follows Teen Patti with four of a kind on
top; two pair sits between Color and Pair; the extra-card kicker rule.)*

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
6. Are exact ties broken by suit, or is the point split?
7. Where do two pair and the 4-card group's extra card rank (see above)?

Confirmed by Bipul on 2026-10-26: groups are played strongest first with
the 4-card group anywhere; a 4-card group is named by the best hand in
it; a full 4-card hand beats a 3-card hand of the same kind.

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
| `strongestFirst` | true | Groups are played strongest first (the engine orders them) |
| `maxRounds` | 100 | Safety limit |
