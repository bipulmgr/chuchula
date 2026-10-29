// Cloud Functions for online play. Clients never write Firestore directly
// (see ../firestore.rules): every change goes through these callables,
// which run the shared rules engine inside a transaction and write each
// player only their own view.
import { initializeApp } from 'firebase-admin/app';
import { DocumentReference, Firestore, getFirestore, Transaction } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { CallableRequest, HttpsError, onCall } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { ChuchulaEngine } from './engine/engine';
import { GameState } from './engine/state';
import * as rooms from './rooms';
import { Room, RoomError, RoomUpdate } from './rooms';

initializeApp();
const REGION = process.env.FUNCTIONS_REGION || 'us-central1';
const engine = new ChuchulaEngine();
const db = (): Firestore => getFirestore();

const opts = { region: REGION, enforceAppCheck: false, maxInstances: 20 };

function requireUid(req: CallableRequest): string {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  return uid;
}

function requireString(v: unknown, field: string, max = 64): string {
  if (typeof v !== 'string' || v.length === 0 || v.length > max) {
    throw new HttpsError('invalid-argument', `${field} is required`, { reason: 'bad-request' });
  }
  return v;
}

function toHttps(e: unknown): never {
  if (e instanceof HttpsError) throw e;
  if (e instanceof RoomError) {
    const code = e.reason === 'room-not-found' ? 'not-found' : 'failed-precondition';
    throw new HttpsError(code, e.message, { reason: e.reason });
  }
  logger.error('Unexpected error', e);
  throw new HttpsError('internal', 'Unexpected server error');
}

const roomRef = (id: string) => db().collection('rooms').doc(id);
const stateRef = (id: string) => roomRef(id).collection('private').doc('state');
const viewRef = (id: string, uid: string) => roomRef(id).collection('views').doc(uid);

interface Loaded {
  ref: DocumentReference;
  room: Room;
  state: GameState | null;
}

async function load(tx: Transaction, roomId: string): Promise<Loaded> {
  const ref = roomRef(roomId);
  const [roomSnap, stateSnap] = await Promise.all([tx.get(ref), tx.get(stateRef(roomId))]);
  if (!roomSnap.exists) throw new RoomError('room-not-found');
  const raw = stateSnap.exists ? (stateSnap.get('json') as string | undefined) : undefined;
  return { ref, room: roomSnap.data() as Room, state: raw ? (JSON.parse(raw) as GameState) : null };
}

/**
 * Writes the room, the private state and every seated player's view.
 * Firestore cannot store nested arrays, so state and views are JSON text.
 */
function save(tx: Transaction, roomId: string, before: Room | null, update: RoomUpdate): void {
  if (!update.room) {
    tx.delete(roomRef(roomId));
    tx.delete(stateRef(roomId));
    for (const s of before?.seats ?? []) if (s.uid) tx.delete(viewRef(roomId, s.uid));
    return;
  }
  tx.set(roomRef(roomId), update.room);
  if (update.state) {
    tx.set(stateRef(roomId), { json: JSON.stringify(update.state), version: update.state.version });
    for (const [uid, view] of rooms.viewsFor(update.room, update.state)) {
      tx.set(viewRef(roomId, uid), { view: JSON.stringify(view), version: view.version });
    }
  }
}

async function mutate(roomId: string, fn: (l: Loaded, now: number) => RoomUpdate): Promise<void> {
  await db().runTransaction(async (tx) => {
    const loaded = await load(tx, roomId);
    save(tx, roomId, loaded.room, fn(loaded, Date.now()));
  });
}

export const createRoom = onCall(opts, async (req) => {
  const uid = requireUid(req);
  try {
    for (let attempt = 0; attempt < 8; attempt++) {
      const code = rooms.newRoomCode();
      const clash = await db().collection('rooms').where('code', '==', code).where('status', '==', 'waiting').limit(1).get();
      if (!clash.empty) continue;
      const ref = db().collection('rooms').doc();
      await ref.set(rooms.createRoom(uid, req.data?.name, code, Date.now()));
      return { roomId: ref.id, code };
    }
    throw new HttpsError('resource-exhausted', 'Could not allocate a room code');
  } catch (e) {
    toHttps(e);
  }
});

export const joinRoom = onCall(opts, async (req) => {
  const uid = requireUid(req);
  const code = requireString(req.data?.code, 'code', 12).trim().toUpperCase();
  try {
    const found = await db().collection('rooms').where('code', '==', code).where('status', 'in', ['waiting', 'playing']).limit(1).get();
    if (found.empty) throw new RoomError('room-not-found');
    const roomId = found.docs[0].id;
    await mutate(roomId, ({ room, state }, now) => ({ room: rooms.joinRoom(room, uid, req.data?.name, now), state }));
    return { roomId };
  } catch (e) {
    toHttps(e);
  }
});

export const leaveRoom = onCall(opts, async (req) => {
  const uid = requireUid(req);
  const roomId = requireString(req.data?.roomId, 'roomId');
  try {
    await mutate(roomId, ({ room, state }, now) => rooms.leaveRoom(room, state, uid, now, engine));
    return { ok: true };
  } catch (e) {
    toHttps(e);
  }
});

export const startMatch = onCall(opts, async (req) => {
  const uid = requireUid(req);
  const roomId = requireString(req.data?.roomId, 'roomId');
  try {
    await mutate(roomId, ({ room }, now) => rooms.startMatch(room, uid, now, engine, `online-${roomId}-${now}`));
    return { ok: true };
  } catch (e) {
    toHttps(e);
  }
});

export const submitMove = onCall(opts, async (req) => {
  const uid = requireUid(req);
  const roomId = requireString(req.data?.roomId, 'roomId');
  try {
    await mutate(roomId, ({ room, state }, now) => {
      if (!state) throw new RoomError('not-playing');
      return rooms.submitMove(room, state, uid, req.data?.move, now, engine);
    });
    return { ok: true };
  } catch (e) {
    toHttps(e);
  }
});

export const heartbeat = onCall(opts, async (req) => {
  const uid = requireUid(req);
  const roomId = requireString(req.data?.roomId, 'roomId');
  try {
    await mutate(roomId, ({ room, state }, now) => rooms.heartbeat(room, state, uid, now, engine));
    return { ok: true };
  } catch (e) {
    toHttps(e);
  }
});

/**
 * Housekeeping: hands silent players to bots in rooms where nobody is left
 * to send heartbeats, and deletes old rooms.
 */
export const cleanupRooms = onSchedule({ schedule: 'every 10 minutes', region: REGION }, async () => {
  const now = Date.now();
  const stale = await db().collection('rooms').where('updatedAt', '<', now - 2 * 60 * 60 * 1000).limit(200).get();
  for (const doc of stale.docs) {
    await db().recursiveDelete(doc.ref);
  }
  const playing = await db().collection('rooms').where('status', '==', 'playing').limit(200).get();
  for (const doc of playing.docs) {
    try {
      await mutate(doc.id, ({ room, state }, t) => rooms.markAway(room, state, t, engine));
    } catch (e) {
      logger.warn('cleanup failed for room', doc.id, e);
    }
  }
  logger.info(`cleanup: deleted ${stale.size}, checked ${playing.size}`);
});
