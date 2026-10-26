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

  group('four-card categories', () {
    test('detects every category', () {
      expect(v('9S 9H 9D 9C').category, HandCategory.fourOfAKind);
      expect(v('5H 6H 7H 8H').category, HandCategory.pureSequence);
      expect(v('5H 5S 5D 8H').category, HandCategory.trail);
      expect(v('5H 6S 7D 8H').category, HandCategory.sequence);
      expect(v('2H 6H 9H KH').category, HandCategory.color);
      expect(v('2H 2S KD KC').category, HandCategory.twoPair);
      expect(v('2H 2S 9D KC').category, HandCategory.pair);
      expect(v('2H 5S 9D KC').category, HandCategory.highCard);
    });

    test('rarity order for four cards', () {
      expectStronger('2S 2H 2D 2C', 'AS KS QS JS');
      expectStronger('2S 3S 4S 5S', 'AS AH AD KC');
      expectStronger('2S 2H 2D 3C', 'AS KH QD JC');
      expectStronger('2S 3H 4D 5C', 'AS KS 9S 7S');
      expectStronger('2S 5S 7S 9S', 'AS AH KD KC');
      expectStronger('2S 2H 3D 3C', 'AS AH KD QC');
      expectStronger('2S 2H 3D 4C', 'AS KH QD 9C');
    });

    test('four-card sequences with aces', () {
      expectStronger('AS KH QD JC', 'AH 2S 3D 4C');
      expectStronger('AH 2S 3D 4C', 'KS QH JD 10C');
      expect(v('AH 2S 3D 5C').category, HandCategory.highCard);
    });

    test('two pair and trail kickers', () {
      expectStronger('KS KH 2D 2C', 'QS QH JD JC');
      expectStronger('KS KH 3D 3C', 'KD KC 2S 2H');
      expectStronger('9S 9H 9D AC', 'KC 8S 8H 8D');
    });
  });

  test('rejects wrong sizes and duplicates', () {
    expect(() => v('AS KS'), throwsArgumentError);
    expect(() => v('AS KS QS JS 10S'), throwsArgumentError);
    expect(() => v('AS AS KS'), throwsArgumentError);
    expect(() => v('3S 4S').compareTo(v('3S 4S 5S')), throwsArgumentError);
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
