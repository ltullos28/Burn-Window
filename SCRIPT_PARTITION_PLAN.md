# Script Partition Plan

## Goal

This file marks the main logic seams that should be split before or during level 2 body/generalization work.

The focus is not "rewrite everything now." It is "move the right kinds of logic into the right homes so the big scripts stop being the only place where the game knows how to work."

## Gameplay Objective Direction

Current working objective direction:

- The player has limited fuel and limited oxygen.
- Fuel is consumed by burns.
- Oxygen is consumed by simulation time itself, including timewarp.
- That creates the intended tradeoff:
  - waiting for efficient windows saves fuel but costs oxygen
  - aggressive trajectories save oxygen but cost fuel

Why this is a strong fit:

- It makes timewarp a meaningful resource decision instead of free convenience.
- It reinforces the cockpit-survival tone and mission pressure.
- It gives orbital optimization a real gameplay stake without needing arcadey mechanics.
- It scales naturally into difficulty modes.

Possible difficulty direction:

- Easier difficulties can provide more oxygen and fuel margin.
- Harder difficulties can tighten both margins.
- A future hard mode could require advanced techniques such as gravity assists once there are more bodies in the system.

Architectural implication:

- Resource/time accounting should eventually live outside `trajectory_map.gd` and outside one-off UI code.
- Oxygen especially should key off simulation time, not real wall-clock time, so it belongs near simulation state / mission state.
- Mission objectives, resource budgets, and fail/success conditions likely want a future `mission_state.gd` or similar owner once the current system modularization work is farther along.

## `trajectory_map.gd`

This script is currently doing too many jobs at once.

### Keep in `trajectory_map.gd`

- CRT-specific drawing
- viewport/screen interaction state
- mode switching for the map display itself
- lightweight coordination between sub-systems

### Move out

- Prediction horizon policy
  - Current logic: `_get_zoom_based_prediction_steps()`, `_get_period_based_prediction_steps()`, `_get_dynamic_prediction_steps()`, `_get_reference_relative_points()`, `_find_continuity_closure_index()`, `_get_continuity_trimmed_steps()`
  - Better home: new `trajectoryMath/prediction_horizon.gd`
  - Why: this is forecast policy, not screen rendering

- Timewarp selection model
  - Current logic: enable/disable state, selection indexing, reference index rebasing, confirm/cancel rules
  - Better home: new `trajectoryMath/timewarp_selector.gd` or similar data object
  - Why: this is stateful timeline selection logic, not drawing

- Geometry cache construction
  - Current logic: `_rebuild_geometry_cache_if_needed()`, `_build_main_ship_runs()`, `_build_hidden_runs()`, `_project_points_range()`, `_draw_projected_runs()`
  - Better home: new `trajectoryMath/trajectory_projection_cache.gd`
  - Why: screen projection/caching is a reusable map-data problem, separate from the actual CRT widget

- Moon-local orbit marker detection
  - Current logic: moon PE/AP/CA extraction and fallback logic are baked into the cache rebuild / draw flow
  - Better home: new `trajectoryMath/local_orbit_markers.gd`
  - Why: marker extraction is analysis on predicted paths, not UI

- Audio coordination
  - Current logic: refresh sound lookup/start/stop in the map script
  - Better home: either a small helper object or a cockpit computer controller node
  - Why: the map should not have to know where the beep player lives in the scene tree

## `player.gd`

This script is still manageable, but it already contains three separate systems.

### Keep in `player.gd`

- top-level seated controller ownership
- camera transform blending

### Move out

- Crosshair presentation
  - Better home: `crosshair_controller.gd`
  - Why: icon switching and visibility are UI state, not player motion

- Interaction/hold logic
  - Better home: `cockpit_interaction_controller.gd`
  - Why: press/release behavior and interactable routing can grow independently

- Trajectory-computer-specific key handling
  - Better home: `trajectory_screen_input.gd`
  - Why: player input should not need hard-coded knowledge of one particular screen's keyboard shortcuts

## `simulation_state.gd`

This is the main level 2 target.

### Current mixed responsibilities

- body constants
- rail-body updates
- global sim time
- body reference helpers
- gravity calculation
- targeted warp scheduling
- physics-frame delta caching

### Split candidates

- `body_registry.gd`
  - body lookup, radius, position, velocity, up vectors

- `rail_orbit_system.gd`
  - updates on-rails body positions/velocities from parent relationships

- `targeted_warp_controller.gd`
  - warp timing, snap state, finish/cancel rules

- `gravity_field.gd`
  - gravity accumulation from registered bodies

## `ship.gd`

This script is in decent shape, but it has one obvious future split.

### Keep in `ship.gd`

- one owner for the ship scene node

### Move out later

- translational orbital integration vs rotational cockpit control
  - Better split:
    - `ship_flight_model.gd`
    - `ship_attitude_controller.gd`
  - Why: translation and manual rotation are already conceptually different systems

## `trajectory_predictor.gd`

This one is mostly in the right layer already.

### What might move later

- dominance/encounter classification helpers
- extrema smoothing / marker index extraction

### Why

Those are analysis passes on prediction output and could become reusable utilities once there are more bodies.

## Level 2 Preparation Summary

The biggest architectural blockers to multi-body modularity are:

1. `SimulationState` still being a hard-coded planet/moon authority.
2. `trajectory_map.gd` still owning forecast policy, cache policy, screen policy, and timewarp UI state all at once.
3. player input being coupled directly to trajectory-computer keys.

The new `body_render.gd` is the first step because it removes duplicated body-visual logic and starts introducing generic body access through `SimulationState`.

## Level 2 Migration Inventory

This section tracks the concrete scripts that still carry the old hard-coded "planet + moon" philosophy and what needs to change in each one.

### `simulation_state.gd`

Still old-philosophy in these ways:

- Exported body setup is still hard-coded as `planet_*` and `moon_*`
- On-rails body update is still moon-specific in `_update_moon_state()`
- Dominance and reference-body logic still assume only `planet` and `moon`
- Legacy compatibility fields are still first-class, not transitional

Planned changes:

- Introduce generic body-state-at-time helpers for on-rails bodies
- Introduce dominant/reference body helpers that return body names, not just planet/moon-specific state
- Keep legacy fields temporarily, but migrate callers toward registry access

### `trajectory_predictor.gd`

Still old-philosophy in these ways:

- Gravity integration is hardcoded to planet + moon
- Future rail-body state prediction is hardcoded in `_moon_state_at_time()`
- Several calculations explicitly depend on `SimulationState.planet_*` and `SimulationState.moon_*`

Planned changes:

- Read gravity sources from the body registry
- Replace `_moon_state_at_time()` with generic body-state-at-time queries
- Keep moon-specific output fields for now, but source them through generic helpers

### `scenes/navball.gd`

Still old-philosophy in these ways:

- Local helper functions explicitly branch between `planet` and `moon`
- Reference-body choice is still "moon or not moon" instead of "current dominant body"

Planned changes:

- Use generic reference-body helpers from `SimulationState`
- Remove direct `planet_pos` / `moon_pos` / `planet_vel` / `moon_vel` branching

### `trajectory_map.gd`

Still old-philosophy in these ways:

- Prediction setup is still written around one primary planet and one moon
- Display code assumes a specific moon-intercept / moon-local handoff model
- Many helpers pull `planet_*` and `moon_*` directly instead of asking the registry
- Center/view modes are still semantically tied to `PLANET`, `MOON`, and `SHIP`

Planned changes:

- Migrate internal body lookups to registry-backed helpers first
- Keep current `PLANET/MOON/SHIP` UI semantics temporarily
- Later split body-agnostic prediction/display logic away from screen/UI logic

### `trajectoryMath/orbit_solver.gd`

Still old-philosophy in these ways:

- API naming is still centered on `solve_planet_orbit(...)`

Planned changes:

- Add generic body-relative orbit solving entry points
- Keep `solve_planet_orbit(...)` as a compatibility wrapper during migration

### `scenes/trajectory_info_label.gd`

Still old-philosophy in these ways:

- Moon-specific closest-approach readouts are built around a single named moon encounter

Planned changes:

- Keep current moon-specific readout for now
- Later decide whether this becomes "selected target body" info or remains moon-only UI

### `trajectoryMath/trajectory_solution.gd`

Still old-philosophy in these ways:

- Output schema still includes moon-specific fields as first-class data

Planned changes:

- Leave compatibility fields for now
- Later introduce body-targeted encounter containers if/when multi-body UI expands

### `player.gd`

Not a first-wave migration target, but note:

- It still knows directly about trajectory computer interaction flow
- Once map/input logic is more modular, this should stop hardcoding trajectory-screen behavior

## First Migration Pass

The first safe/high-leverage migration pass should focus on:

1. `simulation_state.gd`
   - add generic body-state-at-time and reference-body-name helpers
2. `trajectory_predictor.gd`
   - switch future body-state and gravity logic to use registry-backed helpers
3. `scenes/navball.gd`
   - switch to generic reference-body helpers

This keeps behavior stable while moving core simulation consumers off direct hardcoded body fields.

## Broader Audit Findings

This section tracks broader cleanup discovered while validating Level 2 work.

### `trajectory_map.gd`

Still the largest concentration of mixed responsibilities.

Additional concrete issues:

- It is still the de facto owner of:
  - prediction policy
  - display horizon trimming
  - moon-local encounter analysis
  - timewarp selection state
  - refresh/stale gating UI
  - warp-path packaging
- It still hardcodes one global planet display plus one special moon transfer display.
- It still converts between simulation-space, planet-relative space, and moon-relative space inline in many places instead of through a shared projection/body-focus layer.
- It still directly depends on moon-specific solution fields (`moon_points`, `moon_dominance`, `moon_closest_approach_*`) all through the draw path.

Cleanup implication:

- `trajectory_map.gd` should be the main Level 3 target.
- The first real split should probably be:
  - body-focus / projection helpers
  - warp-selection model
  - local encounter/marker analysis

### `trajectory_predictor.gd`

Level 2 generalized it enough to use the registry, but it is still not body-agnostic in output shape.

Additional concrete issues:

- It still emits moon-specific prediction data as first-class outputs.
- It still assumes there is one primary planet frame and one special moon frame.
- Near-circular apsis fallback logic is still bundled directly into the predictor instead of living in a reusable marker-analysis layer.

Cleanup implication:

- Future Level 3 predictor work should separate:
  - generic predicted body-state sampling
  - generic gravity integration
  - body-targeted encounter extraction
  - apsis/marker extraction

### `trajectory_solution.gd`

Currently acts as a compatibility container, not a modular prediction model.

Additional concrete issues:

- Moon-specific fields are still first-class instead of living in a target-body encounter structure.
- Display-only fields and analysis-only fields live together without separation.

Cleanup implication:

- Later replace with something closer to:
  - predicted path data
  - per-body encounter summaries
  - display horizon metadata

### `simulation_state.gd`

The registry exists, but the file still carries both the new and old worldviews at once.

Additional concrete issues:

- Legacy fields (`planet_*`, `moon_*`) are still widely exposed as if they are the source of truth.
- The file still owns:
  - body registry
  - body evolution
  - gravity
  - targeted warp state
  - sim time stepping
- `_sync_legacy_body_fields_from_registry()` is still a necessary compatibility bridge, but it is also now a major piece of technical debt.

Cleanup implication:

- Keep the compatibility layer during migration, but actively shrink direct callers of legacy fields.
- The long-term split should still be:
  - `body_registry.gd`
  - `rail_orbit_system.gd`
  - `gravity_field.gd`
  - `targeted_warp_controller.gd`

### `scenes/navball.gd`

This is in better shape after Level 2, but it still couples rendering math and reference-body selection tightly.

Additional concrete issues:

- It still computes all orbital-frame marker math inline.
- There is no reusable "orbital frame" helper for:
  - prograde/retrograde
  - radial in/out
  - normal/anti-normal

Cleanup implication:

- If more instruments appear later, navball math should move into a shared orbital-frame helper instead of staying UI-local.

### `scenes/trajectory_info_label.gd`

This is mostly a passive view, but it is tightly coupled to `trajectory_map.gd`.

Additional concrete issues:

- It polls a large number of stringly named methods from the map every frame.
- It reflects the map's current mixed responsibilities rather than a dedicated data source.

Cleanup implication:

- Later this should read from a smaller structured telemetry object instead of calling dozens of methods on the map.

### `player.gd`

Still one of the main input-coupling hotspots.

Additional concrete issues:

- It knows trajectory-computer keyboard controls directly.
- It also owns crosshair presentation, interaction focus, zoom focus, and hold-repeat timing.

Cleanup implication:

- Trajectory-screen key handling should still move out before Level 3 gets much deeper.
- Otherwise the player script will continue to be a hidden dependency of map behavior.

### `body_render.gd`

This is already a good Level 1 result, but note one future cleanup point.

Additional concrete issue:

- It updates in both `_physics_process()` and `_process()` to stay visually synchronized, which is acceptable for now but should eventually be reviewed once the sim/render ownership is cleaner.

Cleanup implication:

- Keep as-is for stability now.
- Revisit only after camera/render sync behavior is more formally owned elsewhere.

### `map_revert.gd`

This is intentionally legacy.

Additional concrete issue:

- It is a rollback snapshot, not an actively maintained script.

Cleanup implication:

- Do not treat it as a migration target.
- If the project stabilizes enough later, archive or remove it deliberately rather than letting it drift silently.
