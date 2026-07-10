# Riding Dirty

*Riding Dirty* is a stylized 3D dirt-bike tour built with Godot. The current 2.0 build includes four events across Red Mesa and Pine Ridge, responsive arcade handling, recoverable saves, Flow-line chains, persistent mastery, authored rival pressure, sponsor contracts, and rotating run conditions.

## Play online

[Play Riding Dirty in your browser](https://willtran87.github.io/project-riding-dirty/)

## Run the game

The project includes a locally ignored portable Godot editor under `tools/godot-4.7/` when developed in the original workspace.

From PowerShell:

```powershell
& '.\tools\godot-4.7\Godot_v4.7-stable_win64.exe' --path .
```

Or import `project.godot` into any compatible Godot 4.x editor and run the project.

## Play in a browser

The responsive frontend and current Godot WebAssembly release live under `web/`. Serve that directory over HTTP; browsers will not run the exported game correctly from a `file://` URL.

```powershell
python -m http.server 8777 --bind 127.0.0.1 --directory web
```

Then open [http://127.0.0.1:8777/](http://127.0.0.1:8777/). Click **Start Engine**, click the game once to give it keyboard/audio focus, and use the controls below. A desktop keyboard or gamepad is recommended; the page is responsive on narrow screens, but the game does not yet include touch riding controls.

To rebuild the browser release after a game change, install the Godot 4.7 export templates and run:

```powershell
& '.\tools\godot-4.7\Godot_v4.7-stable_win64_console.exe' --headless --path . --export-release Web 'web/game/index.html'
```

The Web preset uses the single-threaded compatibility renderer, so it works on an ordinary static server without COOP/COEP headers. Rider progress and personal-best ghosts use browser `localStorage`; clearing site data removes those browser saves.

## Controls

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Throttle | W | Right trigger |
| Brake / reverse | S | Left trigger |
| Steer | A / D | Left stick |
| Lean in the air | Up / Down | Right stick |
| Preload / hop | Space | A / Cross |
| Flow boost | Shift | Left shoulder |
| Reset bike | R | Y / Triangle |
| Restart run | Enter | X / Square |
| Pause | Escape | Start |
| Open garage | G | B / Circle |
| Repair in garage | F | Right shoulder |
| Cycle handling assist in garage | H | Left-stick click |

The garage uses `Q` / `E` or the horizontal D-pad to change setups, `W` / `S` or the vertical D-pad to change events, and `Enter` / `A` to purchase or ride. Medal finishes award cash plus activity-specific Racer, Freestyler, or Explorer reputation; profile progress and personal-best records persist between sessions.

Clean landings after at least 0.45 seconds of airtime earn **Flow**. Spend 35 Flow with `Shift` or the left shoulder button for a short acceleration burst with a wider camera, HUD response, and synthesized cue. Resets clear the meter, so the fastest lines link jumps and boosts within the same run.

## Riding Dirty 2.0 systems

- **Flow Lines:** Clean landings, scrubs, whips, wheelies, recoverable saves, boosts, near-misses, and secret routes form a 4.5-second chain with an escalating multiplier.
- **Daily ride conditions:** Tailwind, Flow Surge, or Loose Dirt changes the handling/reward texture for the day without requiring an online service.
- **Sponsor contracts:** Each activity presents a skill objective. Completion awards cash, reputation, and a Style Token.
- **Feats and cosmetics:** Four-move chains, both secret lines, and no-reset race finishes unlock persistent feats. Style Tokens advance the rider's visual tier.
- **Authored Rook rival:** Race events include an amber, collision-free Rook rider following the target racing line, live checkpoint comparison, post-run character callouts, and sector analysis.
- **Alternate lines:** Quarry and Pine Ridge now include narrow shortcuts, transfer kickers, creek skips, ridge threads, distinctive mud/gravel/rock behavior, and reusable breakaway props.
- **Handling assists:** Assisted, Sport, and Pro modes change aerial self-righting. Preload input includes a short buffer and takeoff grace window.
- **Reactive presentation:** Adaptive synthesized music, boost streaks, pooled skid marks, district weather and grading, landing debris, haptics, animated rider posture, trackside spectators, and non-blocking cinematic camera framing respond to the ride.

## Tour progression

The three Red Mesa activities are available from the start. Pine Ridge unlocks after completing any two Red Mesa events, beating Rook's `00:52.000` Quarry Circuit target, reaching 80 combined reputation, or completing two runs on an older save. Every event retains its highest medal. Race checkpoints show live ahead/behind splits against Rook; finishes identify the strongest and costliest sectors; each ride begins with an authored district card before handing control back to the player.

## Quarry events

- **Quarry Circuit** — ordered checkpoint time trial with medals and a personal-best ghost
- **Quarry Freestyle** — 60-second score attack based on airtime, rotation, landing quality, and clean combos
- **Salvage Hunt** — locate six workshop caches using the directional compass and finish-time medals
- **Pine Ridge Enduro** — a separate wooded district with tighter trail geometry, ravine jumps, creek crossing, and its own personal-best ghost

## Validation

Run the deterministic activity smoke tests with:

```powershell
& '.\tools\godot-4.7\Godot_v4.7-stable_win64_console.exe' --headless --path . -- --smoke-test --activity=CIRCUIT
& '.\tools\godot-4.7\Godot_v4.7-stable_win64_console.exe' --headless --path . -- --smoke-test --activity=FREESTYLE
& '.\tools\godot-4.7\Godot_v4.7-stable_win64_console.exe' --headless --path . -- --smoke-test --activity=DISCOVERY
& '.\tools\godot-4.7\Godot_v4.7-stable_win64_console.exe' --headless --path . -- --smoke-test --activity=PINE_ENDURO
```

## Project structure

- `common/` — focused global lifecycle and input services
- `entities/bike/` — bike physics, presentation, audio, and scene
- `features/` — ride direction, environment, audio, camera, race, ghost, garage, and HUD systems
- `levels/quarry/` — the vertical-slice course and environment
- `scenes/` — top-level composition scenes
- `web/` — responsive play page and generated WebAssembly release
- `GAME_DESIGN_DOCUMENT.md` — current vision and production direction
