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
| Class skill VFX (art/vfx/class_skills, daiyooo-vfx GLB) | <= 300 draw calls per effect instance; pooled + prewarmed (client/skills/class_skill_vfx.gd). MET 2026-11-13: worst is arcane_orb ~97 per copy, crater_leap ~77 (was 2264) |
| Status VFX (art/vfx/status, daiyooo-vfx GLB) | <= 40 draws per instance, at most 3 per fighter (head + feet + immune ring); slimmed like class skill VFX, prewarmed once (client/status_vfx.gd). No status may tint the body. MET 2026-11-14: 1-16 draws per look (sleep 16, burn 11), worst fighter ~27 |
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


### Draw-call fix, 2026-11-13 (tech-artist)

Cause: a daiyooo GLB plays each particle as an 8-phase flipbook and hides the off phases by scaling them to
0.0001, so every phase of every particle was drawn every frame. `ClassSkillVfx._slim` (client only) turns those
scale keys into discrete `visible` keys at load (once per skill, shared by the pool) and turns off shadow casting.
Pixel-identical to the raw clip (0 differing pixels over 5 effects x 5 frames, `tools/perf/class_skill_vfx_frames.gd`).
On top, crater_leap / hook_sweep / starfall / intercept / iron_guard were regenerated with fewer particles
(same preset, palette, light; recipes in their recipe.json). Native draws x3 copies after: crater_leap 225,
hook_sweep 186, starfall 195, intercept 138, iron_guard 54, breaker_slam 117, reaping_arc 78, heartseeker 183,
arcane_orb 291. Web 844x390 real battle (Chrome, RTX 3070 Ti, 2 runs each): 26.8 fps -> 30.7 fps average;
VFX off 34.2 fps. Frames with crater_leap live 18.6 -> 30.0 fps, hook_sweep 20.1 -> 30.8, iron_guard 23.1 -> 26.8.

## Status VFX, measured 2026-11-14 (tech-artist)

`tools/shots/status_vfx_measure.gd` (headless, peak meshes drawn over 1.5 s after slimming / meshes in the GLB):
stun 5/40, sleep 16/32, shock 8/64, burn 11/88, poison 6/48, bleed 6/48, slow 7/56, sunder 6/48, debuff 1/8,
regen 5/40, buff 1/8, immune 1/8 (the buff ring tinted cyan at load, no extra asset). A fighter shows at most one
head loop (stun or sleep), one feet loop and the immune ring (worst fighter ~28 draws). The hit flash is the
only whole-body colour: 0.08 s at 18% white, at most once per 0.3 s (client/fighter_view.gd FLASH_*).
Web FPS with statuses on is not measured yet (needs a phone run).

## Card ink-wash look, measured 2026-11-14 (tech-artist)

Hub, 4 live cards (`client/card_portrait.gd` -> studio05 `card_ink`, toggle `CardTokens.PORTRAIT_INK`). Native Windows,
GL Compatibility, uncapped, `tools/perf/hub_fps.gd` with `ZORX_CARD_INK=0/1` run alternately (4 runs each):

| | 1920x1080 avg fps (p1 ms) | 1280x592 avg fps (p1 ms) | draws, 4 cards | prims, 4 cards |
|---|---|---|---|---|
| ink off | 355 (4.8) | 374 (4.3) | 45 | 107k |
| ink on | 340 (4.8) | 349 (4.4) | 74 | 180k |
| ink on v2 (bold line 0.0105, min 1.8 px, inner lines, 2-band cel) | 354 (4.7) | 337 (4.5) | 74 | 180k |

Budget for a hub card: <= 20 draws and <= 50k prims per card portrait (worst now 20 / 47.7k, longbow / greatsword).
The ink line is one back-face hull per visible piece (same mesh, no copy), so it doubles a card's triangles.
Off/on in v2 (4 alternating runs each): 376/354 at 1920x1080 and 352/337 at 1280x592. The inner lines are screen-space
derivatives in the toon fragment shader (no extra pass, no extra draws).
Web/phone not measured yet (OPEN): if a phone drops, keep the hulls on body/hair/head only.

## Download, measured 2026-11-14 (tech-artist)
Budget: first load (engine + core + boot packs, one texture format) <= 50 MiB; battle packs <= 25 MiB (background).
Per device (s3tc), pipeline/build_web.py: 491a821 boot 70.2 / battle 21.1 MiB -> now boot 41.4 / battle 22.3 MiB.
Rules (tests/test_ui_import_budget.gd guards art/ui/): UI images lossy (compress/mode=1, q 0.8) above 512 px,
size_limit (<= 2048) above 1024 px, no mipmaps. 3D colour/normal maps: lossy 0.85 + size_limit 1024 (or VRAM when
used only in 3D); never lossless 2048. Battle-only art (status/class VFX, monsters, maps) goes in a battle pack
(tools/web/pack_layout.json), never core. Unused art goes in the Web preset exclude_filter.
Biggest left: body_<class>.glb 9.5 MiB of the characters pack, ~98% animation (47-51 clips each, about half unused).

## Landing site 3D trail v2, measured 2026-11-14 (tech-artist)
zorx.daiyooo.com (`server/landing/dashboard/trail.js`, three.js r165). Headless Edge 157 on an RTX 3070 Ti (ANGLE D3D11),
vsync off. "Phone" = mobile emulation at DPR 3 with 4x CPU throttling (a proxy, not a real phone). Draw calls are
counted per frame by wrapping `drawElements*`/`drawArrays*`. Raw data and screenshots: `art_source/codex_review/landing_trail_v2_2026-11-14/` (perf_before.json, perf_after.json).

| per stop 01..07 (08 = new login stop) | before (trail3d-20261114) | after (v2) |
|---|---|---|
| draw calls, desktop 1920x1080 | 75 109 105 108 90 50 27 | 93 77 55 52 40 33 26 / 20 |
| draw calls, phone portrait | 44 96 105 88 90 45 27 | 74 68 52 49 37 27 23 / 13 |
| triangles drawn, desktop | 24-27 k | 239 k at the campfire, 44-50 k elsewhere |
| triangles drawn, phone portrait | 19-21 k | 212 k at the campfire, 18-23 k elsewhere |
| desktop mean frame (uncapped) | 0.26-0.48 ms | 0.33-0.79 ms (campfire 0.79) |
| phone-proxy mean / p95 frame | 2.0-3.8 / 3.8-6.7 ms | 2.3-5.3 / 4.2-7.6 ms (campfire 5.1-5.3 / 7.3-7.6) |

The campfire is the most expensive stop: four skinned characters (~23 k triangles each) drawn twice (fill + ink
outline). They are frustum-culled by hand (three.js does not cull skinned meshes) and their animation stops off screen.

**Trail v3 (2026-11-15, Boss: two stops, 01 CAMPFIRE + 02 LOGIN).** Stops 02-07 and their props/columns/inspect
are gone, the login fort moved from z -112 to z -10, trees/rocks/grass only cover z 24..-46 (desktop 92 trees, phone 62).
Same rig and method; raw data `art_source/codex_review/landing_trail_v3_2026-11-15/perf_before.json`, `perf_after.json`.

| view | campfire draw calls before -> after | login draw calls before -> after | campfire tris | login tris |
|---|---|---|---|---|
| desktop 1920x1080 | 93 -> 77 | 20 -> 20 | 239 k -> 212 k | 44 k -> 18 k |
| phone landscape (932x430 @3) | 90 -> 79 | 17 -> 17 | 213 k -> 201 k | 17.6 k -> 7.3 k |
| phone portrait (430x932 @3) | 74 -> 70 | 13 -> 13 | 212 k -> 201 k | 17.6 k -> 7.3 k |

Mean frame, desktop campfire 0.67 -> 0.55 ms, login 0.27 -> 0.30 ms. Phone proxy (4x CPU throttle) campfire mean
4.6-6.0 ms both before and after (run-to-run noise: two repeat runs gave 4.6-6.0 ms before, 5.8-6.0 ms after), p95
7.2-8.9 ms, under the 16.7 ms frame. Most campfire cost is the squad (4 x ~23 k triangles x fill + outline).

Budget for the landing page (keep to these):
- All four squad GLBs together <= 2.5 MB (now 2.31 MB: human 528 KB, viking 569 KB, elf 570 KB, runeborn 648 KB),
  loaded after the first frame; <= 512 px WebP base-colour textures only; one idle clip each; 22-27.5 k triangles per
  character, 5-7 meshes each (same-material gear joined in `tools/landing/build_landing_squad.mjs`).
- Draw calls <= 100 at any stop (worst now: the campfire, 77 desktop / 79 phone landscape, v3). Every outlined object costs 2 draws; station props are baked into one mesh per station
  (fill + outline = 2 draws), scenery is instanced (1 + 1 outline).
- Phones (`pointer:coarse` or <= 640 px): pixel ratio <= 1.25, no MSAA, no outline on trees/rocks/columns, fewer
  trees/grass/embers. Desktop: pixel ratio <= 1.6, MSAA, all outlines.
- Target 60 fps on desktop and on a mid phone; not verified on a real phone yet.
