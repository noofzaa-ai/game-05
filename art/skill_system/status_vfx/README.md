# Body-attached status VFX — native review 2026-10-29

## Current implementation

Six MCP-derived effects (burn/bleed/freeze/chill/shock/stun) are connected locally through client/skills/presenter.gd and status_effect.gd. FighterView stores fitted model bounds once. Stage passes current rendered positions AFTER visual updates, so interpolation and remote smoothing are respected. Separate vertical/horizontal scaling adapts coverage to short, tall and wide models; stun is anchored above the measured head height. Six simultaneous statuses are supported. Status snapshots still own lifetime; no damage, authority, status duration, combat balance or skill motion changed.

Scenes/materials are cached and pooled through the existing presenter. Removing a status, despawning a body or switching combat VFX off recycles it and stops processing; reuse restarts animation at zero. Source remains in ex/status_vfx_review, excluded from exports; runtime derivatives live here and will be included in a future build. NO BUILD/DEPLOY performed in this task.

## Evidence

- tests/status_vfx_lifecycle.gd PASS (six actual scenes load, simultaneous states, current rendered position follows despite different physics position, size/head anchor refit, snapshot expiry, pooled stop/reuse, body despawn, graphics off, StageView compiles).
- Native Godot4.7.2 Compatibility / Apple M1: real Goblin and Chief models at deliberately varied 0.9/1.8/3.2m heights; chief widened1.25x. tools/shots/status_vfx_review.gd renders three animation phases per effect (0.4/0.9/1.5s), eighteen captures in build/status-vfx-trial-*.png. Two sheets build/status-vfx-review-*.jpg are assembled from actual native screenshots, blank lower space cropped only. These extreme review heights do not change production monster size.
- Native screenshot log /tmp/status-vfx-runtime-review.log has no script errors; PASS marker. Lifecycle log /tmp/status-lifecycle-final.log.
- Full project tests/run_all.gd attempted with180s timeout; NOT PASS. Failures include cleanup/profile/cache/online command assertions and legacy special/ultimate assertions; runner timed out. /tmp/status-full-suite.log. No clean baseline comparison was performed, so this task does not establish the cause of those unrelated-suite failures or overall regression-free release readiness.
- No physical mobile/Web/FPS benchmark or fresh online gameplay acceptance claimed. Native landscape only.

## Visual review

Burn: orange flames visible around body. Bleed: red animated droplets now camera-facing. Freeze: cyan crystals narrowed and emission reduced to leave head visible. Chill: pale drifting wisps more opaque and constrained closer to body; deliberately subtler than freeze. Shock: body-local white/lilac bolts made camera-facing to avoid edge-on disappearance. Stun: yellow orbiting crosses above the head. A busy map or many stacked effects may need further aesthetic tuning; screenshots provide the current exact result.

## Runtime budget and provenance

All embedded animation textures capped128px with alpha retained. External extracted textures use VRAM compression and mipmaps. No skeleton/geometry/clip retiming. Authored review loop length is2s, not the gameplay status duration. SHA256 checked at authenticated source download; credentials never stored in assets. MCP job provenance is retained in ex/status_vfx_review/jobs.json.

| Effect | Original GLB bytes | Runtime GLB bytes |
|---|---:|---:|
| burn | 1,270,288 | 844,688 |
| bleed | 62,004 | 64,288 |
| freeze | 154,012 | 155,948 |
| chill | 561,316 | 433,600 |
| shock | 126,144 | 127,184 |
| stun | 36,484 | 37,708 |

Actual source mesh triangles: burn832 / bleed192 / freeze64 / chill64 / shock192 / stun32. Native flipbook derivative groups:12/10/8/7/3/4; animation track reductions89→29 /100→20 /88→24 /77→21 /27→3 /44→12. runtime.scn keeps one active phase mesh per group. Runtime GLB bytes are source-art storage, NOT the actual added gzip web download; no build/download-size measurement was made. GLB originals are retained to rebuild derivatives and may still be transitively packaged by engine resources.

## Rebuild

1. python3 tools/art/prepare_status_assets.py (uses preserved authenticated source bundles)
2. Godot --headless --path . --import
3. Set extracted PNG imports to compress/mode2,mipmaps=true; reimport.
4. Godot --headless --path . --script res://tools/art/prepare_status_scenes.gd
5. Godot --headless --path . --script res://tests/status_vfx_lifecycle.gd
6. Godot --path . --script res://tools/shots/status_vfx_review.gd


Release update: approved and deployed Webc11ef07e658a on2026-10-29; see docs/releases/status-vfx-20261029.md for final packed tests/digest/rollback. This supersedes historical no-build/deploy statements above. Final presenter measures existing FighterView geometry and supports the deployed two-argument Stage through deferred anchor refresh; no Stage/Fighter code shipped.
