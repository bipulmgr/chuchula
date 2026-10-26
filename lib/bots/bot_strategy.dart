import 'dart:math' as math;

import '../game/engine/random_source.dart';
import '../game/models/card.dart';
import '../game/models/game_state.dart';
import '../game/models/player_view.dart';
import 'hand_analysis.dart';

enum BotDifficulty { easy, medium, hard }

/// A bot's decision interface. Bots receive only a [PlayerView], so they
/// can never see other players' hidden cards or future deals.
abstract class BotStrategy {
  const BotStrategy();

  BotDifficulty get difficulty;

  Arrangement arrange(PlayerView view);

  static BotStrategy forDifficulty(BotDifficulty d, {int? seed}) =>
      switch (d) {
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
      return Arrangement.fromOrderedCards(_random.shuffled(hand));
    }
    // Sorted by rank: pairs and trails tend to stay together.
    hand.sort();
    return Arrangement.fromOrderedCards(hand);
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

class _Candidate {
  _Candidate(this.triples, this.quad, this.score);
  final List<int> triples;
  final int quad;
  final double score;
}

/// Evaluates combinations against the distribution of random groups and
/// balances the four groups with a greedy-plus-search approach.
class MediumBot extends BotStrategy {
  const MediumBot({this.quadCandidates = 60});

  final int quadCandidates;

  @override
  BotDifficulty get difficulty => BotDifficulty.medium;

  @override
  Arrangement arrange(PlayerView view) =>
      arrangeHand(view.myHand, ArrangementObjective.fromView(view));

  Arrangement arrangeHand(
      List<PlayingCard> hand, ArrangementObjective objective) {
    final a = HandAnalysis(hand);
    final c3 = StrengthCdf.random3;
    final c4 = StrengthCdf.random4;
    final best = searchArrangements(
      a,
      objective,
      tripleCdfs: [c3, c3, c3],
      quadCdf: c4,
      quadCandidates: quadCandidates,
    );
    return a.toArrangement(best.triples, best.quad);
  }

  /// Searches four-card groups (strongest [quadCandidates] first), every
  /// split of the rest into triples, and every order of those triples.
  static _Candidate searchArrangements(
    HandAnalysis a,
    ArrangementObjective objective, {
    required List<StrengthCdf> tripleCdfs,
    required StrengthCdf quadCdf,
    required int quadCandidates,
  }) {
    final quads = List<int>.of(a.combos4)
      ..sort((x, y) => a.strength[y].compareTo(a.strength[x]));
    final consider = quads.take(quadCandidates);
    _Candidate? best;
    // With one shared distribution the order of the triples cannot change
    // the score, so only one order is searched (then sorted strongest
    // first below).
    final sameCdf = identical(tripleCdfs[0], tripleCdfs[1]) &&
        identical(tripleCdfs[1], tripleCdfs[2]);
    const allOrders = [
      [0, 1, 2],
      [0, 2, 1],
      [1, 0, 2],
      [1, 2, 0],
      [2, 0, 1],
      [2, 1, 0],
    ];
    final orders = sameCdf ? const [[0, 1, 2]] : allOrders;
    for (final q in consider) {
      final pq = quadCdf.probabilityBeats(a.strength[q]);
      for (final part in HandAnalysis.triplePartitions(
          HandAnalysis.fullMask & ~q)) {
        for (final o in orders) {
          final t = [part[o[0]], part[o[1]], part[o[2]]];
          final s = objective.score([
            tripleCdfs[0].probabilityBeats(a.strength[t[0]]),
            tripleCdfs[1].probabilityBeats(a.strength[t[1]]),
            tripleCdfs[2].probabilityBeats(a.strength[t[2]]),
            pq,
          ]);
          if (best == null || s > best.score) best = _Candidate(t, q, s);
        }
      }
    }
    if (sameCdf) {
      final sorted = List.of(best!.triples)
        ..sort((x, y) => a.strength[y].compareTo(a.strength[x]));
      best = _Candidate(sorted, best.quad, best.score);
    }
    return best!;
  }
}

/// Models opponents: simulates hands they could hold (drawn only from
/// cards this bot has not seen), predicts how they would arrange them, and
/// optimizes against the strength each opponent is likely to field in each
/// group position.
class HardBot extends BotStrategy {
  HardBot({int? seed, this.simulations = 20, this.quadCandidates = 100})
      : _seed = seed;

  final int? _seed;
  final int simulations;
  final int quadCandidates;

  @override
  BotDifficulty get difficulty => BotDifficulty.hard;

  @override
  Arrangement arrange(PlayerView view) {
    final random = _seed == null
        ? SeededRandomSource(DateTime.now().microsecondsSinceEpoch)
        : SeededRandomSource(_seed);
    final known = view.knownCards;
    final unseen = [for (final c in fullDeck()) if (!known.contains(c)) c];

    const model = MediumBot(quadCandidates: 30);
    final samples = List.generate(kGroupCount, (_) => <int>[]);
    for (var i = 0; i < simulations; i++) {
      final hand = random.shuffled(unseen).take(kHandSize).toList();
      final arrangement = model.arrangeHand(
          hand, const ArrangementObjective(sweepWeight: 0.5));
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
      tripleCdfs: cdfs.sublist(0, 3),
      quadCdf: cdfs[3],
      quadCandidates: quadCandidates,
    );
    return a.toArrangement(best.triples, best.quad);
  }
}
