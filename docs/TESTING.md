# Testing

## Flutter (app and engine)

```sh
flutter pub get
dart format --output=none --set-exit-if-changed $(git ls-files '*.dart')
flutter analyze
flutter test
```

| Suite | What it covers |
|---|---|
| `test/unit/hand_evaluator_test.dart` | Every category, run edge cases (A-K-Q, A-2-3, no wraparound), tie-breaks, 3- vs 4-card order |
| `test/unit/game_engine_test.dart` | Deal, validation errors, turn order, group resolution, scoring, bonuses, sweeps, instant win, void deal, match end, rule switches |
| `test/unit/bot_test.dart` | Every difficulty makes legal arrangements, medium keeps a trail together, stronger bots beat easy ones over many rounds. (Bots only accept a `PlayerView`, so they cannot see hidden cards by construction.) |
| `test/integration/offline_match_test.dart` | Full matches against each difficulty, save/resume, corrupt saves, pause, rejected moves |
| `test/integration/bluetooth_protocol_test.dart` | Host/client protocol over in-memory sockets: joining, private views, spoofed moves, reconnects, bot takeover, version check |
| `test/widget/screens_test.dart` | Home, rules, settings (audio, theme, card back, Nepali), online without config, Bluetooth permission flow |
| `test/widget/table_test.dart` | The table: 13 cards in groups, tap and drag swaps, Ready, playing each group, scores, next round |
| `test/parity/parity_fixtures_test.dart` | Checks the Dart engine against the shared parity fixtures |

## Cloud Functions

```sh
cd functions
npm ci
npm test            # engine, parity with Dart, rooms, server bot
npm run test:rules  # firestore.rules in the Firestore emulator (needs Java)
npm run test:e2e    # a full 2-player match through the Functions emulator
```

## Changing the rules

If you change the engine on purpose, change both engines, then
regenerate the fixtures and run both suites:

```sh
UPDATE_PARITY=1 flutter test test/parity/parity_fixtures_test.dart
flutter test && (cd functions && npm test)
```

## CI

`.github/workflows/ci.yml` runs on every push and pull request:

- **Analyze and test:** formatting, `flutter analyze`, `flutter test`.
- **Cloud Functions and Firestore rules:** the three npm suites above.
- **Build APKs:** debug and release APKs, then checks each one with
  `aapt2` (package, SDK levels, permissions) and `apksigner`, and uploads
  them as the `chuchula-apks` artifact.

## Not covered by automated tests

- Real Bluetooth between two phones. The protocol is tested over
  in-memory connections and the Kotlin bridge compiles in CI, but radio
  behaviour must be checked on devices.
- Online play against a real Firebase project (the emulator test covers
  the same code paths).
- Audio output and haptics on a device.

### Manual device checklist

1. Install the APK, play an offline match on each difficulty.
2. Drag and tap to rearrange; Ready; play all groups; check the summary.
3. Leave mid-match, reopen the app, resume.
4. Settings: music, effects, haptics, theme, card back, Nepali.
5. Bluetooth with 2 to 4 phones: allow, deny then open settings, host,
   join, play, turn one phone's Bluetooth off and on mid-round.
6. Online with a configured build: create, join by code, play, leave.
