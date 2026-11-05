// End to end: real callables in the Functions emulator, Firestore and Auth
// emulators, two anonymous players. Run with `npm run test:e2e`.
import assert from 'node:assert/strict';
import { after, describe, it } from 'node:test';
import { FirebaseApp, deleteApp, initializeApp } from 'firebase/app';
import { connectAuthEmulator, getAuth, signInAnonymously } from 'firebase/auth';
import { connectFirestoreEmulator, doc, getDoc, getFirestore } from 'firebase/firestore';
import { connectFunctionsEmulator, getFunctions, httpsCallable } from 'firebase/functions';
import { botMove } from '../engine/bot';
import { PlayerView } from '../engine/state';

const apps: FirebaseApp[] = [];

async function player(name: string) {
  const app = initializeApp({ projectId: 'demo-chuchula', apiKey: 'demo-key' }, name);
  apps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
  const db = getFirestore(app);
  connectFirestoreEmulator(db, '127.0.0.1', 8080);
  const fns = getFunctions(app, 'us-central1');
  connectFunctionsEmulator(fns, '127.0.0.1', 5001);
  const user = (await signInAnonymously(auth)).user;
  const call = async (fn: string, data: object) => (await httpsCallable(fns, fn)(data)).data as any;
  const view = async (roomId: string): Promise<PlayerView | null> => {
    const s = await getDoc(doc(db, `rooms/${roomId}/views/${user.uid}`));
    return s.exists() ? (JSON.parse(s.get('view')) as PlayerView) : null;
  };
  return { uid: user.uid, db, call, view };
}

after(async () => {
  for (const a of apps) await deleteApp(a);
});

describe('online play through Cloud Functions', () => {
  it('two players and two bots finish a match', { timeout: 240_000 }, async () => {
    const host = await player('host');
    const guest = await player('guest');
    const { roomId, code } = await host.call('createRoom', { name: 'Host' });
    assert.match(code, /^[A-Z2-9]{6}$/);
    assert.equal((await guest.call('joinRoom', { code: code.toLowerCase(), name: 'Guest' })).roomId, roomId);

    await assert.rejects(guest.call('startMatch', { roomId }), (e: any) => e.details?.reason === 'not-host');
    await assert.rejects(guest.call('joinRoom', { code: 'ZZZZZZ', name: 'x' }), (e: any) => e.details?.reason === 'room-not-found');
    await host.call('startMatch', { roomId });

    // Moves are checked by the engine on the server.
    const first = (await host.view(roomId))!;
    await assert.rejects(
      host.call('submitMove', { roomId, move: { type: 'play', seat: first.mySeat, group: 0 } }),
      (e: any) => e.details?.reason === 'wrongPhase',
    );
    await assert.rejects(
      host.call('submitMove', { roomId, move: { type: 'play', seat: 1, group: 0 } }),
      (e: any) => e.details?.reason === 'invalidSeat',
    );

    // Clients cannot read the private state, even directly.
    await assert.rejects(getDoc(doc(host.db, `rooms/${roomId}/private/state`)));

    let rounds = 0;
    for (let guard = 0; guard < 400; guard++) {
      const views = [await host.view(roomId), await guest.view(roomId)];
      const v = views[0]!;
      if (v.phase === 'matchOver') break;
      // Each player's view has their own 13 cards only.
      assert.equal(views[0]!.myHand.length, 13);
      assert.notDeepEqual(views[0]!.myHand, views[1]!.myHand);
      let acted = false;
      for (const [p, pv] of [[host, views[0]!], [guest, views[1]!]] as const) {
        const move = pv.phase === 'roundOver' ? { type: 'next', seat: pv.mySeat } : botMove(pv);
        if (!move) continue;
        if (move.type === 'next') rounds++;
        await p.call('submitMove', { roomId, move });
        acted = true;
        break;
      }
      assert.ok(acted, `nobody could act in ${v.phase}`);
      if (guard % 10 === 0) await host.call('heartbeat', { roomId });
    }
    const final = (await host.view(roomId))!;
    assert.equal(final.phase, 'matchOver');
    assert.ok(final.result);
    const room = await getDoc(doc(host.db, `rooms/${roomId}`));
    assert.equal(room.get('status'), 'finished');
    console.log(`match finished after ${rounds + 1} rounds, scores ${final.scores.join('/')}`);

    // The finished room takes no more moves.
    await assert.rejects(
      host.call('submitMove', { roomId, move: { type: 'play', seat: final.mySeat, group: 0 } }),
      (e: any) => e.details?.reason === 'not-playing',
    );
  });

  it('four players fill the room; a leaver is replaced by a bot; a rejoin keeps the seat', { timeout: 240_000 }, async () => {
    const ps = [await player('p0'), await player('p1'), await player('p2'), await player('p3')];
    const { roomId, code } = await ps[0].call('createRoom', { name: 'P0' });
    for (let i = 1; i < 4; i++) await ps[i].call('joinRoom', { code, name: `P${i}` });
    const extra = await player('p4');
    await assert.rejects(extra.call('joinRoom', { code, name: 'Late' }), (e: any) => e.details?.reason === 'room-full');
    await ps[0].call('startMatch', { roomId });

    const roomDoc = async () => (await getDoc(doc(ps[0].db, `rooms/${roomId}`))).data() as any;
    assert.equal((await roomDoc()).seats.filter((s: any) => s.isBot).length, 0);

    // A player restarting the app joins with the same code and keeps the seat.
    const before = (await ps[2].view(roomId))!;
    assert.equal((await ps[2].call('joinRoom', { code, name: 'P2' })).roomId, roomId);
    assert.equal((await ps[2].view(roomId))!.mySeat, before.mySeat);
    // Nobody new can take a seat once the match has started.
    await assert.rejects(extra.call('joinRoom', { code, name: 'Late' }), (e: any) => e.details?.reason === 'already-started');

    // Player 3 leaves for good: a bot plays the seat from now on.
    await ps[3].call('leaveRoom', { roomId });
    assert.equal((await roomDoc()).seats.filter((s: any) => s.isBot).length, 1);

    const live = ps.slice(0, 3);
    for (let guard = 0; guard < 600; guard++) {
      const views = await Promise.all(live.map((p) => p.view(roomId)));
      if (views[0]!.phase === 'matchOver') break;
      let acted = false;
      for (let i = 0; i < live.length; i++) {
        const pv = views[i]!;
        const move = pv.phase === 'roundOver' ? { type: 'next', seat: pv.mySeat } : botMove(pv);
        if (!move) continue;
        await live[i].call('submitMove', { roomId, move });
        acted = true;
        break;
      }
      assert.ok(acted, `nobody could act in ${views[0]!.phase}`);
    }
    assert.equal((await ps[0].view(roomId))!.phase, 'matchOver');
    assert.equal((await roomDoc()).status, 'finished');
  });
});
