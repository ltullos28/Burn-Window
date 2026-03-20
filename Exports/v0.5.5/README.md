BURN WINDOW V0.5.5

1. Generalized the trajectory/map architecture from hardcoded planet + moon logic toward focused-child/per-body encounter handling.
2. Extracted major trajectory_map.gd responsibilities into helpers: timewarp selection, body-focus/projection, prediction horizon policy, local orbit marker analysis, geometry cache construction, and impact trimming.
3. Added generic per-body prediction/encounter data flow (body_predictions, per-body encounter records, focused-child cache surfaces) and removed most moon-only cache/solution mirrors.
4. Fixed multi-body child-view ownership so each child body only shows its own valid local duplicated segment and markers.
5. Generalized SimulationState rail-body evolution and added resource-driven celestial system definitions via default_celestial_system.tres.
6. Added generic impact handling on trajectories, red X impact markers, impact audio timing, and gated timewarp/death/reset behavior around impacts.
7. Improved moon/local marker behavior across edge cases: PE/AP fallback, CA/ESC state logic, escape-tail behavior, and near-closed/discontinuous local orbit handling.
8. Optimized large-trajectory performance with adaptive visual decimation, stricter continuity trimming, redraw gating, and projected-render caching to reduce steady-state reprojection cost.

THANKS TO:
-Chicksen (tester)
-Jronz (tester)