import 'dart:math';

import 'package:chuchula/game/models/card.dart';
import 'package:chuchula/game/rules/hand_evaluator.dart';
import 'package:flutter_test/flutter_test.dart';

HandValue v(String codes) => HandEvaluator.evaluate(parseCards(codes));

void expectStronger(String a, String b) {
  expect(v(a) > v(b), isTrue, reason: '$a should beat $b');
  expect(v(b) < v(a), isTrue);
}

void main() {
  group('card model', () {
    test('deck has 52 unique cards with ids 0..51', () {
      final deck = fullDeck();
      expect(deck.length, 52);
      expect(deck.toSet().length, 52);
      expect(deck.map((c) => c.id).toSet(), {for (var i = 0; i < 52; i++) i});
      for (final c in deck) {
        expect(PlayingCard.fromId(c.id), c);
        expect(PlayingCard.parse(c.code), c);
      }
    });

    test('parses ten and rejects garbage', () {
      expect(
        PlayingCard.parse('10H'),
        const PlayingCard(Rank.ten, Suit.hearts),
      );
      expect(() => PlayingCard.parse('1X'), throwsFormatException);
      expect(() => PlayingCard.fromId(52), throwsRangeError);
    });
  });

  group('three-card categories', () {
    test('detects every category', () {
      expect(v('7S 7H 7D').category, HandCategory.trail);
      expect(v('5H 6H 7H').category, HandCategory.pureSequence);
      expect(v('5H 6S 7H').category, HandCategory.sequence);
      expect(v('2H 9H KH').category, HandCategory.color);
      expect(v('9H 9S 2D').category, HandCategory.pair);
      expect(v('2H 9S KD').category, HandCategory.highCard);
    });

    test('Teen Patti category order', () {
      expectStronger('2S 2H 2D', 'AS KS QS'); // trail > pure sequence
      expectStronger('2S 3S 4S', 'AS KH QD'); // pure sequence > sequence
      expectStronger('2S 3H 4D', 'AS KS 9S'); // sequence > color
      expectStronger('2S 5S 7S', 'AS AH KD'); // color > pair
      expectStronger('2S 2H 3D', 'AS KH JD'); // pair > high card
    });

    test('ace sequences: A-K-Q highest, A-2-3 second', () {
      expectStronger('AS KH QD', 'AD 2H 3C');
      expectStronger('AD 2H 3C', 'KS QH JD');
      expectStronger('4S 3H 2D', '6C 8D 9H'); // lowest run still a run
      expect(v('AS 2H 4D').category, HandCategory.highCard);
      expect(v('QS KH AD').category, HandCategory.sequence);
      expect(v('KS AH 2D').category, HandCategory.highCard); // no wrap
    });

    test('rank comparison inside a category', () {
      expectStronger('AS AH AD', 'KS KH KD');
      expectStronger('KS KH 3D', 'QS QH AD'); // pair rank first
      expectStronger('QS QH 9D', 'QD QC 8S'); // then kicker
      expectStronger('AS 9S 3S', 'KH QH 9H'); // color
      expectStronger('AS 4H 2D', 'KS QH 10D'); // high card
      expectStronger('KS 9H 5D', 'KH 9D 4C');
    });

    test('exact rank ties are broken by suit of the highest card', () {
      expectStronger('KS 9H 5D', 'KH 9D 5C');
      expectStronger('QS QH 9D', 'QD QC 9S'); // best queen: spades
      expectStronger('AS 2H 3D', 'AH 2S 3C'); // ace is the highest card
      expect(v('KS 9H 5D').compareTo(v('KH 9D 5C')), isNot(0));
    });
  });

  group('four-card groups', () {
    test('are named after the best hand inside them', () {
      expect(v('9S 9H 9D 9C').category, HandCategory.fourOfAKind);
      expect(v('5H 6H 7H 8H').category, HandCategory.pureSequence);
      expect(v('5H 5S 5D 8H').category, HandCategory.trail);
      expect(v('5H 6S 7D 8H').category, HandCategory.sequence);
      expect(v('5H 6S 7D KC').category, HandCategory.sequence);
      expect(v('2H 6H 9H KH').category, HandCategory.color);
      expect(v('2H 2S KD KC').category, HandCategory.twoPair);
      expect(v('2H 2S 9D KC').category, HandCategory.pair);
      expect(v('2H 5S 9D KC').category, HandCategory.highCard);
      // Three spades and a heart: a Color, not High card.
      expect(v('8S JS KH AS').category, HandCategory.color);
      expect(v('AH 2S 3D 5C').category, HandCategory.sequence);
    });

    test('mark when all four cards make the hand', () {
      expect(v('2H 6H 9H KH').fourCard, isTrue);
      expect(v('5H 6S 7D 8H').fourCard, isTrue);
      expect(v('5H 6H 7H 8H').fourCard, isTrue);
      expect(v('8S JS KH AS').fourCard, isFalse);
      expect(v('5H 6S 7D KC').fourCard, isFalse);
      expect(v('5H 5S 5D 8H').fourCard, isFalse);
    });

    test('a 4-card hand beats a 3-card hand of the same kind', () {
      // 4-card color with 8 high beats a 3-card color with A.
      expectStronger('8S 6S 4S 2S', 'AH 9H 5H');
      expectStronger('8S 6S 4S 2S', '8C JC AC 3D');
      expectStronger('2S 3H 4D 5C', 'QS KH AD');
      expectStronger('2H 3H 4H 5H', 'QS KS AS');
      // To beat it: a stronger 4-card color, or a higher kind.
      expectStronger('9D 6D 4D 2D', '8S 7S 4S 2S');
      expectStronger('2C 3D 4H', '8S 6S 4S 2S');
      expectStronger('2C 3C 4C', '8S 6S 4S 2S');
      expectStronger('2C 2D 2H', '8S 6S 4S 2S');
    });

    test('one ladder for 3 and 4 cards', () {
      expectStronger('2S 2H 2D 2C', 'AS AH AD');
      expectStronger('2S 2H 2D', 'AS KS QS JS');
      expectStronger('2S 3S 4S', 'AS KH QD JC');
      expectStronger('2S 3H 4D', 'AS KS 9S 7S');
      expectStronger('2S 5S 7S', 'AS AH KD KC');
      expectStronger('2S 2H 3D 3C', 'AS AH KD');
      expectStronger('2S 2H 5D', 'AS KH 9D 7C');
      // A spare fourth card adds nothing: equal best three cards go to the
      // suit tie-break, so the K does not help the diamonds.
      expectStronger('AS JS 8S', 'AD JD 8D KH');
      expect(v('5D 5H 6H 7H').spare, PlayingCard.parse('5D'));
      expect(v('5D 5H 6H 7H').strength, v('5H 6H 7H').strength);
    });

    test('four-card sequences with aces', () {
      expectStronger('AS KH QD JC', 'AH 2S 3D 4C');
      expectStronger('AH 2S 3D 4C', 'KS QH JD 10C');
    });

    test('two pair and trail kickers', () {
      expectStronger('KS KH 2D 2C', 'QS QH JD JC');
      expectStronger('KS KH 3D 3C', 'KD KC 2S 2H');
      expectStronger('9S 9H 9D AC', 'KC 8S 8H 8D');
    });
  });

  test("Bipul's round: Pemba and Sita play strongest first", () {
    List<String> order(List<String> groups) => [
      for (final g in HandEvaluator.strongestFirst([
        for (final c in groups) parseCards(c),
      ]))
        g.map((c) => c.code).join(' '),
    ];
    // Pemba: the 4-card double run beats both runs, so it comes second.
    expect(order(['2C 2D 2H', '9C 10C JD', '4S 5H 6H', '6S 7S 8S 9S']), [
      '2C 2D 2H',
      '6S 7S 8S 9S',
      '9C 10C JD',
      '4S 5H 6H',
    ]);
    // Sita: the 4-card color beats the 3-card color and the pair.
    expect(order(['4C 5C 6C', '8C JC KC', '8H AS AH', '3D 10D JD KD']), [
      '4C 5C 6C',
      '3D 10D JD KD',
      '8C JC KC',
      '8H AS AH',
    ]);
  });

  test("Suggest's hand: the spare 5D moves off the double run", () {
    final groups = HandEvaluator.spareToWeakest([
      parseCards('5D 5H 6H 7H'),
      parseCards('2D 3D AH'),
      parseCards('2S 6S 8S'),
      parseCards('10C KH AC'),
    ]);
    expect(groups.map((g) => g.map((c) => c.code).join(' ')), [
      '5H 6H 7H',
      '2D 3D AH',
      '2S 6S 8S',
      '10C KH AC 5D',
    ]);
    // A full 4-card hand keeps all four cards.
    final full = HandEvaluator.spareToWeakest([
      parseCards('2H 5H 9H JH'),
      parseCards('2D 3D AH'),
      parseCards('2S 6S 8S'),
      parseCards('10C KH AC'),
    ]);
    expect(full.singleWhere((g) => g.length == 4).map((c) => c.code), [
      '2H',
      '5H',
      '9H',
      'JH',
    ]);
  });

  test('strongestFirst orders groups for play', () {
    final groups = [
      parseCards('2S 5H 9D'),
      parseCards('5C 5S 5D 8H'),
      parseCards('3H 7H JH'),
      parseCards('QC KD AS'),
    ];
    expect(HandEvaluator.strongestFirst(groups).map((g) => g.first.code), [
      '5C',
      'QC',
      '3H',
      '2S',
    ]);
  });

  test('rejects wrong sizes and duplicates', () {
    expect(() => v('AS KS'), throwsArgumentError);
    expect(() => v('AS KS QS JS 10S'), throwsArgumentError);
    expect(() => v('AS AS KS'), throwsArgumentError);
  });

  test('disjoint groups never tie', () {
    final deck = fullDeck();
    for (var seed = 0; seed < 2000; seed++) {
      final shuffled = List.of(deck)..shuffle(Random(seed));
      for (final size in [3, 4]) {
        final values = [
          for (var p = 0; p < 4; p++)
            HandEvaluator.evaluate(shuffled.sublist(p * size, p * size + size)),
        ];
        for (var i = 0; i < 4; i++) {
          for (var j = i + 1; j < 4; j++) {
            expect(values[i].compareTo(values[j]), isNot(0));
          }
        }
      }
    }
  });
}
