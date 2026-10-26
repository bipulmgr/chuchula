import 'package:chuchula/bots/bot_strategy.dart';
import 'package:chuchula/bots/hand_analysis.dart';
import 'package:chuchula/game/engine/game_engine.dart';
import 'package:chuchula/game/engine/random_source.dart';
import 'package:chuchula/game/models/card.dart';
import 'package:chuchula/game/models/game_state.dart';
import 'package:chuchula/game/models/moves.dart';
import 'package:chuchula/game/models/player_view.dart';
import 'package:chuchula/game/rules/hand_evaluator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  test('triple partitions of 9 cards: 280, disjoint, complete', () {
    const mask = 0x1FF; // 9 cards
    final parts = HandAnalysis.triplePartitions(mask).toList();
    expect(parts.length, 280);
    for (final p in parts) {
      expect(p[0] & p[1], 0);
      expect(p[1] & p[2], 0);
      expect(p[0] | p[1] | p[2], mask);
    }
  });

  test('strength CDF is monotonic', () {
    final c = StrengthCdf.random3;
    expect(c.sampleCount, 22100);
    final low = c.probabilityBeats(0);
    final high = c.probabilityBeats(1 << 30);
    expect(low, 0);
    expect(high, 1);
  });

  for (final d in BotDifficulty.values) {
    test('${d.name} bot always produces a legal arrangement', () {
      for (var seed = 0; seed < (d == BotDifficulty.hard ? 4 : 25); seed++) {
        final e = ChuchulaGameEngine(random: SeededRandomSource(seed));
        final s = start(e);
        if (s.phase != GamePhase.arranging) continue;
        final bot = BotStrategy.forDifficulty(d, seed: seed);
        for (var seat = 0; seat < 4; seat++) {
          final a = bot.arrange(PlayerView.of(s, seat));
          expect(
            e.validateArrangement(s, seat, a).isValid,
            isTrue,
            reason: '${d.name} seed $seed seat $seat',
          );
        }
      }
    });
  }

  test('medium bot keeps a trail together', () {
    const bot = MediumBot();
    final a = bot.arrangeHand(
      parseCards('AS AH AD 2C 5D 7H 9S JC 3D 8H 10S 4C 6D'),
      const ArrangementObjective(),
    );
    final hasTrail = a.groups.any(
      (g) => g.where((c) => c.rank == Rank.ace).length == 3,
    );
    expect(hasTrail, isTrue);
  });

  test('stronger bots beat easy bots over many rounds', () {
    // Seat 0 medium, seat 1 hard, seats 2-3 easy.
    final bots = <BotStrategy>[
      const MediumBot(),
      HardBot(seed: 1, simulations: 12),
      EasyBot(seed: 2),
      EasyBot(seed: 3),
    ];
    final wins = List.filled(4, 0);
    final e = ChuchulaGameEngine(random: SeededRandomSource(99));
    var s = start(e);
    for (var round = 0; round < 12; round++) {
      if (s.phase == GamePhase.matchOver) {
        s = start(e);
      }
      if (s.phase == GamePhase.roundOver) {
        s = e.applyMove(s, const StartNextRound(0));
        continue;
      }
      for (var seat = 0; seat < 4; seat++) {
        s = e.applyMove(
          s,
          SubmitArrangement(seat, bots[seat].arrange(PlayerView.of(s, seat))),
        );
      }
      s = playRound(e, s);
      for (final w in s.history.last.groupWinners) {
        wins[w]++;
      }
    }
    final strong = wins[0] + wins[1];
    final weak = wins[2] + wins[3];
    expect(strong, greaterThan(weak), reason: 'wins: $wins');
  });

  test("Suggest on Bipul's hand puts the weakest group, of 4, last", () {
    final hand = parseCards('5D 5H 6H 7H 2D 3D AH 2S 6S 8S 10C KH AC');
    for (final bot in [const MediumBot(), HardBot(seed: 3)]) {
      final a = bot is MediumBot
          ? bot.arrangeHand(hand, const ArrangementObjective())
          : bot.arrange(
              PlayerView.of(
                start(
                  fixedEngine([
                    deckFor(['5D 5H 6H 7H 2D 3D AH 2S 6S 8S 10C KH AC']),
                  ]),
                ),
                0,
              ),
            );
      final why = '${bot.runtimeType}: ${a.groups}';
      expect([for (final g in a.groups) g.length], [3, 3, 3, 4], reason: why);
      expect(HandEvaluator.fourCardIsWeakest(a.groups), isTrue, reason: why);
      final strengths = [
        for (final g in a.groups.take(3)) HandEvaluator.evaluate(g).strength,
      ];
      expect(strengths, [...strengths]..sort((x, y) => y - x), reason: why);
    }
  });
}
