# Riding Dirty

*Riding Dirty* is a stylized 3D dirt-bike game built with Godot. The current build is a playable quarry time-trial vertical slice focused on responsive handling, jumps, recoverable mistakes, course mastery, medals, and a personal-best ghost.

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
& '.\tools\godot-4.7\Godot_v4.7-stable_win64.exe' --headless --path . --export-release Web 'web/game/index.html'
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
| Reset bike | R | Y / Triangle |
| Restart run | Enter | X / Square |
| Pause | Escape | Start |
| Open garage | G | B / Circle |
| Repair in garage | F | Right shoulder |

The garage uses `Q` / `E` or the horizontal D-pad to change setups, `W` / `S` or the vertical D-pad to change events, and `Enter` / `A` to purchase or ride. Medal finishes award cash plus activity-specific Racer, Freestyler, or Explorer reputation; profile progress and personal-best records persist between sessions.

## Quarry events

- **Quarry Circuit** — ordered checkpoint time trial with medals and a personal-best ghost
- **Quarry Freestyle** — 60-second score attack based on airtime, rotation, landing quality, and clean combos
- **Salvage Hunt** — locate six workshop caches using the directional compass and finish-time medals
- **Pine Ridge Enduro** — a separate wooded district with tighter trail geometry, ravine jumps, creek crossing, and its own personal-best ghost

## Validation

Run the deterministic activity smoke tests with:

```powershell
& '.\tools\godot-4.7\Godot_v4.7-stable_win64.exe' --headless --path . -- --smoke-test --activity=CIRCUIT
& '.\tools\godot-4.7\Godot_v4.7-stable_win64.exe' --headless --path . -- --smoke-test --activity=FREESTYLE
& '.\tools\godot-4.7\Godot_v4.7-stable_win64.exe' --headless --path . -- --smoke-test --activity=DISCOVERY
& '.\tools\godot-4.7\Godot_v4.7-stable_win64.exe' --headless --path . -- --smoke-test --activity=PINE_ENDURO
```

## Project structure

- `common/` — focused global lifecycle and input services
- `entities/bike/` — bike physics, presentation, audio, and scene
- `features/` — camera, race, ghost, and HUD systems
- `levels/quarry/` — the vertical-slice course and environment
- `scenes/` — top-level composition scenes
- `web/` — responsive play page and generated WebAssembly release
- `GAME_DESIGN_DOCUMENT.md` — current vision and production direction
