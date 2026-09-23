import {
  POSTURES, DEFAULT_INTERVALS, intervalMinutes, childStatus, startNap, recordCheck,
  endNap, undoLastCheck, summarize, buildRecordTable, fmtTime, fmtDuration, dateKey,
} from './logic.js';

// ---------- 保存（試作版：端末の中だけ） ----------

const CONFIG_KEY = 'hoiku-nap-config-v1';
const DAY_PREFIX = 'hoiku-nap-day-v1-';
const UI_KEY = 'hoiku-nap-ui-v1';

const SAMPLE_CONFIG = {
  intervals: { ...DEFAULT_INTERVALS },
  sound: true,
  staff: ['サンプル先生A', 'サンプル先生B', 'サンプル先生C'],
  currentStaff: '',
  classes: [
    { id: 'c0', name: '0歳児', age: 0 },
    { id: 'c1', name: '1歳児', age: 1 },
    { id: 'c2', name: '2歳児', age: 2 },
  ],
  children: [
    ['k1', 'サンプル あおい', 'c0'], ['k2', 'サンプル はると', 'c0'], ['k3', 'サンプル ゆい', 'c0'],
    ['k4', 'サンプル そうた', 'c1'], ['k5', 'サンプル めい', 'c1'], ['k6', 'サンプル りく', 'c1'],
    ['k7', 'サンプル こはる', 'c1'], ['k8', 'サンプル いつき', 'c2'], ['k9', 'サンプル ひなた', 'c2'],
    ['k10', 'サンプル さな', 'c2'], ['k11', 'サンプル れん', 'c2'],
  ].map(([id, name, classId]) => ({ id, name, classId })),
};

function load(key, fallback) {
  try {
    const raw = localStorage.getItem(key);
    return raw ? JSON.parse(raw) : fallback;
  } catch {
    return fallback;
  }
}

function save(key, value) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch {
    toast('この端末に保存できませんでした');
  }
}

let config = load(CONFIG_KEY, structuredClone(SAMPLE_CONFIG));
let today = dateKey(Date.now());
let day = load(DAY_PREFIX + today, { naps: {} });
let ui = { tab: 'check', classId: config.classes[0]?.id, ...load(UI_KEY, {}) };
if (!config.classes.some((c) => c.id === ui.classId)) ui.classId = config.classes[0]?.id;

const saveConfig = () => save(CONFIG_KEY, config);
const saveDay = () => save(DAY_PREFIX + today, day);
const saveUi = () => save(UI_KEY, ui);

// ---------- 画面の部品 ----------

const $ = (sel) => document.querySelector(sel);
const view = $('#view');
const dialog = $('#dialog');
const dialogBody = $('#dialogBody');

function esc(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function currentClass() {
  return config.classes.find((c) => c.id === ui.classId);
}

function childrenOf(classId) {
  return config.children.filter((ch) => ch.classId === classId);
}

function classOfChild(child) {
  return config.classes.find((c) => c.id === child.classId);
}

function intervalForChild(child) {
  return intervalMinutes(classOfChild(child)?.age, config.intervals);
}

function statusOf(child, now = Date.now()) {
  return childStatus(day.naps[child.id], now, intervalForChild(child));
}

function toast(msg) {
  const el = document.createElement('div');
  el.textContent = msg;
  Object.assign(el.style, {
    position: 'fixed', left: '50%', bottom: '24px', transform: 'translateX(-50%)',
    background: '#1f2a26', color: '#fff', padding: '10px 16px', borderRadius: '10px',
    fontSize: '14px', zIndex: 100, maxWidth: 'calc(100vw - 32px)',
  });
  document.body.appendChild(el);
  setTimeout(() => el.remove(), 2200);
}

function openDialog(html, onClick) {
  dialogBody.innerHTML = html;
  dialogBody.onclick = (e) => {
    const b = e.target.closest('button[data-act]');
    if (!b) return;
    e.preventDefault();
    const keep = onClick?.(b.dataset.act, b.dataset);
    if (!keep) dialog.close();
  };
  dialog.showModal();
}

// ---------- ヘッダー・タブ・クラス ----------

function renderChrome() {
  const staffBtn = $('#staffBtn');
  staffBtn.textContent = config.currentStaff ? `記録者：${config.currentStaff}` : '記録者を選ぶ';
  staffBtn.classList.toggle('empty', !config.currentStaff);

  document.querySelectorAll('.tab').forEach((t) => t.classList.toggle('active', t.dataset.tab === ui.tab));

  const bar = $('#classBar');
  bar.style.display = ui.tab === 'settings' ? 'none' : '';
  bar.innerHTML = config.classes.map((c) => {
    const alerts = childrenOf(c.id).filter((ch) => statusOf(ch).state === 'overdue').length;
    return `<button type="button" class="class-chip ${c.id === ui.classId ? 'active' : ''}" data-class="${c.id}">
      ${esc(c.name)}${alerts ? ` <span aria-label="確認超過">(${alerts})</span>` : ''}</button>`;
  }).join('');
}

function tickClock() {
  const d = new Date();
  $('#clock').textContent = `${d.getHours()}:${String(d.getMinutes()).padStart(2, '0')}`;
}

function pickStaff(then) {
  const items = config.staff.map((s) =>
    `<button class="btn ${s === config.currentStaff ? 'primary' : ''}" data-act="pick" data-name="${esc(s)}">${esc(s)}</button>`).join('');
  openDialog(`
    <h3>記録者を選んでください</h3>
    <p>チェックの記録に、この名前が残ります。</p>
    <div class="choice-list">${items || '<p>設定タブで職員を登録してください。</p>'}</div>
    <button class="btn ghost" data-act="cancel">閉じる</button>`, (act, data) => {
    if (act === 'pick') {
      config.currentStaff = data.name;
      saveConfig();
      render();
      then?.();
    }
  });
}

// ---------- チェック画面 ----------

function cardHtml(child, st) {
  const name = `<span class="name">${esc(child.name)}</span>`;
  if (st.state === 'before') {
    return `<div class="card before" data-id="${child.id}">
      <div class="card-head">${name}<span class="pill">起きている</span></div>
      <button class="btn primary big" data-act="start">午睡開始</button>
    </div>`;
  }
  if (st.state === 'awake') {
    const s = st.session;
    return `<div class="card awake" data-id="${child.id}">
      <div class="card-head">${name}<span class="pill">起床</span></div>
      <div class="meta">${fmtTime(s.start)}〜${fmtTime(s.end)}（${fmtDuration(s.end - s.start)}）確認${s.checks.length}回</div>
      <button class="btn" data-act="start">もう一度寝た</button>
    </div>`;
  }
  const buttons = Object.entries(POSTURES).map(([key, p]) =>
    `<button class="pbtn ${key}" data-act="check" data-posture="${key}">${p.short}<small>${p.label}</small></button>`).join('');
  return `<div class="card ${st.state}" data-id="${child.id}">
    <div class="card-head">${name}<span class="pill" data-role="pill"></span></div>
    <div class="meta" data-role="meta"></div>
    <div class="postures">${buttons}</div>
    <div class="row">
      <button class="btn ghost" data-act="undo" ${st.session.checks.length ? '' : 'disabled'}>1つ取り消す</button>
      <button class="btn" data-act="end">起床</button>
    </div>
  </div>`;
}

function renderCheck() {
  const cls = currentClass();
  if (!cls) {
    view.innerHTML = '<p class="empty-note">設定タブでクラスを登録してください。</p>';
    return;
  }
  const kids = childrenOf(cls.id);
  const beforeCount = kids.filter((ch) => statusOf(ch).state === 'before').length;
  view.innerHTML = `
    <div class="summary" id="summary"></div>
    <div class="bulk">
      <button class="btn" data-act="startAll" ${beforeCount ? '' : 'disabled'}>まだ寝ていない${beforeCount}名をまとめて午睡開始</button>
    </div>
    <p class="meta">確認間隔：${intervalMinutes(cls.age, config.intervals)}分ごと（設定タブで変更できます）</p>
    <div class="grid">${kids.map((ch) => cardHtml(ch, statusOf(ch))).join('') || '<p class="empty-note">このクラスには子どもが登録されていません。</p>'}</div>`;
  updateLive();
}

// 1秒ごとの更新は文字と色だけ書き換える（ボタンを押している途中で作り直さないため）
function updateLive() {
  if (ui.tab !== 'check') return;
  const now = Date.now();
  const cls = currentClass();
  if (!cls) return;
  const kids = childrenOf(cls.id);
  const statuses = [];
  for (const ch of kids) {
    const st = statusOf(ch, now);
    statuses.push(st);
    const card = view.querySelector(`.card[data-id="${ch.id}"]`);
    if (!card) continue;
    const isSleeping = ['ok', 'soon', 'overdue'].includes(st.state);
    if (!isSleeping) continue;
    card.classList.remove('ok', 'soon', 'overdue');
    card.classList.add(st.state);
    const pill = card.querySelector('[data-role="pill"]');
    const meta = card.querySelector('[data-role="meta"]');
    pill.textContent = st.state === 'overdue' ? `超過 ${fmtDuration(st.remain)}` : `あと ${fmtDuration(st.remain)}`;
    meta.textContent = st.last
      ? `最終 ${fmtTime(st.last.t)} ${POSTURES[st.last.posture].label}${st.last.fixed ? '→仰向けに直した' : ''}（${st.last.staff || '記録者なし'}）`
      : `${fmtTime(st.session.start)} 入眠・まだ確認していません`;
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

function withStaff(fn) {
  if (config.currentStaff) fn();
  else pickStaff(fn);
}

function setNaps(childId, sessions) {
  day.naps[childId] = sessions;
  alerted.delete(childId);
  saveDay();
}

function onCheckClick(e) {
  const b = e.target.closest('button[data-act]');
  if (!b) return;
  const act = b.dataset.act;
  const now = Date.now();

  if (act === 'startAll') {
    for (const ch of childrenOf(ui.classId)) {
      if (statusOf(ch).state === 'before') setNaps(ch.id, startNap(day.naps[ch.id], now));
    }
    render();
    return;
  }

  const card = b.closest('.card');
  if (!card) return;
  const child = config.children.find((c) => c.id === card.dataset.id);
  const sessions = day.naps[child.id] || [];

  if (act === 'start') {
    setNaps(child.id, startNap(sessions, now));
    render();
  } else if (act === 'check') {
    const posture = b.dataset.posture;
    withStaff(() => {
      if (posture === 'prone') {
        openDialog(`
          <h3>${esc(child.name)}：うつぶせ</h3>
          <p>仰向けに直してから「直した」を押してください。記録には「うつぶせ→仰向けに直した」と残ります。</p>
          <button class="btn primary big" data-act="fixed">仰向けに直した</button>
          <button class="btn ghost" data-act="cancel">キャンセル</button>`, (a) => {
          if (a === 'fixed') {
            setNaps(child.id, recordCheck(day.naps[child.id], Date.now(), 'prone', config.currentStaff, true));
            render();
          }
        });
      } else {
        setNaps(child.id, recordCheck(day.naps[child.id], Date.now(), posture, config.currentStaff));
        render();
      }
    });
  } else if (act === 'undo') {
    setNaps(child.id, undoLastCheck(sessions));
    render();
  } else if (act === 'end') {
    openDialog(`
      <h3>${esc(child.name)}：起床にしますか？</h3>
      <button class="btn primary big" data-act="ok">起床</button>
      <button class="btn ghost" data-act="cancel">キャンセル</button>`, (a) => {
      if (a === 'ok') {
        setNaps(child.id, endNap(day.naps[child.id], Date.now()));
        render();
      }
    });
  }
}

// ---------- 確認遅れの通知（音・振動） ----------

const alerted = new Set();
let audioCtx;

function beep() {
  if (!config.sound) return;
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

function checkAlerts() {
  let fresh = false;
  for (const ch of config.children) {
    if (statusOf(ch).state === 'overdue') {
      if (!alerted.has(ch.id)) { alerted.add(ch.id); fresh = true; }
    } else {
      alerted.delete(ch.id);
    }
  }
  if (fresh) beep();
}

// ---------- 記録画面 ----------

function renderRecord() {
  const cls = currentClass();
  if (!cls) {
    view.innerHTML = '<p class="empty-note">クラスが登録されていません。</p>';
    return;
  }
  const kids = childrenOf(cls.id);
  const interval = intervalMinutes(cls.age, config.intervals);
  const { slots, rows } = buildRecordTable(kids, day.naps, interval, Date.now());
  const [y, m, d] = today.split('-').map(Number);
  const title = `${y}年${m}月${d}日 ${cls.name} 午睡チェック表（${interval}分ごと）`;

  if (!slots.length) {
    view.innerHTML = `<p class="empty-note">${esc(cls.name)}の今日の記録はまだありません。</p>`;
    return;
  }

  const head = slots.map((t) => `<th>${fmtTime(t)}</th>`).join('');
  const body = rows.map(({ child, naps, cells }) => {
    const napText = naps.map((s) => `${fmtTime(s.start)}〜${s.end != null ? fmtTime(s.end) : ''}`).join('<br>') || '—';
    const tds = cells.map((c, i) => {
      if (c) {
        const p = POSTURES[c.posture];
        const txt = c.fixed ? `${p.short}→仰` : p.short;
        return `<td class="cell ${c.posture === 'prone' ? 'prone' : ''}" title="${esc(p.label)} ${fmtTime(c.t)} ${esc(c.staff)}"><b>${txt}</b><small>${esc(initial(c.staff))}</small></td>`;
      }
      const slotStart = slots[i];
      const slotEnd = slotStart + interval * 60 * 1000;
      const asleep = naps.some((s) => s.start < slotEnd - 60 * 1000 && (s.end == null ? Date.now() : s.end) > slotEnd);
      return `<td class="cell ${asleep ? 'missing' : ''}">${asleep ? '<small>未</small>' : ''}</td>`;
    }).join('');
    return `<tr><td class="sticky">${esc(child.name)}</td><td>${napText}</td>${tds}</tr>`;
  }).join('');

  view.innerHTML = `
    <div class="record-head no-print">
      <h2>${esc(title)}</h2>
      <button class="btn primary" data-act="print">印刷</button>
    </div>
    <h2 class="print-title">${esc(title)}</h2>
    <p class="legend">仰：仰向け　右：右向き　左：左向き　う：うつぶせ（う→仰：仰向けに直した）　未：その時間枠に確認の記録がない　小さい文字：記録者</p>
    <div class="table-wrap">
      <table class="record">
        <thead><tr><th class="sticky">名前</th><th>入眠〜起床</th>${head}</tr></thead>
        <tbody>${body}</tbody>
      </table>
    </div>`;
}

function initial(name) {
  if (!name) return '';
  const trimmed = name.replace(/サンプル|先生/g, '').trim() || name;
  return trimmed.slice(0, 3);
}

// ---------- 設定画面 ----------

function renderSettings() {
  const intervalRows = config.classes.map((c) => `
    <div class="stepper">
      <span>${esc(c.name)}</span>
      <span class="ctrl">
        <button class="btn" data-act="int-" data-age="${c.age}" aria-label="短くする">−</button>
        <b>${intervalMinutes(c.age, config.intervals)}分</b>
        <button class="btn" data-act="int+" data-age="${c.age}" aria-label="長くする">＋</button>
      </span>
    </div>`).join('');

  const staffRows = config.staff.map((s, i) => `
    <div class="list-item"><span>${esc(s)}</span>
      <button class="btn danger" data-act="delStaff" data-i="${i}">削除</button></div>`).join('');

  const childRows = config.classes.map((c) => {
    const kids = childrenOf(c.id).map((ch) => `
      <div class="list-item"><span>${esc(ch.name)}</span>
        <button class="btn danger" data-act="delChild" data-id="${ch.id}">削除</button></div>`).join('');
    return `<h2>${esc(c.name)}</h2>${kids || '<p class="help">登録なし</p>'}`;
  }).join('');

  const classOptions = config.classes.map((c) =>
    `<option value="${c.id}" ${c.id === ui.classId ? 'selected' : ''}>${esc(c.name)}</option>`).join('');

  view.innerHTML = `
    <div class="section">
      <h2>確認間隔</h2>
      <p class="help">初期値は0歳5分・1〜2歳10分です。園のマニュアルや自治体の指針に合わせて変更してください。</p>
      ${intervalRows}
    </div>
    <div class="section">
      <div class="toggle"><h2 style="margin:0">確認が遅れたら音と振動で知らせる</h2>
        <button class="btn ${config.sound ? 'primary' : ''}" data-act="sound">${config.sound ? 'オン' : 'オフ'}</button></div>
    </div>
    <div class="section">
      <h2>職員（記録者）</h2>
      ${staffRows || '<p class="help">登録なし</p>'}
      <div class="add-row">
        <input id="staffName" placeholder="職員の名前" autocomplete="off">
        <button class="btn primary" data-act="addStaff">追加</button>
      </div>
    </div>
    <div class="section">
      <p class="help">試作版のため、実在の園児の名前は入れないでください。</p>
      ${childRows}
      <div class="add-row">
        <input id="childName" placeholder="名前（例：サンプル たろう）" autocomplete="off">
        <select id="childClass">${classOptions}</select>
        <button class="btn primary" data-act="addChild">追加</button>
      </div>
    </div>
    <div class="section">
      <h2>データ</h2>
      <div class="row">
        <button class="btn danger" data-act="clearToday">今日の記録を消す</button>
        <button class="btn danger" data-act="resetAll">サンプルに戻す</button>
      </div>
    </div>`;
}

function onSettingsClick(e) {
  const b = e.target.closest('button[data-act]');
  if (!b) return;
  const act = b.dataset.act;
  if (act === 'int-' || act === 'int+') {
    const age = b.dataset.age;
    const cur = intervalMinutes(age, config.intervals);
    config.intervals[age] = Math.min(30, Math.max(1, cur + (act === 'int+' ? 1 : -1)));
  } else if (act === 'sound') {
    config.sound = !config.sound;
    if (config.sound) beep();
  } else if (act === 'addStaff') {
    const name = $('#staffName').value.trim();
    if (!name) return;
    if (!config.staff.includes(name)) config.staff.push(name);
  } else if (act === 'delStaff') {
    const [removed] = config.staff.splice(Number(b.dataset.i), 1);
    if (removed === config.currentStaff) config.currentStaff = '';
  } else if (act === 'addChild') {
    const name = $('#childName').value.trim();
    if (!name) return;
    config.children.push({ id: `k${Date.now().toString(36)}`, name, classId: $('#childClass').value });
  } else if (act === 'delChild') {
    const child = config.children.find((c) => c.id === b.dataset.id);
    openDialog(`<h3>${esc(child.name)}を削除しますか？</h3>
      <button class="btn danger big" data-act="ok">削除</button>
      <button class="btn ghost" data-act="cancel">キャンセル</button>`, (a) => {
      if (a === 'ok') {
        config.children = config.children.filter((c) => c.id !== child.id);
        saveConfig();
        render();
      }
    });
    return;
  } else if (act === 'clearToday') {
    openDialog(`<h3>今日の午睡記録をすべて消しますか？</h3><p>元に戻せません。</p>
      <button class="btn danger big" data-act="ok">消す</button>
      <button class="btn ghost" data-act="cancel">キャンセル</button>`, (a) => {
      if (a === 'ok') {
        day = { naps: {} };
        saveDay();
        render();
      }
    });
    return;
  } else if (act === 'resetAll') {
    openDialog(`<h3>設定をサンプルに戻しますか？</h3><p>職員・子ども・確認間隔が初期状態になります。</p>
      <button class="btn danger big" data-act="ok">戻す</button>
      <button class="btn ghost" data-act="cancel">キャンセル</button>`, (a) => {
      if (a === 'ok') {
        config = structuredClone(SAMPLE_CONFIG);
        ui.classId = config.classes[0].id;
        saveConfig();
        saveUi();
        render();
      }
    });
    return;
  }
  saveConfig();
  render();
}

// ---------- 全体 ----------

function render() {
  renderChrome();
  if (ui.tab === 'check') renderCheck();
  else if (ui.tab === 'record') renderRecord();
  else renderSettings();
}

document.querySelector('.tabs').addEventListener('click', (e) => {
  const t = e.target.closest('.tab');
  if (!t) return;
  ui.tab = t.dataset.tab;
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

$('#staffBtn').addEventListener('click', () => pickStaff());

view.addEventListener('click', (e) => {
  if (e.target.closest('[data-act="print"]')) { window.print(); return; }
  if (ui.tab === 'check') onCheckClick(e);
  else if (ui.tab === 'settings') onSettingsClick(e);
});

// 日付が変わったら、その日の記録に切り替える
function rollDay() {
  const k = dateKey(Date.now());
  if (k === today) return;
  today = k;
  day = load(DAY_PREFIX + today, { naps: {} });
  alerted.clear();
  render();
}

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
document.addEventListener('visibilitychange', keepAwake);
document.addEventListener('click', keepAwake, { once: true });

let lastOverdueCount = -1;
setInterval(() => {
  rollDay();
  tickClock();
  checkAlerts();
  updateLive();
  // クラスタブの超過件数だけは状態が変わった時に描き直す
  const overdue = alerted.size;
  if (overdue !== lastOverdueCount) {
    lastOverdueCount = overdue;
    renderChrome();
  }
}, 1000);

tickClock();
render();

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('sw.js').catch(() => {});
}
