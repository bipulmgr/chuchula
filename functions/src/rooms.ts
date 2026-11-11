// Room lifecycle and move handling as pure functions over plain data, so
// the logic is unit-tested without Firestore. src/index.ts wraps each in a
// Firestore transaction.
import { randomInt } from 'node:crypto';
import { botMove } from './engine/bot';
import { ChuchulaEngine, InvalidMoveError } from './engine/engine';
import { GameState, PlayerView, SEAT_COUNT, parseMove, playerView } from './engine/state';

export type RoomStatus = 'waiting' | 'playing' | 'finished' | 'abandoned';

export interface RoomSeat {
  uid: string | null;
  name: string;
  avatar: number;
  isBot: boolean;
  /** A human seat a bot is playing for after a disconnect. */
  away: boolean;
  lastSeen: number;
}

export interface Room {
  code: string;
  hostUid: string;
  status: RoomStatus;
  seats: RoomSeat[];
  createdAt: number;
  updatedAt: number;
  /** When the open show window started (server time), or null. */
  showOpenedAt?: number | null;
}

/** Reasons sent to the client in HttpsError details. */
export type RoomReason =
  | 'room-not-found'
  | 'room-full'
  | 'not-in-room'
  | 'not-host'
  | 'already-started'
  | 'not-playing'
  | 'bad-request';

export class RoomError extends Error {
  constructor(readonly reason: RoomReason | InvalidMoveError['error'], message?: string) {
    super(message ?? reason);
  }
}

/** Client and server clocks differ; a close this early is still accepted. */
export const SHOW_CLOCK_SLACK_MS = 1500;

/** A player is replaced by a bot after this long without a heartbeat. */
export const AWAY_AFTER_MS = 60_000;

const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no I, O, 0, 1
export const BOT_NAMES = [
  'Aarav', 'Sita', 'Pemba', 'Hari', 'Gita', 'Bikash', 'Sarita', 'Dawa', 'Kiran', 'Laxmi', 'Nabin', 'Puja',
  'Ramesh', 'Anita', 'Tenzing', 'Sunita', 'Bishal', 'Asmita', 'Prakash', 'Kamala', 'Suman', 'Nima', 'Rojina', 'Dipesh',
];

/** [count] different bot names in random order. */
export function randomBotNames(count: number): string[] {
  const pool = [...BOT_NAMES];
  for (let i = pool.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [pool[i], pool[j]] = [pool[j], pool[i]];
  }
  return pool.slice(0, count);
}

export function newRoomCode(): string {
  let code = '';
  for (let i = 0; i < 6; i++) code += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
  return code;
}

export function cleanName(raw: unknown): string {
  const s = typeof raw === 'string' ? raw : '';
  // Strip control characters and limit length (names are shown to others).
  const cleaned = s.replace(/[\u0000-\u001f\u007f]/g, '').trim().slice(0, 20);
  return cleaned || 'Player';
}

const emptySeat = (): RoomSeat => ({
  uid: null, name: '', avatar: 0, isBot: false, away: false, lastSeen: 0,
});

export function seatOf(room: Room, uid: string): number {
  return room.seats.findIndex((s) => s.uid === uid);
}

export function createRoom(uid: string, name: unknown, code: string, now: number): Room {
  const seats = Array.from({ length: SEAT_COUNT }, emptySeat);
  seats[0] = { uid, name: cleanName(name), avatar: 0, isBot: false, away: false, lastSeen: now };
  return { code, hostUid: uid, status: 'waiting', seats, createdAt: now, updatedAt: now };
}

export function joinRoom(room: Room, uid: string, name: unknown, now: number): Room {
  const existing = seatOf(room, uid);
  if (existing >= 0) {
    // Rejoining (e.g. after a restart) keeps the seat and takes it back
    // from the bot.
    return touchSeat(room, existing, now);
  }
  if (room.status !== 'waiting') throw new RoomError('already-started');
  const free = room.seats.findIndex((s) => s.uid === null && !s.isBot);
  if (free < 0) throw new RoomError('room-full');
  const seats = [...room.seats];
  seats[free] = { uid, name: cleanName(name), avatar: free, isBot: false, away: false, lastSeen: now };
  return { ...room, seats, updatedAt: now };
}

function touchSeat(room: Room, seat: number, now: number): Room {
  const seats = [...room.seats];
  seats[seat] = { ...seats[seat], lastSeen: now, away: false };
  return { ...room, seats, updatedAt: now };
}

export interface RoomUpdate {
  room: Room | null; // null: delete the room
  state: GameState | null;
}

export function leaveRoom(room: Room, state: GameState | null, uid: string, now: number, engine: ChuchulaEngine): RoomUpdate {
  const seat = seatOf(room, uid);
  if (seat < 0) return { room, state };
  if (room.status === 'waiting') {
    const seats = [...room.seats];
    seats[seat] = emptySeat();
    const humans = seats.filter((s) => s.uid !== null);
    if (humans.length === 0) return { room: null, state: null };
    const hostUid = room.hostUid === uid ? humans[0].uid! : room.hostUid;
    return { room: { ...room, seats, hostUid, updatedAt: now }, state };
  }
  // During a match the seat is handed to a bot for good.
  const seats = [...room.seats];
  seats[seat] = { ...seats[seat], uid: null, isBot: true, away: false };
  let next = { ...room, seats, updatedAt: now };
  const humansLeft = seats.some((s) => s.uid !== null);
  if (!humansLeft && room.status === 'playing') next = { ...next, status: 'abandoned' };
  const newState = state && room.status === 'playing' ? runBots(next, state, engine) : state;
  return { room: withStatus(next, newState, now), state: newState };
}

export function startMatch(room: Room, uid: string, now: number, engine: ChuchulaEngine, matchId: string): RoomUpdate {
  if (room.hostUid !== uid) throw new RoomError('not-host');
  if (room.status !== 'waiting') throw new RoomError('already-started');
  const botNames = randomBotNames(4);
  let bot = 0;
  const seats = room.seats.map((s, i): RoomSeat =>
    s.uid !== null
      ? s
      : { uid: null, name: botNames[bot++], avatar: i, isBot: true, away: false, lastSeen: 0 },
  );
  const state = engine.startGame({
    matchId,
    seats: seats.map((s, i) => ({
      id: s.uid ?? `bot-${i}`,
      name: s.name,
      isBot: s.isBot,
      avatar: s.avatar,
    })),
  });
  const playing: Room = { ...room, seats, status: 'playing', updatedAt: now };
  const after = runBots(playing, state, engine);
  return { room: withStatus(playing, after, now), state: after };
}

/** Seats the server plays for: bots and players who are away. */
export function botSeats(room: Room): number[] {
  return room.seats.flatMap((s, i) => (s.isBot || s.away ? [i] : []));
}

/** Lets bots act until a human must move. */
export function runBots(room: Room, state: GameState, engine: ChuchulaEngine): GameState {
  const seats = botSeats(room);
  let s = state;
  for (let guard = 0; guard < 500; guard++) {
    let moved = false;
    for (const seat of seats) {
      // The bot sees only its own seat's view.
      const move = botMove(playerView(s, seat));
      if (move) {
        s = engine.applyMove(s, move);
        moved = true;
      }
    }
    if (!moved) break;
  }
  return s;
}

function withStatus(room: Room, state: GameState | null, now: number): Room {
  // Starts the show clock when a show window opens, and clears it after.
  const showing = state?.phase === 'showing';
  let r = room;
  if (showing && r.showOpenedAt == null) r = { ...r, showOpenedAt: now };
  if (!showing && r.showOpenedAt != null) r = { ...r, showOpenedAt: null };
  if (state?.phase === 'matchOver' && r.status === 'playing') return { ...r, status: 'finished' };
  return r;
}

export function submitMove(room: Room, state: GameState, uid: string, rawMove: unknown, now: number, engine: ChuchulaEngine): RoomUpdate {
  const seat = seatOf(room, uid);
  if (seat < 0) throw new RoomError('not-in-room');
  if (room.status !== 'playing') throw new RoomError('not-playing');
  let move;
  try {
    move = parseMove(rawMove);
  } catch (e) {
    throw new RoomError('bad-request', (e as Error).message);
  }
  // A client can only move for its own seat.
  if (move.seat !== seat) throw new RoomError('invalidSeat');
  const touched = touchSeat(room, seat, now);
  // "Next round" is idempotent: several players may press it.
  if (move.type === 'next' && state.phase !== 'roundOver') return { room: touched, state };
  // Closing a show window is idempotent too, and only allowed once its time
  // is up by the server's clock (clients send it when their countdown ends).
  if (move.type === 'closeShow') {
    if (state.phase !== 'showing') return { room: touched, state };
    const opened = room.showOpenedAt ?? now;
    if (now - opened < state.rules.showWindowSeconds * 1000 - SHOW_CLOCK_SLACK_MS) {
      throw new RoomError('showStillOpen');
    }
  }
  let next: GameState;
  try {
    next = engine.applyMove(state, move);
  } catch (e) {
    if (e instanceof InvalidMoveError) throw new RoomError(e.error, e.detail);
    throw e;
  }
  next = runBots(touched, next, engine);
  return { room: withStatus(touched, next, now), state: next };
}

/**
 * Records a heartbeat and hands any long-silent players' seats to bots so
 * the table keeps moving. A returning player takes the seat back.
 */
export function heartbeat(room: Room, state: GameState | null, uid: string, now: number, engine: ChuchulaEngine): RoomUpdate {
  const seat = seatOf(room, uid);
  if (seat < 0) throw new RoomError('not-in-room');
  return markAway({ ...touchSeat(room, seat, now) }, state, now, engine);
}

export function markAway(room: Room, state: GameState | null, now: number, engine: ChuchulaEngine): RoomUpdate {
  if (room.status !== 'playing' || !state) return { room, state };
  let changed = false;
  const seats = room.seats.map((s) => {
    if (s.uid !== null && !s.away && now - s.lastSeen > AWAY_AFTER_MS) {
      changed = true;
      return { ...s, away: true };
    }
    return s;
  });
  if (!changed) return { room, state };
  const next = { ...room, seats, updatedAt: now };
  const after = runBots(next, state, engine);
  return { room: withStatus(next, after, now), state: after };
}

/** One view per seated human, keyed by uid. */
export function viewsFor(room: Room, state: GameState): Map<string, PlayerView> {
  const views = new Map<string, PlayerView>();
  room.seats.forEach((s, i) => {
    if (s.uid) views.set(s.uid, playerView(state, i));
  });
  return views;
}
