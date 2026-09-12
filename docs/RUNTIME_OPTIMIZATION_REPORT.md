# Runtime optimization verification — 2026-09-12

All eight findings from the runtime audit are addressed without reducing the
physics rate, opponent intelligence, visual quality settings, or replay sample rate.

## Changes and preservation contracts

| Area | Removed work | Preserved behavior |
| --- | --- | --- |
| Replay recording | Building a full race snapshot every physics tick to read one scalar | Reads the same authoritative integrity progress; capture cadence and interpolation unchanged |
| Browser state | Building hidden Garage/history/workshop/results projections at 10 Hz | Visible menus and results remain projected; strategy cache invalidates on menu, profile, and debrief changes |
| Classification | Building and rendering the same field classification twice per feedback update | Both public signals remain; session-only HUD adapters still receive classification |
| Rival particles | Updating emitters while their existing effect budget disables them | Same enabled-effect policy, particle settings, and nearby feedback |
| Replay loading | Multiple deep copies and repeated validation | One validated owned copy; imported/source mutations cannot affect playback |
| Rival articulation | Node and limb transforms for riders fully behind the camera | Scalar animation state advances normally; a conservative 6 m margin and camera-cut restoration retain the current pose |
| Replay markers | Scanning the full event collection each tick | Indexed seeks and sequential cursor preserve timestamp boundaries, authored ordering, pause, and loop semantics |
| Input/HUD text | Reformatting unchanged bindings, Flow and staging text | Binding revisions/device modes invalidate caches; continuous meters and changing status colors still update |

## Before/after measurements

Release Web export, Chromium headless with SwiftShader, identical 1280×720
diagnostic scenario. Seven batches per case after warm-up; values are median
microseconds per call. The projection case closes the Garage without starting
the simulation. The replay contains about two minutes of 30 Hz samples and
2,048 markers. This isolates CPU work; it is **not an FPS or real-device GPU benchmark**.

| Operation | Before (µs) | After (µs) | Reduction |
| --- | ---: | ---: | ---: |
| Recording progress | 532.73 | 0.934 | 99.8% |
| Racing browser projection | 8,274.21 | 1,178.74 | 85.8% |
| Binding label | 6.89 | 2.636 | 61.7% |
| Replay load | 174,283.8 | 93,690.0 | 46.2% |
| Replay advance/event lookup | 624.64 | 30.02 | 95.2% |

Raw local results: `output/runtime-baseline.json` and
`output/runtime-optimized.json`. Release memory monitoring reported zero
(unavailable); no memory reduction is claimed from that counter.

A final-package rerun using the checked-in runner completed without browser
errors (`output/runtime-final-smoke.json`): 0.925 µs recording progress,
1,307.99 µs browser projection, 2.523 µs binding label, 82,772 µs replay load,
and 30.165 µs replay advance. The observed spread is retained rather than
reporting only the fastest run.

The new runtime regression also checks 120 hidden-pose steps: zero articulation
applications and zero disabled-effect updates, followed by one exact pose
restoration when the camera turns. All child and MultiMesh transforms match
an always-articulated reference. Enabled particles resume updating.

## Reproduction

1. Build with `python tools/build_web_release.py` and serve the `web` directory
   using the project's existing local server.
2. Run `node tools/benchmark_web_runtime.mjs output/runtime-benchmark.json`.
   Install Playwright locally or set `PLAYWRIGHT_MODULE` to the absolute path of
   an existing Playwright `index.mjs`. An optional second argument selects the
   served `/game/index.html` URL.
3. Compare exports on the same machine with other heavy work stopped. The opt-in
   `--runtime-benchmark` argument uses an isolated browser profile and disables
   persistence; normal game startup does not run this diagnostic.

Run the behavior regression with Godot's headless executable and
`--path . res://features/testing/runtime_optimization_probe.tscn`.
It is also included in the normal quality gate.

Validation completed: 27 focused Godot probes and all 17 Web delivery tests;
inspected live racing/Flow feedback at 2560×1600, 1280×720, and 844×390 with
no browser errors or horizontal overflow. The final shared-client startup
check also passed. This was not a rerun of the complete balance matrix.

Representative-device frame pacing, memory usage, and player comfort still
require the device/player sessions in `PLAYER_VALIDATION_PROTOCOL.md`.
