// Security rules: clients may read the lobby and their own view only, and
// may never write. Runs against the Firestore emulator (npm run test:rules).
import { RulesTestEnvironment, assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import 'firebase/compat/firestore'; // registers the SDK the test contexts use
import { deleteDoc, doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { after, before, describe, it } from 'node:test';

let env: RulesTestEnvironment;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-chuchula',
    firestore: { rules: fs.readFileSync(path.join(__dirname, '..', '..', '..', 'firestore.rules'), 'utf8') },
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'rooms/r1'), { code: 'ABC234', hostUid: 'alice', status: 'playing' });
    await setDoc(doc(db, 'rooms/r1/private/state'), { json: '{"hands":[["AS"]]}' });
    await setDoc(doc(db, 'rooms/r1/views/alice'), { view: '{}' });
    await setDoc(doc(db, 'rooms/r1/views/bob'), { view: '{}' });
  });
});

after(async () => {
  await env?.cleanup();
});

describe('firestore rules', () => {
  it('signed-in players can read the lobby, strangers cannot', async () => {
    await assertSucceeds(getDoc(doc(env.authenticatedContext('bob').firestore(), 'rooms/r1')));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'rooms/r1')));
  });

  it('nobody can read the private game state', async () => {
    await assertFails(getDoc(doc(env.authenticatedContext('alice').firestore(), 'rooms/r1/private/state')));
  });

  it('a player reads only their own view', async () => {
    const alice = env.authenticatedContext('alice').firestore();
    await assertSucceeds(getDoc(doc(alice, 'rooms/r1/views/alice')));
    await assertFails(getDoc(doc(alice, 'rooms/r1/views/bob')));
  });

  it('clients cannot write anything', async () => {
    const alice = env.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(alice, 'rooms/r2'), { code: 'X' }));
    await assertFails(updateDoc(doc(alice, 'rooms/r1'), { status: 'finished' }));
    await assertFails(deleteDoc(doc(alice, 'rooms/r1')));
    await assertFails(setDoc(doc(alice, 'rooms/r1/views/alice'), { view: 'cheat' }));
    await assertFails(setDoc(doc(alice, 'rooms/r1/private/state'), { json: '{}' }));
    await assertFails(setDoc(doc(alice, 'other/x'), { a: 1 }));
  });
});
