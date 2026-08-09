# Riding Dirty representative-player release gate

This protocol is the acceptance authority for qualities that deterministic code cannot prove: fun, perceived responsiveness, learnability, fair challenge, motivation, audiovisual taste, comfort, and real-device performance. Automated probes may prepare a candidate, but they must never mark these gates passed without recorded sessions from representative people on the stated hardware.

## Cohorts and minimum sample

Run at least 24 complete sessions with no participant counted in more than one skill cohort:

| Cohort | Minimum | Required representation |
| --- | ---: | --- |
| New to racing games | 8 | At least 4 primarily use keyboard or touch |
| Occasional racing players | 8 | Mixed keyboard and controller |
| Experienced racing players | 6 | At least 3 manual-transmission users |
| Accessibility-focused | 6 | At least 2 motor, 2 visual, and 2 audio/cognitive needs; overlap is allowed |

At least 8 sessions must use lower-performance devices. Recruit a mix of screen sizes and do not coach participants unless the script explicitly permits it.

## Device matrix

| Tier | Required devices and modes | Pass threshold |
| --- | --- | --- |
| Desktop high | 2560x1440, controller and keyboard, Quality | 60 FPS median; no active-play frame stall above 100 ms |
| Desktop low | Integrated graphics, 1280x720, Performance | 30 FPS 1% low; no input stall above 100 ms |
| Compact browser | 844x390 and 960x540, touch where available | No clipped required action; 30 FPS median |
| Mobile portrait/landscape | 390x844 and 844x390 | Orientation recovery without reload or lost progress |
| Assistive modes | 175% text, high contrast, reduced motion/flashes/particles, captions | Every required action remains visible and operable |

Test current Chrome, Edge, and Firefox plus Safari on one current iOS or macOS device. Record browser/OS, CPU/GPU, memory, input device, display scale, graphics preset, and build hash.

## Session scripts

### A. First 15 minutes

1. Start from a clean profile. Do not explain the Garage.
2. Ask the participant to start their first official race.
3. Complete or retry the first Quarry event, then visit Results and Workshop.
4. Ask them to describe Flow, boost, the event plan, the next goal, and how to change a control or assist.

Pass when at least 80% start the intended first event within 90 seconds, 80% explain the core controls without prompting, 75% use Flow intentionally, and 80% identify their next goal. No required action may have a median discoverability time over 45 seconds.

### B. Handling and feedback

1. Trigger acceleration, braking, steering, a jump/landing, Flow, Surge, contact, a crash, recovery, pause, and restart.
2. Repeat with Reduced Motion and captions enabled.

Pass when median control responsiveness is at least 4/5, at least 85% correctly identify every high-priority outcome, no cohort reports a recurring inaccessible action, and motion discomfort remains at or below 2/5 for 90% of participants.

### C. Difficulty and opponents

1. Run matched events on Relaxed, Standard, and Expert.
2. Observe opponent passes, defensive choices, mistakes, Flow banking, and Surge use.
3. Record finish position, restarts, perceived fairness, and whether the result felt recoverable.

Pass when perceived challenge increases monotonically for at least 80% of players, fairness is at least 4/5 for 75%, no difficulty produces unavoidable contact in more than 10% of starts, and expert players observe at least one legible rival Flow/boost attack in 80% of full races.

### D. Strategy and learning loop

1. Complete three runs of one event: baseline, one deliberate plan change, then a repeated plan.
2. Use Results debrief, Workshop Previous/PB history, sector comparison, and plan restore without facilitator explanation.
3. Ask what changed, what evidence is confounded, and what they will try next.

Pass when 80% distinguish Previous from PB, 75% identify the biggest sector opportunity, 75% understand why a changed plan or condition prevents clean attribution, and 70% make a deliberate next-run choice.

### E. Progression and replayability

1. Continue through at least six official events and one optional mode.
2. Use a saved bike build or outfit, one sponsor path, a rotating challenge or Local Duel, and a Custom Tour.
3. Record reward cadence, decision variety, grind perception, and intent to replay.

Pass when 75% rate motivation and reward clarity at least 4/5, 70% use two meaningfully different strategies, 70% voluntarily start another activity, and fewer than 15% describe required grind or manipulative pressure. No purchase or sponsor choice may be mistaken for real-money monetization.

### F. Long-session stability and recovery

1. Play for 60 minutes including at least four transitions, a reload, settings changes, and one forced browser or tab interruption.
2. Resume from primary save; separately exercise the documented backup-recovery test copy.

Pass with zero crashes, lost official results, duplicated rewards, stuck transitions, or unrecoverable saves. Resume must restore the last confirmed official state. Peak memory may not grow by more than 20% after the first 15 minutes when returning to an equivalent Garage state.

## Evidence record and stop-ship rules

Each session must record the exact manifest and pack SHA-256; anonymized participant/cohort ID; device matrix row; event sequence; objective metrics; 1–5 ratings; and structured notes for confusing, unfair, inaccessible, uncomfortable, or especially satisfying moments. Capture video only with explicit consent. Link every failed threshold to an issue tagged `release-blocker`, `tuning`, or `follow-up`.

Publish distributions by cohort and input method, not only averages. Critical data loss, an inaccessible required action, repeatable hard lock, misleading competitive result, or failure to recover a confirmed official save is an automatic stop-ship.
