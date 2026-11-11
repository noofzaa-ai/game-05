# Goblin relics

Only Goblin Medallion and Goblin Lantern from ../../../../assets/gobbin_relic.fbx are used. Original file preserved; source SHA256 and geometry details in asset.json. Source GLBs/shared budgeted maps remain in art_source/props/goblin_base (not Web export). They retain50,000 triangles total; no heavy floating models are shipped by this feature.

Recreate transparent128px UI icons with native Godot: `Godot --path . --script res://tools/shots/goblin_relic_icons.gd`, then import. Uses original model/UV/PBR with muted metallic0.35. UI PNGs preserve alpha and have their own import rules, not3D VRAM-map budgets.

No Relic Web build/deploy yet. Actual Web download delta unmeasured; no claim inferred from file bytes. Catalog/drop behaviour: docs/tech/relic_master.md.

2026-10-30 runtime candidates: models/*.glb now use meshoptimizer UV/normal-aware permissive reduction and15cm normalization. Current1000budget trial is998tri each; sourceGLBs outside export. Shared actual512/256/256maps. Native screenshot build/relic-1000-comparison.png;600trial rejected by Boss.1000trial pending feedback, visible lantern UV distortion remains; do not mark final visual acceptance or deploy. Original19178/30822tri preserved. Runtime controller client/relic_orbit.gd caches loaded mesh resources, no shadows/lights/particles/collisions. Gameplay config data/relics/catalog.json. Rebuild tools/art/prepare_goblin_relic_runtime.py; uses bundled libmeshoptimizer only, no Blender geometry export. Source unchanged.

2026-10-30 rebake follow-up: current998tri-per-piece candidates use fresh UV+high-source BVH-projected colour512/normal256/MR256 rather than old seam-distorted UVs. Final colour conversion corrected after washed-out first trial. Native source comparison build/relic-1000-baked-comparison.png; coarse silhouettes/faceting remain, user acceptance pending. See runtime.json for actualsizes. Pipeline tools/art/{prepare_relic_rebake.py,bake_relic_surface.py,finish_relic_rebake.py}; no Blender geometry export, no deployment. Obsolete sharedUVtextures archived outside runtime.
