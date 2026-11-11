# Timeline Restorer v2 — Phaser Edition

A single-file HTML5 time-travel adventure game: **Timeline Restorer: Back in Time**.
Version 2 rebuilds the verified v1 game on **Phaser 3.80.1**, adding animated
character actors, click-to-walk navigation, richer layered scenes, procedural
sound and music, and kid-friendly UX — while keeping every puzzle, truth,
quiz, dialogue and ending from v1 intact.

## Files in this folder

| File | What it is |
| --- | --- |
| `timeline-restorer.html` | **The deliverable** — one self-contained file (2,755 lines, ~1.35 MB). Open it in a browser or embed it in the Streamlit wrapper unchanged. |
| `phaser.min.js` | Phaser 3.80.1 (minified, 1,181,917 bytes), downloaded from the jsDelivr CDN and inlined by the build script. |
| `game-data.js` | `GAME_DATA` extracted verbatim from v1 (5 acts, 18 scenes, 16 characters, 36 items, 6 recipes, 36 truths, 10 puzzles, 6 quizzes, 16 dialogues, 7 timeline events). |
| `game.js` | The engine (2,394 lines): GameState, TimelineManager, InventoryManager, DialogueManager, PuzzleManager, TruthEngine, QuizEngine, ScoreManager, SaveManager, AudioManager, MusicManager, CharacterFactory, ScenePainter, WorldScene, SceneManager, GameEngine. |
| `shell.html` | The HTML shell (title screen, topbar, scene area, action bar, modals) that `build.py` wraps around the scripts. |
| `build.py` | Assembles `shell.html` + `phaser.min.js` + `game-data.js` + `game.js` into `timeline-restorer.html`. Sanitises Phaser's 4 inert URL literals so the final file contains zero `http://` / `https://` substrings. Re-run it after any edit: `python3 build.py`. |
| `extract_data.py` | Pulls `GAME_DATA` out of the v1 file and writes `game-data.js` (canonical JSON re-emitted as a JS literal). |

## How to run

- **Double-click** `timeline-restorer.html`, or open it from any static host.
  No server, no internet, no install needed — the file has zero external
  references.
- **Streamlit:** the existing wrapper embeds the file with
  `st.components.v1.html`; replacing the v1 file with this one is enough.
- **Controls:** click the floor to walk; click a glowing object or person to
  walk over and investigate it; click doors/paths to change scene. Keyboard:
  arrows/WASD to walk, Enter to interact with the nearest hotspot, Escape to
  close a panel. Ctrl+Shift+D opens the debug console.

## What changed vs v1

- **Animated character actors.** A young Time Cadet plus 16 NPCs (Franklin,
  his apprentice, the printer, the librarian, the market vendor, mill workers,
  scholars, pilots, the Chronarch, …) drawn as clean vector-style art. Each
  character has 4 frames (idle, walk1, walk2, talk) — 68 textures in total —
  drawn with the plain canvas 2D API and registered with Phaser via
  `textures.addCanvas` (renderer-independent, so it also works in Phaser's
  headless mode). Idle bob, walk-cycle leg/arm swing, talk bounce with a 💬
  bubble; NPCs turn to face the Cadet when talked to.
- **Click-to-navigate.** The Cadet tweens to any floor point (240 px/s, with
  walk animation and footstep sounds); clicking a hotspot/NPC walks there
  first, then the interaction opens; exits are doors the Cadet walks through.
- **Richer background scenes.** One layered vector painter per backdrop
  (18 backdrops: workshop, printing shop, marketplace, library, street,
  meeting room, mill, cottage, warehouse, observatory, apothecary,
  university, airfield, hangar, office, Temporal Core, gallery, dais), with
  dust motes indoors, drifting clouds outdoors, cyan shimmer in the Core, and
  paradox effects that scale with the paradox level (screen tint, camera
  shake, glitch particles at high paradox).
- **Sound and music.** Procedural Web Audio only — no audio files. A
  MusicManager plays a gentle generative melody per act (different mood per
  era) plus ambient beds (marketplace murmur, mill clatter, birdsong, wind,
  night, shimmer), and SFX for clicks, footsteps, truth-check chimes,
  pickups, puzzle fanfares and act completion. Mute button + volume slider;
  audio starts on the first user gesture. (Phaser itself runs with
  `audio: { noAudio: true }`; all sound is Web Audio through AudioManager.)
- **Kid-friendly UX.** Bigger buttons, encouraging feedback ("Great detective
  work!"), a HINT button on puzzles, stars and confetti on quiz success,
  forgiving retries with a hint and no harsh penalty. Facts stay accurate and
  labelled FACT vs ALTERNATE TIMELINE.
- **Same systems as v1.** Truth Check panels, inventory (pick up / inspect /
  use / combine / give), the 7-action palette, branching dialogue with
  effects, all 10 puzzles, per-act 5-question quizzes with the same scoring,
  4 endings by stability, ranks S–D, Historical Archive, event log, paradox
  bands and ripple effects (Act 1 choices remembered in later acts). Saves
  use a **new** localStorage key `timeline-restorer-save-v2` (archive
  `timeline-restorer-archive-v2`), so v1 saves are untouched.
- **Bug fixed from v1:** v1's debug buttons used `data-dbg="paradox+"` /
  `"paradox-"` / `"item"` / `"puzzle"` / `"flag"` / `"nextact"` /
  `"resetact"`, but the engine only matched `"paradox-plus"` /
  `"paradox-minus"` / `"add-item"` / `"complete-puzzle"` / `"set-flag"` /
  `"next-act"` / `"reset-act"` (only "score" worked). v2 accepts both naming
  styles.
- **DOM fallback.** If Phaser cannot load or boot, the game still plays in
  classic v1-style DOM mode: hotspot buttons over the scene, same panels and
  logic. `WorldScene` is defined only when `Phaser` exists, so a missing
  Phaser library cannot break the rest of the engine.

## Architecture

```
GAME_DATA (content, ported verbatim from v1)
   └── GameEngine — flow: newGame / continueGame / startAct / travel /
       repairAnomaly / actQuiz / actComplete / computeEnding / panels
         ├── SceneManager — renders via Phaser world when ready, else DOM
         ├── WorldScene (Phaser.Scene "world") — canvas, actors, navigation
         │     ├── ScenePainter — one painter per backdrop key
         │     └── CharacterFactory — canvas-drawn actor textures
         ├── UIManager / InventoryManager / TruthEngine / DialogueManager /
         │   PuzzleManager / QuizEngine / ScoreManager / TimelineManager
         ├── SaveManager (localStorage, v2 keys)
         └── AudioManager + MusicManager (Web Audio, generative)
DOM overlays (dialogue, Truth Check, quiz, inventory, puzzle modals)
sit on top of the Phaser canvas and reuse v1's panel patterns.
```

The Phaser canvas is the scene + characters + navigation; the DOM is the UI
chrome. Layout is responsive (desktop/tablet/mobile). Accessibility: keyboard
nav, ARIA labels, focus states, `prefers-reduced-motion` respected (paradox
shake and bobbing are skipped).

## Verification (all done headlessly in jsdom, 2026-11-11)

- `node --check` passes on `game.js`, `game-data.js` and `phaser.min.js`
  (checked separately).
- Final file greps: **0** TODO / FIXME / lorem; **0** `http://`; **0**
  `https://`; Phaser `3.80.1` present; v2 save key present. The 19 `src=` /
  `href=` strings in the file are all JavaScript property assignments inside
  Phaser's loader internals (`this.src=…`, `r.href=…`) — no HTML resource
  tags, no external URLs.
- **Full playthrough harness — 85/85 checks passed, 0 page errors.**
  Headless Phaser (jsdom + canvas/Image stubs) played Act 1 end to end —
  walk, talk, Truth Check, collect, all 3 combines, both Act 1 puzzles,
  anomaly repair (key digit 7), quiz 5/5, reached Act 2 — then Acts 2–4
  repairs and quizzes through the same UI code paths, and the Act 5 finale
  (memory_recall, final code 7319, final quiz 5/5) → **Perfect Restoration**
  ending, score recorded, stability high, archive populated. Save/load
  round-trip verified; the v1 save key was never written. All 17 characters
  × 4 texture frames generated; all 18 scene backdrops paint without errors.
- **DOM fallback harness — 17/17 checks passed, 0 page errors.** With the
  Phaser script removed, the game boots in classic mode, renders fallback
  hotspot buttons, collects an item via the action bar, and travels between
  scenes.

### Harness notes (jsdom quirks, not game bugs)

- jsdom's `Image` never fires `load`, so Phaser's Texture Manager never
  emits READY and the game loop never starts. The harness stubs `window.Image`
  to fire `load` asynchronously; in a real browser this is unnecessary.
- `Graphics.generateTexture` needs a live renderer (`scene.sys.renderer` is
  null in headless mode), so characters are drawn with the raw canvas 2D API
  and registered via `textures.addCanvas` instead.
- `engine.world` is assigned in `WorldScene.create()` (the scene registers
  itself) because `game.scene.getScene("world")` can return null before boot.
- `requestHotspot` correctly refuses to walk while any modal is open.

## What is playable per act

- **Act 1 — Philadelphia, 1764:** fully playable end to end (see harness
  above). Puzzles: anachronism_workshop, sequence_franklin. Repair needs the
  resonator (copper wire + lodestone → resonator coil + glass tube), the
  anachronism puzzle solved, and the hidden-ink clue. Key digit **7**.
- **Act 2 — Manchester, 1830s:** repair verified via the same UI paths
  (grounding_wrench combine, sequence_loom + testimony puzzles, quiz 5/5).
  Key digit **3**.
- **Act 3 — Europe, 1690s:** repair verified (draft_correction +
  sealing_wax → sealed_correction; sequence_discovery + cipher_letter
  puzzles; quiz 5/5). Key digit **1**.
- **Act 4 — Airfield, 1912:** repair verified (parts_pick +
  sequence_assembly puzzles; quiz 5/5). Key digit **9**.
- **Act 5 — Temporal Core:** finale verified (memory_recall, final code
  **7319**, final quiz 5/5, core sealed → Perfect Restoration).

## Not verified in this build

- **Real-browser visual check.** The harness runs headless with a stubbed
  2D canvas context, so it proves the logic, textures and painters run
  without errors — not what the scenes actually look like. Open the file in a
  real browser and play Act 1 before promoting it; check character art,
  backdrop readability, music start on first click, and the paradox tint.
- **Mobile touch layout** (only desktop-size headless checks were run).
- **Save/load across browser sessions** (round-trip verified within one
  headless session only).

## v1 preservation

The v1 folder and the live v1 file were not touched. SHA-256 verified
unchanged after the v2 build:

```
d03c22ef0260681922932bcbcb52f455a869fdab534dddbfefbbac6d83b90410
  ~/workspace/timeline-restorer/v1/timeline-restorer.html
  ~/workspace/timeline-restorer/timeline-restorer.html
```
