# chibi_v2 — new player base character (character-artist, 2026-10-12)

A new, smoother, more anime-styled player base built by us on the EXISTING chibi skeleton,
per the Boss's decision to replace the faceted v1 clay base. The game still ships v1 until the
Boss approves the switch.

- Runtime asset: `art/characters/chibi-v2/chibi_v2.glb` (~129 KB, no external textures)
- Builder (re-runnable): `tools/blender/build_chibi_v2.py`
  ```
  blender -b --factory-startup --python tools/blender/build_chibi_v2.py -- \
      art/characters/chibi-studio/chibi_base_animated.glb art/characters/chibi-v2/chibi_v2.glb
  ```
- Blender preview: `tools/blender/preview_chibi_v2.py`
- Godot review shots (windowed, old-vs-new): `tools/shots/chibi_v2_shot.gd`
  ```
  godot --path . --script res://tools/shots/chibi_v2_shot.gd -- art_source/preview/chibi_v2
  ```
- Previews: `art_source/preview/chibi_v2/` (doll_v1_* vs doll_v2_*, fight_*, *_v1_vs_v2.png).

## What it is
- ~3,440 triangles, 16 meshes, 8 materials. Smooth shading (no facets).
- Round skull, pointed small chin, full cheeks; big glossy anime eyes with iris + two highlights,
  dark upper lash thicker at the outer corner, tiny nose, small mouth, rosy blush.
- Round-2 hair: a thin skullcap + ~24 separate chunky LOCKS with blunt pointed tips (3 side locks
  per side framing the cheeks to jaw level, 4 back locks, 3 crown locks, an 8-lock fringe whose tips
  stop ABOVE the brows) + a thin dark headband. The locks use the `Neutral clay` material so the
  Look system recolours them to the chosen hair colour (salmon default `#f0968a`); round 1 used a
  `Hair clay` material the recolour code ignored, which is why it came out near-white.
- Round-2 hands: a clean rounded tapered mitt with a soft thumb bump (near-round cross-sections) so
  the ink outline is ONE convex silhouette, not the round-1 tangle of tiny finger cylinders.
- Narrow shoulders, slim waist, soft boot feet.

### Round 2 (PO review fixes, 2026-10-13)
- Hair rebuilt as separate chunky locks (was a smooth helmet); fringe lifted above the brows.
- Hair recolour fixed (locks now use `Neutral clay`, salmon survives the hair-tint code).
- Hands rebuilt clean (ink outline no longer breaks on the fingers).
- 11 NEW v2 anime faces: `art/items/faces_v2/face_v2_<id>.glb` (+ json/png). The base's own default
  face shown in review is the v2 **smile** (eyes OPEN) — round 1 showed the model-team closed-eye
  `face_smile_01` over the new eyes. Data switch: `data/cosmetics/faces_v2.json` (not live).
- Known weak spots (honest): the v2 head reads a touch smaller than v1's big-head chibi; at
  fight-camera scale the fringe can look comb-like against tall hair items; fine iris detail reads
  as "big bright eye" when very small. See `art_source/preview/chibi_v2/round2/`.

## Skeleton contract (UNCHANGED)
Reuses the GameRig armature read straight from `chibi_base_animated.glb`: the SAME 57 bone names,
hierarchy and rest pose. Animations are NOT embedded — the game loads clips from `art/animations/*.glb`
by bone name, so the 31 clips and all weapon grips keep working. Verified: full test suite 1461/0.

## Name/material contract the game code relies on (all kept)
- Mesh/node names: `Body continuous`, `Hands articulated`, `Face`, `Nose`, `Brow.L/.R`,
  `Eye inset.L/.R`, `Eyelid.L/.R`, `Mouth`, `Base foot.L/.R`; hair pieces (`Hair crown`,
  `Front fringe`, `Headband`) tagged extras `studio_hair_style=original`.
- Materials: `Neutral clay` (skin — recoloured by the Look system via a prefix match; brows take the
  hair colour by node name), `Eye inset clay` (sclera + mouth), `Lash clay` (eyelids), `Hair clay`
  (bob, salmon default, hair-tint compatible), `Headband clay` (dark band).
- NEW material `Iris clay` on `Eye inset.L/.R` so the iris colour can be recoloured later (see note).

## To switch the game to v2 (one line, when the Boss approves)
`client/character_model.gd` → `const MODEL_PATH := "res://art/characters/chibi-v2/chibi_v2.glb"`.
Nothing else is required: every mesh/material/node name and the skeleton match the current contract.

Optional follow-ups (NOT done — need Look-system owner / Boss):
- Recolourable iris: the iris is its own `Iris clay` material/surface; the Look system could tint it
  like it tints skin/hair if we add an iris colour (small change in character_model/look code).
- Subtle toon ramp: a client material question (shader), not a model change — reported, not done.
