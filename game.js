(() => {
  "use strict";

  // ---------------------------------------------------------------
  // Constants
  // ---------------------------------------------------------------
  const REF_H = 800;              // reference design height (world/vertical units)
  const ROAD_MARGIN = 0.07;       // fraction of screen width reserved outside the road on each side
  const LOOKAHEAD = 900;          // how far ahead (world units) to keep rows spawned
  const REMOVE_MARGIN = 120;      // remove rows this far behind the player
  const PLAYER_SCREEN_FRAC = 0.74; // player's fixed vertical position (fraction of height)
  const SPEED_BASE = 150;
  const SPEED_MAX = 430;

  const SAVE_KEY = "crowdrush_save_v1";

  const UPGRADES = [
    { key: "startCrowd", name: "初期人数",   icon: "👥", base: 40, growth: 1.55, maxLevel: 10, step: 5,
      effect: (lv) => `開始人数 +${lv * 5}` },
    { key: "control",    name: "操作性",     icon: "🎮", base: 70, growth: 1.65, maxLevel: 5,
      effect: (lv) => `曲がる速さ Lv.${lv}` },
    { key: "magnet",     name: "マグネット", icon: "🧲", base: 55, growth: 1.6,  maxLevel: 5,
      effect: (lv) => `コイン獲得範囲 Lv.${lv}` },
    { key: "luck",       name: "ラック",     icon: "🍀", base: 90, growth: 1.7,  maxLevel: 5,
      effect: (lv) => `良いゲート率 Lv.${lv}` },
  ];

  function upgradeCost(def, level) {
    return Math.round(def.base * Math.pow(def.growth, level));
  }

  // ---------------------------------------------------------------
  // Save data
  // ---------------------------------------------------------------
  function loadSave() {
    try {
      const raw = localStorage.getItem(SAVE_KEY);
      if (raw) {
        const parsed = JSON.parse(raw);
        return Object.assign({ coins: 0, best: 0, upgrades: {} }, parsed);
      }
    } catch (e) { /* ignore corrupt save */ }
    return { coins: 0, best: 0, upgrades: {} };
  }
  function saveGame() {
    try { localStorage.setItem(SAVE_KEY, JSON.stringify(save)); } catch (e) { /* storage unavailable */ }
  }

  let save = loadSave();

  // ---------------------------------------------------------------
  // Canvas setup
  // ---------------------------------------------------------------
  const canvas = document.getElementById("game");
  const ctx = canvas.getContext("2d");

  let cssW = 0, cssH = 0, DPR = 1, VSCALE = 1;
  let roadX0 = 0, roadW = 0;

  function resize() {
    cssW = window.innerWidth;
    cssH = window.innerHeight;
    DPR = Math.min(window.devicePixelRatio || 1, 2.5);
    canvas.width = Math.round(cssW * DPR);
    canvas.height = Math.round(cssH * DPR);
    canvas.style.width = cssW + "px";
    canvas.style.height = cssH + "px";
    ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
    VSCALE = cssH / REF_H;
    roadX0 = cssW * ROAD_MARGIN;
    roadW = cssW * (1 - ROAD_MARGIN * 2);
  }
  window.addEventListener("resize", resize);
  resize();

  // ---------------------------------------------------------------
  // Utility
  // ---------------------------------------------------------------
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  const lerp = (a, b, t) => a + (b - a) * t;
  const rand = (a, b) => a + Math.random() * (b - a);
  const choice = (arr) => arr[(Math.random() * arr.length) | 0];

  function fmtNum(n) {
    n = Math.round(n);
    if (n >= 1000000) return (n / 1000000).toFixed(1).replace(/\.0$/, "") + "M";
    if (n >= 1000) return (n / 1000).toFixed(1).replace(/\.0$/, "") + "K";
    return String(n);
  }

  const GATE_COLORS = {
    x: "#3fa9ff",
    "+": "#3fd67a",
    "-": "#ff5b6e",
    "/": "#ff9f43",
  };

  // ---------------------------------------------------------------
  // Game state
  // ---------------------------------------------------------------
  let state = "menu"; // menu | playing | gameover | shop
  let world = { rows: [], pickups: [], scrollY: 0 };
  let player = { f: 0.5, targetF: 0.5, count: 0, displayCount: 0, bump: 0 };
  let particles = [];
  let popups = [];
  let shake = { time: 0, mag: 0 };
  let runStats = { coins: 0, maxCount: 0 };
  let input;

  function upLevel(key) { return (save.upgrades[key] | 0); }

  function newGame() {
    const startLv = upLevel("startCrowd");
    world = {
      scrollY: 0,
      speed: SPEED_BASE,
      nextSpawnY: 260,
      lastWallY: -99999,
      wallIndex: 0,
      rows: [],
      pickups: [],
    };
    player = {
      f: 0.5,          // horizontal position as fraction of road width [0,1]
      targetF: 0.5,
      count: 10 + startLv * 5,
      displayCount: 10 + startLv * 5,
      bump: 0,
    };
    particles = [];
    popups = [];
    shake = { time: 0, mag: 0 };
    runStats = { coins: 0, maxCount: player.count };

    // seed the road with a few easy rows before the first wall
    for (let i = 0; i < 4; i++) spawnNextRow();
  }

  // ---------------------------------------------------------------
  // Procedural generation
  // ---------------------------------------------------------------
  function spawnNextRow() {
    const dist = world.nextSpawnY;
    const sinceWall = dist - world.lastWallY;
    const luckLv = upLevel("luck");
    const negChance = Math.max(0.08, 0.30 - luckLv * 0.04);

    const wallDue = sinceWall > rand(620, 780) && dist > 480;

    if (wallDue) {
      const base = 22 + world.wallIndex * 14;
      const value = Math.round(base * Math.pow(1.28, world.wallIndex) * rand(0.85, 1.15));
      world.rows.push({
        kind: "wall",
        worldY: dist,
        value: Math.max(6, value),
        processed: false,
        state: "idle", // idle | broken | failed
        stateTime: 0,
      });
      world.lastWallY = dist;
      world.wallIndex++;
      world.nextSpawnY = dist + rand(150, 210);
      return;
    }

    // gate row: 2-3 segments covering the full width
    const segCount = Math.random() < 0.38 ? 3 : 2;
    const bounds = [0];
    for (let i = 1; i < segCount; i++) bounds.push(i / segCount);
    bounds.push(1);

    const growth = 1 + dist * 0.0016;
    const segments = [];
    for (let i = 0; i < segCount; i++) {
      const isBad = Math.random() < negChance;
      let op, value, color;
      if (isBad) {
        op = Math.random() < 0.5 ? "-" : "/";
        value = op === "-" ? Math.round(rand(4, 14) * growth) : choice([2, 2, 3]);
        color = GATE_COLORS[op];
      } else {
        op = Math.random() < 0.55 ? "+" : "x";
        if (op === "+") {
          value = Math.round(rand(5, 22) * growth);
        } else {
          value = choice([2, 2, 2, 3, 3, 4]);
        }
        color = GATE_COLORS[op];
      }
      segments.push({ x0: bounds[i], x1: bounds[i + 1], op, value, color });
    }

    world.rows.push({
      kind: "gate",
      worldY: dist,
      segments,
      processed: false,
    });

    // occasional coin/gem pickup between gates
    if (Math.random() < 0.55) {
      const isGem = Math.random() < 0.18;
      world.pickups.push({
        worldY: dist - rand(30, 70),
        f: clamp(rand(0.15, 0.85), 0.08, 0.92),
        value: isGem ? 5 : 1,
        gem: isGem,
        collected: false,
      });
    }

    world.nextSpawnY = dist + rand(90, 140);
  }

  // ---------------------------------------------------------------
  // Interaction resolution
  // ---------------------------------------------------------------
  function triggerGameOver(reason) {
    if (state !== "playing") return;
    state = "gameover";
    save.coins += runStats.coins;
    const isBest = Math.round(world.scrollY / 8) > save.best;
    if (isBest) save.best = Math.round(world.scrollY / 8);
    saveGame();
    showGameOver(reason, isBest);
  }

  function applyGateSegment(seg) {
    let before = player.count;
    switch (seg.op) {
      case "x": player.count = Math.floor(player.count * seg.value); break;
      case "+": player.count = player.count + seg.value; break;
      case "-": player.count = Math.max(0, player.count - seg.value); break;
      case "/": player.count = Math.floor(player.count / seg.value); break;
    }
    const px = roadX0 + player.f * roadW;
    const py = cssH * PLAYER_SCREEN_FRAC;
    const good = player.count >= before;
    spawnPopup(px, py - 10, (good ? "+" : "") + (player.count - before), good ? "#8fffb0" : "#ff8a95");
    spawnBurst(px, py, seg.color, 14);
    player.bump = 1;
    runStats.maxCount = Math.max(runStats.maxCount, player.count);
    if (player.count <= 0) triggerGameOver("crowd");
  }

  function resolveWall(row) {
    row.processed = true;
    const px = roadX0 + player.f * roadW;
    const py = cssH * PLAYER_SCREEN_FRAC;
    if (player.count >= row.value) {
      row.state = "broken";
      const reward = Math.max(1, Math.round(row.value * 0.12));
      runStats.coins += reward;
      spawnPopup(px, py - 20, "🪙+" + reward, "#ffd166");
      spawnBurst(px, py, "#ffd166", 26);
      shake.time = 0.25; shake.mag = 10;
      player.bump = 1;
    } else {
      row.state = "failed";
      spawnBurst(px, py, "#ff5b6e", 34);
      shake.time = 0.4; shake.mag = 16;
      triggerGameOver("wall");
    }
  }

  function resolveGateRow(row) {
    row.processed = true;
    const seg = row.segments.find(s => player.f >= s.x0 && player.f < s.x1) || row.segments[row.segments.length - 1];
    applyGateSegment(seg);
  }

  // ---------------------------------------------------------------
  // Particles & popups
  // ---------------------------------------------------------------
  function spawnBurst(x, y, color, count) {
    for (let i = 0; i < count; i++) {
      const a = rand(0, Math.PI * 2);
      const sp = rand(60, 260);
      particles.push({
        x, y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp - 40,
        life: rand(0.35, 0.7), maxLife: 0.7, color, size: rand(2, 5),
      });
    }
  }
  function spawnPopup(x, y, text, color) {
    popups.push({ x, y, text, color, life: 0.9, maxLife: 0.9, vy: -46 });
  }

  // ---------------------------------------------------------------
  // Input
  // ---------------------------------------------------------------
  input = { active: false, startX: 0, startF: 0.5 };

  function pointerX(e) {
    return (e.touches && e.touches[0]) ? e.touches[0].clientX : e.clientX;
  }
  canvas.addEventListener("pointerdown", (e) => {
    if (state !== "playing") return;
    input.active = true;
    input.startX = pointerX(e);
    input.startF = player.targetF;
  });
  window.addEventListener("pointermove", (e) => {
    if (!input.active) return;
    const dx = pointerX(e) - input.startX;
    player.targetF = clamp(input.startF + dx / roadW, 0.03, 0.97);
  });
  window.addEventListener("pointerup", () => { input.active = false; });
  window.addEventListener("pointercancel", () => { input.active = false; });

  // ---------------------------------------------------------------
  // Update
  // ---------------------------------------------------------------
  function update(dt) {
    dt = Math.min(dt, 0.05);

    world.speed = clamp(SPEED_BASE + world.scrollY * 0.03, SPEED_BASE, SPEED_MAX);
    world.scrollY += world.speed * dt;

    const controlLv = upLevel("control");
    const t = 1 - Math.pow(1 - clamp(0.22 + controlLv * 0.09, 0.1, 0.85), dt * 60);
    player.f = lerp(player.f, player.targetF, t);
    player.displayCount = lerp(player.displayCount, player.count, 1 - Math.pow(0.001, dt));
    player.bump = Math.max(0, player.bump - dt * 4);

    while (world.nextSpawnY < world.scrollY + LOOKAHEAD) spawnNextRow();

    for (const row of world.rows) {
      if (!row.processed && row.worldY - world.scrollY <= 0) {
        if (row.kind === "wall") resolveWall(row); else resolveGateRow(row);
      }
      if (row.kind === "wall" && row.state !== "idle") row.stateTime += dt;
    }
    world.rows = world.rows.filter(r => (r.worldY - world.scrollY) > -REMOVE_MARGIN);

    const magnetLv = upLevel("magnet");
    const magnetPx = (34 + magnetLv * 16);
    const playerPx = roadX0 + player.f * roadW;
    for (const p of world.pickups) {
      if (p.collected) continue;
      if (p.worldY - world.scrollY <= 10) {
        const px = roadX0 + p.f * roadW;
        if (Math.abs(px - playerPx) < magnetPx) {
          p.collected = true;
          runStats.coins += p.value;
          spawnPopup(px, cssH * PLAYER_SCREEN_FRAC - 20, "🪙+" + p.value, "#ffd166");
        }
      }
    }
    world.pickups = world.pickups.filter(p => !p.collected && (p.worldY - world.scrollY) > -REMOVE_MARGIN);

    for (const pt of particles) {
      pt.life -= dt;
      pt.x += pt.vx * dt;
      pt.y += pt.vy * dt;
      pt.vy += 420 * dt;
    }
    particles = particles.filter(p => p.life > 0);

    for (const pu of popups) {
      pu.life -= dt;
      pu.y += pu.vy * dt;
    }
    popups = popups.filter(p => p.life > 0);

    if (shake.time > 0) shake.time = Math.max(0, shake.time - dt);

    updateHud();
  }

  // ---------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------
  function worldToScreenY(worldY) {
    return cssH * PLAYER_SCREEN_FRAC - (worldY - world.scrollY) * VSCALE;
  }

  function draw() {
    ctx.clearRect(0, 0, cssW, cssH);

    ctx.save();
    if (shake.time > 0) {
      const m = shake.mag * (shake.time / 0.4);
      ctx.translate(rand(-m, m), rand(-m, m));
    }

    drawBackground();
    if (state === "playing" || state === "gameover") {
      drawRoad();
      for (const row of world.rows) drawRow(row);
      for (const p of world.pickups) drawPickup(p);
      drawPlayer();
      drawParticles();
      drawPopups();
    }
    ctx.restore();
  }

  function drawBackground() {
    const g = ctx.createLinearGradient(0, 0, 0, cssH);
    g.addColorStop(0, "#7fd4ff");
    g.addColorStop(1, "#bfeeb0");
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, cssW, cssH);
  }

  function drawRoad() {
    ctx.fillStyle = "#e7e9ee";
    ctx.fillRect(roadX0, 0, roadW, cssH);

    ctx.fillStyle = "#3fa34d";
    ctx.fillRect(0, 0, roadX0, cssH);
    ctx.fillRect(roadX0 + roadW, 0, cssW - (roadX0 + roadW), cssH);

    // scrolling lane stripes for a sense of speed
    ctx.strokeStyle = "rgba(0,0,0,0.06)";
    ctx.lineWidth = 2;
    const spacing = 46 * VSCALE;
    const offset = (world.scrollY * VSCALE) % spacing;
    for (let y = -spacing + offset; y < cssH; y += spacing) {
      ctx.beginPath();
      ctx.moveTo(roadX0, y);
      ctx.lineTo(roadX0 + roadW, y);
      ctx.stroke();
    }
  }

  function drawRow(row) {
    const y = worldToScreenY(row.worldY);
    if (y < -80 || y > cssH + 80) return;

    if (row.kind === "wall") {
      const h = 46 * VSCALE;
      const broken = row.state === "broken";
      const failed = row.state === "failed";
      const alpha = (broken || failed) ? clamp(1 - row.stateTime / 0.5, 0, 1) : 1;
      if (alpha <= 0) return;
      ctx.globalAlpha = alpha;
      ctx.fillStyle = failed ? "#ff3b4e" : (broken ? "#ffd166" : "#2b3a55");
      ctx.fillRect(roadX0, y - h / 2, roadW, h);
      ctx.fillStyle = "#fff";
      ctx.font = `800 ${Math.round(22 * VSCALE)}px sans-serif`;
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(fmtNum(row.value) + " 必要", roadX0 + roadW / 2, y);
      ctx.globalAlpha = 1;
      return;
    }

    const h = 34 * VSCALE;
    for (const seg of row.segments) {
      const x0 = roadX0 + seg.x0 * roadW + 3;
      const x1 = roadX0 + seg.x1 * roadW - 3;
      ctx.fillStyle = seg.color;
      ctx.fillRect(x0, y - h / 2, x1 - x0, h);
      ctx.fillStyle = "rgba(255,255,255,0.9)";
      ctx.font = `800 ${Math.round(17 * VSCALE)}px sans-serif`;
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      const label = seg.op === "x" ? `×${seg.value}` : seg.op === "/" ? `÷${seg.value}` : seg.op + seg.value;
      ctx.fillText(label, (x0 + x1) / 2, y);

      // little posts at the segment edges
      ctx.fillStyle = "#7a5230";
      ctx.fillRect(x0 - 2, y - h / 2 - 4, 4, h + 8);
    }
  }

  function drawPickup(p) {
    const y = worldToScreenY(p.worldY);
    if (y < -30 || y > cssH + 30) return;
    const x = roadX0 + p.f * roadW;
    const r = (p.gem ? 11 : 8) * VSCALE;
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fillStyle = p.gem ? "#a78bfa" : "#ffd166";
    ctx.fill();
    ctx.strokeStyle = "rgba(0,0,0,0.25)";
    ctx.lineWidth = 2;
    ctx.stroke();
    ctx.fillStyle = "rgba(255,255,255,0.85)";
    ctx.font = `700 ${Math.round(10 * VSCALE)}px sans-serif`;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(p.gem ? "+5" : "$", x, y);
  }

  function drawPlayer() {
    const x = roadX0 + player.f * roadW;
    const y = cssH * PLAYER_SCREEN_FRAC;
    const r = clamp(20 + Math.sqrt(player.displayCount) * 2.2, 20, 78) * VSCALE * (1 + player.bump * 0.12);

    // shadow
    ctx.beginPath();
    ctx.ellipse(x, y + r * 0.55, r * 0.9, r * 0.28, 0, 0, Math.PI * 2);
    ctx.fillStyle = "rgba(0,0,0,0.18)";
    ctx.fill();

    const grad = ctx.createRadialGradient(x - r * 0.3, y - r * 0.3, r * 0.1, x, y, r);
    grad.addColorStop(0, "#7ec8ff");
    grad.addColorStop(1, "#2f7fe0");
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fillStyle = grad;
    ctx.fill();
    ctx.lineWidth = 3;
    ctx.strokeStyle = "#134a8f";
    ctx.stroke();

    // little dot pattern for a "crowd" feel
    const dots = Math.min(60, Math.round(player.displayCount));
    ctx.fillStyle = "rgba(255,255,255,0.55)";
    for (let i = 0; i < dots; i++) {
      const a = (i * 137.508) * Math.PI / 180;
      const rad = r * 0.75 * Math.sqrt((i + 1) / dots);
      const dx = x + Math.cos(a) * rad;
      const dy = y + Math.sin(a) * rad;
      ctx.beginPath();
      ctx.arc(dx, dy, Math.max(1.4, r * 0.05), 0, Math.PI * 2);
      ctx.fill();
    }

    ctx.fillStyle = "#fff";
    ctx.font = `900 ${Math.round(clamp(16 + r * 0.16, 16, 30))}px sans-serif`;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.lineWidth = 4;
    ctx.strokeStyle = "rgba(10,30,60,0.65)";
    const label = fmtNum(player.displayCount);
    ctx.strokeText(label, x, y);
    ctx.fillText(label, x, y);
  }

  function drawParticles() {
    for (const p of particles) {
      ctx.globalAlpha = clamp(p.life / p.maxLife, 0, 1);
      ctx.fillStyle = p.color;
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.size * VSCALE, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  function drawPopups() {
    for (const p of popups) {
      ctx.globalAlpha = clamp(p.life / p.maxLife, 0, 1);
      ctx.fillStyle = p.color;
      ctx.font = `800 ${Math.round(18 * VSCALE)}px sans-serif`;
      ctx.textAlign = "center";
      ctx.lineWidth = 3;
      ctx.strokeStyle = "rgba(0,0,0,0.4)";
      ctx.strokeText(p.text, p.x, p.y);
      ctx.fillText(p.text, p.x, p.y);
    }
    ctx.globalAlpha = 1;
  }

  // ---------------------------------------------------------------
  // HUD / DOM
  // ---------------------------------------------------------------
  const el = (id) => document.getElementById(id);
  const hud = el("hud");
  const hudCoins = el("hud-coins").querySelector("span");
  const hudDist = el("hud-dist").querySelector("span");
  const touchHint = el("touch-hint");

  function updateHud() {
    hudCoins.textContent = fmtNum(save.coins + runStats.coins);
    hudDist.textContent = fmtNum(Math.round(world.scrollY / 8));
    if (touchHint && world.scrollY > 40) touchHint.classList.add("hidden");
  }

  function showScreen(id) {
    for (const s of document.querySelectorAll(".screen")) s.classList.add("hidden");
    el(id).classList.remove("hidden");
  }

  function refreshMenu() {
    el("menu-best").textContent = fmtNum(save.best);
    el("menu-coins").textContent = fmtNum(save.coins);
  }

  function showGameOver(reason, isBest) {
    el("go-title").textContent = reason === "wall" ? "壁を突破できなかった…" : "仲間がいなくなった…";
    el("go-score").textContent = fmtNum(Math.round(world.scrollY / 8)) + "m";
    el("go-count").textContent = fmtNum(runStats.maxCount);
    el("go-coins").textContent = "+" + fmtNum(runStats.coins);
    el("go-best-badge").classList.toggle("hidden", !isBest);
    hud.classList.add("hidden");
    showScreen("screen-gameover");
  }

  function startPlaying() {
    newGame();
    state = "playing";
    hud.classList.remove("hidden");
    if (touchHint) touchHint.classList.remove("hidden");
    for (const s of document.querySelectorAll(".screen")) s.classList.add("hidden");
    updateHud();
  }

  // ---------------------------------------------------------------
  // Shop
  // ---------------------------------------------------------------
  function renderShop() {
    el("shop-coins").querySelector("span").textContent = fmtNum(save.coins);
    const list = el("shop-list");
    list.innerHTML = "";
    for (const def of UPGRADES) {
      const lv = upLevel(def.key);
      const maxed = lv >= def.maxLevel;
      const cost = maxed ? 0 : upgradeCost(def, lv);
      const row = document.createElement("div");
      row.className = "shop-item";
      row.innerHTML = `
        <div class="shop-icon">${def.icon}</div>
        <div class="shop-info">
          <div class="shop-name">${def.name}</div>
          <div class="shop-effect">${def.effect(lv)}</div>
          <div class="shop-level">Lv.${lv}${maxed ? " (MAX)" : " / " + def.maxLevel}</div>
        </div>
        <button class="shop-buy ${maxed ? "maxed" : ""}" ${maxed ? "disabled" : (save.coins < cost ? "disabled" : "")}>
          ${maxed ? "MAX" : "🪙" + cost}
        </button>
      `;
      const btn = row.querySelector("button");
      if (!maxed) {
        btn.addEventListener("click", () => {
          if (save.coins < cost) return;
          save.coins -= cost;
          save.upgrades[def.key] = lv + 1;
          saveGame();
          renderShop();
          refreshMenu();
        });
      }
      list.appendChild(row);
    }
  }

  // ---------------------------------------------------------------
  // Buttons
  // ---------------------------------------------------------------
  el("btn-play").addEventListener("click", startPlaying);
  el("btn-retry").addEventListener("click", startPlaying);
  el("btn-shop").addEventListener("click", () => { renderShop(); showScreen("screen-shop"); });
  el("btn-shop2").addEventListener("click", () => { renderShop(); showScreen("screen-shop"); });
  el("btn-back").addEventListener("click", () => {
    refreshMenu();
    showScreen("screen-menu");
  });

  // ---------------------------------------------------------------
  // Main loop
  // ---------------------------------------------------------------
  let lastT = performance.now();
  function tick(t) {
    const dt = (t - lastT) / 1000;
    lastT = t;
    try {
      if (state === "playing") update(dt);
      draw();
    } catch (e) {
      console.error(e);
    }
    requestAnimationFrame(tick);
  }

  refreshMenu();
  requestAnimationFrame(tick);
})();
