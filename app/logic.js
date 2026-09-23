// 午睡チェックの判定ロジック（画面から切り離してテストできるようにしている）

// 体位は紙の午睡チェック表と同じく矢印で表す
export const POSTURES = {
  supine: { label: '仰向け', short: '↑' },
  right: { label: '右向き', short: '→' },
  left: { label: '左向き', short: '←' },
  prone: { label: 'うつぶせ', short: '↓' },
};

// うつぶせを仰向けに直した記録の表記（「→」は右向きと紛らわしいので使わない）
export const FIXED_SHORT = '↓⇒↑';

// 「まもなく確認」とみなす残り時間
export const SOON_MS = 60 * 1000;

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
// rows: [{ child, naps, cells: [{ t, posture, fixed, recorderId } | null, ...] }]
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
