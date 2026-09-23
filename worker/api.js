// /api/* の処理。db は Cloudflare D1（テストでは Node の SQLite で代用）
import {
  hashPassword, verifyPassword, burnPasswordTime, newToken, sha256Hex, PASSWORD_MIN,
} from './auth.js';

const SESSION_MS = 14 * 24 * 60 * 60 * 1000;
const COOKIE = 'hs';
const FAIL_WINDOW_MS = 15 * 60 * 1000;
const FAIL_LIMIT = 5;
const JST_MS = 9 * 60 * 60 * 1000;
// 送信待ちの操作は、オフラインが長引いても受け付けられるよう少し広めに許す
const OP_PAST_MS = 36 * 60 * 60 * 1000;
const OP_FUTURE_MS = 5 * 60 * 1000;
const MAX_OPS = 200;
const POSTURES = ['supine', 'right', 'left', 'prone'];

export function dayOf(t) {
  return new Date(t + JST_MS).toISOString().slice(0, 10);
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

// 文字列の入力チェック
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

  async function audit(me, action, detail) {
    await run('INSERT INTO audit_log (facility_id, user_id, action, detail, at) VALUES (?, ?, ?, ?, ?)',
      me.facility_id, me.id, action, detail ? JSON.stringify(detail) : null, now());
  }

  async function currentUser(request) {
    const token = readCookie(request, COOKIE);
    if (!token) return null;
    const row = await one(
      `SELECT u.id, u.facility_id, u.name, u.role, u.login_id, s.token_hash
         FROM sessions s JOIN users u ON u.id = s.user_id
        WHERE s.token_hash = ? AND s.expires_at > ? AND u.active = 1`,
      await sha256Hex(token), now());
    return row || null;
  }

  // ---------- ログイン ----------

  async function login(request) {
    const b = await body(request);
    const loginId = typeof b.loginId === 'string' ? b.loginId.trim().toLowerCase() : '';
    const password = typeof b.password === 'string' ? b.password : '';
    if (!loginId || !password) fail(400, 'invalid_input');

    const t = now();
    const fails = await one('SELECT COUNT(*) AS n FROM login_failures WHERE login_id = ? AND at > ?',
      loginId, t - FAIL_WINDOW_MS);
    if (fails.n >= FAIL_LIMIT) fail(429, 'too_many_attempts');

    const user = await one('SELECT * FROM users WHERE login_id = ? AND active = 1', loginId);
    const ok = user ? await verifyPassword(password, user.password_hash) : (await burnPasswordTime(password), false);
    if (!ok) {
      await run('INSERT INTO login_failures (login_id, at) VALUES (?, ?)', loginId, t);
      fail(401, 'wrong_credentials');
    }
    await run('DELETE FROM login_failures WHERE login_id = ? OR at < ?', loginId, t - FAIL_WINDOW_MS);
    await run('DELETE FROM sessions WHERE expires_at < ?', t);

    const token = newToken();
    await run('INSERT INTO sessions (token_hash, user_id, facility_id, created_at, expires_at) VALUES (?, ?, ?, ?, ?)',
      await sha256Hex(token), user.id, user.facility_id, t, t + SESSION_MS);
    return json({ ok: true }, 200, { 'set-cookie': sessionCookie(token, SESSION_MS / 1000) });
  }

  async function logout(me) {
    await run('DELETE FROM sessions WHERE token_hash = ?', me.token_hash);
    return json({ ok: true }, 200, { 'set-cookie': sessionCookie('', 0) });
  }

  async function changeOwnPassword(me, request) {
    const b = await body(request);
    const user = await one('SELECT password_hash FROM users WHERE id = ?', me.id);
    if (typeof b.current !== 'string' || !(await verifyPassword(b.current, user.password_hash))) {
      fail(400, 'wrong_password');
    }
    const next = password(b.next);
    await run('UPDATE users SET password_hash = ? WHERE id = ?', await hashPassword(next), me.id);
    // 他の端末のログインは切る
    await run('DELETE FROM sessions WHERE user_id = ? AND token_hash != ?', me.id, me.token_hash);
    await audit(me, 'change_own_password');
    return json({ ok: true });
  }

  function password(v) {
    if (typeof v !== 'string' || v.length < PASSWORD_MIN || v.length > 128) fail(400, 'weak_password');
    return v;
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
      `SELECT id, name, active${me.role === 'admin' ? ', login_id AS loginId, role' : ''} FROM users
        WHERE facility_id = ? ORDER BY name`, me.facility_id);
    return json({
      me: { id: me.id, name: me.name, role: me.role, loginId: me.login_id },
      facility,
      classes: classes.map((c) => ({ ...c, active: !!c.active })),
      children: children.map((c) => ({ ...c, active: !!c.active })),
      staff: staff.map((s) => ({ ...s, active: !!s.active })),
    });
  }

  async function napsOf(me, day) {
    const naps = await all(
      `SELECT id, child_id AS childId, start_at AS start, end_at AS end FROM naps
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
    return [...byNap.values()];
  }

  async function getNaps(me, url) {
    const day = url.searchParams.get('day') || dayOf(now());
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) fail(400, 'invalid_input');
    return json({ day, naps: await napsOf(me, day) });
  }

  // ---------- 午睡の操作 ----------

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

  async function applyOp(me, op) {
    switch (op?.type) {
      case 'startNap': {
        const t = opTime(op.t);
        const child = await one('SELECT id FROM children WHERE id = ? AND facility_id = ? AND active = 1',
          id(op.childId), me.facility_id);
        if (!child) fail(404, 'child_not_found');
        await run(`INSERT INTO naps (id, facility_id, child_id, day, start_at, started_by)
                   VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO NOTHING`,
          id(op.id), me.facility_id, child.id, dayOf(t), t, me.id);
        return;
      }
      case 'check': {
        const t = opTime(op.t);
        if (!POSTURES.includes(op.posture)) fail(400, 'invalid_input');
        const nap = await napOfFacility(me, op.napId);
        if (nap.end_at != null && nap.end_at < t) fail(409, 'nap_already_ended');
        const recorder = await one('SELECT id FROM users WHERE id = ? AND facility_id = ?',
          id(op.recorderId), me.facility_id);
        if (!recorder) fail(404, 'recorder_not_found');
        await run(`INSERT INTO nap_checks (id, facility_id, nap_id, t, posture, fixed, recorder_id, entered_by, created_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO NOTHING`,
          id(op.id), me.facility_id, nap.id, t, op.posture, op.fixed ? 1 : 0, recorder.id, me.id, now());
        return;
      }
      case 'undoCheck': {
        await run(`UPDATE nap_checks SET deleted_at = ?, deleted_by = ?
                    WHERE id = ? AND facility_id = ? AND deleted_at IS NULL`,
          now(), me.id, id(op.checkId), me.facility_id);
        return;
      }
      case 'endNap': {
        const t = opTime(op.t);
        const nap = await napOfFacility(me, op.napId);
        // 2台で同時に午睡開始された場合に備え、その子の開いている午睡をすべて閉じる
        await run(`UPDATE naps SET end_at = ?, ended_by = ?
                    WHERE facility_id = ? AND child_id = ? AND end_at IS NULL AND start_at <= ?`,
          t, me.id, me.facility_id, nap.child_id, t);
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
    const day = dayOf(now());
    return json({ results, day, naps: await napsOf(me, day) });
  }

  // ---------- 管理（管理者のみ） ----------

  async function admin(me, request, parts) {
    if (me.role !== 'admin') fail(403, 'forbidden');
    const [resource, targetId, action] = parts;
    const method = request.method;

    if (resource === 'sessions' && targetId === 'revoke-all' && method === 'POST') {
      await run('DELETE FROM sessions WHERE facility_id = ? AND token_hash != ?', me.facility_id, me.token_hash);
      await audit(me, 'revoke_all_sessions');
      return json({ ok: true });
    }

    if (resource === 'classes') {
      const b = await body(request);
      if (method === 'POST' && !targetId) {
        const newId = crypto.randomUUID();
        await run('INSERT INTO classes (id, facility_id, name, age, interval_min, sort) VALUES (?, ?, ?, ?, ?, ?)',
          newId, me.facility_id, text(b.name), int(b.age, 0, 6), int(b.intervalMin, 1, 30), int(b.sort ?? 0, 0, 999));
        await audit(me, 'create_class', { id: newId });
        return json({ id: newId });
      }
      if (method === 'PATCH' && targetId) {
        const cur = await one('SELECT * FROM classes WHERE id = ? AND facility_id = ?', id(targetId), me.facility_id);
        if (!cur) fail(404, 'not_found');
        await run('UPDATE classes SET name = ?, age = ?, interval_min = ?, sort = ?, active = ? WHERE id = ?',
          b.name !== undefined ? text(b.name) : cur.name,
          b.age !== undefined ? int(b.age, 0, 6) : cur.age,
          b.intervalMin !== undefined ? int(b.intervalMin, 1, 30) : cur.interval_min,
          b.sort !== undefined ? int(b.sort, 0, 999) : cur.sort,
          b.active !== undefined ? (b.active ? 1 : 0) : cur.active,
          cur.id);
        await audit(me, 'update_class', { id: cur.id, ...b });
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
        const loginId = text(b.loginId, 32).toLowerCase();
        if (!/^[a-z0-9._-]{3,32}$/.test(loginId)) fail(400, 'invalid_login_id');
        if (await one('SELECT id FROM users WHERE login_id = ?', loginId)) fail(409, 'login_id_taken');
        const role = b.role === 'admin' ? 'admin' : 'staff';
        const newId = crypto.randomUUID();
        await run(`INSERT INTO users (id, facility_id, login_id, name, role, password_hash, created_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?)`,
          newId, me.facility_id, loginId, text(b.name), role, await hashPassword(password(b.password)), now());
        await audit(me, 'create_user', { id: newId, role });
        return json({ id: newId });
      }
      if (method === 'PATCH' && targetId) {
        const cur = await one('SELECT * FROM users WHERE id = ? AND facility_id = ?', id(targetId), me.facility_id);
        if (!cur) fail(404, 'not_found');
        const active = b.active !== undefined ? (b.active ? 1 : 0) : cur.active;
        const role = b.role !== undefined ? (b.role === 'admin' ? 'admin' : 'staff') : cur.role;
        // 自分自身を停止・降格して、管理者がいなくなるのを防ぐ
        if (cur.id === me.id && (!active || role !== 'admin')) fail(400, 'cannot_demote_self');
        const hash = b.password !== undefined ? await hashPassword(password(b.password)) : cur.password_hash;
        await run('UPDATE users SET name = ?, role = ?, active = ?, password_hash = ? WHERE id = ?',
          b.name !== undefined ? text(b.name) : cur.name, role, active, hash, cur.id);
        if (!active || b.password !== undefined) {
          await run('DELETE FROM sessions WHERE user_id = ?', cur.id);
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

    if (path === '/api/login' && method === 'POST') return login(request);

    const me = await currentUser(request);
    if (!me) fail(401, 'not_logged_in');

    if (path === '/api/logout' && method === 'POST') return logout(me);
    if (path === '/api/bootstrap' && method === 'GET') return bootstrap(me);
    if (path === '/api/naps' && method === 'GET') return getNaps(me, url);
    if (path === '/api/ops' && method === 'POST') return postOps(me, request);
    if (path === '/api/me/password' && method === 'POST') return changeOwnPassword(me, request);
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
