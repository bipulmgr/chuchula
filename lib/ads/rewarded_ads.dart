import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// How a rewarded ad ended.
enum AdOutcome {
  /// Watched to the end: the player earns the reward.
  rewarded,

  /// The ad showed but was closed before the reward.
  closedEarly,

  /// No ad could be loaded or shown (offline, no fill, no consent).
  unavailable,
}

/// Rewarded video ads that top up cash points.
abstract class RewardedAds {
  const RewardedAds();

  /// Whether this platform can show ads at all.
  bool get supported;

  /// Asks for ad consent where the law needs it, starts the ads SDK and
  /// loads the first ad, so a later [show] opens at once. Safe to call
  /// more than once.
  Future<void> prepare() async {}

  /// Shows one ad over [context].
  Future<AdOutcome> show(BuildContext context);

  /// Whether the player must be offered a way to change ad consent
  /// (Settings shows "Ad privacy choices" when true).
  Future<bool> privacyOptionsRequired() async => false;

  /// Opens the consent form again.
  Future<void> showPrivacyOptions() async {}
}

/// Platforms without ads (release web and desktop builds).
class NoRewardedAds extends RewardedAds {
  const NoRewardedAds();

  @override
  bool get supported => false;

  @override
  Future<AdOutcome> show(BuildContext context) async => AdOutcome.unavailable;
}

/// Picks the ads for this build: AdMob on Android and iOS, and a stand-in
/// test ad in debug builds elsewhere (web, Windows), so the +50 flow can be
/// tried on a computer.
RewardedAds platformRewardedAds() {
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    return AdMobRewardedAds();
  }
  return kReleaseMode ? const NoRewardedAds() : DemoRewardedAds();
}

/// Google AdMob rewarded ads (Android and iOS).
///
/// Ad units come from `--dart-define=ADMOB_REWARDED_ID=...` (Android) and
/// `--dart-define=ADMOB_REWARDED_ID_IOS=...` (iOS). Without them, Google's
/// public test units are used: they show a real-looking "Test Ad" and do
/// grant the reward, but earn no money. The app ids are set in
/// android/app/build.gradle.kts and ios/Runner/Info.plist.
///
/// Consent: before any ad is requested, Google's User Messaging Platform
/// shows the consent form to players in regions that need one (EEA, UK,
/// Switzerland). The form's wording is set up in the AdMob console.
class AdMobRewardedAds extends RewardedAds {
  AdMobRewardedAds();

  static const androidTestUnitId = 'ca-app-pub-3940256099942544/5224354917';
  static const iosTestUnitId = 'ca-app-pub-3940256099942544/1712485313';
  static const androidUnitId = String.fromEnvironment(
    'ADMOB_REWARDED_ID',
    defaultValue: androidTestUnitId,
  );
  static const iosUnitId = String.fromEnvironment(
    'ADMOB_REWARDED_ID_IOS',
    defaultValue: iosTestUnitId,
  );

  static String get unitId =>
      defaultTargetPlatform == TargetPlatform.iOS ? iosUnitId : androidUnitId;

  /// Whether this build still uses Google's test ad units.
  static bool get usingTestAds =>
      unitId == androidTestUnitId || unitId == iosTestUnitId;

  /// A loaded ad expires after an hour; reload a little before that.
  static const _maxAge = Duration(minutes: 50);
  static const _loadTimeout = Duration(seconds: 20);

  Future<bool>? _ready;
  RewardedAd? _ad;
  DateTime? _loadedAt;
  Future<RewardedAd?>? _loading;

  @override
  bool get supported => true;

  @override
  Future<void> prepare() async {
    if (await (_ready ??= _consentAndInit())) _preload();
  }

  /// Runs the consent flow, then starts the SDK. Completes with whether
  /// ads may be requested.
  Future<bool> _consentAndInit() async {
    final info = ConsentInformation.instance;
    final updated = Completer<void>();
    info.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      updated.complete,
      (e) {
        debugPrint('Ad consent update failed: ${e.message}');
        updated.complete();
      },
    );
    await updated.future;
    await ConsentForm.loadAndShowConsentFormIfRequired((e) {
      if (e != null) debugPrint('Ad consent form: ${e.message}');
    });
    if (!await info.canRequestAds()) {
      // Ask again next time instead of keeping the refusal for the session.
      _ready = null;
      return false;
    }
    await MobileAds.instance.initialize();
    return true;
  }

  void _preload() {
    final fresh =
        _loadedAt != null && DateTime.now().difference(_loadedAt!) < _maxAge;
    if (_ad != null && fresh) return;
    _ad?.dispose();
    _ad = null;
    _loading ??= _load().then((ad) {
      _loading = null;
      _ad = ad;
      _loadedAt = ad == null ? null : DateTime.now();
      return ad;
    });
  }

  Future<RewardedAd?> _load() {
    final done = Completer<RewardedAd?>();
    RewardedAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: done.complete,
        onAdFailedToLoad: (e) {
          debugPrint('Rewarded ad failed to load: ${e.code} ${e.message}');
          done.complete(null);
        },
      ),
    );
    return done.future.timeout(_loadTimeout, onTimeout: () => null);
  }

  @override
  Future<AdOutcome> show(BuildContext context) async {
    await prepare();
    if (await _ready != true) return AdOutcome.unavailable;
    _preload();
    final ad = _ad ?? await _loading;
    _ad = null;
    _loadedAt = null;
    if (ad == null) {
      // Try again in the background so the next tap is quicker.
      _preload();
      return AdOutcome.unavailable;
    }

    final done = Completer<AdOutcome>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        if (!done.isCompleted) {
          done.complete(earned ? AdOutcome.rewarded : AdOutcome.closedEarly);
        }
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        debugPrint('Rewarded ad failed to show: ${e.message}');
        a.dispose();
        if (!done.isCompleted) done.complete(AdOutcome.unavailable);
      },
    );
    await ad.show(onUserEarnedReward: (_, _) => earned = true);
    final outcome = await done.future;
    _preload();
    return outcome;
  }

  @override
  Future<bool> privacyOptionsRequired() async {
    try {
      return await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> showPrivacyOptions() async {
    final done = Completer<void>();
    await ConsentForm.showPrivacyOptionsForm((e) {
      if (e != null) debugPrint('Ad privacy options: ${e.message}');
      done.complete();
    });
    await done.future;
    // Consent may have changed either way.
    _ready = null;
  }
}

/// A stand-in rewarded ad for debug builds without AdMob (web, desktop):
/// a full-screen "Test ad" with a countdown, which grants the reward only
/// when watched to the end, like the real one.
class DemoRewardedAds extends RewardedAds {
  DemoRewardedAds({this.length = const Duration(seconds: 5)});

  final Duration length;

  @override
  bool get supported => true;

  @override
  Future<AdOutcome> show(BuildContext context) async {
    final watched = await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<bool>(
        opaque: true,
        fullscreenDialog: true,
        pageBuilder: (_, _, _) => DemoAdScreen(length: length),
      ),
    );
    return watched == true ? AdOutcome.rewarded : AdOutcome.closedEarly;
  }
}

class DemoAdScreen extends StatefulWidget {
  const DemoAdScreen({super.key, required this.length});

  final Duration length;

  @override
  State<DemoAdScreen> createState() => _DemoAdScreenState();
}

class _DemoAdScreenState extends State<DemoAdScreen> {
  late int _left = widget.length.inSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _left--);
      if (_left <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = _left <= 0;
    return Scaffold(
      key: const Key('demoAd'),
      backgroundColor: const Color(0xFF101418),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.ondemand_video,
                    size: 72,
                    color: Colors.white70,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Test ad',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    done ? 'Reward earned' : 'Reward in $_left s',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Debug builds only. Phones show a real AdMob test ad.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                key: const Key('closeDemoAd'),
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(done),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
