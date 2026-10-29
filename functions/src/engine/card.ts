// Playing cards, mirroring lib/game/models/card.dart. Cards travel as
// codes like "AS" or "10H"; ids are suit * 13 + (rank - 2).

export const SUITS = ['C', 'D', 'H', 'S'] as const; // clubs < ... < spades
export const RANK_LABELS = [
  '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A',
] as const;

export interface Card {
  /** 2..14, ace high. */
  readonly rank: number;
  /** 0..3: clubs, diamonds, hearts, spades. */
  readonly suit: number;
}

export function cardId(c: Card): number {
  return c.suit * 13 + (c.rank - 2);
}

export function fromId(id: number): Card {
  if (!Number.isInteger(id) || id < 0 || id >= 52) {
    throw new RangeError(`Bad card id ${id}`);
  }
  return { rank: (id % 13) + 2, suit: Math.floor(id / 13) };
}

export function cardCode(c: Card): string {
  return `${RANK_LABELS[c.rank - 2]}${SUITS[c.suit]}`;
}

export function parseCard(code: string): Card {
  if (typeof code !== 'string') throw new Error(`Bad card "${code}"`);
  const t = code.trim().toUpperCase();
  if (t.length < 2) throw new Error(`Bad card "${code}"`);
  const suit = SUITS.indexOf(t.slice(-1) as (typeof SUITS)[number]);
  const rank = RANK_LABELS.indexOf(t.slice(0, -1) as (typeof RANK_LABELS)[number]);
  if (suit < 0 || rank < 0) throw new Error(`Bad card "${code}"`);
  return { rank: rank + 2, suit };
}

export function parseCards(codes: string): Card[] {
  return codes.split(/[\s,]+/).filter((s) => s.length > 0).map(parseCard);
}

/** Rank, then suit (display order of a dealt hand). */
export function compareCards(a: Card, b: Card): number {
  return a.rank !== b.rank ? a.rank - b.rank : a.suit - b.suit;
}

export function sameCard(a: Card, b: Card): boolean {
  return a.rank === b.rank && a.suit === b.suit;
}

export function fullDeck(): Card[] {
  return Array.from({ length: 52 }, (_, i) => fromId(i));
}
