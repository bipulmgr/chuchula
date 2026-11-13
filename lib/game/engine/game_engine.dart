import '../models/card.dart';
import '../models/game_state.dart';
import '../models/moves.dart';
import '../rules/bonuses.dart';
import '../rules/hand_evaluator.dart';
import '../rules/rule_config.dart';
import '../scoring/round_scorer.dart';
import 'random_source.dart';

class GameSetup {
  const GameSetup({
    required this.matchId,
    required this.seats,
    this.rules = RuleConfig.standard,
    this.firstDealer = 3,
  });

  final String matchId;
  final List<SeatInfo> seats;
  final RuleConfig rules;

  /// Dealer for round 1. With the default (seat 3) seat 0 leads first.
  final int firstDealer;
}

/// The Chuchula rules engine. Pure Dart, deterministic for a given
/// [RandomSource], and shared by offline, Bluetooth and online play.
///
/// Phase flow per round:
/// `arranging` → (all four ready) → `playing` group 1..4 → `roundOver`
/// (or `arranging` → a special hand shown → `showing` → `roundOver`)
/// → (`StartNextRound`) → `arranging` … until `matchOver`.
class ChuchulaGameEngine {
  ChuchulaGameEngine({RandomSource? random})
    : random = random ?? SecureRandomSource();

  final RandomSource random;

  static const int _maxRedeals = 20;

  GameState startGame(GameSetup setup) {
    if (setup.seats.length != kSeatCount) {
      throw ArgumentError('Chuchula needs exactly $kSeatCount seats');
    }
    final empty = GameState(
      matchId: setup.matchId,
      rules: setup.rules,
      seats: List.unmodifiable(setup.seats),
      scores: List.filled(kSeatCount, 0),
      round: 0,
      dealerSeat: setup.firstDealer % kSeatCount,
      phase: GamePhase.roundOver,
      hands: List.filled(kSeatCount, const []),
      arrangements: List.filled(kSeatCount, null),
      groupIndex: 0,
      turnSeat: null,
      roundPlays: const [],
      groupWinners: const [],
      history: const [],
      version: 0,
    );
    return _dealRound(empty, nextDealer: empty.dealerSeat);
  }

  /// Shuffles a full deck with [random] (or a fixed deck order when
  /// [random] is a [FixedDeckRandomSource]).
  List<PlayingCard> shuffleAndDeal([RandomSource? source]) {
    final r = source ?? random;
    if (r is FixedDeckRandomSource) {
      final order = r.takeDeck();
      if (order != null) {
        if (order.length != 52 || order.toSet().length != 52) {
          throw ArgumentError('A fixed deck must contain all 52 card ids');
        }
        return [for (final id in order) PlayingCard.fromId(id)];
      }
    }
    return r.shuffled(fullDeck());
  }

  /// Splits a 52-card deck into four hands, dealing one card at a time
  /// starting with the seat after the dealer.
  static List<List<PlayingCard>> dealHands(
    List<PlayingCard> deck,
    int dealerSeat,
  ) {
    final hands = List.generate(kSeatCount, (_) => <PlayingCard>[]);
    for (var i = 0; i < deck.length; i++) {
      hands[(dealerSeat + 1 + i) % kSeatCount].add(deck[i]);
    }
    for (final h in hands) {
      h.sort();
    }
    return [for (final h in hands) List.unmodifiable(h)];
  }

  GameState _dealRound(GameState s, {required int nextDealer}) {
    for (var attempt = 0; attempt < _maxRedeals; attempt++) {
      final hands = dealHands(shuffleAndDeal(), nextDealer);
      final round = s.round + 1;
      final instant = <int>[
        if (s.rules.allRanksInstantWin && !s.rules.declareBonuses)
          for (var i = 0; i < kSeatCount; i++)
            if (BonusDetector.hasAllRanks(hands[i])) i,
      ];
      if (instant.length > 1) continue; // Void deal: redeal.

      final dealt = s.copyWith(
        round: round,
        dealerSeat: nextDealer,
        phase: GamePhase.arranging,
        hands: hands,
        arrangements: List.filled(kSeatCount, null),
        groupIndex: 0,
        turnSeat: () => null,
        roundPlays: const [],
        groupWinners: const [],
      );
      if (instant.length == 1) return _instantWin(dealt, instant.single);
      return dealt;
    }
    throw StateError('Could not produce a valid deal');
  }

  /// Ends the match: [seat] holds one card of every rank.
  GameState _instantWin(GameState s, int seat) {
    final rr = RoundResult(
      round: s.round,
      groupWinners: const [],
      arrangements: List.filled(kSeatCount, null),
      bonuses: [
        for (var i = 0; i < kSeatCount; i++)
          i == seat ? const [Bonus(BonusType.allRanks, 0)] : const <Bonus>[],
      ],
      points: List.filled(kSeatCount, 0),
      instantWinSeat: seat,
      instantWinHand: s.hands[seat],
    );
    return s.copyWith(
      phase: GamePhase.matchOver,
      turnSeat: () => null,
      history: [...s.history, rr],
      shows: const [null, null, null, null],
      showOpener: () => null,
      result: () => MatchResult(
        winnerSeat: seat,
        reason: MatchEndReason.instantWin,
        finalScores: s.scores,
      ),
    );
  }

  /// [seat] shows the special [kind]. During arranging this opens the
  /// show window for the other players; in the window it is [seat]'s
  /// answer. All thirteen ranks wins the match at once: nothing beats it.
  GameState _show(GameState s, int seat, BonusType kind) {
    final shows = List<String?>.of(s.shows);
    shows[seat] = kind.name;
    if (s.phase == GamePhase.arranging &&
        s.rules.showWaitsForAll &&
        s.rules.showWindowSeconds > 0) {
      // The others carry on arranging. Nothing is revealed until every
      // seat has either shown or tapped Ready.
      return _afterArranging(
        s.copyWith(shows: shows, showOpener: () => s.showOpener ?? seat),
      );
    }
    if (kind == BonusType.allRanks) return _instantWin(s, seat);
    if (s.phase == GamePhase.arranging) {
      final opened = s.copyWith(
        phase: GamePhase.showing,
        turnSeat: () => null,
        shows: shows,
        showOpener: () => seat,
      );
      // Without a window the round ends at the first show.
      if (s.rules.showWindowSeconds <= 0) return _resolveShows(opened);
      return opened;
    }
    return _afterAnswer(s.copyWith(shows: shows));
  }

  /// Whether [seat] is done with arranging: it tapped Ready or showed.
  static bool answered(GameState s, int seat) =>
      s.isReady(seat) || (s.shows[seat] != null && s.shows[seat] != kShowPass);

  /// Once every seat has tapped Ready or shown: the specials shown (if
  /// any) are revealed and decide the round, otherwise play starts.
  GameState _afterArranging(GameState s) {
    for (var i = 0; i < kSeatCount; i++) {
      if (!answered(s, i)) return s;
    }
    if (s.shows.every((x) => x == null || x == kShowPass)) {
      return s.copyWith(
        phase: GamePhase.playing,
        groupIndex: 0,
        turnSeat: () => s.firstLeader,
        roundPlays: [List.filled(kSeatCount, null)],
      );
    }
    return _resolveShows(s);
  }

  GameState _afterAnswer(GameState s) =>
      s.shows.every((x) => x != null) ? _resolveShows(s) : s;

  /// Ends the show window: the best special shown wins the round and only
  /// its owner scores. Ties (same kind and ranks) go to whoever showed
  /// first, counting round the table from the opener.
  GameState _resolveShows(GameState s) {
    final opener = s.showOpener ?? 0;
    final kinds = [
      for (final x in s.shows)
        x == null || x == kShowPass ? null : BonusType.values.byName(x),
    ];
    int? winner;
    List<int>? best;
    for (var k = 0; k < kSeatCount; k++) {
      final seat = (opener + k) % kSeatCount;
      final kind = kinds[seat];
      if (kind == null) continue;
      final rank = BonusDetector.showRank(s.hands[seat], kind);
      if (best == null || BonusDetector.compareShowRanks(rank, best) > 0) {
        best = rank;
        winner = seat;
      }
    }
    final w = winner!;
    // All thirteen ranks wins the match outright.
    if (kinds[w] == BonusType.allRanks) return _instantWin(s, w);
    final bonuses = [
      for (final b in BonusDetector.detect(s.hands[w], s.rules))
        if (b.type == kinds[w]) b,
    ];
    final total = bonuses.fold<int>(0, (t, b) => t + b.points);
    final points = [
      for (var i = 0; i < kSeatCount; i++)
        i == w ? RoundScorer.applyTarget(s.scores[i], total, s.rules) : 0,
    ];
    final rr = RoundResult(
      round: s.round,
      groupWinners: const [],
      arrangements: List.filled(kSeatCount, null),
      bonuses: [
        for (var i = 0; i < kSeatCount; i++) i == w ? bonuses : const <Bonus>[],
      ],
      points: points,
      instantWinHand: s.hands[w],
      shownSeat: w,
      shownKinds: kinds,
      shownHands: [
        for (var i = 0; i < kSeatCount; i++)
          kinds[i] == null ? null : s.hands[i],
      ],
    );
    var next = s.copyWith(
      scores: [for (var i = 0; i < kSeatCount; i++) s.scores[i] + points[i]],
      phase: GamePhase.roundOver,
      turnSeat: () => null,
      history: [...s.history, rr],
      shows: const [null, null, null, null],
      showOpener: () => null,
    );
    final match = checkMatchResult(next);
    if (match != null) {
      next = next.copyWith(phase: GamePhase.matchOver, result: () => match);
    }
    return next;
  }

  /// Special hands [seat] could show now: during arranging, or while
  /// another player's show is open and [seat] has not answered. Empty if
  /// none, or if bonuses are scored automatically.
  static List<Bonus> showable(GameState s, int seat) =>
      s.rules.declareBonuses &&
          ((s.phase == GamePhase.arranging && !answered(s, seat)) ||
              (s.phase == GamePhase.showing && s.shows[seat] == null))
      ? BonusDetector.detect(s.hands[seat], s.rules)
      : const [];

  /// The best special to show from [bonuses]: all ranks wins the match,
  /// otherwise the kind worth most. Null when there is none.
  static BonusType? bestShow(List<Bonus> bonuses) {
    if (bonuses.isEmpty) return null;
    if (bonuses.any((b) => b.type == BonusType.allRanks)) {
      return BonusType.allRanks;
    }
    final totals = <BonusType, int>{};
    for (final b in bonuses) {
      totals[b.type] = (totals[b.type] ?? 0) + b.points;
    }
    return totals.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  // ---------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------

  ValidationResult validateArrangement(
    GameState state,
    int seat,
    Arrangement arrangement,
  ) {
    if (seat < 0 || seat >= kSeatCount) {
      return const ValidationResult.fail(RuleError.invalidSeat);
    }
    final groups = arrangement.groups;
    if (groups.length != kGroupCount) {
      return ValidationResult.fail(
        RuleError.wrongGroupCount,
        '${groups.length}',
      );
    }
    // One group of 4 and three of 3, in any submitted position.
    final sizes = [for (final g in groups) g.length]..sort();
    if (sizes.join(',') != kGroupSizes.join(',')) {
      return ValidationResult.fail(RuleError.wrongGroupSize, sizes.join('-'));
    }
    final all = arrangement.allCards;
    if (all.toSet().length != all.length) {
      return const ValidationResult.fail(RuleError.duplicateCard);
    }
    final hand = state.hands[seat].toSet();
    for (final c in all) {
      if (!hand.contains(c)) {
        return ValidationResult.fail(RuleError.cardNotOwned, c.code);
      }
    }
    if (all.length != hand.length) {
      return const ValidationResult.fail(RuleError.missingCards);
    }
    // The 4-card group is played last and must be the weakest, unless no
    // arrangement of this hand allows that.
    if (state.rules.fourCardWeakest &&
        !HandEvaluator.fourCardIsWeakest(groups) &&
        HandEvaluator.fourCardWeakestArrangement(state.hands[seat]) != null) {
      return const ValidationResult.fail(RuleError.fourCardTooStrong);
    }
    return const ValidationResult.ok();
  }

  ValidationResult validateMove(GameState state, GameMove move) {
    if (state.phase == GamePhase.matchOver) {
      return const ValidationResult.fail(RuleError.matchOver);
    }
    if (move.seat < 0 || move.seat >= kSeatCount) {
      return const ValidationResult.fail(RuleError.invalidSeat);
    }
    switch (move) {
      case SubmitArrangement(:final seat, :final arrangement):
        if (state.phase != GamePhase.arranging) {
          return const ValidationResult.fail(RuleError.wrongPhase);
        }
        if (state.isReady(seat)) {
          return const ValidationResult.fail(RuleError.alreadyReady);
        }
        if (state.shows[seat] != null) {
          return const ValidationResult.fail(RuleError.alreadyAnswered);
        }
        return validateArrangement(state, seat, arrangement);
      case PlayGroup(:final seat, :final group):
        if (state.phase != GamePhase.playing) {
          return const ValidationResult.fail(RuleError.wrongPhase);
        }
        if (group != state.groupIndex) {
          return ValidationResult.fail(RuleError.wrongGroup, '$group');
        }
        if (state.turnSeat != seat) {
          return const ValidationResult.fail(RuleError.notYourTurn);
        }
        return const ValidationResult.ok();
      case StartNextRound():
        if (state.phase != GamePhase.roundOver) {
          return const ValidationResult.fail(RuleError.wrongPhase);
        }
        return const ValidationResult.ok();
      case ShowHand(:final seat, :final bonus):
        if (state.phase != GamePhase.arranging &&
            state.phase != GamePhase.showing) {
          return const ValidationResult.fail(RuleError.wrongPhase);
        }
        if (state.shows[seat] != null) {
          return const ValidationResult.fail(RuleError.alreadyAnswered);
        }
        if (state.phase == GamePhase.arranging && state.isReady(seat)) {
          return const ValidationResult.fail(RuleError.alreadyReady);
        }
        if (!showable(
          state,
          seat,
        ).any((b) => bonus == null || b.type == bonus)) {
          return const ValidationResult.fail(RuleError.nothingToShow);
        }
        return const ValidationResult.ok();
      case PassShow(:final seat):
        if (state.phase != GamePhase.showing) {
          return const ValidationResult.fail(RuleError.wrongPhase);
        }
        if (state.shows[seat] != null) {
          return const ValidationResult.fail(RuleError.alreadyAnswered);
        }
        return const ValidationResult.ok();
      case CloseShow():
        if (state.phase != GamePhase.showing) {
          return const ValidationResult.fail(RuleError.wrongPhase);
        }
        return const ValidationResult.ok();
    }
  }

  // ---------------------------------------------------------------------
  // Transitions
  // ---------------------------------------------------------------------

  /// Applies a validated move. Throws [InvalidMoveException] otherwise.
  GameState applyMove(GameState state, GameMove move) {
    final check = validateMove(state, move);
    if (!check.isValid) throw InvalidMoveException(check);

    switch (move) {
      case SubmitArrangement(:final seat, :final arrangement):
        final arrangements = List<Arrangement?>.of(state.arrangements);
        // Groups are always played in order (3-card groups strongest
        // first, the 4-card group last), whatever order the player left
        // them in.
        arrangements[seat] = state.rules.strongestFirst
            ? Arrangement(HandEvaluator.playOrder(arrangement.groups))
            : arrangement;
        return _afterArranging(state.copyWith(arrangements: arrangements));

      case PlayGroup(:final seat):
        final g = state.groupIndex;
        final plays = [
          for (final p in state.roundPlays) List<List<PlayingCard>?>.of(p),
        ];
        plays[g][seat] = state.arrangements[seat]!.groups[g];
        final played = plays[g].where((p) => p != null).length;
        if (played < kSeatCount) {
          return state.copyWith(
            roundPlays: plays,
            turnSeat: () => (seat + 1) % kSeatCount,
          );
        }
        // The seat completing the group plays last, so the leader is the
        // seat after it.
        final winner = resolveGroup(plays[g], leader: (seat + 1) % kSeatCount);
        final winners = [...state.groupWinners, winner];
        if (g + 1 < kGroupCount) {
          plays.add(List.filled(kSeatCount, null));
          return state.copyWith(
            roundPlays: plays,
            groupWinners: winners,
            groupIndex: g + 1,
            turnSeat: () => winner,
          );
        }
        return _finishRound(
          state.copyWith(
            roundPlays: plays,
            groupWinners: winners,
            turnSeat: () => null,
          ),
        );

      case ShowHand(:final seat, :final bonus):
        return _show(state, seat, bonus ?? bestShow(showable(state, seat))!);

      case PassShow(:final seat):
        final shows = List<String?>.of(state.shows);
        shows[seat] = kShowPass;
        return _afterAnswer(state.copyWith(shows: shows));

      case CloseShow():
        return _resolveShows(state);

      case StartNextRound():
        return _dealRound(
          state,
          nextDealer: (state.dealerSeat + 1) % kSeatCount,
        );
    }
  }

  /// Seat whose group wins, with play starting at [leader]. Groups equal
  /// by rank go to whoever of them played last.
  static int resolveGroup(List<List<PlayingCard>?> plays, {int leader = 0}) {
    final values = [for (final p in plays) HandEvaluator.evaluate(p!)];
    return HandEvaluator.groupWinner(values, leader);
  }

  /// Computes the round result for a state whose four groups are complete.
  RoundResult resolveRound(GameState state) {
    if (state.groupWinners.length != kGroupCount) {
      throw StateError('Round is not complete');
    }
    // With declared bonuses, only a shown hand scores them.
    final bonuses = [
      for (var i = 0; i < kSeatCount; i++)
        state.rules.declareBonuses
            ? const <Bonus>[]
            : BonusDetector.detect(
                state.hands[i],
                state.rules,
              ).where((b) => b.type != BonusType.allRanks).toList(),
    ];
    final seatScores = [
      for (var i = 0; i < kSeatCount; i++)
        RoundScorer.scoreSeat(
          seat: i,
          groupWinners: state.groupWinners,
          bonuses: bonuses[i],
          rules: state.rules,
        ),
    ];
    final points = [
      for (var i = 0; i < kSeatCount; i++)
        RoundScorer.applyTarget(
          state.scores[i],
          seatScores[i].total,
          state.rules,
        ),
    ];
    final sweep = seatScores.indexWhere((s) => s.swept);
    return RoundResult(
      round: state.round,
      groupWinners: state.groupWinners,
      arrangements: state.arrangements,
      bonuses: bonuses,
      points: points,
      sweepSeat: sweep < 0 ? null : sweep,
    );
  }

  /// Seat whose last group is a double run (the strongest, if several),
  /// which wins the match; null if none.
  static int? lastGroupDoubleRun(GameState state) {
    if (!state.rules.lastGroupDoubleRunWins) return null;
    if (state.roundPlays.length != kGroupCount) return null;
    final plays = state.roundPlays.last;
    if (plays.any((p) => p == null)) return null;
    // Equal double runs go to whoever played last, as in group play.
    final leader = state.groupWinners.length >= kGroupCount - 1
        ? state.groupWinners[kGroupCount - 2]
        : 0;
    int? seat;
    HandValue? best;
    for (var k = 0; k < kSeatCount; k++) {
      final i = (leader + k) % kSeatCount;
      final v = HandEvaluator.evaluate(plays[i]!);
      if (v.category != HandCategory.pureSequence) continue;
      if (best == null || v.rankStrength >= best.rankStrength) {
        best = v;
        seat = i;
      }
    }
    return seat;
  }

  GameState _finishRound(GameState state) {
    var rr = resolveRound(state);
    final doubleRun = lastGroupDoubleRun(state);
    if (doubleRun != null) {
      rr = RoundResult(
        round: rr.round,
        groupWinners: rr.groupWinners,
        arrangements: rr.arrangements,
        bonuses: rr.bonuses,
        points: rr.points,
        sweepSeat: rr.sweepSeat,
        doubleRunSeat: doubleRun,
      );
    }
    final scores = [
      for (var i = 0; i < kSeatCount; i++) state.scores[i] + rr.points[i],
    ];
    var next = state.copyWith(
      scores: scores,
      phase: GamePhase.roundOver,
      history: [...state.history, rr],
    );
    if (doubleRun != null) {
      // A double run in the last group wins the whole match.
      return next.copyWith(
        phase: GamePhase.matchOver,
        result: () => MatchResult(
          winnerSeat: doubleRun,
          reason: MatchEndReason.doubleRun,
          finalScores: scores,
        ),
      );
    }
    final match = checkMatchResult(next);
    if (match != null) {
      next = next.copyWith(phase: GamePhase.matchOver, result: () => match);
    }
    return next;
  }

  /// Returns the match result if the match is over, otherwise null.
  MatchResult? checkMatchResult(GameState state) {
    if (state.result != null) return state.result;
    final winner = RoundScorer.matchWinner(state.scores, state.rules);
    if (winner != null) {
      return MatchResult(
        winnerSeat: winner,
        reason: MatchEndReason.targetReached,
        finalScores: state.scores,
      );
    }
    if (state.round >= state.rules.maxRounds) {
      var best = 0;
      for (var i = 1; i < kSeatCount; i++) {
        if (state.scores[i] > state.scores[best]) best = i;
      }
      return MatchResult(
        winnerSeat: best,
        reason: MatchEndReason.maxRounds,
        finalScores: state.scores,
      );
    }
    return null;
  }
}
