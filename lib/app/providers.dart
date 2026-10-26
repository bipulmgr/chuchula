import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/audio_service.dart';
import '../core/theme/table_themes.dart';
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
