---
paths:
  - "art/**"
  - "**/*.import"
  - "export_presets.cfg"
  - "tools/web/**"
  - "pipeline/build_web.py"
  - "client/item_assets.gd"
---

# Asset Size Rules (Boss order 2026-11-17: always be aware of this)

Download size is a game feature. A web player downloads every shipped byte before the first fight.

## The incident that created this rule (2026-11-16/17)
When the level-15 gear came in, the web first load grew from 45.5 MiB to 66.1 MiB (+20.6) and the `weapons` pack went from 3.68 to 21.80 MiB (5.9x). Nobody had measured it. The cause was NOT the 36 new models (about 3.8 MB). It was the 5 lv15 colour atlases (2048 px JPEG, 0.5 to 1.9 MB each on disk) imported with `compress/mode=0` (lossless): each became a 3 to 4.4 MB lossless WebP in the pack, 19.5 MB in total. Switching those five to lossy 0.92 (colour error under 0.2 of 255, no banding) cut the first load to 51.25 MiB.
A JPEG on disk says nothing about its shipped size: the import setting decides it.

## Rules
1. **Never ship a colour atlas, albedo, icon sheet or photo-like texture lossless.** Use `compress/mode=1` (lossy) with `lossy_quality` 0.92 (raise to 0.95 only if a windowed before/after shows banding or blocks) and set `detect_3d/compress_to=0` so the editor does not flip it to VRAM compression. Lossless is allowed only for data textures that a shader thresholds or reads exactly (metal masks, lookup tables, normal-like maps) and for small UI pieces; each such exception must be below 0.5 MB in the pack or be listed with the reason in `tests/test_asset_size.gd`.
2. **Every art or asset delivery reports the pack delta.** Before saying an asset task is done, build the real web packs (`pipeline/build_web.py --skip-tests --max-file-mb 0` on a scratch worktree or `tools/web/pack_files.gd`) and report first load, total, and the packs that moved, before and after, in MiB. A change that adds more than 2 MiB to the first load needs the PO's note in the report and a line in `docs/po_defaults.md`.
3. **Budgets** (every new file must fit, tests derive the file list from the directories): monster model at most 5,000 triangles, one material, texture at most 1024 px and lossy, model plus texture at most 450 KB; shared clip libraries at most 200 KB each; armour or weapon piece GLBs reuse one shared atlas per set, never an embedded copy per file; icons 96 px (UI) or 192 px with `process/size_limit` set.
4. **One atlas per set, shared by every GLB of the set, referenced externally.** Re-encoding the delivered atlas at 2048 px is acceptable only after rule 1 and a size check; prefer 1024 px when the piece is drawn small.
5. **Do not delete assets because a text search says nobody names them.** Godot GLB imports keep texture references inside the imported scene, and chains in `client/item_assets.gd` build paths from templates (`{race}`, `_lv15`, `_mid`). On 2026-11-17 a cleanup deleted 1,107 "unused" textures that the game loads; a windowed fight caught it. Only delete after a windowed fight, hub, Equipment and shop run with zero missing-resource lines. `tools/assets/unused_assets.py` is a candidate finder, not a deleter.
6. **Fallback chains are shipped bytes.** Every file kept as a fallback (starter look, MID weapons) ships to every player; keep a fallback only while an item still uses it.
7. **Loaded later is cheaper than loaded first.** Content that most players do not own yet (high-level gear, later zones) belongs in a `stage: battle` or background pack in `tools/web/pack_layout.json`, with the loader falling back to the lower look until the pack lands.
8. **Check `.import` after any Godot reimport.** A reimport can reset `compress/mode`, `lossy_quality` or `detect_3d/compress_to`; the asset-size test must stay green.

## Quick check before you finish any asset task
- [ ] No new lossless colour texture (`compress/mode=0`) except the listed exceptions.
- [ ] Triangle, texture and file budgets met (rule 3).
- [ ] Pack delta measured and reported (rule 2).
- [ ] `godot --headless --path . --import` then the full suite, no new failure names.
