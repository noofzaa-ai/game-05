# Root-anchored crop sprites

Source designs supplied by Boss 2026-11-02. Cleaned/toned derivative sheet is outside runtime at `art_source/farm/crops-toned-sheet-v1.png`; extraction: `tools/art/split_farm_sprites.py`.

9 RGBA plant files256x256: carrot/potato/herb × stage1–3. Root pixel128,240 across every stage. 3 RGBA harvest icons128x128. Root Node3D sits at soil y=.15; child Sprite3D pixel_size=.0048, center raised112pixels, fixed-Y billboard stays vertical while facing camera azimuth. Scene lighting enabled, alpha discard. No baked backdrop, no emissive, no shadows, shared cached textures. Plant art is stage-dependent and four repeated plants per plot. Stage0/harvested have no sprite. Data/persistence unchanged; no rewards granted by visuals.

Plant textures use VRAM compression + mipmaps + alpha-border repair per assets_spec.md; UI icons use lossless128px without mipmaps. PNG runtime source~600KB; actual release pack delta has NOT been built/measured. Do not export high-resolution authoring sheet. Icon use in farm UI only; harvested produce still uses existing farm storage, not converted into combat-inventory items here.
