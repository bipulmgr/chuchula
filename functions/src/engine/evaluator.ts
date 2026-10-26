// Teen Patti style group ranking, mirroring
// lib/game/rules/hand_evaluator.dart. Strength integers must match the
// Dart engine exactly (checked by the parity fixtures).
import { Card, cardId } from './card';

/** Combination categories, weakest first; one ladder for 3 and 4 cards. */
export const CATEGORIES = [
  'highCard', 'pair', 'twoPair', 'color', 'sequence', 'pureSequence',
  'trail', 'fourOfAKind',
] as const;

export type HandCategory = (typeof CATEGORIES)[number];

/** Categories a full four-card group can make. */
const FOUR_CARD_CATEGORIES = new Set<HandCategory>([
  'twoPair', 'color', 'sequence', 'pureSequence', 'fourOfAKind',
]);

export interface HandValue {
  size: number;
  category: HandCategory;
  /** All four cards make the category (4-card color, run, ...). */
  fourCard: boolean;
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

/** Category and deciding ranks of exactly these cards. */
function classify(cards: Card[]): [HandCategory, number[]] {
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
  if (top === 4) return ['fourOfAKind', [grouped[0]]];
  if (top === 3) return ['trail', grouped];
  if (seq !== null && isFlush) return ['pureSequence', [seq]];
  if (seq !== null) return ['sequence', [seq]];
  if (isFlush) return ['color', values];
  if (top === 2 && counts.get(grouped[1]) === 2) return ['twoPair', grouped];
  if (top === 2) return ['pair', grouped];
  return ['highCard', values];
}

function value(
  size: number, category: HandCategory, fourCard: boolean, keys: number[], tieBreakSuit: number,
): HandValue {
  let strength = CATEGORIES.indexOf(category) * 2 + (fourCard ? 1 : 0);
  for (let i = 0; i < 4; i++) strength = strength * 16 + (i < keys.length ? keys[i] : 0);
  strength = strength * 4 + tieBreakSuit;
  return { size, category, fourCard, keys, tieBreakSuit, strength };
}

export function evaluate(cards: Card[]): HandValue {
  const size = cards.length;
  if (size !== 3 && size !== 4) {
    throw new Error(`A group must contain 3 or 4 cards, got ${size}`);
  }
  if (new Set(cards.map(cardId)).size !== size) {
    throw new Error('A group cannot contain duplicate cards');
  }
  const highest = Math.max(...cards.map((c) => c.rank));
  const tieBreakSuit = Math.max(
    ...cards.filter((c) => c.rank === highest).map((c) => c.suit),
  );
  const [category, keys] = classify(cards);
  if (size === 3) return value(3, category, false, keys, tieBreakSuit);
  // Four cards: the full four-card hand if all four make one, otherwise the
  // best three cards with the fourth as a final kicker.
  let best: HandValue | null = FOUR_CARD_CATEGORIES.has(category)
    ? value(4, category, true, keys, tieBreakSuit)
    : null;
  for (let skip = 0; skip < 4; skip++) {
    const three = cards.filter((_, i) => i !== skip);
    const [c3, k3] = classify(three);
    const v = value(4, c3, false, [...k3, cards[skip].rank], tieBreakSuit);
    if (best === null || v.strength > best.strength) best = v;
  }
  return best!;
}

/** Groups reordered strongest first, the order in which they are played. */
export function strongestFirst(groups: Card[][]): Card[][] {
  const strength = new Map(groups.map((g) => [g, evaluate(g).strength]));
  return [...groups].sort((a, b) => strength.get(b)! - strength.get(a)!);
}

/** Index of the strongest group, or -1 for an empty list. */
export function bestIndex(values: HandValue[]): number {
  let best = -1;
  for (let i = 0; i < values.length; i++) {
    if (best < 0 || values[i].strength > values[best].strength) best = i;
  }
  return best;
}
