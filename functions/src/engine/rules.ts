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
});

export function rulesFromJson(json: Partial<RuleConfig> | undefined): RuleConfig {
  const r: RuleConfig = { ...STANDARD_RULES };
  for (const k of Object.keys(STANDARD_RULES) as (keyof RuleConfig)[]) {
    const v = json?.[k];
    if (typeof v === typeof STANDARD_RULES[k]) (r as unknown as Record<string, unknown>)[k] = v;
  }
  return r;
}

export type BonusType = 'fourOfAKind' | 'sixPairs' | 'threeTrails' | 'allRanks';

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
