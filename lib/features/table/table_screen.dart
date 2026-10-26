import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../audio/audio_service.dart';
import '../../bots/bot_strategy.dart';
import '../../core/localization/l10n.dart';
import '../../core/theme/table_themes.dart';
import '../../game/models/card.dart';
import '../../game/models/game_state.dart';
import '../../game/models/player_view.dart';
import '../../game/rules/bonuses.dart';
import '../../game/rules/hand_evaluator.dart';
import '../../game/rules/rule_config.dart';
import '../../game/state/game_session.dart';
import '../../widgets/card_widgets.dart';
import '../../widgets/ornaments.dart';
import '../results/match_over.dart';
import '../results/round_summary.dart';
import '../tutorial/how_to_play_screen.dart';
import 'center_area.dart';
import 'deal_overlay.dart';
import 'hand_strip.dart';
import 'seat_plate.dart';

/// The game table. Works for every mode: it only talks to a [GameSession].
class TableScreen extends ConsumerStatefulWidget {
  const TableScreen({
    super.key,
    required this.session,
    this.isOffline = true,
    this.onPlayAgain,
    this.onMatchFinished,
  });

  final GameSession session;
  final bool isOffline;

  /// Starts a fresh match (offline). Null hides the button.
  final VoidCallback? onPlayAgain;

  /// Called once when the match ends (statistics, clearing the save).
  final void Function(PlayerView finalView)? onMatchFinished;

  @override
  ConsumerState<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends ConsumerState<TableScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _deal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  );
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )..forward();

  List<List<PlayingCard>> _groups = const [];
  int _orderRound = -1;
  final List<List<List<PlayingCard>>> _undo = [];
  PlayerView? _last;
  String? _banner;
  Timer? _bannerTimer;
  bool _showSummary = false;
  Timer? _summaryTimer;
  Timer? _autoPlayTimer;
  bool _reportedFinish = false;
  int _lastDealTick = -1;
  StreamSubscription<SessionEvent>? _events;

  GameSession get session => widget.session;
  AudioService get audio => ref.read(audioServiceProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    session.view.addListener(_onView);
    _events = session.events.listen(_onEvent);
    _deal.addListener(_onDealTick);
  }

  bool _initialViewShown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The first view reads localizations and media settings, which are not
    // available in initState.
    if (!_initialViewShown) {
      _initialViewShown = true;
      if (session.view.value != null) _onView();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    session.view.removeListener(_onView);
    _events?.cancel();
    _bannerTimer?.cancel();
    _summaryTimer?.cancel();
    _autoPlayTimer?.cancel();
    _deal.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      session.onPause();
      audio.onPause();
    } else if (state == AppLifecycleState.resumed) {
      session.onResume();
      audio.onResume();
    }
  }

  bool get _reducedMotion =>
      ref.read(settingsProvider).reducedMotion ||
      MediaQuery.maybeDisableAnimationsOf(context) == true;

  void _onDealTick() {
    final tick = (_deal.value * 52).floor();
    if (tick != _lastDealTick && tick < 52 && tick % 2 == 0) {
      _lastDealTick = tick;
      audio.play(Sfx.deal);
    }
  }

  void _onEvent(SessionEvent e) {
    if (!mounted) return;
    final l = context.l10n;
    switch (e) {
      case MoveRejected(:final error):
        _flash(l.ruleError(error));
        audio.haptic(HapticKind.heavy);
      case ConnectionLost(:final message):
        _flash(l.connectionLost(message));
      case ConnectionRestored():
        _flash(l.connectionRestored);
    }
  }

  void _flash(String text, {Duration duration = const Duration(seconds: 2)}) {
    _bannerTimer?.cancel();
    setState(() => _banner = text);
    _bannerTimer = Timer(duration, () {
      if (mounted) setState(() => _banner = null);
    });
  }

  void _onView() {
    final v = session.view.value;
    if (v == null || !mounted) return;
    final old = _last;
    _last = v;
    final l = context.l10n;

    // New round: reset the draft and play the deal.
    if (v.round != _orderRound) {
      _orderRound = v.round;
      _groups = v.myArrangement?.groups ?? _split(v.myHand);
      _undo.clear();
      _showSummary = false;
      _summaryTimer?.cancel();
      if (v.phase == GamePhase.arranging && !_reducedMotion) {
        _lastDealTick = -1;
        _deal.forward(from: 0);
      }
    } else if (v.myArrangement != null) {
      _groups = v.myArrangement!.groups;
    }

    if (old != null && old.round == v.round) {
      // A group was revealed.
      final oldPlays = old.roundPlays.expand((g) => g).where((p) => p != null);
      final newPlays = v.roundPlays.expand((g) => g).where((p) => p != null);
      if (newPlays.length > oldPlays.length) audio.play(Sfx.play);
      // A group was won.
      if (v.groupWinners.length > old.groupWinners.length) {
        final g = v.groupWinners.length;
        final w = v.groupWinners.last;
        if (w == v.mySeat) {
          audio.play(Sfx.groupWin);
          audio.haptic(HapticKind.medium);
          _flash(l.youWinGroup(g));
        } else {
          _flash(l.groupWinner(v.seats[w].name, g));
        }
      }
      // My turn began.
      if (v.isMyTurn && !old.isMyTurn) {
        audio.play(Sfx.turn);
        audio.haptic(HapticKind.selection);
      }
    }

    if (v.phase == GamePhase.roundOver || v.phase == GamePhase.matchOver) {
      final wasOver =
          old != null &&
          old.round == v.round &&
          (old.phase == GamePhase.roundOver ||
              old.phase == GamePhase.matchOver);
      if (!wasOver) {
        _summaryTimer?.cancel();
        final instant = v.result?.reason == MatchEndReason.instantWin;
        _summaryTimer = Timer(
          Duration(milliseconds: instant || _reducedMotion ? 300 : 1500),
          () {
            if (!mounted) return;
            setState(() => _showSummary = true);
            _celebrate(v);
          },
        );
      } else {
        _showSummary = _showSummary || old.phase != v.phase;
      }
    }

    _scheduleAutoPlay(v);

    if (v.phase == GamePhase.matchOver && !_reportedFinish) {
      _reportedFinish = true;
      widget.onMatchFinished?.call(v);
    }
    setState(() {});
  }

  void _celebrate(PlayerView v) {
    if (v.phase == GamePhase.matchOver && v.result != null) {
      audio.play(v.result!.winnerSeat == v.mySeat ? Sfx.win : Sfx.lose);
      audio.haptic(HapticKind.heavy);
      return;
    }
    final rr = v.lastRound;
    if (rr == null) return;
    final special = rr.sweepSeat != null || rr.bonuses.any((b) => b.isNotEmpty);
    if (special) audio.play(Sfx.achievement);
  }

  // --- Arrangement actions -------------------------------------------------

  /// Splits a 13-card list into 3-3-3-4 groups.
  static List<List<PlayingCard>> _split(List<PlayingCard> cards) =>
      Arrangement.fromOrderedCards(cards).groups;

  /// Re-splits [cards] using the current group sizes.
  List<List<PlayingCard>> _resplit(List<PlayingCard> cards) {
    final next = <List<PlayingCard>>[];
    var start = 0;
    for (final g in _groups) {
      next.add(cards.sublist(start, start + g.length));
      start += g.length;
    }
    return next;
  }

  List<PlayingCard> get _flat => [for (final g in _groups) ...g];

  void _swap(int a, int b) {
    if (a == b) return;
    final next = _flat;
    final tmp = next[a];
    next[a] = next[b];
    next[b] = tmp;
    _setGroups(_resplit(next));
    audio.haptic(HapticKind.selection);
  }

  void _swapGroups(int a, int b) {
    if (a == b) return;
    final next = List.of(_groups);
    final tmp = next[a];
    next[a] = next[b];
    next[b] = tmp;
    _setGroups(next);
    audio.haptic(HapticKind.selection);
  }

  void _setGroups(List<List<PlayingCard>> next) {
    setState(() {
      _undo.add(_groups);
      _groups = next;
    });
    audio.play(Sfx.snap);
  }

  void _sortByRank() =>
      _setGroups(_resplit(_flat..sort((a, b) => a.compareTo(b))));

  void _sortBySuit() => _setGroups(
    _resplit(
      _flat..sort((a, b) {
        final s = a.suit.index.compareTo(b.suit.index);
        return s != 0 ? s : a.rank.value.compareTo(b.rank.value);
      }),
    ),
  );

  void _suggest() {
    final v = _last;
    if (v == null) return;
    final a = const MediumBot().arrange(v);
    _setGroups(a.groups);
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    setState(() => _groups = _undo.removeLast());
    audio.play(Sfx.drag);
  }

  void _reset() {
    final v = _last;
    if (v == null) return;
    _setGroups(_split(v.myHand));
  }

  Future<void> _ready() async {
    final v = _last;
    // The 4-card group must be the weakest, when the hand allows it.
    if (v != null &&
        RuleConfig.standard.fourCardWeakest &&
        !HandEvaluator.fourCardIsWeakest(_groups) &&
        HandEvaluator.fourCardWeakestArrangement(v.myHand) != null) {
      _flash(context.l10n.errFourCardTooStrong);
      audio.haptic(HapticKind.heavy);
      return;
    }
    audio.play(Sfx.button);
    audio.haptic(HapticKind.medium);
    // Groups are played in order: 3-card groups strongest first, then the
    // 4-card group; show them in that order now.
    setState(() => _groups = HandEvaluator.playOrder(_groups));
    await session.submitArrangement(Arrangement(_groups));
  }

  Future<void> _play() async {
    audio.haptic(HapticKind.medium);
    await session.playGroup();
  }

  /// Once everyone is ready, groups are revealed without a tap: my group
  /// goes out shortly after my turn comes, paced like the bots.
  void _scheduleAutoPlay(PlayerView v) {
    if (_autoPlayTimer != null || !v.isMyTurn) return;
    final fresh =
        v.groupIndex > 0 && v.roundPlays[v.groupIndex].every((p) => p == null);
    final delay = _reducedMotion
        ? const Duration(milliseconds: 300)
        : Duration(milliseconds: fresh ? 1700 : 800);
    final round = v.round;
    final group = v.groupIndex;
    _autoPlayTimer = Timer(delay, () {
      _autoPlayTimer = null;
      final now = session.view.value;
      if (!mounted || now == null) return;
      if (now.isMyTurn && now.round == round && now.groupIndex == group) {
        _play();
      } else {
        _scheduleAutoPlay(now);
      }
    });
  }

  Future<void> _show() async {
    audio.play(Sfx.achievement);
    audio.haptic(HapticKind.heavy);
    await session.showHand();
  }

  Future<void> _next() async {
    audio.play(Sfx.button);
    setState(() => _showSummary = false);
    await session.startNextRound();
  }

  Future<void> _confirmLeave() async {
    final l = context.l10n;
    final theme = ref.read(tableThemeProvider);
    final v = _last;
    if (v != null && v.phase == GamePhase.matchOver) {
      Navigator.of(context).pop();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: GoldPanel(
          theme: theme,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l.leaveMatch,
                style: TextStyle(
                  fontFamily: 'YatraOne',
                  fontSize: 22,
                  color: theme.accent,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.isOffline ? l.leaveOfflineBody : l.leaveOnlineBody,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GoldButton(
                      theme: theme,
                      label: l.stay,
                      primary: false,
                      onPressed: () => Navigator.pop(ctx, false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GoldButton(
                      theme: theme,
                      label: l.leave,
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(tableThemeProvider);
    final settings = ref.watch(settingsProvider);
    final reduced = _reducedMotion;
    final v = _last;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: theme.feltEdge,
        body: FeltBackground(
          theme: theme,
          child: SafeArea(
            child: v == null
                ? Center(child: CircularProgressIndicator(color: theme.accent))
                : FadeTransition(
                    opacity: _entrance,
                    child: ScaleTransition(
                      scale: Tween(begin: 0.96, end: 1.0).animate(
                        CurvedAnimation(
                          parent: _entrance,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                      child: _buildTable(v, theme, settings.cardBack, reduced),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildTable(
    PlayerView v,
    TableTheme theme,
    CardBackId back,
    bool reduced,
  ) {
    final l = context.l10n;
    final media = MediaQuery.sizeOf(context);
    final handMaxHeight = (media.height * 0.36).clamp(150.0, 320.0);

    return Stack(
      children: [
        Column(
          children: [
            _TopBar(
              view: v,
              theme: theme,
              onBack: _confirmLeave,
              onRules: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const HowToPlayScreen(),
                ),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(70, 64, 70, 8),
                      child: CenterArea(
                        view: v,
                        theme: theme,
                        reducedMotion: reduced,
                      ),
                    ),
                  ),
                  for (var seat = 0; seat < kSeatCount; seat++)
                    if (seat != v.mySeat)
                      _opponent(v, seat, theme, back, reduced),
                  Positioned.fill(
                    child: DealOverlay(
                      animation: _deal,
                      firstPosition: relativePosition(
                        (v.dealerSeat + 1) % 4,
                        v.mySeat,
                      ),
                      theme: theme,
                      cardBack: back,
                    ),
                  ),
                ],
              ),
            ),
            _myBar(v, theme, reduced),
            SizedBox(
              height: handMaxHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: AnimatedBuilder(
                  animation: _deal,
                  builder: (context, _) => HandStrip(
                    groups: _groups,
                    mode: _stripMode(v),
                    theme: theme,
                    reducedMotion: reduced,
                    onSwap: _swap,
                    onSwapGroups: _swapGroups,
                    onDragStart: () => audio.play(Sfx.drag),
                    onPlayGroup: v.isMyTurn ? _play : null,
                    playedGroups: _myPlayedGroups(v),
                    activeGroup: v.isMyTurn ? v.groupIndex : null,
                    revealProgress: _deal.isAnimating
                        ? ((_deal.value - 0.55) / 0.45).clamp(0.0, 1.0)
                        : 1,
                  ),
                ),
              ),
            ),
            _actions(v, theme, l),
          ],
        ),
        if (_banner != null)
          Positioned(
            top: 56,
            left: 24,
            right: 24,
            child: IgnorePointer(
              child: Center(
                child: _Toast(text: _banner!, theme: theme),
              ),
            ),
          ),
        if (_showSummary &&
            v.phase == GamePhase.roundOver &&
            v.lastRound != null)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.45),
              child: RoundSummaryPanel(
                view: v,
                theme: theme,
                reducedMotion: reduced,
                onNext: session.canStartNextRound ? _next : null,
              ),
            ),
          ),
        if (_showSummary && v.phase == GamePhase.matchOver && v.result != null)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.55),
              child: MatchOverPanel(
                view: v,
                theme: theme,
                reducedMotion: reduced,
                onHome: () => Navigator.of(context).pop(),
                onPlayAgain: widget.onPlayAgain,
              ),
            ),
          ),
      ],
    );
  }

  StripMode _stripMode(PlayerView v) {
    if (v.phase == GamePhase.arranging && v.myArrangement == null) {
      return StripMode.arranging;
    }
    if (v.phase == GamePhase.playing) return StripMode.playing;
    return StripMode.locked;
  }

  int _myPlayedGroups(PlayerView v) {
    var n = 0;
    for (final g in v.roundPlays) {
      if (g[v.mySeat] != null) n++;
    }
    return n;
  }

  Widget _opponent(
    PlayerView v,
    int seat,
    TableTheme theme,
    CardBackId back,
    bool reduced,
  ) {
    final pos = relativePosition(seat, v.mySeat);
    final align = switch (pos) {
      1 => const Alignment(1, -0.25),
      2 => const Alignment(0, -1),
      _ => const Alignment(-1, -0.25),
    };
    final connections = session.connections.value;
    final thinking = session.thinking.value;
    final played = v.roundPlays.where((g) => g[seat] != null).length;
    final remaining =
        v.phase == GamePhase.roundOver || v.phase == GamePhase.matchOver
        ? 0
        : 13 - (played == 0 ? 0 : [3, 6, 9, 13][played - 1]);
    final plate = ValueListenableBuilder(
      valueListenable: session.thinking,
      builder: (context, _, _) => SeatPlate(
        seat: seat,
        info: v.seats[seat],
        score: v.scores[seat],
        theme: theme,
        connection: connections[seat],
        isTurn: v.turnSeat == seat && v.phase == GamePhase.playing,
        isReady: v.ready[seat],
        isThinking: thinking.contains(seat),
        isDealer: v.dealerSeat == seat,
        phase: v.phase,
        reducedMotion: reduced,
        compact: pos != 2,
      ),
    );
    final fan = _BackFan(count: remaining, theme: theme, back: back);
    return Align(
      alignment: align,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: pos == 1
              ? CrossAxisAlignment.end
              : pos == 3
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [plate, const SizedBox(height: 4), fan],
        ),
      ),
    );
  }

  Widget _myBar(PlayerView v, TableTheme theme, bool reduced) {
    final l = context.l10n;
    String status;
    if (v.phase == GamePhase.arranging) {
      status = v.myArrangement == null ? l.arrangeHint : l.waitingForOthers;
    } else if (v.phase == GamePhase.playing) {
      status = v.isMyTurn
          ? l.revealing
          : l.turnOf(v.seats[v.turnSeat ?? 0].name);
    } else {
      status = '';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
      child: Row(
        children: [
          SeatPlate(
            seat: v.mySeat,
            info: v.seats[v.mySeat],
            score: v.scores[v.mySeat],
            theme: theme,
            connection: SeatConnection.local,
            isTurn: v.isMyTurn,
            isReady: v.ready[v.mySeat],
            isThinking: false,
            isDealer: v.dealerSeat == v.mySeat,
            phase: v.phase,
            reducedMotion: reduced,
            compact: true,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(
                status,
                key: ValueKey(status),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.2,
                  fontWeight: v.isMyTurn ? FontWeight.w800 : FontWeight.w400,
                  color: v.isMyTurn ? theme.glow : theme.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(PlayerView v, TableTheme theme, AppLocalizations l) {
    final special = v.phase == GamePhase.arranging
        ? BonusDetector.detect(v.myHand, RuleConfig.standard)
        : const <Bonus>[];
    Widget bar;
    if (v.phase == GamePhase.arranging && v.myArrangement == null) {
      bar = Row(
        children: [
          _iconAction(
            Icons.undo,
            l.undo,
            _undo.isEmpty ? null : _undoLast,
            theme,
          ),
          _iconAction(Icons.restart_alt, l.reset, _reset, theme),
          _iconAction(
            Icons.format_list_numbered,
            l.sortRank,
            _sortByRank,
            theme,
          ),
          _iconAction(Icons.filter_list, l.sortSuit, _sortBySuit, theme),
          _iconAction(Icons.lightbulb_outline, l.suggest, _suggest, theme),
          _iconAction(
            Icons.auto_awesome,
            l.showSpecial,
            () => special.isEmpty ? _flash(l.showNothing) : _show(),
            theme,
            key: const Key('showIconButton'),
            highlight: special.isNotEmpty,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: GoldButton(
              key: const Key('readyButton'),
              theme: theme,
              label: l.ready,
              icon: Icons.check,
              onPressed: _ready,
            ),
          ),
        ],
      );
    } else {
      bar = const SizedBox(height: 50);
    }
    if (special.isNotEmpty) {
      final allRanks = special.any((b) => b.type == BonusType.allRanks);
      final label = allRanks
          ? l.showAllRanks
          : l.showHand(
              special.map((b) => l.bonus(b.type)).join(' + '),
              special.fold<int>(0, (t, b) => t + b.points),
            );
      bar = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.showHint,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: theme.onSurface),
          ),
          const SizedBox(height: 4),
          GoldButton(
            key: const Key('showHandButton'),
            theme: theme,
            label: label,
            icon: Icons.auto_awesome,
            onPressed: _show,
          ),
          const SizedBox(height: 6),
          bar,
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      child: bar,
    );
  }

  Widget _iconAction(
    IconData icon,
    String label,
    VoidCallback? onTap,
    TableTheme theme, {
    Key? key,
    bool highlight = false,
  }) => Tooltip(
    key: key,
    message: label,
    child: Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: onTap == null
            ? null
            : () {
                audio.play(Sfx.button);
                onTap();
              },
        radius: 24,
        child: SizedBox(
          width: 40,
          height: 48,
          child: Icon(
            icon,
            color: onTap == null
                ? theme.onSurface.withValues(alpha: 0.3)
                : (highlight ? theme.glow : theme.accentSoft),
          ),
        ),
      ),
    ),
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.view,
    required this.theme,
    required this.onBack,
    required this.onRules,
  });

  final PlayerView view;
  final TableTheme theme;
  final VoidCallback onBack;
  final VoidCallback onRules;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final chip = BoxDecoration(
      color: theme.surface.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: theme.accent.withValues(alpha: 0.5)),
    );
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            tooltip: l.home,
            onPressed: onBack,
            icon: Icon(Icons.arrow_back_ios_new, color: theme.accentSoft),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: chip,
            child: Text(
              l.roundLabel(view.round),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: theme.accentSoft,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: chip,
              child: Text(
                l.targetScore(view.targetScore),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: theme.onSurface),
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: l.rules,
            onPressed: onRules,
            icon: Icon(Icons.menu_book, color: theme.accentSoft),
          ),
        ],
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({required this.text, required this.theme});
  final String text;
  final TableTheme theme;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    key: ValueKey(text),
    tween: Tween(begin: 0.85, end: 1),
    duration: const Duration(milliseconds: 260),
    curve: Curves.easeOutBack,
    builder: (context, s, child) => Transform.scale(scale: s, child: child),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.glow, width: 1.5),
        boxShadow: [
          BoxShadow(color: theme.glow.withValues(alpha: 0.35), blurRadius: 16),
        ],
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.w800, color: theme.onSurface),
      ),
    ),
  );
}

/// A small fan of face-down cards showing how many an opponent holds.
class _BackFan extends StatelessWidget {
  const _BackFan({
    required this.count,
    required this.theme,
    required this.back,
  });
  final int count;
  final TableTheme theme;
  final CardBackId back;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox(height: 30);
    const w = 20.0;
    const step = 4.0;
    return SizedBox(
      width: w + step * (count - 1),
      height: w / kCardAspect,
      child: Stack(
        children: [
          for (var i = 0; i < count; i++)
            Positioned(
              left: i * step,
              child: CardBack(
                width: w,
                style: back,
                theme: theme,
                elevation: 1,
              ),
            ),
        ],
      ),
    );
  }
}
