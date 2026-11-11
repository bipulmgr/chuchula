import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { arrangeHand, botMove } from '../engine/bot';
import { ChuchulaEngine } from '../engine/engine';
import { GameState, playerView } from '../engine/state';
import * as rooms from '../rooms';
import { Room, RoomError } from '../rooms';

const engine = new ChuchulaEngine();
const reason = (r: string) => (e: unknown) => e instanceof RoomError && e.reason === r;

function lobby(): Room {
  let room = rooms.createRoom('host', 'Bipul', 'ABC234', 1000);
  room = rooms.joinRoom(room, 'maya', 'Maya', 1001);
  return room;
}

/** Plays every human seat with the bot strategy until the match ends. */
function playOut(room: Room, state: GameState): { room: Room; state: GameState } {
  let r = room;
  let s = state;
  for (let guard = 0; guard < 3000 && s.phase !== 'matchOver'; guard++) {
    let moved = false;
    for (const seat of r.seats) {
      if (!seat.uid || seat.away) continue;
      const i = rooms.seatOf(r, seat.uid);
      const view = playerView(s, i);
      const move = view.phase === 'roundOver' ? { type: 'next' as const, seat: i } : botMove(view);
      if (!move) continue;
      const u = rooms.submitMove(r, s, seat.uid, move, 2000 + guard, engine);
      r = u.room!;
      s = u.state!;
      moved = true;
    }
    assert.ok(moved, `stuck in ${s.phase}`);
  }
  return { room: r, state: s };
}

describe('rooms', () => {
  it('creates and joins with clean names', () => {
    const room = rooms.joinRoom(lobby(), 'x', '  \u0007Evil\nName that is far too long  ', 5);
    assert.equal(room.seats[1].name, 'Maya');
    assert.equal(room.seats[2].name, 'EvilName that is far');
    assert.equal(rooms.joinRoom(room, 'maya', 'Maya', 9).seats.filter((s) => s.uid === 'maya').length, 1);
  });

  it('bots get different random names', () => {
    const names = rooms.randomBotNames(4);
    assert.equal(new Set(names).size, 4);
    const seen = new Set<string>();
    for (let i = 0; i < 10; i++) for (const n of rooms.randomBotNames(2)) seen.add(n);
    assert.ok(seen.size > 4);
  });

  it('room codes avoid look-alike characters', () => {
    for (let i = 0; i < 200; i++) assert.match(rooms.newRoomCode(), /^[A-HJ-NP-Z2-9]{6}$/);
  });

  it('refuses a fifth player and joins after the start', () => {
    let room = lobby();
    room = rooms.joinRoom(room, 'c', 'C', 2);
    room = rooms.joinRoom(room, 'd', 'D', 3);
    assert.throws(() => rooms.joinRoom(room, 'e', 'E', 4), reason('room-full'));
    const started = rooms.startMatch(lobby(), 'host', 5, engine, 'm').room!;
    assert.throws(() => rooms.joinRoom(started, 'late', 'Late', 6), reason('already-started'));
  });

  it('only the host starts; empty seats become bots', () => {
    assert.throws(() => rooms.startMatch(lobby(), 'maya', 5, engine, 'm'), reason('not-host'));
    const { room, state } = rooms.startMatch(lobby(), 'host', 5, engine, 'm');
    assert.equal(room!.status, 'playing');
    assert.deepEqual(room!.seats.map((s) => s.isBot), [false, false, true, true]);
    // Bots acted straight away (arranged, or showed a special hand and
    // ended the round); humans still need to arrange.
    if (state!.phase === 'arranging') {
      assert.deepEqual(state!.arrangements.map((a) => a !== null), [false, false, true, true]);
    } else if (state!.phase === 'showing') {
      // A bot showed a special hand; the humans have the window to answer.
      assert.ok([2, 3].includes(state!.showOpener!));
      assert.equal(room!.showOpenedAt, 5);
    } else {
      assert.ok([2, 3].includes(state!.history.at(-1)!.shownSeat!));
    }
  });

  it('a show window closes only once its time is up', () => {
    const { room, state } = rooms.startMatch(lobby(), 'host', 5, engine, 'm');
    // Seat 0 holds four nines; seat 1 must answer.
    const used = new Set(['9S', '9H', '9D', '9C']);
    const rest = state!.hands.flat().filter((c) => !used.has(c));
    const hands = [['9S', '9H', '9D', '9C', ...rest.slice(0, 9)], ...[0, 1, 2].map((i) => rest.slice(9 + i * 13, 22 + i * 13))];
    const arranging = { ...state!, phase: 'arranging' as const, hands, arrangements: [null, null, null, null], shows: [null, null, null, null], showOpener: null };
    const opened = rooms.submitMove({ ...room!, showOpenedAt: null }, arranging, 'host', { type: 'show', seat: 0, bonus: 'fourOfAKind' }, 1000, engine);
    assert.equal(opened.state!.phase, 'showing');
    assert.equal(opened.room!.showOpenedAt, 1000);
    const close = { type: 'closeShow', seat: 1 };
    assert.throws(() => rooms.submitMove(opened.room!, opened.state!, 'maya', close, 5000, engine), reason('showStillOpen'));
    const closed = rooms.submitMove(opened.room!, opened.state!, 'maya', close, 21_000, engine);
    assert.equal(closed.state!.phase === 'roundOver' || closed.state!.phase === 'matchOver', true);
    assert.equal(closed.room!.showOpenedAt, null);
  });

  it('a seat can only move for itself', () => {
    const { room, state } = rooms.startMatch(lobby(), 'host', 5, engine, 'm');
    // Built directly: a bot may already have ended the round by showing a
    // special hand, so botMove could have nothing to do.
    const move = { type: 'arrange' as const, seat: 0, arrangement: arrangeHand(state!.hands[0]) };
    assert.throws(() => rooms.submitMove(room!, state!, 'maya', move, 6, engine), reason('invalidSeat'));
    assert.throws(() => rooms.submitMove(room!, state!, 'stranger', move, 6, engine), reason('not-in-room'));
    assert.throws(() => rooms.submitMove(room!, state!, 'host', { type: 'x' }, 6, engine), reason('bad-request'));
    assert.throws(
      () => rooms.submitMove(room!, state!, 'host', { type: 'play', seat: 0, group: 0 }, 6, engine),
      reason('wrongPhase'),
    );
  });

  it('views go only to their own player', () => {
    const { room, state } = rooms.startMatch(lobby(), 'host', 5, engine, 'm');
    const views = rooms.viewsFor(room!, state!);
    assert.deepEqual([...views.keys()].sort(), ['host', 'maya']);
    const hostText = JSON.stringify(views.get('host'));
    for (const c of state!.hands[1]) assert.ok(!hostText.includes(`"${c}"`));
  });

  it('plays a full online match to the end', () => {
    const started = rooms.startMatch(lobby(), 'host', 5, engine, 'm');
    const { room, state } = playOut(started.room!, started.state!);
    assert.equal(state.phase, 'matchOver');
    assert.equal(room.status, 'finished');
  });

  it('"next round" twice is harmless', () => {
    const started = rooms.startMatch(lobby(), 'host', 5, engine, 'm');
    let r = started.room!;
    let s = started.state!;
    while (s.phase !== 'roundOver' && s.phase !== 'matchOver') {
      for (const uid of ['host', 'maya']) {
        const m = botMove(playerView(s, rooms.seatOf(r, uid)));
        if (m) ({ room: r, state: s } = rooms.submitMove(r, s, uid, m, 7, engine) as { room: Room; state: GameState });
      }
    }
    if (s.phase === 'matchOver') return;
    const round = s.round;
    ({ room: r, state: s } = rooms.submitMove(r, s, 'host', { type: 'next', seat: 0 }, 8, engine) as { room: Room; state: GameState });
    // A bot may show a special hand at once, ending the new round; then a
    // second "next" is legitimately valid, so there is nothing to check.
    if (s.phase !== 'arranging') return;
    ({ room: r, state: s } = rooms.submitMove(r, s, 'maya', { type: 'next', seat: 1 }, 9, engine) as { room: Room; state: GameState });
    assert.equal(s.round, round + 1);
  });

  it('silent players are handed to a bot and can come back', () => {
    const started = rooms.startMatch(lobby(), 'host', 1000, engine, 'm');
    const later = 1001 + rooms.AWAY_AFTER_MS + 10;
    // The host keeps beating; Maya went quiet.
    const beat = rooms.heartbeat(started.room!, started.state!, 'host', later, engine);
    assert.equal(beat.room!.seats[1].away, true);
    // The bot arranged for her, or a bot showed a special hand and ended the round.
    const acted = beat.state!.arrangements[1] !== null || beat.state!.phase !== 'arranging';
    assert.equal(acted, true, 'bot acted for Maya');
    const back = rooms.heartbeat(beat.room!, beat.state!, 'maya', later + 5, engine);
    assert.equal(back.room!.seats[1].away, false);
  });

  it('leaving a lobby frees the seat and moves the host; empty rooms are deleted', () => {
    const left = rooms.leaveRoom(lobby(), null, 'host', 5, engine);
    assert.equal(left.room!.hostUid, 'maya');
    assert.equal(left.room!.seats[0].uid, null);
    assert.equal(rooms.leaveRoom(left.room!, null, 'maya', 6, engine).room, null);
  });

  it('leaving mid-match hands the seat to a bot and the match goes on', () => {
    const started = rooms.startMatch(lobby(), 'host', 5, engine, 'm');
    const left = rooms.leaveRoom(started.room!, started.state!, 'maya', 6, engine);
    assert.equal(left.room!.seats[1].isBot, true);
    assert.equal(left.state!.arrangements[1] !== null || left.state!.phase !== 'arranging', true);
    const { state } = playOut(left.room!, left.state!);
    assert.equal(state.phase, 'matchOver');
  });
});
