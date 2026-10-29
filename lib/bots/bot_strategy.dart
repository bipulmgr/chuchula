import 'dart:math' as math;
import 'dart:typed_data';

import '../game/engine/random_source.dart';
import '../game/models/card.dart';
import '../game/models/game_state.dart';
import '../game/models/player_view.dart';
import '../game/rules/hand_evaluator.dart';
import 'hand_analysis.dart';

enum BotDifficulty { easy, medium, hard }

/// A bot's decision interface. Bots receive only a [PlayerView], so they
/// can never see other players' hidden cards or future deals.
abstract class BotStrategy {
  const BotStrategy();

  BotDifficulty get difficulty;

  Arrangement arrange(PlayerView view);

  static BotStrategy forDifficulty(BotDifficulty d, {int? seed}) => switch (d) {
    BotDifficulty.easy => EasyBot(seed: seed),
    BotDifficulty.medium => const MediumBot(),
    BotDifficulty.hard => HardBot(seed: seed),
  };
}

/// Legal, simple play: usually sorts the hand and cuts it into groups,
/// sometimes groups cards at random.
class EasyBot extends BotStrategy {
  EasyBot({int? seed})
    : _random = seed == null ? SecureRandomSource() : SeededRandomSource(seed);

  final RandomSource _random;

  @override
  BotDifficulty get difficulty => BotDifficulty.easy;

  @override
  Arrangement arrange(PlayerView view) {
    final hand = List<PlayingCard>.of(view.myHand);
    if (_random.nextInt(3) == 0) {
      hand.setAll(0, _random.shuffled(hand));
    } else {
      // Sorted by rank: pairs and trails tend to stay together.
      hand.sort();
    }
    final groups = Arrangement.fromOrderedCards(hand).groups;
    // The 4-card group must be the weakest (played last); fix the cut up
    // when it is not and the hand allows it.
    if (!HandEvaluator.fourCardIsWeakest(groups)) {
      final fixed = HandEvaluator.fourCardWeakestArrangement(view.myHand);
      if (fixed != null) return Arrangement(fixed);
    }
    return Arrangement(HandEvaluator.playOrder(groups));
  }
}

/// Objective shared by medium and hard bots: expected group wins, plus a
/// weighted chance of sweeping all four groups.
class ArrangementObjective {
  const ArrangementObjective({this.sweepWeight = 1.0, this.opponents = 3});

  final double sweepWeight;
  final int opponents;

  double score(List<double> beatOneProbabilities) {
    var sum = 0.0;
    var all = 1.0;
    for (final p in beatOneProbabilities) {
      final win = math.pow(p, opponents).toDouble();
      sum += win;
      all *= win;
    }
    return sum + sweepWeight * all;
  }

  /// Leans towards high-variance (sweep) arrangements when behind, and
  /// towards steady points when an opponent is about to win.
  static ArrangementObjective fromView(PlayerView view) {
    final me = view.scores[view.mySeat];
    var bestOther = 0;
    for (var i = 0; i < view.scores.length; i++) {
      if (i != view.mySeat) bestOther = math.max(bestOther, view.scores[i]);
    }
    final deficit = bestOther - me;
    final weight = deficit >= 6 ? 3.0 : (deficit >= 3 ? 1.5 : 0.5);
    return ArrangementObjective(sweepWeight: weight);
  }
}

class ArrangementCandidate {
  ArrangementCandidate(this.groups, this.score);

  /// Group masks in play order: the triples strongest first, then the
  /// 4-card group.
  final List<int> groups;
  final double score;
}

/// Evaluates combinations against the strength opponents are likely to
/// field in each position (strongest 3-card group first, the 4-card group
/// last).
class MediumBot extends BotStrategy {
  const MediumBot();

  @override
  BotDifficulty get difficulty => BotDifficulty.medium;

  @override
  Arrangement arrange(PlayerView view) =>
      arrangeHand(view.myHand, ArrangementObjective.fromView(view));

  Arrangement arrangeHand(
    List<PlayingCard> hand,
    ArrangementObjective objective,
  ) {
    final a = HandAnalysis(hand);
    final best = searchArrangements(
      a,
      objective,
      positions: PositionDistribution.randomGroups,
    );
    return a.toArrangement(best.groups);
  }

  /// Searches every four-card group and every split of the rest into
  /// triples. The 4-card group is played last and must be weaker than all
  /// three triples; only if the hand allows no such arrangement is any
  /// arrangement considered.
  static ArrangementCandidate searchArrangements(
    HandAnalysis a,
    ArrangementObjective objective, {
    required List<GroupDistribution> positions,
  }) {
    // Win chances per position, computed once per group.
    final p3 = [
      for (var i = 0; i < 3; i++)
        () {
          final p = Float64List(1 << 13);
          for (final m in a.combos3) {
            p[m] = positions[i].probabilityBeats(a.strength[m]);
          }
          return p;
        }(),
    ];
    final p4 = Float64List(1 << 13);
    for (final m in a.combos4) {
      p4[m] = positions[3].probabilityBeats(a.strength[m]);
    }
    ArrangementCandidate? best;
    ArrangementCandidate? bestAny;
    final t = List<int>.filled(3, 0);
    final probs = List<double>.filled(4, 0);
    for (final q in a.combos4) {
      final qs = a.strength[q];
      final rest = [
        for (var i = 0; i < 13; i++)
          if (q & (1 << i) == 0) i,
      ];
      // Each triple's mask for this quad, by 9-bit pattern.
      final local = <int, int>{};
      int maskOf(int pattern) =>
          local[pattern] ??= HandAnalysis.spread(pattern, rest);
      for (final (x, y, z) in HandAnalysis.partitionPatterns) {
        t
          ..[0] = maskOf(x)
          ..[1] = maskOf(y)
          ..[2] = maskOf(z);
        t.sort((x, y) => a.strength[y].compareTo(a.strength[x]));
        final valid = a.strength[t[2]] > qs;
        if (!valid && best != null) continue;
        for (var i = 0; i < 3; i++) {
          probs[i] = p3[i][t[i]];
        }
        probs[3] = p4[q];
        final s = objective.score(probs);
        if (valid) {
          if (best == null || s > best.score) {
            best = ArrangementCandidate([...t, q], s);
          }
        } else if (bestAny == null || s > bestAny.score) {
          bestAny = ArrangementCandidate([...t, q], s);
        }
      }
    }
    return (best ?? bestAny)!;
  }
}

/// Models opponents: simulates hands they could hold (drawn only from
/// cards this bot has not seen), predicts how they would arrange them, and
/// optimizes against the strength each opponent is likely to field in each
/// group position.
class HardBot extends BotStrategy {
  const HardBot({this.seed, this.simulations = 20});

  final int? seed;
  final int simulations;

  @override
  BotDifficulty get difficulty => BotDifficulty.hard;

  @override
  Arrangement arrange(PlayerView view) {
    final random = seed == null
        ? SeededRandomSource(DateTime.now().microsecondsSinceEpoch)
        : SeededRandomSource(seed!);
    final known = view.knownCards;
    final unseen = [
      for (final c in fullDeck())
        if (!known.contains(c)) c,
    ];

    const model = MediumBot();
    // Strength each opponent fields in each position (play order).
    final samples = List.generate(kGroupCount, (_) => <int>[]);
    for (var i = 0; i < simulations; i++) {
      final hand = random.shuffled(unseen).take(kHandSize).toList();
      final arrangement = model.arrangeHand(
        hand,
        const ArrangementObjective(sweepWeight: 0.5),
      );
      final analysis = HandAnalysis(hand);
      for (var g = 0; g < kGroupCount; g++) {
        var mask = 0;
        for (final c in arrangement.groups[g]) {
          mask |= 1 << analysis.cards.indexOf(c);
        }
        samples[g].add(analysis.strength[mask]);
      }
    }
    final cdfs = [for (final s in samples) StrengthCdf(s)];
    final a = HandAnalysis(view.myHand);
    final best = MediumBot.searchArrangements(
      a,
      ArrangementObjective.fromView(view),
      positions: cdfs,
    );
    return a.toArrangement(best.groups);
  }
}
