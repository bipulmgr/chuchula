import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Rewarded video ads that top up cash points.
abstract class RewardedAds {
  /// Whether this platform can show ads at all.
  bool get supported;

  /// Loads and shows one ad. Completes with true only when the player
  /// watched it to the end and earned the reward.
  Future<bool> show();
}

/// Platforms without ads (web, desktop, tests).
class NoRewardedAds implements RewardedAds {
  const NoRewardedAds();

  @override
  bool get supported => false;

  @override
  Future<bool> show() async => false;
}

/// Google AdMob rewarded ads (Android).
///
/// The ad unit comes from `--dart-define=ADMOB_REWARDED_ID=...`. Without
/// it, Google's public test unit is used, which shows test ads and never
/// pays out. The app id is set in android/app/build.gradle.kts.
class AdMobRewardedAds implements RewardedAds {
  AdMobRewardedAds();

  static const testUnitId = 'ca-app-pub-3940256099942544/5224354917';
  static const unitId = String.fromEnvironment(
    'ADMOB_REWARDED_ID',
    defaultValue: testUnitId,
  );

  Future<void>? _init;

  @override
  bool get supported => true;

  @override
  Future<bool> show() async {
    await (_init ??= MobileAds.instance.initialize());
    final ad = Completer<RewardedAd?>();
    await RewardedAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: ad.complete,
        onAdFailedToLoad: (_) => ad.complete(null),
      ),
    );
    final loaded = await ad.future;
    if (loaded == null) return false;

    final done = Completer<bool>();
    var earned = false;
    loaded.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        if (!done.isCompleted) done.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (a, _) {
        a.dispose();
        if (!done.isCompleted) done.complete(false);
      },
    );
    await loaded.show(onUserEarnedReward: (_, _) => earned = true);
    return done.future;
  }
}
