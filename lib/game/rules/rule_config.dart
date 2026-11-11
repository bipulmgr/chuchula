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
    this.strongestFirst = true,
    this.fourCardWeakest = true,
    this.declareBonuses = true,
    this.maxRounds = 100,
    this.showWindowSeconds = 20,
    this.lastGroupDoubleRunWins = true,
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

  /// If true, each player's three 3-card groups are played strongest
  /// first and the 4-card group last. The engine puts submitted groups in
  /// that order. If false, groups are played in the order submitted.
  final bool strongestFirst;

  /// If true, the 4-card group must be weaker than every 3-card group
  /// (an arrangement breaking this is refused), unless the hand allows no
  /// such arrangement.
  final bool fourCardWeakest;

  /// If true, hand bonuses (and the all-ranks win) count only when the
  /// player shows them during arranging, which ends the round at once.
  /// If false, they are scored automatically from the dealt hand.
  final bool declareBonuses;

  /// Safety valve against endless matches (e.g. with [targetIsExact]).
  final int maxRounds;

  /// After a player shows a special hand, the others have this long to
  /// show theirs; the best special shown wins the round. 0 ends the round
  /// at the first show.
  final int showWindowSeconds;

  /// A player whose last group is a double run (pure sequence) wins the
  /// whole match, not just the round.
  final bool lastGroupDoubleRunWins;

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
    'strongestFirst': strongestFirst,
    'fourCardWeakest': fourCardWeakest,
    'declareBonuses': declareBonuses,
    'maxRounds': maxRounds,
    'showWindowSeconds': showWindowSeconds,
    'lastGroupDoubleRunWins': lastGroupDoubleRunWins,
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
      strongestFirst: json['strongestFirst'] as bool? ?? d.strongestFirst,
      fourCardWeakest: json['fourCardWeakest'] as bool? ?? d.fourCardWeakest,
      declareBonuses: json['declareBonuses'] as bool? ?? d.declareBonuses,
      maxRounds: json['maxRounds'] as int? ?? d.maxRounds,
      showWindowSeconds:
          json['showWindowSeconds'] as int? ?? d.showWindowSeconds,
      lastGroupDoubleRunWins:
          json['lastGroupDoubleRunWins'] as bool? ?? d.lastGroupDoubleRunWins,
    );
  }
}
