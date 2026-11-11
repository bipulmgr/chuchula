import '../models/game_state.dart';

/// Cash points: a virtual balance that is staked on offline matches. They
/// have no money value and cannot be bought or cashed out.
class CashPoints {
  const CashPoints._();

  /// Balance of a new player.
  static const startingBalance = 100;

  /// Added for each rewarded ad watched to the end.
  static const adReward = 50;

  /// What 2nd, 3rd and last place pay the winner on the 100 board.
  static const payments = [20, 30, 50];

  /// Boards: what the winner collects in all. Payments scale with the
  /// board (the 200 board pays 40, 60 and 100).
  static const boards = [100, 200, 500, 1000, 2000, 10000];

  static const defaultBoard = 100;

  /// What 2nd, 3rd and last place pay on [board].
  static List<int> paymentsFor(int board) => [
    for (final p in payments) p * board ~/ defaultBoard,
  ];

  /// Cash points needed to sit at [board]: the largest loss there (last
  /// place), so a player who can start a match can always pay for it.
  /// Half the board: 50 for the 100 board, 100 for 200, and so on.
  static int entryFor(int board) => paymentsFor(board).last;

  /// Entry for the smallest board.
  static const minimumToPlay = 50;

  /// Short board name: 100, 200, 500, 1K, 2K, 10K.
  static String boardLabel(int board) =>
      board >= 1000 && board % 1000 == 0 ? '${board ~/ 1000}K' : '$board';

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

  /// Change to each seat's balance at the end of [result] on [board].
  /// The losers pay by place: on the 100 board 2nd pays 20, 3rd 30 and
  /// last 50, and the winner collects it all. Tied players split the
  /// payments of the places they span evenly, rounded down, so the winner
  /// gets exactly what is paid.
  static List<int> settle(MatchResult result, {int board = defaultBoard}) {
    final payments = paymentsFor(board);
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
