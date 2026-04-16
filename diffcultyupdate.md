# Difficulty Update Plan

## Goal
Add a first-pass difficulty-driven challenge layer to gameplay so the selected menu difficulty changes:
- the starting scenario
- the challenge targets
- the on-screen checklist the player uses during a run

## Script-Grounded Constraints
- The current orbital system supports circular child-body orbits around a parent.
- The current child-body system does not yet support true inclined moon orbits.
- Because of that, this pass will scale difficulty with:
- moon orbital phase and distance changes
- ship starting orbit changes
- stricter closest-approach objectives

## Features To Add
- Persist the selected difficulty from the title screen into gameplay.
- Add a central scenario/missions data source for Easy, Normal, and Hard.
- Name the system bodies for the first mission:
- planet: Nacre
- inner moon: Cinder
- outer moon: Veil
- Apply different starting scenario values per difficulty.
- Add a gameplay checklist UI on the left side of the cockpit view.
- Track objective completion using actual closest approach during flight.
- Show each objective with an empty checkbox that fills when completed.

## Difficulty Structure
- Easy
- Coplanar, more forgiving start
- Larger closest-approach windows
- Simpler moon phase setup
- Normal
- Less favorable alignment
- Tighter closest-approach windows
- Slightly more awkward ship start
- Hard
- Most awkward setup of the three available difficulties
- Tightest closest-approach windows
- Hardest starting alignment for this first pass

## Objectives For This Pass
- Reach a close encounter with Cinder.
- Reach a close encounter with Veil.
- Use closest surface approach thresholds instead of just entering each moon’s sphere of influence, so the list feels more intentional and measurable.

## Implementation Steps
1. Add a global gameplay session singleton to hold the selected difficulty, body display names, scenario data, and mission progress.
2. Write the first mission definitions for Easy, Normal, and Hard.
3. Pass the selected difficulty from the menu before gameplay starts.
4. Make SimulationState reset into the correct difficulty scenario.
5. Add a checklist scene to gameplay.
6. Track closest approach in real time and mark objectives complete when the threshold is met.
7. Surface the active difficulty and objective state in the checklist UI.

## Notes For Tuning Later
- Resource amounts and drain rates are intentionally left easy to tune later.
- The locked difficulty can be saved for a future scenario once more advanced orbit variation is supported.
