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

/// The older timed show window, which stops arranging.
const _timedShow = RuleConfig(fourCardWeakest: false, showWaitsForAll: false);

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

  group('show window', () {
    // Seat 0: four nines. Seat 1: six pairs. Seat 2: four kings.
    List<int> deck() => deckFor([
      '9S 9H 9D 9C 2S 3H 5D 7C JS QH 4D AC 4S',
      '2D 2H 3S 3D 5S 5H 6S 6H 7S 7H 8S 8H 10D',
      'KS KH KD KC 2C 3C 5C 6C 8C 10C JC QC AH',
    ]);

    test('others may answer; the best special wins the round', () {
      final e = fixedEngine([deck()]);
      var s = e.applyMove(start(e, rules: _timedShow), const ShowHand(0));
      expect(s.phase, GamePhase.showing);
      // Only answers are allowed now.
      expect(
        e
            .validateMove(
              s,
              SubmitArrangement(1, Arrangement.fromOrderedCards(s.hands[1])),
            )
            .error,
        RuleError.wrongPhase,
      );
      expect(
        e.validateMove(s, const PassShow(0)).error,
        RuleError.alreadyAnswered,
      );
      expect(
        e.validateMove(s, const ShowHand(0)).error,
        RuleError.alreadyAnswered,
      );
      expect(
        e.validateMove(s, const ShowHand(3)).error,
        RuleError.nothingToShow,
      );
      s = e.applyMove(s, const ShowHand(1, BonusType.sixPairs));
      s = e.applyMove(s, const ShowHand(2, BonusType.fourOfAKind));
      expect(s.phase, GamePhase.showing);
      s = e.applyMove(s, const PassShow(3));
      expect(s.phase, GamePhase.roundOver);
      final rr = s.lastRound!;
      // Six pairs outranks four of a kind.
      expect(rr.shownSeat, 1);
      expect(s.scores, [0, 6, 0, 0]);
      expect(rr.shownKinds, [
        BonusType.fourOfAKind,
        BonusType.sixPairs,
        BonusType.fourOfAKind,
        null,
      ]);
      expect(rr.shownHands[3], isNull);
      expect(rr.shownHands[2]!.toSet(), s.hands[2].toSet());
    });

    test('the same special compares by rank', () {
      final e = fixedEngine([deck()]);
      var s = e.applyMove(start(e, rules: _timedShow), const ShowHand(0));
      s = e.applyMove(s, const PassShow(1));
      s = e.applyMove(s, const ShowHand(2, BonusType.fourOfAKind));
      s = e.applyMove(s, const PassShow(3));
      // Four kings beat four nines.
      expect(s.lastRound!.shownSeat, 2);
      expect(s.scores, [0, 0, 4, 0]);
    });

    test('when time is up, silent seats count as passing', () {
      final e = fixedEngine([deck()]);
      var s = e.applyMove(
        start(e, rules: _timedShow),
        const ShowHand(2, BonusType.fourOfAKind),
      );
      expect(e.validateMove(s, const CloseShow(0)).isValid, isTrue);
      s = e.applyMove(s, const CloseShow(0));
      expect(s.phase, GamePhase.roundOver);
      expect(s.lastRound!.shownSeat, 2);
      expect(e.validateMove(s, const CloseShow(0)).error, RuleError.wrongPhase);
    });

    test('a window of 0 seconds ends the round at the first show', () {
      final e = fixedEngine([deck()]);
      final s = e.applyMove(
        start(e, rules: const RuleConfig(showWindowSeconds: 0)),
        const ShowHand(0),
      );
      expect(s.phase, GamePhase.roundOver);
      expect(s.scores, [4, 0, 0, 0]);
    });

    test('state and moves survive JSON', () {
      final e = fixedEngine([deck()]);
      final s = e.applyMove(start(e, rules: _timedShow), const ShowHand(0));
      final back = GameState.fromJson(
        jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
      );
      expect(back.shows, s.shows);
      expect(back.showOpener, 0);
      final view = PlayerView.fromJson(
        jsonDecode(jsonEncode(PlayerView.of(s, 1).toJson()))
            as Map<String, dynamic>,
      );
      expect(view.mustAnswerShow, isTrue);
      expect(GameMove.fromJson(const PassShow(3).toJson()), isA<PassShow>());
      expect(GameMove.fromJson(const CloseShow(1).toJson()), isA<CloseShow>());
    });

    test('only the cards that make the special are highlighted', () {
      final hand = parseCards('9S 9H 9D 9C 2S 2H 2D 3S 5H 7C JS QH AC');
      expect(
        BonusDetector.specialCards(hand, BonusType.fourOfAKind),
        parseCards('9S 9H 9D 9C').toSet(),
      );
      // A trail counts one pair: two of its cards.
      expect(BonusDetector.specialCards(hand, BonusType.sixPairs).length, 6);
      final all = parseCards('AS 2H 3D 4C 5S 6H 7D 8C 9S 10H JD QC KS');
      expect(BonusDetector.specialCards(all, BonusType.allRanks), all.toSet());
    });
  });

  group('double run in the last group', () {
    // Seat 0's last (4-card) group is the double run 5-6-7 of clubs.
    const custom = {0: 'AS AH AD KS KH KD QS QH QD 5C 6C 7C 9D'};

    test('wins the whole match', () {
      final e = fixedEngine([
        deckFor(['AS AH AD KS KH KD QS QH QD 5C 6C 7C 9D']),
      ]);
      var s = arrangeAll(e, start(e, rules: _timedShow), custom: custom);
      s = playRound(e, s);
      expect(s.phase, GamePhase.matchOver);
      expect(s.result!.reason, MatchEndReason.doubleRun);
      expect(s.result!.winnerSeat, 0);
      expect(s.lastRound!.doubleRunSeat, 0);
    });

    test('can be switched off', () {
      final e = fixedEngine([
        deckFor(['AS AH AD KS KH KD QS QH QD 5C 6C 7C 9D']),
      ]);
      final rules = const RuleConfig(
        fourCardWeakest: false,
        lastGroupDoubleRunWins: false,
      );
      var s = arrangeAll(e, start(e, rules: rules), custom: custom);
      s = playRound(e, s);
      expect(s.phase, GamePhase.roundOver);
      expect(s.lastRound!.doubleRunSeat, isNull);
    });
  });

  group('showing special hands', () {
    test('four of a kind: shown during arranging, +4, round ends', () {
      final e = fixedEngine([
        deckFor(['9S 9H 9D 9C 2S 3H 5D 7C JS QH KD AC 4S']),
      ]);
      final s = start(e, rules: _timedShow);
      expect(ChuchulaGameEngine.showable(s, 0), [
        const Bonus(BonusType.fourOfAKind, 4),
      ]);
      expect(
        e.validateMove(s, const ShowHand(1)).error,
        RuleError.nothingToShow,
      );
      final opened = e.applyMove(s, const ShowHand(0));
      // The others get a window to show theirs; nobody else has one.
      expect(opened.phase, GamePhase.showing);
      expect(opened.showOpener, 0);
      expect(opened.shows, ['fourOfAKind', null, null, null]);
      var next = opened;
      for (final seat in [1, 2, 3]) {
        next = e.applyMove(next, PassShow(seat));
      }
      expect(next.phase, GamePhase.roundOver);
      expect(next.shows, [null, null, null, null]);
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
      GameState closed(ChuchulaGameEngine e, GameState s) =>
          e.applyMove(s, const CloseShow(1));
      expect(
        closed(
          pairs,
          pairs.applyMove(start(pairs, rules: _timedShow), const ShowHand(0)),
        ).scores[0],
        6,
      );
      final trails = fixedEngine([
        deckFor(['2S 2H 2D 3S 3H 3D 4S 4H 4D 6S 7H 9C JD']),
      ]);
      expect(
        closed(
          trails,
          trails.applyMove(start(trails, rules: _timedShow), const ShowHand(0)),
        ).scores[0],
        9,
      );
    });

    test('all thirteen ranks: showing wins the match', () {
      final e = fixedEngine([
        deckFor(['', 'AS 2H 3D 4C 5S 6H 7D 8C 9S 10H JD QC KS']),
      ]);
      final s = start(e, rules: _timedShow);
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
      final s = playRound(e, arrangeAll(e, start(e, rules: _timedShow)));
      expect(s.lastRound!.bonuses[0], isEmpty);
    });

    test('a show move survives a JSON round trip', () {
      final m = GameMove.fromJson(const ShowHand(2).toJson());
      expect(m, isA<ShowHand>());
      expect(m.seat, 2);
      final picked = GameMove.fromJson(
        const ShowHand(1, BonusType.sixPairs).toJson(),
      );
      expect((picked as ShowHand).bonus, BonusType.sixPairs);
    });

    test('showing a picked special checks and scores only that one', () {
      // Four nines and three trails (2s, 3s, 4s) in one hand.
      final e = fixedEngine([
        deckFor(['9S 9H 9D 9C 2S 2H 2D 3S 3H 3D 4S 4H 4D']),
      ]);
      final s = start(e, rules: _timedShow);
      expect(
        e.validateMove(s, const ShowHand(0, BonusType.sixPairs)).error,
        RuleError.nothingToShow,
      );
      GameState closed(GameState x) => e.applyMove(x, const CloseShow(2));
      final four = closed(
        e.applyMove(s, const ShowHand(0, BonusType.fourOfAKind)),
      );
      expect(four.scores[0], 4);
      expect(four.lastRound!.bonuses[0].map((b) => b.type), [
        BonusType.fourOfAKind,
      ]);
      final trails = closed(
        e.applyMove(s, const ShowHand(0, BonusType.threeTrails)),
      );
      expect(trails.scores[0], 9);
      expect(
        ChuchulaGameEngine.bestShow(ChuchulaGameEngine.showable(s, 0)),
        BonusType.threeTrails,
      );
    });
  });

  group('show while the others arrange (default)', () {
    // Seat 0: four nines. Seat 1: six pairs. Seat 2: four kings.
    List<int> deck() => deckFor([
      '9S 9H 9D 9C 2S 3H 5D 7C JS QH 4D AC 4S',
      '2D 2H 3S 3D 5S 5H 6S 6H 7S 7H 8S 8H 10D',
      'KS KH KD KC 2C 3C 5C 6C 8C 10C JC QC AH',
    ]);
    GameState ready(ChuchulaGameEngine e, GameState s, int seat) => e.applyMove(
      s,
      SubmitArrangement(seat, Arrangement.fromOrderedCards(s.hands[seat])),
    );

    test('a show keeps arranging open, with no window and no timer', () {
      final e = fixedEngine([deck()]);
      var s = e.applyMove(start(e), const ShowHand(0));
      expect(s.phase, GamePhase.arranging);
      expect(s.showOpener, 0);
      // The shower is done; the others still arrange and tap Ready.
      expect(
        e
            .validateMove(
              s,
              SubmitArrangement(0, Arrangement.fromOrderedCards(s.hands[0])),
            )
            .error,
        RuleError.alreadyAnswered,
      );
      expect(
        e.validateMove(s, const ShowHand(0)).error,
        RuleError.alreadyAnswered,
      );
      expect(e.validateMove(s, const CloseShow(1)).error, RuleError.wrongPhase);
      s = ready(e, s, 1);
      s = ready(e, s, 3);
      // A seat that tapped Ready cannot show any more.
      expect(
        e.validateMove(s, const ShowHand(1)).error,
        RuleError.alreadyReady,
      );
      expect(s.phase, GamePhase.arranging);
      s = ready(e, s, 2);
      // Everyone is ready: the special is revealed and ends the round.
      expect(s.phase, GamePhase.roundOver);
      expect(s.scores, [4, 0, 0, 0]);
      expect(s.lastRound!.shownSeat, 0);
      expect(s.lastRound!.groupWinners, isEmpty);
      expect(s.shows, [null, null, null, null]);
    });

    test('others may show too; the best special wins when all are ready', () {
      final e = fixedEngine([deck()]);
      var s = e.applyMove(start(e), const ShowHand(2, BonusType.fourOfAKind));
      s = e.applyMove(s, const ShowHand(1, BonusType.sixPairs));
      s = ready(e, s, 3);
      expect(s.phase, GamePhase.arranging);
      s = e.applyMove(s, const ShowHand(0));
      expect(s.phase, GamePhase.roundOver);
      expect(s.lastRound!.shownSeat, 1);
      expect(s.scores, [0, 6, 0, 0]);
      expect(s.lastRound!.shownHands[3], isNull);
    });

    test('the others only learn that a special was shown, not which', () {
      final e = fixedEngine([deck()]);
      final s = e.applyMove(start(e), const ShowHand(2, BonusType.fourOfAKind));
      expect(PlayerView.of(s, 0).shows, [null, null, kShowHidden, null]);
      expect(PlayerView.of(s, 2).shows, [null, null, 'fourOfAKind', null]);
      expect(PlayerView.of(s, 0).mustAnswerShow, isFalse);
    });

    test('all thirteen ranks wins the match once everyone is ready', () {
      final e = fixedEngine([
        deckFor(['', 'AS 2H 3D 4C 5S 6H 7D 8C 9S 10H JD QC KS']),
      ]);
      var s = e.applyMove(start(e), const ShowHand(1));
      expect(s.phase, GamePhase.arranging);
      for (final seat in [0, 2, 3]) {
        s = ready(e, s, seat);
      }
      expect(s.phase, GamePhase.matchOver);
      expect(s.result!.winnerSeat, 1);
      expect(s.result!.reason, MatchEndReason.instantWin);
    });

    test('with nothing shown, play starts when all are ready', () {
      final e = fixedEngine([deck()]);
      final s = arrangeAll(e, start(e));
      expect(s.phase, GamePhase.playing);
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

  group('equal groups', () {
    // Seats 0 and 2 play the same ranks (K-K-5); the others are weaker.
    final plays = [
      parseCards('KS KH 5D'),
      parseCards('QS QH 9D'),
      parseCards('KD KC 5S'),
      parseCards('2S 3H 7D'),
    ];

    test('the player who plays last of the tied groups wins', () {
      // Turn order 0,1,2,3: seat 2 plays after seat 0.
      expect(ChuchulaGameEngine.resolveGroup(plays, leader: 0), 2);
      // Turn order 1,2,3,0: seat 0 plays last.
      expect(ChuchulaGameEngine.resolveGroup(plays, leader: 1), 0);
      // Turn order 3,0,1,2: seat 2 plays last.
      expect(ChuchulaGameEngine.resolveGroup(plays, leader: 3), 2);
    });

    test('a stronger rank wins whatever the turn order', () {
      final p = [
        parseCards('KS KH 6D'),
        parseCards('QS QH 9D'),
        parseCards('KD KC 5S'),
        parseCards('2S 3H 7D'),
      ];
      for (var leader = 0; leader < 4; leader++) {
        expect(ChuchulaGameEngine.resolveGroup(p, leader: leader), 0);
      }
    });

    test('in play, a tie goes to the seat that played later', () {
      final e = ChuchulaGameEngine();
      var s = start(e).copyWith(
        phase: GamePhase.playing,
        groupIndex: 0,
        turnSeat: () => 1,
        roundPlays: [
          [null, null, null, null],
        ],
        arrangements: [
          for (final p in plays) Arrangement([p, p, p, p]),
        ],
      );
      // Seat 1 leads, so seat 0 plays its K-K-5 after seat 2's.
      for (final seat in [1, 2, 3, 0]) {
        s = e.applyMove(s, PlayGroup(seat, 0));
      }
      expect(s.groupWinners, [0]);
      expect(s.turnSeat, 0);
    });
  });
}
