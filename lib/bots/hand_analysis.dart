import 'dart:typed_data';

import '../game/engine/random_source.dart';
import '../game/models/card.dart';
import '../game/models/game_state.dart';
import '../game/rules/hand_evaluator.dart';

/// How likely a group of a given strength is to beat one opponent's group.
abstract class GroupDistribution {
  /// Probability that an opponent's group is weaker than [strength]
  /// (ties count half).
  double probabilityBeats(int strength);
}

/// Empirical cumulative distribution of group strengths.
class StrengthCdf implements GroupDistribution {
  StrengthCdf(List<int> samples) : _sorted = (List.of(samples)..sort());

  final List<int> _sorted;

  int get sampleCount => _sorted.length;

  @override
  double probabilityBeats(int strength) {
    if (_sorted.isEmpty) return 0.5;
    final lo = _lowerBound(strength);
    var hi = lo;
    while (hi < _sorted.length && _sorted[hi] == strength) {
      hi++;
    }
    return (lo + (hi - lo) / 2) / _sorted.length;
  }

  int _lowerBound(int v) {
    var lo = 0, hi = _sorted.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_sorted[mid] < v) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  static StrengthCdf? _random3;
  static StrengthCdf? _random4;

  /// Distribution of every possible three-card group (exhaustive).
  static StrengthCdf get random3 => _random3 ??= () {
    final deck = fullDeck();
    final samples = <int>[];
    for (var a = 0; a < 52; a++) {
      for (var b = a + 1; b < 52; b++) {
        for (var c = b + 1; c < 52; c++) {
          samples.add(
            HandEvaluator.evaluate([deck[a], deck[b], deck[c]]).strength,
          );
        }
      }
    }
    return StrengthCdf(samples);
  }();

  /// Distribution of four-card groups (seeded sample).
  static StrengthCdf get random4 => _random4 ??= () {
    final r = SeededRandomSource(4444);
    final deck = fullDeck();
    final samples = <int>[];
    for (var i = 0; i < 20000; i++) {
      final picked = <int>{};
      while (picked.length < 4) {
        picked.add(r.nextInt(52));
      }
      samples.add(
        HandEvaluator.evaluate([for (final p in picked) deck[p]]).strength,
      );
    }
    return StrengthCdf(samples);
  }();
}

/// Strength of the group an opponent plays in one position, when their
/// three random triples are played strongest first and their random quad
/// last. A cheap stand-in for real arrangements.
class PositionDistribution implements GroupDistribution {
  PositionDistribution(this.position);

  /// 0 for the strongest 3-card group, 2 for the weakest, 3 for the
  /// 4-card group.
  final int position;

  @override
  double probabilityBeats(int strength) {
    if (position == 3) return StrengthCdf.random4.probabilityBeats(strength);
    final p = StrengthCdf.random3.probabilityBeats(strength);
    // Their triple in this position is weaker than ours when at least
    // 3 - position of their three triples are.
    final below = [
      (1 - p) * (1 - p) * (1 - p),
      3 * p * (1 - p) * (1 - p),
      3 * p * p * (1 - p),
      p * p * p,
    ];
    var sum = 0.0;
    for (var k = 3 - position; k <= 3; k++) {
      sum += below[k];
    }
    return sum;
  }

  static final randomGroups = [
    for (var i = 0; i < kGroupCount; i++) PositionDistribution(i),
  ];
}

/// Pre-evaluates every 3- and 4-card subset of a 13-card hand, indexed by
/// a 13-bit mask, so arrangement search is cheap.
class HandAnalysis {
  HandAnalysis(List<PlayingCard> hand)
    : cards = List.unmodifiable(hand),
      strength = Int32List(1 << 13) {
    if (hand.length != kHandSize) {
      throw ArgumentError('Expected $kHandSize cards');
    }
    for (var a = 0; a < 13; a++) {
      for (var b = a + 1; b < 13; b++) {
        for (var c = b + 1; c < 13; c++) {
          final m3 = (1 << a) | (1 << b) | (1 << c);
          strength[m3] = HandEvaluator.evaluate([hand[a], hand[b], hand[c]])
              .strength;
          combos3.add(m3);
          for (var d = c + 1; d < 13; d++) {
            final m4 = m3 | (1 << d);
            strength[m4] = HandEvaluator.evaluate([
              hand[a],
              hand[b],
              hand[c],
              hand[d],
            ]).strength;
            combos4.add(m4);
          }
        }
      }
    }
  }

  static const int fullMask = (1 << 13) - 1;

  final List<PlayingCard> cards;
  final Int32List strength;
  final List<int> combos3 = [];
  final List<int> combos4 = [];

  List<PlayingCard> cardsOf(int mask) => [
    for (var i = 0; i < 13; i++)
      if (mask & (1 << i) != 0) cards[i],
  ];

  /// Every way to split the 9 cards in [mask] into three triples
  /// (unordered; 280 partitions).
  static Iterable<List<int>> triplePartitions(int mask) sync* {
    final first = _bits(mask);
    final i = first.first;
    final rest1 = first.sublist(1);
    for (var x = 0; x < rest1.length; x++) {
      for (var y = x + 1; y < rest1.length; y++) {
        final t1 = (1 << i) | (1 << rest1[x]) | (1 << rest1[y]);
        final remaining = _bits(mask & ~t1);
        final j = remaining.first;
        final rest2 = remaining.sublist(1);
        for (var u = 0; u < rest2.length; u++) {
          for (var v = u + 1; v < rest2.length; v++) {
            final t2 = (1 << j) | (1 << rest2[u]) | (1 << rest2[v]);
            final t3 = mask & ~t1 & ~t2;
            yield [t1, t2, t3];
          }
        }
      }
    }
  }

  /// The 280 ways to split nine positions (0..8) into three triples, as
  /// bit patterns over those positions.
  static final List<(int, int, int)> partitionPatterns = [
    for (final p in triplePartitions((1 << 9) - 1)) (p[0], p[1], p[2]),
  ];

  /// Maps a 9-bit [pattern] over [positions] to a hand mask.
  static int spread(int pattern, List<int> positions) {
    var m = 0;
    for (var i = 0; i < 9; i++) {
      if (pattern & (1 << i) != 0) m |= 1 << positions[i];
    }
    return m;
  }

  static List<int> _bits(int mask) => [
    for (var i = 0; i < 13; i++)
      if (mask & (1 << i) != 0) i,
  ];

  /// The arrangement for group [masks], in play order.
  Arrangement toArrangement(List<int> masks) =>
      Arrangement(HandEvaluator.playOrder([for (final m in masks) cardsOf(m)]));
}
