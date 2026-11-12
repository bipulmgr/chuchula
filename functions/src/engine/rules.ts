// Rule switches, mirroring lib/game/rules/rule_config.dart and bonuses.dart.
import { Card } from './card';

export interface RuleConfig {
  targetScore: number;
  targetIsExact: boolean;
  groupWinPoints: number;
  sweepPoints: number;
  sweepReplacesGroupPoints: boolean;
  fourOfAKindPoints: number;
  sixPairsPoints: number;
  threeTrailsPoints: number;
  bonusesStackWithGroupPoints: boolean;
  allRanksInstantWin: boolean;
  strongestFirst: boolean;
  fourCardWeakest: boolean;
  declareBonuses: boolean;
  maxRounds: number;
  showWindowSeconds: number;
  /** No time limit on the show window: it waits for every answer. */
  showWaitsForAll: boolean;
  lastGroupDoubleRunWins: boolean;
}

export const STANDARD_RULES: RuleConfig = Object.freeze({
  targetScore: 20,
  targetIsExact: false,
  groupWinPoints: 1,
  sweepPoints: 5,
  sweepReplacesGroupPoints: true,
  fourOfAKindPoints: 4,
  sixPairsPoints: 6,
  threeTrailsPoints: 9,
  bonusesStackWithGroupPoints: true,
  allRanksInstantWin: true,
  strongestFirst: true,
  fourCardWeakest: true,
  declareBonuses: true,
  maxRounds: 100,
  showWindowSeconds: 20,
  showWaitsForAll: true,
  lastGroupDoubleRunWins: true,
});

export function rulesFromJson(json: Partial<RuleConfig> | undefined): RuleConfig {
  const r: RuleConfig = { ...STANDARD_RULES };
  for (const k of Object.keys(STANDARD_RULES) as (keyof RuleConfig)[]) {
    const v = json?.[k];
    if (typeof v === typeof STANDARD_RULES[k]) (r as unknown as Record<string, unknown>)[k] = v;
  }
  return r;
}

export const BONUS_TYPES = ['fourOfAKind', 'sixPairs', 'threeTrails', 'allRanks'] as const;
export type BonusType = (typeof BONUS_TYPES)[number];

export interface Bonus {
  type: BonusType;
  points: number;
}

function rankCounts(hand: Card[]): Map<number, number> {
  const counts = new Map<number, number>();
  for (const c of hand) counts.set(c.rank, (counts.get(c.rank) ?? 0) + 1);
  return counts;
}

export function hasAllRanks(hand: Card[]): boolean {
  return hand.length === 13 && rankCounts(hand).size === 13;
}

/** Same order and counting as BonusDetector.detect in Dart. */
export function detectBonuses(hand: Card[], rules: RuleConfig): Bonus[] {
  const counts = [...rankCounts(hand).values()];
  const bonuses: Bonus[] = [];
  if (rules.allRanksInstantWin && hasAllRanks(hand)) {
    bonuses.push({ type: 'allRanks', points: 0 });
  }
  const quads = counts.filter((n) => n === 4).length;
  for (let i = 0; i < quads; i++) {
    bonuses.push({ type: 'fourOfAKind', points: rules.fourOfAKindPoints });
  }
  const pairs = counts.reduce((s, n) => s + Math.floor(n / 2), 0);
  if (pairs >= 6) bonuses.push({ type: 'sixPairs', points: rules.sixPairsPoints });
  const trails = counts.filter((n) => n >= 3).length;
  if (trails >= 3) bonuses.push({ type: 'threeTrails', points: rules.threeTrailsPoints });
  return bonuses;
}

/** The best special to show: all ranks wins the match, otherwise the kind worth most. */
export function bestShow(bonuses: Bonus[]): BonusType | null {
  if (bonuses.length === 0) return null;
  if (bonuses.some((b) => b.type === 'allRanks')) return 'allRanks';
  const totals = new Map<BonusType, number>();
  for (const b of bonuses) totals.set(b.type, (totals.get(b.type) ?? 0) + b.points);
  let best: BonusType | null = null;
  for (const [t, v] of totals) if (best === null || v > totals.get(best)!) best = t;
  return best;
}

/**
 * Ranks special hands against each other (BonusDetector.showRank in Dart): all
 * thirteen ranks, then three trails, six pairs, four of a kind; the same kind
 * compares by its ranks, highest first.
 */
export function showRank(hand: Card[], type: BonusType): number[] {
  const kind = { fourOfAKind: 0, sixPairs: 1, threeTrails: 2, allRanks: 3 }[type];
  const need = { fourOfAKind: 4, sixPairs: 2, threeTrails: 3, allRanks: 99 }[type];
  const ranks = [...rankCounts(hand).entries()].filter(([, n]) => n >= need).map(([r]) => r).sort((a, b) => b - a);
  return [kind, ...ranks];
}

export function compareShowRanks(a: number[], b: number[]): number {
  for (let i = 0; i < a.length && i < b.length; i++) if (a[i] !== b[i]) return a[i] - b[i];
  return a.length - b.length;
}
