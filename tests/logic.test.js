import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  intervalMinutes, childStatus, startNap, recordCheck, endNap, undoLastCheck,
  summarize, buildRecordTable, SOON_MS,
} from '../app/logic.js';

const MIN = 60 * 1000;
const T0 = new Date(2026, 8, 23, 12, 0).getTime();

test('確認間隔：年齢ごとの値、未設定なら5分', () => {
  assert.equal(intervalMinutes(0), 5);
  assert.equal(intervalMinutes(2), 10);
  assert.equal(intervalMinutes('1', { 1: 7 }), 7);
  assert.equal(intervalMinutes(3, {}), 5);
});

test('寝る前・午睡中・起床の状態', () => {
  assert.equal(childStatus(undefined, T0, 5).state, 'before');
  let s = startNap(undefined, T0);
  assert.equal(childStatus(s, T0 + 1 * MIN, 5).state, 'ok');
  assert.equal(childStatus(s, T0 + 5 * MIN - SOON_MS + 1, 5).state, 'soon');
  assert.equal(childStatus(s, T0 + 5 * MIN, 5).state, 'overdue');
  s = endNap(s, T0 + 30 * MIN);
  assert.equal(childStatus(s, T0 + 31 * MIN, 5).state, 'awake');
});

test('確認すると次の期限が確認時刻から数え直される', () => {
  let s = startNap([], T0);
  s = recordCheck(s, T0 + 4 * MIN, 'supine', 'A');
  const st = childStatus(s, T0 + 6 * MIN, 5);
  assert.equal(st.state, 'ok');
  assert.equal(st.due, T0 + 9 * MIN);
  assert.equal(st.last.staff, 'A');
});

test('うつぶせは直した印つきで残る・不明な体位はエラー', () => {
  let s = recordCheck(startNap([], T0), T0 + MIN, 'prone', 'A', true);
  assert.deepEqual(s[0].checks[0], { t: T0 + MIN, posture: 'prone', staff: 'A', fixed: true });
  assert.throws(() => recordCheck(s, T0, 'sitting', 'A'));
});

test('起床後は確認や取り消しをしても変わらない', () => {
  const s = endNap(startNap([], T0), T0 + MIN);
  assert.equal(recordCheck(s, T0 + 2 * MIN, 'supine', 'A'), s);
  assert.equal(undoLastCheck(s), s);
  assert.equal(endNap(s, T0 + 3 * MIN), s);
});

test('取り消しは最後の1件だけ消す', () => {
  let s = startNap([], T0);
  s = recordCheck(s, T0 + MIN, 'supine', 'A');
  s = recordCheck(s, T0 + 2 * MIN, 'left', 'A');
  s = undoLastCheck(s);
  assert.equal(s[0].checks.length, 1);
  assert.equal(s[0].checks[0].posture, 'supine');
});

test('午睡中に午睡開始を押しても二重にならない・起床後はもう一度寝られる', () => {
  let s = startNap([], T0);
  assert.equal(startNap(s, T0 + MIN), s);
  s = startNap(endNap(s, T0 + 10 * MIN), T0 + 20 * MIN);
  assert.equal(s.length, 2);
});

test('集計', () => {
  const c = summarize([{ state: 'ok' }, { state: 'soon' }, { state: 'overdue' }, { state: 'awake' }, { state: 'before' }]);
  assert.deepEqual(c, { sleeping: 3, soon: 1, overdue: 1, awake: 1, before: 1 });
});

test('記録表：確認間隔ごとの枠に入る', () => {
  const kids = [{ id: 'a' }, { id: 'b' }];
  let a = startNap([], T0 + 1 * MIN);
  a = recordCheck(a, T0 + 5 * MIN, 'supine', 'A');
  a = recordCheck(a, T0 + 11 * MIN, 'right', 'A');
  a = endNap(a, T0 + 12 * MIN);
  const { slots, rows } = buildRecordTable(kids, { a }, 5, T0 + 60 * MIN);
  assert.equal(slots[0], T0);
  assert.equal(slots.length, 3);
  assert.equal(rows[0].cells[0], null);
  assert.equal(rows[0].cells[1].posture, 'supine');
  assert.equal(rows[0].cells[2].posture, 'right');
  assert.deepEqual(rows[1].cells, [null, null, null]);
  assert.deepEqual(buildRecordTable(kids, {}, 5), { slots: [], rows: [] });
});

test('記録表：寝ている子がいれば現在時刻の枠まで伸びる', () => {
  const a = startNap([], T0);
  const { slots } = buildRecordTable([{ id: 'a' }], { a }, 5, T0 + 21 * MIN);
  assert.equal(slots.length, 5);
});
