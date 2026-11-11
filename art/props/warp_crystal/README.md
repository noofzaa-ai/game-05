# Crystal warp portal

Source: unchanged `../assets/crystal.fbx`. Rebuild with Blender `--python tools/blender/prepare_warp_crystal.py`.

- 1,706 triangles total; width4.8m,height4.915665m,depth3.691565m. Grounded and centered, original geometry/material/UV preserved.
- Color1024 / Normal512 / combined Metallic-Roughness512 per root assets_spec.md. Original FBX remains outside game export.
- Builder identifies the tall disconnected central diamond using welded-position connectivity and normalized world bounds, isolates it as `CrystalRotor`, rebases only its origin to center. Fails if source no longer has exactly one matching crystal.
- Rotor pivot game coordinates(.019275,2.168914,-1.326676); base/frame stay static.
- `client/warp_crystal.gd` rotates the rotor clockwise viewed from above,0.42rad/sec (~15s/revolution),around WORLD up. No pitch/roll,tip remains upward.
- Surface emission and one soft additive aura billboard around center;24 star sparkles,20 expanding/fading ring mist particles. Procedural shaders/32px radial textures, no extra downloaded VFX textures. Existing shadowless portal light retained.
- Camp builder removes old ring/platform geometry preserving RNG usage, replaces rear-frame blocker while keeping new front platform walkable. Existing warp trigger at(0,0,-29.5) and journey choices unchanged.

Deployed2026-10-20: web41e699f893f0/source d3d74f6. Native landscape effect/name capture reviewed; no automated tests or mobile performance profile run.

2026-10-20: blue stone recoloured pale warm white/gray limestone, preserving painted shading and cyan crystal/rune pixels. Reproducible colour-selective albedo conversion in builder; source FBX unchanged.
