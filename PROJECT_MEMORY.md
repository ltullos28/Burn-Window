# Burn Window Project Memory

## Concept

Burn Window is a cockpit-focused orbital navigation game in Godot 4.

The player is confined to a small spacecraft cockpit and navigates primarily through instruments rather than direct visual piloting. The intended feel is closer to `Iron Lung` with orbital mechanics than to a clean, player-friendly `KSP` interface.

Design priorities:

- Diegetic controls and displays
- Tactile, physical cockpit interaction
- Retro-futuristic, dinky, old-computer aesthetic
- Limited information and indirect situational awareness
- Orbital navigation as the core activity

The game currently has no mission/gameplay objective yet; the focus so far is on building the core systems and cockpit experience.

## Player Experience

The player does not freely move around the world. They remain seated in the cockpit and:

- Look around with constrained first-person camera controls
- Interact with controls using a raycast and an interact key
- Zoom into instruments and the forward window
- Use cockpit hardware to understand and modify their trajectory

The window is intentionally not enough for navigation by itself. The flight computer and cockpit instruments are meant to be necessary.

## Current Active Systems

### Core Simulation

- `SimulationState` is an autoload and owns the orbital sim state.
- The planet and moon are on rails.
- The ship is affected by n-body gravity from the planet and moon.
- Ship translation and rotation are handled in `scenes/ship.gd`.
- `SimulationState` now has a first-pass internal body registry (`bodies["planet"]`, `bodies["moon"]`) that stores per-body radius, gravity, mu, position, velocity, up vector, parent body, and orbit metadata while still syncing the older hard-coded `planet_*` / `moon_*` fields for compatibility during the transition.

### Player / Interaction

- `player.gd` is a seated first-person controller.
- Interaction is raycast-based through `InteractRay`.
- Crosshair changes contextually for normal, interact, and zoom targets.
- Zooming moves the camera to predefined `Node3D` anchors on instruments or the window.

### Cockpit Controls

- Pitch, yaw, and roll are controlled through physical cockpit buttons/levers.
- Thrust is a hold interaction, not a toggle.
- Thrust triggers ship acceleration, engine audio, and camera feedback.
- `interact_button.gd` is the main interaction dispatcher for cockpit controls.

### Navball

- `scenes/navball.gd` drives the 3D navball.
- It shows orientation and orbital reference markers similar to KSP:
  - Prograde / retrograde
  - Radial in / out
  - Normal / anti-normal
  - Nose marker

### Trajectory Computer

- The active trajectory computer script is `game/new-game-project/trajectory_map.gd`.
- The old root-level `trajectory_map.gd` is obsolete and deleted.
- The trajectory computer renders inside a `SubViewport` and is shown on the cockpit CRT screen.
- The trajectory computer supports:
  - `PLAN` mode: top-down orbital projection
  - `EQUATOR` mode: inclination / orbital plane instrument
  - Zooming
  - Center/focus cycling
  - Refresh / reveal animation

Trajectory computation combines:

- `trajectory_predictor.gd` for forward simulation
- `orbit_solver.gd` for orbital classification and classical orbit values
- `trajectory_solution.gd` as the result container

Important current behavior:

- The ship trajectory is predicted forward in time.
- Dynamic prediction length depends on zoom, orbit period, and moon-encounter heuristics.
- Moon encounters are detected and tracked.
- In moon focus mode, the moon-dominant portion of the trajectory is duplicated into moon-relative space so the player can inspect the encounter locally.
- In moon focus mode, the intended behavior is a seamless transition: planet-frame approach up to lunar dominance entry, then moon-frame orbit as the primary displayed path with moon PE/AP markers.
- While zoomed into the trajectory computer in `PLAN` mode, the player can move a warp-selection box along the predicted trajectory with keyboard controls.
- The selection step size is a fraction of the current prediction length, so it scales automatically with map zoom / prediction depth.
- The timewarp selector is relative to the ship's current live place on the predicted path; `T+0` should stay on the ship even if the player coasts without refreshing.
- Once a targeted warp begins, that selector reference freezes so the destination marker does not keep drifting forward with the ship during the warp itself.
- Confirming the selection starts a targeted time warp toward the selected future prediction time and stops automatically on arrival.
- During active warp, the trajectory computer enters a dedicated `BENDING TIME...` state and reuses the computer refresh/beep audio for feedback.
- Timewarp is now explicitly gated behind an in-screen toggle; when disabled, the warp selector and its key legend collapse away and the bracket/enter/escape controls are inactive.
- `trajectory_map.gd` now caches expensive trajectory geometry analysis (main ship runs, moon-local runs, moon ghost points, moon local PE/AP indices) and reuses it across frames; only the live overlays such as ship/mood dots, vectors, selector, and text are recomputed every frame.
- The moon-local cached trajectory is stored in moon-relative space and re-anchored to the live moon each frame so it does not drift away as the moon moves.
- In `VIEW: MOON`, if the moon-local segment is an escape rather than a sustained local orbit, the map now draws a short post-dominance tail outside the moon-dominant segment in a separate color so it is clearer where local influence ends.
- Moon-local AP detection also has a circular-orbit fallback: if no clean local maximum is found, it can infer AP as roughly half a detected local loop after moon-local PE.
- Prediction horizon now distinguishes between planet-scale and moon-local situations: moon-dominant/captured cases intentionally use a much shorter local forecast so the map does not draw excessive repeated loops.
- Prediction length is also trimmed by orbital continuity for moon-local cases when useful, so captured moon orbits do not overdraw repeated loops.
- The moon-local continuity trim uses a chunked 3D return-to-start test: once the path clearly leaves the start neighborhood, it scans future chunks for a return within a closure threshold and then trims shortly after that return.

### Prediction Horizon Logic

The trajectory computer no longer uses one fixed "draw this far" rule.

Instead, `trajectory_map.gd` chooses a prediction horizon in layers:

1. It first chooses a broad initial step budget.
   - In normal planet-focused situations, that broad budget still considers zoom level and orbit period so large transfer-like trajectories can draw farther.
   - In moon-dominant situations, it switches to a moon-local budget instead of reusing the large planet-style one.

2. In moon-dominant situations, the budget becomes local-orbit aware.
   - If the ship looks moon-captured, the computer aims for about one moon-local orbital period plus a small margin.
   - If the ship looks like it will escape the moon, the computer uses a shorter local escape horizon instead of drawing far into the future.

3. After that initial budget is chosen, the computer tries to trim redundant repeated loops.
   - It converts the predicted path into positions relative to the current reference body.
   - It defines a closure threshold based on orbit size.
   - It ignores the early samples until the path clearly leaves the starting neighborhood.
- It then scans forward in chunks, looking for the first chunk that returns close enough to the starting point in full 3D distance.
- The closure threshold is adaptive: it scales both with orbit size and with the local sample spacing so clean circular orbits are less likely to miss first-pass closure just because of coarse sample steps.
- When it finds such a chunk, it checks inside that chunk and chooses the closest matching sample within the threshold.
- The final horizon is cut shortly after that point, using an extra tail equal to one sixth of the closure sample index.
- Once a moon-local closure point is positively found, that trimmed horizon is no longer forced back up to the normal broad minimum step floor; the closure result wins, subject only to basic safety and max-step caps.

The practical goal is:

- large, changing transfer trajectories can still draw long enough to be informative
- small, nearly closed orbits should usually draw about one loop rather than many repeated loops
- moon-local capture cases should not spam thick repeated circles
- switching back to planet/ship view from a moon orbit should also be less noisy because the underlying prediction horizon is already shorter

### Flight Computer Readout

- `scenes/trajectory_info_label.gd` provides a separate information readout for:
  - Orbit classification
  - PE / AP
  - Eccentricity
  - SMA
  - Period
  - Closest approaches
  - Ship state
  - Zoom level

### Audio / Atmosphere

- `engine_audio.gd` handles engine loop and mechanical rattles during thrust.
- `ambient_loop.gd` handles ambient looping audio.
- `random_sound_pool.gd` adds intermittent cockpit ambience.
- Button interactions use shared cockpit audio.

### Visual Tone

- CRT styling is handled with `scenes/main.gdshader`.
- The cockpit uses retro computer visuals: curvature, scanlines, glow, barrel distortion, vignette.
- `starfield.gd` creates a surrounding star sphere centered on the player.
- Body visuals are now unified under `body_render.gd`, with `planet_render.gd` and `moon_render.gd` reduced to thin wrappers that set the body key.
- `SimulationState` now exposes generic body lookup helpers (`has_body`, `get_body_position`, `get_body_radius`, etc.) as the first step toward a future body registry.
- The body render flow still updates in both `_physics_process()` and `_process()` so cockpit window visuals stay synchronized with the orbital simulation during targeted warp and other fast updates.

### Level 2 Generalization Progress

- `SimulationState` now has generic helpers beyond simple body lookup:
  - `is_body_on_rails(...)`
  - `get_body_state_at_time(...)`
  - `get_dominant_body_name_at(...)`
  - `get_ship_reference_body_name()`
- `trajectory_predictor.gd` now sources future body states and gravity contributors through those registry-backed helpers instead of relying entirely on bespoke planet/moon-only state code.
- `navball.gd` now selects its reference body through `SimulationState.get_ship_reference_body_name()` and generic body position/velocity accessors.
- `SCRIPT_PARTITION_PLAN.md` now contains a dedicated Level 2 migration inventory listing the scripts that still carry the old hardcoded two-body philosophy and the remaining work in each.

## Scene / Architecture Notes

- `hierarchy.json` is generated on game startup and should be treated as a useful current snapshot of the node tree.
- The main scene exports that hierarchy through `scenes/export_scene_heirarchy_to_json.gd`.
- The active trajectory map lives under the cockpit computer viewport, not at repo root.
- `button_glow.gd` is legacy and currently unused.
- `SCRIPT_PARTITION_PLAN.md` records the current recommended split lines for the large scripts, especially `trajectory_map.gd` and `simulation_state.gd`, so level 2 refactoring can happen deliberately instead of ad hoc.

## Design Guidance For Future Work

When implementing new features, prefer:

- Physical cockpit affordances over abstract UI
- Instrument readouts over omniscient player information
- Characterful, imperfect, old-machine behavior over polished modern UX
- Systems that preserve tension, uncertainty, and confinement

Avoid drifting toward:

- Clean sandbox-space-sim convenience UI
- External HUD-heavy design
- Overly transparent or gamey “easy mode” instrumentation unless explicitly intended

## Current Development Status

The project is still in core systems / cockpit instrumentation development.

Already implemented in meaningful form:

- Seated player controller
- Raycast interaction
- Zoom/focus system
- Cockpit attitude controls
- Thrust interaction
- Engine feedback
- Navball
- Orbital simulation
- Trajectory computer
- Targeted trajectory timewarp selection
- CRT display presentation

Not yet established:

- Final mission structure
- Broader gameplay objectives
- Full navigation gameplay loop beyond operating the systems themselves
