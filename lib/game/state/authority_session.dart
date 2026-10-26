import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../bots/bot_strategy.dart';
import '../engine/game_engine.dart';
import '../models/game_state.dart';
import '../models/moves.dart';
import '../models/player_view.dart';
import 'game_session.dart';

/// Computes a bot arrangement. The default runs the search on a background
/// isolate so the UI never janks; tests inject a synchronous runner.
typedef BotRunner = Future<Arrangement> Function(
  BotStrategy bot,
  PlayerView view,
);

Future<Arrangement> isolateBotRunner(BotStrategy bot, PlayerView view) {
  // Isolates are not available on the web; think on the main thread there,
  // after the current frame so the UI updates first.
  if (kIsWeb) return Future(() => _lighterForWeb(bot).arrange(view));
  return Isolate.run(() => bot.arrange(view));
}

/// Smaller searches for the web build, where bots share the UI thread.
BotStrategy _lighterForWeb(BotStrategy bot) => switch (bot) {
  HardBot(:final seed) => HardBot(
    seed: seed,
    simulations: 8,
    quadCandidates: 50,
  ),
  MediumBot() => const MediumBot(quadCandidates: 30),
  _ => bot,
};

/// A quick, always-legal arrangement used when a bot's normal search fails
/// or takes too long, so a seat can never stay stuck "arranging".
Arrangement fallbackArrangement(PlayerView view) {
  try {
    return const MediumBot(quadCandidates: 12).arrange(view);
  } catch (_) {
    return Arrangement.fromOrderedCards(List.of(view.myHand)..sort());
  }
}

Future<Arrangement> inlineBotRunner(BotStrategy bot, PlayerView view) async =>
    bot.arrange(view);

/// Bot pacing, so bots feel natural without blocking the engine.
class BotTiming {
  const BotTiming({
    this.minThink = const Duration(milliseconds: 900),
    this.maxThink = const Duration(milliseconds: 2200),
    this.play = const Duration(milliseconds: 800),
    this.afterGroup = const Duration(milliseconds: 1700),
  });

  /// Zero delays, for tests and simulations.
  const BotTiming.instant()
    : minThink = Duration.zero,
      maxThink = Duration.zero,
      play = Duration.zero,
      afterGroup = Duration.zero;

  final Duration minThink;
  final Duration maxThink;
  final Duration play;

  /// Pause before leading a new group, so everyone sees the last result.
  final Duration afterGroup;
}

/// A seat controlled by another device (Bluetooth client). The authority
/// sends that seat only its own [PlayerView] and validates its moves.
abstract class RemoteSeatLink {
  void sendView(PlayerView view);
  void sendError(RuleError error);
  Stream<GameMove> get moves;
  ValueListenable<bool> get isConnected;
  Future<void> close();
}

/// Runs the authoritative engine on this device: offline play against bots,
/// and the host side of Bluetooth play.
class AuthorityGameSession extends BaseGameSession {
  AuthorityGameSession({
    required this.engine,
    required GameState initialState,
    required this.localSeat,
    Map<int, BotStrategy> bots = const {},
    Map<int, RemoteSeatLink> remoteSeats = const {},
    this.timing = const BotTiming(),
    this.botRunner = isolateBotRunner,
    this.onStateChanged,
    this.disconnectGrace = const Duration(seconds: 45),
    this.botTimeout = const Duration(seconds: 8),
  }) : _state = initialState,
       _bots = Map.of(bots),
       _remotes = Map.of(remoteSeats) {
    for (final entry in _remotes.entries) {
      _subs.add(entry.value.moves.listen((m) => _onRemoteMove(entry.key, m)));
      entry.value.isConnected.addListener(() => _onRemoteConnection(entry.key));
    }
    _publish();
    scheduleMicrotask(_schedule);
  }

  final ChuchulaGameEngine engine;
  @override
  final int localSeat;
  final BotTiming timing;
  final BotRunner botRunner;

  /// Persistence hook (offline save/resume).
  final Future<void> Function(GameState state)? onStateChanged;

  /// How long a disconnected remote seat is held before a bot takes over.
  final Duration disconnectGrace;

  /// Longest a bot may think before it falls back to a quick arrangement.
  final Duration botTimeout;

  GameState _state;
  final Map<int, BotStrategy> _bots;
  final Map<int, RemoteSeatLink> _remotes;
  final List<StreamSubscription<GameMove>> _subs = [];
  final Set<int> _arranging = {};
  final Map<int, Timer> _graceTimers = {};
  Timer? _playTimer;
  bool _paused = false;
  final math.Random _jitter = math.Random();

  GameState get state => _state;

  @override
  bool get canStartNextRound => true;

  @override
  Future<void> submitArrangement(Arrangement arrangement) async =>
      _applyLocal(SubmitArrangement(localSeat, arrangement));

  @override
  Future<void> playGroup() async =>
      _applyLocal(PlayGroup(localSeat, _state.groupIndex));

  @override
  Future<void> showHand() async => _applyLocal(ShowHand(localSeat));

  @override
  Future<void> startNextRound() async => _applyLocal(StartNextRound(localSeat));

  void _applyLocal(GameMove move) {
    final r = engine.validateMove(_state, move);
    if (!r.isValid) {
      emit(MoveRejected(r.error!));
      return;
    }
    _commit(engine.applyMove(_state, move));
  }

  void _onRemoteMove(int seat, GameMove move) {
    // A client may only act for its own seat and may not start rounds.
    if (move.seat != seat || move is StartNextRound) {
      _remotes[seat]?.sendError(RuleError.invalidSeat);
      return;
    }
    final r = engine.validateMove(_state, move);
    if (!r.isValid) {
      // Duplicates of an already-applied move land here and are ignored.
      _remotes[seat]?.sendError(r.error!);
      _remotes[seat]?.sendView(PlayerView.of(_state, seat));
      return;
    }
    _commit(engine.applyMove(_state, move));
  }

  void _onRemoteConnection(int seat) {
    final link = _remotes[seat];
    if (link == null || disposed) return;
    final list = List.of(connectionsNotifier.value);
    if (link.isConnected.value) {
      _graceTimers.remove(seat)?.cancel();
      list[seat] = SeatConnection.connected;
      link.sendView(PlayerView.of(_state, seat));
      emit(const ConnectionRestored());
    } else {
      list[seat] = SeatConnection.reconnecting;
      emit(ConnectionLost(_state.seats[seat].name));
      _graceTimers[seat]?.cancel();
      _graceTimers[seat] = Timer(disconnectGrace, () => _takeOver(seat));
    }
    connectionsNotifier.value = list;
  }

  /// Replaces an abandoned remote seat with a bot so the match can finish.
  void _takeOver(int seat) {
    if (disposed) return;
    _remotes.remove(seat)?.close();
    _bots[seat] = const MediumBot();
    final list = List.of(connectionsNotifier.value);
    list[seat] = SeatConnection.bot;
    connectionsNotifier.value = list;
    _schedule();
  }

  void _commit(GameState next) {
    if (disposed) return;
    _state = next;
    _publish();
    onStateChanged?.call(next);
    _schedule();
  }

  void _publish() {
    viewNotifier.value = PlayerView.of(_state, localSeat);
    for (final e in _remotes.entries) {
      e.value.sendView(PlayerView.of(_state, e.key));
    }
    connectionsNotifier.value = [
      for (var i = 0; i < kSeatCount; i++)
        i == localSeat
            ? SeatConnection.local
            : _bots.containsKey(i)
            ? SeatConnection.bot
            : (_remotes[i]?.isConnected.value ?? false)
            ? SeatConnection.connected
            : SeatConnection.reconnecting,
    ];
  }

  /// Starts bot work for the current state. Safe to call repeatedly.
  void _schedule() {
    if (disposed || _paused) return;
    final s = _state;
    if (s.phase == GamePhase.arranging) {
      for (final seat in _bots.keys) {
        if (!s.isReady(seat) && !_arranging.contains(seat)) {
          _arrangeBot(seat, s.round);
        }
      }
    } else if (s.phase == GamePhase.playing) {
      final turn = s.turnSeat;
      if (turn != null && _bots.containsKey(turn) && _playTimer == null) {
        final fresh =
            s.groupIndex > 0 &&
            s.roundPlays[s.groupIndex].every((p) => p == null);
        final version = s.version;
        _playTimer = Timer(fresh ? timing.afterGroup : timing.play, () {
          _playTimer = null;
          if (disposed || _paused) return;
          if (_state.version != version) {
            _schedule();
            return;
          }
          _commit(engine.applyMove(_state, PlayGroup(turn, s.groupIndex)));
        });
      }
    }
  }

  Future<void> _arrangeBot(int seat, int round) async {
    _arranging.add(seat);
    thinkingNotifier.value = {...thinkingNotifier.value, seat};
    final started = DateTime.now();
    final bot = _bots[seat]!;
    final view = PlayerView.of(_state, seat);
    // Bots always show a special hand: it ends the round in their favour.
    final show = ShowHand(seat);
    final canShow = engine.validateMove(_state, show).isValid;
    Arrangement? arrangement;
    if (!canShow) {
      try {
        arrangement = await botRunner(bot, view).timeout(botTimeout);
      } catch (e) {
        debugPrint(
          'Bot $seat could not arrange ($e); using a quick arrangement.',
        );
        arrangement = fallbackArrangement(view);
      }
    }
    final spread = timing.maxThink - timing.minThink;
    final target =
        timing.minThink +
        Duration(
          milliseconds: spread.inMilliseconds <= 0
              ? 0
              : _jitter.nextInt(spread.inMilliseconds),
        );
    final elapsed = DateTime.now().difference(started);
    if (elapsed < target) {
      await Future<void>.delayed(target - elapsed);
    }
    _arranging.remove(seat);
    if (disposed) return;
    thinkingNotifier.value = {...thinkingNotifier.value}..remove(seat);
    final GameMove move = arrangement == null
        ? show
        : SubmitArrangement(seat, arrangement);
    if (_state.round == round && engine.validateMove(_state, move).isValid) {
      _commit(engine.applyMove(_state, move));
    }
  }

  @override
  void onPause() {
    _paused = true;
    _playTimer?.cancel();
    _playTimer = null;
  }

  @override
  void onResume() {
    _paused = false;
    _schedule();
  }

  @override
  Future<void> dispose() async {
    _playTimer?.cancel();
    for (final t in _graceTimers.values) {
      t.cancel();
    }
    for (final s in _subs) {
      await s.cancel();
    }
    for (final r in _remotes.values) {
      await r.close();
    }
    await super.dispose();
  }
}
