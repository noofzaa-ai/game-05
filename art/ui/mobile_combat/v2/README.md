# Thin-brass UI skin v2 (2026-10-16)

Reference supplied by user: codex-clipboard-0e6e2110-0d29-4ab2-9239-e69d01e46436.png.
User explicitly selected graphics replacement while retaining existing geometry.

`atlas.png` is derived via the built-in imagegen skill: background extraction,
then removal of sample HUD text/numbers/fill so the game renders live values.
The six combat buttons and Back retain their baked Thai labels. Transparent
outside pixels retain RGB data but have alpha zero; do not flatten to RGB.

Generated outputs: exec-814c64e6-280b-4312-aeb7-8ed011c65d7f.png (extraction),
exec-7444cc87-91e1-4751-b793-d12195a65a65.png (empty live HUD frames).
Final atlas is 1536x1024, lossless import with mipmaps; all parts share one texture.

`client/mobile_ui_art.gd` maps atlas regions and visible button-body bounds.
`client/mobile_combat_art.gd` compensates padding for the unchanged measured
layout in `mobile_controls.gd`. Layout, ellipse hit regions, walking/run and
combat actions remain independent of the art. No duplicate native Thai labels.

Compact bars/counter use empty frames with native live text and fill geometry;
Back uses an image style on its original native Button. Bar/counter/menu bounds
remain unchanged. Prior artwork remains available for rollback.

Validation: native 844x390 landscape/portrait/resume captures, transparent/opaque
pixel checks, all measured geometry regressions, 1893 checks passed (0 failed,
empty stderr). Physical Safari verification and rebuilt Web/container rollout
remain pending.
