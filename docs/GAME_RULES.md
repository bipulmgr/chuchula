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
4. **Play.** Once all four players are ready, the groups are revealed
   automatically, with no taps: everyone's group 1 is played. The player after the dealer reveals first, then the others in
   turn. The strongest group wins the point and its owner leads the next
   group. This repeats for groups 2, 3 and 4. A turn can mix 3-card and
   4-card groups; they compare on the one ladder below.
5. **Score.** Points are added (see below) and the next round is dealt.

The match ends when a player reaches the target score (20).

## Ranking groups (strongest first)

3-card and 4-card groups are ranked on one ladder. A 4-card group counts
as the best hand inside it: three spades and a heart make a Color, and
5-6-7 with a K is a Run. Unless all four cards make the hand, the fourth
card is a spare and adds nothing: 5♦ 5♥ 6♥ 7♥ is worth exactly the same
as 5♥ 6♥ 7♥ (a 3-card double run).

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

**The spare card.** Because a spare adds nothing, padding a strong group
with it gains nothing. Suggest and the bots therefore aim for full 4-card
hands, and otherwise put the spare on the weakest group, where it may
help (a 4-card group of 2♦ 3♦ A♥ 5♦ is still a Color by its best three
cards).

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
top; two pair sits between Color and Pair.)*

## Scoring

| Event | Points |
|---|---|
| Win a group | 1 |
| Win all four groups in a round (sweep) | 5 in total *(interim: replaces the four 1-point wins)* |
| Show four of a kind | 4 (each one), round ends |
| Show six pairs | 6, round ends |
| Show three trails ("three trials") | 9, round ends |
| Show one card of every rank, A to K ("all thirteen different") | Match win |

**Showing a special hand.** While arranging (before the groups are
played), a player holding one of these hands can tap **Show**. The round
ends at once: the shower scores the points, nobody else scores, and the
next round is dealt. Showing all thirteen ranks wins the whole match.
Bots always show. A special hand that is not shown scores nothing.

Details *(interim)*:

- Special hands are judged on the **dealt** 13 cards.
- A hand with more than one special scores all of them together (for
  example four of a kind and three trails: 4 + 9).
- The first player to show ends the round; nobody else can show after.
- For six pairs, a four of a kind counts as two pairs and a trail as one.
- "Three trials" is read as three *trails* (three separate
  three-of-a-kinds).

## Winning *(interim)*

- The first player to reach **20 or more** wins.
- If several players pass 20 in the same round, the highest total wins.
- If the highest totals are tied, another round is played.
- As a safety valve the match stops after 100 rounds (highest score wins).

## Open questions for confirmation

These follow the interim answers above until confirmed:

1. "Three trials": is it three trails (three of a kind)?
2. A hand with two specials (say four of a kind and three trails): both, or the best one?
3. Does a sweep's 5 points replace the four group points or add to them?
4. If two players could show, does the first to show win, or the bigger special?
5. Is the target "20 or more"? What happens with a tie above 20?
6. Are exact ties broken by suit, or is the point split?
7. Where does two pair rank (see above)?

Confirmed by Bipul on 2026-10-26: groups are revealed automatically
once everyone is ready; special hands are shown during arranging and end
the round (4, 6, 9 points) or the match (all thirteen ranks); groups are
played strongest first with
the 4-card group anywhere; a 4-card group is named by the best hand in
it; a full 4-card hand beats a 3-card hand of the same kind; otherwise the fourth card is a spare that adds nothing.

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
| `bonusesStackWithGroupPoints` | true | Only with `declareBonuses` off: if false, a player gets the larger of bonus or group points |
| `allRanksInstantWin` | true | All thirteen ranks wins the match |
| `strongestFirst` | true | Groups are played strongest first (the engine orders them) |
| `declareBonuses` | true | Special hands score only when shown, which ends the round. If false, they score automatically at round end and all-ranks wins at the deal |
| `maxRounds` | 100 | Safety limit |
