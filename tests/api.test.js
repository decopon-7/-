import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { createApi, dayOf, intervalForAge } from '../worker/api.js';
import { hashPassword } from '../worker/auth.js';
import { createTestDb } from './d1-shim.js';

const ORIGIN = 'https://hoiku.example';
const T0 = Date.UTC(2026, 8, 23, 3, 0); // 日本時間 12:00
const MIN = 60e3;
let db;
let clock;
let handle;

// パスワードの変換は遅いので、テスト全体で使い回す
const HASH = await hashPassword('password123');

function seed() {
  const s = db.sqlite;
  for (const f of ['A', 'B']) {
    s.prepare('INSERT INTO facilities VALUES (?, ?, ?)').run(`fac${f}-0001`, `園${f}`, T0);
    s.prepare('INSERT INTO classes (id, facility_id, name, age, interval_min) VALUES (?, ?, ?, 0, 5)')
      .run(`cls${f}-0001`, `fac${f}-0001`, '0歳児');
    s.prepare('INSERT INTO children (id, facility_id, class_id, name, created_at) VALUES (?, ?, ?, ?, ?)')
      .run(`kid${f}-0001`, `fac${f}-0001`, `cls${f}-0001`, 'サンプル', T0);
  }
  const user = (id, fac, login, role, hash = HASH) => s.prepare(
    'INSERT INTO users (id, facility_id, login_id, name, role, password_hash, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
  ).run(id, fac, login, login, role, hash, T0);
  user('usrA-admin', 'facA-0001', 'a-admin', 'admin');
  user('usrA-admn2', 'facA-0001', 'a-admin2', 'admin');
  user('usrA-staff', 'facA-0001', 'staff:usrA-staff', 'staff', '!');
  user('usrA-stf02', 'facA-0001', 'staff:usrA-stf02', 'staff', '!');
  user('usrB-admin', 'facB-0001', 'b-admin', 'admin');
}

beforeEach(() => {
  db = createTestDb();
  clock = T0;
  handle = createApi({ db, now: () => clock });
  seed();
});

function client() {
  let cookie = '';
  const call = async (method, path, data, headers = {}) => {
    const res = await handle(new Request(ORIGIN + path, {
      method,
      headers: {
        ...(data !== undefined ? { 'content-type': 'application/json' } : {}),
        ...(cookie ? { cookie } : {}),
        origin: ORIGIN,
        ...headers,
      },
      body: data !== undefined ? JSON.stringify(data) : undefined,
    }));
    const set = res.headers.get('set-cookie');
    if (set) cookie = set.split(';')[0];
    return { status: res.status, body: await res.json(), setCookie: set };
  };
  return {
    get: (p) => call('GET', p),
    post: (p, d = {}, h) => call('POST', p, d, h),
    patch: (p, d = {}) => call('PATCH', p, d),
    register: (loginId, password = 'password123', deviceName = '0歳児室') =>
      call('POST', '/api/device/register', { loginId, password, deviceName }),
    unlock: (loginId = 'a-admin', password = 'password123') => call('POST', '/api/admin/unlock', { loginId, password }),
  };
}

async function device(loginId = 'a-admin', name = '0歳児室') {
  const c = client();
  assert.equal((await c.register(loginId, 'password123', name)).status, 200);
  return c;
}

async function adminDevice(loginId = 'a-admin') {
  const c = await device(loginId);
  assert.equal((await c.unlock(loginId)).status, 200);
  return c;
}

test('日付は日本時間で決まる／確認間隔は0歳5分・それ以外10分', () => {
  assert.equal(dayOf(Date.UTC(2026, 8, 22, 15, 0)), '2026-09-23');
  assert.equal(dayOf(Date.UTC(2026, 8, 22, 14, 59)), '2026-09-22');
  assert.deepEqual([0, 1, 2, 5].map(intervalForAge), [5, 10, 10, 10]);
});

// ---------- 端末の登録 ----------

test('端末の登録：Cookieは HttpOnly・Secure・SameSite=Strict、端末名が残る', async () => {
  const c = client();
  const r = await c.register('A-Admin');
  assert.equal(r.status, 200);
  assert.match(r.setCookie, /HttpOnly/);
  assert.match(r.setCookie, /Secure/);
  assert.match(r.setCookie, /SameSite=Strict/);
  const b = (await c.get('/api/bootstrap')).body;
  assert.equal(b.device.name, '0歳児室');
  assert.equal(b.facility.name, '園A');
  assert.equal(b.admin, null);
  // 職員は名前だけ（ログインIDは見えない）
  assert.deepEqual(b.staff.map((s) => Object.keys(s).sort()), Array(4).fill(['active', 'id', 'name']));
});

test('職員は端末を登録できない（パスワードがない）', async () => {
  assert.equal((await client().register('staff:usra-staff', '!')).status, 401);
});

test('登録していない端末は何も読めない', async () => {
  assert.equal((await client().get('/api/bootstrap')).status, 401);
  assert.equal((await client().get('/api/day')).status, 401);
});

test('5回失敗すると正しいパスワードでもしばらく登録できない', async () => {
  const c = client();
  for (let i = 0; i < 5; i++) assert.equal((await c.register('a-admin', 'wrong-pass')).status, 401);
  assert.equal((await c.register('a-admin')).status, 429);
  clock += 16 * MIN;
  assert.equal((await c.register('a-admin')).status, 200);
});

test('存在しないIDと間違ったパスワードは同じ応答', async () => {
  const a = await client().register('nobody');
  const b = await client().register('a-admin', 'wrong-pass');
  assert.deepEqual([a.status, a.body], [b.status, b.body]);
});

test('使っている端末は登録が続き、90日使わない端末は切れる', async () => {
  const used = await device();
  const idle = await device();
  for (let i = 0; i < 4; i++) {
    clock += 40 * 24 * 60 * MIN;
    assert.equal((await used.get('/api/bootstrap')).status, 200);
  }
  assert.equal((await idle.get('/api/bootstrap')).status, 401);
});

test('別サイトからの書き込みは断る', async () => {
  const c = await device();
  assert.equal((await c.post('/api/ops', { ops: [] }, { origin: 'https://evil.example' })).status, 403);
});

// ---------- 管理者モード ----------

test('管理者モード：パスワードを入れるまで設定は変えられず、10分で自動で戻る', async () => {
  const c = await device();
  assert.equal((await c.post('/api/admin/children', { name: 'x', classId: 'clsA-0001' })).body.error, 'admin_mode_required');
  assert.equal((await c.unlock('a-admin', 'wrong-pass')).status, 401);
  assert.equal((await c.unlock('a-admin2')).status, 200); // 同じ園の別の管理者でもよい
  const boot = (await c.get('/api/bootstrap')).body;
  assert.equal(boot.admin.name, 'a-admin2');
  assert.ok(boot.staff.some((s) => s.loginId === 'a-admin'));
  assert.equal((await c.post('/api/admin/children', { name: 'x', classId: 'clsA-0001' })).status, 200);
  clock += 11 * MIN;
  assert.equal((await c.post('/api/admin/children', { name: 'y', classId: 'clsA-0001' })).status, 403);
  assert.equal((await c.get('/api/bootstrap')).body.admin, null);
});

test('管理者モード：「戻す」を押せばすぐ戻る', async () => {
  const c = await adminDevice();
  await c.post('/api/admin/lock');
  assert.equal((await c.post('/api/admin/children', { name: 'x', classId: 'clsA-0001' })).status, 403);
});

test('管理者モード：別の園の管理者のパスワードでは入れない', async () => {
  const c = await device();
  assert.equal((await c.unlock('b-admin')).status, 401);
});

test('職員の追加は名前だけ。管理者はIDとパスワードつき', async () => {
  const c = await adminDevice();
  assert.equal((await c.post('/api/admin/users', { name: '佐藤' })).status, 200);
  assert.equal((await c.post('/api/admin/users', { name: '新管理者', role: 'admin', loginId: 'New.Admin', password: 'longenough' })).status, 200);
  assert.equal((await c.post('/api/admin/users', { name: 'x', role: 'admin', loginId: 'new.admin', password: 'longenough' })).status, 409);
  assert.equal((await c.post('/api/admin/users', { name: 'x', role: 'admin', loginId: 'short-pw', password: 'short' })).body.error, 'weak_password');
  assert.equal((await client().register('new.admin', 'longenough')).status, 200);
  const sato = (await c.get('/api/bootstrap')).body.staff.find((s) => s.name === '佐藤');
  assert.equal(sato.role, 'staff');
  assert.equal(sato.loginId, null);
  assert.equal((await c.patch(`/api/admin/users/${sato.id}`, { password: 'longenough' })).body.error, 'staff_has_no_password');
});

test('クラスの確認間隔は年齢から自動で決まり、指定しても変わらない', async () => {
  const c = await adminDevice();
  const { id } = (await c.post('/api/admin/classes', { name: '1歳児', age: 1, intervalMin: 3 })).body;
  let cls = (await c.get('/api/bootstrap')).body.classes.find((x) => x.id === id);
  assert.equal(cls.intervalMin, 10);
  await c.patch(`/api/admin/classes/${id}`, { age: 0 });
  cls = (await c.get('/api/bootstrap')).body.classes.find((x) => x.id === id);
  assert.equal(cls.intervalMin, 5);
});

test('端末の一覧と、1台ずつ・全部の登録解除（今の端末は残る）', async () => {
  const admin = await adminDevice();
  const other = await device('a-admin', '1歳児室');
  const b = await device('b-admin', 'B園');
  const list = (await admin.get('/api/admin/devices')).body.devices;
  assert.deepEqual(list.map((d) => [d.name, d.current]), [['0歳児室', true], ['1歳児室', false]]);
  await admin.post(`/api/admin/devices/${list[1].id}`);
  assert.equal((await other.get('/api/bootstrap')).status, 401);
  const third = await device('a-admin', '2歳児室');
  await admin.post('/api/admin/devices/revoke-all');
  assert.equal((await third.get('/api/bootstrap')).status, 401);
  assert.equal((await admin.get('/api/bootstrap')).status, 200);
  assert.equal((await b.get('/api/bootstrap')).status, 200);
});

test('管理者を停止すると、その人が登録した端末も使えなくなる。自分は停止できない', async () => {
  const admin = await adminDevice('a-admin');
  const byAdmin2 = await device('a-admin2', '1歳児室');
  assert.equal((await admin.patch('/api/admin/users/usrA-admin', { active: false })).body.error, 'cannot_demote_self');
  await admin.patch('/api/admin/users/usrA-admn2', { active: false });
  assert.equal((await byAdmin2.get('/api/bootstrap')).status, 401);
});

test('端末の登録を解除すると読めなくなる', async () => {
  const c = await device();
  await c.post('/api/device/unregister');
  assert.equal((await c.get('/api/bootstrap')).status, 401);
});

// ---------- 午睡の記録 ----------

test('午睡の一連の操作：記録者（2名のどちらか）と端末が残り、二重にならない', async () => {
  const c = await device();
  const ops = [
    { type: 'startNap', id: 'nap-00000001', childId: 'kidA-0001', t: T0 },
    { type: 'check', id: 'chk-00000001', napId: 'nap-00000001', t: T0 + 5 * MIN, posture: 'supine', recorderId: 'usrA-staff' },
    { type: 'check', id: 'chk-00000002', napId: 'nap-00000001', t: T0 + 10 * MIN, posture: 'prone', fixed: true, recorderId: 'usrA-stf02' },
  ];
  clock = T0 + 11 * MIN;
  await c.post('/api/ops', { ops });
  const r = await c.post('/api/ops', { ops });
  assert.deepEqual(r.body.results, [{ ok: true }, { ok: true }, { ok: true }]);
  assert.equal(r.body.naps.length, 1);
  assert.deepEqual(r.body.naps[0].checks.map((x) => [x.posture, x.fixed ?? false, x.recorderId]),
    [['supine', false, 'usrA-staff'], ['prone', true, 'usrA-stf02']]);
  const row = db.sqlite.prepare('SELECT device_name FROM nap_checks WHERE id = ?').get('chk-00000001');
  assert.equal(row.device_name, '0歳児室');

  await c.post('/api/ops', { ops: [{ type: 'undoCheck', checkId: 'chk-00000002' }] });
  const n = await c.get('/api/day?day=2026-09-23');
  assert.equal(n.body.naps[0].checks.length, 1);
  assert.ok(db.sqlite.prepare('SELECT deleted_at FROM nap_checks WHERE id = ?').get('chk-00000002').deleted_at);
});

test('起床は、その子の同じ日の開いている午睡をすべて閉じる', async () => {
  const c = await device();
  clock = T0 + MIN;
  await c.post('/api/ops', { ops: [
    { type: 'startNap', id: 'nap-tablet-1', childId: 'kidA-0001', t: T0 },
    { type: 'startNap', id: 'nap-tablet-2', childId: 'kidA-0001', t: T0 + 1000 },
  ] });
  clock = T0 + 30 * MIN;
  const r = await c.post('/api/ops', { ops: [{ type: 'endNap', napId: 'nap-tablet-2', t: clock }] });
  assert.deepEqual(r.body.naps.map((n) => n.end), [clock, clock]);
  const late = await c.post('/api/ops', { ops: [
    { type: 'check', id: 'chk-late-0001', napId: 'nap-tablet-1', t: clock + MIN, posture: 'supine', recorderId: 'usrA-staff' },
  ] });
  assert.deepEqual(late.body.results, [{ ok: false, error: 'nap_already_ended' }]);
});

test('前の日に起床を押し忘れた午睡は、今日の起床で閉じない', async () => {
  const c = await device();
  await c.post('/api/ops', { ops: [{ type: 'startNap', id: 'nap-yesterday', childId: 'kidA-0001', t: T0 }] });
  clock = T0 + 24 * 60 * MIN;
  await c.post('/api/ops', { ops: [{ type: 'startNap', id: 'nap-today-001', childId: 'kidA-0001', t: clock }] });
  clock += 90 * MIN;
  await c.post('/api/ops', { ops: [{ type: 'endNap', napId: 'nap-today-001', t: clock }] });
  const rows = db.sqlite.prepare('SELECT id, end_at FROM naps ORDER BY start_at').all();
  assert.deepEqual(rows.map((r) => [r.id, r.end_at]), [['nap-yesterday', null], ['nap-today-001', clock]]);
});

test('午睡には開始時点のクラスと確認間隔が残り、あとでクラス替えしても変わらない', async () => {
  const c = await adminDevice();
  await c.post('/api/ops', { ops: [{ type: 'startNap', id: 'nap-00000001', childId: 'kidA-0001', t: T0 }] });
  const { id: cls1 } = (await c.post('/api/admin/classes', { name: '1歳児', age: 1 })).body;
  await c.patch('/api/admin/children/kidA-0001', { classId: cls1 });
  const [nap] = (await c.get('/api/day?day=2026-09-23')).body.naps;
  assert.equal(nap.classId, 'clsA-0001');
  assert.equal(nap.intervalMin, 5);
});

test('室温・湿度：記録と取り消し、ありえない値は断る', async () => {
  const c = await device();
  const r = await c.post('/api/ops', { ops: [
    { type: 'room', id: 'room-0000001', classId: 'clsA-0001', t: T0, tempC10: 245, humidity: 55, recorderId: 'usrA-staff' },
    { type: 'room', id: 'room-0000002', classId: 'clsA-0001', t: T0, tempC10: 999, humidity: 55, recorderId: 'usrA-staff' },
    { type: 'room', id: 'room-0000003', classId: 'clsA-0001', t: T0, tempC10: 240, humidity: 101, recorderId: 'usrA-staff' },
  ] });
  assert.deepEqual(r.body.results.map((x) => x.error ?? 'ok'), ['ok', 'invalid_input', 'invalid_input']);
  assert.deepEqual(r.body.rooms.map((x) => [x.tempC10, x.humidity, x.recorderId]), [[245, 55, 'usrA-staff']]);
  const u = await c.post('/api/ops', { ops: [{ type: 'undoRoom', roomId: 'room-0000001' }] });
  assert.equal(u.body.rooms.length, 0);
});

test('ありえない時刻・不明な操作は断る（他の操作は止めない）', async () => {
  const c = await device();
  const r = await c.post('/api/ops', { ops: [
    { type: 'startNap', id: 'nap-future-1', childId: 'kidA-0001', t: T0 + 60 * MIN },
    { type: 'dance' },
    { type: 'startNap', id: 'nap-ok-00001', childId: 'kidA-0001', t: T0 },
  ] });
  assert.deepEqual(r.body.results.map((x) => x.error ?? 'ok'), ['invalid_time', 'unknown_op', 'ok']);
});

test('別の園の子ども・記録・職員・クラスには触れない', async () => {
  const a = await device();
  const b = await adminDevice('b-admin');
  await a.post('/api/ops', { ops: [{ type: 'startNap', id: 'nap-A-000001', childId: 'kidA-0001', t: T0 }] });

  const r = await b.post('/api/ops', { ops: [
    { type: 'startNap', id: 'nap-B-000001', childId: 'kidA-0001', t: T0 },
    { type: 'check', id: 'chk-B-000001', napId: 'nap-A-000001', t: T0, posture: 'supine', recorderId: 'usrB-admin' },
    { type: 'endNap', napId: 'nap-A-000001', t: T0 },
    { type: 'room', id: 'room-B-00001', classId: 'clsA-0001', t: T0, tempC10: 240, humidity: 50, recorderId: 'usrB-admin' },
  ] });
  assert.deepEqual(r.body.results.map((x) => x.error), ['child_not_found', 'nap_not_found', 'nap_not_found', 'class_not_found']);
  assert.equal((await b.get('/api/day?day=2026-09-23')).body.naps.length, 0);
  assert.equal((await b.patch('/api/admin/children/kidA-0001', { name: 'x' })).status, 404);
  assert.equal((await b.patch('/api/admin/users/usrA-staff', { active: false })).status, 404);
  assert.equal((await b.patch('/api/admin/classes/clsA-0001', { name: 'x' })).status, 404);

  // 他の園の職員を記録者にすることもできない
  const own = await a.post('/api/ops', { ops: [
    { type: 'check', id: 'chk-A-000001', napId: 'nap-A-000001', t: T0, posture: 'supine', recorderId: 'usrB-admin' },
    { type: 'room', id: 'room-A-00001', classId: 'clsA-0001', t: T0, tempC10: 240, humidity: 50, recorderId: 'usrB-admin' },
  ] });
  assert.deepEqual(own.body.results.map((x) => x.error), ['recorder_not_found', 'recorder_not_found']);
});

test('管理の操作は監査ログに端末名つきで残る', async () => {
  const c = await adminDevice();
  await c.post('/api/admin/children', { name: 'サンプル2', classId: 'clsA-0001' });
  const rows = db.sqlite.prepare('SELECT action, user_id, detail FROM audit_log ORDER BY id').all();
  assert.deepEqual(rows.map((r) => r.action), ['register_device', 'admin_unlock', 'create_child']);
  assert.equal(JSON.parse(rows[2].detail).device, '0歳児室');
  assert.equal(rows[2].user_id, 'usrA-admin');
});
