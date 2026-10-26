import '../models/card.dart';

/// Combination categories, weakest first. Every group, of 3 or 4 cards, is
/// ranked on this one ladder; see docs/GAME_RULES.md.
enum HandCategory {
  highCard,
  pair,
  twoPair,
  color,
  sequence,
  pureSequence,
  trail,
  fourOfAKind,
}

/// The evaluated value of a 3- or 4-card group.
///
/// Groups of either size compare on one scale: the category first, then a
/// four-card version of the category (all four cards in the color or run)
/// above a three-card one, then the deciding ranks. Every card in the deck
/// is unique, so two groups from one deal never compare equal (the suit of
/// the highest card breaks exact rank ties).
class HandValue implements Comparable<HandValue> {
  const HandValue({
    required this.size,
    required this.category,
    required this.fourCard,
    required this.keys,
    required this.tieBreakSuit,
    required this.strength,
    this.spare,
  });

  final int size;
  final HandCategory category;

  /// True when all four cards make the category (four-card color, run,
  /// double run, two pair or four of a kind). A 4-card group without this
  /// is named after the best three cards in it.
  final bool fourCard;

  /// Rank keys in comparison order (after the category).
  final List<int> keys;

  /// Best suit among the cards of the highest rank in the group.
  final Suit tieBreakSuit;

  /// A single integer encoding of the value; larger is stronger.
  final int strength;

  /// The card that does not count, in a 4-card group that is not a full
  /// 4-card hand.
  final PlayingCard? spare;

  @override
  int compareTo(HandValue other) => strength.compareTo(other.strength);

  bool operator >(HandValue other) => compareTo(other) > 0;
  bool operator <(HandValue other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is HandValue && other.strength == strength;

  @override
  int get hashCode => strength.hashCode;

  @override
  String toString() =>
      'HandValue($category${fourCard ? ' (4)' : ''}, $keys, '
      '${tieBreakSuit.code})';
}

/// Teen Patti style evaluation, adapted for Chuchula's 3- and 4-card groups.
///
/// See docs/GAME_RULES.md for the full ranking tables.
class HandEvaluator {
  const HandEvaluator._();

  /// Categories a full four-card group can make.
  static const fourCardCategories = {
    HandCategory.twoPair,
    HandCategory.color,
    HandCategory.sequence,
    HandCategory.pureSequence,
    HandCategory.fourOfAKind,
  };

  static HandValue evaluate(List<PlayingCard> cards) {
    final size = cards.length;
    if (size != 3 && size != 4) {
      throw ArgumentError('A group must contain 3 or 4 cards, got $size');
    }
    if (cards.toSet().length != size) {
      throw ArgumentError('A group cannot contain duplicate cards: $cards');
    }
    final tieBreakSuit = _tieBreakSuit(cards);
    if (size == 3) {
      final (category, keys) = _classify(cards);
      return _value(3, category, false, keys, tieBreakSuit);
    }
    // Four cards: the full four-card hand if all four make one. Otherwise
    // the group is worth exactly its best three cards; the spare fourth
    // card adds nothing (not even a tie-break).
    HandValue? best;
    final (category, keys) = _classify(cards);
    if (fourCardCategories.contains(category)) {
      best = _value(4, category, true, keys, tieBreakSuit);
    }
    for (var skip = 0; skip < 4; skip++) {
      final three = [
        for (var i = 0; i < 4; i++)
          if (i != skip) cards[i],
      ];
      final (c3, k3) = _classify(three);
      final v = _value(
        4,
        c3,
        false,
        k3,
        _tieBreakSuit(three),
        spare: cards[skip],
      );
      if (best == null || v > best) best = v;
    }
    return best!;
  }

  static HandValue _value(
    int size,
    HandCategory category,
    bool fourCard,
    List<int> keys,
    Suit tieBreakSuit, {
    PlayingCard? spare,
  }) {
    var strength = category.index * 2 + (fourCard ? 1 : 0);
    for (var i = 0; i < 4; i++) {
      strength = strength * 16 + (i < keys.length ? keys[i] : 0);
    }
    strength = strength * 4 + tieBreakSuit.index;
    return HandValue(
      size: size,
      category: category,
      fourCard: fourCard,
      keys: List.unmodifiable(keys),
      tieBreakSuit: tieBreakSuit,
      strength: strength,
      spare: spare,
    );
  }

  /// The "highest card" for suit tie-breaks. In a sequence A-2-3(-4) the
  /// ace is still the highest card.
  static Suit _tieBreakSuit(List<PlayingCard> cards) {
    var highest = 0;
    for (final c in cards) {
      if (c.rank.value > highest) highest = c.rank.value;
    }
    return cards
        .where((c) => c.rank.value == highest)
        .map((c) => c.suit)
        .reduce((a, b) => a.index >= b.index ? a : b);
  }

  /// Category and deciding ranks of exactly these cards.
  static (HandCategory, List<int>) _classify(List<PlayingCard> cards) {
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
    final topCount = counts[grouped.first]!;

    if (topCount == 4) return (HandCategory.fourOfAKind, [grouped.first]);
    if (topCount == 3) return (HandCategory.trail, grouped);
    if (sequenceKey != null && isFlush) {
      return (HandCategory.pureSequence, [sequenceKey]);
    }
    if (sequenceKey != null) return (HandCategory.sequence, [sequenceKey]);
    if (isFlush) return (HandCategory.color, values);
    if (topCount == 2 && counts[grouped[1]] == 2) {
      return (HandCategory.twoPair, grouped);
    }
    if (topCount == 2) return (HandCategory.pair, grouped);
    return (HandCategory.highCard, values);
  }

  /// Bot and Suggest tidy-up: if the 4-card group is not a full 4-card
  /// hand, its spare card is moved to the weakest 3-card group, so a strong
  /// hand is not padded with a card that adds nothing. No group gets
  /// weaker. Returns the groups strongest first.
  static List<List<PlayingCard>> spareToWeakest(
    List<List<PlayingCard>> groups,
  ) {
    final sorted = strongestFirst(groups);
    final q = sorted.indexWhere((g) => g.length == 4);
    final value = evaluate(sorted[q]);
    final weakest = sorted.lastIndexWhere((g) => g.length == 3);
    if (value.fourCard || value.spare == null || weakest < q) return sorted;
    final spare = value.spare!;
    final next = List.of(sorted);
    next[q] = [
      for (final c in sorted[q])
        if (c != spare) c,
    ];
    next[weakest] = [...sorted[weakest], spare];
    return strongestFirst(next);
  }

  /// [groups] reordered strongest first, the order in
  /// which they are played.
  static List<List<PlayingCard>> strongestFirst(
    List<List<PlayingCard>> groups,
  ) {
    final values = {for (final g in groups) g: evaluate(g).strength};
    return List.of(groups)..sort((a, b) => values[b]!.compareTo(values[a]!));
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
