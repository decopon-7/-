(() => {
  "use strict";

  // ---------------------------------------------------------------
  // Constants
  // ---------------------------------------------------------------
  const REF_H = 800;              // reference design height, used to scale general UI fx
  const LOOKAHEAD = 900;          // how far ahead (world units) to keep rows spawned
  const REMOVE_MARGIN = 120;      // remove rows this far behind the player
  const SPEED_BASE = 150;
  const SPEED_MAX = 480;

  // Pseudo-3D perspective: the road is a triangle converging on a vanishing
  // point at the horizon. CAM_DEPTH controls how quickly things shrink with
  // distance (smaller = more dramatic/fisheye, larger = flatter/telephoto).
  const CAM_DEPTH = 300;
  const HORIZON_FRAC = 0.26;   // horizon line, fraction of screen height
  const PLAYER_Y_FRAC = 0.90;  // player's fixed vertical position, fraction of height
  const ROAD_HALF_W_FRAC = 0.47; // road half-width at the player, fraction of screen width
  const THICKNESS_GATE = 50;   // world-unit depth of a gate row (for the near/far trapezoid)
  const THICKNESS_WALL = 78;
  const TIE_SPACING = 60;      // world-unit spacing of road "speed tie" marks

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
  let HORIZON_Y = 0, PLAYER_Y = 0, ROAD_HALF_W = 0;

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
    HORIZON_Y = cssH * HORIZON_FRAC;
    PLAYER_Y = cssH * PLAYER_Y_FRAC;
    ROAD_HALF_W = cssW * ROAD_HALF_W_FRAC;
  }
  window.addEventListener("resize", resize);
  resize();

  // ---------------------------------------------------------------
  // Perspective projection: world distance-ahead `d` -> screen space.
  // d = 0 at the player's line, d > 0 further away (toward the horizon).
  // ---------------------------------------------------------------
  function project(d) {
    const dd = Math.max(d, -CAM_DEPTH * 0.9);
    const p = CAM_DEPTH / (CAM_DEPTH + dd);
    return { p, y: HORIZON_Y + p * (PLAYER_Y - HORIZON_Y), halfW: ROAD_HALF_W * p, cx: cssW / 2 };
  }
  // Inverse: given a screen y, what half-width/scale does the road have there.
  // Used only for the static road polygon, which must line up with project().
  function projectForY(y) {
    const p = (y - HORIZON_Y) / (PLAYER_Y - HORIZON_Y);
    return { p, y, halfW: ROAD_HALF_W * p, cx: cssW / 2 };
  }
  function xAt(proj, f) { return proj.cx + (f - 0.5) * 2 * proj.halfW; }
  function playerProj() { return project(0); }
  function playerScreenPos() {
    const proj = playerProj();
    return { x: xAt(proj, player.f), y: proj.y, p: proj.p };
  }

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
  // Player character: the user's own illustrated "plant shop clerk"
  // mascot (their artwork, background removed). One pose runs in the
  // crowd formation; the others decorate the menu/shop/game-over screens.
  // ---------------------------------------------------------------
  function loadSprite(src) {
    const img = new Image();
    img.src = src;
    return img;
  }
  const CHAR_SPRITE = loadSprite("assets/char-wave.png");
  const MASCOT_PEACE = loadSprite("assets/char-peace.png");
  const MASCOT_PLANT = loadSprite("assets/char-plant.png");
  const MASCOT_SAD = loadSprite("assets/char-sad.png");
  const FORMATION_SEED = [];
  for (let i = 0; i < 90; i++) FORMATION_SEED.push(rand(0, Math.PI * 2));

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
    // ramps up with distance so the opening stretch stays fair and the challenge builds later
    const negChance = clamp(0.16 + dist * 0.00028 - luckLv * 0.045, 0.1, 0.42);

    const wallDue = sinceWall > rand(500, 640) && dist > 420;

    if (wallDue) {
      const base = 24 + world.wallIndex * 17;
      const value = Math.round(base * Math.pow(1.4, world.wallIndex) * rand(0.85, 1.15));
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

    const growth = 1 + dist * 0.0012;
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
    const pos = playerScreenPos();
    const px = pos.x, py = pos.y;
    const good = player.count >= before;
    spawnPopup(px, py - 10, (good ? "+" : "") + (player.count - before), good ? "#8fffb0" : "#ff8a95");
    spawnBurst(px, py, seg.color, 14);
    player.bump = 1;
    runStats.maxCount = Math.max(runStats.maxCount, player.count);
    if (player.count <= 0) triggerGameOver("crowd");
  }

  function resolveWall(row) {
    row.processed = true;
    const pos = playerScreenPos();
    const px = pos.x, py = pos.y;
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
    player.targetF = clamp(input.startF + dx / (ROAD_HALF_W * 2), 0.03, 0.97);
  });
  window.addEventListener("pointerup", () => { input.active = false; });
  window.addEventListener("pointercancel", () => { input.active = false; });

  // ---------------------------------------------------------------
  // Update
  // ---------------------------------------------------------------
  function update(dt) {
    dt = Math.min(dt, 0.05);

    world.speed = clamp(SPEED_BASE + world.scrollY * 0.045, SPEED_BASE, SPEED_MAX);
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
    const playerPos = playerScreenPos();
    for (const p of world.pickups) {
      if (p.collected) continue;
      const d = p.worldY - world.scrollY;
      if (d <= 10) {
        const proj = project(d);
        const px = xAt(proj, p.f);
        if (Math.abs(px - playerPos.x) < magnetPx) {
          p.collected = true;
          runStats.coins += p.value;
          spawnPopup(playerPos.x, playerPos.y - 20, "🪙+" + p.value, "#ffd166");
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
  function draw() {
    ctx.clearRect(0, 0, cssW, cssH);

    ctx.save();
    if (shake.time > 0) {
      const m = shake.mag * (shake.time / 0.4);
      ctx.translate(rand(-m, m), rand(-m, m));
    }

    drawSky();
    if (state === "playing" || state === "gameover") {
      drawRoad();
      const rows = world.rows.slice().sort((a, b) => b.worldY - a.worldY); // farthest first
      for (const row of rows) drawRow(row);
      const pickups = world.pickups.slice().sort((a, b) => b.worldY - a.worldY);
      for (const p of pickups) drawPickup(p);
      drawPlayer();
      drawParticles();
      drawPopups();
    }
    ctx.restore();
  }

  function drawSky() {
    const g = ctx.createLinearGradient(0, 0, 0, HORIZON_Y);
    g.addColorStop(0, "#7fd4ff");
    g.addColorStop(1, "#cdeeff");
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, cssW, HORIZON_Y);
  }

  function drawRoad() {
    // ground fills everything below the horizon; the road is a triangle on top of it
    const groundGrad = ctx.createLinearGradient(0, HORIZON_Y, 0, cssH);
    groundGrad.addColorStop(0, "#2f9b48");
    groundGrad.addColorStop(1, "#3fc25f");
    ctx.fillStyle = groundGrad;
    ctx.fillRect(0, HORIZON_Y, cssW, cssH - HORIZON_Y);

    // hedge texture blocks on either side, receding with the tie marks
    const offset = world.scrollY % TIE_SPACING;
    ctx.fillStyle = "rgba(0,0,0,0.10)";
    for (let i = 0; i < 16; i++) {
      const d = i * TIE_SPACING - offset;
      if (d < -TIE_SPACING) continue;
      const proj = project(d);
      if (proj.p < 0.04) break;
      const bh = Math.max(1, 16 * proj.p);
      if (i % 2 === 0) {
        ctx.fillRect(0, proj.y - bh / 2, Math.max(2, proj.cx - proj.halfW), bh);
        ctx.fillRect(proj.cx + proj.halfW, proj.y - bh / 2, Math.max(2, cssW - (proj.cx + proj.halfW)), bh);
      }
    }

    // the road itself: a triangle converging on the vanishing point at the horizon
    const near = projectForY(cssH);
    const roadGrad = ctx.createLinearGradient(0, HORIZON_Y, 0, cssH);
    roadGrad.addColorStop(0, "#f3f4f7");
    roadGrad.addColorStop(1, "#d7dbe3");
    ctx.beginPath();
    ctx.moveTo(near.cx - near.halfW, cssH);
    ctx.lineTo(near.cx + near.halfW, cssH);
    ctx.lineTo(near.cx, HORIZON_Y);
    ctx.closePath();
    ctx.fillStyle = roadGrad;
    ctx.fill();

    // edge lines + speed tie marks, clipped to the road triangle
    ctx.save();
    ctx.beginPath();
    ctx.moveTo(near.cx - near.halfW, cssH);
    ctx.lineTo(near.cx + near.halfW, cssH);
    ctx.lineTo(near.cx, HORIZON_Y);
    ctx.closePath();
    ctx.clip();

    ctx.strokeStyle = "rgba(0,0,0,0.09)";
    for (let i = 0; i < 16; i++) {
      const d = i * TIE_SPACING - offset;
      if (d < -TIE_SPACING) continue;
      const proj = project(d);
      if (proj.p < 0.04) break;
      ctx.lineWidth = Math.max(1, 5 * proj.p);
      ctx.beginPath();
      ctx.moveTo(xAt(proj, 0), proj.y);
      ctx.lineTo(xAt(proj, 1), proj.y);
      ctx.stroke();
    }
    ctx.restore();
  }

  function drawRow(row) {
    const d = row.worldY - world.scrollY;
    const thickness = row.kind === "wall" ? THICKNESS_WALL : THICKNESS_GATE;
    const dNear = d - thickness / 2;
    const dFar = d + thickness / 2;
    if (dFar < -CAM_DEPTH * 0.85) return;
    const projNear = project(dNear);
    const projFar = project(dFar);
    if (projNear.p < 0.03 && projFar.p < 0.03) return;

    if (row.kind === "wall") {
      const broken = row.state === "broken";
      const failed = row.state === "failed";
      const alpha = (broken || failed) ? clamp(1 - row.stateTime / 0.5, 0, 1) : 1;
      if (alpha <= 0) return;
      ctx.globalAlpha = alpha;
      ctx.fillStyle = failed ? "#ff3b4e" : (broken ? "#ffd166" : "#2b3a55");
      drawQuad(projNear, projFar, 0, 1);
      const midY = (projNear.y + projFar.y) / 2;
      const midP = (projNear.p + projFar.p) / 2;
      ctx.fillStyle = "#fff";
      ctx.font = `800 ${Math.round(clamp(22 * midP, 9, 26))}px sans-serif`;
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(fmtNum(row.value) + " 必要", projNear.cx, midY);
      ctx.globalAlpha = 1;
      return;
    }

    for (const seg of row.segments) {
      ctx.fillStyle = seg.color;
      drawQuad(projNear, projFar, seg.x0, seg.x1);

      const midY = (projNear.y + projFar.y) / 2;
      const midP = (projNear.p + projFar.p) / 2;
      const midX = (xAt(projNear, (seg.x0 + seg.x1) / 2) + xAt(projFar, (seg.x0 + seg.x1) / 2)) / 2;
      ctx.fillStyle = "rgba(255,255,255,0.92)";
      ctx.font = `800 ${Math.round(clamp(18 * midP, 8, 20))}px sans-serif`;
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      const label = seg.op === "x" ? `×${seg.value}` : seg.op === "/" ? `÷${seg.value}` : seg.op + seg.value;
      ctx.fillText(label, midX, midY);

      // a post at each segment boundary, for a fence-gate feel
      ctx.strokeStyle = "#7a5230";
      ctx.lineWidth = Math.max(1, 5 * midP);
      ctx.beginPath();
      ctx.moveTo(xAt(projNear, seg.x0), projNear.y - 6 * projNear.p);
      ctx.lineTo(xAt(projFar, seg.x0), projFar.y - 6 * projFar.p);
      ctx.stroke();
    }
  }

  // fills a quad spanning road-fraction [f0,f1] between the near and far projections
  function drawQuad(projNear, projFar, f0, f1) {
    ctx.beginPath();
    ctx.moveTo(xAt(projNear, f0), projNear.y);
    ctx.lineTo(xAt(projNear, f1), projNear.y);
    ctx.lineTo(xAt(projFar, f1), projFar.y);
    ctx.lineTo(xAt(projFar, f0), projFar.y);
    ctx.closePath();
    ctx.fill();
  }

  function drawPickup(p) {
    const d = p.worldY - world.scrollY;
    if (d < -CAM_DEPTH * 0.85) return;
    const proj = project(d);
    if (proj.p < 0.03) return;
    const x = xAt(proj, p.f);
    const y = proj.y;
    const r = (p.gem ? 11 : 8) * VSCALE * proj.p;
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fillStyle = p.gem ? "#a78bfa" : "#ffd166";
    ctx.fill();
    ctx.strokeStyle = "rgba(0,0,0,0.25)";
    ctx.lineWidth = Math.max(1, 2 * proj.p);
    ctx.stroke();
    ctx.fillStyle = "rgba(255,255,255,0.85)";
    ctx.font = `700 ${Math.round(clamp(10 * proj.p, 5, 10))}px sans-serif`;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(p.gem ? "+5" : "$", x, y);
  }

  function spriteReady(img) { return img.complete && img.naturalWidth > 0; }

  function drawPlayer() {
    if (!spriteReady(CHAR_SPRITE)) return; // local image, loads almost instantly
    const aspect = CHAR_SPRITE.naturalWidth / CHAR_SPRITE.naturalHeight;

    const pos = playerScreenPos();
    const x = pos.x;
    const y = pos.y;
    const bumpMul = 1 + player.bump * 0.16;
    const formationR = clamp(14 + Math.sqrt(player.displayCount) * 5.6, 14, 100) * VSCALE * bumpMul;
    const visibleN = clamp(Math.round(player.displayCount), 1, 90);
    // smaller sprites as the crowd gets denser, so it reads as a crowd, not a pile
    const spriteSize = clamp(34 - Math.sqrt(visibleN) * 1.7, 15, 34) * VSCALE * bumpMul;

    // one shared shadow under the whole formation
    ctx.beginPath();
    ctx.ellipse(x, y + formationR * 0.5, formationR * 1.05, formationR * 0.34, 0, 0, Math.PI * 2);
    ctx.fillStyle = "rgba(0,0,0,0.18)";
    ctx.fill();

    const now = performance.now() / 1000;
    const members = [];
    for (let i = 0; i < visibleN; i++) {
      const a = (i * 137.508) * Math.PI / 180;
      const rad = formationR * Math.sqrt((i + 0.5) / visibleN);
      const seed = FORMATION_SEED[i % FORMATION_SEED.length];
      const bob = Math.sin(now * 3.2 + seed) * spriteSize * 0.06;
      const dx = Math.cos(a) * rad;
      const dy = Math.sin(a) * rad * 0.7; // flatten the formation a bit for a top-down feel
      const flip = FORMATION_SEED[(i * 7 + 3) % FORMATION_SEED.length] > Math.PI; // cheap per-member variety
      members.push({ dx, dy: dy + bob, sortY: dy, flip });
    }
    members.sort((m1, m2) => m1.sortY - m2.sortY); // draw back-to-front

    for (const m of members) {
      const h = spriteSize * (0.85 + 0.15 * (m.sortY / formationR + 1) / 2) * 1.3;
      const w = h * aspect;
      const cx = x + m.dx, groundY = y + m.dy;
      ctx.save();
      ctx.translate(cx, groundY);
      if (m.flip) ctx.scale(-1, 1);
      ctx.drawImage(CHAR_SPRITE, -w / 2, -h, w, h);
      ctx.restore();
    }

    // count banner above the pack
    const labelY = y - formationR * 0.7 - spriteSize * 1.3 - 12 * VSCALE;
    const label = fmtNum(player.displayCount);
    ctx.font = `900 ${Math.round(clamp(15 + formationR * 0.1, 15, 26))}px sans-serif`;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    const padX = 10 * VSCALE;
    const tw = ctx.measureText(label).width;
    const bh = 22 * VSCALE;
    ctx.fillStyle = "rgba(10,30,60,0.72)";
    roundRect(ctx, x - tw / 2 - padX, labelY - bh / 2, tw + padX * 2, bh, bh / 2);
    ctx.fill();
    ctx.fillStyle = "#fff";
    ctx.fillText(label, x, labelY + 1);
  }

  function roundRect(c, x, y, w, h, r) {
    c.beginPath();
    c.moveTo(x + r, y);
    c.arcTo(x + w, y, x + w, y + h, r);
    c.arcTo(x + w, y + h, x, y + h, r);
    c.arcTo(x, y + h, x, y, r);
    c.arcTo(x, y, x + w, y, r);
    c.closePath();
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
