# Releasing Chuchula on Google Play and the App Store

A step-by-step guide. Steps marked **YOU** need your accounts, money,
phones or a decision; everything else is already in the repository.

Checked against the store rules as of 29 October 2026 (Play production
steps in section 5.6 rechecked 12 November 2026). Store consoles
change their menus often, so follow the names below loosely.

## 0. What you need

| Item | Cost | Needed for |
|---|---|---|
| Google Play developer account | $25 once | Android |
| Apple Developer Program | $99 a year | iPhone |
| A Mac with Xcode, or a cloud Mac service (for example Codemagic) | - | Signing and uploading the iPhone build |
| Firebase project on the Blaze plan | Pay as you go; set a budget alert | Online play only. **Optional**: see "The free way to release" below |
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

## The free way to release (no Firebase bill)

Firebase is needed **only for Online play**. Offline play against bots,
Bluetooth play, cash points, the rewarded ad (AdMob, which pays you) and
everything else run without it. The Online play button only appears in
builds that have Firebase settings (`.env`). Without them it is hidden,
the app never contacts Firebase, and nothing can be billed.

Firebase's free **Spark** plan cannot run Cloud Functions, and the
online game's server logic (dealing, checking moves, bots) runs there.
Online play therefore needs the paid **Blaze** plan. Its cost for a small
game is usually cents a month, mostly for storing the deployed functions.
But it needs a card on file and is never guaranteed to be zero.

Cheapest path, using the Play Console account you already have:

1. Build **without** `.env`, or with the `FIREBASE_*` lines left empty:
   `flutter build appbundle --release`. The AdMob ids still go in as in
   section 3; they don't need Firebase. In CI, leave the `APP_ENV` secret
   out, or put only the `ADMOB_*` lines in it.
2. Stop the existing bill. In the Google Cloud console
   (<https://console.cloud.google.com/billing>), open **Reports** to see
   which service charged you. Then, in the Firebase console, either
   **delete the project** (Project settings > General > Delete project)
   or downgrade it to **Spark** (Usage and billing > Details & settings >
   Modify plan). Downgrading stops the functions, and Spark can never
   charge you.
3. Publish the privacy policy without a paid plan, in one of these ways:
   - Firebase **Hosting** on a **Spark** project is free and needs no
     card: `firebase deploy --only hosting` (skip
     `functions,firestore`).
   - Or paste `assets/legal/privacy_policy.md` into a free **Google
     Sites** page and use that address.
4. Skip section 2. In section 5.3, leave out the two Firebase rows (Name
   and User IDs).
5. Online play can come back later in an update: set up Firebase as in
   section 2 and build with `.env` again. No code change is needed.

Without Firebase, players lose only Online play with strangers or
friends far away. Friends in the same room can still play over
Bluetooth.

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

## 2. Firebase for online play (YOU, optional)

Skip this whole section for the free release above. Details and the data model are in `docs/FIREBASE_SETUP.md`. In short:

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

## 3. AdMob for the +50 reward and the match-end ad (YOU)

1. Sign up at <https://admob.google.com> with the same Google account.
2. **Apps > Add app**, once for Android and once for iOS. Before the store
   listings are live, answer "not published yet". Link the apps to their
   store listings later.
3. In each app, create an ad unit: **Rewarded**, reward amount 50, item
   "cash points" (or your new name). The app always adds exactly 50.
   The number in AdMob is only a label.
   Then create a second ad unit: **Interstitial**. The app shows it once
   when a whole match is over, as the player leaves the result (Home or
   Play again), never between rounds.
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
   | Android interstitial unit | `ca-app-pub-123.../333` | `ADMOB_INTERSTITIAL_ID` in `.env` |
   | iOS interstitial unit | `ca-app-pub-123.../444` | `ADMOB_INTERSTITIAL_ID_IOS` in `.env` |

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

The app itself collects only what online play needs (and nothing at all
in a build without Firebase). AdMob collects more. Google keeps the AdMob part up to date at
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
   then promote the release to **Production**. Section 5.6 walks through
   this step by step.

### 5.6 From internal testing to production (step by step)

You are here once the app runs from the **Internal testing** track. Each
step names where to click in Play Console; menus move around, so search
for the name if it isn't where described.

**Step 1. Check which kind of account you have.** Open **Settings >
Developer account > About you**. If it is a **personal** account created
after 13 November 2023, you must finish steps 2 to 4 before Google lets
you publish to production. If it is an **organisation** account, skip to
step 5.

**Step 2. Make the build you will ship.** Production gets the exact
bundle that testers used, so build it properly first:

- Real AdMob ids in the build (section 3), not Google's test ids.
- Signed with your upload key (section 4), and `version:` raised in
  `pubspec.yaml`, for example `1.0.0+2`.
- `.env` without `FIREBASE_*` lines if you follow "The free way to
  release".
- The match-end ad (shown after a whole match finishes, never in the
  middle of a round) must close normally with its own X and must not
  open by surprise when the player taps a button. Google's
  [Better Ads / disruptive ads policy](https://support.google.com/googleplay/android-developer/answer/9857753)
  rejects ads that appear unexpectedly or block the game. After a match
  is the allowed kind of spot.

**Step 3. Start a closed test with at least 12 testers.**

1. **Test and release > Testing > Closed testing > Create track** (or
   use the default "Alpha" track).
2. **Testers** tab: create an email list with **at least 12 Gmail
   addresses** (aim for 15 to 20, because some people forget to opt in
   or uninstall). Save, then copy the **opt-in link**.
3. **Countries/regions:** add Nepal, India and any others your testers
   are in. A tester in a country not on the list cannot install.
4. **Create new release:** upload the `.aab` from step 2 (or choose
   **Add from library** to reuse the internal-testing bundle), write
   release notes, then **Review release > Start rollout to Closed
   testing**. Google reviews the first closed release; this takes from
   a few hours to a few days.
5. Send each tester the opt-in link. They tap **Become a tester**, then
   **download it on Google Play**. They must use the same Gmail as on
   the list.

**Step 4. Keep 12 testers opted in for 14 days in a row.**

- The 14 days count from the day the 12th tester opts in. If someone
  leaves the test and you drop below 12, the count stops.
- Ask testers to keep the app installed and to actually play a few
  matches across the two weeks. In the production application Google
  asks how testers used the app and what you changed from their
  feedback, and thin answers are the most common reason for rejection.
- Collect feedback (the testers' **Play Store > Private feedback**, or a
  WhatsApp group) and ship at least one update to the closed track
  during the 14 days. Raise `version:` each time. Write down what each
  update fixed: you will paste it in step 6.
- **Dashboard** shows a progress bar for "12 testers, 14 days".

**Step 5. Finish everything on "Set up your app".** On the
**Dashboard**, every task under **Set up your app** must be ticked
(table in 5.2): privacy policy, app access, ads = **Yes**, content
rating, target audience (13+ only), data safety (5.3), advertising ID,
government app, financial features, health. And the **Main store
listing** (5.4) with icon, feature graphic and at least 2 phone
screenshots. An unticked item blocks the production release later.

**Step 6. Apply for production.** When the 14 days are done, the
Dashboard shows **Apply for production**. It asks three groups of
questions; answer in plain words:

- *About your closed test:* how you recruited testers (friends and
  family), how easy it was, how they used the app (for example "played
  offline matches against bots and Bluetooth games with 2 to 4 phones,
  watched the rewarded ad").
- *About your app:* who it is for (adults and teens who play the Nepali
  card game Chuchula), what makes it useful, expected installs in the
  first year (a modest honest number such as 1,000 to 10,000).
- *Production readiness:* what you changed from tester feedback (list
  the fixes from step 4), and how you decided it is ready.

Google usually replies within 7 days, by email and on the Dashboard. If
it says "more testing needed", keep the closed test running (the testers
can stay) and apply again after fixing what it points at.

**Step 7. Create the production release.**

1. **Test and release > Production > Countries/regions:** add the
   countries you want. Start with the ones you care about (Nepal,
   India, and where Nepali speakers live, such as the UAE, Qatar, Saudi
   Arabia, Malaysia, the UK, the US, Australia), or **Add all**.
2. **Production > Create new release > Add from library**, and choose
   the last bundle from the closed test. No new upload is needed if it
   was the final build.
3. Release name `1.0.0`, release notes in English (and Nepali if you
   like), for example "First release of Chuchula: play against bots or
   with friends over Bluetooth."
4. **Next > Review release.** Fix any red error. Yellow warnings (for
   example about deobfuscation files) can be ignored.
5. Choose a **staged rollout**: start at **20%**. Then **Start
   rollout to Production**. Google reviews it (a few hours to about 7
   days for a first release).
6. Optional: **Publishing overview > Managed publishing** on before
   step 5 lets you pick the moment it goes live after approval.

**Step 8. After it is live.**

- Check **Quality > Android vitals** for crashes and ANRs for 2 to 3
  days. If they look fine, open **Production > Releases** and raise the
  rollout to 50%, then 100%. If something is wrong, **Halt rollout**,
  fix, raise `version:`, and release the new bundle.
- In **AdMob > Apps**, link the Android app to its now-live Play listing
  ("Add store"). Ads start filling properly a few days after the
  listing is reviewed.
- Put `app-ads.txt` on the website listed in the store listing (section
  3, step 6), or AdMob limits the ads it serves.
- Future updates no longer need the 14-day test: upload to internal
  testing, check it, then **Promote release > Production**.

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
