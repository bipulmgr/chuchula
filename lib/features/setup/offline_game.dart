import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../bots/bot_strategy.dart';
import '../../core/localization/l10n.dart';
import '../../game/engine/game_engine.dart';
import '../../game/models/game_state.dart';
import '../../game/models/player_view.dart';
import '../../game/scoring/cash_points.dart';
import '../../game/state/authority_session.dart';
import '../../persistence/settings_repository.dart';
import '../table/table_screen.dart';

/// Saved offline match: the full authoritative state plus bot settings.
class SavedMatch {
  const SavedMatch(
    this.state,
    this.difficulty, {
    this.board = CashPoints.defaultBoard,
    this.showSuggest = false,
  });

  final GameState state;
  final BotDifficulty difficulty;

  /// The cash board this match is played on (see [CashPoints.boards]).
  final int board;

  /// Whether the table offers the Suggest button in this match.
  final bool showSuggest;

  Map<String, dynamic> toJson() => {
    'state': state.toJson(),
    'difficulty': difficulty.name,
    'board': board,
    'showSuggest': showSuggest,
  };

  /// Returns null for missing, corrupt, finished or incompatible saves.
  static SavedMatch? tryParse(Map<String, dynamic>? json) {
    if (json == null) return null;
    try {
      final state = GameState.fromJson(
        (json['state'] as Map).cast<String, dynamic>(),
      );
      if (state.phase == GamePhase.matchOver) return null;
      if (state.seats.length != kSeatCount ||
          state.hands.length != kSeatCount) {
        return null;
      }
      final board = json['board'] as int? ?? CashPoints.defaultBoard;
      return SavedMatch(
        state,
        BotDifficulty.values.byName(json['difficulty'] as String),
        board: CashPoints.boards.contains(board)
            ? board
            : CashPoints.defaultBoard,
        showSuggest: json['showSuggest'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}

class OfflineGame {
  const OfflineGame._();

  static const localSeat = 0;

  static GameState newMatch({
    required ChuchulaGameEngine engine,
    required String playerName,
    required List<String> botNames,
  }) => engine.startGame(
    GameSetup(
      matchId: 'offline-${DateTime.now().millisecondsSinceEpoch}',
      seats: [
        SeatInfo(id: 'local', name: playerName, avatar: 0),
        for (var i = 0; i < 3; i++)
          SeatInfo(id: 'bot$i', name: botNames[i], isBot: true, avatar: i + 1),
      ],
    ),
  );

  static AuthorityGameSession session({
    required LocalStore store,
    required GameState state,
    required BotDifficulty difficulty,
    int board = CashPoints.defaultBoard,
    bool showSuggest = false,
    ChuchulaGameEngine? engine,
    BotTiming timing = const BotTiming(),
    BotRunner runner = isolateBotRunner,
  }) {
    return AuthorityGameSession(
      engine: engine ?? ChuchulaGameEngine(),
      initialState: state,
      localSeat: localSeat,
      bots: {
        for (var seat = 1; seat < kSeatCount; seat++)
          seat: BotStrategy.forDifficulty(difficulty),
      },
      timing: timing,
      botRunner: runner,
      onStateChanged: (s) => s.phase == GamePhase.matchOver
          ? store.clearSavedMatch()
          : store.saveMatch(
              SavedMatch(
                s,
                difficulty,
                board: board,
                showSuggest: showSuggest,
              ).toJson(),
            ),
    );
  }

  /// Opens the table for an offline match and returns when the player
  /// leaves it.
  static Future<void> open(
    BuildContext context,
    WidgetRef ref, {
    GameState? resume,
    BotDifficulty? difficulty,
    int board = CashPoints.defaultBoard,
    bool showSuggest = false,
    required String playerName,
    required List<String> botNames,
  }) async {
    final store = ref.read(localStoreProvider);
    final level = difficulty ?? ref.read(settingsProvider).difficulty;
    final engine = ChuchulaGameEngine();
    var state =
        resume ??
        newMatch(engine: engine, playerName: playerName, botNames: botNames);
    SavedMatch saved(GameState s) =>
        SavedMatch(s, level, board: board, showSuggest: showSuggest);
    if (resume == null) {
      await store.saveMatch(saved(state).toJson());
    }
    if (!context.mounted) return;
    final navigator = Navigator.of(context);

    var again = true;
    while (again && context.mounted) {
      again = false;
      final session = OfflineGame.session(
        store: store,
        state: state,
        difficulty: level,
        board: board,
        showSuggest: showSuggest,
        engine: engine,
      );
      await navigator.push(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 450),
          pageBuilder: (_, _, _) => TableScreen(
            session: session,
            onMatchFinished: (v) => _recordStats(ref, v, board),
            stakeBoard: board,
            showSuggest: showSuggest,
            onPlayAgain: () {
              again = true;
              navigator.pop();
            },
          ),
          transitionsBuilder: (_, anim, _, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
      await session.dispose();
      // Another match on this board needs its entry again.
      if (again && !ref.read(walletProvider.notifier).canSit(board)) {
        again = false;
        if (context.mounted) {
          final l = context.l10n;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                l.boardTooHigh(
                  CashPoints.boardLabel(board),
                  CashPoints.entryFor(board),
                ),
              ),
            ),
          );
        }
      }
      if (again) {
        state = newMatch(
          engine: engine,
          playerName: playerName,
          botNames: botNames,
        );
        await store.saveMatch(saved(state).toJson());
      }
    }
  }

  static void _recordStats(WidgetRef ref, PlayerView v, int board) {
    final result = v.result;
    if (result != null) {
      ref
          .read(walletProvider.notifier)
          .settle(v.matchId, CashPoints.settle(result, board: board)[v.mySeat]);
    }
    final groups = v.history
        .expand((r) => r.groupWinners)
        .where((w) => w == v.mySeat)
        .length;
    final sweeps = v.history.where((r) => r.sweepSeat == v.mySeat).length;
    ref
        .read(statsProvider.notifier)
        .record(
          won: v.result?.winnerSeat == v.mySeat,
          groups: groups,
          sweeps: sweeps,
        );
  }
}
