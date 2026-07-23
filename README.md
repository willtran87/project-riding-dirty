# Riding Dirty

*Riding Dirty* is a stylized 3D dirt-bike racing tour built with Godot 4.7. Racecraft V28 includes 18 playable events across Quarry Trail, Pine Ridge, and Red Mesa MX; full championship weekends and replayable seasons; named multi-bike fields; tactile arcade handling; adaptive touch controls; bike building and tuning; competitive challenges; replay and ghost systems; an eight-lesson Riding Academy; and persistent progression.

## Local browser build

The supported workspace endpoint is [http://127.0.0.1:8777/](http://127.0.0.1:8777/). Run the release workflow below before treating the files served there as current. Serving the threaded Godot export through another environment requires the same cross-origin-isolation headers as `serve_web.py`.

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
python .\serve_web.py
```

Then open [http://127.0.0.1:8777/](http://127.0.0.1:8777/). Click **Start the Tour**, click or tap the game once to give it input/audio focus, and use the controls below. Phones and tablets receive adaptive Garage and riding controls; rotate to landscape for the full course view.

To produce and verify the browser release after a game change, install the Godot 4.7 export templates and run:

```powershell
python .\tools\build_web_release.py
```

The deterministic release script exports Godot, content-addresses the pack and the complete WebAssembly/audio-worklet runtime family, reinstalls the wrapper handshake, writes `web/build-manifest.json`, verifies that test-only runtime code is absent, and runs the delivery tests. The Web preset uses Godot's threaded compatibility renderer. `serve_web.py` supplies the required `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp` headers. Static hosts such as GitHub Pages use the root-scoped `web/coi-serviceworker.js` fallback, which reloads the top-level wrapper under the same isolation policy before the game starts. Rider profiles and personal-best ghosts use verified primary and backup slots in browser storage; clearing site data removes those browser saves.

## Controls

| Action | Keyboard | Gamepad | Touch |
| --- | --- | --- | --- |
| Throttle | W | Right trigger | Hold THROTTLE |
| Brake / reverse | S | Left trigger | Hold BRAKE |
| Steer | A / D | Left stick | Drag the ride pad left / right |
| Lean in the air | Up / Down | Right stick | Drag the ride pad up / down |
| Preload / hop | Space | A / Cross | Hold HOP, then release |
| Context Flow | Shift | Left shoulder | Tap FLOW |
| Racecraft technique | C | Right shoulder | Tap TECH |
| Reset bike | R | Y / Triangle | Tap RESET |
| Restart run | Enter | X / Square | Results action |
| Pause | Escape | Start | Tap PAUSE |
| Open garage | G | B / Circle | Tap GARAGE |
| Repair in garage | F | Right shoulder | Tap REPAIR |
| Cycle handling assist in garage | H | Left-stick click | Tap ASSIST |
| Open race workshop | Tab | X / Square | Tap WORKSHOP |
| Settings / accessibility | F1 | Back / Select | Tap SETTINGS |
| Replay | V | - | - |
| Photo mode | P | - | - |

The garage uses `Q` / `E` or the horizontal D-pad to change setups, `W` / `S` or the vertical D-pad to change events, and `Enter` / `A` to purchase or ride. Medal finishes award cash plus activity-specific Racer, Freestyler, or Explorer reputation; profile progress and personal-best records persist between sessions.

Clean landings and well-executed racecraft earn **Flow**. `Shift` or the left shoulder spends it contextually: **Surge** accelerates on a straight, **Rail** settles a braking turn, **Compose** aligns a risky landing, and **Brace** absorbs pack pressure. `C` or the right shoulder is also contextual: it performs a clutch pop under drive, pumps loaded suspension through terrain, or dabs to save the bike at low speed. Resets clear the meter.

### Settings and accessibility

Open the five-page settings surface with `F1`, Back/Select, or the touch SETTINGS button. Every numeric and enumerated option can be changed with keyboard, gamepad, or the on-screen minus/plus controls, and long pages keep the selected row in view. The Input page can force touch controls on or off, swap handedness, and tune control size and opacity.

- **Race difficulty:** Relaxed, Standard, and Expert apply a bounded `-1`, `0`, or `+1` offset to the authored AI tier in ordinary offline races. Daily/weekly challenges and Riding Academy grading remain locked to their authored rules, and difficulty is included in the run signature so unlike sessions do not share records.
- **Visual quality:** Performance uses a 75% 3D render scale without MSAA, Balanced uses 90% with 2x MSAA, and Quality uses 100% with up to 4x MSAA. Web builds cap Quality at 2x MSAA. These presets affect rendering only; race simulation, physics, timing, and signatures do not change.
- **Reduced Motion:** This accessibility option sharply limits dynamic FOV, camera shake, bank, impact response, camera repositioning, and look-ahead, and replaces animated district wipes with a static readable briefing. High-contrast HUD, color-safe flag palettes, text scale, units, haptic strength, and full keyboard/gamepad/mouse rebinding remain available.

Settings use a versioned, checksum-verified format with temporary-write verification, a rotating backup, legacy migration, and automatic primary repair after backup recovery.

## Racecraft V28 systems

- **Authoritative tracks:** One route geometry drives the visible riding surface, collision, map, checkpoints, barriers, reset poses, rivals, and race pack. Quarry and Pine are traversable point-to-point courses; Mesa is a traversable closed circuit; all three have automated topology, clipping, barrier, ground-cover, and terrain-clearance validation. Pine's creek and ridge trails are legal, progress-mapped branches that rejoin the same authoritative course.
- **Full race weekends:** Practice, qualifying, heats, LCQ transfers, main events, flags, sectors, penalties, classifications, DNFs, championship points, standings, and countback rules.
- **Race formats:** Circuit, enduro, motocross, elimination, head-to-head rival, endurance, hillclimb, wet race, rhythm attack, freestyle, discovery, daily challenge, weekly challenge, and Academy sessions.
- **Racing field:** Named opponents share the player bike presentation, hold formation off the start, follow the authoritative route, jump with the surface, overtake, defend, make mistakes, and generate controlled contact pressure. The Garage and results expose local rank, personal best, ghost, replay, championship, and named-rival stakes.
- **Opponent challenge:** Ordinary race fields inherit `0.65` of the active bike and selected Trail, Balanced, or Attack setup's forward-performance gain, capped at a `1.12` opponent multiplier. A starter build stays on the authored baseline while upgrades retain a meaningful player advantage without making the field obsolete. Relaxed, Standard, and Expert remain distinct at authored-tier boundaries; skilled rivals commit to passes and bounded defensive moves, carry stronger section momentum, apply late-race pressure, and recover faster from mistakes. Deterministic full-course acceptance checks player placement at fixed starter and max-build benchmarks: starter `0.888x`-gold pace must finish P5-P8, upgraded `0.680x`-gold pace must finish P4-P9, and upgraded elite `0.650x`-gold pace must win. Difficulty ordering, full-traffic stability, and active racecraft remain release contracts.
- **Interactive gate starts:** During the final countdown the bike remains physically frozen while throttle and brake staging drive live HUD and engine feedback. A well-timed release earns a small 0.9-second launch advantage; holding the brake or missing the throttle can bog the start, with the result bounded to a 0.94-1.08 drive multiplier.
- **Race tension and identity:** Each event now carries an authored difficulty, pace, airtime, replay, and featured-rider contract. A bounded mid-race director keeps battles relevant without copying player velocity or deciding the finish, while eleven rider archetypes preserve recognizable strengths and weaknesses.
- **Bike feel:** Contact-point suspension, planted tire direction, high-speed steering authority, preload jumps, aerial pitch, landing alignment, terrain response, haptics, camera feedback, and stable reset/rejoin behavior. Rear-brake slides, scrubs, pumps, clutch pops, foot dabs, rut capture, outside berms, drafting, defensive roost, and bounded risk/reward skill lines all act on the physical bike.
- **Contextual Flow:** One button chooses Surge, Rail, Compose, or Brace from the current physical state. Each technique has its own cost and purpose, and replays preserve sparse racecraft moments without changing the fixed-rate transform format.
- **Pack racecraft:** Player and AI drafting use direction and alignment gates rather than proximity alone. Rivals choose ruts, outside berms, and deterministic skill lines after the launch phase; deliberate dirt slides can roost a close follower, while drive penalties and wobble chances stay bounded.
- **Career and garage:** A six-round championship, persistent weekend state, cash and reputation rewards, bike purchases, race classes, parts, condition and repair, tuning presets that alter physical suspension/brake/preload values, rider number, liveries, and riding kit customization. Three named build slots let riders preserve and revisit complete bike, kit, class, part, tune, and livery strategies without copying wear or odometer state.
- **Fair progression:** Race reputation starts from medal value, adds bounded placement and personal-best bonuses, and preserves full value for first clears, first wins, and new bests. Non-improving repeat finishes award 35% reputation while retaining their cash reward, making practice useful without letting repetition overwhelm new-event progress. Overtakes, contacts, crashes, recoveries, clean rides, and related achievements are calculated from the player's bike rather than aggregate NPC activity.
- **Competition:** Deterministic daily and weekly events, exact run signatures, local leaderboards, optional queued HTTP submissions, personal-best ghosts, replay, hotseat challenges, and tamper-checked ghost import/export.
- **Riding Academy:** Eight progressive lessons with live ride metrics, prerequisites, explicit rematches, grading, stars, rewards, and a two-objective live lesson HUD. The syllabus now grades rut rails, controlled slides, pumps, clean landings, skill lines, scrubs, Compose saves, dabs, rejoins, drafting passes, and clean contact management.
- **Player options:** Five-page settings for audio, ride, camera/graphics, accessibility, and input; persisted Relaxed/Standard/Expert race difficulty; Performance/Balanced/Quality visual presets; Reduced Motion; adaptive multitouch riding and Garage controls with handedness, scale, and opacity options; keyboard/gamepad/mouse rebinding with conflict protection; assist modes; metric or imperial units; FOV, camera shake, deadzone, sensitivity, response curve, haptic strength, text scale, high contrast, and color-safe flag colors.
- **Reliable saves and lifecycle:** Desktop profiles use verified temporary replacement plus a rotating recovery copy. Browser profiles and ghosts use checksum-verified primary/backup storage and repair a damaged primary from the backup. Hiding the browser pauses and mutes the game without overwriting a pause or mute the player already owned.
- **Audio identity:** Quarry, Pine, and Mesa use distinct procedural score palettes; standard, weekend, finale, and challenge events adapt through base, drive, tension, and results stems with smooth transitions and separate Music/SFX buses.
- **Production pass:** Tracks stream behind event briefings, Pine's signature-validated baked dressing and exact terrain index preserve authored density while shortening preparation, and a live route-derived fallback prevents stale bakes from becoming authoritative. Adaptive music synthesis overlaps district loading, the Garage presents the selected bike and rider as a readable hero composition, dense dressing is batched and spatially indexed, minimap geometry is cached, release probes are excluded, threaded Web payloads negotiate gzip, and the browser wrapper prioritizes a large readable 16:9 canvas at laptop and high-resolution desktop sizes.

## Ride and presentation systems

- **Flow Lines:** Clean landings, scrubs, whips, wheelies, recoverable saves, boosts, near-misses, and secret routes form a 4.5-second chain with an escalating multiplier.
- **Daily ride conditions:** Tailwind, Flow Surge, or Loose Dirt changes the handling/reward texture for the day without requiring an online service.
- **Sponsor relationships:** Dustline Works rewards race precision, Wildbrush Outpost rewards terrain reading, and Sundown Static rewards expressive lines. Each program advances independently through Prospect, Signed, Factory, and Icon ranks; the Garage previews the selected event's relationship, while the live HUD shows the exact objective, progress, cash, reputation, and Style Token reward. Event transitions carry each program's distinct accent, authored tagline, and rides-to-next-rank, while completion uses a sponsor-specific pooled SFX sting. Higher ranks pair modestly harder achievable goals with transparent payouts, and the existing verified contract transaction prevents duplicate rewards.
- **Feats and cosmetics:** Four-move chains, both secret lines, and no-reset race finishes unlock persistent feats. Style Tokens advance the rider's visual tier.
- **Authored Rook rival:** Race events include an amber, collision-free Rook rider following the target racing line, live checkpoint comparison, post-run character callouts, and sector analysis.
- **Alternate lines:** Quarry and Pine Ridge now include narrow shortcuts, transfer kickers, creek skips, ridge threads, distinctive mud/gravel/rock behavior, and reusable breakaway props.
- **Handling assists:** Assisted, Sport, and Pro modes change aerial self-righting. Preload input includes a short buffer and takeoff grace window.
- **Reactive presentation:** The original 143 BPM procedural chiptune “Dust Circuit” previews in the garage and raises its lead and arpeggio layers as Flow rises; boost streaks, pooled skid marks, district weather and grading, landing debris, haptics, animated rider posture, trackside spectators, and non-blocking cinematic camera framing respond to the ride.

## Tour progression

The three Quarry activities are available from the start. Pine Ridge unlocks after completing any two distinct Quarry activities, beating Rook's `03:10.000` Quarry Trail target, or reaching 80 combined reputation. Merely starting two current-version runs does not unlock Pine; the old two-run condition is retained only while migrating a qualifying legacy save. Every event retains its highest medal. Race checkpoints show live ahead/behind splits against Rook; finishes identify the strongest and costliest sectors; each ride begins with an authored district card before handing control back to the player.

## Quarry events

- **Quarry Trail** — a 1.8-kilometer hill course with 18 ordered gates, quarry ridges, canyon descents, loose dirt, medals, and a personal-best ghost
- **Quarry Freestyle** — 60-second score attack based on airtime, rotation, landing quality, and clean combos
- **Salvage Hunt** — locate six workshop caches using the directional compass and finish-time medals
- **Pine Ridge Enduro** — a 3.2-kilometer wooded mountain trail with 23 gates, 92 meters of elevation range, ravine jumps, creek crossings, and its own personal-best ghost

## Acknowledgments

The contact-point motorcycle physics pass was informed by the MIT-licensed [Godot Simple Motorcycle Physics](https://github.com/rishabhsinghio/Godot-Simple-Motorcycle-Physics) project. Its demo mesh and audio are not included. See `THIRD_PARTY_NOTICES.md` for the license notice.

## Validation

Run the deterministic production gate with:

```powershell
python .\tools\run_quality_gate.py
```

The default gate performs a Godot parser/editor scan, a curated set of high-risk physics, route, persistence, settings, progression, competition, and lifecycle probes, and five representative playable activity smokes. It stops at the first failure.

Before a release candidate, run every focused probe plus the representative playable smokes:

```powershell
python .\tools\run_quality_gate.py --full
```

`--full` discovers every focused `*_probe.tscn` contract before running the same activity smokes. After it passes, `tools/build_web_release.py` is the release step that exports, content-addresses, stamps, leak-checks, and delivery-tests the browser build.

Individual activity smokes remain available for focused iteration:

```powershell
& '.\tools\godot-4.7\Godot_v4.7-stable_win64_console.exe' --headless --path . -- --smoke-test --activity=CIRCUIT
& '.\tools\godot-4.7\Godot_v4.7-stable_win64_console.exe' --headless --path . -- --smoke-test --activity=FREESTYLE
& '.\tools\godot-4.7\Godot_v4.7-stable_win64_console.exe' --headless --path . -- --smoke-test --activity=DISCOVERY
& '.\tools\godot-4.7\Godot_v4.7-stable_win64_console.exe' --headless --path . -- --smoke-test --activity=PINE_ENDURO
& '.\tools\godot-4.7\Godot_v4.7-stable_win64_console.exe' --headless --path . res://features/testing/bike_dynamics_probe.tscn -- --smoke-test
```

## Project structure

- `common/` — focused global lifecycle and input services
- `entities/bike/` — bike physics, presentation, audio, and scene
- `features/` — ride direction, environment, audio, camera, race, ghost, garage, and HUD systems
- `levels/quarry/` — the vertical-slice course and environment
- `scenes/` — top-level composition scenes
- `web/` — responsive play page and generated WebAssembly release
- `GAME_DESIGN_DOCUMENT.md` — current vision and production direction
