import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'rewarded_ads.dart';

/// A full-screen ad shown once when a whole match is over, as the player
/// leaves the match result (never between rounds).
abstract class MatchEndAds {
  const MatchEndAds();

  /// Loads an ad in the background so [show] opens at once. Safe to call
  /// more than once.
  void preload() {}

  /// Shows one ad over [context] and completes when it is closed, or at
  /// once when no ad is available. Never throws.
  Future<void> show(BuildContext context);
}

/// Builds without ads (release web and desktop, and tests).
class NoMatchEndAds extends MatchEndAds {
  const NoMatchEndAds();

  @override
  Future<void> show(BuildContext context) async {}
}

/// AdMob on Android and iOS; a stand-in test ad in debug builds elsewhere.
MatchEndAds platformMatchEndAds() {
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    return AdMobMatchEndAds();
  }
  return kReleaseMode ? const NoMatchEndAds() : DemoMatchEndAds();
}

/// Google AdMob interstitial ads.
///
/// Ad units come from `--dart-define=ADMOB_INTERSTITIAL_ID=...` (Android)
/// and `--dart-define=ADMOB_INTERSTITIAL_ID_IOS=...` (iOS). Without them,
/// Google's public test units are used (a "Test Ad" that earns nothing).
/// Consent is shared with the rewarded ads ([AdMobSdk]).
class AdMobMatchEndAds extends MatchEndAds {
  AdMobMatchEndAds();

  static const androidTestUnitId = 'ca-app-pub-3940256099942544/1033173712';
  static const iosTestUnitId = 'ca-app-pub-3940256099942544/4411468910';
  static const _androidUnitId = String.fromEnvironment('ADMOB_INTERSTITIAL_ID');
  static const _iosUnitId = String.fromEnvironment('ADMOB_INTERSTITIAL_ID_IOS');
  static String get androidUnitId =>
      _androidUnitId.isEmpty ? androidTestUnitId : _androidUnitId;
  static String get iosUnitId =>
      _iosUnitId.isEmpty ? iosTestUnitId : _iosUnitId;
  static String get unitId =>
      defaultTargetPlatform == TargetPlatform.iOS ? iosUnitId : androidUnitId;

  /// A loaded ad expires after an hour; reload a little before that.
  static const _maxAge = Duration(minutes: 50);
  static const _loadTimeout = Duration(seconds: 8);

  InterstitialAd? _ad;
  DateTime? _loadedAt;
  Future<InterstitialAd?>? _loading;

  @override
  void preload() {
    unawaited(_preload());
  }

  Future<void> _preload() async {
    if (!await AdMobSdk.ready()) return;
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

  Future<InterstitialAd?> _load() {
    final done = Completer<InterstitialAd?>();
    InterstitialAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: done.complete,
        onAdFailedToLoad: (e) {
          debugPrint('Interstitial failed to load: ${e.code} ${e.message}');
          done.complete(null);
        },
      ),
    );
    return done.future.timeout(_loadTimeout, onTimeout: () => null);
  }

  @override
  Future<void> show(BuildContext context) async {
    try {
      await _preload();
      final ad = _ad ?? await _loading;
      _ad = null;
      _loadedAt = null;
      // No ad ready: let the player carry on rather than wait.
      if (ad == null) return;
      final done = Completer<void>();
      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (a) {
          a.dispose();
          if (!done.isCompleted) done.complete();
        },
        onAdFailedToShowFullScreenContent: (a, e) {
          debugPrint('Interstitial failed to show: ${e.message}');
          a.dispose();
          if (!done.isCompleted) done.complete();
        },
      );
      await ad.show();
      await done.future;
    } catch (e) {
      debugPrint('Interstitial error: $e');
    }
  }
}

/// A stand-in interstitial for debug builds without AdMob (web, desktop):
/// a full-screen "Test ad" that can be closed after a short wait.
class DemoMatchEndAds extends MatchEndAds {
  DemoMatchEndAds({this.length = const Duration(seconds: 3)});

  final Duration length;

  @override
  Future<void> show(BuildContext context) async {
    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: true,
        fullscreenDialog: true,
        pageBuilder: (_, _, _) => _DemoInterstitial(length: length),
      ),
    );
  }
}

class _DemoInterstitial extends StatefulWidget {
  const _DemoInterstitial({required this.length});

  final Duration length;

  @override
  State<_DemoInterstitial> createState() => _DemoInterstitialState();
}

class _DemoInterstitialState extends State<_DemoInterstitial> {
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
  Widget build(BuildContext context) => Scaffold(
    key: const Key('demoInterstitial'),
    backgroundColor: const Color(0xFF101418),
    body: SafeArea(
      child: Stack(
        children: [
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.campaign_outlined, size: 72, color: Colors.white70),
                SizedBox(height: 16),
                Text(
                  'Test ad',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Shown after each match. Debug builds only.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: _left > 0
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '$_left',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  )
                : IconButton(
                    key: const Key('closeDemoInterstitial'),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
          ),
        ],
      ),
    ),
  );
}
