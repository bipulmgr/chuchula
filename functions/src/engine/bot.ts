// A simple server-side bot. It receives only its own PlayerView (its own
// hand), so it cannot see hidden opponent cards or the deck.
import { Card, cardCode, parseCard } from './card';
import { CATEGORIES, evaluate, strongestFirst } from './evaluator';
import { ArrangementJson, GameMove, PlayerView } from './state';

/** Rough 0..1 strength of a group: category first, then top rank. */
function score(group: Card[]): number {
  const v = evaluate(group);
  const top = v.keys[0] ?? 0;
  return (CATEGORIES.indexOf(v.category) + (v.fourCard ? 0.5 : 0) + top / 32) / CATEGORIES.length;
}

function* combinations<T>(items: T[], k: number, start = 0, acc: T[] = []): Generator<T[]> {
  if (acc.length === k) {
    yield [...acc];
    return;
  }
  for (let i = start; i <= items.length - (k - acc.length); i++) {
    acc.push(items[i]);
    yield* combinations(items, k, i + 1, acc);
    acc.pop();
  }
}

/**
 * Picks the arrangement that maximises the sum of squared group scores
 * (favouring a few strong groups over many average ones). Groups are
 * returned strongest first, the order they are played in.
 * Group scores are computed once per card subset (286 triples, 715 quads).
 */
export function arrangeHand(handCodes: string[]): ArrangementJson {
  const hand = handCodes.map(parseCard);
  const idx = hand.map((_, i) => i);
  const groupScore = new Map<number, number>();
  const maskOf = (ix: number[]) => ix.reduce((m, i) => m | (1 << i), 0);
  for (const k of [3, 4]) {
    for (const ix of combinations(idx, k)) {
      groupScore.set(maskOf(ix), score(ix.map((i) => hand[i])) ** 2);
    }
  }
  const full = (1 << hand.length) - 1;
  let bestValue = -1;
  let bestMasks: number[] = [];
  for (const quad of combinations(idx, 4)) {
    const quadMask = maskOf(quad);
    const quadScore = groupScore.get(quadMask)!;
    const rest = idx.filter((i) => !(quadMask & (1 << i)));
    // Partition the other nine cards into three triples (280 ways).
    const [first, ...others] = rest;
    for (const pairA of combinations(others, 2)) {
      const m1 = maskOf([first, ...pairA]);
      const left = others.filter((i) => !(m1 & (1 << i)));
      const [second, ...others2] = left;
      for (const pairB of combinations(others2, 2)) {
        const m2 = maskOf([second, ...pairB]);
        const m3 = full & ~quadMask & ~m1 & ~m2;
        const value = quadScore + groupScore.get(m1)! + groupScore.get(m2)! + groupScore.get(m3)!;
        if (value > bestValue) {
          bestValue = value;
          bestMasks = [m1, m2, m3, quadMask];
        }
      }
    }
  }
  const groups = bestMasks.map((m) => hand.filter((_, i) => m & (1 << i)));
  return strongestFirst(groups).map((g) => g.map(cardCode));
}

/** The bot's next move for [view], or null if it has nothing to do. */
export function botMove(view: PlayerView): GameMove | null {
  const seat = view.mySeat;
  if (view.phase === 'arranging' && !view.ready[seat]) {
    return { type: 'arrange', seat, arrangement: arrangeHand(view.myHand) };
  }
  if (view.phase === 'playing' && view.turnSeat === seat) {
    return { type: 'play', seat, group: view.groupIndex };
  }
  return null;
}
