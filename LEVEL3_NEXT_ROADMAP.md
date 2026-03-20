# Level 3 Next Roadmap

This roadmap tracks what was completed during the major Level 3 generalization pass, what still remains, and what the practical path looks like to reach truly addable future bodies.

It should be read together with:

- [LEVEL3_HANDOFF.md](/T:/Burn%20Window/LEVEL3_HANDOFF.md)
- [SCRIPT_PARTITION_PLAN.md](/T:/Burn%20Window/SCRIPT_PARTITION_PLAN.md)
- [PROJECT_MEMORY.md](/T:/Burn%20Window/PROJECT_MEMORY.md)

## Status Summary

We are now in late Level 3.

The map/cache/encounter side is largely generalized.
The remaining old philosophy is concentrated in:

- body registration still being hardcoded in `simulation_state.gd`
- UI/focus still assuming one special `MOON` view shell
- some remaining moon-named fallback interfaces and compatibility naming
- the lack of a real user-facing process for adding/selecting new bodies

## Completed

These items are materially accomplished and should be treated as done unless regression work is needed.

### 1. Predictor-side generalization

Completed:

- `trajectory_predictor.gd` now produces generic `body_predictions`
- predictor inner loop no longer relies on moon-only dictionary arrays
- body predictions now carry:
  - `body_name`
  - `parent_body_name`
  - `relative_points`
  - `dominance_mask`
  - `closest_approach`

Compatibility state:

- legacy moon outputs are still emitted from the generic prediction result as compatibility outputs

### 2. Focused-child / body-scaled horizon policy

Completed:

- `prediction_horizon.gd` now operates in terms of focused child body policy
- body radius / `mu` are now used in horizon policy
- map exports now expose focused-child policy values instead of only moon-named policy values

Compatibility state:

- moon-named policy concepts still remain in some naming/fallback surfaces

### 3. Map/cache compatibility bridge removal

Completed:

- legacy moon fields were removed from `trajectory_solution.gd`
- moon mirror cache keys were removed from `trajectory_projection_cache.gd`
- duplicate `cached_moon_*` bridge state was removed from `trajectory_map.gd`
- real architecture path is now:
  - generic body prediction
  - per-body encounter data
  - focused-child cache surface
  - focused-child map rendering/querying

### 4. Rail-body runtime evolution generalization

Completed:

- `simulation_state.gd` no longer uses a one-off `_update_moon_state()` runtime path
- runtime now updates all on-rails bodies through generic registry-driven rail evolution
- `_rebuild_body_registry()` now uses reusable registration/orbit helpers

Compatibility state:

- body registration is still hardcoded in code
- moon exports still exist as compatibility-facing setup values

## What Still Remains

These are the main blockers before the architecture can honestly be called body-agnostic enough for practical new-body addition.

## Step 1

Make body registration data-driven instead of hardcoded in `simulation_state.gd`.

Target:

- stop manually adding bodies in `_rebuild_body_registry()`
- define bodies from reusable body-definition data
- allow body parent/orbit setup without writing new code paths

Likely forms:

- exported array of dictionaries
- custom resource for body definitions
- child-node driven registration helper

Recommended target shape for a body definition:

- `body_name`
- `radius`
- `surface_gravity`
- `up`
- `parent_body_name`
- `orbit_mode`
- `center_distance`
- `phase`
- optional speed overrides
- optional static/manual position mode

## Step 2

Generalize focused-body selection beyond the one special moon shell.

Target:

- map/query code should be able to focus a selected child body
- not just “the moon”
- current `PLANET`, `MOON`, and `SHIP` cockpit modes can remain temporarily, but the underlying focused-child target must become selectable

Needed decisions:

- how the map chooses the active child body when there are multiple candidates
- whether this is automatic, manual, or hybrid
- how the UI labels the selected body

## Step 3

Generalize multi-body encounter prioritization.

Target:

- if more than one child body is relevant in a forecast, define rules for:
  - which encounter gets local markers
  - which body gets focused
  - whether the system swaps focus automatically
  - whether the user can lock focus

This is the step that prevents “multiple bodies exist” from degenerating into ambiguous display behavior.

## Step 4

Remove remaining moon-specific compatibility naming where practical.

Examples still left:

- moon-facing UI getter names that are now thin wrappers over generic data
- default focused-child assumptions set to moon
- any remaining moon fallback reads in predictor/horizon/map interfaces

This is mostly cleanup after Steps 1-3.

## Practical Workflow For Adding A New Body

This is the intended process we should be designing toward.

### Current near-term target workflow

1. Create a celestial body definition.
2. Give it a unique `body_name`.
3. Define physical parameters:
   - radius
   - surface gravity
   - up vector
4. Define hierarchy position:
   - choose `parent_body_name`
5. Choose orbit behavior:
   - static body
   - circular on-rails orbit
   - later: more advanced orbit modes if added
6. Enter orbit-on-rails parameters:
   - center distance
   - phase
   - optional speed overrides if supported
7. Let `SimulationState` build it into the registry automatically.
8. Let runtime rail evolution update it automatically.
9. Let predictor emit a body prediction record for it automatically.
10. Let the map choose or allow selection of that body as the focused child body.
11. Verify:
   - gravity affects ship correctly
   - dominance logic works
   - encounter markers appear when relevant
   - body renders in hierarchy correctly

### Desired future user-facing workflow

The user should eventually be able to do something like:

1. Make a new celestial body object/resource.
2. Fill in physical parameters in the inspector.
3. Set parent in hierarchy.
4. Set orbit-on-rails parameters in the inspector.
5. Launch and see it automatically:
   - registered
   - simulated
   - predicted
   - selectable/focusable

That is the practical target we should keep steering toward.

## Recommended Next Order

1. Make body registration data-driven in `simulation_state.gd`
2. Generalize focused-child selection / view targeting
3. Add multi-body encounter prioritization rules
4. Remove remaining moon-specific compatibility naming and defaults

## Short Version

The hard part of Level 3 map/prediction architecture is largely done.

The next phase is no longer “make moon less special inside the map.”
It is:

- make bodies addable without hardcoding them
- make the system able to choose/focus among multiple child bodies
- make the remaining compatibility naming stop mattering
