import '../models/card.dart';

/// Combination categories. The relative strength of each category depends on
/// the group size; see [HandEvaluator.categoryOrder3] and
/// [HandEvaluator.categoryOrder4].
enum HandCategory {
  highCard,
  pair,
  twoPair,
  color,
  sequence,
  trail,
  pureSequence,
  fourOfAKind,
}

/// The evaluated value of a 3- or 4-card group.
///
/// Values of groups with the same size are totally ordered: because every
/// card in the deck is unique, two different groups never compare equal
/// (the suit of the highest card breaks exact rank ties).
class HandValue implements Comparable<HandValue> {
  const HandValue({
    required this.size,
    required this.category,
    required this.keys,
    required this.tieBreakSuit,
    required this.strength,
  });

  final int size;
  final HandCategory category;

  /// Rank keys in comparison order (after the category).
  final List<int> keys;

  /// Best suit among the cards of the highest rank in the group.
  final Suit tieBreakSuit;

  /// A single integer encoding of the value; larger is stronger.
  final int strength;

  @override
  int compareTo(HandValue other) {
    if (other.size != size) {
      throw ArgumentError(
        'Cannot compare a $size-card group with a '
        '${other.size}-card group',
      );
    }
    return strength.compareTo(other.strength);
  }

  bool operator >(HandValue other) => compareTo(other) > 0;
  bool operator <(HandValue other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is HandValue && other.size == size && other.strength == strength;

  @override
  int get hashCode => Object.hash(size, strength);

  @override
  String toString() => 'HandValue($category, $keys, ${tieBreakSuit.code})';
}

/// Teen Patti style evaluation, adapted for Chuchula's 3- and 4-card groups.
///
/// See docs/GAME_RULES.md for the full ranking tables.
class HandEvaluator {
  const HandEvaluator._();

  /// Three-card ranking, strongest last (classic Teen Patti).
  static const categoryOrder3 = <HandCategory>[
    HandCategory.highCard,
    HandCategory.pair,
    HandCategory.color,
    HandCategory.sequence,
    HandCategory.pureSequence,
    HandCategory.trail,
  ];

  /// Four-card ranking, strongest last (ordered by rarity).
  static const categoryOrder4 = <HandCategory>[
    HandCategory.highCard,
    HandCategory.pair,
    HandCategory.twoPair,
    HandCategory.color,
    HandCategory.sequence,
    HandCategory.trail,
    HandCategory.pureSequence,
    HandCategory.fourOfAKind,
  ];

  static HandValue evaluate(List<PlayingCard> cards) {
    final size = cards.length;
    if (size != 3 && size != 4) {
      throw ArgumentError('A group must contain 3 or 4 cards, got $size');
    }
    if (cards.toSet().length != size) {
      throw ArgumentError('A group cannot contain duplicate cards: $cards');
    }

    final values = cards.map((c) => c.rank.value).toList()
      ..sort((a, b) => b.compareTo(a));
    final counts = <int, int>{};
    for (final v in values) {
      counts[v] = (counts[v] ?? 0) + 1;
    }
    // Ranks ordered by (count desc, rank desc).
    final grouped = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0 ? byCount : b.compareTo(a);
      });

    final isFlush = cards.every((c) => c.suit == cards.first.suit);
    final sequenceKey = _sequenceKey(values);

    HandCategory category;
    List<int> keys;
    final topCount = counts[grouped.first]!;

    if (topCount == 4) {
      category = HandCategory.fourOfAKind;
      keys = [grouped.first];
    } else if (topCount == 3) {
      category = HandCategory.trail;
      keys = grouped;
    } else if (sequenceKey != null && isFlush) {
      category = HandCategory.pureSequence;
      keys = [sequenceKey];
    } else if (sequenceKey != null) {
      category = HandCategory.sequence;
      keys = [sequenceKey];
    } else if (isFlush) {
      category = HandCategory.color;
      keys = values;
    } else if (topCount == 2 && counts[grouped[1]] == 2) {
      category = HandCategory.twoPair;
      keys = grouped;
    } else if (topCount == 2) {
      category = HandCategory.pair;
      keys = grouped;
    } else {
      category = HandCategory.highCard;
      keys = values;
    }

    // The "highest card" for suit tie-breaks. In a sequence A-2-3(-4) the
    // ace is still the highest card.
    final highestRank = values.first;
    final tieBreakSuit = cards
        .where((c) => c.rank.value == highestRank)
        .map((c) => c.suit)
        .reduce((a, b) => a.index >= b.index ? a : b);

    final order = size == 3 ? categoryOrder3 : categoryOrder4;
    var strength = order.indexOf(category);
    for (var i = 0; i < 4; i++) {
      strength = strength * 16 + (i < keys.length ? keys[i] : 0);
    }
    strength = strength * 4 + tieBreakSuit.index;

    return HandValue(
      size: size,
      category: category,
      keys: List.unmodifiable(keys),
      tieBreakSuit: tieBreakSuit,
      strength: strength,
    );
  }

  /// Returns a comparison key for a run of consecutive ranks, or null.
  ///
  /// The top run (A-K-Q or A-K-Q-J) scores 15, the ace-low run
  /// (A-2-3 or A-2-3-4) scores 14, and every other run scores its top rank.
  static int? _sequenceKey(List<int> valuesDesc) {
    if (valuesDesc.toSet().length != valuesDesc.length) return null;
    final n = valuesDesc.length;
    final isRun = valuesDesc.first - valuesDesc.last == n - 1;
    if (isRun) {
      return valuesDesc.first == 14 ? 15 : valuesDesc.first;
    }
    // Ace-low: A,(n-1)...2  e.g. [14,3,2] or [14,4,3,2].
    if (valuesDesc.first == 14) {
      final rest = valuesDesc.sublist(1);
      if (rest.first == n && rest.last == 2) return 14;
    }
    return null;
  }

  /// Index of the strongest group, or -1 for an empty list.
  static int bestIndex(List<HandValue> values) {
    var best = -1;
    for (var i = 0; i < values.length; i++) {
      if (best < 0 || values[i] > values[best]) best = i;
    }
    return best;
  }
}
