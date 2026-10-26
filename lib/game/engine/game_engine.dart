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
        if (s.rules.allRanksInstantWin)
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
      if (instant.length == 1) {
        final seat = instant.single;
        final rr = RoundResult(
          round: round,
          groupWinners: const [],
          arrangements: List.filled(kSeatCount, null),
          bonuses: [
            for (var i = 0; i < kSeatCount; i++)
              i == seat
                  ? const [Bonus(BonusType.allRanks, 0)]
                  : const <Bonus>[],
          ],
          points: List.filled(kSeatCount, 0),
          instantWinSeat: seat,
          instantWinHand: hands[seat],
        );
        return dealt.copyWith(
          phase: GamePhase.matchOver,
          history: [...s.history, rr],
          result: () => MatchResult(
            winnerSeat: seat,
            reason: MatchEndReason.instantWin,
            finalScores: s.scores,
          ),
        );
      }
      return dealt;
    }
    throw StateError('Could not produce a valid deal');
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
    // One group of 4 and three of 3, in any position.
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
        // Groups are always played strongest first, whatever order the
        // player left them in.
        arrangements[seat] = state.rules.strongestFirst
            ? Arrangement(HandEvaluator.strongestFirst(arrangement.groups))
            : arrangement;
        var next = state.copyWith(arrangements: arrangements);
        if (next.allReady) {
          next = next.copyWith(
            phase: GamePhase.playing,
            groupIndex: 0,
            turnSeat: () => next.firstLeader,
            roundPlays: [List.filled(kSeatCount, null)],
          );
        }
        return next;

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
        final winner = resolveGroup(plays[g]);
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

      case StartNextRound():
        return _dealRound(
          state,
          nextDealer: (state.dealerSeat + 1) % kSeatCount,
        );
    }
  }

  /// Index of the seat whose group is strongest.
  static int resolveGroup(List<List<PlayingCard>?> plays) {
    final values = [for (final p in plays) HandEvaluator.evaluate(p!)];
    return HandEvaluator.bestIndex(values);
  }

  /// Computes the round result for a state whose four groups are complete.
  RoundResult resolveRound(GameState state) {
    if (state.groupWinners.length != kGroupCount) {
      throw StateError('Round is not complete');
    }
    final bonuses = [
      for (var i = 0; i < kSeatCount; i++)
        BonusDetector.detect(
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

  GameState _finishRound(GameState state) {
    final rr = resolveRound(state);
    final scores = [
      for (var i = 0; i < kSeatCount; i++) state.scores[i] + rr.points[i],
    ];
    var next = state.copyWith(
      scores: scores,
      phase: GamePhase.roundOver,
      history: [...state.history, rr],
    );
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
