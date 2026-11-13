import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { arrangeHand, botMove } from '../engine/bot';
import { cardCode, fullDeck, parseCards } from '../engine/card';
import { ChuchulaEngine, InvalidMoveError, dealHands, secureDecks } from '../engine/engine';
import { evaluate, fourCardIsWeakest } from '../engine/evaluator';
import { GameState, SHOW_HIDDEN, SeatInfo, parseMove, playerView } from '../engine/state';

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

  it('plays 3-card groups strongest first and the 4-card group last', () => {
    const engine = new ChuchulaEngine();
    const s = engine.startGame({ matchId: 'm', seats });
    const h = s.hands[0];
    const legal = arrangeHand(h);
    const next = engine.applyMove(s, { type: 'arrange', seat: 0, arrangement: [...legal].reverse() });
    const stored = next.arrangements[0]!;
    assert.deepEqual(stored.map((g) => g.length), [3, 3, 3, 4]);
    const strengths = stored.slice(0, 3).map((g) => evaluate(parseCards(g.join(' '))).strength);
    assert.deepEqual(strengths, [...strengths].sort((x, y) => y - x));
    const wrong = [h.slice(0, 4), h.slice(4, 8), h.slice(8, 11), h.slice(11, 13)];
    assert.equal(engine.validateArrangement(s, 0, wrong)?.error, 'wrongGroupSize');
  });

  it('refuses a 4-card group stronger than a 3-card group', () => {
    const engine = new ChuchulaEngine();
    const started = engine.startGame({ matchId: 'm', seats });
    const hand = '5D 5H 6H 7H 2D 3D AH 2S 6S 8S 10C KH AC'.split(' ');
    const s: GameState = { ...started, hands: [hand, ...started.hands.slice(1)] };
    const padded = [['5D', '5H', '6H', '7H'], ['2D', '3D', 'AH'], ['2S', '6S', '8S'], ['10C', 'KH', 'AC']];
    assert.equal(engine.validateArrangement(s, 0, padded)?.error, 'fourCardTooStrong');
    const fixed = [['5H', '6H', '7H'], ['2D', '3D', 'AC'], ['2S', '6S', '8S'], ['5D', '10C', 'KH', 'AH']];
    assert.equal(engine.validateArrangement(s, 0, fixed), null);
    const off: GameState = { ...s, rules: { ...s.rules, fourCardWeakest: false } };
    assert.equal(engine.validateArrangement(off, 0, padded), null);
    // The server bot finds a legal arrangement for this hand.
    const bot = arrangeHand(hand).map((g) => parseCards(g.join(' ')));
    assert.ok(fourCardIsWeakest(bot));
  });

  it('a picked special is checked and only it is scored', () => {
    const engine = new ChuchulaEngine();
    const started = engine.startGame({ matchId: 'm', seats });
    const hand = '9S 9H 9D 9C 2S 2H 2D 3S 3H 3D 4S 4H 4D'.split(' ');
    const s: GameState = {
      ...started,
      phase: 'arranging',
      hands: [hand, ...started.hands.slice(1)],
      rules: { ...started.rules, showWaitsForAll: false },
    };
    assert.equal(engine.validateMove(s, { type: 'show', seat: 0, bonus: 'sixPairs' })?.error, 'nothingToShow');
    const close = (x: GameState) => engine.applyMove(x, { type: 'closeShow', seat: 1 });
    const four = close(engine.applyMove(s, { type: 'show', seat: 0, bonus: 'fourOfAKind' }));
    assert.equal(four.scores[0] - s.scores[0], 4);
    const trails = close(engine.applyMove(s, { type: 'show', seat: 0, bonus: 'threeTrails' }));
    assert.equal(trails.scores[0] - s.scores[0], 9);
    assert.throws(() => parseMove({ type: 'show', seat: 0, bonus: 'royalFlush' }));
    assert.deepEqual(parseMove({ type: 'show', seat: 0, bonus: 'sixPairs' }), { type: 'show', seat: 0, bonus: 'sixPairs' });
  });

  it('gives the others a window to show, and the best special wins', () => {
    const engine = new ChuchulaEngine();
    const started = engine.startGame({ matchId: 'm', seats });
    const dealt = [
      '9S 9H 9D 9C 2S 3H 4D 5S 6H 7D 8S 10H JD'.split(' '), // four of a kind
      'AS AH KS KH QS QH JS JH 10S 10D 2H 2C 4C'.split(' '), // six pairs
      'KD KC QD QC 2D 3S 4H 5D 6S 7H 8D 10C JC'.split(' '),
    ];
    const used = new Set(dealt.flat());
    const hands = [...dealt, fullDeck().map(cardCode).filter((c) => !used.has(c))];
    assert.equal(hands[3].length, 13);
    const s: GameState = { ...started, phase: 'arranging', hands, rules: { ...started.rules, showWaitsForAll: false } };
    let x = engine.applyMove(s, { type: 'show', seat: 0, bonus: 'fourOfAKind' });
    assert.equal(x.phase, 'showing');
    assert.equal(x.showOpener, 0);
    assert.equal(engine.validateMove(x, { type: 'passShow', seat: 0 })?.error, 'alreadyAnswered');
    assert.equal(engine.validateMove(x, { type: 'arrange', seat: 1, arrangement: [] })?.error, 'wrongPhase');
    x = engine.applyMove(x, { type: 'show', seat: 1, bonus: 'sixPairs' });
    x = engine.applyMove(x, { type: 'passShow', seat: 2 });
    assert.equal(x.phase, 'showing');
    x = engine.applyMove(x, { type: 'passShow', seat: 3 });
    assert.equal(x.phase, 'roundOver');
    const rr = x.history[x.history.length - 1];
    assert.equal(rr.shownSeat, 1);
    assert.deepEqual(rr.shownKinds, ['fourOfAKind', 'sixPairs', null, null]);
    assert.deepEqual(x.scores.map((v, i) => v - s.scores[i]), [0, 6, 0, 0]);
    assert.deepEqual(x.shows, [null, null, null, null]);
  });

  it('a show lets the others keep arranging, and reveals once all are ready', () => {
    const engine = new ChuchulaEngine();
    const started = engine.startGame({ matchId: 'm', seats });
    const four = '9S 9H 9D 9C 2S 3H 4D 5S 6H 7D 8S 10H JD'.split(' ');
    const used = new Set(four);
    const rest = fullDeck().map(cardCode).filter((c) => !used.has(c));
    const hands = [four, rest.slice(0, 13), rest.slice(13, 26), rest.slice(26, 39)];
    const s: GameState = { ...started, phase: 'arranging', hands, rules: { ...started.rules, fourCardWeakest: false } };
    let x = engine.applyMove(s, { type: 'show', seat: 0, bonus: 'fourOfAKind' });
    assert.equal(x.phase, 'arranging');
    assert.deepEqual(playerView(x, 1).shows, [SHOW_HIDDEN, null, null, null]);
    assert.equal(engine.validateMove(x, { type: 'arrange', seat: 0, arrangement: arrangeHand(hands[0]) })?.error, 'alreadyAnswered');
    for (const seat of [1, 2, 3]) {
      if (x.phase !== 'arranging') break;
      const move = botMove(playerView(x, seat));
      assert.ok(move);
      x = engine.applyMove(x, move!);
    }
    assert.equal(x.phase === 'roundOver' || x.phase === 'matchOver', true);
    assert.equal(x.history[x.history.length - 1].shownKinds[0], 'fourOfAKind');
  });

  it('holds a 4-card group against the own 3-card groups by its best three', () => {
    // 3rd group: color A-J-9; 4th group: 4-card color A-J-8-7.
    const groups = ['KS KH KD', 'QS QH QD', 'AH JH 9H', 'AC JC 8C 7C'].map(parseCards);
    assert.ok(fourCardIsWeakest(groups));
    assert.ok(!fourCardIsWeakest(['KS KH KD', 'QS QH QD', 'AH JH 7H', 'AC JC 8C 7C'].map(parseCards)));
  });

  it('a double run in the last group wins the match', () => {
    const engine = new ChuchulaEngine();
    const started = engine.startGame({ matchId: 'm', seats });
    const arrangement = (codes: string[]) => codes.map((g) => g.split(' '));
    const arrangements = [
      arrangement(['AS AH AD', 'KS KH KD', 'QS QH QD', '5C 6C 7C 9D']),
      arrangement(['2S 3H 5D', '2H 4S 6D', '2D 3S 7H', '8S 9H JD 4C']),
      arrangement(['3D 4H 8D', '4D 5S 9S', '6S 7S 10D', '10S JS 2C 3C']),
      arrangement(['5H 6H 10H', '7D 8H JH', '8C 9C 10C', 'QC KC AC JC']),
    ];
    const s: GameState = {
      ...started,
      phase: 'playing',
      hands: arrangements.map((a) => a.flat()),
      arrangements,
      groupIndex: 3,
      turnSeat: 3,
      roundPlays: [0, 1, 2, 3].map((g) => arrangements.map((a) => a[g])),
      groupWinners: [0, 0, 0],
    };
    s.roundPlays[3][3] = null;
    const done = engine.applyMove(s, { type: 'play', seat: 3, group: 3 });
    // Seat 3's A-K-Q-J of clubs and seat 0's 5-6-7 of clubs are both double
    // runs; the stronger one wins the match.
    assert.equal(done.phase, 'matchOver');
    assert.equal(done.result?.reason, 'doubleRun');
    assert.equal(done.result?.winnerSeat, 3);
    assert.equal(done.history[done.history.length - 1].doubleRunSeat, 3);
  });

  it('ranks 3- and 4-card groups on one ladder', () => {
    const v = (codes: string) => evaluate(parseCards(codes));
    assert.equal(v('8S JS KH AS').category, 'color');
    assert.ok(v('8S 6S 4S 2S').strength > v('AH 9H 5H').strength);
    assert.ok(v('2C 3D 4H').strength > v('8S 6S 4S 2S').strength);
    assert.ok(v('2C 2D 2H').strength > v('5H 6H 7H 8H').strength);
    // A spare fourth card adds nothing.
    assert.equal(v('5D 5H 6H 7H').strength, v('5H 6H 7H').strength);
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
  it('uses every card once, triples strongest first, the 4-card group last', () => {
    const deck = fullDeck();
    for (let i = 0; i < 10; i++) {
      const hand = deck.slice(i * 4, i * 4 + 13).map(cardCode);
      const a = arrangeHand(hand);
      assert.deepEqual(a.map((g) => g.length), [3, 3, 3, 4]);
      assert.deepEqual([...a.flat()].sort(), [...hand].sort());
      const strengths = a.map((g) => evaluate(parseCards(g.join(' '))).strength);
      assert.deepEqual(strengths, [...strengths].sort((x, y) => y - x));
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
