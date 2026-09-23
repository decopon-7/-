import { dateKey } from './logic.js';

// 端末側で操作を反映する（サーバーの処理と同じ結果になるようにしている）
// naps: [{ id, childId, start, end, checks: [{ id, t, posture, fixed?, recorderId }] }]

export function applyOp(naps, op) {
  switch (op.type) {
    case 'startNap':
      if (naps.some((n) => n.id === op.id)) return naps;
      return [...naps, { id: op.id, childId: op.childId, start: op.t, end: null, checks: [] }];
    case 'check':
      return naps.map((n) => {
        if (n.id !== op.napId || (n.end != null && n.end < op.t) || n.checks.some((c) => c.id === op.id)) return n;
        const check = { id: op.id, t: op.t, posture: op.posture, recorderId: op.recorderId };
        if (op.fixed) check.fixed = true;
        return { ...n, checks: [...n.checks, check].sort((a, b) => a.t - b.t) };
      });
    case 'undoCheck':
      return naps.map((n) => (n.checks.some((c) => c.id === op.checkId)
        ? { ...n, checks: n.checks.filter((c) => c.id !== op.checkId) }
        : n));
    case 'endNap': {
      const target = naps.find((n) => n.id === op.napId);
      if (!target) return naps;
      // 同じ日の開いている午睡だけを閉じる（前の日の押し忘れは閉じない）
      const day = dateKey(target.start);
      return naps.map((n) => (n.childId === target.childId && n.end == null && n.start <= op.t && dateKey(n.start) === day
        ? { ...n, end: op.t } : n));
    }
    default:
      return naps;
  }
}

export function applyOps(naps, ops) {
  return ops.reduce(applyOp, naps);
}

// 室温・湿度
// rooms: [{ id, classId, t, tempC10, humidity, recorderId }]
export function applyRoomOp(rooms, op) {
  if (op.type === 'room') {
    if (rooms.some((r) => r.id === op.id)) return rooms;
    const { id, classId, t, tempC10, humidity, recorderId } = op;
    return [...rooms, { id, classId, t, tempC10, humidity, recorderId }].sort((a, b) => a.t - b.t);
  }
  if (op.type === 'undoRoom') return rooms.filter((r) => r.id !== op.roomId);
  return rooms;
}

// その日の記録 { naps, rooms } に操作をまとめて反映する
export function applyDayOps(data, ops) {
  return ops.reduce((d, op) => (op.type === 'room' || op.type === 'undoRoom'
    ? { ...d, rooms: applyRoomOp(d.rooms, op) }
    : { ...d, naps: applyOp(d.naps, op) }), data);
}

// 子どもごとに、入眠の早い順に並べる
export function sessionsByChild(naps) {
  const out = {};
  for (const n of [...naps].sort((a, b) => a.start - b.start)) {
    (out[n.childId] ||= []).push(n);
  }
  return out;
}

export function newId() {
  if (globalThis.crypto?.randomUUID) return crypto.randomUUID();
  const b = crypto.getRandomValues(new Uint8Array(16));
  return Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
}
