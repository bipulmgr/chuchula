import '../models/card.dart';
import 'rule_config.dart';

/// Hand achievements evaluated on a player's dealt thirteen cards.
enum BonusType {
  fourOfAKind,
  sixPairs,
  threeTrails,

  /// One card of every rank (A..K). Instant match win.
  allRanks,
}

class Bonus {
  const Bonus(this.type, this.points);

  final BonusType type;
  final int points;

  Map<String, dynamic> toJson() => {'type': type.name, 'points': points};

  factory Bonus.fromJson(Map<String, dynamic> json) => Bonus(
    BonusType.values.byName(json['type'] as String),
    json['points'] as int,
  );

  @override
  bool operator ==(Object other) =>
      other is Bonus && other.type == type && other.points == points;

  @override
  int get hashCode => Object.hash(type, points);

  @override
  String toString() => 'Bonus(${type.name}, $points)';
}

class BonusDetector {
  const BonusDetector._();

  static Map<Rank, int> rankCounts(List<PlayingCard> hand) {
    final counts = <Rank, int>{};
    for (final c in hand) {
      counts[c.rank] = (counts[c.rank] ?? 0) + 1;
    }
    return counts;
  }

  static bool hasAllRanks(List<PlayingCard> hand) =>
      hand.length == 13 && rankCounts(hand).length == 13;

  /// Detects every bonus in [hand]. Each four of a kind scores separately;
  /// six pairs and three trails score once.
  ///
  /// Counting: a four of a kind contains two pairs, and a three of a kind
  /// contains one pair, when counting towards six pairs.
  static List<Bonus> detect(List<PlayingCard> hand, RuleConfig rules) {
    final counts = rankCounts(hand).values;
    final bonuses = <Bonus>[];
    if (rules.allRanksInstantWin && hasAllRanks(hand)) {
      bonuses.add(const Bonus(BonusType.allRanks, 0));
    }
    final quads = counts.where((n) => n == 4).length;
    for (var i = 0; i < quads; i++) {
      bonuses.add(Bonus(BonusType.fourOfAKind, rules.fourOfAKindPoints));
    }
    final pairs = counts.fold<int>(0, (sum, n) => sum + n ~/ 2);
    if (pairs >= 6) {
      bonuses.add(Bonus(BonusType.sixPairs, rules.sixPairsPoints));
    }
    final trails = counts.where((n) => n >= 3).length;
    if (trails >= 3) {
      bonuses.add(Bonus(BonusType.threeTrails, rules.threeTrailsPoints));
    }
    return bonuses;
  }

  /// The cards of [hand] that make the special [type], so only they are
  /// highlighted when the hand is shown: the four cards of each four of a
  /// kind, two cards of each pair, three cards of each trail, or the whole
  /// hand for all thirteen ranks.
  static Set<PlayingCard> specialCards(List<PlayingCard> hand, BonusType type) {
    final counts = rankCounts(hand);
    int take(int n) => switch (type) {
      BonusType.fourOfAKind => n == 4 ? 4 : 0,
      BonusType.sixPairs => n ~/ 2 * 2,
      BonusType.threeTrails => n >= 3 ? 3 : 0,
      BonusType.allRanks => n,
    };
    final used = <Rank, int>{};
    final out = <PlayingCard>{};
    for (final c in List.of(hand)..sort((a, b) => b.compareTo(a))) {
      final n = used[c.rank] ?? 0;
      if (n < take(counts[c.rank]!)) {
        used[c.rank] = n + 1;
        out.add(c);
      }
    }
    return out;
  }

  /// Ranks special hands against each other when several players show:
  /// all thirteen ranks, then three trails, six pairs, four of a kind.
  /// Two of the same kind compare by their ranks, highest first (the
  /// ranks of the fours, trails or pairs). Compare the lists
  /// lexicographically with [compareShowRanks].
  static List<int> showRank(List<PlayingCard> hand, BonusType type) {
    final counts = rankCounts(hand);
    final kind = switch (type) {
      BonusType.fourOfAKind => 0,
      BonusType.sixPairs => 1,
      BonusType.threeTrails => 2,
      BonusType.allRanks => 3,
    };
    final need = switch (type) {
      BonusType.fourOfAKind => 4,
      BonusType.sixPairs => 2,
      BonusType.threeTrails => 3,
      BonusType.allRanks => 99,
    };
    final ranks = [
      for (final e in counts.entries)
        if (e.value >= need) e.key.value,
    ]..sort((a, b) => b.compareTo(a));
    return [kind, ...ranks];
  }

  static int compareShowRanks(List<int> a, List<int> b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) return a[i].compareTo(b[i]);
    }
    return a.length.compareTo(b.length);
  }
}
