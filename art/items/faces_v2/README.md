# chibi_v2 faces (character-artist, 2026-10-13)

11 NEW anime-style face items for the chibi_v2 base — same ids/names/expressions as the model
team's `data/cosmetics/faces.json`, built as NEW assets. The model team's `art/items/faces/*`
and `faces.json` are left untouched.

- Builder (re-runnable): `tools/blender/build_chibi_v2_faces.py`
  ```
  blender -b --factory-startup --python tools/blender/build_chibi_v2_faces.py -- art/items/faces_v2
  ```
- Each face: `face_v2_<id>.glb` (~11–15 KB, no textures) + `.json` sidecar + `.png` thumbnail.
  All well under the 60 KB/face budget. ~237–367 tris each.

## Format (same mount path as the model-team faces)
- Rigid GLB, **no own skeleton**, authored in the `attach_head` bone's local frame
  (`attach_head` head is at rig z=1.5393; face-local z = world z − 1.5393), front −Y, up +Z.
- `client/character_model.gd` mounts it on the `attach_head` BoneAttachment with NO code change;
  the body's own face features (eyes/brows/mouth) hide while a face item is worn, exactly like v1.
- Fit to the **chibi_v2 OWN round head** (centre rig z=1.33, radii 0.165/0.150/0.185). These faces
  are NOT fit to the model-team chibi head and should only be used with chibi_v2.

## Materials
- `Face ink` — black line art (lashes, pupils, iris dark rim, brows, nose tick, mouth strokes)
- `Face white` — sclera / teeth / highlights
- `Face iris` — the recolourable iris (ruby/pink default; its OWN material, like the base's `Iris clay`)
- `Face tongue`, `Face sweat` — playful/shout tongue, err sweat-drop

## The 11 expressions
smile (open happy eyes, curved smile), soft_smile (half-lidded, small smile), playful (one eye
wink + tongue tip), prankster (sly grin, one brow up), devious (narrowed tilted eyes, brows down,
smirk), Fang (smile + one fang), bored (half-lids, flat mouth), annoyed (brows down-in, small
frown), Err... (wavy mouth, sweat-drop), Worried (brows up-in, small open frown), shout (wide eyes,
big open mouth + tongue).

## Data switch (NOT live — the game default stays v1 faces until the Boss approves)
`data/cosmetics/faces_v2.json` is a parallel of `faces.json` with the same ids/names/order,
pointing at these assets (both `asset_id` = `face_v2_<id>` and a direct `asset_path`).

To go live when approved, EITHER of:
1. **Point the cosmetics loader at the v2 file** — in `logic/cosmetic_options.gd`, change the
   `"face"` entry of `PARTS` to `"res://data/cosmetics/faces_v2.json"`. Because the manifest does
   not yet know the `face_v2_*` ids, also register them (next bullet) so `ItemAssets.path()`
   resolves them; or add a tiny fallback in `ItemAssets.appearance()` to use the json's
   `asset_path` when the manifest has no entry.
2. **Register in the manifest** — add the 11 `face_v2_*` entries (category `face`,
   `asset_path`, `status: "ready"`) to `art/items/item_manifest.json` (model-team file — needs
   their/Boss sign-off), then the existing path resolution works unchanged.

The chibi_v2 base's OWN default face is the new **smile** (eyes OPEN): the review shot
`tools/shots/chibi_v2_shot.gd` loads `face_v2_smile.glb` as v2's default so the new eyes are seen
(round 1's bug was the model-team closed-eye `face_smile_01` covering them).

## Known weaknesses (honest)
- At fight-camera scale the eyes read as pink anime eyes but fine iris detail (dark rim, two
  highlights) mostly reads as "big bright eye" — acceptable, the shapes/brows/mouths carry the
  expression. Verified on `art_source/preview/chibi_v2/round2/faces_v2_fightsize_sheet.png`.
- Faces have no ink outline (same as the model-team faces); the line art is baked geometry.
