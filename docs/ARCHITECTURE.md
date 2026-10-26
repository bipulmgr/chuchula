# Architecture

```
lib/
  game/        Pure Dart rules engine (no Flutter imports)
    models/    Cards, GameState, PlayerView, moves
    rules/     Hand evaluator, bonuses, RuleConfig
    scoring/   Round scoring and match end
    engine/    ChuchulaGameEngine, RandomSource
    state/     GameSession: the interface the table talks to
  bots/        Easy, medium and hard bots (see "Bots")
  multiplayer/
    local/     Bluetooth host lobby, client session, line protocol
    bluetooth/ Platform channel to the Kotlin RFCOMM bridge
    online/    Firebase client (callables + Firestore listeners)
  features/    Screens: home, table, results, settings, lobbies, tutorial
  widgets/     Cards, felt, gold panels
  audio/       Music and sound effects
  persistence/ Settings, saved match, stats (shared_preferences)
functions/     Cloud Functions: TypeScript engine port, rooms, server bot
android/       Android app, including BluetoothBridge.kt
```

## One engine, one authority

The engine is pure, immutable and deterministic for a given
`RandomSource`. Every accepted move returns a new `GameState` with a
higher `version`. Invalid moves are rejected with a `RuleError` code,
which the UI localizes.

`GameState` holds every hand, so it lives only on the **authority**:

| Mode | Authority | Clients receive |
|---|---|---|
| Offline | `AuthorityGameSession` on the phone | (none) |
| Bluetooth | The host phone (`AuthorityGameSession` + `HostLobby`) | Their own `PlayerView` over RFCOMM |
| Online | Cloud Functions | Their own `PlayerView` in `rooms/{id}/views/{uid}` |

`PlayerView.of(state, seat)` contains only that seat's hand plus what has
been revealed to everyone. The table UI and the bots consume
`PlayerView`, never `GameState`, so hidden cards cannot leak to the screen
or to a bot. Tests check that serialized views never contain another
seat's cards.

## Sessions

`GameSession` is what `TableScreen` uses: a `ValueListenable<PlayerView>`,
per-seat connection states, an event stream (rejections, connection lost
or restored) and three actions (submit arrangement, play group, next round).

- `AuthorityGameSession` runs the engine, paces bots (`BotTiming`), runs
  bot thinking in an isolate, pauses when the app is in the background,
  and saves offline matches after each move.
- `RemoteGameSession` is the Bluetooth client. It reconnects with backoff
  and reclaims its seat by client id.
- `OnlineGameSession` listens to the player's view document, sends moves
  through `submitMove`, and sends heartbeats every 15 s.

## Bluetooth

Classic Bluetooth RFCOMM in a star: the host listens on a fixed service
UUID and up to three phones connect. Messages are one JSON object per
line (`hello`, `welcome`, `lobby`, `view`, `move`, `error`, `ping`/`pong`,
`bye`), with a protocol version check. The host validates every move and
only accepts moves for the sender's own seat. A dropped player keeps their
seat for a grace period (60 s). After that a medium bot plays for them until
they reconnect.

## Online

See `docs/FIREBASE_SETUP.md` for setup. Clients never write to Firestore;
`firestore.rules` denies all client writes. Every action is a callable
function that loads the room and private state in a transaction, applies
the move with the TypeScript engine, lets bots act, and writes the room,
the private state and one view per player. State and views are stored as
JSON text because Firestore cannot store nested arrays.

The TypeScript engine (`functions/src/engine`) is a port of the Dart
engine. `test/parity/parity_fixtures_test.dart` records Dart results
(group strengths, bonuses, three full matches with a hash of every state)
in `functions/test-fixtures/parity.json`, and
`functions/src/test/parity.test.ts` replays them. The two engines must
agree move for move.

Players who stop sending heartbeats for 60 s are marked away and a server
bot plays for them. A heartbeat gives the seat back. Rooms idle for two
hours are deleted by a scheduled function.

## Bots

Bots only receive their own `PlayerView`.

- **Easy** usually sorts its hand by rank and cuts it into groups, and
  sometimes groups at random.
- **Medium** searches the strongest four-card candidates and every split
  of the rest, scoring each group by how likely it is to beat a random
  group of the same size (precomputed strength tables).
- **Hard** also estimates what opponents can hold by sampling the cards it
  has not seen (Monte Carlo over unseen cards only), and adapts to the
  score: it chases sweeps when behind.
- The **server bot** (online) uses a simpler exhaustive search over all
  3-3-3-4 splits with a category-based score.
