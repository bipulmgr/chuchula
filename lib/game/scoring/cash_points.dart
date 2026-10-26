import '../models/game_state.dart';

/// Cash points: a virtual balance that is staked on offline matches. They
/// have no money value and cannot be bought or cashed out.
class CashPoints {
  const CashPoints._();

  /// Balance of a new player.
  static const startingBalance = 100;

  /// Added for each rewarded ad watched to the end.
  static const adReward = 50;

  /// What 2nd, 3rd and last place pay the winner.
  static const payments = [20, 30, 50];

  /// The largest payment, so a player who can start a match can always
  /// pay for it.
  static const minimumToPlay = 50;

  /// Finishing places by seat: the winner is 1st, the others follow by
  /// final score. Tied players share a place (the best one they span).
  static List<int> places(MatchResult result) {
    final scores = result.finalScores;
    final others = [
      for (var s = 0; s < scores.length; s++)
        if (s != result.winnerSeat) s,
    ];
    final places = List.filled(scores.length, 1);
    for (final s in others) {
      places[s] = 2 + others.where((o) => scores[o] > scores[s]).length;
    }
    return places;
  }

  /// Change to each seat's balance at the end of [result]. The losers pay
  /// by place: 2nd pays 20, 3rd 30 and last 50, and the winner collects
  /// it all. Tied players split the payments of the places they span
  /// evenly, rounded down, so the winner gets exactly what is paid.
  static List<int> settle(MatchResult result) {
    final scores = result.finalScores;
    final p = places(result);
    final deltas = List.filled(scores.length, 0);
    var pot = 0;
    for (var s = 0; s < scores.length; s++) {
      if (s == result.winnerSeat) continue;
      final tied = [
        for (var o = 0; o < scores.length; o++)
          if (o != result.winnerSeat && p[o] == p[s]) o,
      ];
      final spanned = payments.sublist(p[s] - 2, p[s] - 2 + tied.length);
      final pay = spanned.reduce((a, b) => a + b) ~/ tied.length;
      deltas[s] = -pay;
      pot += pay;
    }
    deltas[result.winnerSeat] = pot;
    return deltas;
  }
}
