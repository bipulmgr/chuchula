// The Chuchula rules engine, a line-by-line port of
// lib/game/engine/game_engine.dart and lib/game/scoring/round_scorer.dart.
// test/parity checks both engines produce identical JSON for the same
// decks and moves.
import { randomInt } from 'node:crypto';
import {
  Card, cardCode, cardId, compareCards, fromId, parseCard,
} from './card';
import { bestIndex, evaluate } from './evaluator';
import { Bonus, RuleConfig, STANDARD_RULES, detectBonuses, hasAllRanks } from './rules';
import {
  GROUP_COUNT, GROUP_SIZES, GameMove, GameState, MatchResult, RoundResult,
  RuleError, SEAT_COUNT, SeatInfo,
} from './state';

/** Supplies one 52-card deck order (card ids) per deal. */
export interface DeckSource {
  nextDeck(): number[];
}

/** Cryptographically secure Fisher-Yates shuffle. */
export const secureDecks: DeckSource = {
  nextDeck() {
    const deck = Array.from({ length: 52 }, (_, i) => i);
    for (let i = deck.length - 1; i > 0; i--) {
      const j = randomInt(i + 1);
      [deck[i], deck[j]] = [deck[j], deck[i]];
    }
    return deck;
  },
};

/** Pre-arranged decks, for tests and parity fixtures. */
export class FixedDecks implements DeckSource {
  private next = 0;
  constructor(private readonly decks: number[][]) {}
  nextDeck(): number[] {
    if (this.next >= this.decks.length) throw new Error('Out of fixed decks');
    return this.decks[this.next++];
  }
}

export class InvalidMoveError extends Error {
  constructor(readonly error: RuleError, readonly detail?: string) {
    super(`${error}${detail ? `: ${detail}` : ''}`);
  }
}

export interface Validation {
  error: RuleError;
  detail?: string;
}

const MAX_REDEALS = 20;

function bump(s: GameState, patch: Partial<GameState>): GameState {
  return { ...s, ...patch, version: s.version + 1 };
}

const cards = (codes: string[]): Card[] => codes.map(parseCard);
const codes = (cs: Card[]): string[] => cs.map(cardCode);

export function dealHands(deck: number[], dealerSeat: number): string[][] {
  const hands: Card[][] = Array.from({ length: SEAT_COUNT }, () => []);
  deck.forEach((id, i) => hands[(dealerSeat + 1 + i) % SEAT_COUNT].push(fromId(id)));
  return hands.map((h) => codes(h.sort(compareCards)));
}

export interface GameSetup {
  matchId: string;
  seats: SeatInfo[];
  rules?: RuleConfig;
  firstDealer?: number;
}

export class ChuchulaEngine {
  constructor(private readonly decks: DeckSource = secureDecks) {}

  startGame(setup: GameSetup): GameState {
    if (setup.seats.length !== SEAT_COUNT) {
      throw new Error(`Chuchula needs exactly ${SEAT_COUNT} seats`);
    }
    const dealer = (setup.firstDealer ?? 3) % SEAT_COUNT;
    const empty: GameState = {
      schema: 1,
      matchId: setup.matchId,
      rules: setup.rules ?? { ...STANDARD_RULES },
      seats: setup.seats,
      scores: [0, 0, 0, 0],
      round: 0,
      dealerSeat: dealer,
      phase: 'roundOver',
      hands: [[], [], [], []],
      arrangements: [null, null, null, null],
      groupIndex: 0,
      turnSeat: null,
      roundPlays: [],
      groupWinners: [],
      history: [],
      version: 0,
      result: null,
    };
    return this.dealRound(empty, dealer);
  }

  private nextDeck(): number[] {
    const order = this.decks.nextDeck();
    if (order.length !== 52 || new Set(order).size !== 52 || order.some((i) => i < 0 || i > 51)) {
      throw new Error('A deck must contain all 52 card ids');
    }
    return order;
  }

  private dealRound(s: GameState, nextDealer: number): GameState {
    for (let attempt = 0; attempt < MAX_REDEALS; attempt++) {
      const hands = dealHands(this.nextDeck(), nextDealer);
      const round = s.round + 1;
      const instant: number[] = [];
      if (s.rules.allRanksInstantWin) {
        for (let i = 0; i < SEAT_COUNT; i++) if (hasAllRanks(cards(hands[i]))) instant.push(i);
      }
      if (instant.length > 1) continue; // Void deal: redeal.

      const dealt = bump(s, {
        round,
        dealerSeat: nextDealer,
        phase: 'arranging',
        hands,
        arrangements: [null, null, null, null],
        groupIndex: 0,
        turnSeat: null,
        roundPlays: [],
        groupWinners: [],
      });
      if (instant.length === 1) {
        const seat = instant[0];
        const rr: RoundResult = {
          round,
          groupWinners: [],
          arrangements: [null, null, null, null],
          bonuses: [0, 1, 2, 3].map((i) => (i === seat ? [{ type: 'allRanks', points: 0 }] : [])),
          points: [0, 0, 0, 0],
          sweepSeat: null,
          instantWinSeat: seat,
          instantWinHand: hands[seat],
        };
        return bump(dealt, {
          phase: 'matchOver',
          history: [...s.history, rr],
          result: { winnerSeat: seat, reason: 'instantWin', finalScores: s.scores },
        });
      }
      return dealt;
    }
    throw new Error('Could not produce a valid deal');
  }

  validateArrangement(state: GameState, seat: number, groups: string[][]): Validation | null {
    if (seat < 0 || seat >= SEAT_COUNT) return { error: 'invalidSeat' };
    if (groups.length !== GROUP_COUNT) return { error: 'wrongGroupCount', detail: `${groups.length}` };
    for (let i = 0; i < GROUP_COUNT; i++) {
      if (groups[i].length !== GROUP_SIZES[i]) {
        return { error: 'wrongGroupSize', detail: `group ${i + 1} has ${groups[i].length} cards` };
      }
    }
    let all: Card[];
    try {
      all = groups.flat().map(parseCard);
    } catch {
      return { error: 'cardNotOwned' };
    }
    const ids = all.map(cardId);
    if (new Set(ids).size !== ids.length) return { error: 'duplicateCard' };
    const hand = new Set(cards(state.hands[seat]).map(cardId));
    for (const c of all) {
      if (!hand.has(cardId(c))) return { error: 'cardNotOwned', detail: cardCode(c) };
    }
    if (all.length !== hand.size) return { error: 'missingCards' };
    if (state.rules.requireAscendingStrength) {
      for (let i = 1; i < 3; i++) {
        if (evaluate(cards(groups[i])).strength < evaluate(cards(groups[i - 1])).strength) {
          return { error: 'notAscending' };
        }
      }
    }
    return null;
  }

  validateMove(state: GameState, move: GameMove): Validation | null {
    if (state.phase === 'matchOver') return { error: 'matchOver' };
    if (!Number.isInteger(move.seat) || move.seat < 0 || move.seat >= SEAT_COUNT) {
      return { error: 'invalidSeat' };
    }
    switch (move.type) {
      case 'arrange':
        if (state.phase !== 'arranging') return { error: 'wrongPhase' };
        if (state.arrangements[move.seat] !== null) return { error: 'alreadyReady' };
        return this.validateArrangement(state, move.seat, move.arrangement);
      case 'play':
        if (state.phase !== 'playing') return { error: 'wrongPhase' };
        if (move.group !== state.groupIndex) return { error: 'wrongGroup', detail: `${move.group}` };
        if (state.turnSeat !== move.seat) return { error: 'notYourTurn' };
        return null;
      case 'next':
        if (state.phase !== 'roundOver') return { error: 'wrongPhase' };
        return null;
    }
  }

  /** Applies a move, or throws [InvalidMoveError]. */
  applyMove(state: GameState, move: GameMove): GameState {
    const check = this.validateMove(state, move);
    if (check) throw new InvalidMoveError(check.error, check.detail);

    switch (move.type) {
      case 'arrange': {
        const arrangements = [...state.arrangements];
        // Store canonical codes (e.g. "10H" not "10h").
        arrangements[move.seat] = move.arrangement.map((g) => codes(cards(g)));
        let next = bump(state, { arrangements });
        if (next.arrangements.every((a) => a !== null)) {
          next = bump(next, {
            phase: 'playing',
            groupIndex: 0,
            turnSeat: (next.dealerSeat + 1) % SEAT_COUNT,
            roundPlays: [[null, null, null, null]],
          });
        }
        return next;
      }
      case 'play': {
        const g = state.groupIndex;
        const plays = state.roundPlays.map((p) => [...p]);
        plays[g][move.seat] = state.arrangements[move.seat]![g];
        const played = plays[g].filter((p) => p !== null).length;
        if (played < SEAT_COUNT) {
          return bump(state, { roundPlays: plays, turnSeat: (move.seat + 1) % SEAT_COUNT });
        }
        const winner = resolveGroup(plays[g]);
        const winners = [...state.groupWinners, winner];
        if (g + 1 < GROUP_COUNT) {
          plays.push([null, null, null, null]);
          return bump(state, { roundPlays: plays, groupWinners: winners, groupIndex: g + 1, turnSeat: winner });
        }
        return this.finishRound(bump(state, { roundPlays: plays, groupWinners: winners, turnSeat: null }));
      }
      case 'next':
        return this.dealRound(state, (state.dealerSeat + 1) % SEAT_COUNT);
    }
  }

  private finishRound(state: GameState): GameState {
    const rr = resolveRound(state);
    const scores = state.scores.map((s, i) => s + rr.points[i]);
    let next = bump(state, { scores, phase: 'roundOver', history: [...state.history, rr] });
    const match = checkMatchResult(next);
    if (match) next = bump(next, { phase: 'matchOver', result: match });
    return next;
  }
}

export function resolveGroup(plays: (string[] | null)[]): number {
  return bestIndex(plays.map((p) => evaluate(cards(p!))));
}

interface SeatScore {
  total: number;
  swept: boolean;
}

function scoreSeat(seat: number, groupWinners: number[], bonuses: Bonus[], rules: RuleConfig): SeatScore {
  const won = groupWinners.filter((w) => w === seat).length;
  const swept = won === GROUP_COUNT;
  const groupPoints = swept
    ? rules.sweepReplacesGroupPoints
      ? rules.sweepPoints
      : won * rules.groupWinPoints + rules.sweepPoints
    : won * rules.groupWinPoints;
  const bonusPoints = bonuses.reduce((s, b) => s + b.points, 0);
  const total = rules.bonusesStackWithGroupPoints
    ? groupPoints + bonusPoints
    : Math.max(groupPoints, bonusPoints);
  return { total, swept };
}

function applyTarget(current: number, points: number, rules: RuleConfig): number {
  return rules.targetIsExact && current + points > rules.targetScore ? 0 : points;
}

export function matchWinner(scores: number[], rules: RuleConfig): number | null {
  const reached = scores
    .map((s, i) => [s, i] as const)
    .filter(([s]) => (rules.targetIsExact ? s === rules.targetScore : s >= rules.targetScore))
    .map(([, i]) => i);
  if (reached.length === 0) return null;
  const best = Math.max(...reached.map((i) => scores[i]));
  const leaders = reached.filter((i) => scores[i] === best);
  return leaders.length === 1 ? leaders[0] : null;
}

export function resolveRound(state: GameState): RoundResult {
  if (state.groupWinners.length !== GROUP_COUNT) throw new Error('Round is not complete');
  const bonuses = state.hands.map((h) =>
    detectBonuses(cards(h), state.rules).filter((b) => b.type !== 'allRanks'),
  );
  const seatScores = bonuses.map((b, i) => scoreSeat(i, state.groupWinners, b, state.rules));
  const points = seatScores.map((s, i) => applyTarget(state.scores[i], s.total, state.rules));
  const sweep = seatScores.findIndex((s) => s.swept);
  return {
    round: state.round,
    groupWinners: state.groupWinners,
    arrangements: state.arrangements,
    bonuses,
    points,
    sweepSeat: sweep < 0 ? null : sweep,
    instantWinSeat: null,
    instantWinHand: null,
  };
}

export function checkMatchResult(state: GameState): MatchResult | null {
  if (state.result) return state.result;
  const winner = matchWinner(state.scores, state.rules);
  if (winner !== null) return { winnerSeat: winner, reason: 'targetReached', finalScores: state.scores };
  if (state.round >= state.rules.maxRounds) {
    let best = 0;
    for (let i = 1; i < SEAT_COUNT; i++) if (state.scores[i] > state.scores[best]) best = i;
    return { winnerSeat: best, reason: 'maxRounds', finalScores: state.scores };
  }
  return null;
}
