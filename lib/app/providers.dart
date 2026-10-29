import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ads/rewarded_ads.dart';
import '../audio/audio_service.dart';
import '../core/theme/table_themes.dart';
import '../game/scoring/cash_points.dart';
import '../multiplayer/bluetooth/bluetooth_platform.dart';
import '../persistence/settings_repository.dart';

/// Overridden in `main()` with the opened store.
final localStoreProvider = Provider<LocalStore>(
  (ref) => throw UnimplementedError('localStoreProvider must be overridden'),
);

/// Overridden in `main()` (real audio) and tests (silent).
final audioServiceProvider = Provider<AudioService>(
  (ref) => SilentAudioService(),
);

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final s = ref.read(localStoreProvider).loadSettings();
    ref.read(audioServiceProvider).apply(s);
    return s;
  }

  void update(AppSettings Function(AppSettings) change) {
    final next = change(state);
    state = next;
    ref.read(audioServiceProvider).apply(next);
    ref.read(localStoreProvider).saveSettings(next);
  }
}

final tableThemeProvider = Provider<TableTheme>(
  (ref) => TableTheme.of(ref.watch(settingsProvider).tableTheme),
);

final statsProvider = NotifierProvider<StatsNotifier, PlayerStats>(
  StatsNotifier.new,
);

class StatsNotifier extends Notifier<PlayerStats> {
  @override
  PlayerStats build() => ref.read(localStoreProvider).loadStats();

  void record({required bool won, int groups = 0, int sweeps = 0}) {
    state = state.add(played: true, won: won, groups: groups, sweeps: sweeps);
    ref.read(localStoreProvider).saveStats(state);
  }
}

/// Overridden in tests with a fake.
final bluetoothPlatformProvider = Provider<BluetoothPlatform>(
  (ref) => MethodChannelBluetooth(),
);

/// Overridden in `main()` with [platformRewardedAds].
final rewardedAdsProvider = Provider<RewardedAds>(
  (ref) => const NoRewardedAds(),
);

final walletProvider = NotifierProvider<WalletNotifier, Wallet>(
  WalletNotifier.new,
);

class WalletNotifier extends Notifier<Wallet> {
  @override
  Wallet build() => ref.read(localStoreProvider).loadWallet();

  bool get canPlay => state.balance >= CashPoints.minimumToPlay;

  void _save(Wallet next) {
    state = next;
    ref.read(localStoreProvider).saveWallet(next);
  }

  /// Shows a rewarded ad and adds [CashPoints.adReward] if it was watched
  /// to the end.
  Future<AdOutcome> watchAd(BuildContext context) async {
    final outcome = await ref.read(rewardedAdsProvider).show(context);
    if (outcome == AdOutcome.rewarded) {
      _save(state.copyWith(balance: state.balance + CashPoints.adReward));
    }
    return outcome;
  }

  /// Applies the local player's share of a finished match, once per match.
  void settle(String matchId, int delta) {
    if (state.settledMatches.contains(matchId)) return;
    final recent = [...state.settledMatches, matchId];
    _save(
      Wallet(
        balance: (state.balance + delta).clamp(0, 1 << 31),
        settledMatches: recent.length > 20
            ? recent.sublist(recent.length - 20)
            : recent,
      ),
    );
  }
}
