// The TypeScript engine must reproduce, move for move, what the Dart
// engine recorded in test-fixtures/parity.json.
import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { parseCards } from '../engine/card';
import { ChuchulaEngine, FixedDecks } from '../engine/engine';
import { evaluate } from '../engine/evaluator';
import { detectBonuses, rulesFromJson, STANDARD_RULES } from '../engine/rules';
import { GameMove, GameState, parseMove, playerView } from '../engine/state';
import { canonical, fnv, loadFixtures } from './helpers';

const fixtures = loadFixtures();

describe('parity with the Dart engine', () => {
  it('evaluates every group to the same strength and category', () => {
    assert.ok(fixtures.evaluator.groups.length > 600);
    for (const g of fixtures.evaluator.groups) {
      const v = evaluate(parseCards(g.cards.join(' ')));
      assert.equal(v.strength, g.strength, g.cards.join(' '));
      assert.equal(v.category, g.category, g.cards.join(' '));
    }
  });

  it('detects the same bonuses', () => {
    for (const h of fixtures.bonuses.hands) {
      assert.deepEqual(detectBonuses(parseCards(h.cards.join(' ')), STANDARD_RULES), h.bonuses, h.cards.join(' '));
    }
  });

  for (const m of fixtures.matches) {
    it(`replays match ${m.seed} identically`, () => {
      const engine = new ChuchulaEngine(new FixedDecks(m.decks));
      const first = m.checkpoints[0].state as GameState;
      let s = engine.startGame({ matchId: first.matchId, seats: first.seats, rules: rulesFromJson(m.rules) });
      assert.equal(canonical(s), canonical(first), 'initial deal');

      const checkpoints = new Map<number, any[]>();
      for (const c of m.checkpoints.slice(1)) checkpoints.set(c.step, [...(checkpoints.get(c.step) ?? []), c]);
      const rejections = new Map<number, any[]>();
      for (const r of m.rejections) rejections.set(r.afterStep, [...(rejections.get(r.afterStep) ?? []), r]);

      const check = (step: number) => {
        for (const r of rejections.get(step) ?? []) {
          const v = engine.validateMove(s, parseMove(r.move));
          assert.equal(v?.error ?? null, r.error, `rejection after step ${step}: ${JSON.stringify(r.move)}`);
        }
        for (const c of checkpoints.get(step) ?? []) {
          if (c.state) assert.equal(canonical(s), canonical(c.state), `state at step ${step}`);
          if (c.views) {
            c.views.forEach((v: unknown, seat: number) =>
              assert.equal(canonical(playerView(s, seat)), canonical(v), `view ${seat} at step ${step}`),
            );
          }
        }
      };

      check(-1);
      m.steps.forEach((step: { move: GameMove; hash: string }, i: number) => {
        s = engine.applyMove(s, parseMove(step.move));
        assert.equal(fnv(canonical(s)), step.hash, `state after step ${i} (${JSON.stringify(step.move)})`);
        check(i);
      });
      assert.equal(s.phase, 'matchOver');
    });
  }
});
