import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ads/rewarded_ads.dart';
import '../../app/providers.dart';
import '../../audio/audio_service.dart';
import '../../bots/bot_strategy.dart';
import '../../core/localization/l10n.dart';
import '../../core/theme/table_themes.dart';
import '../../game/models/card.dart';
import '../../game/scoring/cash_points.dart';
import '../../widgets/card_widgets.dart';
import '../../widgets/ornaments.dart';
import '../lobby/bluetooth_lobby_screen.dart';
import '../lobby/online_lobby_screen.dart';
import '../settings/settings_screen.dart';
import '../setup/offline_game.dart';
import '../tutorial/how_to_play_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  SavedMatch? _saved;
  bool _adBusy = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
    // Consent form (where required) and the first ad load, after the first
    // frame so the form has a screen to show over.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(rewardedAdsProvider).prepare();
    });
  }

  void _loadSaved() {
    final raw = ref.read(localStoreProvider).loadSavedMatch();
    setState(() => _saved = SavedMatch.tryParse(raw));
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  Future<void> _push(Widget screen) async {
    ref.read(audioServiceProvider).play(Sfx.button);
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) _loadSaved();
  }

  String _playerName(AppLocalizations l) {
    final n = ref.read(settingsProvider).playerName.trim();
    return n.isEmpty ? l.defaultPlayerName : n;
  }

  Future<void> _resume() async {
    final saved = _saved;
    if (saved == null) return;
    final l = context.l10n;
    ref.read(audioServiceProvider).play(Sfx.button);
    await OfflineGame.open(
      context,
      ref,
      resume: saved.state,
      difficulty: saved.difficulty,
      board: saved.board,
      showSuggest: saved.showSuggest,
      playerName: _playerName(l),
      botNames: l.botNames,
    );
    if (mounted) _loadSaved();
  }

  /// Shows a rewarded ad and reports the outcome.
  Future<void> _watchAd() async {
    if (_adBusy) return;
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    ref.read(audioServiceProvider).play(Sfx.button);
    if (!ref.read(rewardedAdsProvider).supported) {
      messenger.showSnackBar(SnackBar(content: Text(l.adsAndroidOnly)));
      return;
    }
    setState(() => _adBusy = true);
    final AdOutcome outcome;
    try {
      outcome = await ref.read(walletProvider.notifier).watchAd(context);
    } finally {
      if (mounted) setState(() => _adBusy = false);
    }
    if (outcome == AdOutcome.rewarded) {
      ref.read(audioServiceProvider).play(Sfx.achievement);
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(switch (outcome) {
            AdOutcome.rewarded => l.adRewarded(CashPoints.adReward),
            AdOutcome.closedEarly => l.adClosedEarly,
            AdOutcome.unavailable => l.adUnavailable,
          }),
        ),
      );
  }

  Future<void> _newOffline() async {
    ref.read(audioServiceProvider).play(Sfx.button);
    if (!ref.read(walletProvider.notifier).canPlay) {
      final l = context.l10n;
      final watch = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          key: const Key('needCashDialog'),
          title: Text(l.cashPoints),
          content: Text(
            l.needCash(CashPoints.minimumToPlay, CashPoints.adReward),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.watchAd(CashPoints.adReward)),
            ),
          ],
        ),
      );
      if (watch == true && mounted) await _watchAd();
      return;
    }
    if (!mounted) return;
    final choice = await showModalBottomSheet<_MatchChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SetupSheet(),
    );
    if (choice == null || !mounted) return;
    final l = context.l10n;
    await OfflineGame.open(
      context,
      ref,
      board: choice.board,
      showSuggest: choice.showSuggest,
      playerName: _playerName(l),
      botNames: l.botNames,
    );
    if (mounted) _loadSaved();
  }

  Widget _staggered(int i, Widget child) {
    final start = (0.15 + i * 0.08).clamp(0.0, 0.9);
    final anim = CurvedAnimation(
      parent: _intro,
      curve: Interval(
        start,
        (start + 0.35).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.25),
          end: Offset.zero,
        ).animate(anim),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = ref.watch(tableThemeProvider);
    final stats = ref.watch(statsProvider);
    final saved = _saved;
    final buttons = <Widget>[
      if (saved != null)
        GoldButton(
          key: const Key('resumeButton'),
          theme: theme,
          label: l.resumeMatch,
          subtitle: l.resumeMatchSub(
            saved.state.round,
            saved.state.scores[OfflineGame.localSeat],
          ),
          icon: Icons.play_circle_fill,
          onPressed: _resume,
        ),
      GoldButton(
        key: const Key('playOfflineButton'),
        theme: theme,
        label: l.playOffline,
        subtitle: l.playOfflineSub,
        icon: Icons.style,
        primary: saved == null,
        onPressed: _newOffline,
      ),
      // Online play needs a Firebase project (a paid plan for Cloud
      // Functions). Builds without one leave the mode out entirely.
      if (ref.watch(onlinePlayEnabledProvider))
        GoldButton(
          key: const Key('playOnlineButton'),
          theme: theme,
          label: l.playOnline,
          subtitle: l.playOnlineSub,
          icon: Icons.public,
          primary: false,
          onPressed: () => _push(const OnlineLobbyScreen()),
        ),
      // iPhones cannot open Bluetooth Classic links to Android phones, so
      // Bluetooth play is Android only.
      if (defaultTargetPlatform != TargetPlatform.iOS)
        GoldButton(
          key: const Key('bluetoothButton'),
          theme: theme,
          label: l.bluetoothPlay,
          subtitle: l.bluetoothPlaySub,
          icon: Icons.bluetooth,
          primary: false,
          onPressed: () => _push(const BluetoothLobbyScreen()),
        ),
    ];

    return Scaffold(
      backgroundColor: theme.feltEdge,
      body: FeltBackground(
        theme: theme,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: _WalletChip(
                                    theme: theme,
                                    balance: ref.watch(walletProvider).balance,
                                    onWatchAd: _watchAd,
                                    loading: _adBusy,
                                  ),
                                ),
                              ),
                              IconButton(
                                key: const Key('rulesButton'),
                                tooltip: l.howToPlay,
                                onPressed: () => _push(const HowToPlayScreen()),
                                icon: Icon(
                                  Icons.menu_book,
                                  color: theme.accentSoft,
                                ),
                              ),
                              IconButton(
                                key: const Key('settingsButton'),
                                tooltip: l.settings,
                                onPressed: () => _push(const SettingsScreen()),
                                icon: Icon(
                                  Icons.settings,
                                  color: theme.accentSoft,
                                ),
                              ),
                            ],
                          ),
                          _staggered(
                            0,
                            _HeroCards(theme: theme, intro: _intro),
                          ),
                          const SizedBox(height: 8),
                          _staggered(0, ChuchulaLogo(theme: theme, size: 58)),
                          const SizedBox(height: 4),
                          _staggered(
                            1,
                            Text(
                              l.tagline,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: theme.onSurface.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                          const SizedBox(height: 26),
                          for (var i = 0; i < buttons.length; i++) ...[
                            _staggered(i + 2, buttons[i]),
                            const SizedBox(height: 12),
                          ],
                          const SizedBox(height: 4),
                          _staggered(
                            7,
                            GoldButton(
                              theme: theme,
                              label: l.howToPlay,
                              icon: Icons.school,
                              primary: false,
                              onPressed: () => _push(const HowToPlayScreen()),
                            ),
                          ),
                          const SizedBox(height: 18),
                          _staggered(
                            8,
                            Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.offline_bolt,
                                      size: 16,
                                      color: theme.glow,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        l.offlineReady,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: theme.onSurface,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (stats.played > 0) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    l.statsLine(
                                      stats.won,
                                      stats.played,
                                      stats.sweeps,
                                    ),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.accentSoft,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The player's cash points, with a button to earn more from an ad.
class _WalletChip extends StatelessWidget {
  const _WalletChip({
    required this.theme,
    required this.balance,
    required this.onWatchAd,
    this.loading = false,
  });

  final TableTheme theme;
  final int balance;
  final VoidCallback onWatchAd;

  /// An ad is loading or showing.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Semantics(
      label: l.cashBalance(balance),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
        decoration: BoxDecoration(
          color: theme.surface.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: theme.accent.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.monetization_on, size: 20, color: theme.accent),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '$balance',
                key: const Key('walletBalance'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Mukta',
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: theme.accent,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: loading ? l.adLoading : l.watchAd(CashPoints.adReward),
              child: TextButton.icon(
                key: const Key('watchAdButton'),
                onPressed: loading ? null : onWatchAd,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 36),
                  shape: const StadiumBorder(),
                  backgroundColor: theme.accent.withValues(alpha: 0.18),
                ),
                icon: loading
                    ? SizedBox.square(
                        key: const Key('adLoading'),
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.accentSoft,
                        ),
                      )
                    : Icon(
                        Icons.ondemand_video,
                        size: 18,
                        color: theme.accentSoft,
                      ),
                label: Text(
                  '+${CashPoints.adReward}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: theme.accentSoft,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A fanned hand of cards above the logo.
class _HeroCards extends StatelessWidget {
  const _HeroCards({required this.theme, required this.intro});
  final TableTheme theme;
  final Animation<double> intro;

  @override
  Widget build(BuildContext context) {
    final cards = parseCards('AS KH QD JC');
    return SizedBox(
      height: 110,
      child: AnimatedBuilder(
        animation: intro,
        builder: (context, _) {
          final t = Curves.easeOutBack.transform(intro.value.clamp(0.0, 1.0));
          return Stack(
            alignment: Alignment.bottomCenter,
            children: [
              for (var i = 0; i < cards.length; i++)
                Transform.translate(
                  offset: Offset(
                    (i - 1.5) * 34 * t,
                    -8 * (1 - (i - 1.5).abs() / 1.5),
                  ),
                  child: Transform.rotate(
                    angle: (i - 1.5) * 0.16 * t,
                    alignment: Alignment.bottomCenter,
                    child: CardFace(card: cards[i], width: 62, elevation: 6),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// What the New Match sheet chose.
class _MatchChoice {
  const _MatchChoice(this.board, this.showSuggest);
  final int board;
  final bool showSuggest;
}

class _SetupSheet extends ConsumerStatefulWidget {
  const _SetupSheet();

  @override
  ConsumerState<_SetupSheet> createState() => _SetupSheetState();
}

class _SetupSheetState extends ConsumerState<_SetupSheet> {
  late final TextEditingController _name = TextEditingController(
    text: ref.read(settingsProvider).playerName,
  );

  /// The board; the smallest by default.
  int _board = CashPoints.defaultBoard;

  /// Suggest button at the table; off unless the player turns it on.
  bool _suggest = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = ref.watch(tableThemeProvider);
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final balance = ref.watch(walletProvider).balance;
    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
      ),
      child: GoldPanel(
        theme: theme,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.newMatch,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'YatraOne',
                  fontSize: 24,
                  color: theme.accent,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('nameField'),
                controller: _name,
                maxLength: 16,
                style: TextStyle(color: theme.onSurface),
                decoration: InputDecoration(
                  labelText: l.yourName,
                  hintText: l.defaultPlayerName,
                  labelStyle: TextStyle(color: theme.accentSoft),
                  counterStyle: TextStyle(
                    color: theme.onSurface.withValues(alpha: 0.5),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: theme.accent.withValues(alpha: 0.6),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: theme.accent, width: 2),
                  ),
                ),
                onChanged: (v) =>
                    notifier.update((x) => x.copyWith(playerName: v)),
              ),
              const SizedBox(height: 6),
              Text(
                l.difficulty,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              for (final d in BotDifficulty.values)
                _DifficultyTile(
                  key: Key('difficulty-${d.name}'),
                  theme: theme,
                  title: l.difficultyName(d),
                  subtitle: l.difficultyDesc(d),
                  selected: s.difficulty == d,
                  onTap: () =>
                      notifier.update((x) => x.copyWith(difficulty: d)),
                ),
              const SizedBox(height: 8),
              Text(
                l.board,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  for (final b in CashPoints.boards)
                    _BoardChip(
                      key: Key('board-$b'),
                      theme: theme,
                      label: CashPoints.boardLabel(b),
                      entry: l.boardEntry(CashPoints.entryFor(b)),
                      selected: _board == b,
                      enabled: balance >= CashPoints.entryFor(b),
                      onTap: () => setState(() => _board = b),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                l.boardPays(
                  CashPoints.boardLabel(_board),
                  CashPoints.entryFor(_board),
                ),
                key: const Key('boardPays'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.onSurface.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                key: const Key('suggestToggle'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                activeThumbColor: theme.accent,
                title: Text(
                  l.suggestToggle,
                  style: TextStyle(color: theme.onSurface),
                ),
                subtitle: Text(
                  l.suggestToggleSub,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                value: _suggest,
                onChanged: (v) => setState(() => _suggest = v),
              ),
              Text(
                l.targetScore(20),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.onSurface.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 12),
              GoldButton(
                key: const Key('startMatchButton'),
                theme: theme,
                label: l.startMatch,
                icon: Icons.style,
                onPressed: balance >= CashPoints.entryFor(_board)
                    ? () =>
                          Navigator.pop(context, _MatchChoice(_board, _suggest))
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One board in the New Match sheet: its size and the cash points needed.
class _BoardChip extends StatelessWidget {
  const _BoardChip({
    super.key,
    required this.theme,
    required this.label,
    required this.entry,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final TableTheme theme;
  final String label;
  final String entry;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    enabled: enabled,
    button: true,
    child: GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 84,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? theme.accent.withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? theme.glow
                  : theme.accent.withValues(alpha: 0.3),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: selected ? theme.glow : theme.onSurface,
                ),
              ),
              Text(
                entry,
                style: TextStyle(
                  fontSize: 10.5,
                  color: theme.onSurface.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DifficultyTile extends StatelessWidget {
  const _DifficultyTile({
    super.key,
    required this.theme,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final TableTheme theme;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? theme.accent.withValues(alpha: 0.2)
              : Colors.black.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? theme.glow : theme.accent.withValues(alpha: 0.3),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? theme.glow : theme.accentSoft,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.onSurface.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
