# Draw-style prototype (ink-and-wash look), tech-artist 2026-11-13

Boss 2026-11-13: the battles should feel like watching a cartoon (hand-drawn, ink-and-wash). **Prototype only,
off by default.** The shipped look does not change until Boss picks an option.

## Switch

| Where | How |
|---|---|
| Web | `play.html?style=ink_a` / `ink_b` / `ink_c` |
| Native | `godot --path . -- --style=ink_b` (any scene that opens a stage) |
| Project setting | `zorx/rendering/draw_style` (not set = normal look) |

Code: `client/draw_style/draw_style.gd` (one call at the end of `StageView._ready`), shaders in the same folder.

| Option | What it does |
|---|---|
| ink_a (material) | Stage scenery gets `ink_world.gdshader`: 3 flat light bands, hatching on faces turned from the sun, watercolour wash + paper grain, muted warm colour; inverted-hull brush outlines (`ink_outline_brush.gdshader`, 1.5-4.5 px, width wobbles) on closed props; monsters' ink outline becomes the brush line. |
| ink_b (screen) | One full-screen pass (`ink_screen.gdshader`) on a quad in front of the camera, drawn first among transparent objects (VFX, bars, numbers stay clean): depth silhouette + crease lines, posterized value bands, hatching in dark areas (world-anchored), paper grain/wash, desaturation + warmth. Uses the depth and screen textures (both available in Compatibility). |
| ink_c (both) | ink_a + ink_b's pass at reduced strength. |

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
