import 'dart:convert';

import 'package:chuchula/game/engine/game_engine.dart';
import 'package:chuchula/game/engine/random_source.dart';
import 'package:chuchula/game/models/card.dart';
import 'package:chuchula/game/models/game_state.dart';
import 'package:chuchula/game/models/moves.dart';
import 'package:chuchula/game/models/player_view.dart';
import 'package:chuchula/game/rules/bonuses.dart';
import 'package:chuchula/game/rules/rule_config.dart';
import 'package:chuchula/game/scoring/round_scorer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

// Seat 0 holds unbeatable groups in every position (trails of A, K, Q and
// four jacks), so with [strong0] it wins all four groups.
const strongHand = 'AS AH AD KS KH KD QS QH QD JS JH JD JC';
const strong0 = 'AS AH AD KS KH KD QS QH QD JS JH JD JC';

// Isolates group/sweep points from the hand bonuses that hand also earns.
const noBonus = RuleConfig(
  fourCardWeakest: false,
  threeTrailsPoints: 0,
  fourOfAKindPoints: 0,
);

void main() {
  group('dealing', () {
    test('every seat gets 13 unique cards covering the whole deck', () {
      for (var seed = 0; seed < 50; seed++) {
        final e = ChuchulaGameEngine(random: SeededRandomSource(seed));
        final s = start(e);
        if (s.phase == GamePhase.matchOver) continue; // instant win
        expect(s.hands.every((h) => h.length == 13), isTrue);
        final all = {for (final h in s.hands) ...h};
        expect(all.length, 52);
      }
    });

    test('same seed gives the same deal (deterministic)', () {
      final a = start(ChuchulaGameEngine(random: SeededRandomSource(42)));
      final b = start(ChuchulaGameEngine(random: SeededRandomSource(42)));
      expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
    });

    test('deal starts left of the dealer, one card at a time', () {
      final deck = fullDeck();
      final hands = ChuchulaGameEngine.dealHands(deck, 3);
      expect(hands[0].contains(deck[0]), isTrue);
      expect(hands[1].contains(deck[1]), isTrue);
      expect(hands[3].contains(deck[3]), isTrue);
    });

    test('fixed deck helper deals the requested hands', () {
      final e = fixedEngine([
        deckFor([strongHand]),
      ]);
      final s = start(e);
      expect(s.hands[0].toSet(), parseCards(strongHand).toSet());
    });

    test('rejects a malformed fixed deck', () {
      final e = fixedEngine([
        [1, 2, 3],
      ]);
      expect(() => start(e), throwsArgumentError);
    });
  });

  group('arrangement validation', () {
    late ChuchulaGameEngine e;
    late GameState s;
    setUp(() {
      e = fixedEngine([
        deckFor([strongHand]),
      ]);
      s = start(e);
    });

    test('accepts a 3-3-3-4 split of the own hand', () {
      final a = Arrangement.fromOrderedCards(s.hands[0]);
      expect(e.validateArrangement(s, 0, a).isValid, isTrue);
    });

    test('rejects wrong group sizes', () {
      final h = s.hands[0];
      final a = Arrangement([
        h.sublist(0, 4),
        h.sublist(4, 8),
        h.sublist(8, 11),
        h.sublist(11),
      ]);
      expect(e.validateArrangement(s, 0, a).error, RuleError.wrongGroupSize);
    });

    test('rejects wrong group count', () {
      final h = s.hands[0];
      final a = Arrangement([h.sublist(0, 3), h.sublist(3)]);
      expect(e.validateArrangement(s, 0, a).error, RuleError.wrongGroupCount);
    });

    test('rejects duplicated cards', () {
      final h = s.hands[0];
      final dup = [...h.sublist(0, 12), h[0]];
      final a = Arrangement.fromOrderedCards(dup);
      expect(e.validateArrangement(s, 0, a).error, RuleError.duplicateCard);
    });

    test('rejects cards the seat does not own', () {
      final a = Arrangement.fromOrderedCards(s.hands[1]);
      expect(e.validateArrangement(s, 0, a).error, RuleError.cardNotOwned);
    });

    test('the 4-card group plays last; 3-card groups strongest first', () {
      final e2 = fixedEngine([
        deckFor([strongHand]),
      ]);
      final s2 = start(e2);
      // Weakest first, with the 4-card group in front.
      final weakFirst = Arrangement([
        parseCards('JS JH JD JC'),
        parseCards('QS QH QD'),
        parseCards('KS KH KD'),
        parseCards('AS AH AD'),
      ]);
      expect(e2.validateArrangement(s2, 0, weakFirst).isValid, isTrue);
      final next = e2.applyMove(s2, SubmitArrangement(0, weakFirst));
      expect(next.arrangements[0]!.groups.map((g) => g.length), [3, 3, 3, 4]);
      expect(next.arrangements[0]!.groups.map((g) => g.first.code), [
        'AS',
        'KS',
        'QS',
        'JS',
      ]);

      // With the switch off, groups keep the submitted order.
      final e3 = fixedEngine([
        deckFor([strongHand]),
      ]);
      final s3 = start(
        e3,
        rules: const RuleConfig(strongestFirst: false, fourCardWeakest: false),
      );
      final kept = e3.applyMove(s3, SubmitArrangement(0, weakFirst));
      expect(kept.arrangements[0]!.groups.first.length, 4);
      expect(kept.arrangements[0]!.groups[1].first.code, 'QS');
    });

    test('refuses a 4-card group stronger than a 3-card group', () {
      const hand = '5D 5H 6H 7H 2D 3D AH 2S 6S 8S 10C KH AC';
      final e2 = fixedEngine([
        deckFor([hand]),
      ]);
      final s2 = start(e2, rules: RuleConfig.standard);
      // Bipul's Suggest result: the double run padded to four cards.
      final padded = Arrangement([
        parseCards('5D 5H 6H 7H'),
        parseCards('2D 3D AH'),
        parseCards('2S 6S 8S'),
        parseCards('10C KH AC'),
      ]);
      expect(
        e2.validateArrangement(s2, 0, padded).error,
        RuleError.fourCardTooStrong,
      );
      final fixed = Arrangement([
        parseCards('5H 6H 7H'),
        parseCards('2D 3D AC'),
        parseCards('2S 6S 8S'),
        parseCards('5D 10C KH AH'),
      ]);
      expect(e2.validateArrangement(s2, 0, fixed).isValid, isTrue);
      // The switch turns the check off.
      final s3 = start(
        fixedEngine([
          deckFor([hand]),
        ]),
      );
      expect(e2.validateArrangement(s3, 0, padded).isValid, isTrue);
    });
  });

  group('phases and turns', () {
    test('cannot play before everyone is ready', () {
      final e = fixedEngine([
        deckFor([strongHand]),
      ]);
      var s = start(e);
      expect(
        e.validateMove(s, const PlayGroup(0, 0)).error,
        RuleError.wrongPhase,
      );
      s = e.applyMove(
        s,
        SubmitArrangement(0, Arrangement.fromOrderedCards(s.hands[0])),
      );
      expect(s.phase, GamePhase.arranging);
      expect(s.isReady(0), isTrue);
      expect(
        e
            .validateMove(
              s,
              SubmitArrangement(0, Arrangement.fromOrderedCards(s.hands[0])),
            )
            .error,
        RuleError.alreadyReady,
      );
    });

    test('transitions to playing when all four are ready; seat after '
        'dealer leads', () {
      final e = fixedEngine([
        deckFor([strongHand]),
      ]);
      final s = arrangeAll(e, start(e));
      expect(s.phase, GamePhase.playing);
      expect(s.groupIndex, 0);
      expect(s.turnSeat, 0);
    });

    test('wrong player and wrong group are rejected', () {
      final e = fixedEngine([
        deckFor([strongHand]),
      ]);
      final s = arrangeAll(e, start(e));
      expect(
        e.validateMove(s, const PlayGroup(2, 0)).error,
        RuleError.notYourTurn,
      );
      expect(
        e.validateMove(s, const PlayGroup(0, 1)).error,
        RuleError.wrongGroup,
      );
      expect(
        () => e.applyMove(s, const PlayGroup(2, 0)),
        throwsA(isA<InvalidMoveException>()),
      );
      expect(
        e.validateMove(s, const PlayGroup(9, 0)).error,
        RuleError.invalidSeat,
      );
    });

    test('turns go around and the group winner leads the next group', () {
      final e = fixedEngine([
        deckFor([strongHand]),
      ]);
      var s = arrangeAll(e, start(e), custom: {0: strong0});
      for (final seat in [0, 1, 2, 3]) {
        expect(s.turnSeat, seat);
        s = e.applyMove(s, PlayGroup(seat, 0));
      }
      expect(s.groupWinners, [0]);
      expect(s.groupIndex, 1);
      expect(s.turnSeat, 0);
    });

    test('duplicate play event is rejected (idempotency)', () {
      final e = fixedEngine([
        deckFor([strongHand]),
      ]);
      var s = arrangeAll(e, start(e));
      s = e.applyMove(s, const PlayGroup(0, 0));
      expect(e.validateMove(s, const PlayGroup(0, 0)).isValid, isFalse);
    });
  });

  group('scoring', () {
    test('sweep replaces group points by default (5 total)', () {
      final e = fixedEngine([
        deckFor([strongHand]),
      ]);
      var s = arrangeAll(e, start(e, rules: noBonus), custom: {0: strong0});
      s = playRound(e, s);
      expect(s.phase, GamePhase.roundOver);
      expect(s.lastRound!.groupWinners, [0, 0, 0, 0]);
      expect(s.lastRound!.sweepSeat, 0);
      expect(s.scores[0], 5);
    });

    test('sweep can stack on top of group points', () {
      final e = fixedEngine([
        deckFor([strongHand]),
      ]);
      var s = arrangeAll(
        e,
        start(
          e,
          rules: const RuleConfig(
            fourCardWeakest: false,
            sweepReplacesGroupPoints: false,
            threeTrailsPoints: 0,
            fourOfAKindPoints: 0,
          ),
        ),
        custom: {0: strong0},
      );
      s = playRound(e, s);
      expect(s.scores[0], 9);
    });

    test('each group win is one point and totals match', () {
      final e = ChuchulaGameEngine(random: SeededRandomSource(3));
      var s = arrangeAll(e, start(e));
      s = playRound(e, s);
      final rr = s.lastRound!;
      final bonusTotal = [
        for (final b in rr.bonuses) b.fold<int>(0, (t, x) => t + x.points),
      ];
      for (var i = 0; i < 4; i++) {
        final won = rr.groupWinners.where((w) => w == i).length;
        final groupPts = won == 4 ? 5 : won;
        expect(rr.points[i], groupPts + bonusTotal[i]);
      }
    });

    test('scorer: bonuses stack or take the larger', () {
      const bonuses = [Bonus(BonusType.fourOfAKind, 4)];
      final stacked = RoundScorer.scoreSeat(
        seat: 0,
        groupWinners: [0, 1, 0, 2],
        bonuses: bonuses,
        rules: RuleConfig.standard,
      );
      expect(stacked.total, 6);
      final larger = RoundScorer.scoreSeat(
        seat: 0,
        groupWinners: [0, 1, 0, 2],
        bonuses: bonuses,
        rules: const RuleConfig(
          fourCardWeakest: false,
          bonusesStackWithGroupPoints: false,
        ),
      );
      expect(larger.total, 4);
    });

    test('automatic bonuses: four of a kind scores at round end', () {
      final e = fixedEngine([
        deckFor(['9S 9H 9D 9C 2S 3H 5D 7C JS QH KD AC 4S']),
      ]);
      const auto = RuleConfig(fourCardWeakest: false, declareBonuses: false);
      var s = playRound(e, arrangeAll(e, start(e, rules: auto)));
      expect(
        s.lastRound!.bonuses[0],
        contains(const Bonus(BonusType.fourOfAKind, 4)),
      );
    });

    test('bonus detector: six pairs, three trails, all ranks', () {
      const r = RuleConfig.standard;
      List<BonusType> t(String h) =>
          BonusDetector.detect(parseCards(h), r).map((b) => b.type).toList();
      expect(t('2S 2H 3S 3H 4S 4H 5S 5H 6S 6H 7S 7H 9D'), [BonusType.sixPairs]);
      expect(t('2S 2H 2D 3S 3H 3D 4S 4H 4D 6S 7H 9C JD'), [
        BonusType.threeTrails,
      ]);
      // Three trails also contain three pairs, not six.
      expect(t('AS 2H 3D 4C 5S 6H 7D 8C 9S 10H JD QC KS'), [
        BonusType.allRanks,
      ]);
      // Four of a kind counts as two pairs for six pairs.
      expect(t('2S 2H 2D 2C 3S 3H 4S 4H 5S 5H 6S 6H 9D'), [
        BonusType.fourOfAKind,
        BonusType.sixPairs,
      ]);
      expect(t('2S 5H 8D JC AS 3H 6D 9C QS 4H 7D 10C 2H'), isEmpty);
    });
  });

  group('showing special hands', () {
    test('four of a kind: shown during arranging, +4, round ends', () {
      final e = fixedEngine([
        deckFor(['9S 9H 9D 9C 2S 3H 5D 7C JS QH KD AC 4S']),
      ]);
      final s = start(e);
      expect(ChuchulaGameEngine.showable(s, 0), [
        const Bonus(BonusType.fourOfAKind, 4),
      ]);
      expect(
        e.validateMove(s, const ShowHand(1)).error,
        RuleError.nothingToShow,
      );
      final next = e.applyMove(s, const ShowHand(0));
      expect(next.phase, GamePhase.roundOver);
      expect(next.scores, [4, 0, 0, 0]);
      expect(next.lastRound!.shownSeat, 0);
      expect(next.lastRound!.instantWinHand!.toSet(), s.hands[0].toSet());
      expect(next.lastRound!.groupWinners, isEmpty);
      // Nothing more can be shown or arranged in that round.
      expect(
        e.validateMove(next, const ShowHand(0)).error,
        RuleError.wrongPhase,
      );
    });

    test('six pairs +6 and three trails +9', () {
      final pairs = fixedEngine([
        deckFor(['2S 2H 3S 3H 4S 4H 5S 5H 6S 6H 7S 7H 9D']),
      ]);
      expect(pairs.applyMove(start(pairs), const ShowHand(0)).scores[0], 6);
      final trails = fixedEngine([
        deckFor(['2S 2H 2D 3S 3H 3D 4S 4H 4D 6S 7H 9C JD']),
      ]);
      expect(trails.applyMove(start(trails), const ShowHand(0)).scores[0], 9);
    });

    test('all thirteen ranks: showing wins the match', () {
      final e = fixedEngine([
        deckFor(['', 'AS 2H 3D 4C 5S 6H 7D 8C 9S 10H JD QC KS']),
      ]);
      final s = start(e);
      expect(s.phase, GamePhase.arranging, reason: 'not automatic');
      final next = e.applyMove(s, const ShowHand(1));
      expect(next.phase, GamePhase.matchOver);
      expect(next.result!.winnerSeat, 1);
      expect(next.result!.reason, MatchEndReason.instantWin);
    });

    test('unshown bonuses do not score at round end', () {
      final e = fixedEngine([
        deckFor(['9S 9H 9D 9C 2S 3H 5D 7C JS QH KD AC 4S']),
      ]);
      final s = playRound(e, arrangeAll(e, start(e)));
      expect(s.lastRound!.bonuses[0], isEmpty);
    });

    test('a show move survives a JSON round trip', () {
      final m = GameMove.fromJson(const ShowHand(2).toJson());
      expect(m, isA<ShowHand>());
      expect(m.seat, 2);
    });
  });

  group('match end', () {
    test('instant win when a seat holds all thirteen ranks', () {
      final e = fixedEngine([
        deckFor(['', 'AS 2H 3D 4C 5S 6H 7D 8C 9S 10H JD QC KS']),
      ]);
      final s = start(
        e,
        rules: const RuleConfig(fourCardWeakest: false, declareBonuses: false),
      );
      expect(s.phase, GamePhase.matchOver);
      expect(s.result!.winnerSeat, 1);
      expect(s.result!.reason, MatchEndReason.instantWin);
      expect(s.lastRound!.instantWinSeat, 1);
    });

    test('instant win can be switched off', () {
      final e = fixedEngine([
        deckFor(['', 'AS 2H 3D 4C 5S 6H 7D 8C 9S 10H JD QC KS']),
      ]);
      final s = start(
        e,
        rules: const RuleConfig(
          fourCardWeakest: false,
          allRanksInstantWin: false,
          declareBonuses: false,
        ),
      );
      expect(s.phase, GamePhase.arranging);
      expect(ChuchulaGameEngine.showable(s, 1), isEmpty);
    });

    test('two instant winners void the deal and redeal', () {
      final e = fixedEngine([
        deckFor([
          'AS 2H 3D 4C 5S 6H 7D 8C 9S 10H JD QC KS',
          'AH 2D 3C 4S 5H 6D 7C 8S 9H 10D JC QS KH',
        ]),
        deckFor([strongHand]),
      ]);
      final s = start(
        e,
        rules: const RuleConfig(fourCardWeakest: false, declareBonuses: false),
      );
      expect(s.phase, GamePhase.arranging);
      expect(s.hands[0].toSet(), parseCards(strongHand).toSet());
    });

    test('winner check: at least target, highest wins, tie continues', () {
      const r = RuleConfig.standard;
      expect(RoundScorer.matchWinner([19, 3, 0, 0], r), isNull);
      expect(RoundScorer.matchWinner([20, 3, 0, 0], r), 0);
      expect(RoundScorer.matchWinner([22, 25, 0, 0], r), 1);
      expect(RoundScorer.matchWinner([22, 22, 0, 0], r), isNull);
      const exact = RuleConfig(fourCardWeakest: false, targetIsExact: true);
      expect(RoundScorer.matchWinner([21, 3, 0, 0], exact), isNull);
      expect(RoundScorer.matchWinner([20, 3, 0, 0], exact), 0);
      expect(RoundScorer.applyTarget(18, 3, exact), 0);
      expect(RoundScorer.applyTarget(18, 2, exact), 2);
    });

    test('rounds continue until the target and dealer rotates', () {
      final e = ChuchulaGameEngine(random: SeededRandomSource(11));
      var s = start(e);
      var rounds = 0;
      while (s.phase != GamePhase.matchOver) {
        expect(s.dealerSeat, (3 + s.round - 1) % 4);
        s = playRound(e, arrangeAll(e, s));
        rounds++;
        if (s.phase == GamePhase.roundOver) {
          expect(e.validateMove(s, const PlayGroup(0, 0)).isValid, isFalse);
          s = e.applyMove(s, const StartNextRound(0));
        }
      }
      expect(rounds, greaterThan(1));
      final r = s.result!;
      expect(r.finalScores[r.winnerSeat], greaterThanOrEqualTo(20));
      expect(
        e.validateMove(s, const StartNextRound(0)).error,
        RuleError.matchOver,
      );
      // Score equals the sum of round points: no double awards.
      for (var i = 0; i < 4; i++) {
        expect(
          s.scores[i],
          s.history.fold<int>(0, (t, rr) => t + rr.points[i]),
        );
      }
    });
  });

  group('serialization and views', () {
    test('state survives a JSON round trip mid-round', () {
      final e = ChuchulaGameEngine(random: SeededRandomSource(5));
      var s = arrangeAll(e, start(e));
      s = e.applyMove(s, PlayGroup(s.turnSeat!, 0));
      final json = jsonEncode(s.toJson());
      final restored = GameState.fromJson(jsonDecode(json));
      expect(jsonEncode(restored.toJson()), json);
      // The restored state keeps playing.
      final cont = playRound(e, restored);
      expect(cont.phase, isNot(GamePhase.playing));
    });

    test('corrupt saves are rejected', () {
      expect(() => GameState.fromJson({'schema': 99}), throwsFormatException);
    });

    test('moves round-trip through JSON', () {
      final e = fixedEngine([
        deckFor([strongHand]),
      ]);
      final s = start(e);
      final moves = <GameMove>[
        SubmitArrangement(0, Arrangement.fromOrderedCards(s.hands[0])),
        const PlayGroup(2, 1),
        const StartNextRound(3),
      ];
      for (final m in moves) {
        expect(
          jsonEncode(GameMove.fromJson(m.toJson()).toJson()),
          jsonEncode(m.toJson()),
        );
      }
    });

    test('player view hides other hands and unplayed groups', () {
      final e = fixedEngine([
        deckFor([strongHand]),
      ]);
      var s = arrangeAll(e, start(e));
      s = e.applyMove(s, const PlayGroup(0, 0));
      final view = PlayerView.of(s, 1);
      final json = jsonEncode(view.toJson());
      // Seat 0's unplayed cards must not appear anywhere in seat 1's view.
      final hidden = s.arrangements[0]!.groups.skip(1).expand((g) => g);
      for (final c in hidden) {
        expect(json.contains('"${c.code}"'), isFalse, reason: c.code);
      }
      // Seat 0's revealed group is visible.
      expect(view.roundPlays[0][0], s.arrangements[0]!.groups[0]);
      expect(view.myHand, s.hands[1]);
      final back = PlayerView.fromJson(jsonDecode(json));
      expect(jsonEncode(back.toJson()), json);
    });
  });
}
