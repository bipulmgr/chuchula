# Releasing Chuchula on Google Play and the App Store

A step-by-step guide. Steps marked **YOU** need your accounts, money,
phones or a decision; everything else is already in the repository.

Checked against the store rules as of 29 October 2026. Store consoles
change their menus often, so follow the names below loosely.

## 0. What you need

| Item | Cost | Needed for |
|---|---|---|
| Google Play developer account | $25 once | Android |
| Apple Developer Program | $99 a year | iPhone |
| A Mac with Xcode, or a cloud Mac service (for example Codemagic) | - | Signing and uploading the iPhone build |
| Firebase project on the Blaze plan | Pay as you go, small for a card game; set a budget alert | Online play |
| Google AdMob account | Free | Real ads and the +50 reward |
| 2 Android phones (ideally 4) and 1 iPhone | - | Real-device tests |
| 12 people with Android phones | - | Google's closed test for new personal accounts (section 5.5) |

Already done in the code:

- Android and iOS projects, bundle/package id `com.bipulmgr.chuchula`.
- App icon (all sizes), Play icon `store/play-icon-512.png`, feature
  graphic `store/feature-graphic-1024x500.png`, App Store icon
  `store/icon-1024.png`. Redraw with `python3 scripts/generate_icons.py`.
- Privacy policy: in the app under Settings > About > Privacy policy, and
  as a web page in `hosting/privacy.html` (section 2.6 publishes it).
- Rewarded ads with Google's consent form (UMP) and an Ad privacy choices
  entry in Settings.
- CI builds a signed Play bundle (`.aab`) and APKs, and checks that the
  iOS project builds.

## 1. Decide how the game presents cash points (YOU)

Chuchula is **not real-money gambling**: cash points cannot be bought,
sold, withdrawn or swapped for prizes. But players stake points on the
outcome of a match, which both stores call **simulated gambling**.
That is allowed, with these effects:

- **Google Play:** answer "yes" to simulated gambling in the content
  rating questionnaire. Expect a Teen / PEGI 12 style rating. Do not
  include children under 13 in the target audience: simulated gambling
  is not allowed in apps for children (the Families policy).
- **App Store:** the age rating questionnaire asks how often simulated
  gambling appears. "Infrequent" gives **13+**, "Frequent" gives **18+**.
  Since every offline match has a stake, the honest answer is probably
  "Frequent" (18+).
- **Wording:** keep "virtual", "free" and "no real money" in the listing,
  and never "win cash" or "bet". I recommend renaming "cash points" to
  "coins" or "chips" before release. Reviewers react to the word *cash*.
  The rename is one line per language in `scripts/l10n_source.py`.

## 2. Firebase for online play (YOU)

Details and the data model are in `docs/FIREBASE_SETUP.md`. In short:

1. Create a project at <https://console.firebase.google.com>, then
   upgrade it to **Blaze** and add a **budget alert** (for example $5).
2. **Authentication > Sign-in method:** enable **Anonymous**.
3. **Firestore Database:** create it in production mode. Choose a
   location near your players, for example `asia-south1` (Mumbai) for
   Nepal and India. The location cannot be changed later.
4. **Project settings > Your apps:** add three apps:
   - Android, package `com.bipulmgr.chuchula`
   - iOS, bundle id `com.bipulmgr.chuchula`
   - Web, any nickname

   No `google-services.json` or `GoogleService-Info.plist` is needed.
   Copy the values into `.env` (start from `.env.example`):
   `FIREBASE_API_KEY`, `FIREBASE_PROJECT_ID`,
   `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_STORAGE_BUCKET`, and the
   three app ids `FIREBASE_ANDROID_APP_ID`, `FIREBASE_IOS_APP_ID` and
   `FIREBASE_WEB_APP_ID`.
5. To run the functions near your players, create `functions/.env` with
   `FUNCTIONS_REGION=asia-south1`, and set
   `FIREBASE_FUNCTIONS_REGION=asia-south1` in the app's `.env`.
6. Deploy the server and the privacy page from the repository root:

   ```sh
   npm install -g firebase-tools
   firebase login
   cp .firebaserc.example .firebaserc     # put your project id in it
   (cd functions && npm ci)
   python3 scripts/build_privacy_page.py  # after any policy edit
   firebase deploy --only functions,firestore,hosting
   ```

   The privacy policy is now at
   `https://<project-id>.web.app/privacy`. Use that address in both
   stores.
7. In `assets/legal/privacy_policy.md`, replace `SUPPORT_EMAIL` with the
   support address you will show in the stores. Then run step 6's
   `build_privacy_page.py` and deploy `hosting` again.

**Check it works (YOU, two phones):** build with
`flutter run --release --dart-define-from-file=.env` on both phones.
Phone A taps **Play online > Create room**. Phone B enters the code and
joins. A taps **Start**, and the two empty seats become bots. Play a
round. Then close the app on B mid-round and reopen it. **Play online**
offers **Rejoin room ...**, and B gets its seat and cards back. A bot
plays for B after 60 seconds away.

The same flow with four players, a leaver and a rejoin passes in the
Firebase emulators (`cd functions && npm run test:e2e`). A real project
has not been tried yet.

## 3. AdMob for the +50 reward (YOU)

1. Sign up at <https://admob.google.com> with the same Google account.
2. **Apps > Add app**, once for Android and once for iOS. Before the store
   listings are live, answer "not published yet". Link the apps to their
   store listings later.
3. In each app, create an ad unit: **Rewarded**, reward amount 50, item
   "cash points" (or your new name). The app always adds exactly 50.
   The number in AdMob is only a label.
4. **Privacy & messaging:** create the **European regulations (GDPR)**
   message for both apps and publish it. The app already shows it to
   players in the EEA, the UK and Switzerland.
5. Put the ids into the build:

   | Id | Looks like | Where |
   |---|---|---|
   | Android app id | `ca-app-pub-123...~456` | Gradle property `admobAppId`: in `~/.gradle/gradle.properties` as `admobAppId=...`, or the `ADMOB_APP_ID_ANDROID` CI secret |
   | iOS app id | `ca-app-pub-123...~789` | `ios/Flutter/AdMob.xcconfig` |
   | Android rewarded unit | `ca-app-pub-123.../111` | `ADMOB_REWARDED_ID` in `.env` |
   | iOS rewarded unit | `ca-app-pub-123.../222` | `ADMOB_REWARDED_ID_IOS` in `.env` |

   Without them the app uses Google's test ids. Those show a "Test Ad"
   and **do** add the +50, so the flow can be checked now. They never
   earn money.
6. **app-ads.txt:** AdMob checks that the website in your store listing
   has an `app-ads.txt`. Copy `hosting/app-ads.txt.example` to
   `hosting/app-ads.txt`, put in your publisher id from **AdMob >
   Settings > Account information**, and run
   `firebase deploy --only hosting`. Use `https://<project-id>.web.app`
   as the website in both store listings.
7. While testing with your real ids, add your phones as **test devices**
   (AdMob > Settings > Test devices). Never tap your own live ads: that
   can get the AdMob account suspended.

New AdMob apps serve few ads until the store listing is linked and
reviewed, usually for a few days. Until then the app says "No ad is
available right now".

**How the ad looks in the app:** the **▶ +50** button next to the
balance on the home screen shows a spinner while the ad loads. The ad
fills the screen. When it is watched to the end and closed, the balance
goes up by 50 with a sound and a "+50 cash points added!" message. If
it is closed early, the message says no points were added. In debug
builds on a computer (web or Windows), a stand-in "Test ad" with a
5-second countdown appears, so the flow can be tried without a phone.

## 4. Android release build

### 4.1 Upload key (YOU, once, keep it forever)

```sh
keytool -genkey -v -keystore chuchula-upload.jks -keyalg RSA \
  -keysize 2048 -validity 10000 -alias chuchula
```

Store the `.jks` file and both passwords in a password manager and a
backup. Never commit them. Play App Signing (step 5.2) keeps the real
signing key at Google, so a lost upload key can be reset. It takes a
few days, though.

### 4.2 Build locally

Create `android/key.properties` (git-ignored):

```properties
storeFile=C:/Users/you/keys/chuchula-upload.jks
storePassword=...
keyAlias=chuchula
keyPassword=...
```

Then:

```sh
flutter build appbundle --release --dart-define-from-file=.env
# -> build/app/outputs/bundle/release/app-release.aab
```

### 4.3 Or let GitHub build it

In **GitHub > Settings > Secrets and variables > Actions**, add:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | The keystore as base64. Linux/macOS: `base64 -w0 chuchula-upload.jks`. Windows PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("chuchula-upload.jks"))` |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | `chuchula` |
| `ANDROID_KEY_PASSWORD` | Key password |
| `APP_ENV` | The whole content of your `.env` file |
| `ADMOB_APP_ID_ANDROID` | AdMob Android app id |

Every CI run then uploads `chuchula-release.aab` in the
**chuchula-apks** artifact. The "Verify APKs" step prints the signing
certificate. It should name you, not "Android Debug".

### 4.4 Before each upload

- Raise `version:` in `pubspec.yaml` (`1.0.1+2`). The number after `+`
  must go up for every upload.
- From 31 August 2026, Google Play takes only apps that target Android 16
  (API 36). The CI log prints `targetSdkVersion`. It must say 36 or
  higher. Flutter 3.47 sets this for you.

## 5. Google Play Console (YOU)

### 5.1 Create the app

<https://play.google.com/console> > **Create app**: name "Chuchula",
default language, **Game**, **Free**, then accept the declarations.

### 5.2 Set up your app (Dashboard)

| Section | Answer |
|---|---|
| Privacy policy | `https://<project-id>.web.app/privacy` |
| App access | All functionality is available without special access |
| Ads | **Yes, my app contains ads** |
| Content rating | Category Game. Answer yes to **simulated gambling** (see section 1). No violence, no user-to-user chat, no real-money gambling, no purchases. |
| Target audience | **13 and older** (13-15, 16-17, 18+) or **18+ only**. Do not pick any age under 13. |
| News app | No |
| Data safety | See 5.3 |
| Government app, Financial features, Health | No / none |
| Advertising ID | Yes, it is used, for **Advertising or marketing** (by AdMob) |
| App category | Games > **Card** |
| Store listing contact | Email (required), website `https://<project-id>.web.app` |

Turn on **Play App Signing** when you upload the first bundle. It is the
default.

### 5.3 Data safety form

The app itself collects only what online play needs. AdMob collects
more. Google keeps the AdMob part up to date at
<https://developers.google.com/admob/android/privacy/play-data-disclosure>.
Check that page as you fill this in.

| Data type | Collected | Shared | Why | Optional? |
|---|---|---|---|---|
| Personal info > **Name** (the nickname typed in Settings, online rooms only) | Yes | No | App functionality | Yes (only if you play online) |
| Personal info > **User IDs** (Firebase anonymous id) | Yes | No | App functionality | Yes (only online) |
| **Device or other IDs** (advertising id, AdMob) | Yes | Yes (Google, ads) | Advertising, analytics, fraud prevention | No |
| App activity > **App interactions** (ad views and taps, AdMob) | Yes | Yes | Advertising, analytics | No |
| App info and performance > **Diagnostics** (AdMob SDK) | Yes | Yes | Analytics, fraud prevention | No |
| Location > **Approximate location** (from the IP address, AdMob) | Yes, if the AdMob page says so | Yes | Advertising, fraud prevention | No |

Then:

- **Encrypted in transit:** Yes (HTTPS for Firebase and AdMob;
  Bluetooth play uses an encrypted, paired link).
- **Users can request deletion:** Yes. Online rooms delete themselves
  after about 2 hours. Uninstalling removes everything on the phone. The
  support email handles other requests.
- Bluetooth play sends nothing to any server, so it adds nothing here.

### 5.4 Store listing

| Field | Limit | Suggested |
|---|---|---|
| App name | 30 | Chuchula - Nepali Card Game |
| Short description | 80 | Arrange 13 cards into four groups and outplay friends, bots or players online. |
| Full description | 4000 | Rules in brief, offline bots (3 levels), online rooms with a code, Bluetooth with nearby Android phones, English and Nepali, and the line: "Cash points are virtual and free. They cannot be bought or exchanged for money." |
| App icon | 512 x 512 PNG | `store/play-icon-512.png` |
| Feature graphic | 1024 x 500 | `store/feature-graphic-1024x500.png` |
| Phone screenshots | 2-8, 9:16 | Home, arranging cards, the reveal, round summary, points table, online lobby. Take them on a phone. |

### 5.5 Testing tracks

1. **Internal testing** (up to 100 people, live within minutes): upload
   the `.aab` and add your own Gmail. Install it from the opt-in link and
   run the checks in section 7.
2. **Closed testing:** new personal developer accounts must run a closed
   test with at least **12 testers** who stay opted in for **14 days in a
   row** before Google allows production. Ask friends and family to join
   through the opt-in link and keep the app installed.
3. After the 14 days, choose **Apply for production** on the Dashboard,
   answer the short questions, wait for approval (usually a few days),
   then promote the release to **Production**.

## 6. Apple App Store (YOU)

### 6.1 One-time setup

1. Join the **Apple Developer Program** (<https://developer.apple.com>).
2. **Certificates, Identifiers & Profiles > Identifiers:** register the
   bundle id `com.bipulmgr.chuchula`.
3. **App Store Connect > Apps > +:** New App, platform iOS, name
   "Chuchula", bundle id above, SKU `chuchula`.
4. On the Mac, run `flutter pub get`, then open `ios/Runner.xcworkspace`
   in Xcode. Go to **Runner > Signing & Capabilities**, pick your
   **Team** and keep automatic signing.
5. Put the iOS AdMob app id into `ios/Flutter/AdMob.xcconfig`, and the
   iOS ad unit and Firebase iOS app id into `.env`.

### 6.2 Build and upload

```sh
flutter build ipa --release --dart-define-from-file=.env
# -> build/ios/ipa/Chuchula.ipa
```

Upload it with Apple's **Transporter** app, or with **Xcode >
Window > Organizer > Distribute App**. After processing (about 15
minutes) it shows up in **TestFlight**. Install it on your iPhone and
run section 7.

The app is iPhone only (it still runs on iPads, in a phone-sized
window). So you need **iPhone screenshots only**: 6.9-inch,
1320 x 2868, from 1 to 10 of them.

### 6.3 App Store Connect pages

| Page | Answer |
|---|---|
| Privacy Policy URL | `https://<project-id>.web.app/privacy` |
| Category | Games > Card (secondary: Board) |
| Age Rating | Simulated gambling: **Frequent** (18+) or **Infrequent** (13+), see section 1. Advertising: yes. Everything else: none. |
| App Privacy | Data used to track you: **No**. The app never shows the tracking (ATT) prompt, so AdMob does not use the IDFA. Data linked to you: User ID and Name (online play, app functionality). Data not linked to you: Coarse location, Product interaction, Advertising data, Diagnostics (AdMob, see <https://developers.google.com/admob/ios/privacy/data-disclosure>). |
| Export compliance | Already answered in Info.plist (`ITSAppUsesNonExemptEncryption = NO`) |
| Pricing | Free, all countries you want |

### 6.4 Notes for the reviewer

Paste something like this into **App Review Information > Notes**:

> Chuchula is a traditional Nepali card game. Offline play against bots
> needs no account. Online: tap Play online > Create room, then Start;
> empty seats are filled by bots, so one device is enough to test.
> Cash points are virtual, free, cannot be purchased and have no
> monetary value; players can earn more by watching an optional rewarded
> ad. Bluetooth play is available only in the Android version and is
> not shown on iOS.

### 6.5 Things Apple checks that the app already handles

- No login needed. Online play uses an anonymous account, so there is
  no account to delete (guideline 5.1.1(v) does not apply).
- The privacy policy is reachable inside the app (Settings).
- The ad consent form appears before ads in the EEA and the UK.
- No in-app purchases, so the coins cannot be bought.

## 7. Real-device checks before release (YOU)

| Check | How | Status |
|---|---|---|
| Rewarded ad | Phone build, tap ▶ +50, watch to the end: balance +50. Close one early: no points. | Works with Google test ads in tests; real phone not tried yet |
| Online, 2 phones | Section 2 "Check it works" | Emulators only so far |
| Bluetooth, 2-4 Android phones | Host: Bluetooth play > Host a game, then allow "make visible". Each guest: Join a game, tap the host's name, accept the pairing code on both phones. Host: Start. Play a round, then turn one guest's Bluetooth off and on again: it should reconnect within about 30 seconds. | Protocol tested in code with simulated connections; real phones not tried yet |
| Android 11 or older phone (if you have one) | Bluetooth join with Location off shows a hint to turn it on | Not tried |
| Sound and music | Settings > sound on, play a round | Not tried on a phone |
| iPhone | TestFlight build: offline match, online room, ad | iOS build checked in CI only |

## 8. After launch

- Every update: bump `version:`, update `CHANGELOG.md`, build, upload to
  internal testing first, then promote.
- Watch **Play Console > Android vitals** and **App Store Connect >
  TestFlight / Crashes** for crashes.
- Keep `functions` deployed from the same commit as the app release. The
  Dart and TypeScript engines must match: CI's parity test checks this.
