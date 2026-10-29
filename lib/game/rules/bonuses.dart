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
}
