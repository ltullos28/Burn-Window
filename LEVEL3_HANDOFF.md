# Level 3 Handoff

This file is the handoff brief for starting the next major architecture phase of Burn Window.

Read this file together with:

- `T:\Burn Window\SCRIPT_PARTITION_PLAN.md`
- `T:\Burn Window\PROJECT_MEMORY.md`

## Current Status

Level 1 is done enough to be useful:

- body rendering has been unified under `body_render.gd`
- `planet_render.gd` and `moon_render.gd` are thin wrappers

Level 2 is underway and materially established:

- `simulation_state.gd` now contains a real body registry
- legacy `planet_*` / `moon_*` fields still exist as compatibility bridges
- the predictor has started using registry-backed body data
- navball uses generic reference-body helpers

Level 3 has only been lightly prepared.

The real Level 3 work still remains:

- make prediction outputs less moon-specialized
- make map/body focus logic more body-agnostic
- reduce reliance on hardcoded `planet + moon` assumptions
- prepare for future multi-body and hierarchical systems

## Required Working Style

The user explicitly wants strong turn discipline.

Important rule for the next chat:

- Do not compact or recompact context in the middle of a turn.
- If you need to compact, it must be the very last thing you do after fully completing everything requested in that turn.

The user is sensitive to drift.

That means:

- do not "accidentally" work on some other bug from prior context
- do not change adjacent systems unless they are directly required
- if you do make a wrong-turn change, revert your own change before proceeding

## Code Philosophy For Level 3

### New philosophy

The game should stop treating `planet` and `moon` as special in the core architecture.

Instead, the code should move toward:

- bodies as registry entries
- generic body-relative helpers
- generic dominant-body logic
- generic predicted body-state access
- generic encounter/transition concepts

UI can still remain temporarily specialized.

For example:

- it is acceptable for the cockpit to still expose `PLANET`, `MOON`, and `SHIP` modes for now
- it is not acceptable for low-level simulation or prediction code to stay deeply hardcoded around one primary and one special moon forever

### How to identify the old philosophy

Treat these as indicators of the old philosophy:

- direct use of `SimulationState.planet_*` and `SimulationState.moon_*` when a generic body helper could be used instead
- logic that assumes there is one "main" body and one "special encounter body"
- output structures with first-class moon-specific fields instead of generalized containers
- code that branches specifically on `"planet"` / `"moon"` inside low-level math when it should be looping over bodies or using focused-body helpers

Not every occurrence must be removed immediately.

Some are still compatibility bridges by design.

The task is to distinguish:

- compatibility bridges we are intentionally keeping during migration
- accidental architecture blockers that should be refactored now

## Existing Plan Files

These files already exist and should be used:

- `T:\Burn Window\SCRIPT_PARTITION_PLAN.md`
- `T:\Burn Window\PROJECT_MEMORY.md`

`SCRIPT_PARTITION_PLAN.md` contains:

- migration inventory
- partition strategy
- broader audit findings

`PROJECT_MEMORY.md` contains:

- important behavioral expectations
- bugfix intent
- system notes that should not be lost

Do not ignore these files.

## Fragile Fixes And Behaviors To Preserve

These areas are easy to break and must be treated carefully.

### 1. Targeted warp follows the selected predicted path

Relevant files:

- `T:\Burn Window\game\new-game-project\trajectory_map.gd`
- `T:\Burn Window\game\new-game-project\simulation_state.gd`
- `T:\Burn Window\game\new-game-project\scenes\ship.gd`

Behavior:

- targeted warp does not simply integrate live and hope to match the prediction
- it packages prediction samples into a warp path
- during active targeted warp, ship translation follows that stored path

Why it exists:

- live integration during targeted warp let the ship drift off the displayed line
- this caused visible jumps, especially at the moon-dominance handoff

Be careful:

- stale predictions are dangerous here
- if you touch warp packaging, selection, or ship motion during warp, preserve the "ship stays on displayed selected path" behavior

### 2. Timewarp gating on stale trajectory prediction

Relevant files:

- `T:\Burn Window\game\new-game-project\trajectory_map.gd`
- `T:\Burn Window\game\new-game-project\simulation_state.gd`
- `T:\Burn Window\game\new-game-project\scenes\ship.gd`
- `T:\Burn Window\game\new-game-project\player.gd`

Behavior:

- burns mark the prediction stale
- timewarp cannot be enabled while stale
- the legend has three states:
  - fresh + off
  - fresh + on
  - stale + off needs refresh
- if the text block is expanded and the prediction becomes stale, it collapses immediately

Why it exists:

- targeted warp now follows a stored predicted path
- if the player burns after refresh but before warp, the old path becomes invalid

Be careful:

- if you move timewarp logic out of `trajectory_map.gd`, preserve these stale gating rules

### 3. Geometry caching split from live overlays

Relevant file:

- `T:\Burn Window\game\new-game-project\trajectory_map.gd`

Behavior:

- the map still redraws every frame
- but expensive static geometry is cached
- live overlays remain dynamic:
  - ship dot
  - nose vector
  - velocity vector
  - UI text
  - moving body dots

Why it exists:

- moon-view lag was previously caused by expensive geometry rebuilding every frame

Be careful:

- if you split map responsibilities, do not regress into rebuilding heavy trajectory geometry every frame

### 4. Refresh-time predictor performance

Relevant files:

- `T:\Burn Window\game\new-game-project\trajectoryMath\trajectory_predictor.gd`
- `T:\Burn Window\game\new-game-project\trajectory_map.gd`

Behavior:

- predictor inner loop now uses compiled body metadata and one-pass per-step body-state evaluation
- refresh tries to reuse the quick prediction instead of always running the predictor twice

Why it exists:

- naive registry generalization caused a visible refresh lag spike
- the issue was implementation overhead, not the registry concept

Be careful:

- if you generalize predictor further, keep the low-level fast path mentality
- avoid reintroducing repeated helper churn in the inner loop

### 5. Planet/moon rendering scale fix

Relevant files:

- `T:\Burn Window\game\new-game-project\body_render.gd`
- `T:\Burn Window\game\new-game-project\planet_render.gd`
- `T:\Burn Window\game\new-game-project\moon_render.gd`

Behavior:

- base mesh radius is auto-detected from mesh bounds if not explicitly set
- body placement lives on the parent visual node
- child mesh local position is zeroed so baked offsets do not shove the body away

Why it exists:

- renderer previously scaled meshes as if their base radius were `1.0`
- actual meshes were much larger, causing massive incorrect body sizes

Be careful:

- if you touch body rendering or visual shells, do not break base-radius detection or parent-centered placement

### 6. Planet atmosphere and moon haze tuning

Relevant files:

- `T:\Burn Window\game\new-game-project\planetary_haze_shell.gdshader`
- `T:\Burn Window\game\new-game-project\planet_render.gd`
- `T:\Burn Window\game\new-game-project\moon_render.gd`

Behavior:

- planet has a thin Mars-like atmosphere shell
- moon has a lighter Titan-like haze shell
- the terminator alignment was tuned carefully

Why it exists:

- earlier versions had the shell too thick, always glowing, or slightly misaligned with the lit side

Be careful:

- if you touch shell lighting or body visual wrappers, preserve the current tuned result unless intentionally retuning visuals

## File-by-File Notes

### `simulation_state.gd`

Capabilities:

- body registry
- body state queries
- dominant-body queries
- gravity
- targeted warp state
- sim time stepping
- rail orbit updates

Why certain things are still there:

- legacy `planet_*` and `moon_*` fields still exist because many systems still consume them
- `_sync_legacy_body_fields_from_registry()` is a compatibility bridge, not a final design

What likely needs change:

- gradually reduce direct callers of legacy fields
- eventually split registry / rails / gravity / targeted warp into smaller systems

### `trajectory_predictor.gd`

Capabilities:

- future trajectory integration
- generic gravity accumulation from compiled bodies
- closest-approach detection
- apsis prediction

Why certain things are still there:

- moon-specific outputs remain because the map/UI still depend on them
- near-circular apsis fallback logic is still embedded here for compatibility

What likely needs change:

- move toward body-targeted encounter summaries rather than moon-specific outputs
- separate generic prediction from marker-analysis concerns

### `trajectory_map.gd`

Capabilities:

- trajectory screen UI
- map mode switching
- cached trajectory geometry
- local moon display handoff
- targeted warp selector UI
- refresh controls

Why certain things are still there:

- this file accumulated many responsibilities because it was the easiest place to keep the feature behavior coherent while bugs were being fixed

What likely needs change:

- split out timewarp selector model
- split out focus/projection/body-relative drawing helpers
- split out local encounter / marker analysis
- reduce direct planet/moon field coupling

### `trajectory_solution.gd`

Capabilities:

- stores prediction outputs and derived orbit data

Why certain things are still there:

- moon-specific fields are still compatibility data for existing map/UI behavior

What likely needs change:

- evolve toward a more structured solution model with:
  - generic path data
  - encounter summaries per body
  - display metadata

### `orbit_solver.gd`

Capabilities:

- relative orbit solving
- currently wrapped in a `solve_planet_orbit(...)` compatibility API

Why certain things are still there:

- `solve_planet_orbit(...)` remains because many systems still call it directly

What likely needs change:

- expose and use more generic body-relative solve entry points

### `navball.gd`

Capabilities:

- orbital orientation markers
- reference-body-based prograde/radial/normal indicators

Why certain things are still there:

- orbital frame math remains local to the instrument for now

What likely needs change:

- eventually move shared orbital-frame math into a reusable helper if more instruments need it

### `player.gd`

Capabilities:

- seated player control
- free look
- crosshair state
- interact/zoom logic
- trajectory screen key handling

Why certain things are still there:

- direct trajectory screen input handling was kept here to stabilize behavior during timewarp and stale-prediction fixes

What likely needs change:

- move trajectory-screen-specific input logic out
- reduce coupling between player input and map logic

### `trajectory_info_label.gd`

Capabilities:

- cockpit telemetry display

Why certain things are still there:

- it polls map methods because there is not yet a dedicated structured telemetry source

What likely needs change:

- replace stringly map polling with a smaller telemetry surface later

## Recommended Level 3 Opening Plan

1. Read:
   - `SCRIPT_PARTITION_PLAN.md`
   - `PROJECT_MEMORY.md`
   - this file

2. Audit the current `trajectory_map.gd` responsibilities against the plan file.

3. Start with one clean extraction, not many:
   - preferred first extraction: timewarp selection model
   - second candidate: body-focus/projection helpers

4. Keep compatibility behavior stable after each extraction:
   - stale warp gating
   - warp path following
   - moon-local transfer continuity
   - cached geometry behavior

5. After each migration slice, verify no regressions before continuing.

## Avoid These Failure Modes

- Do not start by trying to make the whole UI body-agnostic in one pass.
- Do not remove compatibility fields from `SimulationState` too early.
- Do not refactor targeted warp casually; it interacts with several delicate bugfixes.
- Do not collapse geometry caching back into live per-frame rebuilds.
- Do not chase unrelated bugs while doing architecture work unless the current turn explicitly asks for it.
