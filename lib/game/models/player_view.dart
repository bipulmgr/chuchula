import 'card.dart';
import 'game_state.dart';

/// What one seat is allowed to know about the match. This is the only
/// state sent to remote clients and the only state the table UI and bots
/// consume, so hidden cards cannot leak through either.
class PlayerView {
  const PlayerView({
    required this.mySeat,
    required this.matchId,
    required this.seats,
    required this.scores,
    required this.targetScore,
    required this.round,
    required this.dealerSeat,
    required this.phase,
    required this.myHand,
    required this.myArrangement,
    required this.ready,
    required this.groupIndex,
    required this.turnSeat,
    required this.roundPlays,
    required this.groupWinners,
    required this.lastRound,
    required this.result,
    required this.version,
  });

  factory PlayerView.of(GameState s, int seat) => PlayerView(
        mySeat: seat,
        matchId: s.matchId,
        seats: s.seats,
        scores: s.scores,
        targetScore: s.rules.targetScore,
        round: s.round,
        dealerSeat: s.dealerSeat,
        phase: s.phase,
        myHand: s.hands[seat],
        myArrangement: s.arrangements[seat],
        ready: [for (var i = 0; i < kSeatCount; i++) s.isReady(i)],
        groupIndex: s.groupIndex,
        turnSeat: s.turnSeat,
        roundPlays: s.roundPlays,
        groupWinners: s.groupWinners,
        lastRound: s.lastRound,
        result: s.result,
        version: s.version,
      );

  final int mySeat;
  final String matchId;
  final List<SeatInfo> seats;
  final List<int> scores;
  final int targetScore;
  final int round;
  final int dealerSeat;
  final GamePhase phase;
  final List<PlayingCard> myHand;
  final Arrangement? myArrangement;
  final List<bool> ready;
  final int groupIndex;
  final int? turnSeat;
  final List<List<List<PlayingCard>?>> roundPlays;
  final List<int> groupWinners;
  final RoundResult? lastRound;
  final MatchResult? result;
  final int version;

  bool get isMyTurn => phase == GamePhase.playing && turnSeat == mySeat;

  /// Every card this seat has legitimately seen this round: its own hand
  /// plus every revealed group.
  Set<PlayingCard> get knownCards => {
        ...myHand,
        for (final g in roundPlays)
          for (final p in g)
            if (p != null) ...p,
      };

  Map<String, dynamic> toJson() => {
        'mySeat': mySeat,
        'matchId': matchId,
        'seats': [for (final s in seats) s.toJson()],
        'scores': scores,
        'targetScore': targetScore,
        'round': round,
        'dealerSeat': dealerSeat,
        'phase': phase.name,
        'myHand': [for (final c in myHand) c.code],
        'myArrangement': myArrangement?.toJson(),
        'ready': ready,
        'groupIndex': groupIndex,
        'turnSeat': turnSeat,
        'roundPlays': [
          for (final g in roundPlays)
            [
              for (final p in g) p == null ? null : [for (final c in p) c.code]
            ]
        ],
        'groupWinners': groupWinners,
        'lastRound': lastRound?.toJson(),
        'result': result?.toJson(),
        'version': version,
      };

  factory PlayerView.fromJson(Map<String, dynamic> json) {
    List<PlayingCard> cards(Object? l) =>
        [for (final c in l as List) PlayingCard.parse(c as String)];
    return PlayerView(
      mySeat: json['mySeat'] as int,
      matchId: json['matchId'] as String,
      seats: [
        for (final s in json['seats'] as List)
          SeatInfo.fromJson((s as Map).cast<String, dynamic>())
      ],
      scores: (json['scores'] as List).cast<int>(),
      targetScore: json['targetScore'] as int,
      round: json['round'] as int,
      dealerSeat: json['dealerSeat'] as int,
      phase: GamePhase.values.byName(json['phase'] as String),
      myHand: cards(json['myHand']),
      myArrangement: json['myArrangement'] == null
          ? null
          : Arrangement.fromJson(json['myArrangement']),
      ready: (json['ready'] as List).cast<bool>(),
      groupIndex: json['groupIndex'] as int,
      turnSeat: json['turnSeat'] as int?,
      roundPlays: [
        for (final g in json['roundPlays'] as List)
          [for (final p in g as List) p == null ? null : cards(p)]
      ],
      groupWinners: (json['groupWinners'] as List).cast<int>(),
      lastRound: json['lastRound'] == null
          ? null
          : RoundResult.fromJson(
              (json['lastRound'] as Map).cast<String, dynamic>()),
      result: json['result'] == null
          ? null
          : MatchResult.fromJson((json['result'] as Map).cast<String, dynamic>()),
      version: json['version'] as int,
    );
  }
}
