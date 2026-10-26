# Changelog

## 1.0.0 (unreleased)

First version.

- Points table: every round's points per player and the totals, from the
  table's top bar and the round and match summaries.
- Cash points (virtual, no money value) for offline matches: start with
  100, +50 for watching a rewarded ad, at least 50 to start a match. At
  the end, 2nd pays the winner 20, 3rd pays 30 and last pays 50.

- Rules engine for 4 players: 13 cards in 3/3/3/4 groups, Teen Patti
  style ranking, sweeps, hand bonuses, instant win, 20-point match. Rules
  that still need confirmation are switches (see docs/GAME_RULES.md).
- Offline play against easy, medium and hard bots, with save and resume.
- Bluetooth play for 2 to 4 phones (one host), with reconnects and a bot
  taking over a seat that does not come back.
- Online play through Firebase: anonymous sign-in, room codes, server
  authoritative Cloud Functions, private per-player views.
- The three 3-card groups are played strongest first and the 4-card
  group last; it must be the weakest group (Ready is refused otherwise).
  3- and 4-card groups rank on one ladder: a 4-card group is named by the
  best hand in it, and a full 4-card color, run or double run beats any
  3-card hand of that kind. Otherwise the fourth card is a spare that
  adds nothing.
- Once everyone is Ready, groups are revealed automatically.
- Special hands are shown from the Show menu while arranging: the player
  picks four of a kind +4, six pairs +6, three trails +9 (each ends the
  round) or all thirteen ranks (wins the match), and the pick is checked.
  Nothing hints at the hand beforehand. Bots show theirs too.
- Table with drag-and-drop or tap-to-swap arranging (single cards or
  whole groups), suggestions, undo, sort, animations, sounds, music and
  haptics.
- Four table themes, four card backs, three music tracks, three sound
  styles, English and Nepali, reduced motion, and a switch to hide
  Suggest. Bots get random names each game.
- Dealing animation: the deck is riffled, then cards arc to each seat
  and land in your hand one by one.
- Tests for the engine, bots, offline matches, the Bluetooth protocol,
  screens, the table, engine parity, security rules and a full online
  match in the Firebase emulators.
