# Performance budget (tech-artist, 2026-11-10)

Web is the main target (WebGL2, GL Compatibility, no threads, no shader cache between sessions).
Measure with `tools/perf/goblin_stage_render_measure.gd` (draw calls / primitives / map-art share per camera
spot, optional `--breakdown`, `--shots=`) and `tools/perf/stage_entry_profile.gd` (scene-entry frame times).
Both need a window. The measure script writes `user://graphics.cfg`: delete it afterwards.

## Targets

| Item | Budget |
|---|---|
| Web desktop | 60 fps target, 30 fps floor (frame p50 <= 33 ms) at render scale 1.0 |
| Web mobile | 30 fps at render scale 0.5, outline/glow allowed off |
| Goblin_base stage scene (static art, `art/maps/goblin_base/manifest.json`) | <= 60k instanced tris, <= 16 surfaces (test_goblin_base_render_budget.gd) |
| Map art actually drawn per camera spot | <= 50k prims, <= 15 draw calls |
| Regular monster (complete, with weapon) | <= 4.5k tris target (current goblins 8.6-10.6k, see goblin_wave_gpu_audit.md) |
| Player character | <= 60 draw calls with outline (currently ~192, OPEN) |
| Materials per prop model | 1 (shared kit atlas or vertex colours) |
| Effect nodes per hit | pooled; prewarmed at load (Effects.prewarm, presenter.warm_build, telegraph quad) |
| Class skill VFX (art/vfx/class_skills, daiyooo-vfx GLB) | target <= 300 draw calls per effect instance; pooled + prewarmed (client/skills/class_skill_vfx.gd). OVER: crater_leap 2264, hook_sweep 1656, starfall 1328, arcane_orb 568, intercept 688 (2026-11-13, see below) |
| Scene entry | no single frame over 1 s after the loading label (currently OPEN, see below) |

## Measured 2026-11-10 (native M1, GL Compatibility, 1920x912, MSAA 4x, glow, outline, scale 1.0)

goblin_base_quarry, 8 goblins + player, start / north camera spot:

| | draw calls | primitives | map art dc / prims |
|---|---|---|---|
| before (06d77bf scenes) | 391 / 377 | 179.6k / 168.5k | 11 / 42.0k, 14 / 50.3k |
| after | 378 / 369 | 162.9k / 165.7k | 10 / 25.5k, 14 / 47.6k |

Whole-frame breakdown (before, start spot): player 192 dc / 33k prims; 8 goblins ~54 dc / ~98k prims;
map art 11 dc / 42k (the 06d77bf crate/stone/log/grass/fern dressing is only 5 dc / 7.4k); hidden collider
boxes 12 dc; the rest is HUD/2D/post. The ink outline pass is the largest single cost: outline off gives
266 dc / 89k prims and roughly halves the render time (render CPU 72-82 ms -> 34-39 ms on this machine).
MSAA 0/2/4 and glow on/off made no measurable difference natively (bound by draw submission/vertex work, not
fill); this needs confirming on the Web build on a PC GPU before changing defaults.

Scene entry (quarry, native): before _ready 0.96 s, _ready 0.57 s, first draw 5.75 s (2.5 s again on a second
entry in the same process). On the Boss's web PC this showed as one 18 s frame. OPEN: needs a GPU/WebGL trace.

## Class skill VFX, measured 2026-11-13 (tech-artist)

Native per effect, 3 copies looping, `tools/perf/class_skill_vfx_cost.gd` (Windows, RTX 3070 Ti, gl_compatibility, vsync off):
draw calls x3 / extra ms: crater_leap 6792 / +14.4, hook_sweep 4968 / +10.6, starfall 3984 / +8.0, intercept 2064 / +4.0,
arcane_orb 1704 / +3.2, heartseeker 1296 / +2.4, battle_trance 1176 / +2.3, shield_rush 1128 / +2.3, the rest <= 936 / <= +1.6.
Every mesh in these GLBs is its own MeshInstance3D + material (8 "phase" textures per layer), so cost = draw calls.
Web (Chrome, same PC, 1280x720 and 844x390, real 3-card battle): see the PO report; the A/B switch is `play.html?class_vfx=0`.

