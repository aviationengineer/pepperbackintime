"use strict";
/* ================================================================
   TIMELINE RESTORER v2: BACK IN TIME — Phaser edition
   Data-driven point-and-click time-travel adventure.
   Content lives in GAME_DATA (ported verbatim from v1); the engine
   consumes it. The Phaser canvas renders scenes, animated character
   actors and click-to-walk navigation; DOM overlays provide the HUD,
   panels, modals and inventory. If Phaser cannot boot, the game falls
   back to v1-style DOM hotspots so play never breaks.
   Engine classes: GameEngine, GameState, SceneManager, TimelineManager,
   InventoryManager, DialogueManager, PuzzleManager, TruthEngine,
   QuizEngine, ScoreManager, SaveManager, UIManager, AudioManager,
   MusicManager, CharacterFactory, ScenePainter, WorldScene.
   ================================================================ */

/* ---------------- utilities ---------------- */
function $(id) { return document.getElementById(id); }
function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }
function esc(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;"); }
function makeEl(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined && text !== null) e.textContent = text;
  return e;
}

/* ---------------- event log ---------------- */
const LOG_LEVELS = { DEBUG: 0, INFO: 1, WARNING: 2, ERROR: 3 };
const eventLog = [];
function logEvent(level, message, data) {
  const entry = { ts: new Date().toISOString(), level, message, data: data || null };
  eventLog.push(entry);
  if (eventLog.length > 500) eventLog.shift();
  try {
    const stored = JSON.parse(localStorage.getItem("timeline-restorer-log-v2") || "[]");
    stored.push(entry);
    localStorage.setItem("timeline-restorer-log-v2", JSON.stringify(stored.slice(-200)));
  } catch (e) { /* storage is best-effort */ }
  const dbg = $("debug-log");
  if (dbg) {
    const line = "[" + level + "] " + message;
    const div = makeEl("div", "debug-line", line);
    dbg.appendChild(div);
    while (dbg.children.length > 80) dbg.removeChild(dbg.firstChild);
  }
}

/* Kid-friendly encouragement shown on first discoveries and solves. */
const PRAISE = [
  "Great detective work!",
  "You spotted it!",
  "Brilliant — the timeline thanks you!",
  "Sharp eyes, Restorer!",
  "That's the spirit — keep going!",
  "Wonderful! History is a little safer now."
];
function praise() { return PRAISE[Math.floor(Math.random() * PRAISE.length)]; }

/* ---------------- GameState ---------------- */
class GameState {
  constructor() { this.reset(); }
  reset() {
    this.data = {
      currentAct: 1, currentScene: "workshop", score: 0,
      paradoxLevel: 15, timelineStability: 85,
      inventory: [], discoveredTruths: [], solvedPuzzles: [],
      timelineFlags: {}, dialogueFlags: {}, visitedScenes: [],
      quizResults: {}, playerChoices: [], gameCompleted: false,
      keyDigits: {},
      categories: { knowledge: 0, puzzles: 0, truths: 0, artifacts: 0, restoration: 0, exploration: 0 }
    };
  }
  get(key) { return this.data[key]; }
  set(key, value) { this.data[key] = value; }
  toJSON() { return JSON.parse(JSON.stringify(this.data)); }
  fromJSON(data) {
    if (!data || typeof data !== "object") return false;
    this.reset();
    for (const key of Object.keys(this.data)) {
      if (data[key] !== undefined) this.data[key] = data[key];
    }
    return true;
  }
}

/* ---------------- ScoreManager ---------------- */
class ScoreManager {
  constructor(state) { this.state = state; }
  add(points, category) {
    if (!points) return;
    this.state.data.score += points;
    if (category && this.state.data.categories[category] !== undefined) {
      this.state.data.categories[category] += points;
    }
    logEvent("INFO", "Score +" + points + " (" + (category || "general") + ") total=" + this.state.data.score);
  }
  total() { return this.state.data.score; }
  breakdown() { return Object.assign({}, this.state.data.categories); }
}

/* ---------------- TimelineManager ---------------- */
class TimelineManager {
  constructor(state) { this.state = state; }
  addParadox(n) {
    const d = this.state.data;
    d.paradoxLevel = clamp(d.paradoxLevel + n, 0, 100);
    d.timelineStability = clamp(d.timelineStability - Math.round(n / 2), 0, 100);
    logEvent("INFO", "Paradox " + (n >= 0 ? "+" : "") + n + " -> " + d.paradoxLevel + "%; stability " + d.timelineStability + "%");
    return d.paradoxLevel;
  }
  addStability(n) {
    const d = this.state.data;
    d.timelineStability = clamp(d.timelineStability + n, 0, 100);
    d.paradoxLevel = clamp(d.paradoxLevel - Math.round(n / 2), 0, 100);
    logEvent("INFO", "Stability +" + n + " -> " + d.timelineStability + "%; paradox " + d.paradoxLevel + "%");
    return d.timelineStability;
  }
  setFlag(name, value) {
    this.state.data.timelineFlags[name] = value === undefined ? true : value;
    logEvent("INFO", "Timeline flag set: " + name + " = " + JSON.stringify(this.state.data.timelineFlags[name]));
  }
  hasFlag(name) { return !!this.state.data.timelineFlags[name]; }
  band() {
    const p = this.state.data.paradoxLevel;
    if (p <= 20) return "stable";
    if (p <= 40) return "minor";
    if (p <= 60) return "unstable";
    if (p <= 80) return "severe";
    return "critical";
  }
  bandLabel() {
    const labels = { stable: "Stable", minor: "Minor distortion", unstable: "Timeline unstable", severe: "Severe distortion", critical: "Critical paradox" };
    return labels[this.band()];
  }
  /* Apply a generic effects object: {paradox, stability, score, flag, item, truth} */
  applyEffects(effects, engine) {
    if (!effects) return;
    if (effects.paradox) this.addParadox(effects.paradox);
    if (effects.stability) this.addStability(effects.stability);
    if (effects.score && engine) engine.scores.add(effects.score, "knowledge");
    if (effects.flag) this.setFlag(effects.flag);
    if (effects.item && engine) engine.inventory.addItem(effects.item);
    if (effects.truth && engine) engine.truths.discover(effects.truth, true);
  }
}

/* ---------------- SaveManager ---------------- */
class SaveManager {
  constructor() {
    this.saveKey = "timeline-restorer-save-v2";
    this.archiveKey = "timeline-restorer-archive-v2";
  }
  save(state) {
    try {
      localStorage.setItem(this.saveKey, JSON.stringify(state.toJSON()));
      logEvent("INFO", "Game saved.");
      return true;
    } catch (e) {
      logEvent("ERROR", "Save failed: " + e.message);
      return false;
    }
  }
  load() {
    try {
      const raw = localStorage.getItem(this.saveKey);
      if (!raw) return null;
      return JSON.parse(raw);
    } catch (e) {
      logEvent("ERROR", "Load failed: " + e.message);
      return null;
    }
  }
  hasSave() {
    try { return !!localStorage.getItem(this.saveKey); } catch (e) { return false; }
  }
  clear() {
    try { localStorage.removeItem(this.saveKey); } catch (e) { /* ignore */ }
  }
  archiveAdd(truthId) {
    try {
      const list = this.archiveGet();
      if (list.indexOf(truthId) === -1) list.push(truthId);
      localStorage.setItem(this.archiveKey, JSON.stringify(list));
    } catch (e) { /* ignore */ }
  }
  archiveGet() {
    try { return JSON.parse(localStorage.getItem(this.archiveKey) || "[]"); }
    catch (e) { return []; }
  }
  archiveClear() {
    try { localStorage.removeItem(this.archiveKey); } catch (e) { /* ignore */ }
  }
}

/* ---------------- AudioManager (Web Audio, procedural only) ---------------- */
class AudioManager {
  constructor() {
    this.ctx = null; this.muted = false; this.volume = 0.8;
    this.master = null; this.sfxBus = null; this.musicBus = null; this._noiseBuf = null;
    try {
      this.muted = localStorage.getItem("timeline-restorer-muted-v2") === "1";
      const v = parseFloat(localStorage.getItem("timeline-restorer-volume-v2"));
      if (!isNaN(v)) this.volume = clamp(v, 0, 1);
    } catch (e) { /* ignore */ }
  }
  init() {
    if (this.ctx) { if (this.ctx.state === "suspended") this.ctx.resume(); return; }
    try {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return;
      this.ctx = new AC();
      this.master = this.ctx.createGain();
      this.master.gain.value = this.muted ? 0 : this.volume;
      this.master.connect(this.ctx.destination);
      this.sfxBus = this.ctx.createGain(); this.sfxBus.gain.value = 0.9; this.sfxBus.connect(this.master);
      this.musicBus = this.ctx.createGain(); this.musicBus.gain.value = 0.5; this.musicBus.connect(this.master);
    } catch (e) { logEvent("WARNING", "Web Audio unavailable: " + e.message); }
  }
  setMuted(m) {
    this.muted = m;
    try { localStorage.setItem("timeline-restorer-muted-v2", m ? "1" : "0"); } catch (e) { /* ignore */ }
    if (this.master && this.ctx) this.master.gain.setValueAtTime(m ? 0 : this.volume, this.ctx.currentTime);
  }
  setVolume(v) {
    this.volume = clamp(v, 0, 1);
    try { localStorage.setItem("timeline-restorer-volume-v2", String(this.volume)); } catch (e) { /* ignore */ }
    if (this.master && this.ctx && !this.muted) this.master.gain.setValueAtTime(this.volume, this.ctx.currentTime);
  }
  noiseBuffer() {
    if (this._noiseBuf) return this._noiseBuf;
    const len = this.ctx.sampleRate * 1;
    const buf = this.ctx.createBuffer(1, len, this.ctx.sampleRate);
    const ch = buf.getChannelData(0);
    for (let i = 0; i < len; i++) ch[i] = Math.random() * 2 - 1;
    this._noiseBuf = buf;
    return buf;
  }
  /* One soft note. `when` is a ctx time; `dest` defaults to the SFX bus. */
  note(freq, when, dur, type, vol, dest) {
    if (this.muted || !this.ctx) return;
    try {
      const osc = this.ctx.createOscillator();
      const gain = this.ctx.createGain();
      osc.type = type || "sine";
      osc.frequency.setValueAtTime(freq, when);
      gain.gain.setValueAtTime(0.0001, when);
      gain.gain.exponentialRampToValueAtTime(vol || 0.08, when + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.001, when + dur);
      osc.connect(gain); gain.connect(dest || this.sfxBus);
      osc.start(when); osc.stop(when + dur + 0.05);
    } catch (e) { /* audio is best-effort */ }
  }
  beep(freq, dur, type, vol) {
    if (this.muted) return;
    this.init();
    if (!this.ctx) return;
    this.note(freq, this.ctx.currentTime, dur, type, vol, this.sfxBus);
  }
  click() { this.beep(660, 0.06, "square", 0.04); }
  truth() { this.beep(880, 0.12, "sine", 0.07); setTimeout(() => this.beep(1174, 0.14, "sine", 0.06), 90); }
  distortion() { this.beep(160, 0.3, "sawtooth", 0.06); }
  solved() {
    this.beep(523, 0.1, "sine", 0.07);
    setTimeout(() => this.beep(659, 0.1, "sine", 0.07), 100);
    setTimeout(() => this.beep(784, 0.18, "sine", 0.07), 200);
  }
  artifact() { this.beep(1046, 0.1, "triangle", 0.06); setTimeout(() => this.beep(1318, 0.16, "triangle", 0.05), 90); }
  actComplete() { const seq = [523, 659, 784, 1046]; seq.forEach((f, i) => setTimeout(() => this.beep(f, 0.16, "sine", 0.07), i * 130)); }
  error() { this.beep(220, 0.15, "square", 0.05); }
  footstep() {
    if (this.muted) return;
    this.init();
    if (!this.ctx) return;
    try {
      const t = this.ctx.currentTime;
      const src = this.ctx.createBufferSource();
      src.buffer = this.noiseBuffer();
      const filt = this.ctx.createBiquadFilter();
      filt.type = "lowpass"; filt.frequency.value = 500;
      const gain = this.ctx.createGain();
      gain.gain.setValueAtTime(0.10, t);
      gain.gain.exponentialRampToValueAtTime(0.001, t + 0.07);
      src.connect(filt); filt.connect(gain); gain.connect(this.sfxBus);
      src.start(t, Math.random() * 0.5, 0.08);
    } catch (e) { /* best-effort */ }
  }
}

/* ---------------- MusicManager (generative music + ambience) ----------------
   No audio files: melodies are scheduled oscillator notes from per-act
   scales; ambience is looped filtered noise with occasional chirps. */
class MusicManager {
  constructor(audio) {
    this.audio = audio;
    this.enabled = true;            // music on/off (separate from mute)
    this.currentAct = 0;
    this.timer = null;
    this.step = 0;
    this.nextTime = 0;
    this.ambience = null;           // {nodes...} for the current ambience bed
    this.chirpTimer = null;
    /* Per-act mood: scale (semitone offsets from the root), root Hz,
       tempo (bpm), and a simple 16-step melody pattern (scale degrees,
       -1 = rest). */
    this.ACT_MUSIC = {
      1: { root: 261.63, tempo: 96,  scale: [0, 2, 4, 7, 9, 12], melody: [0, -1, 2, -1, 3, 2, 1, -1, 0, -1, 2, 3, 4, 3, 2, -1] },
      2: { root: 220.00, tempo: 112, scale: [0, 2, 3, 5, 7, 10, 12], melody: [0, 2, -1, 1, -1, 2, 3, -1, 4, 3, 2, 1, 0, -1, 1, -1] },
      3: { root: 293.66, tempo: 88,  scale: [0, 2, 3, 5, 7, 8, 10, 12], melody: [0, -1, 1, 2, -1, 3, 2, -1, 4, -1, 3, 2, 1, 2, 0, -1] },
      4: { root: 246.94, tempo: 120, scale: [0, 2, 4, 5, 7, 9, 11, 12], melody: [0, 2, 4, -1, 3, 2, 1, -1, 0, -1, 2, 1, 2, 4, 5, -1] },
      5: { root: 277.18, tempo: 76,  scale: [0, 2, 4, 6, 8, 10, 12], melody: [0, -1, 2, -1, 4, -1, 3, 2, 1, -1, 2, 3, 4, -1, 2, -1] }
    };
  }
  setEnabled(on) {
    this.enabled = on;
    if (!on) this.stop();
    else if (this.currentAct) this.start(this.currentAct);
  }
  start(act) {
    this.currentAct = act;
    if (!this.enabled) return;
    this.audio.init();
    if (!this.audio.ctx) return;
    this.stopTimer();
    const cfg = this.ACT_MUSIC[act] || this.ACT_MUSIC[1];
    this.step = 0;
    this.nextTime = this.audio.ctx.currentTime + 0.1;
    const stepDur = 60 / cfg.tempo / 4; // 16th notes
    this.timer = setInterval(() => {
      if (this.audio.muted || !this.audio.ctx) return;
      const ahead = this.audio.ctx.currentTime + 0.25;
      while (this.nextTime < ahead) {
        this._scheduleStep(cfg, this.step, this.nextTime, stepDur);
        this.nextTime += stepDur;
        this.step = (this.step + 1) % 64;
      }
    }, 90);
  }
  stopTimer() { if (this.timer) { clearInterval(this.timer); this.timer = null; } }
  stop() { this.stopTimer(); this.currentAct = 0; }
  _freq(cfg, degree) {
    const oct = Math.floor(degree / cfg.scale.length);
    const semis = cfg.scale[degree % cfg.scale.length] + oct * 12;
    return cfg.root * Math.pow(2, semis / 12);
  }
  _scheduleStep(cfg, step, t, stepDur) {
    const bar = Math.floor(step / 16);
    const inBar = step % 16;
    const mel = cfg.melody[inBar];
    if (mel >= 0) this.audio.note(this._freq(cfg, mel), t, stepDur * 1.8, "triangle", 0.045, this.audio.musicBus);
    if (inBar === 0) { // soft bass at each bar
      const bassDeg = [0, 3, 4, 2][bar % 4];
      this.audio.note(this._freq(cfg, bassDeg) / 2, t, stepDur * 10, "sine", 0.05, this.audio.musicBus);
    }
    if (inBar === 0 && bar % 2 === 0) { // gentle pad chord
      [0, 2, 4].forEach((d) => this.audio.note(this._freq(cfg, d), t, stepDur * 14, "sine", 0.018, this.audio.musicBus));
    }
  }
  /* Ambience bed per scene type: wind, mill, market, room, night, shimmer. */
  setAmbience(kind) {
    this.clearAmbience();
    this.audio.init();
    if (!this.audio.ctx || this.audio.muted) return;
    try {
      const ctx = this.audio.ctx;
      const src = ctx.createBufferSource();
      src.buffer = this.audio.noiseBuffer();
      src.loop = true;
      const filt = ctx.createBiquadFilter();
      const gain = ctx.createGain();
      const conf = {
        wind:    { type: "bandpass", freq: 420,  vol: 0.020 },
        mill:    { type: "lowpass",  freq: 180,  vol: 0.030 },
        market:  { type: "bandpass", freq: 1100, vol: 0.014 },
        room:    { type: "lowpass",  freq: 300,  vol: 0.008 },
        night:   { type: "bandpass", freq: 900,  vol: 0.012 },
        shimmer: { type: "highpass", freq: 2400, vol: 0.008 }
      }[kind] || { type: "lowpass", freq: 300, vol: 0.008 };
      filt.type = conf.type; filt.frequency.value = conf.freq;
      gain.gain.value = conf.vol;
      src.connect(filt); filt.connect(gain); gain.connect(this.audio.musicBus);
      src.start();
      this.ambience = { src, filt, gain, kind };
      if (kind === "wind" || kind === "market" || kind === "night") this._startChirps(kind);
    } catch (e) { /* best-effort */ }
  }
  _startChirps(kind) {
    this.chirpTimer = setInterval(() => {
      if (this.audio.muted || !this.audio.ctx || Math.random() < 0.4) return;
      const t = this.audio.ctx.currentTime;
      const base = kind === "night" ? 3400 : 2400 + Math.random() * 1200;
      this.audio.note(base, t, 0.09, "sine", 0.02, this.audio.musicBus);
      this.audio.note(base * 1.25, t + 0.11, 0.07, "sine", 0.016, this.audio.musicBus);
    }, 2600);
  }
  clearAmbience() {
    if (this.chirpTimer) { clearInterval(this.chirpTimer); this.chirpTimer = null; }
    if (this.ambience) {
      try { this.ambience.src.stop(); } catch (e) { /* ignore */ }
      try { this.ambience.src.disconnect(); } catch (e) { /* ignore */ }
      this.ambience = null;
    }
  }
}

/* ---------------- UIManager ---------------- */
class UIManager {
  showScreen(name) {
    ["screen-title", "screen-game", "screen-ending"].forEach((id) => {
      $(id).classList.toggle("hidden", id !== "screen-" + name);
    });
  }
  toast(msg) {
    const t = $("toast");
    t.textContent = msg;
    t.style.display = "block";
    clearTimeout(this._toastTimer);
    this._toastTimer = setTimeout(() => { t.style.display = "none"; }, 2600);
  }
  openModal(title, bodyNode, actions) {
    $("modal-title").textContent = title;
    const body = $("modal-body");
    body.innerHTML = "";
    if (typeof bodyNode === "string") body.innerHTML = bodyNode;
    else if (bodyNode) body.appendChild(bodyNode);
    const act = $("modal-actions");
    act.innerHTML = "";
    (actions || []).forEach((a) => {
      const b = makeEl("button", "btn" + (a.secondary ? " secondary" : ""), a.label);
      b.addEventListener("click", () => { if (a.onClick) a.onClick(); });
      act.appendChild(b);
    });
    $("modal-backdrop").classList.remove("hidden");
    const first = act.querySelector("button") || body.querySelector("button, input");
    if (first) first.focus();
  }
  closeModal() { $("modal-backdrop").classList.add("hidden"); }
  modalOpen() { return !$("modal-backdrop").classList.contains("hidden"); }
  setPanel(html) {
    const p = $("panel");
    p.innerHTML = html;
    p.classList.remove("flash");
    void p.offsetWidth;
    p.classList.add("flash");
  }
  updateMeters(state, timeline) {
    const d = state.data;
    $("stability-fill").style.width = d.timelineStability + "%";
    $("stability-num").textContent = d.timelineStability + "%";
    $("paradox-fill").style.width = d.paradoxLevel + "%";
    $("paradox-num").textContent = d.paradoxLevel + "%";
    const act = GAME_DATA.acts[d.currentAct];
    $("act-label").textContent = act ? act.title.split("—")[0].trim().toUpperCase() : "ACT " + d.currentAct;
    document.body.classList.remove("px-minor", "px-unstable", "px-severe", "px-critical");
    const band = timeline.band();
    if (band === "minor") document.body.classList.add("px-minor");
    if (band === "unstable") document.body.classList.add("px-unstable");
    if (band === "severe") document.body.classList.add("px-severe");
    if (band === "critical") document.body.classList.add("px-critical");
  }
  renderInventory(state, selectedId, onSelect) {
    const strip = $("inventory-strip");
    strip.innerHTML = "";
    strip.appendChild(makeEl("span", "inv-label", "🎒 Inventory:"));
    if (state.data.inventory.length === 0) {
      strip.appendChild(makeEl("span", null, " (empty — click objects in the scene to collect items)"));
      return;
    }
    state.data.inventory.forEach((itemId) => {
      const def = GAME_DATA.items[itemId];
      if (!def) return;
      const chip = makeEl("button", "inv-chip" + (selectedId === itemId ? " selected" : ""),
        def.icon + " " + def.name);
      chip.setAttribute("aria-label", "Inventory item: " + def.name + ". " + def.desc);
      chip.title = def.desc;
      chip.addEventListener("click", () => onSelect(itemId));
      strip.appendChild(chip);
    });
  }
}

/* ---------------- InventoryManager ---------------- */
class InventoryManager {
  constructor(state, engine) { this.state = state; this.engine = engine; }
  hasItem(id) { return this.state.data.inventory.indexOf(id) !== -1; }
  addItem(id) {
    const def = GAME_DATA.items[id];
    if (!def) { logEvent("WARNING", "Tried to add unknown item: " + id); return false; }
    if (this.hasItem(id)) return false;
    this.state.data.inventory.push(id);
    this.engine.scores.add(20, "artifacts");
    this.engine.audio.artifact();
    logEvent("INFO", "Item collected: " + def.name);
    this.engine.ui.toast("🎒 Collected: " + def.name);
    this.engine.refreshUI();
    return true;
  }
  removeItem(id) {
    const idx = this.state.data.inventory.indexOf(id);
    if (idx !== -1) this.state.data.inventory.splice(idx, 1);
  }
  list() {
    return this.state.data.inventory
      .map((id) => GAME_DATA.items[id])
      .filter(Boolean);
  }
  findRecipe(a, b) {
    return (GAME_DATA.recipes || []).find((r) => {
      const has = (x) => r.inputs.indexOf(x) !== -1;
      return r.inputs.length === 2 && has(a) && has(b) && a !== b;
    }) || null;
  }
  combine(a, b) {
    const recipe = this.findRecipe(a, b);
    if (!recipe) {
      this.engine.ui.setPanel("<p>Those two items do not combine. Try other pairings — the game will tell you when a combination works.</p>");
      this.engine.audio.error();
      return null;
    }
    this.removeItem(a);
    this.removeItem(b);
    this.addItem(recipe.output);
    const out = GAME_DATA.items[recipe.output];
    this.engine.scores.add(50, "puzzles");
    logEvent("INFO", "Items combined: " + a + " + " + b + " = " + recipe.output);
    this.engine.ui.setPanel("<p class='clue'>✨ " + esc(recipe.message) + "</p><p>You made: <strong>" + esc(out.name) + "</strong> " + out.icon + "</p><p class='clue'>" + esc(praise()) + "</p>");
    this.engine.refreshUI();
    return recipe.output;
  }
}

/* ---------------- TruthEngine ---------------- */
class TruthEngine {
  constructor(state, engine) { this.state = state; this.engine = engine; }
  discover(truthId, silent) {
    const truth = GAME_DATA.truths[truthId];
    if (!truth) { logEvent("WARNING", "Truth not found: " + truthId); return null; }
    const already = this.state.data.discoveredTruths.indexOf(truthId) !== -1;
    if (!already) {
      this.state.data.discoveredTruths.push(truthId);
      this.engine.saves.archiveAdd(truthId);
      if (!silent) {
        this.engine.scores.add(50, "truths");
        this.engine.timeline.addStability(2);
      }
      logEvent("INFO", "Truth discovered: " + truth.object);
    }
    return truth;
  }
  check(truthId) {
    const truth = GAME_DATA.truths[truthId];
    if (!truth) {
      this.engine.ui.openModal("Truth Check", "<p>No verification record exists for this. The Truth Engine has no data — try examining it with LOOK first.</p>", [{ label: "Close", onClick: () => this.engine.ui.closeModal() }]);
      logEvent("WARNING", "Truth check with no record: " + truthId);
      return;
    }
    const firstTime = this.state.data.discoveredTruths.indexOf(truthId) === -1;
    this.discover(truthId, false);
    this.engine.audio.truth();
    if (firstTime && this.engine.world) this.engine.world.sparkleAtHotspot(truthId);
    logEvent("INFO", "Truth checked: " + truth.object + " (" + truth.status + ")");
    const isAnach = truth.status === "anachronistic";
    const body = document.createElement("div");
    body.innerHTML =
      "<div class='" + (isAnach ? "verdict-anach" : "verdict-auth") + "'>" +
      "<h3>" + (isAnach ? "⚠ TIMELINE DISTORTION" : "✓ AUTHENTIC") + "</h3>" +
      "<p><strong>Object:</strong> " + esc(truth.object) + "</p>" +
      "<p><strong>Historical Status:</strong> " + (isAnach ? "✕ ANACHRONISTIC" : "✓ AUTHENTIC") + "</p>" +
      (isAnach ? "<p><strong>Expected Era:</strong> " + esc(truth.expectedEra) + "</p><p><strong>Current Era:</strong> " + esc(truth.currentEra) + "</p><p><strong>Paradox Contribution:</strong> +" + truth.paradox + "%</p>" : "") +
      "<p><strong>Historical Fact:</strong> " + esc(truth.fact) + "</p>" +
      "<p><strong>Truth Confidence:</strong> " + truth.confidence + "%</p>" +
      (truth.clue ? "<p class='clue'>🔎 Clue: " + esc(truth.clue) + "</p>" : "") +
      (firstTime ? "<p>⭐ First discovery! +50 points, Timeline Stability +2%. " + esc(praise()) + "</p>" : "<p>Already discovered — no additional points.</p>") +
      "</div>";
    this.engine.ui.openModal("🔎 TRUTH VERIFICATION", body, [
      { label: "Close", onClick: () => this.engine.ui.closeModal() }
    ]);
    this.engine.refreshUI();
  }
}

/* ---------------- DialogueManager ---------------- */
class DialogueManager {
  constructor(state, engine) { this.state = state; this.engine = engine; this.current = null; }
  start(dialogueId) {
    const dlg = GAME_DATA.dialogues[dialogueId];
    if (!dlg) {
      logEvent("ERROR", "Dialogue not found: " + dialogueId);
      this.engine.ui.setPanel("<p>The person has nothing to say right now.</p>");
      return;
    }
    this.current = { id: dialogueId, node: dlg.start };
    logEvent("INFO", "Dialogue started: " + dialogueId);
    if (this.engine.world) this.engine.world.setTalking(dlg.npc, true);
    this.render();
  }
  render() {
    if (!this.current) return;
    const dlg = GAME_DATA.dialogues[this.current.id];
    const node = dlg.nodes[this.current.node];
    if (!node) { this.end(); return; }
    const npc = GAME_DATA.characters[dlg.npc];
    const body = document.createElement("div");
    const who = makeEl("p", "speaker", (npc ? npc.name : "Someone") + ":");
    body.appendChild(who);
    const text = makeEl("p", null, node.text);
    body.appendChild(text);
    const keys = makeEl("p", "kbd-hint", "Press 1–" + node.choices.length + " to choose, or click.");
    body.appendChild(keys);
    const actions = [];
    node.choices.forEach((choice, i) => {
      const b = makeEl("button", "choice-btn", (i + 1) + ". " + choice.text);
      b.addEventListener("click", () => this.choose(i));
      body.appendChild(b);
    });
    actions.push({ label: "End conversation", secondary: true, onClick: () => { this.end(); this.engine.ui.closeModal(); } });
    this.engine.ui.openModal("💬 " + (npc ? npc.name : "Conversation"), body, actions);
    this._choiceCount = node.choices.length;
  }
  choose(index) {
    if (!this.current) return;
    const dlg = GAME_DATA.dialogues[this.current.id];
    const node = dlg.nodes[this.current.node];
    const choice = node.choices[index];
    if (!choice) return;
    this.engine.audio.click();
    this.state.data.playerChoices.push({ dialogue: this.current.id, node: this.current.node, choice: choice.text });
    this.state.data.dialogueFlags[this.current.id + ":" + this.current.node + ":" + index] = true;
    logEvent("INFO", "Dialogue choice: " + choice.text);
    if (choice.effects) this.engine.timeline.applyEffects(choice.effects, this.engine);
    const npc = GAME_DATA.characters[dlg.npc];
    this.engine.ui.setPanel("<p><span class='speaker'>" + esc(npc ? npc.name : "Someone") + ":</span> " + esc(choice.response || "") + "</p>");
    this.engine.refreshUI();
    if (choice.next) {
      this.current.node = choice.next;
      this.render();
    } else {
      this.end();
      this.engine.ui.closeModal();
    }
  }
  end() {
    if (this.current && this.engine.world) this.engine.world.setTalking(GAME_DATA.dialogues[this.current.id].npc, false);
    this.current = null; this._choiceCount = 0;
  }
}

/* ---------------- PuzzleManager ---------------- */
class PuzzleManager {
  constructor(state, engine) { this.state = state; this.engine = engine; this.attempts = {}; }
  isSolved(id) { return this.state.data.solvedPuzzles.indexOf(id) !== -1; }
  open(puzzleId) {
    const puzzle = GAME_DATA.puzzles[puzzleId];
    if (!puzzle) {
      logEvent("ERROR", "Puzzle definition not found: " + puzzleId);
      this.engine.ui.openModal("Puzzle", "<p>This puzzle could not be loaded. Please continue exploring.</p>", [{ label: "Close", onClick: () => this.engine.ui.closeModal() }]);
      return;
    }
    if (this.isSolved(puzzleId)) {
      this.engine.ui.openModal(puzzle.title, "<p>You have already solved this puzzle. Well done — the solution stands.</p>", [{ label: "Close", onClick: () => this.engine.ui.closeModal() }]);
      return;
    }
    this.attempts[puzzleId] = (this.attempts[puzzleId] || 0) + 1;
    logEvent("INFO", "Puzzle started: " + puzzleId + " (attempt " + this.attempts[puzzleId] + ")");
    this.engine.audio.click();
    if (puzzle.type === "anachronism") this.renderAnachronism(puzzle);
    else if (puzzle.type === "sequence") this.renderSequence(puzzle);
    else if (puzzle.type === "cipher") this.renderCipher(puzzle);
    else if (puzzle.type === "testimony") this.renderTestimony(puzzle);
    else if (puzzle.type === "code") this.renderCode(puzzle);
    else {
      logEvent("ERROR", "Unknown puzzle type: " + puzzle.type);
      this.engine.ui.openModal("Puzzle", "<p>This puzzle type is not supported in this build.</p>", [{ label: "Close", onClick: () => this.engine.ui.closeModal() }]);
    }
  }
  solve(puzzle) {
    this.state.data.solvedPuzzles.push(puzzle.id);
    this.engine.scores.add(puzzle.score, "puzzles");
    if (puzzle.paradoxReward) this.engine.timeline.addParadox(puzzle.paradoxReward);
    this.engine.audio.solved();
    if (this.engine.world) this.engine.world.celebrate();
    logEvent("INFO", "Puzzle completed: " + puzzle.id);
    this.engine.ui.openModal("✅ Puzzle Solved: " + puzzle.title,
      "<p>Excellent work. <strong>+" + puzzle.score + " points.</strong> Timeline Stability improved.</p><p class='clue'>" + esc(praise()) + "</p>",
      [{ label: "Continue", onClick: () => { this.engine.ui.closeModal(); this.engine.onPuzzleSolved(puzzle.id); } }]);
    this.engine.refreshUI();
  }
  fail(puzzle, message) {
    this.engine.timeline.addParadox(2);
    this.engine.audio.error();
    logEvent("INFO", "Puzzle attempt failed: " + puzzle.id);
    this.engine.ui.openModal("Not quite — " + puzzle.title,
      "<p>" + esc(message) + "</p><p class='clue'>💡 Hint: " + esc(puzzle.hint) + "</p><p>Paradox +2%. Try again — there is no penalty for thinking.</p>",
      [{ label: "Try again", onClick: () => { this.engine.ui.closeModal(); this.open(puzzle.id); } },
       { label: "Leave for now", secondary: true, onClick: () => this.engine.ui.closeModal() }]);
    this.engine.refreshUI();
  }
  renderAnachronism(puzzle) {
    const body = document.createElement("div");
    body.appendChild(makeEl("p", null, puzzle.instructions));
    const wantAnach = puzzle.mode !== "authentic";
    const targetCount = puzzle.options.filter((o) => o.anachronistic === wantAnach).length;
    body.appendChild(makeEl("p", "kbd-hint", "Select " + targetCount + " object" + (targetCount > 1 ? "s" : "") + (wantAnach ? " that do NOT belong in this era." : " that belong in this era.")));
    const grid = makeEl("div", "anach-grid");
    const selected = new Set();
    puzzle.options.forEach((opt) => {
      const card = makeEl("button", "anach-card", "");
      card.innerHTML = "<span class='a-icon'>" + opt.icon + "</span>" + esc(opt.label);
      card.setAttribute("aria-pressed", "false");
      card.addEventListener("click", () => {
        if (selected.has(opt.id)) { selected.delete(opt.id); card.classList.remove("selected"); card.setAttribute("aria-pressed", "false"); }
        else { selected.add(opt.id); card.classList.add("selected"); card.setAttribute("aria-pressed", "true"); }
        this.engine.audio.click();
      });
      grid.appendChild(card);
    });
    body.appendChild(grid);
    this.engine.ui.openModal("🧩 " + puzzle.title, body, [
      { label: "Confirm selection", onClick: () => {
        const correctSet = puzzle.options.filter((o) => o.anachronistic === wantAnach).map((o) => o.id).sort();
        const picked = Array.from(selected).sort();
        const ok = JSON.stringify(correctSet) === JSON.stringify(picked);
        if (ok) this.solve(puzzle);
        else this.fail(puzzle, "That selection is not right. Look again — which objects could not have been made, powered or understood in this era?");
      } },
      { label: "Hint", secondary: true, onClick: () => { this.engine.ui.openModal("Hint", "<p>" + esc(puzzle.hint) + "</p>", [{ label: "Back", onClick: () => this.open(puzzle.id) }]); } },
      { label: "Leave", secondary: true, onClick: () => this.engine.ui.closeModal() }
    ]);
  }
  renderSequence(puzzle) {
    const body = document.createElement("div");
    body.appendChild(makeEl("p", null, puzzle.instructions));
    const picked = [];
    const orderBox = makeEl("p", "clue", "Your order: (none yet)");
    body.appendChild(orderBox);
    const list = document.createElement("div");
    puzzle.steps.forEach((step) => {
      const b = makeEl("button", "seq-item", step.label + " — " + step.detail);
      b.addEventListener("click", () => {
        if (picked.indexOf(step.id) !== -1) return;
        picked.push(step.id);
        b.classList.add("picked");
        b.disabled = true;
        orderBox.textContent = "Your order: " + picked.map((id) => {
          const s = puzzle.steps.find((x) => x.id === id);
          return s ? s.label : id;
        }).join(" → ");
        this.engine.audio.click();
      });
      list.appendChild(b);
    });
    body.appendChild(list);
    const resetBtn = makeEl("button", "btn secondary small", "↺ Reset order");
    resetBtn.addEventListener("click", () => this.open(puzzle.id));
    body.appendChild(resetBtn);
    this.engine.ui.openModal("🧩 " + puzzle.title, body, [
      { label: "Check order", onClick: () => {
        const correct = puzzle.correct || [];
        if (JSON.stringify(picked) === JSON.stringify(correct)) this.solve(puzzle);
        else this.fail(puzzle, "That order is not the true sequence. History has a definite order — check the dates and try again.");
      } },
      { label: "Hint", secondary: true, onClick: () => { this.engine.ui.openModal("Hint", "<p>" + esc(puzzle.hint) + "</p>", [{ label: "Back", onClick: () => this.open(puzzle.id) }]); } },
      { label: "Leave", secondary: true, onClick: () => this.engine.ui.closeModal() }
    ]);
  }
  renderCipher(puzzle) {
    const body = document.createElement("div");
    body.appendChild(makeEl("p", null, puzzle.instructions));
    body.appendChild(makeEl("p", null, "Encoded message: "));
    const code = makeEl("p", null, "");
    code.innerHTML = "<strong style='font-size:1.4rem; letter-spacing:.3em'>" + esc(puzzle.encoded) + "</strong>";
    body.appendChild(code);
    const input = makeEl("input", "text-input");
    input.setAttribute("type", "text");
    input.setAttribute("aria-label", "Decoded message");
    input.setAttribute("maxlength", "20");
    body.appendChild(input);
    this.engine.ui.openModal("🧩 " + puzzle.title, body, [
      { label: "Decode", onClick: () => {
        const val = (input.value || "").trim().toUpperCase();
        if (val === puzzle.answer) this.solve(puzzle);
        else this.fail(puzzle, "“" + (val || "(nothing)") + "” is not the decoded message. Remember the shift.");
      } },
      { label: "Hint", secondary: true, onClick: () => { this.engine.ui.openModal("Hint", "<p>" + esc(puzzle.hint) + "</p>", [{ label: "Back", onClick: () => this.open(puzzle.id) }]); } },
      { label: "Leave", secondary: true, onClick: () => this.engine.ui.closeModal() }
    ]);
    input.focus();
  }
  renderTestimony(puzzle) {
    const body = document.createElement("div");
    body.appendChild(makeEl("p", null, puzzle.instructions));
    puzzle.statements.forEach((st) => {
      const b = makeEl("button", "choice-btn", st.text);
      b.addEventListener("click", () => {
        if (st.correct) this.solve(puzzle);
        else this.fail(puzzle, "That account does not fit the facts. " + st.why);
      });
      body.appendChild(b);
    });
    this.engine.ui.openModal("🧩 " + puzzle.title, body, [
      { label: "Hint", secondary: true, onClick: () => { this.engine.ui.openModal("Hint", "<p>" + esc(puzzle.hint) + "</p>", [{ label: "Back", onClick: () => this.open(puzzle.id) }]); } },
      { label: "Leave", secondary: true, onClick: () => this.engine.ui.closeModal() }
    ]);
  }
  renderCode(puzzle) {
    const body = document.createElement("div");
    body.appendChild(makeEl("p", null, puzzle.instructions));
    const input = makeEl("input", "code-input");
    input.setAttribute("type", "text");
    input.setAttribute("inputmode", "numeric");
    input.setAttribute("aria-label", "Four digit code");
    input.setAttribute("maxlength", "4");
    body.appendChild(input);
    const digits = makeEl("p", "kbd-hint", "Digits you have found: " + this.engine.keyDigitsText());
    body.appendChild(digits);
    this.engine.ui.openModal("🧩 " + puzzle.title, body, [
      { label: "Seal the Core", onClick: () => {
        const val = (input.value || "").trim();
        if (val === puzzle.answer) this.solve(puzzle);
        else this.fail(puzzle, "The Core rejects that sequence. The digits are one per act — Kite, Loom, Lens, Wing.");
      } },
      { label: "Hint", secondary: true, onClick: () => { this.engine.ui.openModal("Hint", "<p>" + esc(puzzle.hint) + "</p>", [{ label: "Back", onClick: () => this.open(puzzle.id) }]); } },
      { label: "Leave", secondary: true, onClick: () => this.engine.ui.closeModal() }
    ]);
    input.focus();
  }
}

/* ---------------- QuizEngine ---------------- */
class QuizEngine {
  constructor(state, engine) { this.state = state; this.engine = engine; }
  scoreFor(correct) {
    if (correct === 5) return 500;
    if (correct === 4) return 350;
    if (correct === 3) return 200;
    if (correct === 2) return 100;
    return 0;
  }
  starsFor(correct) {
    if (correct >= 5) return "⭐⭐⭐";
    if (correct === 4) return "⭐⭐";
    if (correct === 3) return "⭐";
    return "";
  }
  start(quizId, onDone) {
    const quiz = GAME_DATA.quizzes[quizId];
    if (!quiz || !quiz.questions || quiz.questions.length === 0) {
      logEvent("ERROR", "Quiz not found or empty: " + quizId);
      if (onDone) onDone(false);
      return;
    }
    logEvent("INFO", "Quiz started: " + quizId);
    this._run(quizId, quiz, 0, 0, onDone);
  }
  _run(quizId, quiz, index, correct, onDone) {
    const q = quiz.questions[index];
    const body = document.createElement("div");
    body.appendChild(makeEl("p", "kbd-hint", quiz.title + " — Question " + (index + 1) + " of " + quiz.questions.length));
    body.appendChild(makeEl("h3", null, q.q));
    const feedback = makeEl("p", null, "");
    body.appendChild(feedback);
    let answered = false;
    q.options.forEach((opt, i) => {
      const b = makeEl("button", "quiz-opt", String.fromCharCode(65 + i) + ". " + opt);
      b.addEventListener("click", () => {
        if (answered) return;
        answered = true;
        const ok = i === q.answer;
        b.classList.add(ok ? "correct" : "wrong");
        if (!ok) {
          const right = body.querySelectorAll(".quiz-opt")[q.answer];
          if (right) right.classList.add("correct");
          this.engine.audio.error();
        } else {
          this.engine.audio.solved();
        }
        feedback.innerHTML = (ok ? "✅ Correct! " : "❌ Not quite. ") + "<span class='fact'>" + esc(q.explanation) + "</span>";
        logEvent("INFO", "Quiz answered: " + quizId + " Q" + (index + 1) + " " + (ok ? "correct" : "wrong"));
        const nextBtn = makeEl("button", "btn", index + 1 < quiz.questions.length ? "Next question →" : "See results");
        nextBtn.addEventListener("click", () => {
          if (index + 1 < quiz.questions.length) this._run(quizId, quiz, index + 1, correct + (ok ? 1 : 0), onDone);
          else this._finish(quizId, quiz, correct + (ok ? 1 : 0), onDone);
        });
        body.appendChild(nextBtn);
        nextBtn.focus();
      });
      body.appendChild(b);
    });
    this.engine.ui.openModal("📝 " + quiz.title, body, []);
  }
  _finish(quizId, quiz, correct, onDone) {
    const total = quiz.questions.length;
    const points = this.scoreFor(correct);
    const passed = correct >= 2;
    this.state.data.quizResults[quizId] = { correct, total, score: passed ? points : 0, passed };
    if (passed) {
      this.engine.scores.add(points, "knowledge");
      if (this.engine.world) this.engine.world.celebrate();
    }
    logEvent("INFO", "Quiz finished: " + quizId + " " + correct + "/" + total + " passed=" + passed);
    const body = document.createElement("div");
    body.innerHTML = "<h3>" + correct + " / " + total + " correct</h3>" +
      (passed && this.starsFor(correct) ? "<p class='stars'>" + this.starsFor(correct) + "</p>" : "") +
      "<p>" + (passed ? "You earned <strong>+" + points + " points</strong>. " + esc(praise()) : "You need at least 2 correct answers to proceed. The timeline demands better — but there is no penalty for trying again.") + "</p>" +
      "<p>Scoring: 5/5 = +500, 4/5 = +350, 3/5 = +200, 2/5 = +100, 0–1 = retry required.</p>";
    const actions = [];
    if (passed) {
      actions.push({ label: "Continue", onClick: () => { this.engine.ui.closeModal(); if (onDone) onDone(true); } });
    } else {
      actions.push({ label: "↻ Retry the quiz", onClick: () => { this.engine.ui.closeModal(); this.start(quizId, onDone); } });
      actions.push({ label: "Review the act first", secondary: true, onClick: () => { this.engine.ui.closeModal(); if (onDone) onDone(false); } });
    }
    this.engine.ui.openModal("📝 Quiz Results", body, actions);
    this.engine.refreshUI();
  }
}

/* ---------------- CharacterFactory ----------------
   All actors are clean vector-style art drawn with the plain canvas
   2D API into offscreen canvases, then registered with Phaser via
   textures.addCanvas — no external images, and no dependency on the
   renderer (so it also works in Phaser's headless mode). Each
   character gets four frames: idle, walk1, walk2, talk. */
const CHAR_STYLE = {
  cadet:          { skin: 0xf0c08c, hair: 0x6b4a2a, hairStyle: "short", coat: 0x1d7f8f, trousers: 0x1d2c4a, sash: true, goggles: true },
  franklin:       { skin: 0xe8b98a, hair: 0x9a9a9a, hairStyle: "grey-sides", coat: 0x6b4a2a, trousers: 0x3a2c1e, waistcoat: 0xd9c9a8, spectacles: true },
  apprentice:     { skin: 0xe8b98a, hair: 0x4a3220, hairStyle: "short", coat: 0x8a7a5a, trousers: 0x4a3a2a, apron: 0xd9c9a8 },
  printer:        { skin: 0xd9a878, hair: 0x2c2c2c, hairStyle: "cap", coat: 0x3a3a3a, trousers: 0x2c2c2c, apron: 0x666666 },
  librarian:      { skin: 0xe8b98a, hair: 0x7a6a5a, hairStyle: "bun", coat: 0x7a4a6b, trousers: 0x3a2c3a },
  vendor:         { skin: 0xc98a5a, hair: 0x2c2c2c, hairStyle: "cap", coat: 0x4a6b46, trousers: 0x3a2c1e, moustache: true },
  mill_owner:     { skin: 0xe8b98a, hair: 0x9a9a9a, hairStyle: "grey-sides", coat: 0x22222e, trousers: 0x1a1a24, hat: "tophat", waistcoat: 0x8a7a5a },
  worker:         { skin: 0xd9a878, hair: 0x4a3220, hairStyle: "cap", coat: 0x8a7a5a, trousers: 0x4a3a2a },
  engineer:       { skin: 0xf0c08c, hair: 0x2c2c2c, hairStyle: "bun", coat: 0x3a5a7a, trousers: 0x2c2c3a },
  astronomer:     { skin: 0xe8b98a, hair: 0xd9d9d9, hairStyle: "beard", coat: 0x2c3a6b, trousers: 0x1d2c4a, hat: "cap", hatColor: 0x2c3a6b },
  apothecary:     { skin: 0xe8b98a, hair: 0x888888, hairStyle: "wimple", coat: 0x4a4a4a, trousers: 0x3a3a3a },
  student:        { skin: 0xf0c08c, hair: 0x6b4a2a, hairStyle: "cap", coat: 0x5a3a2c, trousers: 0x3a2c22 },
  pilot:          { skin: 0xd9a878, hair: 0x4a3220, hairStyle: "short", coat: 0x6b4a2a, trousers: 0x3a2c1e, scarf: 0xf2f2f2, goggles: true },
  mechanic:       { skin: 0xc98a5a, hair: 0x2c2c2c, hairStyle: "cap", coat: 0x3a4a5a, trousers: 0x2c343c },
  engineer4:      { skin: 0xf0c08c, hair: 0x2c2c2c, hairStyle: "bun", coat: 0x7a3a4a, trousers: 0x3a2c3a },
  chronarch:      { skin: 0x9ab8c8, hair: 0x1d3a4a, hairStyle: "hood", coat: 0x1d3a4a, trousers: 0x1d3a4a, robe: true, glowEyes: true },
  chronarch_final:{ skin: 0x9ab8c8, hair: 0x1d3a4a, hairStyle: "hood", coat: 0x2a4a5a, trousers: 0x2a4a5a, robe: true, glowEyes: true }
};

class CharacterFactory {
  /* Colours are Phaser-style 0xRRGGBB numbers. */
  static css(c) { return "#" + c.toString(16).padStart(6, "0"); }
  static circle(ctx, x, y, r, color, alpha) {
    ctx.globalAlpha = alpha === undefined ? 1 : alpha;
    ctx.fillStyle = CharacterFactory.css(color);
    ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill();
    ctx.globalAlpha = 1;
  }
  static ellipse(ctx, x, y, w, h, color, alpha) {
    ctx.globalAlpha = alpha === undefined ? 1 : alpha;
    ctx.fillStyle = CharacterFactory.css(color);
    ctx.beginPath(); ctx.ellipse(x, y, w / 2, h / 2, 0, 0, Math.PI * 2); ctx.fill();
    ctx.globalAlpha = 1;
  }
  static rect(ctx, x, y, w, h, color, alpha) {
    ctx.globalAlpha = alpha === undefined ? 1 : alpha;
    ctx.fillStyle = CharacterFactory.css(color);
    ctx.fillRect(x, y, w, h);
    ctx.globalAlpha = 1;
  }
  static roundRect(ctx, x, y, w, h, r, color) {
    ctx.fillStyle = CharacterFactory.css(color);
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + h, r);
    ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r);
    ctx.arcTo(x, y, x + w, y, r);
    ctx.closePath(); ctx.fill();
  }
  static line(ctx, x1, y1, x2, y2, width, color) {
    ctx.strokeStyle = CharacterFactory.css(color);
    ctx.lineWidth = width;
    ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke();
  }
  static halfCap(ctx, x, y, r, color) {
    ctx.fillStyle = CharacterFactory.css(color);
    ctx.beginPath(); ctx.arc(x, y, r, Math.PI, Math.PI * 2); ctx.closePath(); ctx.fill();
  }
  static drawPerson(ctx, s, frame) {
    const C = CharacterFactory;
    const walkA = frame === "walk1", walkB = frame === "walk2", talk = frame === "talk";
    const legLift = walkA ? -4 : walkB ? 4 : 0;
    const armSwing = walkA ? -5 : walkB ? 5 : 0;
    ctx.clearRect(0, 0, 72, 108);
    // legs (hidden under a robe)
    if (!s.robe) {
      C.rect(ctx, 26 + (walkA ? -3 : 0), 66, 9, 34 + (walkA ? legLift : 0), s.trousers);
      C.rect(ctx, 38 + (walkB ? 3 : 0), 66, 9, 34 + (walkB ? legLift : 0), s.trousers);
      C.rect(ctx, 24 + (walkA ? -3 : 0), 96 + (walkA ? legLift : 0), 12, 6, 0x1a1a1a);
      C.rect(ctx, 38 + (walkB ? 3 : 0), 96 + (walkB ? legLift : 0), 12, 6, 0x1a1a1a);
    }
    // torso / robe
    if (s.robe) C.roundRect(ctx, 20, 38, 32, 64, 8, s.coat);
    else C.roundRect(ctx, 20, 38, 32, 30, 6, s.coat);
    if (s.waistcoat) C.rect(ctx, 28, 40, 16, 26, s.waistcoat);
    if (s.apron) C.rect(ctx, 22, 42, 28, 24, s.apron);
    if (s.sash) C.line(ctx, 22, 42, 50, 66, 4, 0xc9a227);
    // arms
    if (talk) {
      C.rect(ctx, 20, 42, 6, 22, s.coat); // left arm down
      C.rect(ctx, 46, 24, 6, 22, s.coat); // right arm raised
      C.circle(ctx, 23, 66, 3.5, s.skin); C.circle(ctx, 49, 24, 3.5, s.skin);
    } else {
      C.rect(ctx, 20 + (armSwing > 0 ? 2 : -2), 42, 6, 22, s.coat);
      C.rect(ctx, 46 + (armSwing < 0 ? -2 : 2), 42, 6, 22, s.coat);
      C.circle(ctx, 23 + (armSwing > 0 ? 2 : -2), 66, 3.5, s.skin);
      C.circle(ctx, 49 + (armSwing < 0 ? -2 : 2), 66, 3.5, s.skin);
    }
    if (s.scarf) C.rect(ctx, 22, 34, 28, 6, s.scarf);
    // head
    if (s.hairStyle === "hood") {
      C.circle(ctx, 36, 26, 14, s.coat);
      C.circle(ctx, 36, 27, 9, s.skin);
    } else if (s.hairStyle === "wimple") {
      C.circle(ctx, 36, 26, 13, 0xf2f2f2);
      C.circle(ctx, 36, 27, 9.5, s.skin);
    } else {
      C.circle(ctx, 36, 26, 11, s.skin);
    }
    // hair / hats
    if (s.hairStyle === "short") C.halfCap(ctx, 36, 25, 11, s.hair);
    else if (s.hairStyle === "grey-sides") { C.circle(ctx, 26, 22, 4, s.hair); C.circle(ctx, 46, 22, 4, s.hair); }
    else if (s.hairStyle === "bun") { C.halfCap(ctx, 36, 25, 11, s.hair); C.circle(ctx, 36, 12, 5, s.hair); }
    else if (s.hairStyle === "cap") { C.halfCap(ctx, 36, 25, 11, s.hair); C.rect(ctx, 22, 20, 28, 4, s.hair); }
    else if (s.hairStyle === "beard") C.ellipse(ctx, 36, 35, 15, 10, s.hair);
    if (s.hat === "tophat") { C.rect(ctx, 26, 2, 20, 14, 0x1a1a1a); C.rect(ctx, 22, 14, 28, 4, 0x1a1a1a); }
    if (s.hat === "cap") { C.halfCap(ctx, 36, 25, 11, s.hatColor || s.hair); C.rect(ctx, 22, 20, 28, 4, s.hatColor || s.hair); }
    // face
    if (s.glowEyes) {
      C.circle(ctx, 32, 25, 2, 0x39d5e8); C.circle(ctx, 40, 25, 2, 0x39d5e8);
    } else {
      C.circle(ctx, 32, 25, 1.6, 0x1d2433); C.circle(ctx, 40, 25, 1.6, 0x1d2433);
    }
    if (s.moustache) C.rect(ctx, 31, 30, 10, 2.5, s.hair);
    if (talk) C.ellipse(ctx, 36, 31, 5, 6, 0x4a2c22);
    else {
      ctx.strokeStyle = CharacterFactory.css(0x4a2c22); ctx.lineWidth = 1.4;
      ctx.beginPath(); ctx.arc(36, 27, 5, Math.PI * 0.15, Math.PI * 0.85); ctx.stroke();
    }
    if (s.spectacles) {
      ctx.strokeStyle = CharacterFactory.css(0x2c2c2c); ctx.lineWidth = 1.2;
      ctx.beginPath(); ctx.arc(32, 25, 3.4, 0, Math.PI * 2); ctx.stroke();
      ctx.beginPath(); ctx.arc(40, 25, 3.4, 0, Math.PI * 2); ctx.stroke();
      C.line(ctx, 35.4, 25, 36.6, 25, 1.2, 0x2c2c2c);
    }
    if (s.goggles) {
      C.circle(ctx, 31, 17, 3.6, 0x2c4a6b); C.circle(ctx, 41, 17, 3.6, 0x2c4a6b);
      C.line(ctx, 27, 17, 45, 17, 1.6, 0x2c4a6b);
    }
  }
  static makeCanvas(w, h) {
    const c = document.createElement("canvas");
    c.width = w; c.height = h;
    return c;
  }
  static generateAll(scene) {
    const C = CharacterFactory;
    for (const id of Object.keys(CHAR_STYLE)) {
      for (const frame of ["idle", "walk1", "walk2", "talk"]) {
        const c = C.makeCanvas(72, 108);
        const ctx = c.getContext("2d");
        if (!ctx) { logEvent("ERROR", "No 2D canvas context for character texture " + id); continue; }
        C.drawPerson(ctx, CHAR_STYLE[id], frame);
        scene.textures.addCanvas(id + "_" + frame, c);
      }
    }
    // shared small textures
    const dot = C.makeCanvas(8, 8);
    let ctx = dot.getContext("2d");
    if (ctx) { C.circle(ctx, 4, 4, 4, 0xffffff); scene.textures.addCanvas("dot", dot); }
    const shadow = C.makeCanvas(40, 10);
    ctx = shadow.getContext("2d");
    if (ctx) { C.ellipse(ctx, 20, 5, 40, 10, 0x000000, 0.28); scene.textures.addCanvas("shadow", shadow); }
    const ring = C.makeCanvas(64, 64);
    ctx = ring.getContext("2d");
    if (ctx) {
      ctx.strokeStyle = CharacterFactory.css(0xc9a227); ctx.lineWidth = 4;
      ctx.beginPath(); ctx.arc(32, 32, 26, 0, Math.PI * 2); ctx.stroke();
      ctx.strokeStyle = "rgba(255,255,255,0.9)"; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.arc(32, 32, 30, 0, Math.PI * 2); ctx.stroke();
      scene.textures.addCanvas("ring", ring);
    }
    const ringA = C.makeCanvas(64, 64);
    ctx = ringA.getContext("2d");
    if (ctx) {
      ctx.strokeStyle = CharacterFactory.css(0xff7a5c); ctx.lineWidth = 4;
      ctx.beginPath(); ctx.arc(32, 32, 26, 0, Math.PI * 2); ctx.stroke();
      ctx.strokeStyle = "rgba(255,255,255,0.9)"; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.arc(32, 32, 30, 0, Math.PI * 2); ctx.stroke();
      scene.textures.addCanvas("ring-anomaly", ringA);
    }
    const cloud = C.makeCanvas(120, 48);
    ctx = cloud.getContext("2d");
    if (ctx) {
      C.ellipse(ctx, 30, 24, 46, 22, 0xffffff, 0.85);
      C.ellipse(ctx, 62, 20, 44, 24, 0xffffff, 0.85);
      C.ellipse(ctx, 90, 26, 46, 20, 0xffffff, 0.85);
      scene.textures.addCanvas("cloud", cloud);
    }
  }
}

/* ---------------- ScenePainter ----------------
   Layered vector backdrops, one painter per backdrop key.
   Canvas is 960 x 540; the floor band is y 380-540. */
class ScenePainter {
  static band(g, x, y, w, h, c1, c2, steps) {
    const r1 = (c1 >> 16) & 255, g1 = (c1 >> 8) & 255, b1 = c1 & 255;
    const r2 = (c2 >> 16) & 255, g2 = (c2 >> 8) & 255, b2 = c2 & 255;
    for (let i = 0; i < steps; i++) {
      const t = i / (steps - 1);
      const c = ((Math.round(r1 + (r2 - r1) * t)) << 16) | ((Math.round(g1 + (g2 - g1) * t)) << 8) | Math.round(b1 + (b2 - b1) * t);
      g.fillStyle(c, 1);
      g.fillRect(x, y + (h / steps) * i, w, h / steps + 1);
    }
  }
  static wall(g, color, floorY) {
    g.fillStyle(color, 1); g.fillRect(0, 0, 960, floorY);
    g.fillStyle(0x000000, 0.18); g.fillRect(0, floorY - 14, 960, 14);
  }
  static floorWood(g, y, c1, c2) {
    g.fillStyle(c1, 1); g.fillRect(0, y, 960, 540 - y);
    g.fillStyle(c2, 1);
    for (let yy = y + 22; yy < 540; yy += 26) g.fillRect(0, yy, 960, 2);
  }
  static floorStone(g, y, c1, c2) {
    g.fillStyle(c1, 1); g.fillRect(0, y, 960, 540 - y);
    g.fillStyle(c2, 1);
    for (let yy = y + 24; yy < 540; yy += 28) g.fillRect(0, yy, 960, 2);
    for (let xx = 60; xx < 960; xx += 120) g.fillRect(xx, y, 2, 540 - y);
  }
  static floorGrass(g, y, c1, c2) {
    g.fillStyle(c1, 1); g.fillRect(0, y, 960, 540 - y);
    g.fillStyle(c2, 1);
    for (let i = 0; i < 40; i++) g.fillRect((i * 97) % 960, y + 8 + ((i * 53) % 120), 14, 3);
  }
  static win(g, x, y, w, h, night) {
    g.fillStyle(0x3a2c14, 1); g.fillRect(x - 6, y - 6, w + 12, h + 12);
    g.fillStyle(night ? 0x1d2c4a : 0x9ec8e8, 1); g.fillRect(x, y, w, h);
    if (night) { g.fillStyle(0xf2e7c9, 1); g.fillCircle(x + w - 26, y + 26, 14); }
    g.fillStyle(0x3a2c14, 1);
    g.fillRect(x + w / 2 - 3, y, 6, h); g.fillRect(x, y + h / 2 - 3, w, 6);
  }
  static table(g, x, y, w, h, color) {
    g.fillStyle(color, 1); g.fillRect(x, y, w, 14);
    g.fillRect(x + 8, y + 14, 10, h); g.fillRect(x + w - 18, y + 14, 10, h);
  }
  static shelf(g, x, y, w, rows) {
    const cols = [0x8b2e2e, 0x2e5a8b, 0x2e8b57, 0x8b6b2e, 0x5a2e8b];
    for (let r = 0; r < rows; r++) {
      const yy = y + r * 56;
      g.fillStyle(0x4a3220, 1); g.fillRect(x, yy + 44, w, 8);
      for (let i = 0; i < Math.floor(w / 16); i++) {
        g.fillStyle(cols[(i + r) % cols.length], 1);
        g.fillRect(x + 6 + i * 16, yy + 8 + ((i * 7 + r * 3) % 8), 11, 36);
      }
    }
  }
  static door(g, x, y, w, h, color) {
    g.fillStyle(color, 1); g.fillRect(x, y, w, h);
    g.fillStyle(0x000000, 0.25); g.fillRect(x, y, w, 10);
    g.fillStyle(0xc9a227, 1); g.fillCircle(x + w - 14, y + h / 2, 4);
  }
  static biplane(g, x, y, scale) {
    g.fillStyle(0x8a7a5a, 1);
    g.fillRect(x - 70 * scale, y - 26 * scale, 150 * scale, 10 * scale);
    g.fillRect(x - 60 * scale, y + 6 * scale, 130 * scale, 9 * scale);
    g.fillStyle(0x6b5a44, 1);
    g.fillRect(x - 10 * scale, y - 22 * scale, 90 * scale, 16 * scale);
    g.lineStyle(3, 0x3a2c1e, 1);
    g.lineBetween(x - 40 * scale, y - 20 * scale, x - 40 * scale, y + 8 * scale);
    g.lineBetween(x + 20 * scale, y - 20 * scale, x + 20 * scale, y + 8 * scale);
    g.fillStyle(0x2c2c2c, 1);
    g.fillCircle(x + 84 * scale, y - 14 * scale, 4 * scale);
    g.lineStyle(2, 0x2c2c2c, 1);
    g.lineBetween(x + 84 * scale, y - 34 * scale, x + 84 * scale, y + 6 * scale);
  }
  static paint(g, backdrop) {
    const P = ScenePainter;
    g.clear();
    switch (backdrop) {
      case "bg-workshop":
        P.wall(g, 0x6b4a2a, 380); P.floorWood(g, 380, 0x4a3220, 0x3a2818);
        P.win(g, 60, 60, 130, 150, false);
        P.table(g, 480, 300, 380, 80, 0x5c4630);
        g.fillStyle(0x9ec8e8, 1); g.fillCircle(560, 282, 12); g.fillCircle(620, 284, 10);
        g.fillStyle(0x2c4a6b, 1); g.fillRect(700, 268, 26, 34);
        g.fillStyle(0xc9a227, 1); g.fillRect(520, 276, 40, 8); g.fillRect(760, 280, 60, 6);
        g.fillStyle(0xf2e7c9, 1); g.fillCircle(880, 90, 16); g.fillRect(876, 106, 8, 40);
        break;
      case "bg-printshop":
        P.wall(g, 0x5c4630, 380); P.floorWood(g, 380, 0x3a2c1e, 0x2c2118);
        g.fillStyle(0x2c2c2c, 1); g.fillRect(380, 120, 220, 260);
        g.fillStyle(0x4a4a4a, 1); g.fillRect(400, 140, 180, 60);
        g.fillStyle(0x8a7a5a, 1); g.fillCircle(490, 250, 46);
        g.lineStyle(6, 0x8a7a5a, 1); g.lineBetween(490, 250, 560, 180);
        g.fillStyle(0xf2f2f2, 1);
        for (let i = 0; i < 5; i++) g.fillRect(700 + i * 6, 320 - i * 8, 60, 6);
        P.win(g, 760, 60, 120, 140, false);
        break;
      case "bg-marketplace":
        P.band(g, 0, 0, 960, 380, 0x7a9ab0, 0xc8d8e8, 12);
        P.floorStone(g, 380, 0x8a7a5a, 0x6b5a44);
        g.fillStyle(0x8b2e2e, 1); g.fillTriangle(120, 200, 300, 200, 210, 150);
        g.fillStyle(0x2e5a8b, 1); g.fillTriangle(380, 200, 560, 200, 470, 150);
        g.fillStyle(0x6b4a2a, 1); g.fillRect(130, 200, 160, 70); g.fillRect(390, 200, 160, 70);
        g.fillStyle(0xd9a03a, 1); g.fillCircle(180, 190, 12); g.fillCircle(220, 192, 10); g.fillCircle(440, 190, 12);
        g.fillStyle(0x4a6b46, 1); g.fillCircle(500, 192, 11);
        g.fillStyle(0x5a4a3a, 1); g.fillRect(700, 220, 180, 50);
        g.fillStyle(0x8a7a5a, 1); g.fillRect(720, 270, 20, 110); g.fillRect(840, 270, 20, 110);
        break;
      case "bg-library":
        P.wall(g, 0x6b4d1f, 380); P.floorWood(g, 380, 0x4a3220, 0x3a2818);
        P.shelf(g, 40, 40, 240, 4); P.shelf(g, 680, 40, 240, 4);
        P.table(g, 360, 320, 240, 60, 0x5c4630);
        g.fillStyle(0x8b2e2e, 1); g.fillRect(420, 300, 30, 18); g.fillRect(470, 302, 26, 16);
        g.fillStyle(0xf2e7c9, 1); g.fillCircle(600, 300, 14);
        break;
      case "bg-street":
        P.band(g, 0, 0, 960, 380, 0x5a6b7a, 0xa8b8c8, 12);
        g.fillStyle(0x6b4a3a, 1); g.fillRect(60, 120, 200, 260); g.fillRect(700, 100, 200, 280);
        g.fillStyle(0x9ec8e8, 1);
        for (let i = 0; i < 3; i++) { g.fillRect(90 + i * 55, 150, 30, 40); g.fillRect(730 + i * 55, 130, 30, 40); }
        P.floorStone(g, 380, 0x7a7a7a, 0x5a5a5a);
        g.fillStyle(0x2c2c2c, 1); g.fillRect(480, 180, 8, 200);
        g.fillStyle(0xf2e7c9, 1); g.fillCircle(484, 172, 14);
        break;
      case "bg-meeting":
        P.wall(g, 0x6b3a24, 380); P.floorWood(g, 380, 0x4a2c1e, 0x3a2218);
        P.table(g, 280, 300, 400, 80, 0x5c4630);
        g.fillStyle(0x2c4a6b, 1); g.fillCircle(480, 282, 22);
        g.fillStyle(0xc9a227, 1); g.fillRect(330, 286, 8, 22); g.fillRect(620, 286, 8, 22);
        g.fillStyle(0xf2e7c9, 1); g.fillCircle(334, 282, 7); g.fillCircle(624, 282, 7);
        P.win(g, 760, 60, 130, 150, false);
        break;
      case "bg-mill":
        P.wall(g, 0x6b5a44, 380); P.floorWood(g, 380, 0x3a2c1e, 0x2c2118);
        P.win(g, 60, 50, 130, 170, false); P.win(g, 770, 50, 130, 170, false);
        g.fillStyle(0x4a3220, 1); g.fillRect(340, 140, 280, 180);
        g.lineStyle(2, 0xd9c9a8, 0.9);
        for (let i = 0; i < 12; i++) g.lineBetween(360 + i * 20, 150, 360 + i * 20, 310);
        g.fillStyle(0x8a7a5a, 1); g.fillRect(340, 300, 280, 16);
        g.fillStyle(0xd9c9a8, 1); g.fillRect(120, 330, 90, 50); g.fillRect(750, 330, 90, 50);
        break;
      case "bg-cottage":
        P.wall(g, 0x6b7a44, 380); P.floorWood(g, 380, 0x4a3220, 0x3a2818);
        g.fillStyle(0x6b4a3a, 1); g.fillRect(60, 120, 180, 260);
        g.fillStyle(0x2c2c2c, 1); g.fillRect(120, 200, 60, 80);
        g.fillStyle(0xff7a3c, 1); g.fillTriangle(130, 260, 170, 260, 150, 210);
        g.fillStyle(0xf2e7c9, 1); g.fillTriangle(140, 260, 162, 260, 151, 225);
        P.table(g, 640, 300, 220, 80, 0x5c4630);
        P.win(g, 700, 60, 120, 130, false);
        break;
      case "bg-warehouse":
        P.wall(g, 0x46586a, 380); P.floorStone(g, 380, 0x5a5a5a, 0x444444);
        g.fillStyle(0x6b4a2a, 1);
        g.fillRect(80, 240, 110, 110); g.fillRect(200, 260, 90, 90); g.fillRect(90, 140, 80, 90);
        g.lineStyle(3, 0x4a3220, 1);
        g.lineBetween(80, 240, 190, 350); g.lineBetween(190, 240, 80, 350);
        g.fillStyle(0x8a7a5a, 1); g.fillCircle(760, 300, 40); g.fillCircle(840, 320, 34);
        P.win(g, 420, 60, 140, 150, false);
        break;
      case "bg-observatory":
        P.band(g, 0, 0, 960, 380, 0x0a0e24, 0x2c3a6b, 12);
        g.fillStyle(0xffffff, 1);
        for (let i = 0; i < 40; i++) g.fillCircle((i * 173) % 960, (i * 97) % 340 + 10, 2);
        g.fillStyle(0xf2e7c9, 1); g.fillCircle(800, 80, 26);
        P.floorStone(g, 380, 0x3a3a4a, 0x2c2c3a);
        g.lineStyle(8, 0xc9a227, 1); g.lineBetween(480, 360, 620, 180);
        g.fillStyle(0x2c4a6b, 1); g.fillCircle(630, 170, 16);
        P.table(g, 300, 330, 200, 50, 0x5c4630);
        break;
      case "bg-apothecary":
        P.wall(g, 0x4a6b4a, 380); P.floorWood(g, 380, 0x4a3220, 0x3a2818);
        P.shelf(g, 40, 60, 220, 3); P.shelf(g, 700, 60, 220, 3);
        P.table(g, 380, 300, 220, 80, 0x5c4630);
        g.fillStyle(0x8b2e2e, 1); g.fillCircle(430, 284, 10); g.fillCircle(470, 286, 8);
        g.fillStyle(0x2e5a8b, 1); g.fillCircle(510, 284, 9);
        g.fillStyle(0x4a6b46, 1); g.fillRect(600, 180, 60, 8);
        break;
      case "bg-university":
        P.wall(g, 0x6b4a6b, 380); P.floorWood(g, 380, 0x4a3220, 0x3a2818);
        g.fillStyle(0x1d2c1e, 1); g.fillRect(330, 70, 300, 150);
        g.lineStyle(2, 0xf2f2f2, 0.8);
        g.lineBetween(350, 110, 610, 110); g.lineBetween(350, 150, 560, 150); g.lineBetween(350, 190, 600, 190);
        P.table(g, 120, 320, 200, 60, 0x5c4630); P.table(g, 640, 320, 200, 60, 0x5c4630);
        break;
      case "bg-airfield":
        P.band(g, 0, 0, 960, 380, 0x7a9ab0, 0xd8e8f2, 12);
        g.fillStyle(0xf2e7c9, 1); g.fillCircle(840, 70, 30);
        P.floorGrass(g, 380, 0x5a7a44, 0x4a6b3a);
        P.biplane(g, 620, 300, 1);
        g.fillStyle(0x2c2c2c, 1); g.fillRect(120, 180, 6, 200);
        g.fillStyle(0xff7a3c, 1); g.fillTriangle(126, 180, 126, 210, 190, 195);
        break;
      case "bg-hangar":
        P.wall(g, 0x6b6b5a, 380); P.floorStone(g, 380, 0x5a5a5a, 0x444444);
        g.fillStyle(0x4a4a4a, 1); g.fillRect(80, 60, 300, 320);
        g.lineStyle(3, 0x2c2c2c, 1);
        for (let i = 0; i < 4; i++) g.lineBetween(110 + i * 70, 60, 110 + i * 70, 380);
        P.biplane(g, 640, 300, 0.9);
        P.table(g, 420, 320, 160, 60, 0x5c4630);
        break;
      case "bg-office":
        P.wall(g, 0x7a6a44, 380); P.floorWood(g, 380, 0x4a3220, 0x3a2818);
        P.table(g, 380, 300, 260, 80, 0x5c4630);
        g.fillStyle(0xf2f2f2, 1); g.fillRect(420, 280, 180, 20);
        g.lineStyle(2, 0x2e5a8b, 1);
        g.lineBetween(440, 290, 580, 290); g.lineBetween(450, 280, 450, 300);
        P.win(g, 760, 60, 130, 150, false);
        g.fillStyle(0x4a4a4a, 1); g.fillRect(80, 180, 90, 200);
        break;
      case "bg-core":
        P.band(g, 0, 0, 960, 540, 0x050a14, 0x12303e, 12);
        for (let r = 200; r > 40; r -= 30) {
          g.lineStyle(3, 0x39d5e8, 0.25 + (200 - r) / 600);
          g.strokeCircle(480, 240, r);
        }
        g.fillStyle(0x39d5e8, 0.9); g.fillCircle(480, 240, 34);
        g.fillStyle(0xffffff, 1); g.fillCircle(480, 240, 16);
        g.fillStyle(0xc9a227, 0.8);
        for (let i = 0; i < 6; i++) g.fillRect(120 + i * 130, 420 + ((i * 37) % 60), 18, 26);
        break;
      case "bg-gallery":
        P.band(g, 0, 0, 960, 540, 0x2c2340, 0x0d0a18, 10);
        for (let i = 0; i < 4; i++) {
          const x = 80 + i * 220;
          g.fillStyle(0xc9a227, 1); g.fillRect(x, 90, 150, 110);
          g.fillStyle([0x8b2e2e, 0x2e5a8b, 0x2e8b57, 0x8b6b2e][i], 1); g.fillRect(x + 8, 98, 134, 94);
        }
        g.fillStyle(0x5a2e3a, 1); g.fillRect(0, 440, 960, 100);
        break;
      case "bg-dais":
        P.band(g, 0, 0, 960, 540, 0x30142a, 0x0d0510, 10);
        g.fillStyle(0x6b4a6b, 1);
        g.fillRect(80, 100, 30, 300); g.fillRect(850, 100, 30, 300);
        g.fillStyle(0x8a6a8a, 1); g.fillRect(70, 90, 50, 16); g.fillRect(840, 90, 50, 16);
        g.fillStyle(0x4a2c44, 1);
        g.fillRect(300, 440, 360, 30); g.fillRect(340, 410, 280, 30); g.fillRect(380, 380, 200, 30);
        g.lineStyle(4, 0x39d5e8, 0.8); g.strokeCircle(480, 330, 44);
        g.fillStyle(0x39d5e8, 0.7); g.fillCircle(480, 330, 14);
        break;
      default:
        P.wall(g, 0x3a3a4a, 380); P.floorWood(g, 380, 0x4a3220, 0x3a2818);
    }
  }
}

/* ---------------- WorldScene (Phaser) ----------------
   Renders the scene backdrop, animated actors, hotspot markers and
   exits; handles click-to-walk navigation and keyboard walking. */
const WORLD_W = 960, WORLD_H = 540;
const FLOOR_TOP = 420, FLOOR_BOTTOM = 510;
const OUTDOOR = ["bg-marketplace", "bg-street", "bg-airfield"];
const INDOOR = ["bg-workshop", "bg-printshop", "bg-library", "bg-meeting", "bg-mill", "bg-cottage", "bg-warehouse", "bg-apothecary", "bg-university", "bg-hangar", "bg-office"];
const AMBIENCE_FOR = {
  "bg-marketplace": "market", "bg-street": "wind", "bg-airfield": "wind",
  "bg-mill": "mill", "bg-observatory": "night",
  "bg-core": "shimmer", "bg-gallery": "shimmer", "bg-dais": "shimmer"
};

/* Defined only when Phaser loaded — the DOM fallback never touches it,
   so the rest of the engine keeps working when Phaser is absent. */
const WorldScene = typeof Phaser !== "undefined" ? class WorldScene extends Phaser.Scene {
  constructor() {
    super({ key: "world" });
    this.currentSceneId = null;
    this.cadet = null; this.cadetShadow = null;
    this.npcSprites = {};
    this.hotspotMarkers = [];
    this.exitSigns = [];
    this.walkTween = null; this.walkTimer = null; this.walkFrame = 0;
    this.keys = null; this.keyDir = null;
    this.atmo = []; // atmosphere objects to destroy on scene change
    this.overlay = null; this.lastShake = 0;
    this.reducedMotion = false;
    try { this.reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches; } catch (e) { /* ignore */ }
  }

  create() {
    engine.world = this; // register the live scene (getScene may be null pre-boot)
    this.input.setTopOnly(true);
    CharacterFactory.generateAll(this);
    this.bgGfx = this.add.graphics().setDepth(0);
    // floor click zone (depth 1; hotspots/NPCs above it win the click)
    this.floorZone = this.add.zone(0, 0, WORLD_W, WORLD_H).setOrigin(0, 0).setDepth(1);
    this.floorZone.setInteractive(new Phaser.Geom.Rectangle(0, 0, WORLD_W, WORLD_H), Phaser.Geom.Rectangle.Contains);
    this.floorZone.on("pointerdown", (p) => {
      if (engine.ui.modalOpen()) return;
      this.walkTo(clamp(p.x, 40, 920), clamp(p.y, FLOOR_TOP, FLOOR_BOTTOM), null);
    });
    // paradox overlay (depth 300)
    this.overlay = this.add.rectangle(0, 0, WORLD_W, WORLD_H, 0x39d5e8, 0).setOrigin(0, 0).setDepth(300).setScrollFactor(0);
    // the Time Cadet
    this.cadetShadow = this.add.image(90, 522, "shadow").setDepth(90);
    this.cadet = this.add.image(90, 470, "cadet_idle").setDepth(470);
    this.cadet.setScale(1.05);
    // keyboard (arrows + WASD)
    this.keys = this.input.keyboard.addKeys("UP,DOWN,LEFT,RIGHT,W,A,S,D");
    this.events.once("shutdown", () => this._clearWalk());
    logEvent("INFO", "Phaser world ready.");
    engine.onWorldReady();
  }

  /* ---------- scene rendering ---------- */
  renderScene(sceneId) {
    const scene = GAME_DATA.scenes[sceneId];
    if (!scene) { logEvent("ERROR", "Scene not found: " + sceneId); return; }
    this.currentSceneId = sceneId;
    this._clearWalk();
    this._clearAtmosphere();
    this.hotspotMarkers.forEach((m) => m.destroy());
    this.hotspotMarkers = [];
    this.exitSigns.forEach((m) => m.destroy());
    this.exitSigns = [];
    for (const k of Object.keys(this.npcSprites)) this.npcSprites[k].destroy();
    this.npcSprites = {};
    ScenePainter.paint(this.bgGfx, scene.backdrop);
    // hotspots
    scene.hotspots.forEach((hs) => {
      if (hs.item && engine.inventory.hasItem(hs.item)) return;
      const x = (hs.x / 100) * WORLD_W;
      const y = (hs.y / 100) * WORLD_H;
      if (hs.npc) this._makeNpc(hs, x, y);
      else this._makeMarker(hs, x, clamp(y, 110, 500));
    });
    // exits as walkable door signs
    const exitSpots = [{ x: 70, y: 445 }, { x: 890, y: 445 }, { x: 800, y: 485 }];
    scene.exits.forEach((ex, i) => {
      const spot = exitSpots[i % exitSpots.length];
      this._makeExit(ex, spot.x, spot.y);
    });
    // place the Cadet (restore position if re-rendering the same scene)
    const saved = engine.cadetPos[sceneId];
    const px = saved ? saved.x : 90, py = saved ? saved.y : 470;
    this.cadet.setPosition(px, py).setDepth(100 + py);
    this.cadetShadow.setPosition(px, py + 52).setDepth(90 + py);
    this.cadet.setTexture("cadet_idle");
    this._startAtmosphere(scene.backdrop);
    this.setParadoxBand(engine.timeline.band());
    try { engine.audio.music.setAmbience(AMBIENCE_FOR[scene.backdrop] || "room"); } catch (e) { /* ignore */ }
  }

  _makeMarker(hs, x, y) {
    const c = this.add.container(x, y).setDepth(200);
    const ring = this.add.image(0, 0, hs.anomaly ? "ring-anomaly" : "ring");
    const icon = this.add.text(0, 0, hs.icon, { fontSize: "26px" }).setOrigin(0.5);
    c.add([ring, icon]);
    c.setSize(64, 64);
    c.setInteractive(new Phaser.Geom.Rectangle(-32, -32, 64, 64), Phaser.Geom.Rectangle.Contains);
    const label = this.add.text(x, y - 46, hs.name, {
      fontSize: "14px", color: "#f2e7c9", backgroundColor: "rgba(11,18,38,0.85)",
      padding: { x: 6, y: 3 }
    }).setOrigin(0.5).setDepth(210).setVisible(false);
    c.on("pointerover", () => { c.setScale(1.15); label.setVisible(true); });
    c.on("pointerout", () => { c.setScale(1); label.setVisible(false); });
    c.on("pointerdown", () => engine.requestHotspot(hs));
    if (hs.anomaly) {
      this.tweens.add({ targets: ring, scaleX: 1.18, scaleY: 1.18, duration: 700, yoyo: true, repeat: -1 });
    } else if (hs.item) {
      this.tweens.add({ targets: c, y: y - 5, duration: 900, yoyo: true, repeat: -1, ease: "Sine.inOut" });
    }
    this.hotspotMarkers.push(c, label);
    return c;
  }

  _makeNpc(hs, x, y) {
    const charId = hs.npc;
    const standY = clamp(y, 400, 480);
    const spr = this.add.image(x, standY, charId + "_idle").setDepth(100 + standY);
    spr.setInteractive({ useHandCursor: true });
    const shadow = this.add.image(x, standY + 52, "shadow").setDepth(90 + standY);
    const bubble = this.add.text(x, standY - 66, "💬", { fontSize: "20px" }).setOrigin(0.5).setDepth(210);
    this.tweens.add({ targets: bubble, y: standY - 72, duration: 1000, yoyo: true, repeat: -1, ease: "Sine.inOut" });
    const label = this.add.text(x, standY - 92, GAME_DATA.characters[charId].name, {
      fontSize: "14px", color: "#f2e7c9", backgroundColor: "rgba(11,18,38,0.85)",
      padding: { x: 6, y: 3 }
    }).setOrigin(0.5).setDepth(210).setVisible(false);
    spr.on("pointerover", () => { label.setVisible(true); spr.setScale(1.06); });
    spr.on("pointerout", () => { label.setVisible(false); spr.setScale(1); });
    spr.on("pointerdown", () => engine.requestHotspot(hs));
    this.tweens.add({ targets: spr, y: standY - 3, duration: 1400 + Math.random() * 600, yoyo: true, repeat: -1, ease: "Sine.inOut" });
    this.npcSprites[charId] = spr;
    this.hotspotMarkers.push(spr, shadow, bubble, label);
    return spr;
  }

  _makeExit(ex, x, y) {
    const c = this.add.container(x, y).setDepth(190);
    const door = this.add.text(0, -14, "🚪", { fontSize: "30px" }).setOrigin(0.5);
    const label = this.add.text(0, 16, ex.label, {
      fontSize: "13px", color: "#e8c766", backgroundColor: "rgba(11,18,38,0.85)",
      padding: { x: 6, y: 3 }
    }).setOrigin(0.5);
    c.add([door, label]);
    c.setSize(120, 70);
    c.setInteractive(new Phaser.Geom.Rectangle(-60, -35, 120, 70), Phaser.Geom.Rectangle.Contains);
    c.on("pointerover", () => c.setScale(1.1));
    c.on("pointerout", () => c.setScale(1));
    c.on("pointerdown", () => engine.requestExit(ex));
    this.exitSigns.push(c);
    return c;
  }

  /* ---------- atmosphere ---------- */
  _startAtmosphere(backdrop) {
    if (this.reducedMotion) return;
    if (OUTDOOR.indexOf(backdrop) !== -1) {
      for (let i = 0; i < 3; i++) {
        const cloud = this.add.image(-140, 40 + i * 55, "cloud").setDepth(5).setAlpha(0.75);
        this.tweens.add({ targets: cloud, x: 1100, duration: 70000 + i * 20000, repeat: -1, delay: i * 15000 });
        this.atmo.push(cloud);
      }
    } else if (backdrop === "bg-observatory" || backdrop === "bg-core" || backdrop === "bg-gallery" || backdrop === "bg-dais") {
      const e = this.add.particles(0, 0, "dot", {
        x: { min: 0, max: WORLD_W }, y: { min: 40, max: 360 },
        lifespan: 5000, speedY: { min: -12, max: -4 }, speedX: { min: -3, max: 3 },
        scale: { start: 0.9, end: 0 }, alpha: { start: 0.8, end: 0 },
        frequency: 260, tint: 0x39d5e8, depth: 20
      });
      this.atmo.push(e);
    } else if (INDOOR.indexOf(backdrop) !== -1) {
      const e = this.add.particles(0, 0, "dot", {
        x: { min: 0, max: WORLD_W }, y: { min: 60, max: 360 },
        lifespan: 7000, speedY: { min: 2, max: 8 }, speedX: { min: -4, max: 4 },
        scale: { start: 0.5, end: 0 }, alpha: { start: 0.3, end: 0 },
        frequency: 320, tint: 0xf2e7c9, depth: 20
      });
      this.atmo.push(e);
    }
  }
  _clearAtmosphere() {
    this.atmo.forEach((a) => { try { a.destroy(); } catch (e) { /* ignore */ } });
    this.atmo = [];
  }

  /* ---------- navigation ---------- */
  walkTo(x, y, done) {
    x = clamp(x, 40, 920); y = clamp(y, FLOOR_TOP, FLOOR_BOTTOM);
    const dx = x - this.cadet.x, dy = y - this.cadet.y;
    const dist = Math.hypot(dx, dy);
    if (dist < 8) { if (done) done(); return; }
    this._clearWalk();
    this.cadet.setFlipX(dx < 0);
    this.walkFrame = 0;
    this.walkTimer = this.time.addEvent({
      delay: 170, loop: true,
      callback: () => {
        this.walkFrame = (this.walkFrame + 1) % 2;
        this.cadet.setTexture(this.walkFrame === 0 ? "cadet_walk1" : "cadet_walk2");
        engine.audio.footstep();
      }
    });
    this.walkTween = this.tweens.add({
      targets: this.cadet, x, y,
      duration: (dist / 240) * 1000,
      ease: "Linear",
      onUpdate: () => {
        this.cadet.setDepth(100 + this.cadet.y);
        this.cadetShadow.setPosition(this.cadet.x, this.cadet.y + 52).setDepth(90 + this.cadet.y);
      },
      onComplete: () => {
        this._clearWalk();
        this.cadet.setTexture("cadet_idle");
        engine.cadetPos[this.currentSceneId] = { x: this.cadet.x, y: this.cadet.y };
        if (done) done();
      }
    });
  }
  _clearWalk() {
    if (this.walkTween) { try { this.walkTween.stop(); } catch (e) { /* ignore */ } this.walkTween = null; }
    if (this.walkTimer) { try { this.walkTimer.remove(false); } catch (e) { /* ignore */ } this.walkTimer = null; }
  }
  update() {
    if (!this.cadet || !this.keys || engine.ui.modalOpen()) return;
    let dx = 0, dy = 0;
    if (this.keys.LEFT.isDown || this.keys.A.isDown) dx -= 1;
    if (this.keys.RIGHT.isDown || this.keys.D.isDown) dx += 1;
    if (this.keys.UP.isDown || this.keys.W.isDown) dy -= 1;
    if (this.keys.DOWN.isDown || this.keys.S.isDown) dy += 1;
    if (dx === 0 && dy === 0) {
      if (!this.walkTween) this.cadet.setTexture("cadet_idle");
      return;
    }
    this._clearWalk();
    const nx = clamp(this.cadet.x + dx * 3.4, 40, 920);
    const ny = clamp(this.cadet.y + dy * 2.6, FLOOR_TOP, FLOOR_BOTTOM);
    if (dx !== 0) this.cadet.setFlipX(dx < 0);
    this._keyStep = (this._keyStep || 0) + Math.hypot(nx - this.cadet.x, ny - this.cadet.y);
    if (this._keyStep > 26) { this._keyStep = 0; engine.audio.footstep(); }
    this.walkFrame = (this.walkFrame + 1) % 2 === 0 ? 0 : 1;
    if (Math.floor((this._keyStepAcc = (this._keyStepAcc || 0) + 1) / 8) % 2 === 0) this.cadet.setTexture("cadet_walk1");
    else this.cadet.setTexture("cadet_walk2");
    this.cadet.setPosition(nx, ny).setDepth(100 + ny);
    this.cadetShadow.setPosition(nx, ny + 52).setDepth(90 + ny);
    engine.cadetPos[this.currentSceneId] = { x: nx, y: ny };
  }
  nearestHotspot() {
    if (!this.currentSceneId) return null;
    const scene = GAME_DATA.scenes[this.currentSceneId];
    let best = null, bestD = 110;
    scene.hotspots.forEach((hs) => {
      if (hs.item && engine.inventory.hasItem(hs.item)) return;
      const hx = (hs.x / 100) * WORLD_W, hy = clamp((hs.y / 100) * WORLD_H, FLOOR_TOP, FLOOR_BOTTOM);
      const d = Math.hypot(hx - this.cadet.x, hy - this.cadet.y);
      if (d < bestD) { bestD = d; best = hs; }
    });
    return best;
  }

  /* ---------- effects ---------- */
  celebrate() {
    if (this.reducedMotion) return;
    try {
      const e = this.add.particles(480, 30, "dot", {
        speed: { min: 120, max: 340 }, angle: { min: 25, max: 155 },
        scale: { start: 1.4, end: 0 }, lifespan: 1500,
        tint: [0xc9a227, 0x39d5e8, 0xff7a5c, 0x4caf6d, 0xe8c766], emitting: false, depth: 260
      });
      e.explode(70, 480, 30);
      this.time.delayedCall(1800, () => { try { e.destroy(); } catch (err) { /* ignore */ } });
    } catch (err) { logEvent("WARNING", "Confetti failed: " + err.message); }
  }
  sparkleAtHotspot(truthId) {
    try {
      const scene = GAME_DATA.scenes[this.currentSceneId];
      if (!scene) return;
      const hs = scene.hotspots.find((h) => h.truth === truthId);
      if (!hs) return;
      const e = this.add.particles((hs.x / 100) * WORLD_W, (hs.y / 100) * WORLD_H, "dot", {
        speed: { min: 20, max: 90 }, scale: { start: 1.1, end: 0 }, lifespan: 900,
        tint: [0xe8c766, 0x39d5e8], emitting: false, depth: 260
      });
      e.explode(16, (hs.x / 100) * WORLD_W, (hs.y / 100) * WORLD_H);
      this.time.delayedCall(1200, () => { try { e.destroy(); } catch (err) { /* ignore */ } });
    } catch (err) { /* best-effort */ }
  }
  setTalking(npcId, on) {
    const spr = this.npcSprites[npcId];
    if (!spr) return;
    spr.setTexture(npcId + (on ? "_talk" : "_idle"));
    if (on && this.cadet) spr.setFlipX(this.cadet.x < spr.x);
    else spr.setFlipX(false);
  }
  setParadoxBand(band) {
    if (!this.overlay) return;
    const conf = {
      stable: { color: 0x39d5e8, alpha: 0 },
      minor: { color: 0x39d5e8, alpha: 0.05 },
      unstable: { color: 0x39d5e8, alpha: 0.10 },
      severe: { color: 0xff7a5c, alpha: 0.14 },
      critical: { color: 0xff3c3c, alpha: 0.20 }
    }[band] || { color: 0x39d5e8, alpha: 0 };
    this.overlay.setFillStyle(conf.color, conf.alpha);
    if ((band === "severe" || band === "critical") && !this.reducedMotion) {
      const now = Date.now();
      if (now - this.lastShake > (band === "critical" ? 2500 : 4500)) {
        this.lastShake = now;
        try { this.cameras.main.shake(220, 0.0035); } catch (e) { /* ignore */ }
      }
    }
  }
} : null;

/* ---------------- SceneManager (DOM + Phaser bridge) ---------------- */
class SceneManager {
  constructor(engine) { this.engine = engine; }
  render(sceneId) {
    const scene = GAME_DATA.scenes[sceneId];
    const engine = this.engine;
    if (!scene) {
      logEvent("ERROR", "Scene not found: " + sceneId);
      engine.ui.setPanel("<p>This place cannot be reached. Please choose another exit.</p>");
      return;
    }
    const state = engine.state.data;
    state.currentScene = sceneId;
    if (state.visitedScenes.indexOf(sceneId) === -1) {
      state.visitedScenes.push(sceneId);
      engine.scores.add(10, "exploration");
      logEvent("INFO", "Scene entered: " + sceneId);
    }
    $("scene-name").textContent = scene.name + " — " + GAME_DATA.acts[scene.act].title;
    $("scene-caption").textContent = scene.caption;
    if (engine.world && engine.worldReady) {
      $("scene-fallback").innerHTML = "";
      $("scene-fallback").classList.add("hidden");
      engine.world.renderScene(sceneId);
    } else if (engine.world) {
      // Phaser is still booting (textures not generated yet) — render the
      // scene as soon as the world is ready instead of crashing.
      engine._pendingScene = sceneId;
      $("scene-fallback").innerHTML = "";
      $("scene-fallback").classList.add("hidden");
    } else {
      this.renderDomFallback(scene);
    }
    const exits = $("exits");
    exits.innerHTML = "";
    scene.exits.forEach((ex) => {
      const b = makeEl("button", "btn secondary small", ex.label);
      b.addEventListener("click", () => engine.travel(ex.to));
      exits.appendChild(b);
    });
    engine.ui.setPanel("<p><strong>" + esc(scene.name) + ".</strong> " + esc(scene.desc) + "</p><p class='kbd-hint'>Click anywhere on the floor to walk there. Click a glowing object or person to investigate it. " + esc(scene.caption) + "</p>");
    engine.selectedHotspot = null;
    engine.refreshUI();
  }
  /* v1-style DOM hotspots, used only if Phaser cannot boot. */
  renderDomFallback(scene) {
    const engine = this.engine;
    const fb = $("scene-fallback");
    fb.innerHTML = "";
    fb.classList.remove("hidden");
    scene.hotspots.forEach((hs) => {
      if (hs.item && engine.inventory.hasItem(hs.item)) return;
      const btn = makeEl("button", "hotspot" + (hs.anomaly ? " anomaly-hs" : ""), "");
      btn.style.left = hs.x + "%";
      btn.style.top = hs.y + "%";
      btn.innerHTML = "<span class='hs-icon'>" + hs.icon + "</span><span>" + esc(hs.name) + "</span>";
      btn.setAttribute("aria-label", hs.name + ". " + hs.desc);
      btn.title = hs.name;
      btn.addEventListener("click", () => engine.selectHotspot(hs, btn));
      fb.appendChild(btn);
    });
  }
}

/* ---------------- GameEngine ---------------- */
class GameEngine {
  constructor() {
    this.state = new GameState();
    this.scores = new ScoreManager(this.state);
    this.timeline = new TimelineManager(this.state);
    this.saves = new SaveManager();
    this.audio = new AudioManager();
    this.music = new MusicManager(this.audio);
    this.ui = new UIManager();
    this.inventory = new InventoryManager(this.state, this);
    this.truths = new TruthEngine(this.state, this);
    this.dialogues = new DialogueManager(this.state, this);
    this.puzzles = new PuzzleManager(this.state, this);
    this.quizzes = new QuizEngine(this.state, this);
    this.scenes = new SceneManager(this);
    this.selectedHotspot = null;
    this.selectedItem = null;
    this.useMode = false;
    this._bound = false;
    this.game = null;       // Phaser.Game
    this.world = null;      // WorldScene instance
    this.worldReady = false;
    this._pendingScene = null;
    this.cadetPos = {};     // sceneId -> {x, y} where the Cadet stands
  }

  /* ---------- lifecycle ---------- */
  init() {
    if (this._bound) return;
    this._bound = true;
    $("btn-new-game").addEventListener("click", () => { this.audio.init(); this.audio.click(); this.newGame(); });
    $("btn-continue").addEventListener("click", () => { this.audio.init(); this.audio.click(); this.continueGame(); });
    $("btn-archive").addEventListener("click", () => { this.audio.init(); this.showArchive(); });
    $("btn-ending-archive").addEventListener("click", () => this.showArchive());
    $("btn-replay-act").addEventListener("click", () => this.replayAct5());
    $("btn-new-timeline").addEventListener("click", () => this.newGame());
    $("btn-sound").addEventListener("click", () => this.toggleSound());
    $("btn-music").addEventListener("click", () => this.toggleMusic());
    const vol = $("volume-slider");
    vol.value = String(Math.round(this.audio.volume * 100));
    vol.addEventListener("input", () => { this.audio.init(); this.audio.setVolume(parseInt(vol.value, 10) / 100); });
    $("btn-save").addEventListener("click", () => this.saveGame(true));
    $("btn-menu").addEventListener("click", () => { this.saveGame(false); this.music.stop(); this.ui.showScreen("title"); this.refreshContinue(); });
    document.querySelectorAll("#actionbar .btn").forEach((b) => {
      b.addEventListener("click", () => { this.audio.init(); this.audio.click(); this.doAction(b.dataset.action); });
    });
    document.addEventListener("keydown", (e) => this.onKey(e));
    document.addEventListener("click", () => this.audio.init(), { once: true });
    $("btn-debug-close").addEventListener("click", () => $("debug-panel").classList.add("hidden"));
    document.querySelectorAll("[data-dbg]").forEach((b) => {
      b.addEventListener("click", () => this.debugAction(b.dataset.dbg));
    });
    window.addEventListener("resize", () => { if (this.game) { try { this.game.scale.refresh(); } catch (e) { /* ignore */ } } });
    this.refreshContinue();
    this.updateSoundButton();
    this.ui.showScreen("title");
    logEvent("INFO", "Game initialised (v2, Phaser edition).");
  }
  refreshContinue() {
    $("btn-continue").disabled = !this.saves.hasSave();
  }
  updateSoundButton() {
    $("btn-sound").textContent = this.audio.muted ? "🔇 Sound Off" : "🔊 Sound On";
    const mb = $("btn-music");
    if (mb) mb.textContent = this.music.enabled ? "🎵 Music On" : "🎵 Music Off";
  }
  toggleSound() {
    this.audio.setMuted(!this.audio.muted);
    this.updateSoundButton();
    this.ui.toast(this.audio.muted ? "Sound muted." : "Sound on.");
  }
  toggleMusic() {
    this.music.setEnabled(!this.music.enabled);
    this.updateSoundButton();
    this.ui.toast(this.music.enabled ? "Music on." : "Music off.");
  }

  /* ---------- Phaser boot ---------- */
  ensureWorld() {
    if (this.game) { try { this.game.scale.refresh(); } catch (e) { /* ignore */ } return; }
    if (!window.Phaser) {
      logEvent("WARNING", "Phaser not available — playing in classic DOM mode.");
      this.ui.toast("Animated scenes are unavailable in this browser — playing in classic mode.");
      return;
    }
    try {
      const config = {
        type: window.__TR_HEADLESS__ ? Phaser.HEADLESS : Phaser.AUTO,
        parent: "phaser-wrap",
        width: WORLD_W, height: WORLD_H,
        backgroundColor: "#0b1226",
        scale: { mode: Phaser.Scale.FIT, autoCenter: Phaser.Scale.CENTER_BOTH },
        scene: [WorldScene],
        audio: { noAudio: true },
        banner: false
      };
      this.game = new Phaser.Game(config);
      this.world = this.game.scene.getScene("world");
    } catch (e) {
      logEvent("ERROR", "Phaser failed to start: " + e.message);
      this.game = null; this.world = null;
      this.ui.toast("Animated scenes could not start — playing in classic mode.");
    }
  }
  onWorldReady() {
    this.worldReady = true;
    logEvent("INFO", "Phaser world ready; pending scene: " + (this._pendingScene || "none"));
    if (this._pendingScene) {
      const s = this._pendingScene;
      this._pendingScene = null;
      this.world.renderScene(s);
    }
  }

  /* ---------- game flow ---------- */
  newGame() {
    this.state.reset();
    this.saves.clear();
    this.selectedHotspot = null; this.selectedItem = null; this.useMode = false;
    this.cadetPos = {};
    logEvent("INFO", "New game started.");
    const body = document.createElement("div");
    body.innerHTML = "<p>You are a <strong>Timeline Restorer</strong> — and this time you walk the eras yourself. A temporal disturbance has corrupted five eras. In each one, something from the future has appeared where it does not belong.</p><p>Click anywhere on the floor and your Time Cadet walks there. Click people to talk to them, and objects to investigate. Your <strong>Truth Check</strong> tells real history from distortion.</p><p>Your first assignment: <strong>Philadelphia, 1764</strong>. Benjamin Franklin has begun speaking of devices no one in this century could know.</p><p class='kbd-hint'>Tip: walk up to objects, then use the action bar. Truth Check anything that looks wrong. Collect everything that looks useful.</p>";
    this.ui.showScreen("game");
    this.ensureWorld();
    this.music.start(1);
    this.ui.openModal("📜 Your Assignment", body, [
      { label: "Begin Act 1 — Philadelphia, 1764", onClick: () => { this.ui.closeModal(); this.startAct(1); } }
    ]);
  }
  continueGame() {
    const data = this.saves.load();
    if (!data) { this.ui.toast("No saved game found."); return; }
    if (!this.state.fromJSON(data)) { this.ui.toast("Save data was damaged. Starting fresh is safest."); return; }
    logEvent("INFO", "Game loaded. Act " + this.state.data.currentAct + ", scene " + this.state.data.currentScene);
    this.ui.showScreen("game");
    this.ensureWorld();
    this.music.start(this.state.data.currentAct);
    this.scenes.render(this.state.data.currentScene);
    this.ui.setPanel("<p>Welcome back, Restorer. You are in <strong>" + esc(GAME_DATA.scenes[this.state.data.currentScene].name) + "</strong>, Act " + this.state.data.currentAct + ". The timeline is " + this.state.data.timelineStability + "% stable; paradox stands at " + this.state.data.paradoxLevel + "%.</p>");
    this.ui.toast("↻ Game loaded.");
  }
  startAct(n) {
    const act = GAME_DATA.acts[n];
    if (!act) { logEvent("ERROR", "Act not found: " + n); return; }
    this.state.data.currentAct = n;
    this.state.data.currentScene = act.scenes[0];
    this.ui.showScreen("game");
    this.ensureWorld();
    this.music.start(n);
    this.audio.actComplete();
    logEvent("INFO", "Act started: " + n + " — " + act.title);
    const body = document.createElement("div");
    body.innerHTML = "<h3>" + esc(act.title) + "</h3><p><em>" + esc(act.subtitle) + "</em></p><p>" + esc(act.intro) + "</p><p class='distort'>⚠ Anomaly: " + esc(act.anomaly) + "</p>";
    this.ui.openModal(act.title, body, [
      { label: "Investigate", onClick: () => { this.ui.closeModal(); this.scenes.render(act.scenes[0]); } }
    ]);
    this.refreshUI();
  }
  travel(sceneId) {
    const scene = GAME_DATA.scenes[sceneId];
    if (!scene) { logEvent("WARNING", "Travel to unknown scene: " + sceneId); return; }
    if (scene.act !== this.state.data.currentAct) {
      this.ui.setPanel("<p>That place belongs to another act. Finish this era first.</p>");
      return;
    }
    this.audio.click();
    this.scenes.render(sceneId);
  }
  saveGame(announce) {
    const ok = this.saves.save(this.state);
    if (announce) this.ui.toast(ok ? "💾 Game saved." : "Save failed — browser storage may be unavailable.");
    return ok;
  }
  refreshUI() {
    this.ui.updateMeters(this.state, this.timeline);
    this.ui.renderInventory(this.state, this.selectedItem, (id) => this.selectInventoryItem(id));
    this.updateActionStates();
    if (this.world && this.worldReady) this.world.setParadoxBand(this.timeline.band());
  }
  updateActionStates() {
    const hs = this.selectedHotspot;
    const hasNpc = !!(hs && hs.npc);
    const hasTruth = !!(hs && hs.truth);
    const canInteract = !!(hs && (hs.item || hs.puzzle || hs.npc || hs.anomaly));
    $("act-talk").disabled = !hasNpc;
    $("act-truth").disabled = !hasTruth;
    $("act-interact").disabled = !canInteract && !hs;
    $("act-look").disabled = !hs;
    $("act-use").disabled = false;
  }
  keyDigitsText() {
    const d = this.state.data.keyDigits;
    const names = { 1: "Kite", 2: "Loom", 3: "Lens", 4: "Wing" };
    return [1, 2, 3, 4].map((a) => names[a] + " " + (d[a] !== undefined ? d[a] : "?")).join(", ");
  }

  /* ---------- selection & actions ---------- */
  /* Walk the Cadet to a hotspot, then select it (Phaser mode). */
  requestHotspot(hs) {
    if (this.ui.modalOpen()) return;
    if (this.world && this.worldReady) {
      const hx = (hs.x / 100) * WORLD_W;
      const hy = clamp((hs.y / 100) * WORLD_H, FLOOR_TOP, FLOOR_BOTTOM);
      let tx = hx, ty = hy;
      if (hs.npc) {
        tx = clamp(hx + (this.world.cadet.x < hx ? -80 : 80), 40, 920);
        ty = 470;
      }
      this.world.walkTo(tx, ty, () => this.selectHotspot(hs, null));
    } else {
      this.selectHotspot(hs, null);
    }
  }
  requestExit(ex) {
    if (this.ui.modalOpen()) return;
    if (this.world && this.worldReady) {
      const scene = GAME_DATA.scenes[this.state.data.currentScene];
      const idx = scene.exits.indexOf(ex);
      const spots = [{ x: 70, y: 445 }, { x: 890, y: 445 }, { x: 800, y: 485 }];
      const spot = spots[idx >= 0 ? idx : 0];
      this.world.walkTo(spot.x, spot.y, () => this.travel(ex.to));
    } else {
      this.travel(ex.to);
    }
  }
  selectHotspot(hs, btn) {
    if (this.useMode && this.selectedItem) { this.resolveUse(this.selectedItem, hs); return; }
    this.selectedHotspot = hs;
    document.querySelectorAll(".hotspot.selected").forEach((h) => h.classList.remove("selected"));
    if (btn) btn.classList.add("selected");
    this.audio.click();
    logEvent("INFO", "Object inspected: " + hs.name);
    let hint = "<p class='kbd-hint'>";
    if (hs.npc) hint += "TALK to speak. ";
    if (hs.truth) hint += "TRUTH CHECK to verify it. ";
    if (hs.puzzle) hint += "INTERACT to attempt the puzzle. ";
    if (hs.item) hint += "INTERACT to pick it up. ";
    if (hs.anomaly) hint += "This is the anomaly — TRUTH CHECK it, then repair it with the right tool. ";
    if (hs.useTarget) hint += "Something here can be USED ON — select an item, then press USE. ";
    hint += "</p>";
    this.ui.setPanel("<p><strong>" + esc(hs.name) + "</strong></p><p>" + esc(hs.desc) + "</p>" + hint);
    this.refreshUI();
  }
  selectInventoryItem(id) {
    const def = GAME_DATA.items[id];
    if (!def) return;
    if (this.selectedItem === id) { this.selectedItem = null; this.ui.setPanel("<p>Item deselected.</p>"); this.refreshUI(); return; }
    this.selectedItem = id;
    this.audio.click();
    this.ui.setPanel("<p><strong>" + esc(def.name) + "</strong> " + def.icon + "</p><p>" + esc(def.desc) + "</p><p class='kbd-hint'>Era: " + esc(def.era) + " · Category: " + esc(def.category) + (def.combineWith && def.combineWith.length ? " · Combines with: " + def.combineWith.map((c) => GAME_DATA.items[c] ? GAME_DATA.items[c].name : c).join(", ") : "") + "</p><p>Press USE, then click a hotspot to use it on something. Or open INVENTORY to combine it.</p>");
    if (this.useMode) this.ui.setPanel(this.uiPanelUseHint());
    this.refreshUI();
  }
  uiPanelUseHint() {
    return "<p>🛠 Use mode: an item is selected. Now click a hotspot in the scene to use it on that object — or select a different item.</p>";
  }
  doAction(action) {
    const hs = this.selectedHotspot;
    if (action === "inventory") { this.showInventory(); return; }
    if (action === "timeline") { this.showTimeline(); return; }
    if (!hs && action !== "use") {
      this.ui.setPanel("<p>Select an object or person in the scene first — click one, then choose an action.</p>");
      return;
    }
    if (action === "look") this.doLook(hs);
    else if (action === "talk") this.doTalk(hs);
    else if (action === "interact") this.doInteract(hs);
    else if (action === "use") this.doUse();
    else if (action === "truth") this.doTruth(hs);
  }
  doLook(hs) {
    logEvent("INFO", "Object inspected (LOOK): " + hs.name);
    let extra = "";
    if (hs.anomaly) extra = "<p class='distort'>⚠ ANOMALY: this object does not belong in this era. It is bleeding future technology into the timeline.</p>";
    if (hs.truth) extra += "<p class='clue'>🔎 This can be verified with TRUTH CHECK.</p>";
    this.ui.setPanel("<p><strong>" + esc(hs.name) + "</strong></p><p>" + esc(hs.desc) + "</p>" + extra);
  }
  doTalk(hs) {
    if (!hs.npc) { this.ui.setPanel("<p>There is no one here to talk to.</p>"); return; }
    this.dialogues.start(this.dialogueIdFor(hs.npc));
  }
  dialogueIdFor(npcId) {
    const char = GAME_DATA.characters[npcId];
    if (char && char.dialogue) return char.dialogue;
    return npcId + "_intro";
  }
  doInteract(hs) {
    if (hs.exit) { this.travel(hs.exit); return; }
    if (hs.puzzle) { this.puzzles.open(hs.puzzle); return; }
    if (hs.requirement && hs.requirement.flag && !this.timeline.hasFlag(hs.requirement.flag)) {
      this.ui.setPanel("<p>" + esc(hs.lockedMsg || "This is locked.") + "</p>");
      this.audio.error();
      return;
    }
    if (hs.id === "final_seal") {
      this.quizzes.start("final", (passed) => { if (passed) this.actComplete(5); });
      return;
    }
    if (hs.npc) { this.dialogues.start(this.dialogueIdFor(hs.npc)); return; }
    if (hs.anomaly) { this.anomalyInfo(hs); return; }
    if (hs.item) {
      if (hs.requirement && !this.inventory.hasItem(hs.requirement.item)) {
        this.ui.setPanel("<p>" + esc(hs.lockedMsg || "You need something to open this.") + "</p>");
        this.audio.error();
        return;
      }
      const def = GAME_DATA.items[hs.item];
      if (this.inventory.addItem(hs.item)) {
        this.ui.setPanel("<p>🎒 You picked up the <strong>" + esc(def.name) + "</strong>. " + esc(def.desc) + "</p>");
        this.scenes.render(this.state.data.currentScene);
      }
      return;
    }
    if (hs.useTarget) { this.ui.setPanel("<p>" + esc(hs.desc) + "</p><p class='clue'>Try using the right tool on this. Select an item from your inventory, then press USE.</p>"); return; }
    this.ui.setPanel("<p>" + esc(hs.desc) + "</p>");
  }
  doTruth(hs) {
    if (!hs.truth) { this.ui.setPanel("<p>The Truth Check finds nothing verifiable here.</p>"); return; }
    this.truths.check(hs.truth);
  }
  doUse() {
    if (!this.selectedItem) {
      this.useMode = true;
      this.ui.setPanel("<p>🛠 Use mode: first select an item from your inventory strip below, then click a hotspot to use it on.</p>");
      this.ui.toast("Select an item, then click a hotspot.");
      return;
    }
    if (!this.selectedHotspot) {
      this.useMode = true;
      this.ui.setPanel(this.uiPanelUseHint());
      this.ui.toast("Now click a hotspot in the scene.");
      return;
    }
    this.resolveUse(this.selectedItem, this.selectedHotspot);
  }
  resolveUse(itemId, hs) {
    const item = GAME_DATA.items[itemId];
    this.useMode = false;
    if (!item) { this.ui.setPanel("<p>Unknown item.</p>"); return; }
    if (!hs.useTarget || !item.usableWith || item.usableWith.indexOf(hs.useTarget) === -1) {
      this.audio.error();
      this.ui.setPanel("<p>Using the <strong>" + esc(item.name) + "</strong> on the <strong>" + esc(hs.name) + "</strong> does nothing useful.</p><p class='kbd-hint'>The right tool matters — check TRUTH CHECK clues and puzzle hints.</p>");
      this.selectedItem = null;
      this.refreshUI();
      return;
    }
    this.repairAnomaly(hs.useTarget, item);
    this.selectedItem = null;
  }
  anomalyInfo(hs) {
    const act = this.state.data.currentAct;
    const reqs = {
      1: "Solve “What Does Not Belong?” in the workshop, then combine a magnifying glass with a historical document to reveal the hidden-ink clue, build the resonator (copper wire + lodestone + glass tube), and USE the resonator on the music player.",
      2: "Solve the loom sequence and the testimony puzzle, then craft the grounding wrench (wrench + copper wire) and USE it on the radio.",
      3: "Solve the discovery sequence and decode the cipher letter, then prepare the sealed correction (draft correction + sealing wax) and USE it on the germ chart.",
      4: "Solve the parts pick and the assembly sequence, then USE the wrench on the turbine blade.",
      5: "The Core is sealed with the four-key code (Kite, Loom, Lens, Wing) and the memory of your journey. INTERACT with the fractured Core."
    };
    this.ui.setPanel("<p><strong>" + esc(hs.name) + "</strong> — this is the timeline anomaly.</p><p>" + esc(hs.desc) + "</p><p class='clue'>🛠 To repair it: " + esc(reqs[act] || "Find the right tool and use it here.") + "</p>");
  }

  /* ---------- repair & act progression ---------- */
  repairAnomaly(targetId, item) {
    const act = this.state.data.currentAct;
    const gate = {
      1: { item: "resonator", need: ["anachronism_workshop"], clue: "hidden_ink_clue", keyDigit: 7, keyName: "Kite" },
      2: { item: "grounding_wrench", need: ["sequence_loom", "testimony"], keyDigit: 3, keyName: "Loom" },
      3: { item: "sealed_correction", need: ["sequence_discovery", "cipher_letter"], keyDigit: 1, keyName: "Lens" },
      4: { item: "wrench", need: ["parts_pick", "sequence_assembly"], keyDigit: 9, keyName: "Wing" }
    }[act];
    if (!gate) {
      this.ui.setPanel("<p>The Core cannot be repaired with a tool — it needs the four-key code. INTERACT with the fractured Core.</p>");
      return;
    }
    if (item.id !== gate.item) {
      this.audio.error();
      this.ui.setPanel("<p>The <strong>" + esc(item.name) + "</strong> is not the right tool for this anomaly.</p>");
      return;
    }
    const missing = gate.need.filter((p) => !this.puzzles.isSolved(p));
    if (missing.length) {
      const titles = missing.map((p) => GAME_DATA.puzzles[p] ? GAME_DATA.puzzles[p].title : p).join(", ");
      this.audio.error();
      this.ui.setPanel("<p>Not yet — the repair is not safe. First solve: <strong>" + esc(titles) + "</strong>.</p>");
      return;
    }
    if (gate.clue && !this.inventory.hasItem(gate.clue)) {
      this.audio.error();
      this.ui.setPanel("<p>You are missing the clue. Combine the magnifying glass with a historical document to reveal the hidden-ink clue first.</p>");
      return;
    }
    const keyId = "temporal_key_" + act;
    this.state.data.timelineFlags["a" + act + "_repaired"] = true;
    this.state.data.keyDigits[act] = gate.keyDigit;
    this.inventory.addItem(keyId);
    this.scores.add(300, "restoration");
    this.timeline.addStability(10);
    this.audio.actComplete();
    logEvent("INFO", "Anomaly repaired: act " + act + " (key digit " + gate.keyDigit + ")");
    this.scenes.render(this.state.data.currentScene);
    this.saveGame(false);
    const body = document.createElement("div");
    body.innerHTML = "<p>🎉 <strong>Anomaly repaired!</strong> The distortion folds away. Timeline Stability +10%, Paradox −5%.</p><p>You received a <strong>Temporal Key</strong> — digit <strong>" + gate.keyDigit + "</strong> (" + gate.keyName + "). Remember it: the Core at the end of time needs four digits.</p><p>Now prove what you have learned.</p>";
    this.ui.openModal("✅ Act " + act + " — Anomaly Repaired", body, [
      { label: "Take the Act Quiz", onClick: () => { this.ui.closeModal(); this.actQuiz(act); } }
    ]);
    this.refreshUI();
  }
  actQuiz(act) {
    this.quizzes.start("act" + act, (passed) => {
      if (passed) this.actComplete(act);
      else this.ui.setPanel("<p>Review the act and retry the quiz when ready — the Act Quiz button is on the Timeline panel.</p>");
    });
  }
  onPuzzleSolved(puzzleId) {
    this.timeline.setFlag("puzzle_" + puzzleId, true);
    this.saveGame(false);
    const guidance = {
      anachronism_workshop: "You identified all three distortions. Now build the resonator — combine the magnifying glass with a document first.",
      final_code: null, // handled by final flow below
      memory_recall: "The Core remembers your journey. The Chronarch is ready to speak — talk to them, then seal the Core."
    };
    if (puzzleId === "final_code") {
      this.state.data.timelineFlags.a5_core_sealed = true;
      this.scores.add(300, "restoration");
      this.timeline.addStability(10);
      this.saveGame(false);
      const body = document.createElement("div");
      body.innerHTML = "<p>🔒 <strong>THE CORE IS SEALED.</strong> The four keys turn as one: <strong>7 – 3 – 1 – 9</strong>. The fractures close. The eras stop bleeding into each other.</p><p>One last task: the final quiz — five questions from across the whole journey.</p>";
      this.ui.openModal("✅ The Temporal Core — Sealed", body, [
        { label: "Take the Final Quiz", onClick: () => { this.ui.closeModal(); this.quizzes.start("final", (passed) => { if (passed) this.actComplete(5); }); } }
      ]);
      return;
    }
    if (guidance[puzzleId]) this.ui.setPanel("<p>✅ Puzzle solved.</p><p class='clue'>" + guidance[puzzleId] + "</p>");
    else this.ui.setPanel("<p>✅ Puzzle solved. Timeline Stability improved.</p>");
    this.refreshUI();
  }
  actComplete(act) {
    this.timeline.addStability(5);
    this.audio.actComplete();
    logEvent("INFO", "Act completed: " + act);
    this.saveGame(false);
    if (act < 5) {
      const next = GAME_DATA.acts[act + 1];
      const body = document.createElement("div");
      body.innerHTML = "<p>🎉 <strong>Act " + act + " complete!</strong> The era is restored — for now.</p><p>Next: <strong>" + esc(next.title) + "</strong> — " + esc(next.subtitle) + "</p>";
      this.ui.openModal("Act " + act + " Complete", body, [
        { label: "Continue to Act " + (act + 1), onClick: () => { this.ui.closeModal(); this.startAct(act + 1); } }
      ]);
    } else {
      this.computeEnding();
    }
    this.refreshUI();
  }

  /* ---------- ending ---------- */
  computeEnding() {
    const d = this.state.data;
    d.gameCompleted = true;
    this.music.stop();
    const s = d.timelineStability;
    let ending;
    if (s >= 95) ending = { title: "🏆 PERFECT RESTORATION", text: "Every distortion undone, every era intact. The timeline hums exactly as it should. Franklin's kite, the looms, the scholars' manuscripts, the biplane — all stand in their proper centuries. You are a legend among Restorers." };
    else if (s >= 80) ending = { title: "🌟 SUCCESSFUL RESTORATION", text: "The timeline is stable and the anomalies are gone. A few small ripples remain — a word here, a sketch there — but history stands. The Chronarch nods: well done, Restorer." };
    else if (s >= 50) ending = { title: "⚠ DAMAGED TIMELINE", text: "The Core is sealed, but the timeline carries scars. Some things are subtly wrong — a date shifted, a name forgotten. History survives, but it will take other Restorers to smooth what you could not." };
    else ending = { title: "💥 CATASTROPHIC PARADOX", text: "The Core is sealed, but the paradox was too deep. Eras bleed into each other; the past is a patchwork of impossible things. The timeline endures — barely. Somewhere, a pedlar is laughing." };
    let rank;
    if (s >= 95 && d.score >= 3000) rank = "S — Master Chronologist";
    else if (s >= 80) rank = "A — Timeline Guardian";
    else if (s >= 50) rank = "B — Historical Investigator";
    else if (s >= 30) rank = "C — Temporal Apprentice";
    else rank = "D — Timeline Tourist";
    const quizLines = Object.keys(d.quizResults).map((q) => {
      const r = d.quizResults[q];
      return GAME_DATA.quizzes[q] ? GAME_DATA.quizzes[q].title + ": " + r.correct + "/" + r.total : q;
    });
    $("ending-title").textContent = ending.title;
    $("ending-body").innerHTML =
      "<p>" + ending.text + "</p>" +
      "<h3>Your Record</h3>" +
      "<table class='score-table'><tbody>" +
      "<tr><td>Final Score</td><td>" + d.score + "</td></tr>" +
      "<tr><td>Timeline Stability</td><td>" + d.timelineStability + "%</td></tr>" +
      "<tr><td>Paradox Level</td><td>" + d.paradoxLevel + "%</td></tr>" +
      "<tr><td>Rank</td><td><strong>" + rank + "</strong></td></tr>" +
      "<tr><td>Historical Knowledge</td><td>" + d.categories.knowledge + "</td></tr>" +
      "<tr><td>Puzzle Solving</td><td>" + d.categories.puzzles + "</td></tr>" +
      "<tr><td>Truth Discoveries</td><td>" + d.categories.truths + " (" + d.discoveredTruths.length + " truths)</td></tr>" +
      "<tr><td>Artifacts Collected</td><td>" + d.categories.artifacts + " (" + d.inventory.length + " items)</td></tr>" +
      "<tr><td>Timeline Restoration</td><td>" + d.categories.restoration + "</td></tr>" +
      "<tr><td>Exploration</td><td>" + d.categories.exploration + " (" + d.visitedScenes.length + " scenes)</td></tr>" +
      "<tr><td>Puzzles Solved</td><td>" + d.solvedPuzzles.length + "</td></tr>" +
      "</tbody></table>" +
      (quizLines.length ? "<h3>Quiz Results</h3><p>" + quizLines.map(esc).join("<br>") + "</p>" : "") +
      "<p class='fact'>Key digits recovered: " + esc(this.keyDigitsText()) + " — the code of the Core, 7-3-1-9.</p>" +
      "<p>Your Historical Archive persists — open it from the title screen or the ending screen.</p>";
    this.saveGame(false);
    this.ui.showScreen("ending");
    logEvent("INFO", "Game completed. Ending: " + ending.title + " rank " + rank);
  }
  replayAct5() {
    const d = this.state.data;
    d.gameCompleted = false;
    d.solvedPuzzles = d.solvedPuzzles.filter((p) => p !== "final_code" && p !== "memory_recall");
    delete d.quizResults.final;
    delete d.quizResults.act5;
    Object.keys(d.timelineFlags).forEach((k) => { if (k.indexOf("a5_") === 0 || k.indexOf("puzzle_final_code") === 0 || k.indexOf("puzzle_memory_recall") === 0) delete d.timelineFlags[k]; });
    this.startAct(5);
  }

  /* ---------- panels ---------- */
  showArchive() {
    const archived = this.saves.archiveGet();
    const body = document.createElement("div");
    if (!archived.length) {
      body.innerHTML = "<p>Your Historical Archive is empty. Discover truths with TRUTH CHECK — every verified fact is kept here across replays.</p>";
    } else {
      const list = archived.map((id) => {
        const t = GAME_DATA.truths[id];
        if (!t) return "";
        return "<p><strong>" + esc(t.object) + "</strong> — " + (t.status === "anachronistic" ? "⚠ Anachronistic" : "✓ Authentic") + "<br><span class='fact'>" + esc(t.fact) + "</span></p>";
      }).join("");
      body.innerHTML = "<p>" + archived.length + " verified fact" + (archived.length > 1 ? "s" : "") + " discovered across all timelines.</p>" + list;
    }
    this.ui.openModal("📚 Historical Archive", body, [{ label: "Close", onClick: () => this.ui.closeModal() }]);
  }
  showTimeline() {
    const d = this.state.data;
    const act = GAME_DATA.acts[d.currentAct];
    const PUZZLE_ACTS = { anachronism_workshop: 1, sequence_franklin: 1, sequence_loom: 2, testimony: 2, cipher_letter: 3, sequence_discovery: 3, parts_pick: 4, sequence_assembly: 4, memory_recall: 5, final_code: 5 };
    const actPuzzles = Object.keys(GAME_DATA.puzzles).filter((p) => PUZZLE_ACTS[p] === d.currentAct);
    const solved = actPuzzles.filter((p) => this.puzzles.isSolved(p));
    const body = document.createElement("div");
    body.innerHTML =
      "<h3>" + esc(act.title) + "</h3>" +
      "<p>Timeline Stability: <strong>" + d.timelineStability + "%</strong> · Paradox: <strong>" + d.paradoxLevel + "%</strong> (" + esc(this.timeline.bandLabel()) + ")</p>" +
      "<p>Score: <strong>" + d.score + "</strong> · Key digits: " + esc(this.keyDigitsText()) + "</p>" +
      "<p>Truths discovered: " + d.discoveredTruths.length + " · Puzzles solved in this act: " + solved.length + " / " + actPuzzles.length + "</p>" +
      "<p>Anomaly: " + (d.timelineFlags["a" + d.currentAct + "_repaired"] ? "✅ Repaired" : "⚠ Still active — " + esc(act.anomaly)) + "</p>" +
      (actPuzzles.length ? "<p>Puzzles this act: " + actPuzzles.map((p) => (this.puzzles.isSolved(p) ? "✅ " : "☐ ") + esc(GAME_DATA.puzzles[p].title)).join("<br>") + "</p>" : "") +
      "<p class='kbd-hint'>Press ESC to close.</p>";
    this.ui.openModal("⏳ Timeline Status", body, [
      { label: "Take the Act Quiz", onClick: () => { this.ui.closeModal(); this.actQuiz(d.currentAct); } },
      { label: "Close", secondary: true, onClick: () => this.ui.closeModal() }
    ]);
  }
  showInventory() {
    const items = this.inventory.list();
    const body = document.createElement("div");
    if (!items.length) {
      body.innerHTML = "<p>Your inventory is empty. Click objects in the scene to collect useful items.</p>";
    } else {
      body.appendChild(makeEl("p", null, "Click an item to inspect it. To combine: click a first item, then a second item — if they fit together, you will make something new."));
      items.forEach((item) => {
        const b = makeEl("button", "choice-btn", item.icon + " " + item.name + " — " + item.desc);
        b.addEventListener("click", () => this.selectInventoryItem(item.id));
        body.appendChild(b);
      });
    }
    const actions = [];
    if (this.selectedItem) {
      actions.push({ label: "Combine selected item…", onClick: () => this.combinePrompt(this.selectedItem) });
      actions.push({ label: "Use selected item", onClick: () => { this.ui.closeModal(); this.doUse(); } });
    }
    actions.push({ label: "Close", secondary: true, onClick: () => this.ui.closeModal() });
    this.ui.openModal("🎒 Inventory", body, actions);
  }
  combinePrompt(firstId) {
    const first = GAME_DATA.items[firstId];
    const body = document.createElement("div");
    body.appendChild(makeEl("p", null, "Combine “" + first.name + "” with:"));
    const others = this.inventory.list().filter((i) => i.id !== firstId);
    if (!others.length) body.appendChild(makeEl("p", null, "No other items to combine with yet."));
    others.forEach((item) => {
      const b = makeEl("button", "choice-btn", item.icon + " " + item.name);
      b.addEventListener("click", () => {
        this.ui.closeModal();
        const result = this.inventory.combine(firstId, item.id);
        if (result) this.scenes.render(this.state.data.currentScene);
        else this.showInventory();
      });
      body.appendChild(b);
    });
    this.ui.openModal("🔧 Combine Items", body, [{ label: "Cancel", secondary: true, onClick: () => this.ui.closeModal() }]);
  }

  /* ---------- debug ---------- */
  debugRefresh() {
    const d = this.state.data;
    $("debug-state").innerHTML =
      "Act: " + d.currentAct + " · Scene: " + esc(d.currentScene) + "<br>" +
      "Score: " + d.score + " · Stability: " + d.timelineStability + "% · Paradox: " + d.paradoxLevel + "%<br>" +
      "Inventory: " + (d.inventory.join(", ") || "(empty)") + "<br>" +
      "Solved: " + (d.solvedPuzzles.join(", ") || "(none)") + "<br>" +
      "Truths: " + d.discoveredTruths.length + " · Flags: " + JSON.stringify(d.timelineFlags) + "<br>" +
      "Key digits: " + esc(this.keyDigitsText()) + "<br>" +
      "Phaser: " + (this.game ? (this.worldReady ? "ready" : "booting…") : "unavailable (classic mode)");
  }
  debugAction(kind) {
    const d = this.state.data;
    if (kind === "score") this.scores.add(10, "knowledge");
    else if (kind === "paradox-plus" || kind === "paradox+") this.timeline.addParadox(10);
    else if (kind === "paradox-minus" || kind === "paradox-") this.timeline.addParadox(-10);
    else if (kind === "add-item" || kind === "item") {
      const id = prompt("Item id to add (e.g. magnifier, copper_wire, resonator):");
      if (id) this.inventory.addItem(id.trim());
    }
    else if (kind === "complete-puzzle" || kind === "puzzle") {
      const id = prompt("Puzzle id to mark solved (e.g. anachronism_workshop):");
      if (id && GAME_DATA.puzzles[id.trim()]) { this.puzzles.solve(GAME_DATA.puzzles[id.trim()]); }
      else if (id) this.ui.toast("Unknown puzzle id.");
    }
    else if (kind === "set-flag" || kind === "flag") {
      const kv = prompt("Flag name=value (e.g. a1_repaired=true):");
      if (kv) { const parts = kv.split("="); this.timeline.setFlag(parts[0].trim(), parts[1] ? parts[1].trim() === "true" : true); }
    }
    else if (kind === "next-act" || kind === "nextact") {
      const next = Math.min(5, d.currentAct + 1);
      this.startAct(next);
    }
    else if (kind === "reset-act" || kind === "resetact") {
      this.startAct(d.currentAct);
    }
    this.debugRefresh();
    this.refreshUI();
  }
  onKey(e) {
    if (e.ctrlKey && e.shiftKey && (e.key === "D" || e.key === "d")) {
      e.preventDefault();
      const panel = $("debug-panel");
      panel.classList.toggle("hidden");
      if (!panel.classList.contains("hidden")) this.debugRefresh();
      return;
    }
    if (e.key === "Escape") {
      if (this.ui.modalOpen()) { this.ui.closeModal(); this.dialogues.end(); }
      else $("debug-panel").classList.add("hidden");
      return;
    }
    if (this.dialogues.current && ["1", "2", "3", "4"].indexOf(e.key) !== -1) {
      const idx = parseInt(e.key, 10) - 1;
      if (idx < (this.dialogues._choiceCount || 0)) this.dialogues.choose(idx);
      return;
    }
    // Enter: walk to and select the nearest hotspot (game screen, no modal)
    if (e.key === "Enter" && !this.ui.modalOpen() && !$("screen-game").classList.contains("hidden")) {
      if (this.world && this.worldReady) {
        const hs = this.world.nearestHotspot();
        if (hs) this.requestHotspot(hs);
      }
    }
  }
}

/* ---------------- boot ---------------- */
const engine = new GameEngine();
if (typeof window !== "undefined") window.__TR_ENGINE__ = engine;
document.addEventListener("DOMContentLoaded", () => engine.init());
if (document.readyState !== "loading") engine.init();
