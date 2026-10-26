/// Tunable Chuchula rules. Defaults follow docs/GAME_RULES.md; every rule
/// that was still awaiting confirmation is a switch here so it can be
/// changed without touching the engine.
class RuleConfig {
  const RuleConfig({
    this.targetScore = 20,
    this.targetIsExact = false,
    this.groupWinPoints = 1,
    this.sweepPoints = 5,
    this.sweepReplacesGroupPoints = true,
    this.fourOfAKindPoints = 4,
    this.sixPairsPoints = 6,
    this.threeTrailsPoints = 9,
    this.bonusesStackWithGroupPoints = true,
    this.allRanksInstantWin = true,
    this.requireAscendingStrength = false,
    this.maxRounds = 100,
  });

  /// Points needed to win the match.
  final int targetScore;

  /// If true the match ends only when a player reaches exactly
  /// [targetScore]; points that would overshoot are not awarded.
  /// Default: false (reaching *at least* the target wins).
  final bool targetIsExact;

  final int groupWinPoints;

  /// Awarded for winning all four groups in a round.
  final int sweepPoints;

  /// If true a sweep is worth [sweepPoints] in total instead of
  /// 4 x [groupWinPoints] + [sweepPoints].
  final bool sweepReplacesGroupPoints;

  final int fourOfAKindPoints;
  final int sixPairsPoints;

  /// "Three trials": three separate three-of-a-kinds (trails) in the hand.
  final int threeTrailsPoints;

  /// If false, a player who earns a hand bonus gets only the larger of the
  /// bonus total and the group-win total for that round.
  final bool bonusesStackWithGroupPoints;

  /// One card of each of the thirteen ranks wins the match immediately.
  final bool allRanksInstantWin;

  /// If true, groups 1..3 must be non-decreasing in strength (the 4-card
  /// group is compared separately). Default false: any order is allowed.
  final bool requireAscendingStrength;

  /// Safety valve against endless matches (e.g. with [targetIsExact]).
  final int maxRounds;

  static const standard = RuleConfig();

  Map<String, dynamic> toJson() => {
    'targetScore': targetScore,
    'targetIsExact': targetIsExact,
    'groupWinPoints': groupWinPoints,
    'sweepPoints': sweepPoints,
    'sweepReplacesGroupPoints': sweepReplacesGroupPoints,
    'fourOfAKindPoints': fourOfAKindPoints,
    'sixPairsPoints': sixPairsPoints,
    'threeTrailsPoints': threeTrailsPoints,
    'bonusesStackWithGroupPoints': bonusesStackWithGroupPoints,
    'allRanksInstantWin': allRanksInstantWin,
    'requireAscendingStrength': requireAscendingStrength,
    'maxRounds': maxRounds,
  };

  factory RuleConfig.fromJson(Map<String, dynamic> json) {
    const d = RuleConfig.standard;
    return RuleConfig(
      targetScore: json['targetScore'] as int? ?? d.targetScore,
      targetIsExact: json['targetIsExact'] as bool? ?? d.targetIsExact,
      groupWinPoints: json['groupWinPoints'] as int? ?? d.groupWinPoints,
      sweepPoints: json['sweepPoints'] as int? ?? d.sweepPoints,
      sweepReplacesGroupPoints:
          json['sweepReplacesGroupPoints'] as bool? ??
          d.sweepReplacesGroupPoints,
      fourOfAKindPoints:
          json['fourOfAKindPoints'] as int? ?? d.fourOfAKindPoints,
      sixPairsPoints: json['sixPairsPoints'] as int? ?? d.sixPairsPoints,
      threeTrailsPoints:
          json['threeTrailsPoints'] as int? ?? d.threeTrailsPoints,
      bonusesStackWithGroupPoints:
          json['bonusesStackWithGroupPoints'] as bool? ??
          d.bonusesStackWithGroupPoints,
      allRanksInstantWin:
          json['allRanksInstantWin'] as bool? ?? d.allRanksInstantWin,
      requireAscendingStrength:
          json['requireAscendingStrength'] as bool? ??
          d.requireAscendingStrength,
      maxRounds: json['maxRounds'] as int? ?? d.maxRounds,
    );
  }
}
