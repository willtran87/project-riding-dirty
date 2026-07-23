# Riding Dirty

## Game Design Document

**Status:** Early concept  
**Genre:** Arcade-physics dirt-bike adventure and racing game  
**Working title:** *Riding Dirty*

## 1. High Concept

*Riding Dirty* is a dirt-bike game about mastering dangerous terrain, building a distinctive bike, and earning a reputation in a fading off-road town.

The player begins with a battered dirt bike and limited resources. By competing in organized races, discovering hidden trails, performing stunts, and taking on illicit riding challenges, they earn money, parts, sponsors, and recognition. Progress opens new districts, rivals, motorcycles, and increasingly dangerous events.

The game combines the freedom of an open riding playground with approachable controls and expressive physics. Its defining sensation should be narrowly saving a jump, landing, or slide that appeared destined to become a crash.

## 2. Player Fantasy

The player should feel like a talented but unproven rider building a name through skill, nerve, and mechanical ingenuity.

The experience should support several overlapping fantasies:

- Mastering a responsive dirt bike.
- Finding fast or creative routes through difficult terrain.
- Turning a cheap machine into a personalized build.
- Developing a reputation as a racer, freestyler, explorer, mechanic, or outlaw.
- Becoming familiar with a region until every shortcut and jump feels personally discovered.

## 3. Design Pillars

### Expressive Riding

Controls are easy to understand, but terrain, momentum, suspension, and weight transfer create depth. Skilled players should be visibly smoother and faster without the game becoming inaccessible.

### Risk Creates Stories

Players constantly decide whether to preserve control or attempt a faster line, larger jump, difficult trick, or dangerous shortcut. Mistakes should frequently be recoverable so near-disasters become memorable moments.

### A World Built for Dirt Bikes

The environment is not scenery between races. It is a network of trails, jumps, challenges, shortcuts, secrets, and natural riding lines that rewards curiosity.

### Bikes With Character

Parts and tuning alter behavior through meaningful tradeoffs. A bike should feel like a personal build, not a collection of linear stat upgrades.

### Reputation Defines the Rider

Progress reflects how the player chooses to ride. Racing, freestyle, exploration, mechanical experimentation, and outlaw activity each build a different reputation.

## 4. Core Gameplay Loop

1. Select an event, job, rival challenge, or unexplored trail.
2. Inspect the terrain and tune the bike for the expected conditions.
3. Ride while managing speed, balance, traction, stamina, and damage.
4. Complete objectives, discover routes, perform tricks, and establish records.
5. Earn cash, parts, sponsorship opportunities, and reputation.
6. Repair or modify the bike and unlock new areas or challenges.
7. Return with a better build or improved technique to master earlier routes.

## 5. Riding Model

The target is arcade readability supported by convincing physical behavior. The game should reward real dirt-bike ideas without requiring simulation-level knowledge.

### Core Inputs

- Throttle
- Front and rear braking, either separated or contextually combined
- Rider lean forward and backward
- Steering
- Suspension preload before jumps
- Trick or contextual action input
- Flow boost, earned through clean landings and spent tactically on the ground

### Advanced Techniques

- Scrubbing jumps to remain low and preserve racing speed
- Whipping the bike for style and repositioning it before landing
- Using wheelies and weight transfer over rough ground
- Controlling slides with throttle and countersteering
- Correcting pitch in the air
- Absorbing hard landings with rider movement
- Recovering from imperfect landings before they become crashes

### Terrain Behavior

Terrain types should feel distinct rather than acting as cosmetic speed modifiers.

- **Packed dirt:** Predictable grip and the baseline handling surface.
- **Mud:** Reduced traction, deeper ruts, and greater momentum loss.
- **Sand:** Heavy steering, power demand, and flowing slides.
- **Gravel:** Loose lateral grip and unstable braking.
- **Rock:** High impact risk and technical wheel placement.
- **Wet ground:** Reduced grip with localized puddles and changing lines.

### Crashes and Recovery

Minor errors should produce wobbles, poor landings, lost speed, or bike damage before triggering a full crash. This creates space for dramatic saves.

Full crashes should be quick to recover from during ordinary play. Severe injury systems are not currently part of the concept; damage is primarily mechanical and competitive.

## 6. World Structure

The recommended structure is a compact open region containing interconnected riding districts. Events reuse the same physical world, allowing players to develop geographic mastery.

Potential districts include:

- A working quarry with steep walls, machinery, and enormous jumps
- Woodland trails with roots, streams, and narrow technical routes
- Farms with field tracks, irrigation ditches, and unauthorized shortcuts
- A dedicated motocross facility
- Sand pits and riverbanks
- Storm drains and flood channels
- Abandoned factories or rail yards
- A small town containing garages, shops, meeting spots, and story characters

The world should feature recognizable landmarks and layered routes for different skill levels. A visible destination may have a safe route, a fast route, and a dangerous expert line.

## 7. Activities and Events

### Racing

- Motocross circuit races
- Point-to-point trail races
- Hill climbs
- Enduro endurance events
- Time trials
- Rival races
- Ghost challenges against personal or community records

### Freestyle

- Trick competitions
- Score-attack stunt parks
- Continuous lines that reward flow and variety
- Gap jumps and landing challenges
- Environmental trick objectives

### Exploration

- Hidden trails
- Unmarked jumps
- Scenic overlooks
- Abandoned parts or bike discoveries
- Route-finding challenges
- Environmental puzzles solved through riding skill

### Outlaw Activities

- Unauthorized night rides
- Trespassing challenges
- Escapes from security or law enforcement
- Illegal street-to-dirt races
- Deliveries or timed jobs using restricted routes

Outlaw activities should emphasize pursuit, navigation, and escape rather than violence.

### Mechanical Challenges

- Restore abandoned motorcycles
- Win events using restricted parts or unusual setups
- Diagnose handling problems through test rides
- Build a bike for a specific rider or terrain type

## 8. Progression and Reputation

Progression is divided into complementary reputation paths. Players may specialize or build a mixed identity.

| Reputation | Earned Through | Typical Unlocks |
| --- | --- | --- |
| Racer | Victories, clean laps, records | Organized events, race parts, sponsors |
| Freestyler | Tricks, lines, style scores | Trick parks, visual gear, freestyle parts |
| Outlaw | Trespassing, escapes, illicit events | Hidden contacts, illegal races, secret routes |
| Explorer | Discoveries, trail completion, secrets | Maps, remote districts, rare finds |
| Mechanic | Restorations, tuning challenges, unusual builds | Workshop tools, experimental parts, project bikes |

Reputation should change how characters describe and approach the player. It may also create rivalries, sponsorship choices, and mutually exclusive opportunities.

## 9. Bikes, Parts, and Tuning

Upgrades should create choices rather than strictly replacing previous parts.

Example tradeoffs include:

- Greater engine power with more wheelspin and harder control
- Soft suspension for rough trails versus stiff suspension for large jumps
- Short gearing for technical climbs versus long gearing for high-speed racing
- Lightweight components with reduced durability
- High-grip tires that wear quickly or perform poorly on other surfaces
- Improvised repairs that are cheap but visibly unreliable

### Potential Tuning Categories

- Gear ratio
- Suspension stiffness and damping
- Tire compound and tread
- Brake balance
- Engine mapping
- Rider stance or control sensitivity

Tuning should communicate consequences clearly. Presets can make the system approachable, while manual adjustment supports advanced players.

## 10. Economy and Garage

Cash is used for repairs, parts, entry fees, cosmetic customization, and new motorcycles. The economy should encourage experimentation without forcing repetitive grinding.

The garage is the player's home base and should evolve visually as their career grows. It may support:

- Repairing and cleaning bikes
- Installing and comparing parts
- Saving named bike setups
- Painting and decorating bikes
- Displaying trophies and recovered motorcycles
- Talking with crew members, sponsors, and rivals
- Selecting events and inspecting conditions

## 11. Tone and Presentation

The tone should be energetic, rough-edged, and grounded without becoming grim. The world is worn, muddy, mechanically noisy, and full of local personality.

### Visual Direction

The game will use stylized low-to-mid-poly 3D rather than photorealism. The target is a playable action-sports poster: bold silhouettes, dramatic terrain, richly colored dirt, battered machinery, graphic liveries, and cinematic natural lighting.

The visual identity should combine early-2000s action-sports grit with modern lighting and material treatment. Stylization should make the game more readable, distinctive, and achievable while allowing animation, effects, and camera work to provide the spectacle.

Key visual principles include:

- Large, readable bike and rider silhouettes
- Exaggerated elevation, berms, ruts, jumps, and landing zones
- Saturated bikes and riding gear against earthy environments
- Warm sunlight contrasted with cool shadows and atmospheric fog
- Clearly visible suspension travel, rider lean, and bike weight transfer
- Thick dust, thrown mud, tire tracks, sparks, and loose debris
- Dense landmarks arranged around memorable riding lines
- Purposeful wear, repairs, decals, and improvised construction

The game should look cohesive rather than expensive. Strong composition, motion, lighting, and material contrast take priority over polygon count or physically exact motorcycle reproduction.

Potential themes include:

- Finding purpose in a town whose old industries are disappearing
- Tension between organized motorsport and informal riding culture
- Community, rivalry, and reputation
- Repairing and repurposing discarded machines and places

The implemented soundtrack establishes an original arcade-hip-hop/chiptune direction. “Dust Circuit” is synthesized procedurally in D minor at 143 BPM: a bass, drum, and noise-channel foundation runs continuously while an independent pulse-lead and arpeggio stem fades in with the player’s Flow chain. Future districts can extend this adaptive stem-based language with garage rock, punk, breakbeats, and atmospheric trail music.

## 12. Camera, Format, and Technology

The game will be built as a fully 3D third-person experience in Godot. This direction best supports exploration, terrain reading, racing immersion, expressive bike control, and the fantasy of inhabiting a connected off-road region.

### Camera Direction

The primary camera is a responsive third-person chase camera that communicates speed without obscuring the terrain ahead. It should:

- Pull back subtly as speed increases
- Look toward the rider's intended direction and upcoming terrain
- Preserve a clear view of jump faces and landing zones
- Compress forward during hard acceleration and open up in the air
- Use restrained shake for engine vibration, impacts, and hard landings
- Allow cinematic framing during large jumps without removing control
- Recover quickly and predictably after crashes or sharp direction changes

Optional replay and event cameras may use trackside, low-angle, and aerial framing to make successful runs feel like action-sports footage.

### Technical Art Direction

Core gameplay assets will be genuine 3D elements: the bike, rider, terrain, obstacles, collision, and animation. Procedural geometry, modular environment kits, stylized materials, shaders, particles, and deliberate lighting will carry most of the visual workload.

Image generation will support the art pipeline rather than substitute for gameplay-critical 3D assets. Appropriate uses include:

- Environment, lighting, character, outfit, and bike-livery concepts
- Event posters, loading screens, story stills, and menu backgrounds
- Garage decorations, murals, signage, and fictional sponsor treatments
- Reference sheets for mud, rust, paint, wear, and regional color palettes
- Early visual targets used to guide 3D modeling and scene composition

Generated artwork must be curated and adapted to the established style. It should not be used directly for collision-ready terrain, finished motorcycles, consistent rider animation, or mechanically important components.

## 13. Minimum Viable Prototype

The first playable version should answer one question: is repeatedly riding the same short course enjoyable?

### Prototype Content

- One stylized low-to-mid-poly dirt bike and rider
- One quarry test environment with exaggerated elevation and multiple readable lines
- One approximately two-minute circuit
- Several optional stunt lines and shortcuts
- Basic throttle, braking, steering, lean, suspension, jumping, and landing
- Recoverable mistakes and full crashes
- A responsive third-person chase camera
- A focused lighting setup with dust, mud, tire marks, and landing feedback
- A ghost of the player's best run
- Time and style medals
- Simple bike reset and instant event restart

### Prototype Success Criteria

- Riding is enjoyable without progression rewards.
- Players understand why they lost control.
- Skilled riding produces visibly smoother and faster results.
- Jumps create meaningful decisions about speed, angle, and landing.
- Players voluntarily replay the course to improve a time or line.
- Crashes are entertaining but do not interrupt the flow for long.

## 14. Initial Production Roadmap

### Phase 1: Feel Prototype

Build the bike controller, camera, terrain response, jump behavior, recovery, and crash loop in a gray-box environment.

### Phase 2: Replayable Course

Create one polished route with multiple lines, timing, medals, ghost replay, and basic audio feedback.

### Phase 3: Garage Loop

Add repairs, a small set of tradeoff-based parts, saved setups, and event rewards.

### Phase 4: Vertical Slice

Produce one representative district containing races, exploration, freestyle opportunities, a rival, and a small narrative arc.

### Phase 5: Expansion Decision

Use playtest results to determine world size, event variety, progression depth, and the feasible content plan.

## 15. Key Risks

- The bike can feel either too unstable for new players or too simple for mastery.
- A fully 3D open world greatly increases environment and animation scope.
- Physics inconsistencies can make failure feel arbitrary.
- Large upgrade trees can undermine meaningful tuning choices.
- Police or outlaw systems could distract from the riding if overdeveloped.
- An oversized world could dilute the density of memorable riding lines.

## 16. Open Design Questions

1. Is the primary fantasy racing, open exploration, freestyle expression, or a deliberate balance?
2. Does the player control a named protagonist or create their own rider?
3. How central are characters and story to progression?
4. Are pursuits a major system or occasional event type?
5. Is multiplayer part of the initial vision, a later possibility, or out of scope?
6. How much mechanical damage and repair detail supports fun without creating maintenance chores?
7. What is the target platform and control scheme?

## 17. Current Direction Summary

*Riding Dirty* will be a compact, fully 3D third-person off-road game built in Godot. It will use stylized low-to-mid-poly artwork, arcade-readable physics, meaningful bike tuning, several reputation paths, and a mixture of racing, freestyle, exploration, and outlaw challenges.

The initial visual target is a muddy, colorful, slightly exaggerated world in which every strong gameplay moment could resemble action-sports key art. Image generation will establish concepts and enrich presentation, while the core bike, rider, terrain, animation, and effects remain controllable 3D assets.

Development should begin with a single stylized bike and rider on a short, replayable quarry course. The project should expand only after riding, jumping, landing, recovering, and watching the bike move are satisfying on their own.

## 18. Implementation Status

The project now contains a playable Godot vertical slice of the recommended direction.

### Implemented and Verified

- Stylized low-to-mid-poly dirt bike and rider assembled from procedural 3D geometry
- Rigid-body arcade handling with two-point ray suspension, active balance, steering, braking, reverse, preload hopping, and airborne lean control
- A 0–100 Flow meter earned by clean airborne landings, with a 35-point ground boost that raises acceleration and temporary top speed
- Responsive speed-reactive third-person chase camera with predictive framing and landing kick
- A complete Red Mesa quarry circuit with track markings, jumps, table sections, berms, cliffs, props, course markers, lighting, fog, and environmental landmarks
- Ordered checkpoint validation, countdown, microsecond timing, medal thresholds, instant restart, and safe-position bike reset
- Persistent personal-best time and interpolated collision-free ghost playback
- Synthesized engine and pooled gameplay cues, dust trails, landing bursts, wheel animation, rider pose response, boost camera punch, and speed presentation
- Responsive race HUD with keyboard and gamepad instructions, pause state, speed, time, best time, checkpoint progress, and finish results
- Persistent cash, Racer reputation, run rewards, and transaction history
- A playable garage with three bike setups: Trail, Balanced, and Attack
- Setup purchases and meaningful tradeoffs across power, grip, suspension, lean, and top speed
- Three persistent named bike-build slots that restore bike, setup, class, parts, tune, and livery while preserving the live machine's condition and odometer
- Garage event selection across Circuit, Freestyle, and Discovery activities
- A 60-second freestyle event scoring physical airtime, bike rotation, landing quality, and clean combo chains
- A six-cache exploration hunt with animated salvage pickups, completion medals, persistent best time, and a nearest-target compass
- Mode-specific HUD presentation and persistent best records for all three quarry activities
- Pine Ridge, a second wooded riding district with its own enduro route, creek bridge, ravine jumps, ranger cabin, timber landmarks, and batched forest foliage
- Data-driven track configuration with district-specific spawn points, gates, medal thresholds, presentation, and persistent ghost slots
- Separate Racer, Freestyler, and Explorer reputation progression
- Persistent bike condition, hard-landing damage, modest condition-based performance loss, and garage repair costs as a currency sink
- Persistent per-event medal mastery, tour completion tracking, and Pine Ridge unlock rules with backward-compatible save migration
- Rook rival targets for both race districts with live checkpoint split feedback and persistent rival victories
- Authored district cover/reveal transitions for every activity, with event-specific route, target, and identity copy
- Ride Director ownership of 4.5-second Flow-line chains spanning clean landings, scrubs, whips, wheelies, saves, boosts, routes, and near-misses
- Two secret route gates per activity, narrow alternate route geometry, reusable breakaway props, and surface-specific mud, gravel, and rock handling
- Deterministic daily Tailwind, Flow Surge, and Loose Dirt conditions plus persistent sponsor contracts
- Persistent Style Tokens, feat unlocks, and three cosmetic tiers earned through four-move chains, route discovery, contracts, and no-reset finishes
- Assisted, Sport, and Pro handling modes with buffered preload, takeoff grace, and aerial self-righting differences
- Authored collision-free Rook riders following district racing curves, character finish callouts, and best/costliest sector analysis
- Reactive rider posture, wobble recovery, pooled skid marks, boost trails, landing debris, controller haptics, and route/airtime camera framing
- Activity-specific atmospheric grading, fog, lightweight weather, trackside spectators, flags, and adaptive two-layer synthesized music
- Responsive web frontend with a single-threaded WebAssembly build, fullscreen presentation, browser input capture, and visibility-aware pause/audio behavior
- Browser-local persistence for rider progress and personal-best ghost recordings
- Runtime smoke validation covering acceleration, stable height, chase-camera distance, checkpoint registration, and run reset
- Activity-specific smoke validation covering both race districts, authored rivals, secret routes, sector breakdowns, physical Flow lines, contracts, feats, cosmetics, assist persistence, discovery pickup rebuilding, and repair transaction invariants
- Live browser validation at 2560×1600, 1280×800, and 390×844, including WebAssembly startup and in-canvas keyboard input
- Rendered visual validation at 2560×1440, 1280×720, and 960×540

### Next Expansion Targets

1. Run representative long-session playtests to tune sponsor rank pacing, objective variety, and event-build recommendations.
2. Add voiced sponsor briefings and trackside sponsor treatments while retaining readable text-only feedback.
3. Add authored production music and voice while retaining the synthesized Web fallback.
4. Add optional online leaderboards and shared daily seeds without making progression network-dependent.
