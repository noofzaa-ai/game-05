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
| Violent skill looks (client/vfx/violence.gd + violent_vfx.gd, data/combat/vfx.json "violence" + violent/*; shipped at L3 2026-11-19 on every race ultimate, class skill and mummy boss move) | per blow <= 13 drawn layers full / <= 9 phone, <= 32 particles per burst, no ground decals, flash <= 0.12 s and <= 0.16 alpha, at most 1 flash per 0.9 s, phones at most 3 violent blows a second; no new art files; pooled; prewarmed only for the active level. Boss wave: full <= +15% frame p50, phone variant <= +1-2 ms web. MET 2026-11-19 (below) |
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

## Hero ink look in battle, measured 2026-11-15 (tech-artist)

Boss: heroes keep the cards' ink look in battle (`client/draw_style/draw_style.gd` hero_ink/dress_hero, studio05
`card_ink` with `ink_line_world` 0.014 m, 2.0-4.5 px). On for drawn_style on/lite (default on), off for "off".
Tool: `tools/perf/battle_fps.gd` (3-card squad, wave journey seed 7, 1280x720, render scale 0.5, native Windows).
Exact A/B: the same frozen frame with the hero hulls and card_ink on, then off. Mean of 3 runs:

| view | draws off -> on | prims off -> on | fps off -> on |
|---|---|---|---|
| overview | 276 -> 333 (+57) | 499k -> 568k | 229 -> 198 |
| follow (zoomed on hero 1) | 315 -> 341 (+26) | 731k -> 795k | 207 -> 185 |

(VFX keep animating while the fight is frozen, so these draw counts carry some noise.) Exact cost per hero, counted on
the models: ink hulls = 12 / 18 / 20 / 12 draws and 12.5k / 12.1k / 13.5k / 12.7k tris (sword_shield / greatsword /
longbow / magic). Phones (web_android / web_ios / mobile, or `-- --phone-ink`) skip pieces under 400 tris except
weapons, head and hair: 5 / 8 / 10 / 8 draws and 10.6k / 10.1k / 11.1k / 11.7k tris; the outer outline stays.

Budget: <= 22 extra draws per hero (one hull per visible piece, 12-20 pieces; phones 5-10) and <= 14k extra tris per
hero. The live (unfrozen) fight varies more between runs than this cost. Phone web not measured yet (OPEN).


## Battle lag on the web, measured 2026-11-15 (tech-artist)

Boss: the auto-battle feels laggy on staging. Rig: local web export of this branch served from localhost, Chrome
(ANGLE D3D11, RTX 3070 Ti, vsync off), 1280x720, render scale 0.5, 3-card squad (sword_shield/human, greatsword/viking,
longbow/elf), goblin_waves seed 7. Probe: `tools/perf/battle_fps.gd` (native) and the same code as a temporary autoload
in the web export (`?perfprobe`, `?perfprobe&series`; not committed). Per-frame split = physics (sim + stage tick),
process (scripts' _process), draw (render submit until frame_post_draw).

Before (web, desktop): live fight 19.6 fps overview / 29.8 follow; split physics 17.8 ms + process 4.6 + draw 27.8
at ~400 draw calls. Over a whole run it got worse: 26 fps in wave 1, 11-16 fps from ~3 minutes on, with
every frame over 50 ms (series windows of 120 frames: hitches50 = 120/120).

Causes, by impact:
1. Fallen enemies were never removed: solo wave journeys keep every dead enemy in the sim, and its hidden view kept
   posing its model, AnimationPlayers and status loops each frame. 30-70 corpses by the late waves; node count 5k -> 12k+.
   Fixed (client/fighter_view.gd: a hidden view disables its subtree and frees its status VFX; show_state skips it).
2. Sun shadow in 4 PSSM splits: each caster drawn into every split. Frozen battle frame 396 -> 255 draw calls,
   549k -> 398k prims (native 171 -> 201 fps). Fixed: one orthogonal map (client/atmosphere.gd); shots in
   art_source/codex_review/battle_perf_2026-11-15/ (pssm4/ vs ortho/, shadow_*.png): same look at the board camera.
3. Auto-battle HUD restyled 3 labels with add_theme_*_override every physics tick (text reshaped each time):
   0.53-0.67 ms per tick native, ~3x on wasm. Fixed (client/hud.gd: once).

After (web, desktop, same rig; build without the subtree part of fix 1): live 28.5 fps overview / 31.3 follow, split
physics 8.4 + process 2.5 + draw 23.5 ms; whole run 24-31 fps with a few hitches (was 11-26). Native late fight
69-85 -> 105-160 fps.

Still OPEN (not changed, needs a decision or another owner):
- Draw: ~0.07-0.09 ms per draw call on WebGL. Hero ink look costs ~+30-60 draws / +4-5 ms per frame on the web
  (frozen A/B: overview 40.3 -> 50.2 fps, follow 53.8 -> 65.9 fps without it). Class skill VFX are the largest draw
  group while live (~117 of ~270 visible surfaces in one frame).
- Physics: the sim runs at 60 Hz; on the web each tick costs ~4 ms (stage tick incl. sim), so at 30 fps two ticks run
  per frame (8-10 ms). Dead enemies in the sim: FIXED 2026-11-15, see below.
- The drawn-style slow-device guard (draw_style.gd SLOW_FPS 27) switched the screen pass off on this RTX 3070 Ti
  desktop in both drawn-style runs: the look changes mid-battle on ordinary PCs. FIXED 2026-11-15, see below.
- Battle entry: one ~27 s frame on the web (3 s native) when the stage opens. Not investigated here.
- Phones not measured (needs a real phone).


## Corpses removed and slow-device verdict at load, measured 2026-11-15 (tech-artist)

PO / Boss 2026-11-15: a fallen enemy lies 3 s, then fades out and is freed completely; the sim drops it too (wave
journeys only, `corpse_clear_seconds` in data/journeys/goblin_waves.json -> GameSim.corpse_clear_ticks). The view
sinks and shrinks over 0.5 s (no alpha pass: no shader compile mid-fight) and is queue_free'd with its model,
AnimationPlayers, status VFX and bar; stage_view drops it from every map. Slow device: decided once at battle load.

Rig: native Windows, RTX 3070 Ti, 1280x720, render scale 0.5, drawn style on, 3-card squad, goblin_waves seed 7,
`battle_fps.gd -- --series --windows=160 --speed=3 --no-marks` (3x fast-forward, 120-frame windows; median per wave).

| wave | fps before -> after | nodes max | static memory MB max | fighters in sim / views max |
|---|---|---|---|---|
| 1 | 163 -> 146 | 5478 -> 5484 | 163.8 -> 164.0 | 9/9 -> 9/9 |
| 3 | 123 -> 151 | 5848 -> 5674 | 170.6 -> 168.4 | 25/25 -> 13/12 |
| 5 | 119 -> 156 | 6472 -> 5841 | 176.1 -> 170.3 | 41/41 -> 13/12 |
| 7 | 113 -> 168 | 6919 -> 5920 | 179.6 -> 170.8 | 52/52 -> 10/10 |
| 9 | 96 -> 146 | 7265 -> 5969 | 182.8 -> 171.2 | 66/66 -> 12/11 |
| 11 | 85 -> (not reached: the 160 windows ended in wave 9) | 7527 | 185.8 | 82/82 |

Node count and memory now stay flat over the run (~5.5-6k nodes, ~170 MB) instead of climbing with every wave.
Sim: a 12-wave fight carried max 90 fighters, now max 15; same seed = same ticks, kills, loot and waves
(tests/test_corpse_clear.gd). Web not re-measured yet (OPEN); the web cost per corpse was larger (physics ~4 ms/tick).

Found on the way: a wave fight could be reported cleared with waves still queued (a race-trigger kill after the
wave release left 0 living for one tick): the local journey ended "won" at wave 6-8 in 4 of 12 seeds. Fixed in
GameSim._check_stage_clear (no clear while waves are queued).

Slow device (docs/po_defaults.md): no mid-battle switch any more. begin_battle (stage load) marks the device slow
when it renders in software or an earlier battle on it ran below 22 fps median over >= 20 s (user://device_speed.cfg);
slow = no screen pass and no hero ink hulls for that whole battle. The battle's own median is only written for the next
one. Graphics "On" forgets the verdict. Not tested on a real phone (OPEN).


## Violent skill looks guide, measured 2026-11-19 (tech-artist)

`tools/shots/vfx_violence_shots.gd -- --perf --level=<current|L1|L2|L3> [--device=phone --size=844x390]` (windowed, native
Windows RTX 3070 Ti, gl_compatibility, vsync off, cap off, goblin island, fight frozen). Stress: every 1.2 s for 9.6 s, 3
High Wizard stars (0.23 s apart) + 1 Arcane Orb burst + 1 Runebreaker slam, each with what the game shows today plus the
violent layers. Two reps; mean shown. CPU frame p50 / p95 ms, GPU p50 ms, draw calls avg, live effect nodes max.

| level | full 1280x720 | phone variant 844x390 |
|---|---|---|
| current | 5.09 / 7.84, gpu 1.41, 669 dc, 22 nodes | 4.58 / 6.75, gpu 1.16, 614 dc, 30 |
| L1 | 5.49 / 8.28 (+8%), gpu 1.50, 701 dc, 55 | 4.84 / 7.31 (+0.26 ms), gpu 1.19, 643 dc, 55 |
| L2 | 5.80 / 8.51 (+14%), gpu 1.56, 725 dc, 80 | 5.00 / 7.48 (+0.42 ms), gpu 1.21, 661 dc, 69 |
| L3 | 6.03 / 8.76 (+18%), gpu 1.64, 743 dc, 106 | 5.08 / 7.58 (+0.50 ms), gpu 1.22, 668 dc, 82 |

Each drawn layer is one draw call (a burst of up to 32 particles is one mesh); the cost is mostly CPU draw submission
(~+0.012 ms per extra live node here). The web/phone estimate uses the ~6-8x CPU factor seen between this PC and the
Boss's iPhone (perf_ab logs): phone L2 +0.42 ms native -> ~+2.5-3.4 ms on the iPhone in this 5-blows-per-1.2 s stress,
~+0.8-1.2 ms for a normal fight (one guide blow at a time). Fill: smoke puffs are the only large alpha quads
(phone sizes x0.75); measured GPU change on the phone variant <= 0.06 ms at 844x390.

### Rollout at L3, boss wave, measured 2026-11-19 (tech-artist)

The Boss chose the L3 light (no ground rings / scorch, no lighting dim, no hit-stop), rolled out to every race ultimate,
class skill and the mummy bosses' big moves. Same harness, `--map=mummy` (pyramid hall, the High Wizard wave): every 1.0 s
for 10 s, 3 stars + curse + Pharaoh nova + Runebreaker + repulse nova + crater leap + heartseeker (9 blows a second, 81 in
all), each with today's bundle / layers; "current" is the same blows without the new look. Two reps, mean.

| | frame p50 / p95 ms | GPU p50 ms | draw calls avg | live effect nodes max |
|---|---|---|---|---|
| full 1280x720, current | 6.00 / 7.93 | 1.84 | 744 | 16 |
| full 1280x720, L3 | 6.75 / 8.94 (+12.4% / +12.7%) | 2.15 | 846 | 143 |
| phone 844x390, current | 6.33 / 9.19 | 1.44 | 701 | 16 |
| phone 844x390, L3, uncapped | (before the cap: +0.75 ms p50, 785 dc, 122 nodes) | | | |
| phone 844x390, L3, 3 blows/s cap | 6.66 / 9.27 (+0.33 ms) | 1.46 | 739 | 59 |

Full stays inside the +15% budget even at 9 blows a second. The phone variant is capped at 3 violent blows a second
(client/vfx/violent_vfx.gd PHONE_BLOWS_PER_SECOND: in a boss wave the rest keep only their own bundle), so the phone adds
~+0.33 ms native -> ~+2-2.6 ms on the Boss's iPhone in this worst case, ~+0.8-1.2 ms for one blow at a time. A normal
fight is far below this stress. Web pack: no new art files (procedural layers); vfx.json grew ~70 KB of text in the core
pack, the battle pack is unchanged.


### Fight light + VFX tiers, measured 2026-11-25 (tech-artist)

Boss approved: (1) brighter fight scenes, (2) VFX hierarchy. Data: `data/render/fight_light.json` (exposure / ambient /
character key+rim multipliers per zone, applied by `client/fight_light.gd`; no new lights, no new passes) and
`data/combat/vfx.json` "violence".tiers / budget. Tiers: **A** = boss big moves + race ultimates (only tier with the screen
flash and zoom punch; debris halved 56 -> 16 full, 18 -> 9 phone; smoke halved, life x0.55 = 1.65-1.9 s); **B** = class
skills, combos, monster shots, auras (debris 32+24 -> 10, no grit, smoke 14+10 -> 5+4 at x0.45 life, sparks x0.6, no
flash, no punch, shake x0.6); **C** = plain hits (no debris, no flash; hit/crit and skill_impact/3|crit lost their flash).
Screen caps over all violent blows (client/vfx/violent_vfx.gd budget_drop): debris 48 (phone 24), smoke particles 24
(phone 10); a blow over the cap plays without that layer.

`tools/shots/fight_light_shots.gd` (windowed, RTX 3070 Ti native, vsync off, live wave-1 fight from 6 s, 300 frames, two
reps mean; CPU frame p50 / p95 ms, draw calls avg):

| map | 844x390 before | 844x390 after | 1280x720 before | 1280x720 after |
|---|---|---|---|---|
| goblin courtyard | 2.75 / 4.80, 221 dc | 3.23 / 5.34, 217 dc | 2.77 / 5.40, 228 dc | 2.89 / 5.08, 215 dc |
| mummy hall | 3.04 / 5.14, 218 dc | 3.18 / 5.37, 209 dc | 3.05 / 5.21, 223 dc | 3.17 / 5.50, 214 dc |
| orc camp | 3.01 / 5.72, 229 dc | 3.39 / 5.76, 232 dc | 3.00 / 5.99, 228 dc | 3.35 / 6.60, 228 dc |
| elder grove | 1.84 / 3.45, 178 dc | 1.88 / 3.62, 173 dc | 1.87 / 3.75, 178 dc | 2.07 / 3.68, 178 dc |

Wave 1 has no skills or ultimates yet, so the VFX cut barely shows here; the differences (+0.1-0.4 ms p50) are inside the
run-to-run noise of these short live fights (the fight differs per run: the sim rng is not seeded by the tool) and draw
calls are flat or lower. The light change costs nothing by construction (same lights, uniform values only). The VFX cut
lowers the particle count of every violent blow (tier A debris -50 %, tier B debris -82 %, smoke -50..-65 % and 45-55 %
shorter life), which is the fill-heavy part on phones (large alpha smoke quads). OPEN: no real-iPhone measure yet; the
boss-wave stress (vfx_violence_shots.gd --perf) was not re-run.

Orc Camp DUSK (Boss 2026-11-25, same files): the orc zone in fight_light.json also sets a gradient sky (violet top ->
pink -> orange horizon, ProceduralSkyMaterial; the drawn style keeps it via meta fight_light_sky), the existing sun low
(-20 deg) from the side, warm #ffbf8a at 0.95, a violet shade ambient #8c7cc4, a warm rim #ffb070 x1.9 and key x1.6. Same
lights, no new pass: orc 844x390 p50 / p95 3.46 / 5.97 ms, 218 dc (night 'after' 3.39 / 5.76, 232 dc) = noise.
