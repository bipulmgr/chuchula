# Firebase setup (online play)

Online play needs your own Firebase project on the paid Blaze plan
(Cloud Functions do not run on the free Spark plan). Without it the app
still builds and runs, and the Online play button is hidden. Offline and Bluetooth play never need Firebase.

## 1. Create the project

1. Create a project at <https://console.firebase.google.com>.
2. **Build → Authentication → Sign-in method:** enable **Anonymous**.
3. **Build → Firestore Database:** create a database in production mode.
4. Cloud Functions need the **Blaze** (pay as you go) plan. Normal play
   uses a few function calls per move; set a budget alert.
5. **Project settings → Your apps:** add an Android app (package
   `com.bipulmgr.chuchula`), an iOS app (bundle id
   `com.bipulmgr.chuchula`) and a Web app. No `google-services.json` or
   `GoogleService-Info.plist` is needed. Copy `apiKey`,
   `messagingSenderId`, `projectId` and `storageBucket` into `.env`, and
   each app's `appId` into `FIREBASE_ANDROID_APP_ID`,
   `FIREBASE_IOS_APP_ID` and `FIREBASE_WEB_APP_ID` (see `.env.example`).
   `FIREBASE_APP_ID` alone also works: it is used for any platform
   without its own id.

## 2. Deploy the server

```sh
npm install -g firebase-tools
firebase login
cp .firebaserc.example .firebaserc   # put your project id in it
cd functions && npm ci && cd ..
firebase deploy --only functions,firestore,hosting
```

This deploys the callables (`createRoom`, `joinRoom`, `leaveRoom`,
`startMatch`, `submitMove`, `heartbeat`), the `cleanupRooms` schedule,
`firestore.rules` and its index, and the privacy policy page in
`hosting/`. The default region is `us-central1`. To change it, set
`FUNCTIONS_REGION` in `functions/.env` for the functions and `FIREBASE_FUNCTIONS_REGION` in
`.env` to the same value.

No service-account keys are needed or stored: deployed functions use
their runtime identity.

## 3. Build the app

```sh
flutter build apk --release --dart-define-from-file=.env
```

## Data model

| Path | Contents | Who can read |
|---|---|---|
| `rooms/{id}` | Code, host, status, seat names, heartbeats | Any signed-in player |
| `rooms/{id}/private/state` | Full game state, all hands | Nobody (functions only) |
| `rooms/{id}/views/{uid}` | That player's view (their hand + public table) | Only that player |

Clients cannot write anything. Every change goes through a function,
which validates the move with the rules engine.

## Local emulators

```sh
cd functions
npm run serve          # Functions, Firestore and Auth emulators
```

Then run the app with `FIREBASE_EMULATOR_HOST=10.0.2.2` (Android
emulator) or your computer's LAN address (real phone), plus any values
for the other keys and `FIREBASE_PROJECT_ID=demo-chuchula`.
