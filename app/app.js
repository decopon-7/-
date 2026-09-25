import {
  POSTURES, FIXED_SHORT, childStatus, summarize, buildRecordTable, slotIndex, recorderMarks, fmtRoom,
  fmtTime, fmtDuration, dateKey,
} from './logic.js';
import { applyDayOps, sessionsByChild, newId } from './ops.js';
import { FOOD_STATUS, nextStatus, mealFlags, checkSnapshot, isStale } from './meals.js';

// ---------- 端末に残す情報 ----------
// 登録した園の情報・その日の記録・送信待ちの操作だけを保存し、登録解除で消す

const CACHE_KEY = 'hs-cache-v3';
const UI_KEY = 'hs-ui-v3';
const POLL_MS = 15 * 1000;
const EMPTY_DAY = () => ({ naps: [], rooms: [] });

let st = {
  mode: null, // 'server' | 'demo'
  boot: null, // { device, admin, facility, classes, children, staff }
  day: dateKey(Date.now()),
  data: EMPTY_DAY(), // サーバーから受け取った当日の記録 { naps, rooms }
  outbox: [], // 送信待ちの操作
  lastSync: 0,
};
let online = true;
// duty: クラスごとの午睡担当 { [classId]: { ids: [職員ID, 職員ID], active: 0 | 1 } }（端末ごと）
let ui = { tab: 'check', classId: null, recordDay: null, duty: {}, sound: true, mealView: 'precheck', mealChildId: null };
// 給食：今日の分をサーバーから取得してここに持つ（オフライン時の送信待ちには入れない）
let meals = null; // { day, foods, childFoods, menus, checks }

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
const saveUi = () => save(UI_KEY, { tab: ui.tab, classId: ui.classId, duty: ui.duty, sound: ui.sound });

// ---------- デモ用のサンプル ----------

const DEMO_BOOT = {
  device: { name: 'デモ' },
  admin: null,
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
  staff: ['佐藤', '鈴木', '高橋', '田中'].map((x, i) => ({ id: `demo-s${i + 1}`, name: `サンプル${x}`, active: true })),
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
  cannot_demote_self: '自分自身を停止することはできません',
  admin_mode_required: '管理者モードの時間が過ぎました。もう一度管理者モードにしてください',
  invalid_input: '入力内容を確かめてください',
  no_menu: '今日の献立が登録されていません。先に「今日の献立」で登録してください',
  two_checkers_required: '違う2名を選んでください',
  food_not_found: 'その食材が見つかりません',
  child_not_found: 'その子どもが見つかりません',
  class_not_found: 'そのクラスが見つかりません',
  recorder_not_found: '記録者が見つかりません。担当を選び直してください',
};
const messageOf = (e) => MESSAGES[e.code] || `うまくいきませんでした（${e.code}）`;

// 送信待ちの操作をまとめて送る
let flushing = false;
const unregistered = () => !$('#loginView').hidden;
async function flush() {
  if (st.mode !== 'server' || flushing || !st.outbox.length || unregistered()) return;
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
    receiveDay(r);
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
  if (st.mode !== 'server' || unregistered()) return;
  if (st.outbox.length) return flush();
  try {
    const r = await api('GET', `/api/day?day=${dateKey(Date.now())}`);
    online = true;
    receiveDay(r);
    persist();
  } catch (e) {
    handleApiError(e);
  }
  renderBanner();
}

// 受け取った記録が変わっていた時だけ描き直す（押している途中のボタンを作り直さないため）
function receiveDay({ day, naps, rooms }) {
  const next = { naps, rooms };
  const changed = day !== st.day || JSON.stringify(next) !== JSON.stringify(st.data);
  st.day = day;
  st.data = next;
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
      ? `この端末の登録が切れました。送信待ちの記録が${st.outbox.length}件あります。管理者が登録し直すと送信します。`
      : 'この端末の登録が切れました。管理者が登録し直してください。');
  } else if (e.status === 0) {
    online = false;
  } else if (e.code === 'admin_mode_required') {
    toast(messageOf(e));
    refreshBoot();
  } else {
    toast(messageOf(e));
  }
}

// ---------- 給食（オフライン非対応。つながらない時はその旨を出す） ----------

let mealSavesInFlight = 0;

async function loadMeals() {
  if (st.mode !== 'server') return;
  let r;
  try {
    r = await api('GET', `/api/meals?day=${dateKey(Date.now())}`);
  } catch (e) {
    handleApiError(e);
    return;
  }
  // 取りに行っている間にタップが始まっていたら、その分を巻き戻さないよう受け取った内容は捨てる
  if (mealSavesInFlight > 0) return;
  meals = r;
  if (ui.tab === 'meal' || ui.tab === 'settings') render();
}

// 保存中でない時だけ、ほかの端末での変更を定期的に取り込む
async function pollMeals() {
  if (st.mode !== 'server' || unregistered() || mealSavesInFlight > 0) return;
  if (ui.tab !== 'meal' && ui.tab !== 'settings') return;
  await loadMeals();
}

function handleMealError(e) {
  if (e.status === 401 || e.status === 0) handleApiError(e);
  else toast(messageOf(e));
  // 保存に失敗した時は、画面を先読みで変えた分が実際の値とずれている。サーバーの値で直す
  if (e.status !== 0) loadMeals();
}

// 同じ献立・同じ子×食材への保存は、必ず1件ずつ順番に送る。
// 献立の保存は「今の全食材」を毎回まるごと送る作りなので、連打で2件が同時に届くと
// サーバー側の処理順が入れ替わり、あとから送ったはずの内容が消えることがある（実際に確認して直した）
const saveChains = new Map();
function serialize(key, task) {
  mealSavesInFlight++;
  const prev = saveChains.get(key) || Promise.resolve();
  const next = prev.then(task, task).finally(() => { mealSavesInFlight--; });
  saveChains.set(key, next);
  return next;
}

// 成功した時はサーバーへ送った内容がそのまま画面の状態と一致しているので、わざわざ読み直さない。
// ここで毎回読み直すと、その応答が返るまでの間に次のタップが読む状態を巻き戻してしまい、
// 連打した時に直前の変更が消えることがあった（実際に確認して直した）。失敗した時だけ読み直す
async function saveMenuFood(cls, foodId, on, recorderId) {
  // 食材1つずつの増減にしているので、違う食材どうしは並行に送っても結果が変わらない。
  // 同じ食材への操作だけ順番を守ればよいので、食材ごとに直列化する
  return serialize(`menu:${cls.id}:${foodId}`, async () => {
    try {
      await api('POST', '/api/meals/menu', { classId: cls.id, day: dateKey(Date.now()), foodId, on, recorderId });
    } catch (e) {
      handleMealError(e);
    }
  });
}

async function saveChildFood(childId, foodId, status, recorderId) {
  return serialize(`food:${childId}:${foodId}`, async () => {
    try {
      await api('POST', '/api/meals/child-food', { childId, foodId, status, recorderId });
    } catch (e) {
      handleMealError(e);
    }
  });
}

async function submitMealCheck(cls, checkerIds) {
  try {
    await api('POST', '/api/meals/check', { id: newId(), classId: cls.id, checkerIds });
    toast('確認して記録しました');
    await loadMeals();
  } catch (e) {
    handleMealError(e);
  }
}

async function adminMealCall(method, path, data, okMsg) {
  try {
    await api(method, path, data);
    if (okMsg) toast(okMsg);
    await loadMeals();
    return true;
  } catch (e) {
    handleApiError(e);
    if (e.status === 0) toast(MESSAGES.offline);
    return false;
  }
}

// 保存の応答を待たずに画面へ反映する（タップした通りに、すぐ見た目へ反映するため）
function applyLocalMenuFood(classId, foodId, on) {
  if (!meals) return;
  const i = meals.menus.findIndex((m) => m.classId === classId);
  const foodIds = i >= 0 ? meals.menus[i].foodIds : [];
  const has = foodIds.includes(foodId);
  if (on === has) return;
  const nextIds = on ? [...foodIds, foodId] : foodIds.filter((f) => f !== foodId);
  if (i >= 0) meals.menus[i] = { ...meals.menus[i], foodIds: nextIds };
  else meals.menus.push({ classId, foodIds: nextIds, updatedAt: Date.now(), recorderId: null });
}

function applyLocalChildFood(childId, foodId, status) {
  if (!meals) return;
  meals.childFoods = meals.childFoods.filter((cf) => !(cf.childId === childId && cf.foodId === foodId));
  if (status !== 'none') meals.childFoods.push({ childId, foodId, status });
}

function groupBy(arr, keyFn) {
  const out = {};
  for (const item of arr) (out[keyFn(item)] ||= []).push(item);
  return out;
}

function setBoot(boot) {
  st.boot = boot;
  if (!activeClasses().some((c) => c.id === ui.classId)) ui.classId = activeClasses()[0]?.id ?? null;
  // 停止した職員は担当から外す
  const activeIds = new Set(boot.staff.filter((s) => s.active).map((s) => s.id));
  for (const d of Object.values(ui.duty)) {
    d.ids = d.ids.filter((x) => activeIds.has(x));
    if (d.active >= d.ids.length) d.active = 0;
  }
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

function inputDialog(title, note, { value = '', okLabel = '決定' }, onOk) {
  openDialog(`
    <h3>${esc(title)}</h3>${note ? `<p>${esc(note)}</p>` : ''}
    <input id="dlgInput" class="field" value="${esc(value)}" autocomplete="off">
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

const isAdmin = () => st.mode === 'server' && !!st.boot?.admin && st.boot.admin.until > Date.now();
const activeClasses = () => (st.boot?.classes || []).filter((c) => c.active);
const currentClass = () => activeClasses().find((c) => c.id === ui.classId);
const childrenOf = (classId) => st.boot.children.filter((ch) => ch.active && ch.classId === classId);
const classById = (id) => st.boot.classes.find((c) => c.id === id);
const staffById = (id) => st.boot.staff.find((s) => s.id === id);
const staffName = (id) => staffById(id)?.name || '（不明）';
const intervalOf = (child) => classById(child.classId)?.intervalMin || 5;

function todayData() {
  return st.mode === 'server' ? applyDayOps(st.data, st.outbox) : st.data;
}

function statusOf(child, byChild, now = Date.now()) {
  return childStatus(byChild[child.id], now, intervalOf(child));
}

function dispatch(op) {
  const withKey = { ...op, key: newId() };
  if (st.mode === 'demo') {
    st.data = applyDayOps(st.data, [withKey]);
  } else {
    st.outbox.push(withKey);
  }
  persist();
  render();
  flush();
}

// ---------- 午睡担当（2名） ----------

function dutyOf(classId) {
  return ui.duty[classId] || { ids: [], active: 0 };
}

// いま入力している人
function inputterId(classId = ui.classId) {
  const d = dutyOf(classId);
  return d.ids[d.active] || null;
}

// 担当を選ぶ（名前をタップ。2名まで）。選び終わったら then を呼ぶ
function editDuty(then) {
  const cls = currentClass();
  const picked = [...dutyOf(cls.id).ids];
  const draw = () => {
    const items = st.boot.staff.filter((s) => s.active).map((s) => {
      const i = picked.indexOf(s.id);
      return `<button class="btn ${i >= 0 ? 'primary' : ''}" data-act="toggle" data-id="${s.id}">${i >= 0 ? `${'①②'[i]} ` : ''}${esc(s.name)}</button>`;
    }).join('');
    dialogBody.innerHTML = `
      <h3>${esc(cls.name)}の午睡担当</h3>
      <p>2名まで選べます。選んだ順に①②になります。記録するたびに、①②のどちらが入力したかが残ります。</p>
      <div class="choice-list">${items || '<p>職員が登録されていません。</p>'}</div>
      <button class="btn primary big" data-act="ok" ${picked.length ? '' : 'disabled'}>決定</button>
      <button class="btn ghost" data-act="cancel">キャンセル</button>`;
  };
  openDialog('', (act, data) => {
    if (act === 'toggle') {
      const i = picked.indexOf(data.id);
      if (i >= 0) picked.splice(i, 1);
      else if (picked.length < 2) picked.push(data.id);
      else toast('担当は2名までです。先にどちらかを外してください');
      draw();
      return true;
    }
    if (act === 'ok' && picked.length) {
      ui.duty[cls.id] = { ids: picked, active: 0 };
      saveUi();
      render();
      then?.();
    }
    return false;
  });
  draw();
}

// 入力する人がまだ決まっていない時は、先に担当を選んでもらう
function withInputter(fn) {
  if (inputterId()) fn(inputterId());
  else editDuty(() => { if (inputterId()) fn(inputterId()); });
}

// ---------- 端末の登録 ----------

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
    await api('POST', '/api/device/register', {
      loginId: form.loginId.value.trim(), password: form.password.value, deviceName: form.deviceName.value.trim(),
    });
    const boot = await api('GET', '/api/bootstrap');
    // 別の園で登録した場合は、前の園の送信待ちを持ち越さない
    if (st.boot?.facility.id !== boot.facility.id) st.outbox = [];
    st.mode = 'server';
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
  st = { mode: 'demo', boot: DEMO_BOOT, day: dateKey(Date.now()), data: EMPTY_DAY(), outbox: [], lastSync: 0 };
  setBoot(DEMO_BOOT);
  persist();
  showApp();
});

function unregister() {
  const pending = st.outbox.length;
  const go = async () => {
    if (st.mode === 'server') await api('POST', '/api/device/unregister', {}).catch(() => {});
    st = { mode: null, boot: null, day: dateKey(Date.now()), data: EMPTY_DAY(), outbox: [], lastSync: 0 };
    save(CACHE_KEY, null);
    showLogin('');
  };
  if (pending) {
    confirmDialog(`送信待ちの記録が${pending}件あります`, '登録を解除すると、この記録は消えます。通信がつながるまで待つことをおすすめします。', 'それでも解除', go, true);
  } else if (st.mode === 'demo') {
    go();
  } else {
    confirmDialog('この端末の登録を解除しますか？', 'もう一度使うには、管理者が登録し直す必要があります。', '解除', go, true);
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
  } else if (isAdmin()) {
    html = `管理者モード中（${st.boot.admin.name}）　設定タブの「管理者モードを終わる」で戻ります`;
    cls = 'admin';
  }
  b.textContent = html;
  b.className = `banner ${cls}`;
  b.hidden = !html;
}

// ヘッダーには「いま入力している人」を出し、タップでもう1人に切り替える
function renderInputterChip() {
  const chip = $('#staffBtn');
  const d = dutyOf(ui.classId);
  const id = inputterId();
  chip.textContent = id ? `入力：${'①②'[d.active]} ${staffName(id)}` : '午睡担当を選ぶ';
  chip.classList.toggle('empty', !id);
  chip.hidden = ui.tab === 'settings' || !currentClass();
}

function renderChrome() {
  renderInputterChip();
  document.querySelectorAll('.tab').forEach((t) => t.classList.toggle('active', t.dataset.tab === ui.tab));
  renderClassBar();
  renderBanner();
}

function renderClassBar(byChild = sessionsByChild(todayData().naps)) {
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

function switchInputter() {
  const d = dutyOf(ui.classId);
  if (d.ids.length < 2) return editDuty();
  d.active = d.active ? 0 : 1;
  ui.duty[ui.classId] = d;
  saveUi();
  render();
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

function dutyBarHtml(cls) {
  const d = dutyOf(cls.id);
  if (!d.ids.length) {
    return '<div class="duty"><button class="btn primary big" data-act="dutyEdit">午睡担当（2名）を選ぶ</button></div>';
  }
  const slots = d.ids.map((id, i) =>
    `<button class="duty-btn ${i === d.active ? 'active' : ''}" data-act="dutyPick" data-slot="${i}">
      ${'①②'[i]} ${esc(staffName(id))}<small>${i === d.active ? '入力中' : 'タップで交代'}</small></button>`).join('');
  return `<div class="duty">${slots}<button class="btn ghost duty-edit" data-act="dutyEdit">担当を変える</button></div>`;
}

function roomPanelHtml(cls, rooms) {
  const mine = rooms.filter((r) => r.classId === cls.id);
  const last = mine[mine.length - 1];
  const text = last
    ? `<b>${fmtRoom(last)}</b><small>${fmtTime(last.t)} ${esc(staffName(last.recorderId))}</small>`
    : '<b class="muted">今日はまだ記録していません</b>';
  return `<div class="room-panel">
    <span class="room-label">室温・湿度</span>
    <span class="room-value">${text}</span>
    <button class="btn" data-act="room">記録する</button>
  </div>`;
}

function renderCheck() {
  const cls = currentClass();
  if (!cls) {
    view.innerHTML = '<p class="empty-note">クラスが登録されていません。管理者モードで登録してください。</p>';
    return;
  }
  const data = todayData();
  const byChild = sessionsByChild(data.naps);
  const kids = childrenOf(cls.id);
  const beforeCount = kids.filter((ch) => statusOf(ch, byChild).state === 'before').length;
  view.innerHTML = `
    ${dutyBarHtml(cls)}
    ${roomPanelHtml(cls, data.rooms)}
    <div class="summary" id="summary"></div>
    <div class="bulk">
      <span class="meta">確認：${cls.intervalMin}分ごと</span>
      <button class="btn" data-act="startAll" ${beforeCount ? '' : 'disabled'}>まだ寝ていない${beforeCount}名をまとめて午睡開始</button>
    </div>
    <div class="grid">${kids.map((ch) => cardHtml(ch, statusOf(ch, byChild))).join('') || '<p class="empty-note">このクラスには子どもが登録されていません。</p>'}</div>`;
  updateLive(byChild);
}

// 1秒ごとの更新は文字と色だけ書き換える
function updateLive(byChild = sessionsByChild(todayData().naps)) {
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
      ? `最終 ${fmtTime(s.last.t)} ${POSTURES[s.last.posture].short}${POSTURES[s.last.posture].label}${s.last.fixed ? '（仰向けに直した）' : ''}（${staffName(s.last.recorderId)}）`
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

// 室温・湿度の入力（タップだけ。前回の値から始める）
function openRoomDialog() {
  const cls = currentClass();
  const mine = todayData().rooms.filter((r) => r.classId === cls.id);
  const last = mine[mine.length - 1];
  let temp = last ? last.tempC10 : 240;
  let hum = last ? last.humidity : 50;
  const draw = () => {
    dialogBody.innerHTML = `
      <h3>${esc(cls.name)}の室温・湿度</h3>
      <p>記録者：${esc(staffName(inputterId()))}</p>
      <div class="stepper big-stepper"><span>室温</span><span class="ctrl">
        <button class="btn" data-act="t" data-d="-10">−1</button>
        <button class="btn" data-act="t" data-d="-5">−0.5</button>
        <b>${(temp / 10).toFixed(1)}℃</b>
        <button class="btn" data-act="t" data-d="5">＋0.5</button>
        <button class="btn" data-act="t" data-d="10">＋1</button></span></div>
      <div class="stepper big-stepper"><span>湿度</span><span class="ctrl">
        <button class="btn" data-act="h" data-d="-5">−5</button>
        <button class="btn" data-act="h" data-d="-1">−1</button>
        <b>${hum}%</b>
        <button class="btn" data-act="h" data-d="1">＋1</button>
        <button class="btn" data-act="h" data-d="5">＋5</button></span></div>
      <button class="btn primary big" data-act="save">この値で記録</button>
      ${last ? `<button class="btn ghost" data-act="undoLast">直前の記録（${fmtTime(last.t)} ${fmtRoom(last)}）を取り消す</button>` : ''}
      <button class="btn ghost" data-act="cancel">キャンセル</button>`;
  };
  openDialog('', (act, data) => {
    if (act === 't') { temp = Math.min(450, Math.max(50, temp + Number(data.d))); draw(); return true; }
    if (act === 'h') { hum = Math.min(100, Math.max(0, hum + Number(data.d))); draw(); return true; }
    if (act === 'save') {
      dispatch({ type: 'room', id: newId(), classId: cls.id, t: Date.now(), tempC10: temp, humidity: hum, recorderId: inputterId() });
      toast(`室温 ${(temp / 10).toFixed(1)}℃・湿度 ${hum}% を記録しました`);
    }
    if (act === 'undoLast') dispatch({ type: 'undoRoom', roomId: last.id });
    return false;
  });
  draw();
}

function onCheckClick(e) {
  const b = e.target.closest('button[data-act]');
  if (!b) return;
  const act = b.dataset.act;
  const byChild = sessionsByChild(todayData().naps);

  if (act === 'dutyEdit') return editDuty();
  if (act === 'dutyPick') {
    const d = dutyOf(ui.classId);
    d.active = Number(b.dataset.slot);
    ui.duty[ui.classId] = d;
    saveUi();
    return render();
  }
  if (act === 'room') return withInputter(openRoomDialog);

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
    withInputter((recorderId) => {
      const record = (fixed) => dispatch({
        type: 'check', id: newId(), napId: s.session.id, t: Date.now(), posture, recorderId, ...(fixed ? { fixed: true } : {}),
      });
      if (posture === 'prone') {
        openDialog(`
          <h3>${esc(child.name)}：うつぶせ</h3>
          <p>仰向けに直してから「直した」を押してください。記録には「${FIXED_SHORT}（うつぶせを仰向けに直した）」と残ります。</p>
          <button class="btn primary big" data-act="fixed">仰向けに直した</button>
          <button class="btn ghost" data-act="cancel">キャンセル</button>`, (a) => { if (a === 'fixed') record(true); });
      } else {
        record(false);
      }
    });
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
  if (fresh && ui.sound) beep();
}

// ---------- 給食画面 ----------

function foodNameOf(id) {
  return meals.foods.find((f) => f.id === id)?.name || '？';
}

function renderMealPrecheck(cls) {
  const kids = childrenOf(cls.id);
  const menu = meals.menus.find((m) => m.classId === cls.id);
  const menuFoodIds = menu?.foodIds || [];
  if (!menuFoodIds.length) {
    return '<p class="empty-note">今日の献立がまだ登録されていません。「今日の献立」タブで登録してください。</p>';
  }
  const flagged = mealFlags(kids, meals.childFoods, menuFoodIds);
  const flaggedIds = new Set(flagged.map((f) => f.childId));
  const okCount = kids.length - flaggedIds.size;

  const rows = flagged.map((f) => {
    const child = kids.find((c) => c.id === f.childId);
    const untried = f.untried.length
      ? `<span class="food-tag untried">未経験：${f.untried.map((id) => esc(foodNameOf(id))).join('、')}</span>` : '';
    const excluded = f.excluded.length
      ? `<span class="food-tag excluded">除去：${f.excluded.map((id) => esc(foodNameOf(id))).join('、')}</span>` : '';
    return `<div class="meal-flag-card"><span class="name">${esc(child.name)}</span><div class="food-tags">${untried}${excluded}</div></div>`;
  }).join('');

  const currentSnapshot = checkSnapshot(kids, meals.childFoods, menuFoodIds);
  const checks = meals.checks.filter((c) => c.classId === cls.id);
  const checkRows = checks.map((c) => {
    const stale = isStale(c.snapshot, currentSnapshot);
    return `<div class="check-row ${stale ? 'stale' : ''}">
      <span>${fmtTime(c.t)}　${esc(staffName(c.checker1Id))}・${esc(staffName(c.checker2Id))}で確認</span>
      ${stale ? '<span class="warn">確認後に献立・食材の記録が変わっています</span>' : ''}
    </div>`;
  }).join('');

  return `
    <p class="meal-menu-line">今日の献立：${menuFoodIds.map((id) => esc(foodNameOf(id))).join('、')}</p>
    ${rows || '<p class="empty-note">未経験・除去の食材がある子はいません。</p>'}
    ${okCount > 0 ? `<p class="meal-ok-line">ほか${okCount}名は問題なし</p>` : ''}
    <button class="btn primary big" data-act="mealCheck">2名で確認して記録</button>
    ${checkRows ? `<div class="meal-checks">${checkRows}</div>` : ''}
    <p class="help">アレルギー対応は、医師の指示書に基づく園の手順が優先です。ここでの確認は、照らし合わせの見落としを減らす補助です。</p>`;
}

function renderMealMenu(cls) {
  const menu = meals.menus.find((m) => m.classId === cls.id);
  const menuFoodIds = new Set(menu?.foodIds || []);
  const groups = groupBy(meals.foods.filter((f) => f.active), (f) => f.category || 'その他');
  const groupHtml = Object.entries(groups).map(([cat, items]) => `
    <h3>${esc(cat)}</h3>
    <div class="food-grid">${items.map((f) =>
      `<button class="food-btn ${menuFoodIds.has(f.id) ? 'active' : ''}" data-act="toggleMenuFood" data-id="${f.id}">${esc(f.name)}</button>`).join('')}</div>`).join('');
  return `<p class="help">タップで、今日この献立に使う食材を選んでください。</p>
    ${groupHtml || '<p class="empty-note">食材が登録されていません。管理者モードで登録してください。</p>'}`;
}

function renderMealFoods(cls) {
  const kids = childrenOf(cls.id);
  if (!ui.mealChildId || !kids.some((k) => k.id === ui.mealChildId)) ui.mealChildId = kids[0]?.id || null;
  if (!ui.mealChildId) return '<p class="empty-note">このクラスには子どもが登録されていません。</p>';
  const child = kids.find((k) => k.id === ui.mealChildId);
  const childChips = kids.map((k) =>
    `<button class="class-chip ${k.id === ui.mealChildId ? 'active' : ''}" data-act="pickMealChild" data-id="${k.id}">${esc(k.name)}</button>`).join('');
  const statusOfFood = (fid) => meals.childFoods.find((cf) => cf.childId === ui.mealChildId && cf.foodId === fid)?.status || 'none';
  const groups = groupBy(meals.foods.filter((f) => f.active), (f) => f.category || 'その他');
  const groupHtml = Object.entries(groups).map(([cat, items]) => `
    <h3>${esc(cat)}</h3>
    <div class="food-grid">${items.map((f) => {
      const s = statusOfFood(f.id);
      return `<button class="food-btn status-${s}" data-act="cycleChildFood" data-id="${f.id}">${esc(f.name)}<small>${FOOD_STATUS[s].label}</small></button>`;
    }).join('')}</div>`).join('');
  return `
    <div class="class-bar child-bar no-print">${childChips}</div>
    <h2 class="print-title">${esc(st.boot.facility.name)}　${esc(child.name)}　食材チェック表</h2>
    <button class="btn no-print" data-act="printFoodChart">この子の食材チェック表を印刷</button>
    ${groupHtml || '<p class="empty-note">食材が登録されていません。管理者モードで登録してください。</p>'}`;
}

function renderMeal() {
  const cls = currentClass();
  if (!cls) {
    view.innerHTML = '<p class="empty-note">クラスが登録されていません。</p>';
    return;
  }
  if (st.mode === 'demo') {
    view.innerHTML = '<p class="empty-note">デモでは給食機能は使えません。管理者が登録した園でお試しください。</p>';
    return;
  }
  if (!meals || meals.day !== dateKey(Date.now())) {
    view.innerHTML = '<p class="empty-note">読み込んでいます…</p>';
    loadMeals();
    return;
  }
  const subnav = `<div class="meal-subnav no-print">
    <button class="sub-tab ${ui.mealView === 'precheck' ? 'active' : ''}" data-act="mealView" data-view="precheck">配膳前チェック</button>
    <button class="sub-tab ${ui.mealView === 'menu' ? 'active' : ''}" data-act="mealView" data-view="menu">今日の献立</button>
    <button class="sub-tab ${ui.mealView === 'foods' ? 'active' : ''}" data-act="mealView" data-view="foods">食べた食材</button>
  </div>`;
  const body = ui.mealView === 'menu' ? renderMealMenu(cls)
    : ui.mealView === 'foods' ? renderMealFoods(cls)
    : renderMealPrecheck(cls);
  view.innerHTML = subnav + body;
}

function openMealCheckDialog(cls) {
  const picked = [];
  const draw = () => {
    const items = st.boot.staff.filter((s) => s.active).map((s) => {
      const i = picked.indexOf(s.id);
      return `<button class="btn ${i >= 0 ? 'primary' : ''}" data-act="toggle" data-id="${s.id}">${i >= 0 ? `${'①②'[i]} ` : ''}${esc(s.name)}</button>`;
    }).join('');
    dialogBody.innerHTML = `
      <h3>${esc(cls.name)}：配膳前チェック</h3>
      <p>2名で献立と食材を照らし合わせたら、その2名の名前をタップしてください。</p>
      <div class="choice-list">${items || '<p>職員が登録されていません。</p>'}</div>
      <button class="btn primary big" data-act="ok" ${picked.length === 2 ? '' : 'disabled'}>この2名で確認して記録</button>
      <button class="btn ghost" data-act="cancel">キャンセル</button>`;
  };
  openDialog('', (act, data) => {
    if (act === 'toggle') {
      const i = picked.indexOf(data.id);
      if (i >= 0) picked.splice(i, 1);
      else if (picked.length < 2) picked.push(data.id);
      else toast('2名までです。先にどちらかを外してください');
      draw();
      return true;
    }
    if (act === 'ok' && picked.length === 2) submitMealCheck(cls, picked);
    return false;
  });
  draw();
}

function onMealClick(e) {
  const b = e.target.closest('button[data-act]');
  if (!b) return;
  const act = b.dataset.act;
  const cls = currentClass();

  if (act === 'mealView') { ui.mealView = b.dataset.view; render(); return; }
  if (act === 'pickMealChild') { ui.mealChildId = b.dataset.id; render(); return; }
  if (act === 'printFoodChart') { window.print(); return; }
  if (act === 'mealCheck') { openMealCheckDialog(cls); return; }
  if (act === 'toggleMenuFood') {
    const menu = meals.menus.find((m) => m.classId === cls.id);
    const on = !(menu?.foodIds || []).includes(b.dataset.id);
    applyLocalMenuFood(cls.id, b.dataset.id, on);
    render();
    withInputter((recorderId) => saveMenuFood(cls, b.dataset.id, on, recorderId));
    return;
  }
  if (act === 'cycleChildFood') {
    const cur = meals.childFoods.find((cf) => cf.childId === ui.mealChildId && cf.foodId === b.dataset.id)?.status || 'none';
    const next = nextStatus(cur);
    applyLocalChildFood(ui.mealChildId, b.dataset.id, next);
    render();
    withInputter((recorderId) => saveChildFood(ui.mealChildId, b.dataset.id, next, recorderId));
  }
}

// ---------- 記録画面 ----------

const recordCache = new Map();

async function loadRecordDay(day) {
  if (st.mode !== 'server') return;
  try {
    const r = await api('GET', `/api/day?day=${day}`);
    recordCache.set(day, { naps: r.naps, rooms: r.rooms });
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
  let data;
  if (isToday) data = todayData();
  else if (recordCache.has(day)) data = recordCache.get(day);
  else {
    data = null;
    loadRecordDay(day);
  }

  const [y, m, d] = day.split('-').map(Number);
  const nav = `
    <div class="day-nav no-print">
      <button class="btn" data-act="prevDay" ${st.mode === 'demo' ? 'disabled' : ''}>前の日</button>
      <span>${m}月${d}日${isToday ? '（今日）' : ''}</span>
      <button class="btn" data-act="nextDay" ${isToday ? 'disabled' : ''}>次の日</button>
    </div>`;

  if (data === null) {
    view.innerHTML = `${nav}<p class="empty-note">読み込んでいます…</p>`;
    return;
  }

  // その日にこのクラスで寝た子（その後にクラス替え・停止した子も含む）と、今このクラスにいる子
  const childById = (id) => st.boot.children.find((c) => c.id === id);
  const napClass = (n) => n.classId || childById(n.childId)?.classId;
  const classNaps = data.naps.filter((n) => napClass(n) === cls.id);
  const rooms = data.rooms.filter((r) => r.classId === cls.id);
  const ids = new Set([...childrenOf(cls.id).map((c) => c.id), ...classNaps.map((n) => n.childId)]);
  const kids = st.boot.children.filter((c) => ids.has(c.id));
  // 確認間隔は、その日に午睡を始めた時点の値を使う（あとで設定を変えても過去の表は変わらない）
  const interval = classNaps.find((n) => n.intervalMin)?.intervalMin || cls.intervalMin;
  const { slots, rows } = buildRecordTable(kids, sessionsByChild(classNaps), interval, isToday ? Date.now() : null,
    rooms.map((r) => r.t));
  const title = `${y}年${m}月${d}日 ${cls.name} 午睡チェック表（${interval}分ごと）`;
  if (!slots.length) {
    view.innerHTML = `${nav}<p class="empty-note">${esc(cls.name)}のこの日の記録はありません。</p>`;
    return;
  }

  // 記録者に ①② の印（その日に初めて記録した順）
  const marks = recorderMarks([...classNaps.flatMap((n) => n.checks), ...rooms]);
  const markOf = (id) => marks.get(id) || '';
  const recorders = [...marks].map(([id, mark]) => `${mark} ${esc(staffName(id))}`).join('　');

  const head = slots.map((t) => `<th>${fmtTime(t)}〜</th>`).join('');
  const roomCells = slots.map(() => []);
  for (const r of rooms) {
    const i = slotIndex(slots, interval, r.t);
    if (i >= 0) roomCells[i].push(r);
  }
  const roomRow = rooms.length
    ? `<tr class="room-row"><td class="sticky">室温・湿度</td><td></td>${roomCells.map((list) => `<td class="cell">${list.map((r) =>
      `<div class="chk"><b class="room-v">${(r.tempC10 / 10).toFixed(1)}℃<br>${r.humidity}%</b><small>${fmtTime(r.t)} ${markOf(r.recorderId)}</small></div>`).join('')}</td>`).join('')}</tr>`
    : '';

  const body = rows.map(({ child, naps: sessions, cells, unclosed }) => {
    const napText = sessions.map((s) => `${fmtTime(s.start)}〜${s.end != null ? fmtTime(s.end) : ''}`).join('<br>') || '—';
    const warn = unclosed && !isToday ? '<br><span class="warn">起床の記録なし</span>' : '';
    const tds = cells.map((cell) => {
      if (!cell.checks.length) {
        return `<td class="cell ${cell.missing ? 'missing' : ''}">${cell.missing ? '<small>未</small>' : ''}</td>`;
      }
      const items = cell.checks.map((c) => {
        const p = POSTURES[c.posture];
        return `<div class="chk ${c.posture === 'prone' ? 'prone' : ''} ${c.late ? 'late' : ''}" title="${esc(p.label)} ${fmtTime(c.t)} ${esc(staffName(c.recorderId))}">
          <b>${c.fixed ? FIXED_SHORT : p.short}</b><small>${fmtTime(c.t)} ${markOf(c.recorderId)}</small></div>`;
      }).join('');
      return `<td class="cell">${items}</td>`;
    }).join('');
    return `<tr><td class="sticky">${esc(child.name)}</td><td>${napText}${warn}</td>${tds}</tr>`;
  }).join('');

  view.innerHTML = `
    ${nav}
    <div class="record-head no-print">
      <h2>${esc(title)}</h2>
      <button class="btn primary" data-act="print">印刷</button>
    </div>
    <h2 class="print-title">${esc(st.boot.facility.name)}　${esc(title)}</h2>
    <p class="recorders">記録者：${recorders || '—'}</p>
    <p class="legend">↑：仰向け　→：右向き　←：左向き　↓：うつぶせ　${FIXED_SHORT}：うつぶせを仰向けに直した
      小さい文字：確認した時刻と記録者　赤枠：前の確認から${interval}分を超えて確認した　未：確認が遅れていた時間枠</p>
    <div class="table-wrap">
      <table class="record">
        <thead><tr><th class="sticky">名前</th><th>入眠〜起床</th>${head}</tr></thead>
        <tbody>${roomRow}${body}</tbody>
      </table>
    </div>`;
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

let devices = null;

function renderSettings() {
  const sync = st.mode === 'server'
    ? `<p class="help">最後にサーバーと同期：${st.lastSync ? fmtTime(st.lastSync) : '—'}　送信待ち：${st.outbox.length}件</p>`
    : '';

  let html = `
    <div class="section">
      <h2>この端末</h2>
      <p class="help">${esc(st.boot.facility.name)}　端末の名前：${esc(st.boot.device.name)}</p>
      ${sync}
      <div class="toggle"><span>確認が遅れたら音と振動で知らせる</span>
        <button class="btn ${ui.sound ? 'primary' : ''}" data-act="sound">${ui.sound ? 'オン' : 'オフ'}</button></div>
      <p class="help gap-top">確認の間隔：0歳児クラスは5分ごと、それ以外は10分ごと</p>
    </div>`;

  if (st.mode === 'demo') {
    html += `<div class="section"><p class="help">デモでは、クラス・子ども・職員の登録や変更はできません。</p>
      <button class="btn danger" data-act="unregister">デモを終わる</button></div>`;
  } else if (isAdmin()) {
    html += adminSettingsHtml();
  } else {
    html += `
      <div class="section">
        <h2>管理者モード</h2>
        <p class="help">クラス・子ども・職員・端末の登録や変更は、管理者のパスワードを入れてから行います。10分たつと自動で戻ります。</p>
        <button class="btn primary" data-act="unlock">管理者モードにする</button>
      </div>`;
  }
  view.innerHTML = html;
}

function adminSettingsHtml() {
  const { classes, children, staff } = st.boot;
  const left = Math.max(0, Math.ceil((st.boot.admin.until - Date.now()) / 60000));

  const classRows = classes.map((c) => `
    <div class="list-item ${c.active ? '' : 'inactive'}">
      <span>${esc(c.name)}<small class="sub">${c.age}歳・${c.intervalMin}分ごと${c.active ? '' : '・停止中'}</small></span>
      <span class="item-actions">
        <button class="btn" data-act="renameClass" data-id="${c.id}">名前</button>
        <button class="btn ${c.active ? 'danger' : ''}" data-act="toggleClass" data-id="${c.id}">${c.active ? '停止' : '再開'}</button>
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
      <span>${esc(s.name)}<small class="sub">${s.role === 'admin' ? `管理者・${esc(s.loginId)}` : '職員'}${s.active ? '' : '・停止中'}</small></span>
      <span class="item-actions">
        <button class="btn" data-act="renameUser" data-id="${s.id}">名前</button>
        ${s.role === 'admin' ? `<button class="btn" data-act="resetPassword" data-id="${s.id}">パスワード</button>` : ''}
        <button class="btn ${s.active ? 'danger' : ''}" data-act="toggleUser" data-id="${s.id}">${s.active ? '停止' : '再開'}</button>
      </span>
    </div>`).join('');

  if (meals === null) loadMeals();
  const foodRows = meals ? meals.foods.map((f) => `
    <div class="list-item ${f.active ? '' : 'inactive'}">
      <span>${esc(f.name)}${f.category ? `<small class="sub">${esc(f.category)}</small>` : ''}${f.active ? '' : '（停止中）'}</span>
      <span class="item-actions">
        <button class="btn" data-act="renameFood" data-id="${f.id}">名前</button>
        <button class="btn ${f.active ? 'danger' : ''}" data-act="toggleFood" data-id="${f.id}">${f.active ? '停止' : '再開'}</button>
      </span>
    </div>`).join('') : '<p class="help">読み込んでいます…</p>';

  if (devices === null) loadDevices();
  const deviceRows = (devices || []).map((d) => `
    <div class="list-item">
      <span>${esc(d.name || '（名前なし）')}${d.current ? '（この端末）' : ''}<small class="sub">登録：${esc(d.registeredBy)}・${new Date(d.createdAt).toLocaleDateString('ja-JP')}</small></span>
      ${d.current ? '' : `<button class="btn danger" data-act="revokeDevice" data-id="${d.id}">登録解除</button>`}
    </div>`).join('');

  return `
    <div class="section admin-head">
      <div class="toggle"><span><b>管理者モード中</b>（${esc(st.boot.admin.name)}・あと${left}分）</span>
        <button class="btn" data-act="lock">管理者モードを終わる</button></div>
    </div>
    <div class="section">
      <h2>職員</h2>
      <p class="help">職員は名前を登録するだけです。端末で名前を選んで記録します。退職した人は「停止」にします（過去の記録の名前は残ります）。</p>
      ${staffRows}
      <form class="add-row" data-form="addStaff">
        <input name="name" placeholder="職員の名前" autocomplete="off" required maxlength="40">
        <button class="btn primary">追加</button>
      </form>
      <details class="gap-top">
        <summary>管理者を追加する（端末の登録・管理者モードに使うIDとパスワードを持つ人）</summary>
        <form class="add-row" data-form="addAdmin">
          <input name="name" placeholder="名前" autocomplete="off" required maxlength="40">
          <input name="loginId" placeholder="ログインID（半角英数字）" autocomplete="off" autocapitalize="none" required>
          <input name="password" placeholder="パスワード（8文字以上）" autocomplete="new-password" required minlength="8">
          <button class="btn primary">追加</button>
        </form>
      </details>
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
      <h2>クラス</h2>
      <p class="help">確認の間隔は年齢で決まります（0歳は5分、それ以外は10分）。</p>
      ${classRows}
      <form class="add-row" data-form="addClass">
        <input name="name" placeholder="クラスの名前" autocomplete="off" required maxlength="40">
        <select name="age">${[0, 1, 2, 3, 4, 5].map((a) => `<option value="${a}">${a}歳</option>`).join('')}</select>
        <button class="btn primary">追加</button>
      </form>
    </div>
    <div class="section">
      <h2>給食の食材</h2>
      <p class="help">園の食材チェック表の項目をまとめて登録できます（改行で区切って貼り付けてください）。</p>
      ${foodRows}
      <form class="add-row food-add-form" data-form="addFoods">
        <textarea name="names" class="field" placeholder="例：米&#10;にんじん&#10;たまご" rows="3" required></textarea>
        <input name="category" placeholder="分類（任意・例：野菜）" autocomplete="off" maxlength="20">
        <button class="btn primary">まとめて登録</button>
      </form>
    </div>
    <div class="section">
      <h2>登録している端末</h2>
      <p class="help">なくした端末や使わなくなった端末は、ここで登録を解除してください。</p>
      ${devices == null ? '<p class="help">読み込んでいます…</p>' : deviceRows}
      <div class="row gap-top">
        <button class="btn danger" data-act="revokeAll">この端末以外をすべて解除</button>
        <button class="btn danger" data-act="unregister">この端末の登録を解除</button>
      </div>
    </div>`;
}

async function loadDevices() {
  devices = undefined;
  try {
    devices = (await api('GET', '/api/admin/devices')).devices;
  } catch (e) {
    devices = [];
    handleApiError(e);
  }
  if (ui.tab === 'settings') render();
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
  const findChild = () => st.boot.children.find((x) => x.id === idOf);
  const findUser = () => staffById(idOf);
  const findClass = () => classById(idOf);

  if (act === 'sound') {
    ui.sound = !ui.sound;
    saveUi();
    if (ui.sound) beep();
    render();
  } else if (act === 'unregister') {
    unregister();
  } else if (act === 'unlock') {
    openDialog(`
      <h3>管理者モード</h3>
      <p>管理者のログインIDとパスワードを入れてください。10分たつと自動で戻ります。</p>
      <input id="adId" class="field" placeholder="ログインID" autocomplete="username" autocapitalize="none">
      <input id="adPw" class="field" type="password" placeholder="パスワード" autocomplete="current-password">
      <button class="btn primary big" data-act="ok">管理者モードにする</button>
      <button class="btn ghost" data-act="cancel">キャンセル</button>`, (a) => {
      if (a !== 'ok') return false;
      api('POST', '/api/admin/unlock', { loginId: $('#adId').value.trim(), password: $('#adPw').value })
        .then(() => { dialog.close(); devices = null; refreshBoot(); })
        .catch((ex) => toast(messageOf(ex)));
      return true;
    });
  } else if (act === 'lock') {
    adminCall('POST', '/api/admin/lock', {});
  } else if (act === 'renameChild') {
    const ch = findChild();
    inputDialog('名前の変更', '', { value: ch.name }, (v) => adminCall('PATCH', `/api/admin/children/${ch.id}`, { name: v }));
  } else if (act === 'moveChild') {
    const ch = findChild();
    const items = activeClasses().map((c) =>
      `<button class="btn ${c.id === ch.classId ? 'primary' : ''}" data-act="pick" data-id="${c.id}">${esc(c.name)}</button>`).join('');
    openDialog(`<h3>${esc(ch.name)}のクラス</h3><div class="choice-list">${items}</div>
      <button class="btn ghost" data-act="cancel">キャンセル</button>`, (a, data) => {
      if (a === 'pick' && data.id !== ch.classId) adminCall('PATCH', `/api/admin/children/${ch.id}`, { classId: data.id });
    });
  } else if (act === 'toggleChild') {
    const ch = findChild();
    if (ch.active) {
      confirmDialog(`${ch.name}を停止しますか？`, 'チェック画面に出なくなります。過去の記録は残ります。', '停止', () =>
        adminCall('PATCH', `/api/admin/children/${ch.id}`, { active: false }), true);
    } else {
      adminCall('PATCH', `/api/admin/children/${ch.id}`, { active: true });
    }
  } else if (act === 'renameUser') {
    const u = findUser();
    inputDialog('名前の変更', '', { value: u.name }, (v) => adminCall('PATCH', `/api/admin/users/${u.id}`, { name: v }));
  } else if (act === 'toggleUser') {
    const u = findUser();
    if (u.active) {
      const note = u.role === 'admin'
        ? 'この人が登録した端末も使えなくなります（登録し直しが必要です）。過去の記録の名前は残ります。'
        : '担当の選択肢に出なくなります。過去の記録の名前は残ります。';
      confirmDialog(`${u.name}を停止しますか？`, note, '停止', () =>
        adminCall('PATCH', `/api/admin/users/${u.id}`, { active: false }), true);
    } else {
      adminCall('PATCH', `/api/admin/users/${u.id}`, { active: true });
    }
  } else if (act === 'resetPassword') {
    const u = findUser();
    inputDialog(`${u.name}のパスワードを変更`, '8文字以上。この人が登録した端末は、登録し直しが必要になります。',
      { okLabel: '変更' }, (v) => adminCall('PATCH', `/api/admin/users/${u.id}`, { password: v }, 'パスワードを変更しました'));
  } else if (act === 'renameClass') {
    const c = findClass();
    inputDialog('クラスの名前', '', { value: c.name }, (v) => adminCall('PATCH', `/api/admin/classes/${c.id}`, { name: v }));
  } else if (act === 'toggleClass') {
    const c = findClass();
    if (c.active) {
      confirmDialog(`${c.name}を停止しますか？`, 'チェック画面に出なくなります。過去の記録は残ります。', '停止', () =>
        adminCall('PATCH', `/api/admin/classes/${c.id}`, { active: false }), true);
    } else {
      adminCall('PATCH', `/api/admin/classes/${c.id}`, { active: true });
    }
  } else if (act === 'renameFood') {
    const f = meals.foods.find((x) => x.id === idOf);
    inputDialog('食材の名前', '', { value: f.name }, (v) => adminMealCall('PATCH', `/api/admin/foods/${f.id}`, { name: v }));
  } else if (act === 'toggleFood') {
    const f = meals.foods.find((x) => x.id === idOf);
    if (f.active) {
      confirmDialog(`${f.name}を停止しますか？`, '献立・食べた食材の選択肢に出なくなります。過去の記録は残ります。', '停止', () =>
        adminMealCall('PATCH', `/api/admin/foods/${f.id}`, { active: false }), true);
    } else {
      adminMealCall('PATCH', `/api/admin/foods/${f.id}`, { active: true });
    }
  } else if (act === 'revokeDevice') {
    const d = devices.find((x) => x.id === idOf);
    confirmDialog(`「${d.name}」の登録を解除しますか？`, 'その端末では記録できなくなります。', '解除', async () => {
      await adminCall('POST', `/api/admin/devices/${d.id}`, {}, '登録を解除しました');
      loadDevices();
    }, true);
  } else if (act === 'revokeAll') {
    confirmDialog('この端末以外をすべて解除しますか？', 'ほかの端末は、管理者が登録し直すまで使えなくなります。', '解除', async () => {
      await adminCall('POST', '/api/admin/devices/revoke-all', {}, 'ほかの端末をすべて解除しました');
      loadDevices();
    }, true);
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
  } else if (form.dataset.form === 'addStaff') {
    ok = await adminCall('POST', '/api/admin/users', { name: f.name }, '追加しました');
  } else if (form.dataset.form === 'addAdmin') {
    ok = await adminCall('POST', '/api/admin/users',
      { name: f.name, loginId: f.loginId, password: f.password, role: 'admin' }, '管理者を追加しました');
  } else if (form.dataset.form === 'addClass') {
    ok = await adminCall('POST', '/api/admin/classes', { name: f.name, age: Number(f.age) }, '追加しました');
  } else if (form.dataset.form === 'addFoods') {
    const names = f.names.split('\n').map((s) => s.trim()).filter(Boolean);
    if (names.length) {
      const r = await adminMealCall('POST', '/api/admin/foods', { names, category: f.category || '' }, null);
      if (r) toast(`${names.length}件を登録しました`);
      ok = r;
    }
  }
  if (ok) form.reset();
}

// ---------- 全体 ----------

function render() {
  if (!st.boot || $('#appView').hidden) return;
  renderChrome();
  if (ui.tab === 'check') renderCheck();
  else if (ui.tab === 'meal') renderMeal();
  else if (ui.tab === 'record') renderRecord();
  else renderSettings();
}

document.querySelector('.tabs').addEventListener('click', (e) => {
  const t = e.target.closest('.tab');
  if (!t) return;
  ui.tab = t.dataset.tab;
  if (ui.tab !== 'record') ui.recordDay = null;
  if (ui.tab === 'settings') devices = null;
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

$('#staffBtn').addEventListener('click', switchInputter);

view.addEventListener('click', (e) => {
  if (ui.tab === 'check') onCheckClick(e);
  else if (ui.tab === 'meal') onMealClick(e);
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
let wasAdmin = false;
setInterval(() => {
  tickClock();
  if (!st.boot || $('#appView').hidden) return;
  const today = dateKey(Date.now());
  if (st.mode === 'demo' && st.day !== today) {
    st.day = today;
    st.data = EMPTY_DAY();
    persist();
    render();
  }
  // 管理者モードの時間が過ぎたら、画面も戻す
  if (wasAdmin && !isAdmin()) render();
  wasAdmin = isAdmin();
  const byChild = sessionsByChild(todayData().naps);
  checkAlerts(byChild);
  updateLive(byChild);
  // クラスの超過人数は、人数が変わった時だけ描き直す
  if (alerted.size !== lastOverdue) {
    lastOverdue = alerted.size;
    renderClassBar(byChild);
  }
}, 1000);
setInterval(poll, POLL_MS);
setInterval(pollMeals, POLL_MS);

// ---------- 起動 ----------

async function start() {
  tickClock();
  const savedUi = load(UI_KEY);
  if (savedUi) Object.assign(ui, { ...savedUi, recordDay: null, duty: savedUi.duty || {} });
  const cached = load(CACHE_KEY);

  if (cached?.boot && (cached.mode === 'server' || cached.mode === 'demo')) {
    // 前回の情報ですぐ表示し、裏でサーバーの最新を取りに行く（オフラインでも開ける）
    st = { ...st, ...cached };
    if (st.mode === 'demo' && st.day !== dateKey(Date.now())) {
      st.day = dateKey(Date.now());
      st.data = EMPTY_DAY();
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
