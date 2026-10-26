// Teen Patti style group ranking, mirroring
// lib/game/rules/hand_evaluator.dart. Strength integers must match the
// Dart engine exactly (checked by the parity fixtures).
import { Card, cardId } from './card';

export type HandCategory =
  | 'highCard'
  | 'pair'
  | 'twoPair'
  | 'color'
  | 'sequence'
  | 'trail'
  | 'pureSequence'
  | 'fourOfAKind';

/** Three-card ranking, strongest last. */
export const CATEGORY_ORDER_3: HandCategory[] = [
  'highCard', 'pair', 'color', 'sequence', 'pureSequence', 'trail',
];

/** Four-card ranking, strongest last. */
export const CATEGORY_ORDER_4: HandCategory[] = [
  'highCard', 'pair', 'twoPair', 'color', 'sequence', 'trail',
  'pureSequence', 'fourOfAKind',
];

export interface HandValue {
  size: number;
  category: HandCategory;
  keys: number[];
  tieBreakSuit: number;
  strength: number;
}

function sequenceKey(desc: number[]): number | null {
  if (new Set(desc).size !== desc.length) return null;
  const n = desc.length;
  if (desc[0] - desc[n - 1] === n - 1) return desc[0] === 14 ? 15 : desc[0];
  if (desc[0] === 14) {
    const rest = desc.slice(1);
    if (rest[0] === n && rest[rest.length - 1] === 2) return 14;
  }
  return null;
}

export function evaluate(cards: Card[]): HandValue {
  const size = cards.length;
  if (size !== 3 && size !== 4) {
    throw new Error(`A group must contain 3 or 4 cards, got ${size}`);
  }
  if (new Set(cards.map(cardId)).size !== size) {
    throw new Error('A group cannot contain duplicate cards');
  }
  const values = cards.map((c) => c.rank).sort((a, b) => b - a);
  const counts = new Map<number, number>();
  for (const v of values) counts.set(v, (counts.get(v) ?? 0) + 1);
  const grouped = [...counts.keys()].sort((a, b) => {
    const byCount = counts.get(b)! - counts.get(a)!;
    return byCount !== 0 ? byCount : b - a;
  });
  const isFlush = cards.every((c) => c.suit === cards[0].suit);
  const seq = sequenceKey(values);
  const top = counts.get(grouped[0])!;

  let category: HandCategory;
  let keys: number[];
  if (top === 4) {
    category = 'fourOfAKind';
    keys = [grouped[0]];
  } else if (top === 3) {
    category = 'trail';
    keys = grouped;
  } else if (seq !== null && isFlush) {
    category = 'pureSequence';
    keys = [seq];
  } else if (seq !== null) {
    category = 'sequence';
    keys = [seq];
  } else if (isFlush) {
    category = 'color';
    keys = values;
  } else if (top === 2 && counts.get(grouped[1]) === 2) {
    category = 'twoPair';
    keys = grouped;
  } else if (top === 2) {
    category = 'pair';
    keys = grouped;
  } else {
    category = 'highCard';
    keys = values;
  }

  const highest = values[0];
  const tieBreakSuit = Math.max(
    ...cards.filter((c) => c.rank === highest).map((c) => c.suit),
  );
  const order = size === 3 ? CATEGORY_ORDER_3 : CATEGORY_ORDER_4;
  let strength = order.indexOf(category);
  for (let i = 0; i < 4; i++) strength = strength * 16 + (i < keys.length ? keys[i] : 0);
  strength = strength * 4 + tieBreakSuit;
  return { size, category, keys, tieBreakSuit, strength };
}

/** Index of the strongest group, or -1 for an empty list. */
export function bestIndex(values: HandValue[]): number {
  let best = -1;
  for (let i = 0; i < values.length; i++) {
    if (best < 0 || values[i].strength > values[best].strength) best = i;
  }
  return best;
}
