# Build and release

## Requirements

- Flutter 3.47.8 (Dart 3.13), Android SDK with platform 36, JDK 17.
- Node 22 and Java 21 only for the Cloud Functions and their emulator tests.

The app targets Android 7.0 (API 24) and up, portrait only. The package
id is `com.bipulmgr.chuchula`.

## Debug build

```sh
flutter pub get
flutter run                    # on a connected phone or emulator
flutter build apk --debug      # build/app/outputs/flutter-apk/app-debug.apk
```

Add `--dart-define-from-file=.env` to enable online play (see
`docs/FIREBASE_SETUP.md`). Without it, online play shows a "not set up"
message and everything else works.

## Release build

1. Create an upload keystore once and keep it safe, outside the repo:

   ```sh
   keytool -genkey -v -keystore ~/chuchula-release.jks -keyalg RSA \
     -keysize 2048 -validity 10000 -alias chuchula
   ```

2. Create `android/key.properties` (git-ignored):

   ```properties
   storeFile=/home/you/chuchula-release.jks
   storePassword=...
   keyAlias=chuchula
   keyPassword=...
   ```

3. Build:

   ```sh
   flutter build apk --release --dart-define-from-file=.env
   flutter build appbundle --release --dart-define-from-file=.env   # for Play
   ```

Without a keystore, the release build is signed with the debug key and
Gradle prints a warning. Such an APK is fine for testing but cannot be
published or updated on Google Play.

Never commit keystores, `key.properties`, `.env` or any service-account
JSON. `.gitignore` excludes them.

## Rewarded ads (cash points)

Cash points can be topped up by watching a Google AdMob rewarded ad. Out
of the box the app uses Google's public **test** ids, which only show
test ads and earn nothing. For real ads, create an AdMob app and a
rewarded ad unit, then build with both ids:

```sh
flutter build apk --release \
  -PadmobAppId=ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY \
  --dart-define=ADMOB_REWARDED_ID=ca-app-pub-XXXXXXXXXXXXXXXX/ZZZZZZZZZZ
```

- The app id goes into the manifest through `admobAppId` in
  `android/app/build.gradle.kts` (a Gradle property, so it can also live
  in `~/.gradle/gradle.properties`).
- The ad unit id is read in `lib/ads/rewarded_ads.dart`
  (`ADMOB_REWARDED_ID`).
- Before publishing, declare ads and the advertising id in the Play
  Console (see docs/ANDROID_PERMISSIONS.md).

Ads are Android only; on other platforms the +50 button explains that.

## Releases from CI

Every push builds debug and release APKs in GitHub Actions and uploads
them as the **chuchula-apks** artifact on the workflow run. The verify step
prints each APK's size, SHA-256, package info, permissions and signing
certificate.

To sign CI releases with your key, add these repository secrets:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 chuchula-release.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Key alias |
| `ANDROID_KEY_PASSWORD` | Key password |

## Versioning

Bump `version:` in `pubspec.yaml` (`1.0.0+1` is name `1.0.0`, code 1)
and add an entry to `CHANGELOG.md`. The version code must increase for
every Play upload.

## Install on a phone

Download `chuchula-release.apk` from the workflow artifact, copy it to the
phone, and open it (allow installs from that app when asked), or:

```sh
adb install -r chuchula-release.apk
```
