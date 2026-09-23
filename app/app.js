import {
  POSTURES, childStatus, summarize, buildRecordTable, fmtTime, fmtDuration, dateKey,
} from './logic.js';
import { applyOp, applyOps, sessionsByChild, newId } from './ops.js';

// ---------- 端末に残す情報 ----------
// ログイン中の園の情報・その日の記録・送信待ちの操作だけを保存し、ログアウトで消す

const CACHE_KEY = 'hs-cache-v2';
const UI_KEY = 'hs-ui-v2';
const POLL_MS = 15 * 1000;

let st = {
  mode: null, // 'server' | 'demo'
  boot: null, // { me, facility, classes, children, staff }
  day: dateKey(Date.now()),
  naps: [], // サーバーから受け取った当日の記録
  outbox: [], // 送信待ちの操作
  recorderId: '',
  lastSync: 0,
};
let online = true;
let ui = { tab: 'check', classId: null, recordDay: null };

function load(key) {
  try {
    const raw = localStorage.getItem(key);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

function save(key, value) {
  try {
    if (value == null) localStorage.removeItem(key);
    else localStorage.setItem(key, JSON.stringify(value));
  } catch {
    toast('この端末に保存できませんでした');
  }
}

const persist = () => save(CACHE_KEY, st);
const saveUi = () => save(UI_KEY, { ...load(UI_KEY), tab: ui.tab, classId: ui.classId });

// ---------- デモ用のサンプル ----------

const DEMO_BOOT = {
  me: { id: 'demo-s1', name: 'サンプル先生A', role: 'staff' },
  facility: { id: 'demo', name: 'デモ園' },
  classes: [
    { id: 'demo-c0', name: '0歳児', age: 0, intervalMin: 5, active: true },
    { id: 'demo-c1', name: '1歳児', age: 1, intervalMin: 10, active: true },
    { id: 'demo-c2', name: '2歳児', age: 2, intervalMin: 10, active: true },
  ],
  children: [
    ['k1', 'あおい', 'c0'], ['k2', 'はると', 'c0'], ['k3', 'ゆい', 'c0'],
    ['k4', 'そうた', 'c1'], ['k5', 'めい', 'c1'], ['k6', 'りく', 'c1'], ['k7', 'こはる', 'c1'],
    ['k8', 'いつき', 'c2'], ['k9', 'ひなた', 'c2'], ['k10', 'さな', 'c2'], ['k11', 'れん', 'c2'],
  ].map(([id, name, c]) => ({ id: `demo-${id}`, name: `サンプル ${name}`, classId: `demo-${c}`, active: true })),
  staff: ['A', 'B', 'C'].map((x, i) => ({ id: `demo-s${i + 1}`, name: `サンプル先生${x}`, active: true })),
};

// ---------- サーバーとのやりとり ----------

class ApiError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

async function api(method, path, data) {
  let res;
  try {
    res = await fetch(path, {
      method,
      credentials: 'same-origin',
      headers: data !== undefined ? { 'content-type': 'application/json' } : {},
      body: data !== undefined ? JSON.stringify(data) : undefined,
    });
  } catch {
    throw new ApiError(0, 'offline');
  }
  const isJson = (res.headers.get('content-type') || '').includes('application/json');
  const body = isJson ? await res.json().catch(() => ({})) : {};
  if (!res.ok || !isJson) throw new ApiError(isJson ? res.status : 0, body.error || (isJson ? 'error' : 'no_api'));
  return body;
}

const MESSAGES = {
  offline: 'サーバーにつながりません',
  wrong_credentials: 'ログインIDかパスワードが違います',
  too_many_attempts: '失敗が続いたため、15分ほど待ってからもう一度お試しください',
  login_id_taken: 'そのログインIDはすでに使われています',
  invalid_login_id: 'ログインIDは半角英数字（. _ - も可）3〜32字で入力してください',
  weak_password: 'パスワードは8文字以上にしてください',
  wrong_password: '今のパスワードが違います',
  cannot_demote_self: '自分自身を停止・変更することはできません',
  forbidden: '管理者だけができる操作です',
  invalid_input: '入力内容を確かめてください',
};
const messageOf = (e) => MESSAGES[e.code] || `うまくいきませんでした（${e.code}）`;

// 送信待ちの操作をまとめて送る
let flushing = false;
const loggedOut = () => !$('#loginView').hidden;
async function flush() {
  if (st.mode !== 'server' || flushing || !st.outbox.length || loggedOut()) return;
  flushing = true;
  let sentOk = false;
  const batch = st.outbox.slice(0, 200);
  try {
    const r = await api('POST', '/api/ops', { ops: batch });
    const sent = new Set(batch.map((o) => o.key));
    st.outbox = st.outbox.filter((o) => !sent.has(o.key));
    const failed = r.results.filter((x) => !x.ok).length;
    if (failed) toast(`${failed}件の記録を保存できませんでした。もう一度記録してください`);
    online = true;
    sentOk = true;
    receiveNaps(r.day, r.naps);
  } catch (e) {
    handleApiError(e);
  } finally {
    flushing = false;
    persist();
    renderBanner();
  }
  // 200件を超えていた時は続けて送る（失敗した時は次の定期送信に任せる）
  if (sentOk && st.outbox.length) flush();
}

async function poll() {
  if (st.mode !== 'server' || loggedOut()) return;
  if (st.outbox.length) return flush();
  try {
    const r = await api('GET', `/api/naps?day=${dateKey(Date.now())}`);
    online = true;
    receiveNaps(r.day, r.naps);
    persist();
  } catch (e) {
    handleApiError(e);
  }
  renderBanner();
}

// 受け取った記録が変わっていた時だけ描き直す（押している途中のボタンを作り直さないため）
function receiveNaps(day, naps) {
  const changed = day !== st.day || JSON.stringify(naps) !== JSON.stringify(st.naps);
  st.day = day;
  st.naps = naps;
  st.lastSync = Date.now();
  if (changed) render();
}

async function refreshBoot() {
  if (st.mode !== 'server') return;
  try {
    const boot = await api('GET', '/api/bootstrap');
    online = true;
    setBoot(boot);
    persist();
    render();
  } catch (e) {
    handleApiError(e);
  }
}

function handleApiError(e) {
  if (e.status === 401) {
    showLogin(st.outbox.length
      ? `ログインの期限が切れました。送信待ちの記録が${st.outbox.length}件あります。ログインすると送信します。`
      : 'ログインの期限が切れました。もう一度ログインしてください。');
  } else if (e.status === 0) {
    online = false;
  } else {
    toast(messageOf(e));
  }
}

function setBoot(boot) {
  st.boot = boot;
  const staffIds = new Set(boot.staff.filter((s) => s.active).map((s) => s.id));
  if (!staffIds.has(st.recorderId)) st.recorderId = boot.me.id;
  if (!activeClasses().some((c) => c.id === ui.classId)) ui.classId = activeClasses()[0]?.id ?? null;
}

// ---------- 画面の部品 ----------

const $ = (sel) => document.querySelector(sel);
const view = $('#view');
const dialog = $('#dialog');
const dialogBody = $('#dialogBody');

function esc(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

let toastTimer;
function toast(msg) {
  const el = $('#toast');
  el.textContent = msg;
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.hidden = true; }, 3000);
}

function openDialog(html, onAct) {
  dialogBody.innerHTML = html;
  const act = (name, data) => {
    const keep = onAct?.(name, data);
    if (!keep) dialog.close();
  };
  dialogBody.onclick = (e) => {
    const b = e.target.closest('button[data-act]');
    if (!b) return;
    e.preventDefault();
    act(b.dataset.act, b.dataset);
  };
  // 入力欄で Enter を押した時は「決定」と同じ扱い
  dialogBody.onsubmit = (e) => {
    e.preventDefault();
    act('ok', {});
  };
  dialog.showModal();
  dialogBody.querySelector('input')?.focus();
}

function confirmDialog(title, note, okLabel, onOk, danger = false) {
  openDialog(`
    <h3>${esc(title)}</h3>${note ? `<p>${esc(note)}</p>` : ''}
    <button class="btn ${danger ? 'danger' : 'primary'} big" data-act="ok">${esc(okLabel)}</button>
    <button class="btn ghost" data-act="cancel">キャンセル</button>`, (a) => { if (a === 'ok') onOk(); });
}

function inputDialog(title, note, { value = '', type = 'text', okLabel = '決定' }, onOk) {
  openDialog(`
    <h3>${esc(title)}</h3>${note ? `<p>${esc(note)}</p>` : ''}
    <input id="dlgInput" class="field" type="${type}" value="${esc(value)}" autocomplete="off">
    <button class="btn primary big" data-act="ok">${esc(okLabel)}</button>
    <button class="btn ghost" data-act="cancel">キャンセル</button>`, (a) => {
    if (a !== 'ok') return false;
    const v = $('#dlgInput').value.trim();
    if (!v) return true;
    onOk(v);
    return false;
  });
}

// ---------- データの見方 ----------

const isAdmin = () => st.mode === 'server' && st.boot?.me.role === 'admin';
const activeClasses = () => (st.boot?.classes || []).filter((c) => c.active);
const currentClass = () => activeClasses().find((c) => c.id === ui.classId);
const childrenOf = (classId) => st.boot.children.filter((ch) => ch.active && ch.classId === classId);
const classById = (id) => st.boot.classes.find((c) => c.id === id);
const staffName = (id) => st.boot.staff.find((s) => s.id === id)?.name || '（不明）';
const intervalOf = (child) => classById(child.classId)?.intervalMin || 5;

function todayNaps() {
  return st.mode === 'server' ? applyOps(st.naps, st.outbox) : st.naps;
}

function statusOf(child, byChild, now = Date.now()) {
  return childStatus(byChild[child.id], now, intervalOf(child));
}

function dispatch(op) {
  const withKey = { ...op, key: newId() };
  if (st.mode === 'demo') {
    st.naps = applyOp(st.naps, withKey);
  } else {
    st.outbox.push(withKey);
  }
  persist();
  render();
  flush();
}

// ---------- ログイン ----------

function showLogin(note, { demo = false } = {}) {
  $('#appView').hidden = true;
  $('#loginView').hidden = false;
  if (dialog.open) dialog.close();
  const n = $('#loginNote');
  n.textContent = note || '';
  n.hidden = !note;
  $('#demoBtn').hidden = !demo;
  $('#loginError').hidden = true;
}

function showApp() {
  $('#loginView').hidden = true;
  $('#appView').hidden = false;
  render();
}

$('#loginForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const form = e.target;
  const btn = form.querySelector('button');
  const err = $('#loginError');
  err.hidden = true;
  btn.disabled = true;
  try {
    await api('POST', '/api/login', { loginId: form.loginId.value.trim(), password: form.password.value });
    const boot = await api('GET', '/api/bootstrap');
    // 別の園でログインした場合は、前の園の送信待ちを持ち越さない
    if (st.boot?.facility.id !== boot.facility.id) st.outbox = [];
    st.mode = 'server';
    st.recorderId = boot.me.id;
    setBoot(boot);
    persist();
    form.password.value = '';
    online = true;
    showApp();
    flush();
    poll();
  } catch (ex) {
    err.textContent = messageOf(ex);
    err.hidden = false;
    if (ex.code === 'no_api') $('#demoBtn').hidden = false;
  } finally {
    btn.disabled = false;
  }
});

$('#demoBtn').addEventListener('click', () => {
  st = { mode: 'demo', boot: DEMO_BOOT, day: dateKey(Date.now()), naps: [], outbox: [], recorderId: '', lastSync: 0 };
  setBoot(DEMO_BOOT);
  persist();
  showApp();
});

function logout() {
  const pending = st.outbox.length;
  const go = async () => {
    if (st.mode === 'server') await api('POST', '/api/logout', {}).catch(() => {});
    st = { mode: null, boot: null, day: dateKey(Date.now()), naps: [], outbox: [], recorderId: '', lastSync: 0 };
    save(CACHE_KEY, null);
    showLogin('', { demo: false });
  };
  if (pending) {
    confirmDialog(`送信待ちの記録が${pending}件あります`, 'ログアウトすると、この記録は消えます。通信がつながるまで待つことをおすすめします。', 'それでもログアウト', go, true);
  } else {
    confirmDialog('ログアウトしますか？', '', 'ログアウト', go);
  }
}

// ---------- ヘッダー・タブ・クラス ----------

function renderBanner() {
  const b = $('#banner');
  if (!st.boot) return;
  let html = '';
  let cls = '';
  if (st.mode === 'demo') {
    html = 'デモです。データはこの端末の中だけに保存されます。実在の園児の情報は入力しないでください';
    cls = 'demo';
  } else if (!online) {
    html = `サーバーにつながっていません。記録は続けられます${st.outbox.length ? `（送信待ち${st.outbox.length}件・つながったら自動で送ります）` : ''}`;
    cls = 'offline';
  } else if (st.outbox.length) {
    html = `送信中…（${st.outbox.length}件）`;
    cls = 'pending';
  }
  b.textContent = html;
  b.className = `banner ${cls}`;
  b.hidden = !html;
}

function renderChrome() {
  const staffBtn = $('#staffBtn');
  staffBtn.textContent = `記録者：${staffName(st.recorderId)}`;
  document.querySelectorAll('.tab').forEach((t) => t.classList.toggle('active', t.dataset.tab === ui.tab));
  renderClassBar();
  renderBanner();
}

function renderClassBar(byChild = sessionsByChild(todayNaps())) {
  const bar = $('#classBar');
  bar.hidden = ui.tab === 'settings';
  bar.innerHTML = activeClasses().map((c) => {
    const alerts = childrenOf(c.id).filter((ch) => statusOf(ch, byChild).state === 'overdue').length;
    return `<button type="button" class="class-chip ${c.id === ui.classId ? 'active' : ''}" data-class="${c.id}">
      ${esc(c.name)}${alerts ? ` <span class="chip-alert" aria-label="確認が遅れている人数">${alerts}</span>` : ''}</button>`;
  }).join('');
}

function tickClock() {
  const d = new Date();
  $('#clock').textContent = `${d.getHours()}:${String(d.getMinutes()).padStart(2, '0')}`;
}

function pickRecorder() {
  const items = st.boot.staff.filter((s) => s.active).map((s) =>
    `<button class="btn ${s.id === st.recorderId ? 'primary' : ''}" data-act="pick" data-id="${s.id}">${esc(s.name)}</button>`).join('');
  openDialog(`
    <h3>記録者を選んでください</h3>
    <p>この端末でのチェックに、この名前が残ります。交代したら切り替えてください。</p>
    <div class="choice-list">${items}</div>
    <button class="btn ghost" data-act="cancel">閉じる</button>`, (act, data) => {
    if (act === 'pick') {
      st.recorderId = data.id;
      persist();
      render();
    }
  });
}

// ---------- チェック画面 ----------

function cardHtml(child, s) {
  const name = `<span class="name">${esc(child.name)}</span>`;
  if (s.state === 'before') {
    return `<div class="card before" data-id="${child.id}">
      <div class="card-head">${name}<span class="pill">起きている</span></div>
      <button class="btn primary big" data-act="start">午睡開始</button>
    </div>`;
  }
  if (s.state === 'awake') {
    const n = s.session;
    return `<div class="card awake" data-id="${child.id}">
      <div class="card-head">${name}<span class="pill">起床</span></div>
      <div class="meta">${fmtTime(n.start)}〜${fmtTime(n.end)}（${fmtDuration(n.end - n.start)}）確認${n.checks.length}回</div>
      <button class="btn" data-act="start">もう一度寝た</button>
    </div>`;
  }
  const buttons = Object.entries(POSTURES).map(([key, p]) =>
    `<button class="pbtn ${key}" data-act="check" data-posture="${key}">${p.short}<small>${p.label}</small></button>`).join('');
  return `<div class="card ${s.state}" data-id="${child.id}">
    <div class="card-head">${name}<span class="pill" data-role="pill"></span></div>
    <div class="meta" data-role="meta"></div>
    <div class="postures">${buttons}</div>
    <div class="row">
      <button class="btn ghost" data-act="undo" ${s.session.checks.length ? '' : 'disabled'}>1つ取り消す</button>
      <button class="btn" data-act="end">起床</button>
    </div>
  </div>`;
}

function renderCheck() {
  const cls = currentClass();
  if (!cls) {
    view.innerHTML = `<p class="empty-note">${isAdmin() ? '設定タブでクラスを登録してください。' : 'クラスが登録されていません。管理者に登録を依頼してください。'}</p>`;
    return;
  }
  const byChild = sessionsByChild(todayNaps());
  const kids = childrenOf(cls.id);
  const beforeCount = kids.filter((ch) => statusOf(ch, byChild).state === 'before').length;
  view.innerHTML = `
    <div class="summary" id="summary"></div>
    <div class="bulk">
      <button class="btn" data-act="startAll" ${beforeCount ? '' : 'disabled'}>まだ寝ていない${beforeCount}名をまとめて午睡開始</button>
    </div>
    <p class="meta">確認間隔：${cls.intervalMin}分ごと</p>
    <div class="grid">${kids.map((ch) => cardHtml(ch, statusOf(ch, byChild))).join('') || '<p class="empty-note">このクラスには子どもが登録されていません。</p>'}</div>`;
  updateLive(byChild);
}

// 1秒ごとの更新は文字と色だけ書き換える
function updateLive(byChild = sessionsByChild(todayNaps())) {
  if (ui.tab !== 'check') return;
  const cls = currentClass();
  if (!cls) return;
  const now = Date.now();
  const statuses = [];
  for (const ch of childrenOf(cls.id)) {
    const s = statusOf(ch, byChild, now);
    statuses.push(s);
    const card = view.querySelector(`.card[data-id="${ch.id}"]`);
    if (!card || !['ok', 'soon', 'overdue'].includes(s.state)) continue;
    card.classList.remove('ok', 'soon', 'overdue');
    card.classList.add(s.state);
    card.querySelector('[data-role="pill"]').textContent =
      s.state === 'overdue' ? `超過 ${fmtDuration(s.remain)}` : `あと ${fmtDuration(s.remain)}`;
    card.querySelector('[data-role="meta"]').textContent = s.last
      ? `最終 ${fmtTime(s.last.t)} ${POSTURES[s.last.posture].label}${s.last.fixed ? '→仰向けに直した' : ''}（${staffName(s.last.recorderId)}）`
      : `${fmtTime(s.session.start)} 入眠・まだ確認していません`;
  }
  const c = summarize(statuses);
  const sum = view.querySelector('#summary');
  if (sum) {
    sum.innerHTML = `
      <div class="sum"><b>${c.sleeping}</b><span>午睡中</span></div>
      <div class="sum soon ${c.soon ? 'has' : ''}"><b>${c.soon}</b><span>まもなく確認</span></div>
      <div class="sum overdue ${c.overdue ? 'has' : ''}"><b>${c.overdue}</b><span>確認が遅れている</span></div>`;
  }
}

function onCheckClick(e) {
  const b = e.target.closest('button[data-act]');
  if (!b) return;
  const act = b.dataset.act;
  const byChild = sessionsByChild(todayNaps());

  if (act === 'startAll') {
    const now = Date.now();
    for (const ch of childrenOf(ui.classId)) {
      if (statusOf(ch, byChild).state === 'before') dispatch({ type: 'startNap', id: newId(), childId: ch.id, t: now });
    }
    return;
  }

  const card = b.closest('.card');
  if (!card) return;
  const child = st.boot.children.find((c) => c.id === card.dataset.id);
  const s = statusOf(child, byChild);

  if (act === 'start') {
    dispatch({ type: 'startNap', id: newId(), childId: child.id, t: Date.now() });
  } else if (act === 'check') {
    const posture = b.dataset.posture;
    const record = (fixed) => dispatch({
      type: 'check', id: newId(), napId: s.session.id, t: Date.now(), posture, recorderId: st.recorderId, ...(fixed ? { fixed: true } : {}),
    });
    if (posture === 'prone') {
      openDialog(`
        <h3>${esc(child.name)}：うつぶせ</h3>
        <p>仰向けに直してから「直した」を押してください。記録には「うつぶせ→仰向けに直した」と残ります。</p>
        <button class="btn primary big" data-act="fixed">仰向けに直した</button>
        <button class="btn ghost" data-act="cancel">キャンセル</button>`, (a) => { if (a === 'fixed') record(true); });
    } else {
      record(false);
    }
  } else if (act === 'undo') {
    const last = s.session.checks[s.session.checks.length - 1];
    if (last) dispatch({ type: 'undoCheck', checkId: last.id });
  } else if (act === 'end') {
    confirmDialog(`${child.name}：起床にしますか？`, '', '起床', () =>
      dispatch({ type: 'endNap', napId: s.session.id, t: Date.now() }));
  }
}

// ---------- 確認遅れの通知（音・振動） ----------

const alerted = new Set();
let audioCtx;

function beep() {
  try {
    audioCtx ??= new (window.AudioContext || window.webkitAudioContext)();
    const t = audioCtx.currentTime;
    [0, 0.3].forEach((offset) => {
      const osc = audioCtx.createOscillator();
      const gain = audioCtx.createGain();
      osc.frequency.value = 880;
      gain.gain.setValueAtTime(0.25, t + offset);
      gain.gain.exponentialRampToValueAtTime(0.001, t + offset + 0.25);
      osc.connect(gain).connect(audioCtx.destination);
      osc.start(t + offset);
      osc.stop(t + offset + 0.25);
    });
  } catch { /* 音が出せない端末では何もしない */ }
  navigator.vibrate?.([200, 100, 200]);
}

function checkAlerts(byChild) {
  let fresh = false;
  for (const ch of st.boot.children) {
    if (!ch.active) continue;
    if (statusOf(ch, byChild).state === 'overdue') {
      if (!alerted.has(ch.id)) { alerted.add(ch.id); fresh = true; }
    } else {
      alerted.delete(ch.id);
    }
  }
  if (fresh && load(UI_KEY)?.sound !== false) beep();
  return fresh;
}

// ---------- 記録画面 ----------

const recordCache = new Map();

async function loadRecordDay(day) {
  if (st.mode !== 'server') return;
  try {
    const r = await api('GET', `/api/naps?day=${day}`);
    recordCache.set(day, r.naps);
    if (ui.tab === 'record' && ui.recordDay === day) render();
  } catch (e) {
    handleApiError(e);
  }
}

function shiftDay(day, delta) {
  const [y, m, d] = day.split('-').map(Number);
  return dateKey(new Date(y, m - 1, d + delta).getTime());
}

function renderRecord() {
  const cls = currentClass();
  if (!cls) {
    view.innerHTML = '<p class="empty-note">クラスが登録されていません。</p>';
    return;
  }
  const today = dateKey(Date.now());
  const day = ui.recordDay || today;
  const isToday = day === today;
  let naps;
  if (isToday) naps = todayNaps();
  else if (recordCache.has(day)) naps = recordCache.get(day);
  else {
    naps = null;
    loadRecordDay(day);
  }

  const [y, m, d] = day.split('-').map(Number);
  const title = `${y}年${m}月${d}日 ${cls.name} 午睡チェック表（${cls.intervalMin}分ごと）`;
  const nav = `
    <div class="day-nav no-print">
      <button class="btn" data-act="prevDay" ${st.mode === 'demo' ? 'disabled' : ''}>前の日</button>
      <span>${m}月${d}日${isToday ? '（今日）' : ''}</span>
      <button class="btn" data-act="nextDay" ${isToday ? 'disabled' : ''}>次の日</button>
    </div>`;

  if (naps === null) {
    view.innerHTML = `${nav}<p class="empty-note">読み込んでいます…</p>`;
    return;
  }

  const kids = childrenOf(cls.id);
  const { slots, rows } = buildRecordTable(kids, sessionsByChild(naps), cls.intervalMin, Date.now());
  if (!slots.length) {
    view.innerHTML = `${nav}<p class="empty-note">${esc(cls.name)}のこの日の記録はありません。</p>`;
    return;
  }

  const step = cls.intervalMin * 60 * 1000;
  const head = slots.map((t) => `<th>${fmtTime(t)}</th>`).join('');
  const body = rows.map(({ child, naps: sessions, cells }) => {
    const napText = sessions.map((s) => `${fmtTime(s.start)}〜${s.end != null ? fmtTime(s.end) : ''}`).join('<br>') || '—';
    const tds = cells.map((c, i) => {
      if (c) {
        const p = POSTURES[c.posture];
        const txt = c.fixed ? `${p.short}→仰` : p.short;
        const who = staffName(c.recorderId);
        return `<td class="cell ${c.posture === 'prone' ? 'prone' : ''}" title="${esc(p.label)} ${fmtTime(c.t)} ${esc(who)}"><b>${txt}</b><small>${esc(initial(who))}</small></td>`;
      }
      const slotEnd = slots[i] + step;
      const asleep = sessions.some((s) => s.start < slotEnd - 60 * 1000 && (s.end == null ? Date.now() : s.end) > slotEnd);
      return `<td class="cell ${asleep ? 'missing' : ''}">${asleep ? '<small>未</small>' : ''}</td>`;
    }).join('');
    return `<tr><td class="sticky">${esc(child.name)}</td><td>${napText}</td>${tds}</tr>`;
  }).join('');

  view.innerHTML = `
    ${nav}
    <div class="record-head no-print">
      <h2>${esc(title)}</h2>
      <button class="btn primary" data-act="print">印刷</button>
    </div>
    <h2 class="print-title">${esc(st.boot.facility.name)}　${esc(title)}</h2>
    <p class="legend">仰：仰向け　右：右向き　左：左向き　う：うつぶせ（う→仰：仰向けに直した）　未：その時間枠に確認の記録がない　小さい文字：記録者</p>
    <div class="table-wrap">
      <table class="record">
        <thead><tr><th class="sticky">名前</th><th>入眠〜起床</th>${head}</tr></thead>
        <tbody>${body}</tbody>
      </table>
    </div>`;
}

function initial(name) {
  const trimmed = name.replace(/サンプル|先生/g, '').trim() || name;
  return trimmed.slice(0, 3);
}

function onRecordClick(e) {
  const b = e.target.closest('button[data-act]');
  if (!b) return;
  const today = dateKey(Date.now());
  if (b.dataset.act === 'print') window.print();
  else if (b.dataset.act === 'prevDay') ui.recordDay = shiftDay(ui.recordDay || today, -1);
  else if (b.dataset.act === 'nextDay') {
    const next = shiftDay(ui.recordDay || today, 1);
    ui.recordDay = next >= today ? null : next;
  }
  if (b.dataset.act !== 'print') render();
}

// ---------- 設定画面 ----------

function renderSettings() {
  const me = st.boot.me;
  const sound = load(UI_KEY)?.sound !== false;
  const sync = st.mode === 'server'
    ? `<p class="help">最後にサーバーと同期：${st.lastSync ? fmtTime(st.lastSync) : '—'}　送信待ち：${st.outbox.length}件</p>`
    : '';

  let html = `
    <div class="section">
      <h2>この端末</h2>
      <p class="help">${esc(st.boot.facility.name)}　ログイン中：${esc(me.name)}${me.role === 'admin' ? '（管理者）' : ''}</p>
      ${sync}
      <div class="toggle"><span>確認が遅れたら音と振動で知らせる</span>
        <button class="btn ${sound ? 'primary' : ''}" data-act="sound">${sound ? 'オン' : 'オフ'}</button></div>
      <div class="row gap-top">
        ${st.mode === 'server' ? '<button class="btn" data-act="myPassword">パスワード変更</button>' : ''}
        <button class="btn danger" data-act="logout">${st.mode === 'demo' ? 'デモを終わる' : 'ログアウト'}</button>
      </div>
    </div>`;

  if (st.mode === 'demo') {
    html += '<div class="section"><p class="help">デモでは、クラス・子ども・職員の登録や変更はできません。</p></div>';
  } else if (isAdmin()) {
    html += adminSettingsHtml();
  } else {
    html += '<div class="section"><p class="help">クラス・子ども・職員の登録や変更は、管理者が行います。</p></div>';
  }
  view.innerHTML = html;
}

function adminSettingsHtml() {
  const { classes, children, staff } = st.boot;
  const classRows = classes.map((c) => `
    <div class="stepper ${c.active ? '' : 'inactive'}">
      <span>${esc(c.name)}${c.active ? '' : '（停止中）'}</span>
      <span class="ctrl">
        <button class="btn" data-act="int" data-id="${c.id}" data-delta="-1" aria-label="短くする">−</button>
        <b>${c.intervalMin}分</b>
        <button class="btn" data-act="int" data-id="${c.id}" data-delta="1" aria-label="長くする">＋</button>
      </span>
    </div>`).join('');

  const childSections = classes.filter((c) => c.active).map((c) => {
    const kids = children.filter((ch) => ch.classId === c.id).map((ch) => `
      <div class="list-item ${ch.active ? '' : 'inactive'}">
        <span>${esc(ch.name)}${ch.active ? '' : '（停止中）'}</span>
        <span class="item-actions">
          <button class="btn" data-act="renameChild" data-id="${ch.id}">名前</button>
          <button class="btn" data-act="moveChild" data-id="${ch.id}">クラス</button>
          <button class="btn ${ch.active ? 'danger' : ''}" data-act="toggleChild" data-id="${ch.id}">${ch.active ? '停止' : '再開'}</button>
        </span>
      </div>`).join('');
    return `<h3>${esc(c.name)}</h3>${kids || '<p class="help">登録なし</p>'}`;
  }).join('');

  const classOptions = classes.filter((c) => c.active)
    .map((c) => `<option value="${c.id}" ${c.id === ui.classId ? 'selected' : ''}>${esc(c.name)}</option>`).join('');

  const staffRows = staff.map((s) => `
    <div class="list-item ${s.active ? '' : 'inactive'}">
      <span>${esc(s.name)}<small class="sub">${esc(s.loginId)}${s.role === 'admin' ? '・管理者' : ''}${s.active ? '' : '・停止中'}</small></span>
      <span class="item-actions">
        <button class="btn" data-act="resetPassword" data-id="${s.id}">パスワード</button>
        ${s.id === st.boot.me.id ? '' : `<button class="btn ${s.active ? 'danger' : ''}" data-act="toggleUser" data-id="${s.id}">${s.active ? '停止' : '再開'}</button>`}
      </span>
    </div>`).join('');

  return `
    <div class="section">
      <h2>確認間隔（クラスごと）</h2>
      <p class="help">園のマニュアルや自治体の指針に合わせて設定してください。</p>
      ${classRows}
    </div>
    <div class="section">
      <h2>子ども</h2>
      <p class="help">退園・転園した子は「停止」にします（過去の記録は残ります）。</p>
      ${childSections}
      <form class="add-row" data-form="addChild">
        <input name="name" placeholder="名前" autocomplete="off" required maxlength="40">
        <select name="classId">${classOptions}</select>
        <button class="btn primary">追加</button>
      </form>
    </div>
    <div class="section">
      <h2>職員</h2>
      <p class="help">職員ごとにログインIDを発行します。退職した人は「停止」にすると、その人の端末のログインも切れます。</p>
      ${staffRows}
      <form class="add-row" data-form="addUser">
        <input name="name" placeholder="名前" autocomplete="off" required maxlength="40">
        <input name="loginId" placeholder="ログインID（半角英数字）" autocomplete="off" autocapitalize="none" required>
        <input name="password" placeholder="初期パスワード（8文字以上）" autocomplete="new-password" required minlength="8">
        <select name="role"><option value="staff">職員</option><option value="admin">管理者</option></select>
        <button class="btn primary">追加</button>
      </form>
    </div>
    <div class="section">
      <h2>端末の紛失・盗難のとき</h2>
      <p class="help">この端末以外のすべての端末をログアウトさせます。</p>
      <button class="btn danger" data-act="revokeAll">全端末をログアウト</button>
    </div>`;
}

async function adminCall(method, path, data, okMsg) {
  try {
    await api(method, path, data);
    if (okMsg) toast(okMsg);
    await refreshBoot();
    return true;
  } catch (e) {
    handleApiError(e);
    if (e.status === 0) toast(MESSAGES.offline);
    return false;
  }
}

function onSettingsClick(e) {
  const b = e.target.closest('button[data-act]');
  if (!b) return;
  const act = b.dataset.act;
  const idOf = b.dataset.id;

  if (act === 'sound') {
    const cur = load(UI_KEY) || {};
    const next = cur.sound === false;
    save(UI_KEY, { ...cur, tab: ui.tab, classId: ui.classId, sound: next });
    if (next) beep();
    render();
  } else if (act === 'logout') {
    logout();
  } else if (act === 'myPassword') {
    openDialog(`
      <h3>パスワード変更</h3>
      <input id="pwCurrent" class="field" type="password" placeholder="今のパスワード" autocomplete="current-password">
      <input id="pwNext" class="field" type="password" placeholder="新しいパスワード（8文字以上）" autocomplete="new-password">
      <button class="btn primary big" data-act="ok">変更</button>
      <button class="btn ghost" data-act="cancel">キャンセル</button>`, (a) => {
      if (a !== 'ok') return false;
      api('POST', '/api/me/password', { current: $('#pwCurrent').value, next: $('#pwNext').value })
        .then(() => toast('パスワードを変更しました。他の端末ではもう一度ログインが必要です'))
        .catch((ex) => toast(messageOf(ex)));
      return false;
    });
  } else if (act === 'int') {
    const c = classById(idOf);
    const next = Math.min(30, Math.max(1, c.intervalMin + Number(b.dataset.delta)));
    if (next !== c.intervalMin) adminCall('PATCH', `/api/admin/classes/${c.id}`, { intervalMin: next });
  } else if (act === 'renameChild') {
    const ch = st.boot.children.find((x) => x.id === idOf);
    inputDialog('名前の変更', '', { value: ch.name }, (v) => adminCall('PATCH', `/api/admin/children/${ch.id}`, { name: v }));
  } else if (act === 'moveChild') {
    const ch = st.boot.children.find((x) => x.id === idOf);
    const items = activeClasses().map((c) =>
      `<button class="btn ${c.id === ch.classId ? 'primary' : ''}" data-act="pick" data-id="${c.id}">${esc(c.name)}</button>`).join('');
    openDialog(`<h3>${esc(ch.name)}のクラス</h3><div class="choice-list">${items}</div>
      <button class="btn ghost" data-act="cancel">キャンセル</button>`, (a, data) => {
      if (a === 'pick' && data.id !== ch.classId) adminCall('PATCH', `/api/admin/children/${ch.id}`, { classId: data.id });
    });
  } else if (act === 'toggleChild') {
    const ch = st.boot.children.find((x) => x.id === idOf);
    if (ch.active) {
      confirmDialog(`${ch.name}を停止しますか？`, 'チェック画面に出なくなります。過去の記録は残ります。', '停止', () =>
        adminCall('PATCH', `/api/admin/children/${ch.id}`, { active: false }), true);
    } else {
      adminCall('PATCH', `/api/admin/children/${ch.id}`, { active: true });
    }
  } else if (act === 'toggleUser') {
    const u = st.boot.staff.find((x) => x.id === idOf);
    if (u.active) {
      confirmDialog(`${u.name}を停止しますか？`, 'ログインできなくなり、使っている端末のログインも切れます。過去の記録の名前は残ります。', '停止', () =>
        adminCall('PATCH', `/api/admin/users/${u.id}`, { active: false }), true);
    } else {
      adminCall('PATCH', `/api/admin/users/${u.id}`, { active: true });
    }
  } else if (act === 'resetPassword') {
    const u = st.boot.staff.find((x) => x.id === idOf);
    inputDialog(`${u.name}のパスワードを再発行`, '新しいパスワードを本人に伝えてください。その人の端末のログインは切れます。',
      { okLabel: '再発行' }, (v) => adminCall('PATCH', `/api/admin/users/${u.id}`, { password: v }, 'パスワードを再発行しました'));
  } else if (act === 'revokeAll') {
    confirmDialog('全端末をログアウトしますか？', 'この端末以外は、もう一度ログインが必要になります。', 'ログアウトさせる', () =>
      adminCall('POST', '/api/admin/sessions/revoke-all', {}, '他の端末をすべてログアウトしました'), true);
  }
}

async function onSettingsSubmit(e) {
  const form = e.target.closest('form[data-form]');
  if (!form) return;
  e.preventDefault();
  const f = Object.fromEntries(new FormData(form));
  let ok = false;
  if (form.dataset.form === 'addChild') {
    ok = await adminCall('POST', '/api/admin/children', { name: f.name, classId: f.classId }, '追加しました');
  } else if (form.dataset.form === 'addUser') {
    ok = await adminCall('POST', '/api/admin/users',
      { name: f.name, loginId: f.loginId, password: f.password, role: f.role }, '追加しました');
  }
  if (ok) form.reset();
}

// ---------- 全体 ----------

function render() {
  if (!st.boot || $('#appView').hidden) return;
  renderChrome();
  if (ui.tab === 'check') renderCheck();
  else if (ui.tab === 'record') renderRecord();
  else renderSettings();
}

document.querySelector('.tabs').addEventListener('click', (e) => {
  const t = e.target.closest('.tab');
  if (!t) return;
  ui.tab = t.dataset.tab;
  if (ui.tab !== 'record') ui.recordDay = null;
  saveUi();
  render();
});

$('#classBar').addEventListener('click', (e) => {
  const c = e.target.closest('.class-chip');
  if (!c) return;
  ui.classId = c.dataset.class;
  saveUi();
  render();
});

$('#staffBtn').addEventListener('click', pickRecorder);

view.addEventListener('click', (e) => {
  if (ui.tab === 'check') onCheckClick(e);
  else if (ui.tab === 'record') onRecordClick(e);
  else onSettingsClick(e);
});
view.addEventListener('submit', onSettingsSubmit);

// 午睡中は画面が消えないようにする（対応端末のみ）
let wakeLock;
async function keepAwake() {
  try {
    if ('wakeLock' in navigator && document.visibilityState === 'visible' && !wakeLock) {
      wakeLock = await navigator.wakeLock.request('screen');
      wakeLock.addEventListener('release', () => { wakeLock = null; });
    }
  } catch { /* 非対応・拒否時は何もしない */ }
}
document.addEventListener('visibilitychange', () => {
  keepAwake();
  if (document.visibilityState === 'visible') { refreshBoot(); poll(); }
});
document.addEventListener('click', keepAwake, { once: true });
window.addEventListener('online', () => { online = true; flush(); poll(); });
window.addEventListener('offline', () => { online = false; renderBanner(); });

let lastOverdue = -1;
setInterval(() => {
  tickClock();
  if (!st.boot || $('#appView').hidden) return;
  const today = dateKey(Date.now());
  if (st.mode === 'demo' && st.day !== today) {
    st.day = today;
    st.naps = [];
    persist();
    render();
  }
  const byChild = sessionsByChild(todayNaps());
  checkAlerts(byChild);
  updateLive(byChild);
  // クラスの超過人数は、人数が変わった時だけ描き直す
  if (alerted.size !== lastOverdue) {
    lastOverdue = alerted.size;
    renderClassBar(byChild);
  }
}, 1000);
setInterval(poll, POLL_MS);

// ---------- 起動 ----------

async function start() {
  tickClock();
  const cached = load(CACHE_KEY);
  const savedUi = load(UI_KEY);
  if (savedUi) Object.assign(ui, { tab: savedUi.tab || 'check', classId: savedUi.classId || null });

  if (cached?.boot && (cached.mode === 'server' || cached.mode === 'demo')) {
    // 前回の情報ですぐ表示し、裏でサーバーの最新を取りに行く（オフラインでも開ける）
    st = { ...st, ...cached };
    if (st.mode === 'demo' && st.day !== dateKey(Date.now())) {
      st.day = dateKey(Date.now());
      st.naps = [];
    }
    setBoot(st.boot);
    showApp();
    if (st.mode === 'server') {
      await refreshBoot();
      flush();
      poll();
    }
    return;
  }

  try {
    const boot = await api('GET', '/api/bootstrap');
    st.mode = 'server';
    st.recorderId = boot.me.id;
    setBoot(boot);
    persist();
    showApp();
    poll();
  } catch (e) {
    if (e.status === 401) showLogin('');
    else showLogin('サーバーにつながりません。通信を確かめてください。', { demo: e.code === 'no_api' });
  }
}

start();

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('sw.js').catch(() => {});
}
