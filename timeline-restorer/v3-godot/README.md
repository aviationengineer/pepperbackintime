# Timeline Restorer: Back in Time — Godot Proof of Concept (v3)

One playable scene — **Franklin's workshop, Act 1, Philadelphia 1764** — rebuilt in
Godot 4 to show the visual and gameplay difference Godot makes versus the Phaser v2.
All content is original and ported faithfully from the v1 Act 1 workshop slice
(scene, Franklin dialogue, truths, items). No characters, art, dialogue or assets
were copied from any existing game.

## Godot version

**Godot 4.7.2-stable** (`4.7.2.stable.official.ed1daf0bf`), Linux editor, GDScript only.
Renderer: **Compatibility** (`gl_compatibility`). Web export: **single-threaded**
(`thread_support=false` in `export_presets.cfg`) — runs on plain static hosting
with no special server headers. Viewport 1280×720.

## What the PoC shows

- A hand-painted-style workshop: window with daylight, patterned wallpaper,
  shelves of books and jars, workbench with Leyden jar, quills, copper wire and a
  candle, plus foreground leaves framing the top corners for depth.
- Two illustrated characters (single sprites with procedural animation — idle bob,
  squash-and-stretch walk, flip-to-face, Franklin's talk bounce): the Time Cadet
  (curly hair, teal explorer jacket, hourglass pendant) and Benjamin Franklin
  (bald, spectacles, blue coat, brass key).
- Click-to-walk with **real pathfinding** (`NavigationAgent2D` +
  `NavigationRegion2D`): the Cadet walks around the workbench and stool, never
  through them. Footstep sounds.
- Dialogue: click Franklin, the Cadet walks to him, Franklin turns to face him,
  and a styled panel opens with his original lines and 3 player choices — one
  choice (telling him about the future) raises paradox, as in v1.
- Truth Check: the humming future device can be Truth Checked — the panel shows
  **ANACHRONISTIC**, the historical fact, expected vs current era, confidence
  (99%) and paradox contribution (+12). Score +50 on discovery.
- Inventory: the magnifying glass can be picked up and appears in the inventory
  strip ("Picked up: Magnifying Glass").
- Light and atmosphere: flickering candle `PointLight2D` over the workbench, cool
  window light, drifting dust motes (`CPUParticles2D`), and a paradox tint over
  the scene.
- Act title card ("ACT 1 — PHILADELPHIA, 1764") on scene start.
- Procedural audio via `AudioStreamGenerator` (no audio files): a gentle
  pentatonic motif, click / footstep / truth / pickup sounds, and a Sound On/Off
  mute button.
- Minimal HUD: score and paradox top-right, inventory bottom-left, one hint line
  bottom-centre — no cluttered bars.

## How to open the project in the editor

1. Install Godot **4.7.2-stable** (or newer 4.x) and the matching export
   templates if you want to re-export.
2. Open Godot → Import → select `project.godot` in this folder (or run
   `godot --path .` from the command line).
3. Press F5 (or the Play button) to run the scene. Click anywhere to walk;
   click a glowing object to investigate it. `?autodemo=1` in the web export
   (or `--autodemo` on the command line) plays a short scripted demo:
   the Cadet walks to Franklin and opens the dialogue.

## How to run the web export locally

The ready-to-run export is in `web-export/` (also zipped as
`timeline-restorer-godot-poc-web.zip`, ~12 MB):

```sh
cd web-export
python3 -m http.server 8901
```

Then open <http://localhost:8901/index.html> in a browser. Any plain static
server works (no special headers needed — the export is single-threaded).
First load takes a few seconds while the 39 MB WebAssembly engine compiles.

## Screenshots (all taken from the running web export, 1280×720)

| File | What it shows |
|---|---|
| `shot-title.png` | Act title card on scene start |
| `shot-scene.png` | The workshop with both characters, HUD, hotspot rings |
| `shot-dialogue.png` | Franklin dialogue open, Cadet beside him, 3 choices |
| `shot-truth.png` | Truth Check panel: ANACHRONISTIC, fact, eras, confidence, +12 paradox, Score 50 |
| `shot-inventory.png` | "Picked up: Magnifying Glass" toast + inventory slot |
| `shot-magnifier-popup.png` | Magnifying Glass action popup (Look / Pick up) |
| `shot-device-popup.png` | Humming Device action popup (Look / Truth Check) |

## Verification performed

- `godot --headless --import` — clean, no errors.
- Navigation test (`test_nav.gd`, headless SceneTree): **0 failures** — routes to
  Franklin, the magnifier and the device all return real waypoint paths that
  go around the workbench and stool (e.g. to Franklin:
  `(790,660) → (900,700) → (1000,700) → (1010,660)`).
- Web export completed (single-threaded, Compatibility renderer). Export size:
  **41 MB** total — `index.wasm` 39.5 MB, `index.pck` 2.6 MB, `index.js` 280 KB.
  Console on load reports `Build configuration: Emscripten 4.0.20,
  single-threaded, no GDExtension support` and `OpenGL ES 3.0 (WebGL 2.0)`.
- The export was loaded in headless Chromium and driven end-to-end via CDP:
  engine initialised with no fatal errors, and the screenshots above were taken
  from live play (click-to-walk, dialogue, Truth Check and pickup all exercised
  with real mouse clicks, not scripted state).
- v1 and v2 untouched: `v1/timeline-restorer.html` SHA256 is still
  `d03c22ef0260681922932bcbcb52f455a869fdab534dddbfefbbac6d83b90410`.
- Nothing was pushed to GitHub; the zip is the delivery vehicle (the `.wasm` /
  `.pck` are binaries and cannot be pushed via the text-only GitHub push tool).

### Caveats (honest)

- **HTTP check in this sandbox:** the sandbox's Chromium build blocks
  `localhost` navigation (`ERR_BLOCKED_BY_LOCAL_NETWORK_ACCESS_CHECKS`) even
  with the Local Network Access feature flag disabled, a managed-policy
  allow-list, and a CDP permission grant. The HTTP server itself was verified
  serving the files (`curl` 200 on `index.html` and `index.pck`), and the
  engine was verified by loading the identical export files via `file://`
  (the only difference is the URL scheme). On a normal machine the export runs
  over plain HTTP as documented above.
- **Audio in headless:** the procedural audio code runs (no errors), but sound
  itself could not be heard in headless Chromium — the AudioContext is
  suspended until a user gesture, which is standard browser behaviour. The
  mute button works. Verify sound by ear in a real browser.
- **Mobile touch:** not tested — the PoC is mouse-driven; touch input is not
  wired up.
- **Walk speed in headless:** under SwiftShader (software rendering) the game
  runs at very low FPS, so the Cadet walks slowly in the headless screenshots.
  On real hardware with GPU rendering he walks at the intended 190 px/s.
- **Nav band is approximate:** the walkable region is a painted-backdrop
  approximation — a 20 px strip above the workbench is technically walkable,
  though the pathfinder prefers the corridor and bottom strip for all hotspot
  routes. Floor clicks are clamped to y 585–695.
- `make_polygons_from_outlines()` prints a deprecation warning on load in
  Godot 4.7 (it still works; the replacement API is
  `NavigationServer2D.parse_source_geometry_data()` /
  `bake_from_source_geometry_data()`).
- **Single-frame character animation:** the characters are single sprites with
  procedural bob / squash / flip rather than multi-frame walk cycles —
  generated multi-frame cycles looked inconsistent, so this was the deliberate
  choice. The scene still reads as illustrated characters, not vector shapes.

## What is still a placeholder

- Only Act 1, one scene: no quiz, no paradox/stability game-over, no endings,
  no save system, no other acts or hotspots beyond the workshop set
  (music player, magnifier, Leyden jar, Franklin, workbench notes).
- The paradox percentage does not yet change in the HUD when a truth is found
  (the +12 is recorded and shown in the panel; the HUD update on close is
  still to be wired).
- Art is AI-generated raster illustration (original, made for this PoC), not
  hand-drawn pixel art. The background, Cadet, Franklin and leaves are in
  `art/` (raw generations kept in `art/raw/`, excluded from the export).
- The Godot project is a proof of concept, not the full game rebuild.

## Files

- `project.godot`, `main.tscn`, `export_presets.cfg`, `icon.svg` — project.
- `scripts/` — `main.gd` (scene, input, HUD, dialogue/truth/action UI),
  `cadet.gd`, `franklin.gd`, `dialogue_data.gd` (ported v1 content),
  `audio_manager.gd` (procedural sound).
- `art/` — `workshop_bg.png`, `cadet.png`, `franklin.png`, `leaves.png`.
- `web-export/` — the built web export; `timeline-restorer-godot-poc-web.zip`
  — the same export, zipped.
- `test_nav.gd`, `test_nav_debug.gd` — headless navigation verification scripts.
- `cdp-*.mjs` — the CDP drivers used to screenshot and click-test the export
  in headless Chromium (verification tooling, not part of the game).
