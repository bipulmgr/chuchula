// Wire/storage shapes, identical to the JSON written by the Dart models
// (GameState.toJson, PlayerView.toJson, GameMove.toJson). Cards are codes.
import { Bonus, RuleConfig } from './rules';

export const SEAT_COUNT = 4;
export const HAND_SIZE = 13;
export const GROUP_COUNT = 4;
export const GROUP_SIZES = [3, 3, 3, 4];

export type GamePhase = 'arranging' | 'playing' | 'roundOver' | 'matchOver';
export type MatchEndReason = 'targetReached' | 'instantWin' | 'maxRounds';

export interface SeatInfo {
  id: string;
  name: string;
  isBot: boolean;
  avatar: number;
}

/** Four groups of card codes (3, 3, 3, 4). */
export type ArrangementJson = string[][];

export interface RoundResult {
  round: number;
  groupWinners: number[];
  arrangements: (ArrangementJson | null)[];
  bonuses: Bonus[][];
  points: number[];
  sweepSeat: number | null;
  instantWinSeat: number | null;
  instantWinHand: string[] | null;
}

export interface MatchResult {
  winnerSeat: number;
  reason: MatchEndReason;
  finalScores: number[];
}

export interface GameState {
  schema: 1;
  matchId: string;
  rules: RuleConfig;
  seats: SeatInfo[];
  scores: number[];
  round: number;
  dealerSeat: number;
  phase: GamePhase;
  hands: string[][];
  arrangements: (ArrangementJson | null)[];
  groupIndex: number;
  turnSeat: number | null;
  roundPlays: (string[] | null)[][];
  groupWinners: number[];
  history: RoundResult[];
  version: number;
  result: MatchResult | null;
}

export type GameMove =
  | { type: 'arrange'; seat: number; arrangement: ArrangementJson }
  | { type: 'play'; seat: number; group: number }
  | { type: 'next'; seat: number };

export type RuleError =
  | 'wrongPhase'
  | 'notYourTurn'
  | 'invalidSeat'
  | 'alreadyReady'
  | 'wrongGroupCount'
  | 'wrongGroupSize'
  | 'duplicateCard'
  | 'cardNotOwned'
  | 'missingCards'
  | 'wrongGroup'
  | 'matchOver';

export interface PlayerView {
  mySeat: number;
  matchId: string;
  seats: SeatInfo[];
  scores: number[];
  targetScore: number;
  round: number;
  dealerSeat: number;
  phase: GamePhase;
  myHand: string[];
  myArrangement: ArrangementJson | null;
  ready: boolean[];
  groupIndex: number;
  turnSeat: number | null;
  roundPlays: (string[] | null)[][];
  groupWinners: number[];
  history: RoundResult[];
  result: MatchResult | null;
  version: number;
}

/**
 * What one seat may know. Never includes another seat's hand or
 * unrevealed arrangement; mirrors PlayerView.of in Dart.
 */
export function playerView(s: GameState, seat: number): PlayerView {
  return {
    mySeat: seat,
    matchId: s.matchId,
    seats: s.seats,
    scores: s.scores,
    targetScore: s.rules.targetScore,
    round: s.round,
    dealerSeat: s.dealerSeat,
    phase: s.phase,
    myHand: s.hands[seat],
    myArrangement: s.arrangements[seat],
    ready: s.arrangements.map((a) => a !== null),
    groupIndex: s.groupIndex,
    turnSeat: s.turnSeat,
    roundPlays: s.roundPlays,
    groupWinners: s.groupWinners,
    history: s.history,
    result: s.result,
    version: s.version,
  };
}

/** Parses an untrusted move from a client. Throws on malformed input. */
export function parseMove(json: unknown): GameMove {
  if (typeof json !== 'object' || json === null) throw new Error('move must be an object');
  const m = json as Record<string, unknown>;
  const seat = m.seat;
  if (typeof seat !== 'number' || !Number.isInteger(seat)) throw new Error('bad seat');
  switch (m.type) {
    case 'arrange': {
      const a = m.arrangement;
      if (
        !Array.isArray(a) ||
        a.length > 8 ||
        !a.every((g) => Array.isArray(g) && g.length <= 13 && g.every((c) => typeof c === 'string' && c.length <= 3))
      ) {
        throw new Error('bad arrangement');
      }
      return { type: 'arrange', seat, arrangement: a as string[][] };
    }
    case 'play':
      if (typeof m.group !== 'number' || !Number.isInteger(m.group)) throw new Error('bad group');
      return { type: 'play', seat, group: m.group };
    case 'next':
      return { type: 'next', seat };
    default:
      throw new Error('unknown move type');
  }
}
