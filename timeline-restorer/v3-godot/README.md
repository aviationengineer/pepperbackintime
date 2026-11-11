# Timeline Restorer: Back in Time — Godot v3 (full game)

The **complete** game rebuilt in Godot 4 — all 5 acts, all 18 scenes, every system
from the v1 HTML game, ported faithfully. All content is original; no characters,
art, dialogue or assets were copied from any existing game. History is broadly
accurate and labelled FACT vs ALTERNATE TIMELINE in the Truth Check panels.

## Godot version

**Godot 4.7.2-stable** (`4.7.2.stable.official.ed1daf0bf`), Linux editor, GDScript
only. Renderer: **Compatibility** (`gl_compatibility`). Web export:
**single-threaded** (`thread_support=false` in `export_presets.cfg`) — runs on
plain static hosting with no special server headers. Viewport 1280×720.

## What v3 contains

- **All 5 acts, 18 scenes** — Act 1 Philadelphia 1764 (workshop, printshop,
  marketplace, library, street, meeting), Act 2 Manchester 1830s (mill,
  warehouse, cottage), Act 3 Europe 1690s (observatory, apothecary,
  university), Act 4 airfield 1912 (airfield, hangar, office), Act 5 Temporal
  Core (gallery, core, dais). Every scene from v1 exists and is reachable
  (walk exits + Travel menu).
- **One hand-painted storybook background per scene** (960×540, warm saturated
  palette, foreground framing) — every background has a clear, empty,
  walkable floor in the bottom quarter, and the NavigationRegion2D sits on
  that floor. Characters walk on the floor, never on furniture (the PoC's
  "characters stand on the workbench" flaw is fixed by construction).
- **Character sprites for the Time Cadet + all 16 NPCs** (450×900, transparent
  backgrounds, hand-painted storybook style) with procedural animation — idle
  bob, squash-and-stretch walk, flip-to-face, talk bounce. Single-sprite +
  procedural animation is the deliberate choice (generated multi-frame cycles
  looked inconsistent).
- **All systems from v1:** NavigationAgent2D click-to-walk in every scene
  (walk-to-hotspot-first); branching dialogue with effects
  (paradox/score/flags); Truth Check panels (Authentic vs Anachronistic, fact,
  confidence, era, paradox contribution); inventory (pick up / inspect / use /
  combine / give); all **10 puzzles** (anachronism-spot, milestone sequence,
  loom sequence, testimony, cipher, discovery chain, parts pick, assembly,
  memory recall, final code **7319**); **6 quizzes** (5 questions each, same
  scoring: 5/5=+500, 4/5=+350, 3/5=+200, 2/5=+100, 0–1=retry); **4 endings**
  by stability (Perfect / Successful / Damaged / Catastrophic) and ranks S–D;
  **Historical Archive** persisting across replays; **save/load** via
  `user://` (autosaves on pickup/combine/truth/puzzle/repair/quiz/act
  complete/dialogue end); **debug overlay** (F1 or Menu — act/scene/paradox/
  flags/inventory/puzzles/truths/score, event log, jump-to-act buttons);
  **event log** (also printed to console); **paradox bands** (stable / minor /
  unstable / severe / critical) + ripple effects (Act 1 choices remembered in
  later acts); kid-friendly UX (praise, hints, stars, confetti on quiz
  success, forgiving retries).
- **Paradox HUD updates immediately when a Truth is found** (the PoC flaw is
  fixed — the meter moves the moment the Truth panel opens).
- **Procedural audio, no audio files:** per-act music motif (C / D-minor / G /
  A-minor / E-minor roots), ambient, and SFX (click, footsteps, truth, pickup,
  puzzle solved, fanfare, repair, error). Mute (M) + volume cycle in the HUD.
- **Act title cards** for all 5 acts, with ripple notes (timeline events whose
  flag is set).
- **Autodemo** (`?autodemo=full` in the web export, `--autodemo` on the
  command line; `?autodemo=act1` / `--autodemo=act1` for Act 1 only): a
  scripted playthrough that drives the real UI handlers end to end and
  reports `AUTODEMO_DONE score=… stability=… paradox=… rank=…` in the console
  (and `document.title` on web). Verification tooling, not part of the game.

## Data

`data/game_data.json` (116 KB) — the v1 game data converted verbatim from
`../v2/game-data.js` by `scripts/extract_game_data.py`: 5 acts, 18 scenes,
16 characters, 36 items, 6 combine recipes, 36 truths, 10 puzzles,
16 dialogues, 6 quizzes, 7 timeline events, plus the 5 per-act repair
requirements extracted from the v1 engine code. The Godot game loads this file
at runtime and is fully data-driven from it. Scoring rules match v1 exactly
(Truth +50, puzzle +150/+300, item +20, combine +50, first scene visit +10,
repair +300, quiz 5/5=+500 … 2/5=+100, retry below 2; paradox/stability
coupling uses v1's `Math.round` semantics).

## How to open the project in the editor

1. Install Godot **4.7.2-stable** (or newer 4.x) and the matching export
   templates if you want to re-export.
2. Open Godot → Import → select `project.godot` in this folder (or run
   `godot --path .` from the command line).
3. Press F5 (or the Play button) to run. Click anywhere to walk; click a
   glowing object to investigate it. F1 debug panel, M mute, Esc close a panel.

## How to run the web export locally

The ready-to-run export is in `web-export/` (also zipped as
`timeline-restorer-godot-v3-web.zip`, 37 MB zipped / 65 MB unpacked):

```sh
cd web-export
python3 -m http.server 8901
```

Then open <http://localhost:8901/index.html> in a browser. Any plain static
server works (no special headers needed — the export is single-threaded).
First load takes a few seconds while the 39 MB WebAssembly engine compiles.
It also runs from GitHub Pages as-is (single-threaded, WebGL2 only).

## Screenshots (taken from the running game under Xvfb, 1280×720)

| File | What it shows |
|---|---|
| `00-title.png` | Title screen: TIMELINE RESTORER, New Game / Continue / Archive / How to Play |
| `act-title-1.png` | Act 1 title card — Philadelphia, 1764 |
| `act1-workshop.png` | Act 1 — Franklin's workshop, Cadet + Franklin, painted floor |
| `act2-mill.png` | Act 2 — the Manchester mill, Josiah Grimshaw |
| `act3-observatory.png` | Act 3 — the observatory, Master Corvin |
| `act4-hangar.png` | Act 4 — the 1912 hangar, Gus Berger |
| `act5-core.png` | Act 5 — the Temporal Core, the Chronarch |
| `dialogue-franklin.png` | Branching dialogue with Franklin (choices + effects) |
| `truth-music_player.png` | Truth Check: ANACHRONISTIC, fact, eras, confidence, paradox |
| `quiz-act1.png` | Act 1 quiz, one question at a time with immediate feedback |
| `repair-act1.png` | Repair moment — Temporal Key, Kite Digit 7 |
| `ending.png` | Ending screen — PERFECT RESTORATION, rank S, final stats |

(All screenshots live in `screenshots/`; the full per-scene set from the
verification run is in the same folder.)

## Verification performed

- `godot --headless --import` — clean, no errors.
- **Full playthrough, headless Godot, autodemo driving the real UI
  handlers:** `AUTODEMO_DONE score=7205 stability=100 paradox=0 rank=S`
  — all 4 repairs (key digits 7, 3, 1, 9 → code 7319), all 10 puzzles, all 6
  combines, all 6 quizzes 5/5, final quiz 5/5, ending **PERFECT RESTORATION**,
  rank **S — Master Chronologist**. Zero script errors, zero `[ERROR]` lines.
  Act 1 alone: `AUTODEMO_ACT1_DONE score=1640 stability=100 paradox=0
  rank=A` (both puzzles, all 3 combines, repair, quiz 5/5 → Act 2 opens).
- **Real mouse click test** (`--clicktest`, under Xvfb): a genuine injected
  mouse click on the magnifying-glass hotspot is picked up by the physics
  point query and starts the Cadet walking to it — **CLICKTEST PASS**.
- **Save/load round-trip** (`--autocontinue`, in the running game): the
  autosave written by the playthrough loads back with the full state
  (act/scene/score/stability/paradox/inventory/flags/truths/puzzles) —
  **AUTOCONTINUE** verified.
- **Screenshots:** every screenshot above was looked at. Characters stand on
  the floor in every scene; panels are centred and readable; no placeholder
  art. (One layout bug was caught and fixed by this pass: centred panels were
  built with `set_anchors_preset(PRESET_CENTER)` before their size was set,
  so their top-left sat at the screen centre and they were clipped — all five
  are now wrapped in a `CenterContainer`.)
- Web export completed (single-threaded, Compatibility renderer). Export
  size: **65 MB** total — `index.wasm` 39.5 MB, `index.pck` 28 MB,
  `index.js` 280 KB.
- v1 and v2 untouched: `v1/timeline-restorer.html` SHA256 is still
  `d03c22ef0260681922932bcbcb52f455a869fdab534dddbfefbbac6d83b90410`;
  `v2/timeline-restorer.html` SHA256 is still
  `1bd4a150e3a3eee26eace2f8bb427a209a671833aa9e054eeedd64c068725c38`.
- Nothing was pushed to GitHub; the zip is the delivery vehicle (the `.wasm` /
  `.pck` are binaries and cannot be pushed via the text-only GitHub push tool).

### Caveats (honest)

- **Web-export browser run not re-verified in this session:** the sandbox's
  Chromium build now refuses to start without a Hatch WebGL domain policy
  ("Hatch WebGL domain policy is required for browser startup") and the
  policy document is a signed contract issued by the Hatch daemon — it cannot
  be forged from this VM, so the v3 export could not be driven in headless
  Chromium here. The export pipeline is identical to the PoC's (which *was*
  verified end-to-end in headless Chromium via CDP), the export is 65 MB and
  structurally complete (`index.html` + `index.js` + `index.wasm` +
  `index.pck`), and the *game itself* was verified end-to-end in the Godot
  runtime (autodemo + real click test + save/load + screenshots under Xvfb).
  Please do one real-browser smoke test on first open (New Game → walk →
  talk to Franklin) before sharing the link.
- **Audio heard only in a real browser:** the procedural audio code runs with
  no errors, but sound itself could not be heard in headless/Xvfb runs (no
  audio device in the VM; in a browser the AudioContext is suspended until a
  user gesture, which is standard behaviour). The mute/volume controls work.
  Verify sound by ear in a real browser.
- **Mobile touch:** not tested — the game is mouse-driven; touch input is not
  wired up.
- **Walk speed under Xvfb:** software rendering (llvmpipe) runs at low FPS,
  so the Cadet walks slowly in the Xvfb screenshots. On real hardware with
  GPU rendering he walks at the intended 190 px/s (3× in autodemo).
- **Truth coverage in the autodemo:** the scripted playthrough Truth-checks
  the 4 anomaly devices (music player, radio, germ chart, turbine blade).
  The other 32 truths are discoverable in normal play (Truth Check any
  hotspot); they were not all exercised by the autodemo.
- **Single-frame character animation:** the characters are single sprites
  with procedural bob / squash / flip rather than multi-frame walk cycles —
  generated multi-frame cycles looked inconsistent, so this was the
  deliberate choice.
- Art is AI-generated raster illustration (original, made for this project),
  not hand-drawn pixel art. Raw generations are kept in `art/raw/` (excluded
  from the export); processed backgrounds/NPCs are in `art/`.

## Files

- `project.godot`, `main.tscn`, `export_presets.cfg`, `icon.svg` — project.
- `scripts/` — `main.gd` (~2,700 lines: scenes, input, HUD, dialogue/truth/
  action/modal UI, puzzles, quizzes, endings, archive, save/load, debug,
  autodemo, screenshot/clicktest/autocontinue verification hooks),
  `cadet.gd`, `npc.gd`, `audio_manager.gd` (procedural sound),
  `extract_game_data.py` (v1 JS → JSON converter),
  `process_art.py` (background crop + NPC background removal).
- `data/game_data.json` — the full v1 game data.
- `art/` — 18 `bg-<scene>.png` backgrounds + `cadet.png`, `npc-*.png`
  (16 NPCs incl. Franklin + Chronarch), `leaves.png`; `art/raw/` holds the
  original generations.
- `web-export/` — the built web export; `timeline-restorer-godot-v3-web.zip`
  — the same export, zipped.
- `screenshots/` — verification screenshots from the running game.
- `cdp-*.mjs` — the PoC's CDP drivers (headless-Chromium verification
  tooling, not part of the game; not re-runnable in this sandbox — see the
  caveat above).
