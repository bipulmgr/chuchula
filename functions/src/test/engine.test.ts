import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { arrangeHand, botMove } from '../engine/bot';
import { cardCode, fullDeck, parseCards } from '../engine/card';
import { ChuchulaEngine, InvalidMoveError, dealHands, secureDecks } from '../engine/engine';
import { evaluate } from '../engine/evaluator';
import { GameState, SeatInfo, parseMove, playerView } from '../engine/state';

const seats: SeatInfo[] = [0, 1, 2, 3].map((i) => ({ id: `p${i}`, name: `P${i}`, isBot: false, avatar: i }));

describe('engine', () => {
  it('secure decks are full permutations', () => {
    for (let i = 0; i < 20; i++) {
      const d = secureDecks.nextDeck();
      assert.equal(new Set(d).size, 52);
    }
  });

  it('deals 13 sorted cards to each seat starting after the dealer', () => {
    const deck = Array.from({ length: 52 }, (_, i) => i);
    const hands = dealHands(deck, 3);
    assert.equal(hands.length, 4);
    for (const h of hands) assert.equal(h.length, 13);
    assert.equal(hands[0][0], '2C'); // id 0 goes to seat 0
    assert.equal(new Set(hands.flat()).size, 52);
  });

  it('views never contain another seat\'s hand', () => {
    const engine = new ChuchulaEngine();
    const s = engine.startGame({ matchId: 'm', seats });
    for (let seat = 0; seat < 4; seat++) {
      const text = JSON.stringify(playerView(s, seat));
      for (let other = 0; other < 4; other++) {
        if (other === seat) continue;
        for (const c of s.hands[other]) assert.ok(!text.includes(`"${c}"`), `${seat} sees ${c}`);
      }
    }
  });

  it('rejects malformed and foreign moves', () => {
    const engine = new ChuchulaEngine();
    const s = engine.startGame({ matchId: 'm', seats });
    assert.throws(() => parseMove(null));
    assert.throws(() => parseMove({ type: 'nope', seat: 0 }));
    assert.throws(() => parseMove({ type: 'arrange', seat: 0, arrangement: 'AS' }));
    const foreign = [s.hands[1].slice(0, 3), s.hands[0].slice(3, 6), s.hands[0].slice(6, 9), s.hands[0].slice(9, 13)];
    assert.throws(
      () => engine.applyMove(s, { type: 'arrange', seat: 0, arrangement: foreign }),
      (e: unknown) => e instanceof InvalidMoveError && e.error === 'cardNotOwned',
    );
    const bogus = [['ZZ', 'AS', 'KS'], ...foreign.slice(1)];
    assert.equal(engine.validateArrangement(s, 0, bogus)?.error, 'cardNotOwned');
  });

  it('plays a whole match with server bots', () => {
    const engine = new ChuchulaEngine();
    let s: GameState = engine.startGame({ matchId: 'm', seats });
    for (let guard = 0; guard < 5000 && s.phase !== 'matchOver'; guard++) {
      if (s.phase === 'roundOver') {
        s = engine.applyMove(s, { type: 'next', seat: 0 });
        continue;
      }
      for (let seat = 0; seat < 4; seat++) {
        const m = botMove(playerView(s, seat));
        if (m) s = engine.applyMove(s, m);
      }
    }
    assert.equal(s.phase, 'matchOver');
    assert.ok(s.result);
  });
});

describe('server bot', () => {
  it('uses every card exactly once in a 3-3-3-4 split', () => {
    const deck = fullDeck();
    for (let i = 0; i < 10; i++) {
      const hand = deck.slice(i * 4, i * 4 + 13).map(cardCode);
      const a = arrangeHand(hand);
      assert.deepEqual(a.map((g) => g.length), [3, 3, 3, 4]);
      assert.deepEqual([...a.flat()].sort(), [...hand].sort());
    }
  });

  it('keeps strong sets together', () => {
    // Bonuses count on the dealt hand, so splitting AAAA is fine as long
    // as the aces and kings still make two strong groups.
    const a = arrangeHand(parseCards('AS AH AD AC KS KH KD 2C 5D 7H 9S JC 3D').map(cardCode));
    const cats = a.map((g) => evaluate(parseCards(g.join(' '))).category);
    assert.ok(cats.filter((c) => c === 'trail' || c === 'fourOfAKind').length >= 2, cats.join());
  });

  it('arranges quickly', () => {
    const s = new ChuchulaEngine().startGame({ matchId: 'm', seats });
    const t = Date.now();
    arrangeHand(s.hands[0]);
    assert.ok(Date.now() - t < 1500, `took ${Date.now() - t}ms`);
  });
});
