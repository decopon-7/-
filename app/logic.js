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
// until: 起床していない午睡を、どこまで寝ていたものとして扱うか
//   今日の表は現在時刻を渡す。過去の日は null を渡し、最後の確認までで止める
//   （起床の押し忘れがあっても、記録のない時間まで表を伸ばさない）
// rows: [{ child, naps, unclosed, cells: [{ checks: [{ t, posture, fixed?, recorderId, late }], missing }] }]
//   late: 前の確認（または入眠）から確認間隔より長く空いた確認
//         表に出る「分」で比べる（12:30→12:35 は遅れなし、12:30→12:36 は遅れ）。秒の差で印がつくと表と食い違うため
//   missing: 確認が遅れていた時間にかかる枠で、確認の記録がない
export function buildRecordTable(children, napsByChild, intervalMin, until) {
  const endOf = (s) => {
    if (s.end != null) return until == null ? s.end : Math.min(s.end, until);
    if (until != null) return until;
    return s.checks.length ? Math.max(...s.checks.map((c) => c.t)) : s.start;
  };
  const all = [];
  for (const ch of children) {
    for (const s of napsByChild[ch.id] || []) {
      all.push(s.start, endOf(s));
      for (const c of s.checks) all.push(c.t);
    }
  }
  if (!all.length) return { slots: [], rows: [] };
  const step = intervalMin * 60 * 1000;
  // 時間枠はその日の0時から数える（7分など半端な間隔でも見出しの時刻がそろうように）
  const first = Math.min(...all);
  const midnight = new Date(first).setHours(0, 0, 0, 0);
  const base = midnight + Math.floor((first - midnight) / step) * step;
  const count = Math.floor((Math.max(...all) - base) / step) + 1;
  const slots = Array.from({ length: count }, (_, i) => base + i * step);
  const rows = children.map((child) => {
    const naps = napsByChild[child.id] || [];
    const cells = slots.map(() => ({ checks: [], missing: false }));
    for (const s of naps) {
      let prev = s.start;
      for (const c of [...s.checks].sort((a, b) => a.t - b.t)) {
        cells[Math.floor((c.t - base) / step)].checks.push({ ...c, late: minutesBetween(prev, c.t) > intervalMin });
        prev = c.t;
      }
    }
    // 「未」は、確認が遅れていた時間（前の確認から間隔が過ぎてから、次の確認・起床まで）にかかる枠
    // 枠の区切りと確認の時刻がずれているだけの枠（12:30入眠→12:35確認 など）には付けない
    const overdue = [];
    for (const s of naps) {
      const times = [s.start, ...s.checks.map((c) => c.t).sort((a, b) => a - b), endOf(s)];
      for (let k = 0; k < times.length - 1; k++) {
        if (minutesBetween(times[k], times[k + 1]) > intervalMin) {
          overdue.push([times[k] + step, times[k + 1]]);
        }
      }
    }
    slots.forEach((slotStart, i) => {
      const slotEnd = slotStart + step;
      cells[i].missing = !cells[i].checks.length && overdue.some(([from, to]) => from < slotEnd && to > slotStart);
    });
    return { child, naps, cells, unclosed: naps.some((s) => s.end == null) };
  });
  return { slots, rows };
}

// 表示上の時刻（分）どうしの差
export function minutesBetween(a, b) {
  return Math.floor(b / 60000) - Math.floor(a / 60000);
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
