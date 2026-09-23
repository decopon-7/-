import { test } from 'node:test';
import assert from 'node:assert/strict';
import { childStatus, summarize, buildRecordTable, SOON_MS } from '../app/logic.js';
import { applyOp, applyOps, sessionsByChild } from '../app/ops.js';

const MIN = 60 * 1000;
const T0 = new Date(2026, 8, 23, 12, 0).getTime();

const start = (id, childId, t) => ({ type: 'startNap', id, childId, t });
const check = (id, napId, t, posture = 'supine', extra = {}) =>
  ({ type: 'check', id, napId, t, posture, recorderId: 'u1', ...extra });

function sessionsOf(ops, childId = 'a') {
  return sessionsByChild(applyOps([], ops))[childId];
}

test('寝る前・午睡中・起床の状態', () => {
  assert.equal(childStatus(undefined, T0, 5).state, 'before');
  const s = sessionsOf([start('n1', 'a', T0)]);
  assert.equal(childStatus(s, T0 + 1 * MIN, 5).state, 'ok');
  assert.equal(childStatus(s, T0 + 5 * MIN - SOON_MS + 1, 5).state, 'soon');
  assert.equal(childStatus(s, T0 + 5 * MIN, 5).state, 'overdue');
  const ended = sessionsOf([start('n1', 'a', T0), { type: 'endNap', napId: 'n1', t: T0 + 30 * MIN }]);
  assert.equal(childStatus(ended, T0 + 31 * MIN, 5).state, 'awake');
});

test('確認すると次の期限が確認時刻から数え直される', () => {
  const s = sessionsOf([start('n1', 'a', T0), check('c1', 'n1', T0 + 4 * MIN)]);
  const st = childStatus(s, T0 + 6 * MIN, 5);
  assert.equal(st.state, 'ok');
  assert.equal(st.due, T0 + 9 * MIN);
  assert.equal(st.last.recorderId, 'u1');
});

test('同じ操作を2回反映しても二重にならない', () => {
  const ops = [start('n1', 'a', T0), check('c1', 'n1', T0 + MIN)];
  const once = applyOps([], ops);
  assert.deepEqual(applyOps(once, ops), once);
});

test('うつぶせは直した印つきで残る', () => {
  const [nap] = applyOps([], [start('n1', 'a', T0), check('c1', 'n1', T0 + MIN, 'prone', { fixed: true })]);
  assert.deepEqual(nap.checks[0], { id: 'c1', t: T0 + MIN, posture: 'prone', recorderId: 'u1', fixed: true });
});

test('起床より後の確認は反映しない', () => {
  const naps = applyOps([], [start('n1', 'a', T0), { type: 'endNap', napId: 'n1', t: T0 + MIN }, check('c1', 'n1', T0 + 2 * MIN)]);
  assert.equal(naps[0].checks.length, 0);
});

test('取り消しは指定した確認だけ消す', () => {
  const naps = applyOps([], [
    start('n1', 'a', T0), check('c1', 'n1', T0 + MIN), check('c2', 'n1', T0 + 2 * MIN, 'left'),
    { type: 'undoCheck', checkId: 'c2' },
  ]);
  assert.deepEqual(naps[0].checks.map((c) => c.id), ['c1']);
});

test('起床はその子の開いている午睡をすべて閉じ、他の子には影響しない', () => {
  const naps = applyOps([], [
    start('n1', 'a', T0), start('n2', 'a', T0 + 1000), start('n3', 'b', T0),
    { type: 'endNap', napId: 'n2', t: T0 + 10 * MIN },
  ]);
  assert.deepEqual(naps.map((n) => n.end), [T0 + 10 * MIN, T0 + 10 * MIN, null]);
});

test('起床後にもう一度寝ると、最後の午睡が対象になる', () => {
  const s = sessionsOf([start('n1', 'a', T0), { type: 'endNap', napId: 'n1', t: T0 + 10 * MIN }, start('n2', 'a', T0 + 20 * MIN)]);
  assert.equal(s.length, 2);
  assert.equal(childStatus(s, T0 + 21 * MIN, 5).state, 'ok');
});

test('集計', () => {
  const c = summarize([{ state: 'ok' }, { state: 'soon' }, { state: 'overdue' }, { state: 'awake' }, { state: 'before' }]);
  assert.deepEqual(c, { sleeping: 3, soon: 1, overdue: 1, awake: 1, before: 1 });
});

test('記録表：確認間隔ごとの枠に入る', () => {
  const kids = [{ id: 'a' }, { id: 'b' }];
  const byChild = sessionsByChild(applyOps([], [
    start('n1', 'a', T0 + MIN), check('c1', 'n1', T0 + 5 * MIN), check('c2', 'n1', T0 + 11 * MIN, 'right'),
    { type: 'endNap', napId: 'n1', t: T0 + 12 * MIN },
  ]));
  const { slots, rows } = buildRecordTable(kids, byChild, 5, T0 + 60 * MIN);
  assert.equal(slots[0], T0);
  assert.equal(slots.length, 3);
  assert.equal(rows[0].cells[0], null);
  assert.equal(rows[0].cells[1].posture, 'supine');
  assert.equal(rows[0].cells[2].posture, 'right');
  assert.deepEqual(rows[1].cells, [null, null, null]);
  assert.deepEqual(buildRecordTable(kids, {}, 5), { slots: [], rows: [] });
});

test('記録表：寝ている子がいれば現在時刻の枠まで伸びる', () => {
  const { slots } = buildRecordTable([{ id: 'a' }], sessionsByChild([applyOp([], start('n1', 'a', T0))[0]]), 5, T0 + 21 * MIN);
  assert.equal(slots.length, 5);
});
