# Drawn battle look (ink-and-wash), tech-artist 2026-11-13

Boss 2026-11-13: the battles should feel like watching a cartoon. Boss played the three prototypes on a phone and
picked **ink_c, now the default** (materials + screen pass).

## Switch

| Where | How |
|---|---|
| Player | Settings > Graphics > "Drawn style": On / Lite / Off (`drawn_style` in `client/graphics_options.gd`, default on) |
| On | materials + full-screen ink pass; the pass runs only at render scale 0.5 and turns itself off for the session when the battle runs under 27 fps for 2x2 s (after a 3 s warm-up). The materials stay. |
| Lite | materials only (prototype ink_a) |
| Off | the old look |
| Debug | web `?style=on|lite|off|ink_b` (ink_a = lite, ink_c = on), native `-- --style=...`; an override keeps the pass at any scale |

Code: `client/draw_style/draw_style.gd` (one call at the end of `StageView._ready`), shaders in the same folder.
Test: `tests/test_draw_style.gd`. HP bars are made alpha-blended (alpha 1, same look) so they draw after the pass.

| Option | What it does |
|---|---|
| ink_a (material) | Stage scenery gets `ink_world.gdshader`: 3 flat light bands, hatching on faces turned from the sun, watercolour wash + paper grain, muted warm colour; inverted-hull brush outlines (`ink_outline_brush.gdshader`, 1.5-4.5 px, width wobbles) on closed props; monsters' ink outline becomes the brush line. |
| ink_b (screen) | One full-screen pass (`ink_screen.gdshader`) on a quad in front of the camera, drawn first among transparent objects (VFX, bars, numbers stay clean): depth silhouette + crease lines, posterized value bands, hatching in dark areas (world-anchored), paper grain/wash, desaturation + warmth. Uses the depth and screen textures (both available in Compatibility). |
| ink_c (both) | ink_a + ink_b's pass at reduced strength. Tuned for the default: soft centred wash (4-6 m pools, +-10%), grain +-5%, saturation 0.9 in the material and 0.95 in the environment, no screen wash. |

Limits found: in Compatibility a shadowed sun is drawn in an additive pass, so a material's `light()` cannot darken
(hatch) inside cast shadows; only the screen pass can. The screen pass reads the screen and depth copies that
Godot makes after the opaque pass; on ANGLE/WebGL2 that copy is the main cost (render CPU 2 -> 6-22 ms at scale 1.0).

## Tools

- `tools/shots/draw_style_shots.gd`: windowed native run, PNGs + frame time per style/view, `--audit` lists every
  drawn material. Output `build/draw_style/<style>/`.
- `client/draw_style/draw_style_bench.gd/.tscn`: the same run in the web export. For a bench build the main
  scene is pointed at the bench scene only for the export (release web templates ignore `--script` and scene
  arguments), then `project.godot` is restored. Page and runner: `build/draw_style/web/bench.html`,
  `build/draw_style/run_web_bench.sh` (Chrome, `--disable-gpu-vsync --disable-frame-rate-limit`).

## Measured 2026-11-13 (Chrome 157 WebGL2/ANGLE D3D11, RTX 3070 Ti, 1296x800, vsync off, MSAA 2x, frozen fight)

Mean frame ms, goblin_base_gate overview / close, mummy_arena_a overview / close. Run-to-run noise is about 3 ms.

| Render scale | default | ink_a | ink_b | ink_c |
|---|---|---|---|---|
| 0.5 (shipped default) | 14.9 / 12.4 / 12.9 / 12.1 | 14.7 / 13.7 / 12.1 / 11.6 | 16.4 / 14.2 / 13.3 / 13.1 | 17.4 / 15.4 / 12.9 / 12.7 |
| 1.0 | 22.7-26.0 / 15.7-18.7 / 12.3 / 9.7 | 27.0 / 18.7 / 11.2 / 8.9 | 31.9-38.4 / 21.4-24.1 / 23.7-28.7 / 21.0-22.8 | 32.2-45.6 / 22.3-32.4 / 15.3-24.1 / 13.0-20.3 |

Mobile not measured. The screen pass is per pixel, so phones pay for it in proportion to the pixels drawn.

## Live battle, phone landscape size (2026-11-13)

Same PC and Chrome, window 860x470 (canvas ~844x390), render scale 0.5, MSAA 2x, the real wave journey with the
3-card squad and class VFX (alive in 55-75% of frames, up to 4 at once), 30 s per run, 2 runs:

| Drawn style | fps run 1 / run 2 | p95 ms | frames over 50 ms |
|---|---|---|---|
| off | 29.1 / 29.8 | 58.6 / 53.0 | 84 / 60 |
| lite | (invalid: window hidden) / 31.4 | 52.0 | 52 |
| on | 30.1 / 31.1 | 57.0 / 57.4 | 70 / 80 |

At this size the battle is bound by something other than the drawn style (all three within run noise). No phone
was measured: the slow guard is the safety net there.

## Watercolour repaint (2026-11-13, Codex set, PO-approved for Boss)

Raw images: `art_source/codex_review/repaint/` (review only, gitignored). Shipped at 512 px (sky 1024x512), VRAM
compressed (s3tc + etc2), all in the `stages` battle pack:

| Texture | Use | How |
|---|---|---|
| `art/maps/goblin_base/painted/dirt.png`, `grass.png` | goblin camp ground | `ink_world` overlay in world XZ (grass where the art is green); tint 0.15, saturation 0.4: muted warm grey-brown |
| `art/maps/goblin_base/painted/relic_colour_ink.png` | goblin kit atlas | recoloured from the palette sheet in Blender (`tools/blender/recolour_atlas_from_palette.py`); swapped in only under the drawn style |
| `art/maps/mummy_tomb/painted/floor_tile.png`, `sand.png` | mummy floors | warm greyscale, baked into the floor/sand UVs of new `*_painted.glb` copies (`tools/blender/bake_mummy_floor_tile.py`, originals untouched); 1 painted slab per modelled 2 m slab |
| `art/environment/draw_style/paper_grain.png` | every stage material | replaces the procedural grain in `ink_world` |
| `art/environment/draw_style/sky_backdrop.png` | panorama sky | replaces the procedural sky (not under a night mood) |

Settings per stage: `data/ui/draw_style.json`. Under the drawn style the mummy maps' collider floor box (seen
through the slab gaps; its grey-green ink wash read as green grout) is drawn dark warm brown. Debug A/B: web
`?painted=0` / native `-- --painted=0` skips the painted set.
