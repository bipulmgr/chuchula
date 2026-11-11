// The Chuchula rules engine, a line-by-line port of
// lib/game/engine/game_engine.dart and lib/game/scoring/round_scorer.dart.
// test/parity checks both engines produce identical JSON for the same
// decks and moves.
import { randomInt } from 'node:crypto';
import {
  Card, cardCode, cardId, compareCards, fromId, parseCard,
} from './card';
import { bestIndex, evaluate, fourCardIsWeakest, fourCardWeakestArrangement, playOrder } from './evaluator';
import {
  Bonus, BonusType, RuleConfig, STANDARD_RULES, bestShow, compareShowRanks, detectBonuses, hasAllRanks, showRank,
} from './rules';
import {
  GROUP_COUNT, GROUP_SIZES, GameMove, GameState, MatchResult, RoundResult,
  RuleError, SEAT_COUNT, SHOW_PASS, SeatInfo,
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
      shows: [null, null, null, null],
      showOpener: null,
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
      if (s.rules.allRanksInstantWin && !s.rules.declareBonuses) {
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
      if (instant.length === 1) return this.instantWin(dealt, instant[0]);
      return dealt;
    }
    throw new Error('Could not produce a valid deal');
  }

  /** Ends the match: [seat] holds one card of every rank. */
  private instantWin(s: GameState, seat: number): GameState {
    const rr: RoundResult = {
      round: s.round,
      groupWinners: [],
      arrangements: [null, null, null, null],
      bonuses: [0, 1, 2, 3].map((i) => (i === seat ? [{ type: 'allRanks', points: 0 }] : [])),
      points: [0, 0, 0, 0],
      sweepSeat: null,
      instantWinSeat: seat,
      instantWinHand: s.hands[seat],
      shownSeat: null,
      shownKinds: [null, null, null, null],
      shownHands: [null, null, null, null],
      doubleRunSeat: null,
    };
    return bump(s, {
      phase: 'matchOver',
      turnSeat: null,
      history: [...s.history, rr],
      result: { winnerSeat: seat, reason: 'instantWin', finalScores: s.scores },
    });
  }

  /**
   * [seat] shows the special [kind]. During arranging this opens the show
   * window for the other players; in the window it is [seat]'s answer. All
   * thirteen ranks wins the match at once.
   */
  private show(s: GameState, seat: number, kind: BonusType): GameState {
    if (kind === 'allRanks') return this.instantWin(s, seat);
    const shows = [...s.shows];
    shows[seat] = kind;
    if (s.phase === 'arranging') {
      const opened = bump(s, { phase: 'showing', turnSeat: null, shows, showOpener: seat });
      if (s.rules.showWindowSeconds <= 0) return this.resolveShows(opened);
      return opened;
    }
    return this.afterAnswer(bump(s, { shows }));
  }

  private afterAnswer(s: GameState): GameState {
    return s.shows.every((x) => x !== null) ? this.resolveShows(s) : s;
  }

  /** Ends the show window: the best special shown wins the round (ties go to the earliest from the opener). */
  private resolveShows(s: GameState): GameState {
    const opener = s.showOpener ?? 0;
    const kinds = s.shows.map((x) => (x === null || x === SHOW_PASS ? null : (x as BonusType)));
    let winner = -1;
    let best: number[] | null = null;
    for (let k = 0; k < SEAT_COUNT; k++) {
      const seat = (opener + k) % SEAT_COUNT;
      const kind = kinds[seat];
      if (kind === null) continue;
      const rank = showRank(cards(s.hands[seat]), kind);
      if (best === null || compareShowRanks(rank, best) > 0) {
        best = rank;
        winner = seat;
      }
    }
    const w = winner;
    const bonuses = detectBonuses(cards(s.hands[w]), s.rules).filter((b) => b.type === kinds[w]);
    const total = bonuses.reduce((t, b) => t + b.points, 0);
    const points = [0, 1, 2, 3].map((i) => (i === w ? applyTarget(s.scores[i], total, s.rules) : 0));
    const rr: RoundResult = {
      round: s.round,
      groupWinners: [],
      arrangements: [null, null, null, null],
      bonuses: [0, 1, 2, 3].map((i) => (i === w ? bonuses : [])),
      points,
      sweepSeat: null,
      instantWinSeat: null,
      instantWinHand: s.hands[w],
      shownSeat: w,
      shownKinds: kinds,
      shownHands: kinds.map((k, i) => (k === null ? null : s.hands[i])),
      doubleRunSeat: null,
    };
    let next = bump(s, {
      scores: s.scores.map((x, i) => x + points[i]),
      phase: 'roundOver',
      turnSeat: null,
      history: [...s.history, rr],
      shows: [null, null, null, null],
      showOpener: null,
    });
    const match = checkMatchResult(next);
    if (match) next = bump(next, { phase: 'matchOver', result: match });
    return next;
  }

  validateArrangement(state: GameState, seat: number, groups: string[][]): Validation | null {
    if (seat < 0 || seat >= SEAT_COUNT) return { error: 'invalidSeat' };
    if (groups.length !== GROUP_COUNT) return { error: 'wrongGroupCount', detail: `${groups.length}` };
    // One group of 4 and three of 3, in any position.
    const sizes = groups.map((g) => (Array.isArray(g) ? g.length : -1)).sort((a, b) => a - b);
    if (sizes.join(',') !== GROUP_SIZES.join(',')) {
      return { error: 'wrongGroupSize', detail: sizes.join('-') };
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
    // The 4-card group is played last and must be the weakest, unless no
    // arrangement of this hand allows that.
    if (state.rules.fourCardWeakest) {
      const parsed = groups.map((g) => g.map(parseCard));
      if (!fourCardIsWeakest(parsed) && fourCardWeakestArrangement(cards(state.hands[seat])) !== null) {
        return { error: 'fourCardTooStrong' };
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
      case 'show':
        if (state.phase !== 'arranging' && state.phase !== 'showing') return { error: 'wrongPhase' };
        if (state.phase === 'showing' && state.shows[move.seat] !== null) return { error: 'alreadyAnswered' };
        if (!showable(state, move.seat).some((b) => !move.bonus || b.type === move.bonus)) {
          return { error: 'nothingToShow' };
        }
        return null;
      case 'passShow':
        if (state.phase !== 'showing') return { error: 'wrongPhase' };
        if (state.shows[move.seat] !== null) return { error: 'alreadyAnswered' };
        return null;
      case 'closeShow':
        if (state.phase !== 'showing') return { error: 'wrongPhase' };
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
        // Store canonical codes (e.g. "10H" not "10h"). Groups are played
        // strongest first, whatever order the player left them in.
        const groups = move.arrangement.map((g) => cards(g));
        arrangements[move.seat] = (state.rules.strongestFirst ? playOrder(groups) : groups)
          .map(codes);
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
      case 'show':
        return this.show(state, move.seat, move.bonus ?? bestShow(showable(state, move.seat))!);
      case 'passShow': {
        const shows = [...state.shows];
        shows[move.seat] = SHOW_PASS;
        return this.afterAnswer(bump(state, { shows }));
      }
      case 'closeShow':
        return this.resolveShows(state);
      case 'next':
        return this.dealRound(state, (state.dealerSeat + 1) % SEAT_COUNT);
    }
  }

  private finishRound(state: GameState): GameState {
    const doubleRun = lastGroupDoubleRun(state);
    const rr = { ...resolveRound(state), doubleRunSeat: doubleRun };
    const scores = state.scores.map((s, i) => s + rr.points[i]);
    let next = bump(state, { scores, phase: 'roundOver', history: [...state.history, rr] });
    if (doubleRun !== null) {
      // A double run in the last group wins the whole match.
      return bump(next, {
        phase: 'matchOver',
        result: { winnerSeat: doubleRun, reason: 'doubleRun', finalScores: scores },
      });
    }
    const match = checkMatchResult(next);
    if (match) next = bump(next, { phase: 'matchOver', result: match });
    return next;
  }
}

/** Seat whose last group is a double run (the strongest, if several), or null. */
export function lastGroupDoubleRun(state: GameState): number | null {
  if (!state.rules.lastGroupDoubleRunWins || state.roundPlays.length !== GROUP_COUNT) return null;
  const plays = state.roundPlays[GROUP_COUNT - 1];
  if (plays.some((p) => p === null)) return null;
  let seat: number | null = null;
  let best = -1;
  plays.forEach((p, i) => {
    const v = evaluate(cards(p!));
    if (v.category === 'pureSequence' && v.strength > best) {
      best = v.strength;
      seat = i;
    }
  });
  return seat;
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
  // With declared bonuses, only a shown hand scores them.
  const bonuses = state.hands.map((h) =>
    state.rules.declareBonuses
      ? []
      : detectBonuses(cards(h), state.rules).filter((b) => b.type !== 'allRanks'),
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
    shownSeat: null,
    shownKinds: [null, null, null, null],
    shownHands: [null, null, null, null],
    doubleRunSeat: null,
  };
}

/**
 * Special hands [seat] could show now: during arranging, or while another
 * player's show is open and [seat] has not answered.
 */
export function showable(s: GameState, seat: number): Bonus[] {
  const open = s.phase === 'arranging' || (s.phase === 'showing' && s.shows[seat] === null);
  return s.rules.declareBonuses && open ? detectBonuses(cards(s.hands[seat]), s.rules) : [];
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
