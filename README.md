# Chuchula (चुचुला)

An Android card game for four players, built with Flutter. Each player
gets 13 cards and splits them into three groups of 3 and one group of 4.
The groups are then played one at a time, Teen Patti style, and the
strongest group wins the point. The first player to 20 points wins.

- **Offline** against easy, medium or hard bots. Matches save and resume.
- **Bluetooth** with 2 to 4 phones nearby, no internet needed. Empty
  seats are filled by bots.
- **Online** with friends by room code, through your own Firebase
  project (optional).
- English and Nepali, four table themes, four card backs, sound, music
  and haptics.

The full rules are in [docs/GAME_RULES.md](docs/GAME_RULES.md). Some
rules still use interim interpretations, listed there with the open
questions.

## Quick start

```sh
flutter pub get
flutter run                                  # phone or emulator
flutter test                                 # all app and engine tests
flutter build apk --release                  # build/app/outputs/flutter-apk/
```

Every push also builds debug and release APKs in GitHub Actions
(artifact **chuchula-apks** on the workflow run).

To enable online play, set up Firebase
([docs/FIREBASE_SETUP.md](docs/FIREBASE_SETUP.md)), copy `.env.example`
to `.env`, fill it in, and add `--dart-define-from-file=.env`.

## Documentation

| Doc | Contents |
|---|---|
| [GAME_RULES](docs/GAME_RULES.md) | Rules, rankings, scoring, rule switches, open questions |
| [ARCHITECTURE](docs/ARCHITECTURE.md) | Engine, sessions, Bluetooth and online design, bots |
| [ANDROID_PERMISSIONS](docs/ANDROID_PERMISSIONS.md) | Every permission and why |
| [STORE_RELEASE](docs/STORE_RELEASE.md) | Step-by-step Google Play and App Store release, Firebase and AdMob setup |
| [BUILD_AND_RELEASE](docs/BUILD_AND_RELEASE.md) | Building, signing, CI artifacts, versioning |
| [TESTING](docs/TESTING.md) | Test suites, CI, manual device checklist |
| [FIREBASE_SETUP](docs/FIREBASE_SETUP.md) | Firebase project, deploying functions and rules |
| [CHANGELOG](CHANGELOG.md) | Release notes |

## Project layout

```
lib/game/       Rules engine (pure Dart)
lib/bots/       Bots
lib/features/   Screens
lib/multiplayer/ Bluetooth and online sessions
functions/      Cloud Functions (TypeScript engine port, rooms)
android/        Android app and Bluetooth bridge (Kotlin)
test/           Unit, integration, widget and parity tests
```

## Credits

Fonts: Mukta and Yatra One (SIL Open Font License, see
`assets/fonts/LICENSE.md`). Sounds and music are synthesized from scratch by
`scripts/generate_audio.py`.
