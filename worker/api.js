// /api/* の処理。db は Cloudflare D1（テストでは Node の SQLite で代用）
//
// ログインの考え方（docs/server-design.md）
// ・管理者が IDとパスワードで「園の端末」を登録する。これがセッション（1台 = 1セッション）
// ・職員は端末で名前を選ぶだけ（パスワードなし）
// ・設定の変更は、管理者がパスワードを入れて「管理者モード」にした時だけ。10分で自動で戻る
import { hashPassword, verifyPassword, burnPasswordTime, newToken, sha256Hex, PASSWORD_MIN } from './auth.js';
import { checkSnapshot } from '../app/meals.js';

const DAY_MS = 24 * 60 * 60 * 1000;
// 使っている端末は登録が続き、90日使わなかった端末は登録が切れる
const SESSION_MS = 90 * DAY_MS;
const SESSION_RENEW_MS = 60 * DAY_MS;
const ADMIN_MODE_MS = 10 * 60 * 1000;
const COOKIE = 'hs';
const FAIL_WINDOW_MS = 15 * 60 * 1000;
const FAIL_LIMIT = 5;
const JST_MS = 9 * 60 * 60 * 1000;
// 送信待ちの操作は、オフラインが長引いても受け付けられるよう少し広めに許す
const OP_PAST_MS = 36 * 60 * 60 * 1000;
const OP_FUTURE_MS = 5 * 60 * 1000;
const MAX_OPS = 200;
const POSTURES = ['supine', 'right', 'left', 'prone'];
const FOOD_CATEGORIES_MAX = 20;
// 職員（名前を選ぶだけの人）の password_hash。どのパスワードとも一致しない
const NO_PASSWORD = '!';

export function dayOf(t) {
  return new Date(t + JST_MS).toISOString().slice(0, 10);
}

// 確認間隔は年齢で決める（0歳は5分、それ以外は10分）
export function intervalForAge(age) {
  return age === 0 ? 5 : 10;
}

class HttpError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

const fail = (status, code) => { throw new HttpError(status, code); };

function json(data, status = 200, headers = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', ...headers },
  });
}

function sessionCookie(token, maxAgeSec) {
  return `${COOKIE}=${token}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=${maxAgeSec}`;
}

function readCookie(request, name) {
  const header = request.headers.get('cookie') || '';
  for (const part of header.split(';')) {
    const [k, ...v] = part.trim().split('=');
    if (k === name) return v.join('=');
  }
  return null;
}

// 入力チェック
function text(v, max = 40) {
  if (typeof v !== 'string') fail(400, 'invalid_input');
  const s = v.trim();
  if (!s || s.length > max) fail(400, 'invalid_input');
  return s;
}

function int(v, min, max) {
  if (!Number.isInteger(v) || v < min || v > max) fail(400, 'invalid_input');
  return v;
}

function id(v) {
  if (typeof v !== 'string' || !/^[A-Za-z0-9_-]{8,64}$/.test(v)) fail(400, 'invalid_input');
  return v;
}

function password(v) {
  if (typeof v !== 'string' || v.length < PASSWORD_MIN || v.length > 128) fail(400, 'weak_password');
  return v;
}

function dayParam(v) {
  if (typeof v !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(v)) fail(400, 'invalid_input');
  return v;
}

function loginIdOf(v) {
  const s = text(v, 32).toLowerCase();
  if (!/^[a-z0-9._-]{3,32}$/.test(s)) fail(400, 'invalid_login_id');
  return s;
}

async function body(request) {
  try {
    return await request.json();
  } catch {
    return fail(400, 'invalid_json');
  }
}

export function createApi({ db, now = () => Date.now() }) {
  const one = (sql, ...args) => db.prepare(sql).bind(...args).first();
  const all = async (sql, ...args) => (await db.prepare(sql).bind(...args).all()).results;
  const run = (sql, ...args) => db.prepare(sql).bind(...args).run();

  // me: 端末のセッション。user_id は端末を登録した管理者、admin_user_id は管理者モード中の管理者
  async function audit(me, action, detail) {
    await run('INSERT INTO audit_log (facility_id, user_id, action, detail, at) VALUES (?, ?, ?, ?, ?)',
      me.facility_id, me.admin_user_id || me.user_id, action,
      JSON.stringify({ device: me.device_name, ...(detail || {}) }), now());
  }

  async function currentDevice(request) {
    const token = readCookie(request, COOKIE);
    if (!token) return null;
    const t = now();
    const row = await one(
      `SELECT s.token_hash, s.user_id, s.facility_id, s.device_name, s.expires_at, s.admin_user_id, s.admin_until
         FROM sessions s JOIN users u ON u.id = s.user_id
        WHERE s.token_hash = ? AND s.expires_at > ? AND u.active = 1`,
      await sha256Hex(token), t);
    if (!row) return null;
    if (row.expires_at - t < SESSION_RENEW_MS) {
      await run('UPDATE sessions SET expires_at = ? WHERE token_hash = ?', t + SESSION_MS, row.token_hash);
    }
    row.isAdmin = !!row.admin_user_id && row.admin_until > t;
    return row;
  }

  // 管理者のIDとパスワードを確かめる（連続して間違えたら止める）
  async function checkAdminCredentials(loginIdRaw, pw, facilityId = null) {
    const loginId = typeof loginIdRaw === 'string' ? loginIdRaw.trim().toLowerCase() : '';
    if (!loginId || typeof pw !== 'string' || !pw) fail(400, 'invalid_input');
    const t = now();
    const fails = await one('SELECT COUNT(*) AS n FROM login_failures WHERE login_id = ? AND at > ?',
      loginId, t - FAIL_WINDOW_MS);
    if (fails.n >= FAIL_LIMIT) fail(429, 'too_many_attempts');

    const user = await one("SELECT * FROM users WHERE login_id = ? AND active = 1 AND role = 'admin'", loginId);
    const sameFacility = user && (!facilityId || user.facility_id === facilityId);
    const ok = sameFacility ? await verifyPassword(pw, user.password_hash) : (await burnPasswordTime(pw), false);
    if (!ok) {
      await run('INSERT INTO login_failures (login_id, at) VALUES (?, ?)', loginId, t);
      fail(401, 'wrong_credentials');
    }
    await run('DELETE FROM login_failures WHERE login_id = ? OR at < ?', loginId, t - FAIL_WINDOW_MS);
    return user;
  }

  // ---------- 端末の登録・解除 ----------

  async function registerDevice(request) {
    const b = await body(request);
    const deviceName = text(b.deviceName ?? '', 20);
    const user = await checkAdminCredentials(b.loginId, b.password);
    const t = now();
    await run('DELETE FROM sessions WHERE expires_at < ?', t);
    const token = newToken();
    await run(`INSERT INTO sessions (token_hash, user_id, facility_id, device_name, created_at, expires_at)
               VALUES (?, ?, ?, ?, ?, ?)`,
      await sha256Hex(token), user.id, user.facility_id, deviceName, t, t + SESSION_MS);
    await run('INSERT INTO audit_log (facility_id, user_id, action, detail, at) VALUES (?, ?, ?, ?, ?)',
      user.facility_id, user.id, 'register_device', JSON.stringify({ device: deviceName }), t);
    return json({ ok: true }, 200, { 'set-cookie': sessionCookie(token, SESSION_MS / 1000) });
  }

  async function unregisterDevice(me) {
    await run('DELETE FROM sessions WHERE token_hash = ?', me.token_hash);
    return json({ ok: true }, 200, { 'set-cookie': sessionCookie('', 0) });
  }

  async function adminUnlock(me, request) {
    const b = await body(request);
    const user = await checkAdminCredentials(b.loginId, b.password, me.facility_id);
    const until = now() + ADMIN_MODE_MS;
    await run('UPDATE sessions SET admin_user_id = ?, admin_until = ? WHERE token_hash = ?', user.id, until, me.token_hash);
    await audit({ ...me, admin_user_id: user.id }, 'admin_unlock');
    return json({ ok: true, adminUntil: until, adminName: user.name });
  }

  async function adminLock(me) {
    await run('UPDATE sessions SET admin_user_id = NULL, admin_until = NULL WHERE token_hash = ?', me.token_hash);
    return json({ ok: true });
  }

  // ---------- 読み取り ----------

  async function bootstrap(me) {
    const facility = await one('SELECT id, name FROM facilities WHERE id = ?', me.facility_id);
    const classes = await all(
      `SELECT id, name, age, interval_min AS intervalMin, sort, active FROM classes
        WHERE facility_id = ? ORDER BY sort, age, name`, me.facility_id);
    const children = await all(
      `SELECT id, class_id AS classId, name, sort, active FROM children
        WHERE facility_id = ? ORDER BY sort, name`, me.facility_id);
    const staff = await all(
      `SELECT id, name, active${me.isAdmin ? ", role, CASE WHEN role = 'admin' THEN login_id END AS loginId" : ''}
         FROM users WHERE facility_id = ? ORDER BY name`, me.facility_id);
    const admin = me.isAdmin
      ? { name: (await one('SELECT name FROM users WHERE id = ?', me.admin_user_id)).name, until: me.admin_until }
      : null;
    return json({
      device: { name: me.device_name },
      admin,
      facility,
      classes: classes.map((c) => ({ ...c, active: !!c.active })),
      children: children.map((c) => ({ ...c, active: !!c.active })),
      staff: staff.map((s) => ({ ...s, active: !!s.active })),
    });
  }

  async function dayData(me, day) {
    const naps = await all(
      `SELECT id, child_id AS childId, class_id AS classId, interval_min AS intervalMin,
              start_at AS start, end_at AS end FROM naps
        WHERE facility_id = ? AND day = ? ORDER BY start_at`, me.facility_id, day);
    const checks = await all(
      `SELECT c.id, c.nap_id AS napId, c.t, c.posture, c.fixed, c.recorder_id AS recorderId
         FROM nap_checks c JOIN naps n ON n.id = c.nap_id
        WHERE n.facility_id = ? AND n.day = ? AND c.deleted_at IS NULL ORDER BY c.t`, me.facility_id, day);
    const byNap = new Map(naps.map((n) => [n.id, { ...n, checks: [] }]));
    for (const c of checks) {
      const { napId, fixed, ...rest } = c;
      byNap.get(napId)?.checks.push(fixed ? { ...rest, fixed: true } : rest);
    }
    const rooms = await all(
      `SELECT id, class_id AS classId, t, temp_c10 AS tempC10, humidity, recorder_id AS recorderId
         FROM room_readings WHERE facility_id = ? AND day = ? AND deleted_at IS NULL ORDER BY t`, me.facility_id, day);
    return { day, naps: [...byNap.values()], rooms };
  }

  async function getDay(me, url) {
    const day = url.searchParams.get('day') || dayOf(now());
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) fail(400, 'invalid_input');
    return json(await dayData(me, day));
  }

  // ---------- 記録の操作 ----------

  function opTime(t) {
    const n = now();
    if (!Number.isInteger(t) || t < n - OP_PAST_MS || t > n + OP_FUTURE_MS) fail(400, 'invalid_time');
    return t;
  }

  async function napOfFacility(me, napId) {
    const nap = await one('SELECT * FROM naps WHERE id = ? AND facility_id = ?', id(napId), me.facility_id);
    if (!nap) fail(404, 'nap_not_found');
    return nap;
  }

  async function recorderOf(me, recorderId) {
    const r = await one('SELECT id FROM users WHERE id = ? AND facility_id = ?', id(recorderId), me.facility_id);
    if (!r) fail(404, 'recorder_not_found');
    return r.id;
  }

  async function applyOp(me, op) {
    switch (op?.type) {
      case 'startNap': {
        const t = opTime(op.t);
        const child = await one(
          `SELECT k.id, k.class_id, c.interval_min FROM children k JOIN classes c ON c.id = k.class_id
            WHERE k.id = ? AND k.facility_id = ? AND k.active = 1`,
          id(op.childId), me.facility_id);
        if (!child) fail(404, 'child_not_found');
        // その時点のクラスと確認間隔を残す（あとで変更しても過去の記録表が変わらないように）
        await run(`INSERT INTO naps (id, facility_id, child_id, class_id, interval_min, day, start_at, started_by)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO NOTHING`,
          id(op.id), me.facility_id, child.id, child.class_id, child.interval_min, dayOf(t), t, me.user_id);
        return;
      }
      case 'check': {
        const t = opTime(op.t);
        if (!POSTURES.includes(op.posture)) fail(400, 'invalid_input');
        const nap = await napOfFacility(me, op.napId);
        if (nap.end_at != null && nap.end_at < t) fail(409, 'nap_already_ended');
        const recorder = await recorderOf(me, op.recorderId);
        await run(`INSERT INTO nap_checks (id, facility_id, nap_id, t, posture, fixed, recorder_id, entered_by, device_name, created_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO NOTHING`,
          id(op.id), me.facility_id, nap.id, t, op.posture, op.fixed ? 1 : 0, recorder, me.user_id, me.device_name, now());
        return;
      }
      case 'undoCheck': {
        await run(`UPDATE nap_checks SET deleted_at = ?, deleted_by = ?
                    WHERE id = ? AND facility_id = ? AND deleted_at IS NULL`,
          now(), me.user_id, id(op.checkId), me.facility_id);
        return;
      }
      case 'endNap': {
        const t = opTime(op.t);
        const nap = await napOfFacility(me, op.napId);
        // 2台で同時に午睡開始された場合に備え、その子の同じ日の開いている午睡をすべて閉じる
        // （前の日に起床を押し忘れた午睡は閉じない。閉じると何十時間もの午睡になってしまうため）
        await run(`UPDATE naps SET end_at = ?, ended_by = ?
                    WHERE facility_id = ? AND child_id = ? AND day = ? AND end_at IS NULL AND start_at <= ?`,
          t, me.user_id, me.facility_id, nap.child_id, nap.day, t);
        return;
      }
      case 'room': {
        const t = opTime(op.t);
        const cls = await one('SELECT id FROM classes WHERE id = ? AND facility_id = ?', id(op.classId), me.facility_id);
        if (!cls) fail(404, 'class_not_found');
        const recorder = await recorderOf(me, op.recorderId);
        await run(`INSERT INTO room_readings (id, facility_id, class_id, day, t, temp_c10, humidity, recorder_id, device_name, created_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO NOTHING`,
          id(op.id), me.facility_id, cls.id, dayOf(t), t, int(op.tempC10, 50, 450), int(op.humidity, 0, 100),
          recorder, me.device_name, now());
        return;
      }
      case 'undoRoom': {
        await run('UPDATE room_readings SET deleted_at = ? WHERE id = ? AND facility_id = ? AND deleted_at IS NULL',
          now(), id(op.roomId), me.facility_id);
        return;
      }
      default:
        fail(400, 'unknown_op');
    }
  }

  // 1件ずつ処理し、失敗した操作はその理由を返す（他の操作は止めない）
  async function postOps(me, request) {
    const b = await body(request);
    if (!Array.isArray(b.ops) || b.ops.length > MAX_OPS) fail(400, 'invalid_input');
    const results = [];
    for (const op of b.ops) {
      try {
        await applyOp(me, op);
        results.push({ ok: true });
      } catch (e) {
        if (!(e instanceof HttpError)) throw e;
        results.push({ ok: false, error: e.code });
      }
    }
    return json({ results, ...(await dayData(me, dayOf(now()))) });
  }


  // ---------- 給食の未経験食材チェック（docs/meal-check-design.md） ----------

  async function mealContext(me, classId, day) {
    const children = await all(
      'SELECT id FROM children WHERE facility_id = ? AND class_id = ? AND active = 1', me.facility_id, classId);
    const menu = (await all('SELECT food_id FROM menu_items WHERE class_id = ? AND day = ? AND facility_id = ?',
      classId, day, me.facility_id)).map((r) => r.food_id);
    const childFoods = await all(
      `SELECT child_id AS childId, food_id AS foodId, status FROM child_foods
        WHERE facility_id = ? AND child_id IN (SELECT id FROM children WHERE facility_id = ? AND class_id = ?)`,
      me.facility_id, me.facility_id, classId);
    return { children, menu, childFoods };
  }

  async function getMeals(me, url) {
    const day = dayParam(url.searchParams.get('day') || dayOf(now()));
    const foods = await all(
      'SELECT id, name, category, sort, active FROM foods WHERE facility_id = ? ORDER BY sort, category, name', me.facility_id);
    const childFoods = await all(
      'SELECT child_id AS childId, food_id AS foodId, status FROM child_foods WHERE facility_id = ?', me.facility_id);
    const items = await all('SELECT class_id, food_id FROM menu_items WHERE facility_id = ? AND day = ?', me.facility_id, day);
    const menuRows = await all(
      'SELECT class_id AS classId, updated_at AS updatedAt, recorder_id AS recorderId FROM menus WHERE facility_id = ? AND day = ?',
      me.facility_id, day);
    const menus = menuRows.map((m) => ({ ...m, foodIds: items.filter((i) => i.class_id === m.classId).map((i) => i.food_id) }));
    const checks = (await all(
      `SELECT id, class_id AS classId, t, checker1_id AS checker1Id, checker2_id AS checker2Id, snapshot
         FROM meal_checks WHERE facility_id = ? AND day = ? ORDER BY t`, me.facility_id, day))
      .map((c) => ({ ...c, snapshot: JSON.parse(c.snapshot) }));
    return json({ day, foods: foods.map((f) => ({ ...f, active: !!f.active })), childFoods, menus, checks });
  }

  async function classOfFacility(me, classId) {
    const c = await one('SELECT id FROM classes WHERE id = ? AND facility_id = ?', id(classId), me.facility_id);
    if (!c) fail(404, 'class_not_found');
    return c.id;
  }

  // 献立は「食材ごとに1つ増やす／減らす」操作にしている（丸ごと置き換えではない）。
  // 全食材を毎回まるごと送る作りだと、連続でタップした時にあとから送ったはずの内容が
  // 消えることがあった（実際に確認して直した）。1件ずつなら、届く順番が入れ替わっても結果は変わらない
  async function toggleMenuFood(me, request) {
    const b = await body(request);
    const classId = await classOfFacility(me, b.classId);
    const day = dayParam(b.day);
    const food = await one('SELECT id FROM foods WHERE id = ? AND facility_id = ?', id(b.foodId), me.facility_id);
    if (!food) fail(404, 'food_not_found');
    const recorder = await recorderOf(me, b.recorderId);
    if (b.on) {
      await run(`INSERT INTO menu_items (facility_id, class_id, day, food_id) VALUES (?, ?, ?, ?)
                 ON CONFLICT(class_id, day, food_id) DO NOTHING`, me.facility_id, classId, day, food.id);
    } else {
      await run('DELETE FROM menu_items WHERE class_id = ? AND day = ? AND food_id = ? AND facility_id = ?',
        classId, day, food.id, me.facility_id);
    }
    await run(`INSERT INTO menus (facility_id, class_id, day, updated_at, recorder_id, device_name) VALUES (?, ?, ?, ?, ?, ?)
               ON CONFLICT(class_id, day) DO UPDATE SET updated_at = excluded.updated_at,
                 recorder_id = excluded.recorder_id, device_name = excluded.device_name`,
      me.facility_id, classId, day, now(), recorder, me.device_name);
    return json({ ok: true });
  }

  async function setChildFood(me, request) {
    const b = await body(request);
    const child = await one('SELECT id FROM children WHERE id = ? AND facility_id = ?', id(b.childId), me.facility_id);
    if (!child) fail(404, 'child_not_found');
    const food = await one('SELECT id FROM foods WHERE id = ? AND facility_id = ?', id(b.foodId), me.facility_id);
    if (!food) fail(404, 'food_not_found');
    if (!['none', 'ok', 'ng'].includes(b.status)) fail(400, 'invalid_input');
    const recorder = await recorderOf(me, b.recorderId);
    const t = now();
    if (b.status === 'none') {
      await run('DELETE FROM child_foods WHERE child_id = ? AND food_id = ?', child.id, food.id);
    } else {
      await run(`INSERT INTO child_foods (child_id, food_id, facility_id, status, updated_at) VALUES (?, ?, ?, ?, ?)
                 ON CONFLICT(child_id, food_id) DO UPDATE SET status = excluded.status, updated_at = excluded.updated_at`,
        child.id, food.id, me.facility_id, b.status, t);
    }
    await run(`INSERT INTO child_food_log (facility_id, child_id, food_id, status, recorder_id, device_name, at)
               VALUES (?, ?, ?, ?, ?, ?, ?)`, me.facility_id, child.id, food.id, b.status, recorder, me.device_name, t);
    return json({ ok: true });
  }

  // 配膳前の確認（2名）。対象の子・食材はサーバーで計算し直して残す
  async function mealCheck(me, request) {
    const b = await body(request);
    const classId = await classOfFacility(me, b.classId);
    if (!Array.isArray(b.checkerIds) || b.checkerIds.length !== 2) fail(400, 'two_checkers_required');
    const [c1, c2] = [await recorderOf(me, b.checkerIds[0]), await recorderOf(me, b.checkerIds[1])];
    if (c1 === c2) fail(400, 'two_checkers_required');
    const day = dayOf(now());
    const ctx = await mealContext(me, classId, day);
    if (!ctx.menu.length) fail(400, 'no_menu');
    const snapshot = checkSnapshot(ctx.children, ctx.childFoods, ctx.menu);
    await run(`INSERT INTO meal_checks (id, facility_id, class_id, day, t, checker1_id, checker2_id, device_name, snapshot, created_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO NOTHING`,
      id(b.id), me.facility_id, classId, day, now(), c1, c2, me.device_name, JSON.stringify(snapshot), now());
    return json({ ok: true, snapshot });
  }

  async function childFoodHistory(me, url) {
    const child = await one('SELECT id FROM children WHERE id = ? AND facility_id = ?',
      id(url.searchParams.get('childId') || ''), me.facility_id);
    if (!child) fail(404, 'child_not_found');
    const rows = await all(
      `SELECT food_id AS foodId, status, recorder_id AS recorderId, device_name AS deviceName, at
         FROM child_food_log WHERE child_id = ? AND facility_id = ? ORDER BY at DESC LIMIT 200`, child.id, me.facility_id);
    return json({ history: rows });
  }

  // ---------- 管理（管理者モードのみ） ----------

  async function admin(me, request, parts) {
    const [resource, targetId] = parts;
    const method = request.method;
    if (resource === 'unlock' && method === 'POST') return adminUnlock(me, request);
    if (resource === 'lock' && method === 'POST') return adminLock(me);
    if (!me.isAdmin) fail(403, 'admin_mode_required');
    const actor = me.admin_user_id;

    if (resource === 'devices' && method === 'GET' && !targetId) {
      const rows = await all(
        `SELECT s.token_hash, s.device_name AS name, s.created_at AS createdAt, u.name AS registeredBy
           FROM sessions s JOIN users u ON u.id = s.user_id
          WHERE s.facility_id = ? AND s.expires_at > ? ORDER BY s.created_at`, me.facility_id, now());
      // 合言葉の変換値そのものは返さず、先頭だけを端末の番号として使う
      return json({
        devices: rows.map(({ token_hash: h, ...r }) => ({ ...r, id: h.slice(0, 16), current: h === me.token_hash })),
      });
    }
    if (resource === 'devices' && method === 'POST' && targetId === 'revoke-all') {
      await run('DELETE FROM sessions WHERE facility_id = ? AND token_hash != ?', me.facility_id, me.token_hash);
      await audit(me, 'revoke_all_devices');
      return json({ ok: true });
    }
    if (resource === 'devices' && method === 'POST' && targetId) {
      if (!/^[0-9a-f]{16}$/.test(targetId)) fail(400, 'invalid_input');
      await run('DELETE FROM sessions WHERE facility_id = ? AND substr(token_hash, 1, 16) = ? AND token_hash != ?',
        me.facility_id, targetId, me.token_hash);
      await audit(me, 'revoke_device', { id: targetId });
      return json({ ok: true });
    }


    if (resource === 'foods') {
      const b = await body(request);
      if (method === 'POST' && !targetId) {
        // まとめて登録（園の食材チェック表の項目を貼り付ける）。すでにある名前は飛ばす
        if (!Array.isArray(b.names) || !b.names.length || b.names.length > 300) fail(400, 'invalid_input');
        const category = b.category ? text(b.category, FOOD_CATEGORIES_MAX) : '';
        const base = (await one('SELECT COALESCE(MAX(sort), 0) AS m FROM foods WHERE facility_id = ?', me.facility_id)).m;
        let added = 0;
        for (const [i, raw] of b.names.entries()) {
          const name = text(raw, 30);
          const r = await run(`INSERT INTO foods (id, facility_id, name, category, sort, created_at) VALUES (?, ?, ?, ?, ?, ?)
                               ON CONFLICT(facility_id, name) DO NOTHING`,
            crypto.randomUUID(), me.facility_id, name, category, base + i + 1, now());
          added += r.meta?.changes ?? 0;
        }
        await audit(me, 'create_foods', { count: added });
        return json({ added });
      }
      if (method === 'PATCH' && targetId) {
        const cur = await one('SELECT * FROM foods WHERE id = ? AND facility_id = ?', id(targetId), me.facility_id);
        if (!cur) fail(404, 'not_found');
        await run('UPDATE foods SET name = ?, category = ?, sort = ?, active = ? WHERE id = ?',
          b.name !== undefined ? text(b.name, 30) : cur.name,
          b.category !== undefined ? (b.category ? text(b.category, FOOD_CATEGORIES_MAX) : '') : cur.category,
          b.sort !== undefined ? int(b.sort, 0, 9999) : cur.sort,
          b.active !== undefined ? (b.active ? 1 : 0) : cur.active,
          cur.id);
        await audit(me, 'update_food', { id: cur.id, fields: Object.keys(b) });
        return json({ ok: true });
      }
    }

    if (resource === 'classes') {
      const b = await body(request);
      if (method === 'POST' && !targetId) {
        const newId = crypto.randomUUID();
        const age = int(b.age, 0, 6);
        await run('INSERT INTO classes (id, facility_id, name, age, interval_min, sort) VALUES (?, ?, ?, ?, ?, ?)',
          newId, me.facility_id, text(b.name), age, intervalForAge(age), int(b.sort ?? 0, 0, 999));
        await audit(me, 'create_class', { id: newId });
        return json({ id: newId });
      }
      if (method === 'PATCH' && targetId) {
        const cur = await one('SELECT * FROM classes WHERE id = ? AND facility_id = ?', id(targetId), me.facility_id);
        if (!cur) fail(404, 'not_found');
        const age = b.age !== undefined ? int(b.age, 0, 6) : cur.age;
        await run('UPDATE classes SET name = ?, age = ?, interval_min = ?, sort = ?, active = ? WHERE id = ?',
          b.name !== undefined ? text(b.name) : cur.name, age, intervalForAge(age),
          b.sort !== undefined ? int(b.sort, 0, 999) : cur.sort,
          b.active !== undefined ? (b.active ? 1 : 0) : cur.active,
          cur.id);
        await audit(me, 'update_class', { id: cur.id, fields: Object.keys(b) });
        return json({ ok: true });
      }
    }

    if (resource === 'children') {
      const b = await body(request);
      const classOk = async (classId) => {
        const c = await one('SELECT id FROM classes WHERE id = ? AND facility_id = ?', id(classId), me.facility_id);
        if (!c) fail(404, 'class_not_found');
        return c.id;
      };
      if (method === 'POST' && !targetId) {
        const newId = crypto.randomUUID();
        await run('INSERT INTO children (id, facility_id, class_id, name, sort, created_at) VALUES (?, ?, ?, ?, ?, ?)',
          newId, me.facility_id, await classOk(b.classId), text(b.name), int(b.sort ?? 0, 0, 999), now());
        await audit(me, 'create_child', { id: newId });
        return json({ id: newId });
      }
      if (method === 'PATCH' && targetId) {
        const cur = await one('SELECT * FROM children WHERE id = ? AND facility_id = ?', id(targetId), me.facility_id);
        if (!cur) fail(404, 'not_found');
        await run('UPDATE children SET name = ?, class_id = ?, sort = ?, active = ? WHERE id = ?',
          b.name !== undefined ? text(b.name) : cur.name,
          b.classId !== undefined ? await classOk(b.classId) : cur.class_id,
          b.sort !== undefined ? int(b.sort, 0, 999) : cur.sort,
          b.active !== undefined ? (b.active ? 1 : 0) : cur.active,
          cur.id);
        // 監査ログには名前を残さない（IDのみ）
        await audit(me, 'update_child', { id: cur.id, fields: Object.keys(b) });
        return json({ ok: true });
      }
    }

    if (resource === 'users') {
      const b = await body(request);
      if (method === 'POST' && !targetId) {
        const newId = crypto.randomUUID();
        if (b.role === 'admin') {
          // 管理者：端末の登録と管理者モードに使うIDとパスワードを持つ
          const loginId = loginIdOf(b.loginId);
          if (await one('SELECT id FROM users WHERE login_id = ?', loginId)) fail(409, 'login_id_taken');
          await run(`INSERT INTO users (id, facility_id, login_id, name, role, password_hash, created_at)
                     VALUES (?, ?, ?, ?, 'admin', ?, ?)`,
            newId, me.facility_id, loginId, text(b.name), await hashPassword(password(b.password)), now());
        } else {
          // 職員：名前を選ぶだけ。ログインIDは内部用の値にしておく
          await run(`INSERT INTO users (id, facility_id, login_id, name, role, password_hash, created_at)
                     VALUES (?, ?, ?, ?, 'staff', ?, ?)`,
            newId, me.facility_id, `staff:${newId}`, text(b.name), NO_PASSWORD, now());
        }
        await audit(me, 'create_user', { id: newId, role: b.role === 'admin' ? 'admin' : 'staff' });
        return json({ id: newId });
      }
      if (method === 'PATCH' && targetId) {
        const cur = await one('SELECT * FROM users WHERE id = ? AND facility_id = ?', id(targetId), me.facility_id);
        if (!cur) fail(404, 'not_found');
        const active = b.active !== undefined ? (b.active ? 1 : 0) : cur.active;
        // 自分自身を停止して、管理者がいなくなるのを防ぐ
        if (cur.id === actor && !active) fail(400, 'cannot_demote_self');
        let hash = cur.password_hash;
        if (b.password !== undefined) {
          if (cur.role !== 'admin') fail(400, 'staff_has_no_password');
          hash = await hashPassword(password(b.password));
        }
        await run('UPDATE users SET name = ?, active = ?, password_hash = ? WHERE id = ?',
          b.name !== undefined ? text(b.name) : cur.name, active, hash, cur.id);
        // 管理者を停止した時・パスワードを変えた時は、その人が登録した端末の登録も切る
        if (cur.role === 'admin' && (!active || b.password !== undefined)) {
          await run('DELETE FROM sessions WHERE user_id = ? AND token_hash != ?', cur.id, me.token_hash);
        }
        await audit(me, 'update_user', { id: cur.id, fields: Object.keys(b) });
        return json({ ok: true });
      }
    }

    return fail(404, 'not_found');
  }

  // ---------- 振り分け ----------

  async function route(request) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, '');
    const method = request.method;

    // 書き込みは同じサイトからのものだけ受け付ける
    if (method !== 'GET' && method !== 'HEAD') {
      const origin = request.headers.get('origin');
      if (origin && origin !== url.origin) fail(403, 'bad_origin');
      if (!(request.headers.get('content-type') || '').includes('application/json')) fail(415, 'json_required');
    }

    if (path === '/api/device/register' && method === 'POST') return registerDevice(request);

    const me = await currentDevice(request);
    if (!me) fail(401, 'not_registered');

    if (path === '/api/device/unregister' && method === 'POST') return unregisterDevice(me);
    if (path === '/api/bootstrap' && method === 'GET') return bootstrap(me);
    if (path === '/api/day' && method === 'GET') return getDay(me, url);
    if (path === '/api/ops' && method === 'POST') return postOps(me, request);
    if (path === '/api/meals' && method === 'GET') return getMeals(me, url);
    if (path === '/api/meals/menu' && method === 'POST') return toggleMenuFood(me, request);
    if (path === '/api/meals/child-food' && method === 'POST') return setChildFood(me, request);
    if (path === '/api/meals/check' && method === 'POST') return mealCheck(me, request);
    if (path === '/api/meals/history' && method === 'GET') return childFoodHistory(me, url);
    if (path.startsWith('/api/admin/')) return admin(me, request, path.slice('/api/admin/'.length).split('/'));
    return fail(404, 'not_found');
  }

  return async function handle(request) {
    try {
      return await route(request);
    } catch (e) {
      if (e instanceof HttpError) return json({ error: e.code }, e.status);
      console.error(e);
      return json({ error: 'server_error' }, 500);
    }
  };
}
