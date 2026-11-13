import 'dart:async';
import 'dart:convert';

import 'package:chuchula/bots/bot_strategy.dart';
import 'package:chuchula/features/setup/offline_game.dart';
import 'package:chuchula/game/engine/game_engine.dart';
import 'package:chuchula/game/engine/random_source.dart';
import 'package:chuchula/game/models/game_state.dart';
import 'package:chuchula/game/models/player_view.dart';
import 'package:chuchula/game/rules/bonuses.dart';
import 'package:chuchula/game/rules/rule_config.dart';
import 'package:chuchula/game/state/authority_session.dart';
import 'package:chuchula/game/state/game_session.dart';
import 'package:chuchula/persistence/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Drives the human seat like a player would: arranges with the medium bot
/// logic when it is time to arrange, plays when it is its turn, deals the
/// next round from the summary.
Future<PlayerView> playToEnd(GameSession session, {int maxSteps = 5000}) async {
  for (var i = 0; i < maxSteps; i++) {
    await Future<void>.delayed(Duration.zero);
    final v = session.view.value!;
    if (v.phase == GamePhase.matchOver) return v;
    if (v.mustAnswerShow) {
      // Answer another player's show: show a special if the hand has one.
      final best = ChuchulaGameEngine.bestShow(
        BonusDetector.detect(v.myHand, RuleConfig.standard),
      );
      await (best == null ? session.passShow() : session.showHand(best));
    } else if (v.phase == GamePhase.arranging && v.myArrangement == null) {
      await session.submitArrangement(const MediumBot().arrange(v));
    } else if (v.isMyTurn) {
      await session.playGroup();
    } else if (v.phase == GamePhase.roundOver) {
      await session.startNextRound();
    }
  }
  fail('Match did not finish');
}

void main() {
  late LocalStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
  });

  for (final difficulty in BotDifficulty.values) {
    test(
      'complete offline match against three ${difficulty.name} bots',
      () async {
        final engine = ChuchulaGameEngine(
          random: SeededRandomSource(difficulty.index + 10),
        );
        final state = OfflineGame.newMatch(
          engine: engine,
          playerName: 'You',
          botNames: ['A', 'B', 'C'],
        );
        final session = OfflineGame.session(
          store: store,
          state: state,
          difficulty: difficulty,
          engine: engine,
          timing: const BotTiming.instant(),
          runner: inlineBotRunner,
        );
        final end = await playToEnd(session);
        expect(end.result, isNotNull);
        final winner = end.result!.winnerSeat;
        if (end.result!.reason == MatchEndReason.targetReached) {
          expect(end.scores[winner], greaterThanOrEqualTo(20));
        }
        for (var i = 0; i < 4; i++) {
          expect(
            end.scores[i],
            end.history.fold<int>(0, (t, r) => t + r.points[i]),
          );
        }
        // Finished matches are not offered for resume.
        expect(SavedMatch.tryParse(store.loadSavedMatch()), isNull);
        await session.dispose();
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }

  test('save and resume mid-round restores the exact state', () async {
    final engine = ChuchulaGameEngine(random: SeededRandomSource(77));
    final state = OfflineGame.newMatch(
      engine: engine,
      playerName: 'You',
      botNames: ['A', 'B', 'C'],
    );
    final session = OfflineGame.session(
      store: store,
      state: state,
      difficulty: BotDifficulty.easy,
      engine: engine,
      timing: const BotTiming.instant(),
      runner: inlineBotRunner,
    );
    // Arrange and play the first group.
    await Future<void>.delayed(Duration.zero);
    var v = session.view.value!;
    await session.submitArrangement(const MediumBot().arrange(v));
    for (var i = 0; i < 50 && session.view.value!.groupWinners.isEmpty; i++) {
      await Future<void>.delayed(Duration.zero);
      if (session.view.value!.isMyTurn) await session.playGroup();
    }
    final before = session.state;
    await session.dispose();

    final saved = SavedMatch.tryParse(store.loadSavedMatch());
    expect(saved, isNotNull);
    expect(jsonEncode(saved!.state.toJson()), jsonEncode(before.toJson()));
    expect(saved.difficulty, BotDifficulty.easy);

    final resumed = OfflineGame.session(
      store: store,
      state: saved.state,
      difficulty: saved.difficulty,
      timing: const BotTiming.instant(),
      runner: inlineBotRunner,
    );
    v = resumed.view.value!;
    expect(v.round, before.round);
    expect(v.groupWinners, before.groupWinners);
    final end = await playToEnd(resumed);
    expect(end.phase, GamePhase.matchOver);
    await resumed.dispose();
  });

  test('corrupt or incompatible saves are ignored', () async {
    expect(SavedMatch.tryParse({'state': 'nonsense'}), isNull);
    expect(
      SavedMatch.tryParse({
        'state': {'schema': 1},
      }),
      isNull,
    );
    expect(SavedMatch.tryParse(null), isNull);
    SharedPreferences.setMockInitialValues({'savedMatch.v1': '{not json'});
    final s = await LocalStore.open();
    expect(s.loadSavedMatch(), isNull);
  });

  test('wrong-turn moves from the UI are rejected with an event', () async {
    final engine = ChuchulaGameEngine(random: SeededRandomSource(5));
    final session = OfflineGame.session(
      store: store,
      state: OfflineGame.newMatch(
        engine: engine,
        playerName: 'You',
        botNames: ['A', 'B', 'C'],
      ),
      difficulty: BotDifficulty.easy,
      engine: engine,
      timing: const BotTiming.instant(),
      runner: inlineBotRunner,
    );
    final events = <SessionEvent>[];
    session.events.listen(events.add);
    await session.playGroup(); // still arranging
    await Future<void>.delayed(Duration.zero);
    expect(events.whereType<MoveRejected>(), isNotEmpty);
    await session.dispose();
  });

  test('pausing stops bots; resuming continues', () async {
    final engine = ChuchulaGameEngine(random: SeededRandomSource(6));
    final session = OfflineGame.session(
      store: store,
      state: OfflineGame.newMatch(
        engine: engine,
        playerName: 'You',
        botNames: ['A', 'B', 'C'],
      ),
      difficulty: BotDifficulty.easy,
      engine: engine,
      timing: const BotTiming.instant(),
      runner: inlineBotRunner,
    );
    session.onPause(); // before the bots get a chance to arrange
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(session.view.value!.ready, [false, false, false, false]);
    session.onResume();
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(session.view.value!.ready, [false, true, true, true]);
    await session.dispose();
  });

  group('bots never get stuck arranging', () {
    Future<void> expectBotsReady(BotRunner runner, {Duration? budget}) async {
      final engine = ChuchulaGameEngine(random: SeededRandomSource(7));
      final session = AuthorityGameSession(
        engine: engine,
        initialState: OfflineGame.newMatch(
          engine: engine,
          playerName: 'You',
          botNames: ['A', 'B', 'C'],
        ),
        localSeat: 0,
        bots: {for (var s = 1; s < 4; s++) s: const MediumBot()},
        timing: const BotTiming.instant(),
        botRunner: runner,
        botTimeout: budget ?? const Duration(seconds: 5),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      // Done when every bot has tapped Ready or shown a special hand.
      bool waiting() {
        final v = session.view.value!;
        return (v.phase == GamePhase.arranging &&
                [1, 2, 3].any((s) => !v.ready[s] && v.shows[s] == null)) ||
            session.thinking.value.isNotEmpty;
      }

      while (waiting()) {
        if (DateTime.now().isAfter(deadline)) fail('bots never arranged');
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(session.thinking.value, isEmpty);
      await session.dispose();
    }

    test('when the background runner throws (e.g. no isolates on web)', () {
      return expectBotsReady(
        (bot, view) => Future.error(UnsupportedError('Isolate.run')),
      );
    });

    test('when the background runner never answers', () {
      return expectBotsReady(
        (bot, view) => Completer<Arrangement>().future,
        budget: const Duration(milliseconds: 200),
      );
    });

    test('with the default runner', () => expectBotsReady(isolateBotRunner));
  });
}
