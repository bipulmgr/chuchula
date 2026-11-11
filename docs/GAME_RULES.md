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
3. **Order.** The three 3-card groups are played **strongest first**
   (groups 1 to 3), and the **4-card group is always played last** (group
   4). The 4-card group must be the player's **weakest** group: weaker
   than each of the three 3-card groups. For this check the 4-card group
   counts as its **best three cards** (a 4-card color A-J-8-7 counts as
   the color A-J-8, so it may sit under a 3-card color A-J-9; the same for
   a double pair or a 4-card run). Against other players it still plays
   as a full 4-card hand. The app puts the groups in this
   order when Ready is pressed, and refuses Ready (as do the engine and
   server) while the 4-card group is stronger than a 3-card group. Only a
   hand that cannot be arranged that way at all (very rare) may play a
   stronger 4-card group last.
4. **Play.** Once all four players are ready, the groups are revealed
   automatically, with no taps: everyone's group 1 is played. The player after the dealer reveals first, then the others in
   turn. The strongest group wins the point and its owner leads the next
   group. This repeats for groups 2, 3 and 4. Group 4 is everyone's
   4-card group.
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
with it gains nothing. The 4-card group is the weakest group anyway, so
Suggest and the bots use it for the leftover cards.

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
| Last group (group 4) is a double run | Match win |

**Double run in the last group.** When the groups of a round are all
played and a player's last group is a double run (its best hand is a run
in one suit), that player wins the whole match, not just the round. If
several players have one, the strongest double run wins.

To show, tap **Show** (the ✨ button) while arranging and pick the special
from its menu. The app gives no hint about which special the hand holds.
The pick is checked against the dealt cards: if the hand has it, the round
ends and **only the picked kind scores** (two fours of a kind score 4 each);
if not, nothing is shown and the player carries on arranging.

**Showing a special hand.** While arranging (before the groups are
played), a player holding one of these hands can tap **Show**. The other
players then get **20 seconds** to show a special of their own or pass.
When everyone has answered, or the time is up, the best special shown
wins the round: its owner scores its points and nobody else scores.
Specials rank: all thirteen ranks, then three trails, six pairs, four of a
kind. Two of the same kind compare by rank (four kings beat four nines;
for trails and pairs the highest one decides first). If they are still
equal, the one shown first wins. Showing all thirteen ranks wins the
whole match at once. Bots always show, and answer at once. A special hand
that is not shown scores nothing. In the round summary only the cards
that make each special are highlighted.

Details *(interim)*:

- Special hands are judged on the **dealt** 13 cards.
- A hand with more than one special scores only the kind the player
  picks (bots pick the most valuable).
- After the first show, the others have 20 seconds to answer
  (`showWindowSeconds`).
- For six pairs, a four of a kind counts as two pairs and a trail as one.
- "Three trials" is read as three *trails* (three separate
  three-of-a-kinds).

## Winning *(interim)*

- The first player to reach **20 or more** wins.
- If several players pass 20 in the same round, the highest total wins.
- If the highest totals are tied, another round is played.
- As a safety valve the match stops after 100 rounds (highest score wins).

## Cash points

Cash points are a virtual balance for offline matches against bots. They
have no money value: they cannot be bought, sold or cashed out.

- Every player starts with **100**.
- Watching a rewarded ad to the end adds **50** (Android app only). An ad
  that fails to load or is closed early adds nothing.
- A new match is played on a **board**: 100, 200, 500, 1K, 2K or 10K.
  The board is what the winner collects. Sitting at a board needs its
  largest loss, half the board: 50 for 100, 100 for 200, 250 for 500,
  500 for 1K, 1,000 for 2K and 5,000 for 10K. Below 50, the app offers an
  ad. Boards the balance cannot cover are greyed out on the New Match
  screen.
- At the end of a match the losers pay the winner by finishing place. On
  the 100 board **2nd pays 20, 3rd pays 30, last pays 50**, so the winner
  gains 100; bigger boards scale this (the 1K board pays 200, 300, 500).
  Places after the winner follow final scores. Players tied on score
  split the payments of the places they span evenly, rounded down (two
  tied for 2nd and 3rd pay 25 each); the winner receives exactly what is
  paid.
- A match is settled once, when it ends. The match-over screen shows each
  player's gain or loss and your new balance. Bots' balances are not kept
  between matches.
- Online and Bluetooth matches are not played for cash points yet.

## Points table

The points table (the 📊 button at the top of the table, or **Points
table** on the round and match summaries) lists each round's points per
player and the running totals.

## Open questions for confirmation

These follow the interim answers above until confirmed:

1. "Three trials": is it three trails (three of a kind)?
2. A hand with two specials (say four of a kind and three trails): the app now scores only the one the player picks. Should both count?
3. Does a sweep's 5 points replace the four group points or add to them?
4. If two players could show, does the first to show win, or the bigger special?
5. Is the target "20 or more"? What happens with a tie above 20?
6. Are exact ties broken by suit, or is the point split?
7. Where does two pair rank (see above)?

Confirmed by Bipul on 2026-10-26: groups are revealed automatically
once everyone is ready; special hands are shown during arranging and end
the round (4, 6, 9 points) or the match (all thirteen ranks); the three
3-card groups are played strongest first and the 4-card group last, as
the weakest group; a 4-card group is named by the best hand in
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
| `strongestFirst` | true | 3-card groups are played strongest first, then the 4-card group (the engine orders them) |
| `fourCardWeakest` | true | The 4-card group must be weaker than every 3-card group, unless the hand allows no such arrangement |
| `declareBonuses` | true | Special hands score only when shown, which ends the round. If false, they score automatically at round end and all-ranks wins at the deal |
| `showWindowSeconds` | 20 | After a show, how long the others have to show theirs. 0 ends the round at the first show |
| `lastGroupDoubleRunWins` | true | A double run in the last group wins the match |
| `maxRounds` | 100 | Safety limit |
