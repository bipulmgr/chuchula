# Changelog

## 1.0.0 (unreleased)

First version.

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
- Special hands are shown with the Show button (always next to Suggest)
  while arranging: four of a
  kind +4, six pairs +6, three trails +9 end the round; all thirteen
  ranks wins the match. Bots show theirs too.
- Table with drag-and-drop or tap-to-swap arranging (single cards or
  whole groups), suggestions, undo, sort, animations, sounds, music and
  haptics.
- Four table themes, four card backs, English and Nepali, reduced motion.
- Tests for the engine, bots, offline matches, the Bluetooth protocol,
  screens, the table, engine parity, security rules and a full online
  match in the Firebase emulators.
