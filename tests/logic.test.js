import { test } from 'node:test';
import assert from 'node:assert/strict';
import { childStatus, summarize, buildRecordTable, slotIndex, recorderMarks, fmtRoom, SOON_MS } from '../app/logic.js';
import { applyOp, applyOps, applyDayOps, sessionsByChild } from '../app/ops.js';

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

test('記録表：確認間隔ごとの枠に、実際の時刻つきで入る', () => {
  const kids = [{ id: 'a' }, { id: 'b' }];
  const byChild = sessionsByChild(applyOps([], [
    start('n1', 'a', T0 + MIN), check('c1', 'n1', T0 + 5 * MIN), check('c2', 'n1', T0 + 11 * MIN, 'right'),
    { type: 'endNap', napId: 'n1', t: T0 + 12 * MIN },
  ]));
  const { slots, rows } = buildRecordTable(kids, byChild, 5, T0 + 60 * MIN);
  assert.equal(slots[0], T0);
  assert.equal(slots.length, 3);
  assert.deepEqual(rows[0].cells.map((c) => c.checks.map((x) => x.posture)), [[], ['supine'], ['right']]);
  assert.equal(rows[0].cells[2].checks[0].t, T0 + 11 * MIN);
  assert.deepEqual(rows[1].cells.map((c) => c.checks.length), [0, 0, 0]);
  assert.deepEqual(buildRecordTable(kids, {}, 5, T0), { slots: [], rows: [] });
});

test('記録表：同じ枠に2回確認したら両方残る', () => {
  const byChild = sessionsByChild(applyOps([], [
    start('n1', 'a', T0), check('c1', 'n1', T0 + MIN), check('c2', 'n1', T0 + 3 * MIN, 'left'),
  ]));
  const { rows } = buildRecordTable([{ id: 'a' }], byChild, 5, T0 + 4 * MIN);
  assert.deepEqual(rows[0].cells[0].checks.map((c) => c.posture), ['supine', 'left']);
});

test('記録表：前の確認から間隔を超えた確認に印がつき、確認のない枠は「未」', () => {
  const byChild = sessionsByChild(applyOps([], [
    start('n1', 'a', T0), check('c1', 'n1', T0 + 4 * MIN), check('c2', 'n1', T0 + 13 * MIN),
    { type: 'endNap', napId: 'n1', t: T0 + 14 * MIN },
  ]));
  const { rows } = buildRecordTable([{ id: 'a' }], byChild, 5, T0 + 60 * MIN);
  const cells = rows[0].cells;
  assert.equal(cells[0].checks[0].late, false);
  assert.equal(cells[1].missing, true);
  assert.equal(cells[2].checks[0].late, true);
});

test('記録表：寝ている子がいれば現在時刻の枠まで伸びる', () => {
  const byChild = sessionsByChild(applyOps([], [start('n1', 'a', T0)]));
  const { slots } = buildRecordTable([{ id: 'a' }], byChild, 5, T0 + 21 * MIN);
  assert.equal(slots.length, 5);
});

test('記録表：過去の日で起床を押し忘れた午睡は、最後の確認までで表が止まる', () => {
  const byChild = sessionsByChild(applyOps([], [start('n1', 'a', T0), check('c1', 'n1', T0 + 4 * MIN), check('c2', 'n1', T0 + 9 * MIN)]));
  const { slots, rows } = buildRecordTable([{ id: 'a' }], byChild, 5, null);
  assert.equal(slots.length, 2);
  assert.equal(rows[0].unclosed, true);
  assert.equal(rows[0].cells.some((c) => c.missing), false);
});

test('前の日に起床を押し忘れた午睡は、今日の起床で閉じない', () => {
  const yesterday = T0 - 24 * 60 * MIN;
  const naps = applyOps([], [
    start('old', 'a', yesterday), start('new', 'a', T0), { type: 'endNap', napId: 'new', t: T0 + 90 * MIN },
  ]);
  assert.deepEqual(naps.map((n) => n.end), [null, T0 + 90 * MIN]);
});

test('記録表：半端な間隔でも、時間枠はその日の0時からそろう', () => {
  const byChild = sessionsByChild(applyOps([], [start('n1', 'a', T0 + 3 * MIN)]));
  const { slots } = buildRecordTable([{ id: 'a' }], byChild, 7, T0 + 20 * MIN);
  // 入眠 12:03 は0時から 723分。7分×103 = 721分 なので、最初の枠は 12:01
  assert.equal(new Date(slots[0]).getMinutes(), 1);
  assert.ok(slots.every((t) => ((t - new Date(t).setHours(0, 0, 0, 0)) / MIN) % 7 === 0));
});

test('記録表：遅れの印は表示の「分」で判断する', () => {
  const byChild = sessionsByChild(applyOps([], [
    start('n1', 'a', T0), check('c1', 'n1', T0 + 5 * MIN + 30 * 1000), check('c2', 'n1', T0 + 11 * MIN + 10 * 1000),
  ]));
  const { rows } = buildRecordTable([{ id: 'a' }], byChild, 5, T0 + 12 * MIN);
  const checks = rows[0].cells.flatMap((c) => c.checks);
  // 12:00 → 12:05（5分）は遅れなし、12:05 → 12:11（6分）は遅れ
  assert.deepEqual(checks.map((c) => c.late), [false, true]);
});

test('記録表：「未」は確認が本当に遅れていた枠だけ（枠の区切りのずれでは付かない）', () => {
  const on = sessionsByChild(applyOps([], [
    start('n1', 'a', T0), check('c1', 'n1', T0 + 5 * MIN), check('c2', 'n1', T0 + 10 * MIN),
    { type: 'endNap', napId: 'n1', t: T0 + 12 * MIN },
  ]));
  const a = buildRecordTable([{ id: 'a' }], on, 5, T0 + 60 * MIN);
  assert.deepEqual(a.rows[0].cells.map((c) => c.missing), [false, false, false]);

  // 起床の直前まで確認していなかった場合は、遅れていた枠に「未」
  const off = sessionsByChild(applyOps([], [
    start('n1', 'a', T0), check('c1', 'n1', T0 + 4 * MIN), { type: 'endNap', napId: 'n1', t: T0 + 17 * MIN },
  ]));
  const b = buildRecordTable([{ id: 'a' }], off, 5, T0 + 60 * MIN);
  assert.deepEqual(b.rows[0].cells.map((c) => c.missing), [false, true, true, true]);

  // 今日の寝ている子は、現在時刻まで確認していなければ「未」
  const now = sessionsByChild(applyOps([], [start('n1', 'a', T0)]));
  const c = buildRecordTable([{ id: 'a' }], now, 5, T0 + 12 * MIN);
  assert.deepEqual(c.rows[0].cells.map((x) => x.missing), [false, true, true]);
});

test('室温・湿度：記録・二重防止・取り消し、午睡の操作と混ざっても正しく振り分ける', () => {
  const room = { type: 'room', id: 'r1', classId: 'c', t: T0, tempC10: 245, humidity: 55, recorderId: 'u1' };
  let d = applyDayOps({ naps: [], rooms: [] }, [room, room, start('n1', 'a', T0)]);
  assert.equal(d.rooms.length, 1);
  assert.equal(d.naps.length, 1);
  assert.equal(fmtRoom(d.rooms[0]), '24.5℃ 55%');
  d = applyDayOps(d, [{ type: 'undoRoom', roomId: 'r1' }]);
  assert.equal(d.rooms.length, 0);
});

test('記録者の印：その日に初めて記録した順に ①② と付く', () => {
  const marks = recorderMarks([
    { t: T0 + 2 * MIN, recorderId: 'sato' }, { t: T0, recorderId: 'suzuki' }, { t: T0 + 3 * MIN, recorderId: 'sato' },
  ]);
  assert.deepEqual([...marks], [['suzuki', '①'], ['sato', '②']]);
});

test('記録表：室温・湿度の時刻も表の範囲に入り、枠の番号が求められる', () => {
  const byChild = sessionsByChild(applyOps([], [start('n1', 'a', T0 + 10 * MIN)]));
  const { slots } = buildRecordTable([{ id: 'a' }], byChild, 5, T0 + 12 * MIN, [T0]);
  assert.equal(slots[0], T0);
  assert.equal(slotIndex(slots, 5, T0 + 7 * MIN), 1);
  assert.equal(slotIndex(slots, 5, T0 - MIN), -1);
});
