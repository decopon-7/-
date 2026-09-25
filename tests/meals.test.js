import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { mealFlags, nextStatus, checkSnapshot, isStale } from '../app/meals.js';
import { createApi } from '../worker/api.js';
import { hashPassword } from '../worker/auth.js';
import { createTestDb } from './d1-shim.js';

// ---------- 照らし合わせ ----------

test('タップで 未 → 家庭で食べた → 除去 → 未', () => {
  assert.deepEqual([undefined, 'none', 'ok', 'ng'].map(nextStatus), ['ok', 'ok', 'ng', 'none']);
});

test('献立に未経験・除去の食材がある子だけが出る', () => {
  const kids = [{ id: 'a' }, { id: 'b' }, { id: 'c' }];
  const childFoods = [
    { childId: 'a', foodId: 'carrot', status: 'ok' }, { childId: 'a', foodId: 'rice', status: 'ok' },
    { childId: 'b', foodId: 'rice', status: 'ok' },
    { childId: 'c', foodId: 'rice', status: 'ok' }, { childId: 'c', foodId: 'carrot', status: 'ng' },
  ];
  assert.deepEqual(mealFlags(kids, childFoods, ['rice', 'carrot']), [
    { childId: 'b', untried: ['carrot'], excluded: [] },
    { childId: 'c', untried: [], excluded: ['carrot'] },
  ]);
  assert.deepEqual(mealFlags(kids, childFoods, []), []);
});

test('確認のあとで献立・食べた食材が変わると「変更あり」になる。並び順だけの違いは変更にしない', () => {
  const kids = [{ id: 'a' }, { id: 'b' }];
  const saved = checkSnapshot(kids, [], ['x', 'y']);
  assert.equal(isStale(saved, checkSnapshot([{ id: 'b' }, { id: 'a' }], [], ['y', 'x'])), false);
  assert.equal(isStale(saved, checkSnapshot(kids, [], ['x'])), true);
  assert.equal(isStale(saved, checkSnapshot(kids, [{ childId: 'a', foodId: 'x', status: 'ok' }], ['x', 'y'])), true);
});

// ---------- API ----------

const ORIGIN = 'https://hoiku.example';
const T0 = Date.UTC(2026, 8, 23, 2, 0); // 日本時間 11:00
const DAY = '2026-09-23';
const HASH = await hashPassword('password123');
let db;
let handle;

beforeEach(() => {
  db = createTestDb();
  handle = createApi({ db, now: () => T0 });
  const s = db.sqlite;
  for (const f of ['A', 'B']) {
    s.prepare('INSERT INTO facilities VALUES (?, ?, ?)').run(`fac${f}-0001`, `園${f}`, T0);
    s.prepare('INSERT INTO classes (id, facility_id, name, age, interval_min) VALUES (?, ?, ?, 0, 5)')
      .run(`cls${f}-0001`, `fac${f}-0001`, '0歳児');
    s.prepare('INSERT INTO users (id, facility_id, login_id, name, role, password_hash, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)')
      .run(`usr${f}-admin`, `fac${f}-0001`, `${f.toLowerCase()}-admin`, `${f}管理者`, 'admin', HASH, T0);
  }
  for (const [kid, name] of [['kidA-0001', 'あ'], ['kidA-0002', 'い']]) {
    s.prepare('INSERT INTO children (id, facility_id, class_id, name, created_at) VALUES (?, ?, ?, ?, ?)')
      .run(kid, 'facA-0001', 'clsA-0001', name, T0);
  }
  for (const u of ['usrA-sato', 'usrA-suzu']) {
    s.prepare("INSERT INTO users (id, facility_id, login_id, name, role, password_hash, created_at) VALUES (?, 'facA-0001', ?, ?, 'staff', '!', ?)")
      .run(u, `staff:${u}`, u, T0);
  }
});

function client() {
  let cookie = '';
  const call = async (method, path, data) => {
    const res = await handle(new Request(ORIGIN + path, {
      method,
      headers: { ...(data !== undefined ? { 'content-type': 'application/json' } : {}), ...(cookie ? { cookie } : {}), origin: ORIGIN },
      body: data !== undefined ? JSON.stringify(data) : undefined,
    }));
    const set = res.headers.get('set-cookie');
    if (set) cookie = set.split(';')[0];
    return { status: res.status, body: await res.json() };
  };
  return { get: (p) => call('GET', p), post: (p, d = {}) => call('POST', p, d), patch: (p, d = {}) => call('PATCH', p, d) };
}

async function device(loginId = 'a-admin', unlock = false) {
  const c = client();
  assert.equal((await c.post('/api/device/register', { loginId, password: 'password123', deviceName: '給食室' })).status, 200);
  if (unlock) assert.equal((await c.post('/api/admin/unlock', { loginId, password: 'password123' })).status, 200);
  return c;
}

async function foodIds(c) {
  const foods = (await c.get(`/api/meals?day=${DAY}`)).body.foods;
  return Object.fromEntries(foods.map((f) => [f.name, f.id]));
}

test('食材の登録は管理者モードだけ。まとめて登録でき、同じ名前は飛ばす', async () => {
  const staff = await device();
  assert.equal((await staff.post('/api/admin/foods', { names: ['米'] })).status, 403);
  const admin = await device('a-admin', true);
  assert.deepEqual((await admin.post('/api/admin/foods', { names: ['米', 'にんじん', '米'], category: '野菜' })).body, { added: 2 });
  assert.deepEqual((await admin.post('/api/admin/foods', { names: ['にんじん', 'たまご'] })).body, { added: 1 });
  const f = await foodIds(admin);
  await admin.patch(`/api/admin/foods/${f['たまご']}`, { active: false });
  const foods = (await admin.get(`/api/meals?day=${DAY}`)).body.foods;
  assert.equal(foods.find((x) => x.name === 'たまご').active, false);
});

test('献立・食べた食材・配膳前の確認（2名）の流れ', async () => {
  const admin = await device('a-admin', true);
  await admin.post('/api/admin/foods', { names: ['米', 'にんじん', 'たまご'] });
  const f = await foodIds(admin);
  const c = await device();

  // 献立がない日は確認できない
  const noMenu = await c.post('/api/meals/check', { id: 'mchk-000001', classId: 'clsA-0001', checkerIds: ['usrA-sato', 'usrA-suzu'] });
  assert.equal(noMenu.body.error, 'no_menu');

  for (const food of ['米', 'にんじん']) {
    assert.equal((await c.post('/api/meals/menu', { classId: 'clsA-0001', day: DAY, foodId: f[food], on: true, recorderId: 'usrA-sato' })).status, 200);
  }
  for (const [kid, food, status] of [['kidA-0001', '米', 'ok'], ['kidA-0001', 'にんじん', 'ok'], ['kidA-0002', '米', 'ok'], ['kidA-0002', 'にんじん', 'ng']]) {
    assert.equal((await c.post('/api/meals/child-food', { childId: kid, foodId: f[food], status, recorderId: 'usrA-suzu' })).status, 200);
  }

  // 同じ人を2回は選べない
  const same = await c.post('/api/meals/check', { id: 'mchk-000002', classId: 'clsA-0001', checkerIds: ['usrA-sato', 'usrA-sato'] });
  assert.equal(same.body.error, 'two_checkers_required');

  const ok = await c.post('/api/meals/check', { id: 'mchk-000003', classId: 'clsA-0001', checkerIds: ['usrA-sato', 'usrA-suzu'] });
  assert.equal(ok.status, 200);
  assert.deepEqual(ok.body.snapshot.flagged, [{ childId: 'kidA-0002', untried: [], excluded: [f['にんじん']] }]);

  // 確認の記録は、あとで食べた食材を変えても変わらない
  await c.post('/api/meals/child-food', { childId: 'kidA-0002', foodId: f['にんじん'], status: 'none', recorderId: 'usrA-sato' });
  const meals = (await c.get(`/api/meals?day=${DAY}`)).body;
  assert.equal(meals.checks.length, 1);
  assert.deepEqual(meals.checks[0].snapshot.flagged[0].excluded, [f['にんじん']]);
  assert.deepEqual([meals.checks[0].checker1Id, meals.checks[0].checker2Id], ['usrA-sato', 'usrA-suzu']);
  assert.deepEqual(meals.menus[0].foodIds.sort(), [f['米'], f['にんじん']].sort());
  assert.ok(!meals.childFoods.some((x) => x.childId === 'kidA-0002' && x.foodId === f['にんじん']));

  // 状態を変えた履歴は消えずに残る（新しい順）
  const hist = (await c.get('/api/meals/history?childId=kidA-0002')).body.history;
  assert.deepEqual(hist.map((h) => h.status), ['none', 'ng', 'ok']);
  assert.equal(hist[0].deviceName, '給食室');
});

test('別の園の食材・子ども・クラス・職員には触れない', async () => {
  const adminA = await device('a-admin', true);
  await adminA.post('/api/admin/foods', { names: ['米'] });
  const fA = await foodIds(adminA);
  const b = await device('b-admin', true);

  assert.equal((await b.get(`/api/meals?day=${DAY}`)).body.foods.length, 0);
  assert.equal((await b.patch(`/api/admin/foods/${fA['米']}`, { name: 'x' })).status, 404);
  assert.equal((await b.post('/api/meals/menu', { classId: 'clsA-0001', day: DAY, foodId: 'x', on: true, recorderId: 'usrB-admin' })).body.error, 'class_not_found');
  await b.post('/api/admin/foods', { names: ['パン'] });
  const fB = await foodIds(b);
  assert.equal((await b.post('/api/meals/menu', { classId: 'clsB-0001', day: DAY, foodId: fA['米'], on: true, recorderId: 'usrB-admin' })).body.error, 'food_not_found');
  assert.equal((await b.post('/api/meals/child-food', { childId: 'kidA-0001', foodId: fB['パン'], status: 'ok', recorderId: 'usrB-admin' })).body.error, 'child_not_found');
  assert.equal((await b.post('/api/meals/check', { id: 'mchk-B00001', classId: 'clsB-0001', checkerIds: ['usrA-sato', 'usrB-admin'] })).body.error, 'recorder_not_found');
  assert.equal((await b.get('/api/meals/history?childId=kidA-0001')).body.error, 'child_not_found');
  // A園の職員を記録者にして自分の園の記録をすることもできない
  const a = await device();
  assert.equal((await a.post('/api/meals/child-food', { childId: 'kidA-0001', foodId: fA['米'], status: 'ok', recorderId: 'usrB-admin' })).body.error, 'recorder_not_found');
});

test('登録していない端末は給食のデータも読めない', async () => {
  assert.equal((await client().get(`/api/meals?day=${DAY}`)).status, 401);
});

test('献立は食材ごとの追加・削除。同時に複数の食材を操作しても、順序に関係なく結果が正しい', async () => {
  const admin = await device('a-admin', true);
  await admin.post('/api/admin/foods', { names: ['米', 'にんじん', 'たまご'] });
  const f = await foodIds(admin);
  const c = await device();

  // 違う食材への追加は、届く順番が入れ替わっても（Promise.all）全部残る
  await Promise.all([
    c.post('/api/meals/menu', { classId: 'clsA-0001', day: DAY, foodId: f['たまご'], on: true, recorderId: 'usrA-sato' }),
    c.post('/api/meals/menu', { classId: 'clsA-0001', day: DAY, foodId: f['にんじん'], on: true, recorderId: 'usrA-sato' }),
    c.post('/api/meals/menu', { classId: 'clsA-0001', day: DAY, foodId: f['米'], on: true, recorderId: 'usrA-sato' }),
  ]);
  const menu1 = (await c.get(`/api/meals?day=${DAY}`)).body.menus[0];
  assert.deepEqual(menu1.foodIds.sort(), [f['米'], f['にんじん'], f['たまご']].sort());

  // 同じ食材を追加・削除しても二重にならず、片付ければちゃんと消える
  await c.post('/api/meals/menu', { classId: 'clsA-0001', day: DAY, foodId: f['米'], on: true, recorderId: 'usrA-sato' });
  await c.post('/api/meals/menu', { classId: 'clsA-0001', day: DAY, foodId: f['にんじん'], on: false, recorderId: 'usrA-sato' });
  const menu2 = (await c.get(`/api/meals?day=${DAY}`)).body.menus[0];
  assert.deepEqual(menu2.foodIds.sort(), [f['米'], f['たまご']].sort());
});
