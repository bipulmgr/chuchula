import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../audio/audio_service.dart';
import '../../bots/bot_strategy.dart';
import '../../core/localization/l10n.dart';
import '../../core/theme/table_themes.dart';
import '../../game/models/card.dart';
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

  @override
  void initState() {
    super.initState();
    _loadSaved();
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
      playerName: _playerName(l),
      botNames: l.botNames,
    );
    if (mounted) _loadSaved();
  }

  Future<void> _newOffline() async {
    ref.read(audioServiceProvider).play(Sfx.button);
    final start = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SetupSheet(),
    );
    if (start != true || !mounted) return;
    final l = context.l10n;
    await OfflineGame.open(
      context,
      ref,
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
      GoldButton(
        key: const Key('playOnlineButton'),
        theme: theme,
        label: l.playOnline,
        subtitle: l.playOnlineSub,
        icon: Icons.public,
        primary: false,
        onPressed: () => _push(const OnlineLobbyScreen()),
      ),
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
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
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
                                    Text(
                                      l.offlineReady,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: theme.onSurface,
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

class _SetupSheet extends ConsumerStatefulWidget {
  const _SetupSheet();

  @override
  ConsumerState<_SetupSheet> createState() => _SetupSheetState();
}

class _SetupSheetState extends ConsumerState<_SetupSheet> {
  late final TextEditingController _name = TextEditingController(
    text: ref.read(settingsProvider).playerName,
  );

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
    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
      ),
      child: GoldPanel(
        theme: theme,
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
                onTap: () => notifier.update((x) => x.copyWith(difficulty: d)),
              ),
            const SizedBox(height: 6),
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
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
  }
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
