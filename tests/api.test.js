import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { createApi, dayOf } from '../worker/api.js';
import { hashPassword } from '../worker/auth.js';
import { createTestDb } from './d1-shim.js';

const ORIGIN = 'https://hoiku.example';
const T0 = Date.UTC(2026, 8, 23, 3, 0); // 日本時間 12:00
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
  const user = (id, fac, login, role) => s.prepare(
    'INSERT INTO users (id, facility_id, login_id, name, role, password_hash, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
  ).run(id, fac, login, login, role, HASH, T0);
  user('usrA-admin', 'facA-0001', 'a-admin', 'admin');
  user('usrA-staff', 'facA-0001', 'a-staff', 'staff');
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
    call,
    get: (p) => call('GET', p),
    post: (p, d = {}, h) => call('POST', p, d, h),
    patch: (p, d = {}) => call('PATCH', p, d),
    login: (loginId, password = 'password123') => call('POST', '/api/login', { loginId, password }),
  };
}

async function loggedIn(loginId) {
  const c = client();
  assert.equal((await c.login(loginId)).status, 200);
  return c;
}

test('日付は日本時間で決まる', () => {
  assert.equal(dayOf(Date.UTC(2026, 8, 22, 15, 0)), '2026-09-23');
  assert.equal(dayOf(Date.UTC(2026, 8, 22, 14, 59)), '2026-09-22');
});

test('ログイン：Cookieは HttpOnly・Secure・SameSite=Strict', async () => {
  const c = client();
  const r = await c.login('A-Admin');
  assert.equal(r.status, 200);
  assert.match(r.setCookie, /HttpOnly/);
  assert.match(r.setCookie, /Secure/);
  assert.match(r.setCookie, /SameSite=Strict/);
  const b = await c.get('/api/bootstrap');
  assert.equal(b.body.me.role, 'admin');
  assert.equal(b.body.facility.name, '園A');
});

test('ログインしていないと読めない', async () => {
  assert.equal((await client().get('/api/bootstrap')).status, 401);
  assert.equal((await client().get('/api/naps')).status, 401);
});

test('5回失敗すると正しいパスワードでもしばらく入れない', async () => {
  const c = client();
  for (let i = 0; i < 5; i++) assert.equal((await c.login('a-staff', 'wrong-pass')).status, 401);
  assert.equal((await c.login('a-staff')).status, 429);
  clock += 16 * 60 * 1000;
  assert.equal((await c.login('a-staff')).status, 200);
});

test('存在しないIDと間違ったパスワードは同じ応答', async () => {
  const a = await client().login('nobody', 'password123');
  const b = await client().login('a-staff', 'wrong-pass');
  assert.deepEqual([a.status, a.body], [b.status, b.body]);
});

test('別サイトからの書き込みは断る', async () => {
  const c = await loggedIn('a-staff');
  const r = await c.post('/api/ops', { ops: [] }, { origin: 'https://evil.example' });
  assert.equal(r.status, 403);
});

test('午睡の一連の操作と、同じ操作を2回送っても二重にならないこと', async () => {
  const c = await loggedIn('a-staff');
  const ops = [
    { type: 'startNap', id: 'nap-00000001', childId: 'kidA-0001', t: T0 },
    { type: 'check', id: 'chk-00000001', napId: 'nap-00000001', t: T0 + 5 * 60e3, posture: 'supine', recorderId: 'usrA-admin' },
    { type: 'check', id: 'chk-00000002', napId: 'nap-00000001', t: T0 + 10 * 60e3, posture: 'prone', fixed: true, recorderId: 'usrA-staff' },
  ];
  clock = T0 + 11 * 60e3;
  await c.post('/api/ops', { ops });
  const r = await c.post('/api/ops', { ops });
  assert.deepEqual(r.body.results, [{ ok: true }, { ok: true }, { ok: true }]);
  assert.equal(r.body.naps.length, 1);
  assert.deepEqual(r.body.naps[0].checks.map((x) => [x.posture, x.fixed ?? false, x.recorderId]),
    [['supine', false, 'usrA-admin'], ['prone', true, 'usrA-staff']]);

  // 取り消しは記録から消えるが、データには取り消した人が残る
  await c.post('/api/ops', { ops: [{ type: 'undoCheck', checkId: 'chk-00000002' }] });
  const n = await c.get('/api/naps?day=2026-09-23');
  assert.equal(n.body.naps[0].checks.length, 1);
  const row = db.sqlite.prepare('SELECT deleted_by, entered_by FROM nap_checks WHERE id = ?').get('chk-00000002');
  assert.equal(row.deleted_by, 'usrA-staff');
  assert.equal(row.entered_by, 'usrA-staff');
});

test('起床は、その子の開いている午睡をすべて閉じる', async () => {
  const c = await loggedIn('a-staff');
  clock = T0 + 60e3;
  await c.post('/api/ops', { ops: [
    { type: 'startNap', id: 'nap-tablet-1', childId: 'kidA-0001', t: T0 },
    { type: 'startNap', id: 'nap-tablet-2', childId: 'kidA-0001', t: T0 + 1000 },
  ] });
  clock = T0 + 30 * 60e3;
  const r = await c.post('/api/ops', { ops: [{ type: 'endNap', napId: 'nap-tablet-2', t: clock }] });
  assert.deepEqual(r.body.naps.map((n) => n.end), [clock, clock]);
  // 起床後の時刻の確認は受け付けない
  const late = await c.post('/api/ops', { ops: [
    { type: 'check', id: 'chk-late-0001', napId: 'nap-tablet-1', t: clock + 60e3, posture: 'supine', recorderId: 'usrA-staff' },
  ] });
  assert.deepEqual(late.body.results, [{ ok: false, error: 'nap_already_ended' }]);
});

test('ありえない時刻・不明な操作は断る（他の操作は止めない）', async () => {
  const c = await loggedIn('a-staff');
  const r = await c.post('/api/ops', { ops: [
    { type: 'startNap', id: 'nap-future-1', childId: 'kidA-0001', t: T0 + 60 * 60e3 },
    { type: 'dance' },
    { type: 'startNap', id: 'nap-ok-00001', childId: 'kidA-0001', t: T0 },
  ] });
  assert.deepEqual(r.body.results.map((x) => x.error ?? 'ok'), ['invalid_time', 'unknown_op', 'ok']);
});

test('別の園の子ども・記録・職員には触れない', async () => {
  const a = await loggedIn('a-staff');
  const b = await loggedIn('b-admin');
  await a.post('/api/ops', { ops: [{ type: 'startNap', id: 'nap-A-000001', childId: 'kidA-0001', t: T0 }] });

  const r = await b.post('/api/ops', { ops: [
    { type: 'startNap', id: 'nap-B-000001', childId: 'kidA-0001', t: T0 },
    { type: 'check', id: 'chk-B-000001', napId: 'nap-A-000001', t: T0, posture: 'supine', recorderId: 'usrB-admin' },
    { type: 'endNap', napId: 'nap-A-000001', t: T0 },
  ] });
  assert.deepEqual(r.body.results.map((x) => x.error), ['child_not_found', 'nap_not_found', 'nap_not_found']);
  assert.equal((await b.get('/api/naps?day=2026-09-23')).body.naps.length, 0);
  assert.equal((await b.patch('/api/admin/children/kidA-0001', { name: 'x' })).status, 404);
  assert.equal((await b.patch('/api/admin/users/usrA-staff', { active: false })).status, 404);

  // 他の園の職員を記録者にすることもできない
  const own = await a.post('/api/ops', { ops: [
    { type: 'check', id: 'chk-A-000001', napId: 'nap-A-000001', t: T0, posture: 'supine', recorderId: 'usrB-admin' },
  ] });
  assert.deepEqual(own.body.results, [{ ok: false, error: 'recorder_not_found' }]);
});

test('職員は管理の操作ができず、他の職員のログインIDも見えない', async () => {
  const c = await loggedIn('a-staff');
  assert.equal((await c.post('/api/admin/children', { name: 'x', classId: 'clsA-0001' })).status, 403);
  const boot = await c.get('/api/bootstrap');
  assert.equal(boot.body.staff.some((s) => 'loginId' in s), false);
});

test('管理者：職員を停止するとその人のログインが切れる', async () => {
  const admin = await loggedIn('a-admin');
  const staff = await loggedIn('a-staff');
  assert.equal((await admin.patch('/api/admin/users/usrA-staff', { active: false })).status, 200);
  assert.equal((await staff.get('/api/bootstrap')).status, 401);
  assert.equal((await client().login('a-staff')).status, 401);
});

test('管理者：自分を停止・降格はできない', async () => {
  const admin = await loggedIn('a-admin');
  assert.equal((await admin.patch('/api/admin/users/usrA-admin', { role: 'staff' })).body.error, 'cannot_demote_self');
});

test('管理者：職員・子ども・クラスの追加と変更', async () => {
  const admin = await loggedIn('a-admin');
  const u = await admin.post('/api/admin/users', { loginId: 'New.Staff', name: '新しい先生', password: 'longenough' });
  assert.equal(u.status, 200);
  assert.equal((await admin.post('/api/admin/users', { loginId: 'new.staff', name: 'x', password: 'longenough' })).status, 409);
  assert.equal((await admin.post('/api/admin/users', { loginId: 'short-pw', name: 'x', password: 'short' })).body.error, 'weak_password');
  assert.equal((await client().login('new.staff', 'longenough')).status, 200);

  const k = await admin.post('/api/admin/children', { name: 'サンプル2', classId: 'clsA-0001' });
  assert.equal(k.status, 200);
  assert.equal((await admin.post('/api/admin/children', { name: 'x', classId: 'clsB-0001' })).status, 404);
  await admin.patch('/api/admin/classes/clsA-0001', { intervalMin: 7 });
  assert.equal((await admin.patch('/api/admin/classes/clsA-0001', { intervalMin: 0 })).status, 400);

  const boot = (await admin.get('/api/bootstrap')).body;
  assert.equal(boot.classes[0].intervalMin, 7);
  assert.equal(boot.children.length, 2);
  const logged = db.sqlite.prepare('SELECT action FROM audit_log ORDER BY id').all().map((r) => r.action);
  assert.deepEqual(logged, ['create_user', 'create_child', 'update_class']);
});

test('管理者：全端末ログアウト（自分の端末は残る）', async () => {
  const admin = await loggedIn('a-admin');
  const staff = await loggedIn('a-staff');
  const other = await loggedIn('b-admin');
  await admin.post('/api/admin/sessions/revoke-all');
  assert.equal((await staff.get('/api/bootstrap')).status, 401);
  assert.equal((await admin.get('/api/bootstrap')).status, 200);
  assert.equal((await other.get('/api/bootstrap')).status, 200);
});

test('自分のパスワード変更：他の端末のログインは切れる', async () => {
  const tablet = await loggedIn('a-staff');
  const phone = await loggedIn('a-staff');
  assert.equal((await phone.post('/api/me/password', { current: 'nope', next: 'newpassword' })).body.error, 'wrong_password');
  assert.equal((await phone.post('/api/me/password', { current: 'password123', next: 'newpassword' })).status, 200);
  assert.equal((await tablet.get('/api/bootstrap')).status, 401);
  assert.equal((await phone.get('/api/bootstrap')).status, 200);
  assert.equal((await client().login('a-staff', 'newpassword')).status, 200);
});

test('ログアウトとセッションの期限切れ', async () => {
  const c = await loggedIn('a-staff');
  assert.equal((await c.post('/api/logout')).status, 200);
  assert.equal((await c.get('/api/bootstrap')).status, 401);
  const d = await loggedIn('a-staff');
  clock += 15 * 24 * 60 * 60e3;
  assert.equal((await d.get('/api/bootstrap')).status, 401);
});
