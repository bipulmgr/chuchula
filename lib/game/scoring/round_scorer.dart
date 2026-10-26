import '../models/game_state.dart';
import '../rules/bonuses.dart';
import '../rules/rule_config.dart';

/// Points for one seat in one round, with the breakdown shown in the
/// round summary.
class SeatScore {
  const SeatScore({
    required this.groupsWon,
    required this.groupPoints,
    required this.bonuses,
    required this.total,
    required this.swept,
  });

  final int groupsWon;
  final int groupPoints;
  final List<Bonus> bonuses;
  final int total;
  final bool swept;

  int get bonusPoints => bonuses.fold(0, (s, b) => s + b.points);
}

class RoundScorer {
  const RoundScorer._();

  static SeatScore scoreSeat({
    required int seat,
    required List<int> groupWinners,
    required List<Bonus> bonuses,
    required RuleConfig rules,
  }) {
    final won = groupWinners.where((w) => w == seat).length;
    final swept = won == kGroupCount;
    int groupPoints;
    if (swept) {
      groupPoints = rules.sweepReplacesGroupPoints
          ? rules.sweepPoints
          : won * rules.groupWinPoints + rules.sweepPoints;
    } else {
      groupPoints = won * rules.groupWinPoints;
    }
    final bonusPoints = bonuses.fold<int>(0, (s, b) => s + b.points);
    final total = rules.bonusesStackWithGroupPoints
        ? groupPoints + bonusPoints
        : (groupPoints > bonusPoints ? groupPoints : bonusPoints);
    return SeatScore(
      groupsWon: won,
      groupPoints: groupPoints,
      bonuses: bonuses,
      total: total,
      swept: swept,
    );
  }

  /// Applies the exact-target rule: a seat that would overshoot an exact
  /// target scores nothing this round.
  static int applyTarget(int current, int points, RuleConfig rules) {
    if (rules.targetIsExact && current + points > rules.targetScore) {
      return 0;
    }
    return points;
  }

  /// Decides whether the match is over after a round.
  ///
  /// Returns the winning seat, or null to keep playing. When several seats
  /// reach the target in the same round, the highest score wins; an exact
  /// tie for the highest score means another round is played.
  static int? matchWinner(List<int> scores, RuleConfig rules) {
    final reached = <int>[
      for (var i = 0; i < scores.length; i++)
        if (rules.targetIsExact
            ? scores[i] == rules.targetScore
            : scores[i] >= rules.targetScore)
          i
    ];
    if (reached.isEmpty) return null;
    final best = reached.map((i) => scores[i]).reduce((a, b) => a > b ? a : b);
    final leaders = reached.where((i) => scores[i] == best).toList();
    return leaders.length == 1 ? leaders.single : null;
  }
}
