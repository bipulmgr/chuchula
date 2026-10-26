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
- Table with drag-and-drop or tap-to-swap arranging, suggestions, undo,
  sort, animations, sounds, music and haptics.
- Four table themes, four card backs, English and Nepali, reduced motion.
- Tests for the engine, bots, offline matches, the Bluetooth protocol,
  screens, the table, engine parity, security rules and a full online
  match in the Firebase emulators.
