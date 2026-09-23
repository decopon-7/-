// 午睡チェックの判定ロジック（画面から切り離してテストできるようにしている）

export const POSTURES = {
  supine: { label: '仰向け', short: '仰' },
  right: { label: '右向き', short: '右' },
  left: { label: '左向き', short: '左' },
  prone: { label: 'うつぶせ', short: 'う' },
};

// 確認間隔の初期値（分）。園のマニュアル・自治体の指針に合わせて設定画面で変更する前提
export const DEFAULT_INTERVALS = { 0: 5, 1: 10, 2: 10 };

// 「まもなく確認」とみなす残り時間
export const SOON_MS = 60 * 1000;

export function intervalMinutes(age, intervals = DEFAULT_INTERVALS) {
  const v = intervals[age] ?? intervals[String(age)];
  return Number.isFinite(v) && v > 0 ? v : 5;
}

// 子ども1人の、最後の午睡セッションを返す
export function lastSession(sessions) {
  return sessions && sessions.length ? sessions[sessions.length - 1] : null;
}

// 状態: 'before'（まだ寝ていない） / 'awake'（起床済み） / 'ok' / 'soon' / 'overdue'
export function childStatus(sessions, now, intervalMin) {
  const s = lastSession(sessions);
  if (!s) return { state: 'before' };
  if (s.end != null) return { state: 'awake', session: s };
  const last = s.checks.length ? s.checks[s.checks.length - 1] : null;
  const base = last ? last.t : s.start;
  const due = base + intervalMin * 60 * 1000;
  const remain = due - now;
  let state = 'ok';
  if (remain <= 0) state = 'overdue';
  else if (remain <= SOON_MS) state = 'soon';
  return { state, session: s, last, due, remain };
}

export function startNap(sessions, now) {
  const s = lastSession(sessions);
  if (s && s.end == null) return sessions;
  return [...(sessions || []), { start: now, end: null, checks: [] }];
}

export function recordCheck(sessions, now, posture, staff, fixed = false) {
  if (!POSTURES[posture]) throw new Error(`unknown posture: ${posture}`);
  const s = lastSession(sessions);
  if (!s || s.end != null) return sessions;
  const check = { t: now, posture, staff: staff || '' };
  if (fixed) check.fixed = true;
  return [...sessions.slice(0, -1), { ...s, checks: [...s.checks, check] }];
}

export function endNap(sessions, now) {
  const s = lastSession(sessions);
  if (!s || s.end != null) return sessions;
  return [...sessions.slice(0, -1), { ...s, end: now }];
}

// 直前の確認を取り消す（押し間違い用）
export function undoLastCheck(sessions) {
  const s = lastSession(sessions);
  if (!s || s.end != null || !s.checks.length) return sessions;
  return [...sessions.slice(0, -1), { ...s, checks: s.checks.slice(0, -1) }];
}

export function summarize(statuses) {
  const c = { sleeping: 0, soon: 0, overdue: 0, awake: 0, before: 0 };
  for (const st of statuses) {
    if (st.state === 'ok' || st.state === 'soon' || st.state === 'overdue') c.sleeping++;
    if (st.state === 'soon') c.soon++;
    if (st.state === 'overdue') c.overdue++;
    if (st.state === 'awake') c.awake++;
    if (st.state === 'before') c.before++;
  }
  return c;
}

// 記録表用：確認間隔ごとの時間枠に区切った表を作る
// rows: [{ child, cells: [{ posture, fixed, staff } | null, ...] }]
// まだ寝ている子がいる間は、現在時刻の枠まで表を伸ばす
export function buildRecordTable(children, napsByChild, intervalMin, now = Date.now()) {
  const all = [];
  for (const ch of children) {
    for (const s of napsByChild[ch.id] || []) {
      all.push(s.start);
      all.push(s.end != null ? s.end : now);
      for (const c of s.checks) all.push(c.t);
    }
  }
  if (!all.length) return { slots: [], rows: [] };
  const step = intervalMin * 60 * 1000;
  const first = Math.min(...all);
  const base = Math.floor(first / step) * step;
  const count = Math.floor((Math.max(...all) - base) / step) + 1;
  const slots = Array.from({ length: count }, (_, i) => base + i * step);
  const rows = children.map((child) => {
    const cells = Array(count).fill(null);
    const naps = napsByChild[child.id] || [];
    for (const s of naps) {
      for (const c of s.checks) {
        cells[Math.floor((c.t - base) / step)] = c;
      }
    }
    return { child, naps, cells };
  });
  return { slots, rows };
}

export function fmtTime(t) {
  const d = new Date(t);
  return `${d.getHours()}:${String(d.getMinutes()).padStart(2, '0')}`;
}

export function fmtDuration(ms) {
  const sec = Math.max(0, Math.round(Math.abs(ms) / 1000));
  return `${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, '0')}`;
}

export function dateKey(t) {
  const d = new Date(t);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
