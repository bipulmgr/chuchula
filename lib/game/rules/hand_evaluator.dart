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

  /// [groups] in the order they are played: the three 3-card groups
  /// strongest first, then the 4-card group last.
  static List<List<PlayingCard>> playOrder(List<List<PlayingCard>> groups) {
    final values = {for (final g in groups) g: evaluate(g).strength};
    return List.of(groups)..sort((a, b) {
      if (a.length != b.length) return a.length.compareTo(b.length);
      return values[b]!.compareTo(values[a]!);
    });
  }

  /// Strength of the best three cards in a 3- or 4-card group, valued as
  /// a 3-card hand. A player's own 4-card group is held against their
  /// 3-card groups this way (A-J-8-7 of one suit counts as the color
  /// A-J-8), while against other players it plays as a full 4-card hand.
  static int bestThreeStrength(List<PlayingCard> cards) {
    if (cards.length == 3) return evaluate(cards).strength;
    var best = -1;
    for (var skip = 0; skip < cards.length; skip++) {
      final s = evaluate([
        for (var i = 0; i < cards.length; i++)
          if (i != skip) cards[i],
      ]).strength;
      if (s > best) best = s;
    }
    return best;
  }

  /// True when the 4-card group, by its best three cards, is weaker than
  /// every 3-card group.
  static bool fourCardIsWeakest(List<List<PlayingCard>> groups) {
    final quads = groups.where((g) => g.length == 4).toList();
    if (quads.length != 1) return true;
    final q = bestThreeStrength(quads.single);
    return groups
        .where((g) => g.length == 3)
        .every((g) => evaluate(g).strength > q);
  }

  /// An arrangement of [hand] (13 cards) whose 4-card group (by its best
  /// three cards) is weaker than all three 3-card groups, in play order,
  /// or null if the hand has none. Tries the weakest 4-card groups first,
  /// so this is usually immediate.
  static List<List<PlayingCard>>? fourCardWeakestArrangement(
    List<PlayingCard> hand,
  ) {
    if (hand.length != 13) return null;
    final s3 = <int, int>{};
    for (var a = 0; a < 13; a++) {
      for (var b = a + 1; b < 13; b++) {
        for (var c = b + 1; c < 13; c++) {
          s3[(1 << a) | (1 << b) | (1 << c)] = evaluate([
            hand[a],
            hand[b],
            hand[c],
          ]).strength;
        }
      }
    }
    final quads = <(int, int)>[];
    for (var a = 0; a < 13; a++) {
      for (var b = a + 1; b < 13; b++) {
        for (var c = b + 1; c < 13; c++) {
          for (var d = c + 1; d < 13; d++) {
            final ma = 1 << a, mb = 1 << b, mc = 1 << c, md = 1 << d;
            var best = s3[mb | mc | md]!;
            for (final t in [ma | mc | md, ma | mb | md, ma | mb | mc]) {
              if (s3[t]! > best) best = s3[t]!;
            }
            quads.add((ma | mb | mc | md, best));
          }
        }
      }
    }
    // Ties (quads sharing their best three) break on the mask, so both
    // engines pick the same arrangement.
    quads.sort((x, y) {
      final c = x.$2.compareTo(y.$2);
      return c != 0 ? c : x.$1.compareTo(y.$1);
    });
    List<PlayingCard> cardsOf(int m) => [
      for (var i = 0; i < 13; i++)
        if (m & (1 << i) != 0) hand[i],
    ];
    for (final (q, qs) in quads) {
      final rest = [
        for (var i = 0; i < 13; i++)
          if (q & (1 << i) == 0) i,
      ];
      final first = rest.first;
      for (var x = 1; x < 9; x++) {
        for (var y = x + 1; y < 9; y++) {
          final t1 = (1 << first) | (1 << rest[x]) | (1 << rest[y]);
          if (s3[t1]! <= qs) continue;
          final left = [
            for (final i in rest)
              if (t1 & (1 << i) == 0) i,
          ];
          for (var u = 1; u < 6; u++) {
            for (var v = u + 1; v < 6; v++) {
              final t2 = (1 << left[0]) | (1 << left[u]) | (1 << left[v]);
              if (s3[t2]! <= qs) continue;
              var t3 = 0;
              for (final i in left) {
                if (t2 & (1 << i) == 0) t3 |= 1 << i;
              }
              if (s3[t3]! <= qs) continue;
              return playOrder([
                cardsOf(t1),
                cardsOf(t2),
                cardsOf(t3),
                cardsOf(q),
              ]);
            }
          }
        }
      }
    }
    return null;
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
