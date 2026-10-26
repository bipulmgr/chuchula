import '../rules/bonuses.dart';
import '../rules/rule_config.dart';
import 'card.dart';

const int kSeatCount = 4;
const int kHandSize = 13;
const int kGroupCount = 4;

/// Group sizes in a hand, ascending. Groups may sit in any position: they
/// are played strongest first, so the four-card group can come anywhere.
const List<int> kGroupSizes = [3, 3, 3, 4];

enum GamePhase { arranging, playing, roundOver, matchOver }

enum MatchEndReason { targetReached, instantWin, maxRounds }

List<String> _codes(List<PlayingCard> cards) =>
    cards.map((c) => c.code).toList();

List<PlayingCard> _cards(Object? json) =>
    (json as List).map((c) => PlayingCard.parse(c as String)).toList();

class SeatInfo {
  const SeatInfo({
    required this.id,
    required this.name,
    this.isBot = false,
    this.avatar = 0,
  });

  final String id;
  final String name;
  final bool isBot;

  /// Index into the avatar palette.
  final int avatar;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'isBot': isBot,
    'avatar': avatar,
  };

  factory SeatInfo.fromJson(Map<String, dynamic> json) => SeatInfo(
    id: json['id'] as String,
    name: json['name'] as String,
    isBot: json['isBot'] as bool? ?? false,
    avatar: json['avatar'] as int? ?? 0,
  );
}

/// A player's thirteen cards split into four ordered groups (3, 3, 3, 4).
class Arrangement {
  Arrangement(List<List<PlayingCard>> groups)
    : groups = List.unmodifiable(groups.map(List<PlayingCard>.unmodifiable));

  final List<List<PlayingCard>> groups;

  List<PlayingCard> get allCards => [for (final g in groups) ...g];

  List<List<String>> toJson() => [for (final g in groups) _codes(g)];

  factory Arrangement.fromJson(Object? json) =>
      Arrangement([for (final g in json as List) _cards(g)]);

  /// Splits an ordered 13-card list into groups using [kGroupSizes].
  factory Arrangement.fromOrderedCards(List<PlayingCard> ordered) {
    final groups = <List<PlayingCard>>[];
    var start = 0;
    for (final size in kGroupSizes) {
      groups.add(ordered.sublist(start, start + size));
      start += size;
    }
    return Arrangement(groups);
  }
}

class RoundResult {
  const RoundResult({
    required this.round,
    required this.groupWinners,
    required this.arrangements,
    required this.bonuses,
    required this.points,
    this.sweepSeat,
    this.instantWinSeat,
    this.instantWinHand,
    this.shownSeat,
  });

  final int round;

  /// Winning seat for each group (empty for an instant-win round).
  final List<int> groupWinners;

  /// Every player's revealed arrangement (null for an instant-win round).
  final List<Arrangement?> arrangements;

  /// Bonuses earned by each seat this round.
  final List<List<Bonus>> bonuses;

  /// Points awarded to each seat this round.
  final List<int> points;

  final int? sweepSeat;
  final int? instantWinSeat;

  /// The hand revealed by [instantWinSeat] or [shownSeat].
  final List<PlayingCard>? instantWinHand;

  /// Seat that ended the round by showing a special hand.
  final int? shownSeat;

  Map<String, dynamic> toJson() => {
    'round': round,
    'groupWinners': groupWinners,
    'arrangements': [for (final a in arrangements) a?.toJson()],
    'bonuses': [
      for (final b in bonuses) [for (final x in b) x.toJson()],
    ],
    'points': points,
    'sweepSeat': sweepSeat,
    'instantWinSeat': instantWinSeat,
    'instantWinHand': instantWinHand == null ? null : _codes(instantWinHand!),
    'shownSeat': shownSeat,
  };

  factory RoundResult.fromJson(Map<String, dynamic> json) => RoundResult(
    round: json['round'] as int,
    groupWinners: (json['groupWinners'] as List).cast<int>(),
    arrangements: [
      for (final a in json['arrangements'] as List)
        a == null ? null : Arrangement.fromJson(a),
    ],
    bonuses: [
      for (final b in json['bonuses'] as List)
        [
          for (final x in b as List)
            Bonus.fromJson((x as Map).cast<String, dynamic>()),
        ],
    ],
    points: (json['points'] as List).cast<int>(),
    sweepSeat: json['sweepSeat'] as int?,
    instantWinSeat: json['instantWinSeat'] as int?,
    instantWinHand: json['instantWinHand'] == null
        ? null
        : _cards(json['instantWinHand']),
    shownSeat: json['shownSeat'] as int?,
  );
}

class MatchResult {
  const MatchResult({
    required this.winnerSeat,
    required this.reason,
    required this.finalScores,
  });

  final int winnerSeat;
  final MatchEndReason reason;
  final List<int> finalScores;

  Map<String, dynamic> toJson() => {
    'winnerSeat': winnerSeat,
    'reason': reason.name,
    'finalScores': finalScores,
  };

  factory MatchResult.fromJson(Map<String, dynamic> json) => MatchResult(
    winnerSeat: json['winnerSeat'] as int,
    reason: MatchEndReason.values.byName(json['reason'] as String),
    finalScores: (json['finalScores'] as List).cast<int>(),
  );
}

/// The complete, authoritative state of a match. Immutable: the engine
/// returns a new instance for every accepted move.
///
/// This object contains every player's private cards. Only the authority
/// (the local device offline, the Bluetooth host, or the Cloud Function
/// online) holds it; clients receive a `PlayerView` instead.
class GameState {
  const GameState({
    required this.matchId,
    required this.rules,
    required this.seats,
    required this.scores,
    required this.round,
    required this.dealerSeat,
    required this.phase,
    required this.hands,
    required this.arrangements,
    required this.groupIndex,
    required this.turnSeat,
    required this.roundPlays,
    required this.groupWinners,
    required this.history,
    required this.version,
    this.result,
  });

  final String matchId;
  final RuleConfig rules;
  final List<SeatInfo> seats;
  final List<int> scores;

  /// 1-based round number.
  final int round;
  final int dealerSeat;
  final GamePhase phase;

  /// Each seat's dealt thirteen cards for the current round.
  final List<List<PlayingCard>> hands;

  /// Each seat's confirmed arrangement, null until confirmed.
  final List<Arrangement?> arrangements;

  /// Group currently being played (0..3).
  final int groupIndex;

  /// Seat that must act next while playing, otherwise null.
  final int? turnSeat;

  /// Groups revealed so far this round: `roundPlays[group][seat]`.
  final List<List<List<PlayingCard>?>> roundPlays;

  /// Winner of each completed group this round.
  final List<int> groupWinners;

  /// Results of every completed round, oldest first.
  final List<RoundResult> history;

  /// Incremented on every accepted move; used for idempotent sync.
  final int version;

  final MatchResult? result;

  RoundResult? get lastRound => history.isEmpty ? null : history.last;

  bool isReady(int seat) => arrangements[seat] != null;

  bool get allReady => arrangements.every((a) => a != null);

  /// Seat that leads the first group of the current round.
  int get firstLeader => (dealerSeat + 1) % kSeatCount;

  GameState copyWith({
    List<int>? scores,
    int? round,
    int? dealerSeat,
    GamePhase? phase,
    List<List<PlayingCard>>? hands,
    List<Arrangement?>? arrangements,
    int? groupIndex,
    int? Function()? turnSeat,
    List<List<List<PlayingCard>?>>? roundPlays,
    List<int>? groupWinners,
    List<RoundResult>? history,
    MatchResult? Function()? result,
  }) => GameState(
    matchId: matchId,
    rules: rules,
    seats: seats,
    scores: scores ?? this.scores,
    round: round ?? this.round,
    dealerSeat: dealerSeat ?? this.dealerSeat,
    phase: phase ?? this.phase,
    hands: hands ?? this.hands,
    arrangements: arrangements ?? this.arrangements,
    groupIndex: groupIndex ?? this.groupIndex,
    turnSeat: turnSeat != null ? turnSeat() : this.turnSeat,
    roundPlays: roundPlays ?? this.roundPlays,
    groupWinners: groupWinners ?? this.groupWinners,
    history: history ?? this.history,
    version: version + 1,
    result: result != null ? result() : this.result,
  );

  Map<String, dynamic> toJson() => {
    'schema': 1,
    'matchId': matchId,
    'rules': rules.toJson(),
    'seats': [for (final s in seats) s.toJson()],
    'scores': scores,
    'round': round,
    'dealerSeat': dealerSeat,
    'phase': phase.name,
    'hands': [for (final h in hands) _codes(h)],
    'arrangements': [for (final a in arrangements) a?.toJson()],
    'groupIndex': groupIndex,
    'turnSeat': turnSeat,
    'roundPlays': [
      for (final g in roundPlays)
        [for (final p in g) p == null ? null : _codes(p)],
    ],
    'groupWinners': groupWinners,
    'history': [for (final r in history) r.toJson()],
    'version': version,
    'result': result?.toJson(),
  };

  factory GameState.fromJson(Map<String, dynamic> json) {
    if (json['schema'] != 1) {
      throw const FormatException('Unsupported save format');
    }
    return GameState(
      matchId: json['matchId'] as String,
      rules: RuleConfig.fromJson(
        (json['rules'] as Map).cast<String, dynamic>(),
      ),
      seats: [
        for (final s in json['seats'] as List)
          SeatInfo.fromJson((s as Map).cast<String, dynamic>()),
      ],
      scores: (json['scores'] as List).cast<int>(),
      round: json['round'] as int,
      dealerSeat: json['dealerSeat'] as int,
      phase: GamePhase.values.byName(json['phase'] as String),
      hands: [for (final h in json['hands'] as List) _cards(h)],
      arrangements: [
        for (final a in json['arrangements'] as List)
          a == null ? null : Arrangement.fromJson(a),
      ],
      groupIndex: json['groupIndex'] as int,
      turnSeat: json['turnSeat'] as int?,
      roundPlays: [
        for (final g in json['roundPlays'] as List)
          [for (final p in g as List) p == null ? null : _cards(p)],
      ],
      groupWinners: (json['groupWinners'] as List).cast<int>(),
      history: [
        for (final r in json['history'] as List)
          RoundResult.fromJson((r as Map).cast<String, dynamic>()),
      ],
      version: json['version'] as int,
      result: json['result'] == null
          ? null
          : MatchResult.fromJson(
              (json['result'] as Map).cast<String, dynamic>(),
            ),
    );
  }
}
