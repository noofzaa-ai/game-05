# Studio drop 2026-11-11 — inventory and port status

Source (read-only): `C:\Users\wanwi\project\game05\art\characters\studio05\studio-20261111T172801Z-1-001\studio\`
(`index.html`, `class-gear.js`, `line-art.js`, `eyes/*.js`, `hair/`, `outfits/`, `STUDIO_SPEC.md`, `hair_studio.gd/.tscn`).
Game copy: `art/characters/studio05/v1111/` (new files only; the older studio05 files stay in place).
Port: `client/characters/studio05_character_model.gd`, `studio05_toon.gdshader`, `studio05_ink.gdshader`.
Review shots: `build/studio_v1111/` (`tools/shots/studio_v1111_shots.gd`, `tools/shots/shield_review.gd`).

## 1. What is new or changed versus `art/characters/studio05/`

Checked by file hash, then by mesh / inverse-bind / rest / animation-channel hashes.

| Source file | Status vs ours |
|---|---|
| `hair/our_character_lowpoly_toon_hair_{a,b,c,e,f}_5k.glb` (Sword & Shield) | **identical** to ours |
| `outfits/our_character_lowpoly_toon_hair_*_5k_silver.glb` | **identical** to ours |
| `hair/our_character_{greatsword,longbow,magic}_hair_c_5k.glb` | **identical** to our `classes/<class>.glb` |
| `hair/our_character_{greatsword,longbow,magic}_hair_{a,b,e,f}_5k.glb` | **new** (12 files) |
| `outfits/our_character_{greatsword,longbow,magic}_hair_*_5k_silver.glb` | **new** (15 files), not copied: the silk mesh is byte-identical in all 20 silver files, so the game merges it from our existing silver file instead (saves ~110 MB) |
| `hair/hair_g.glb` | **new** — a hair-only file |
| `outfits/armor_{sword_shield,greatsword,longbow,magic}.glb` | **new** — class gear |
| `class-gear.js` | **new** runtime (gear merge, outfit/weapons mode, hair replace) |
| `eyes/iris-presets.js` | **new** (iris styles 3, 6, 7, 9, 10) |
| `eyes/blink.js` | **new** (procedural blink) |
| `eyes/eye-makeup.js` | **changed**: adds style 2 "ธรรมชาติ · ไม่แต่งตา" (natural); liners take `blink` and skin colour |
| `eyes/anime-face.js` | **changed**: round pupils, gaze centred at X ±0.04325 / Y 0.3585 r 0.0123, relaxed upper lid, blink lids, starry iris (style 1), shut line |
| `line-art.js`, `STUDIO_SPEC.md` | same rules as before (hair/face ink, hulls 0.0019/0.0014, 1.5 px screen outline) |
| `index.html` | new menus: hair G, iris style, makeup set, outfit, class |

Every GLB uses the same 102-joint skin (`Root`, `mixamorig:*`, `hair_{CB,LB,LF,LS,RB,RF,RS}_{1..3}`, `headfront`), the same
inverse bind matrices and joint rest transforms. Only the wrapper differs: body files have
`OurCharacter_50Percent (scale 0.5) > ReferenceRig_Meshy (y 0.012151)`, the gear and hair G files bake that into
`ReferenceRig_Meshy (scale 0.5, y 0.0060755)` — identical world result. The Sword & Shield hair A/B files have a slightly
different `Head_Anime` mesh (extra `COLOR_0/COLOR_1`) and four unused nodes (`Sharp turquoise eye`, `Sharp lifted eyebrow`).

## 2. Hair per class, and hair G

`index.html` offers the same six hair buttons for **every** class: A, B, C, E, F, G (D retired).
A body file exists per class × A/B/C/E/F (`our_character_<model>_hair_<x>_5k.glb`, model = `lowpoly_toon` for
Sword & Shield, `greatsword`, `longbow`, `magic`). Each file carries the class clips with the secondary motion baked for
that hair (the hair bone tracks differ per hair: longbow/greatsword F have their own; magic shares one set).

Hair triangle counts: A 2698, B ~2700, C 2697, E/F ~2700 (STUDIO_SPEC lists the full files at ~5k each).
Hair colour: A/B use material colour `#6F657F` (hair-colour input default); C, E, F carry vertex colour
`COLOR_0 = (0.80, 0.80, 0.86)` with a white material; index.html sets the input to `#ffffff` for C-G.

**Hair G** = `hair/hair_g.glb`: one skinned mesh `Hair_G` (2698 tris, weighted to the same 102 joints incl. the hair chains),
textured PBR material (`Hair G - Original PBR`: 2048² base colour, normal, metal/rough JPEGs, KHR_materials_specular), no
clips. `loadInPlaceRun()` loads the class's **hair A** body file and `replaceCharacterHair()` removes the first `Hair_*` mesh
and appends `Hair_G` (so G moves with hair A's baked hair-bone motion). Line-art: G gets `painted_bangs = 0`, part −0.003.

## 3. Armor and weapons per class

`class-gear.js equipClassGear(character, gear, showArmor)` appends the gear meshes to the body's skin (same joint names
in the same order, else it throws) under `ReferenceRig_Meshy`, and copies gear animation channels into body clips of the
same name.

- **outfit** mode (`showArmor = true`, the default "ชุดประจำคลาส"): every gear mesh is added and `Base_Body`'s mesh is removed.
- **weapons** mode (Silver Silk selected): only nodes matching `/\| (?:Sword|Shield|Bow|Quiver|Staff|Spellbook)\b/`; base body kept.

So yes, **the weapon meshes live inside `armor_<class>.glb`** as skinned pieces (no socket; weighted to the hand bones).

| File | Pieces (tris) | Weapon pieces (weapons mode) | Total tris |
|---|---|---|---|
| `armor_sword_shield.glb` | B 00 Armor suit 4000 (3 morph targets: Cape Trail, Cape Ripple Sine, Cape Ripple Cosine), **B 01 Shield 1400**, **B 02 Sword 1000**, pauldrons 364+365, R knee 250, bracers 270+270, R glove 280, Neck fitting 151 | Shield, Sword | 8350 |
| `armor_greatsword.glb` | A 00 collar 99, A 01 suit 3999, A 02 emblem/belt 460, **A 03 Sword blade 660**, L pauldron 300 + lower 178, knees 210+210, **A 06 crossguard 420**, gloves 230+230, **A 11 pommel 149**, R pauldron 298, **A 14 grip 170**, L bracer 180, Neck 151 | blade, crossguard, pommel, grip (all named "Sword …") | 7944 |
| `armor_longbow.glb` | **L 01 Bow 900**, belt pouch 630, hood 500, **L 04 Quiver 440**, coat 2340, gloves 220+219, trousers/boots 1700, L bracer 320, pauldrons 300+300, chest strap 330, knees 220+220, **L 14 Quiver arrows 359**, belt trim 180, **L 17 Bow string 20**, Neck 151 | Bow, Quiver, Quiver arrows, Bow string | 9349 |
| `armor_magic.glb` | **M 01 Staff 1180**, coat 4140, **M 03 Spellbook 477**, L cuff 310, boots 500+500, gloves 240+240, trousers 720, Neck 151 | Staff, Spellbook | 8458 |

Materials: one textured PBR material per file (2048² base/normal/metal-rough JPEG, `KHR_materials_specular`), plus the
skin material on `Neck - Armor fitting` and a flat colour on the bow string. `armor_sword_shield.glb` also has 47 clips that
only animate the cape morph targets (`weights` on `B 00 | Armor suit`), named like the Sword & Shield body clips.

Per-character totals in game (body/head/hair + gear, measured): Sword & Shield outfit 12,548 tris, Great Sword 12,142,
Longbow 13,547, Magic 12,656; Silver Silk + class weapons 8,843–9,844.

### Shield (Sword & Shield off-hand slot)

The Studio shield is `B 01 | Shield` inside `armor_sword_shield.glb` — a separate skinned mesh weighted to the left
hand/forearm, so it can be shown or hidden on its own without touching the rest of the gear (the game does exactly that).
Rules now (Boss 2026-11-11): off-hand slot only for Sword & Shield; starter item `round_shield` (procedural catalog item).
The model shows, in order: an equipped shield with its own model file (left socket) → the equipped procedural round
shield → when the slot is empty, the Studio's `B 01 | Shield`. Refine aura follows the off-hand item's level. Other
classes show no shield.

## 4. Eye options

- **Iris style** (`index.html #iris-style`, value → default `data-color`): 0 Classic (eye-colour input, default `#C98634`),
  1 Starry Violet `#a352df`, 3 Solar Flame `#ff562c`, 6 Lavender Orbit `#a577db`, 7 Sunburst `#f75c3e`, 9 Pastel Halo `#b960db`,
  10 Astral Sigil `#9b69e7`. Selecting a style sets the eye colour to that style's remembered or default colour.
- **Makeup set** (`#makeup-style` → `makeupStyle`): 0 Anime Soft, 1 Sharp Wing, 2 ธรรมชาติ · ไม่แต่งตา (natural: no shadow/wing/lash
  clusters, skin-toned thin rims, lighter lash shading, thinner shut line).
- **Eye colour** input (`#eye-color`), **Show eyes** toggle.
- **Blink** (`eyes/blink.js`): close 80 ms, hold 35 ms, open 145 ms (smoothstep), first after 1.6 s, then 2.8–5.6 s random gaps
  with a 16 % chance of a quick double (180 ms); paused (value 0) while the preview is paused or eyes hidden; a frame gap
  over 500 ms restarts the wait.

## 5. Runtime behaviour in the JS and its port status

| Behaviour | Source | Game | Status |
|---|---|---|---|
| Gear merge onto the body skeleton, outfit / weapons modes | class-gear.js | `_dress_class_gear` / `_merge` (mesh reparent onto our skeleton, skins bind by bone name) | ported |
| Hair replace (G) | class-gear.js `replaceCharacterHair` | `_load_variant` hair "g" | ported |
| Cape morph-target clips (Sword & Shield gear) | class-gear.js copies gear `weights` channels into same-named clips | `_apply_cape` samples the gear file's blend-shape tracks by clip name at the body clip time | ported, not visually compared |
| Cel bands, linear colour, cull-disabled | applyCelShading | toon shader | ported (as before) |
| Textured gear / Hair G under the cel bands (diffuseColor = colour × map × vertex colour; normal map perturbs the cel normal) | three.js MeshStandardMaterial + cel replace | toon shader `use_albedo_tex`, `use_normal_tex`, `use_vertex_color` | ported; metal/rough/specular ignored as in the source (outgoingLight is replaced) |
| Hair ink (crease, band, painted bangs A/B) | line-art.js hairInk | toon shader part 2 | ported (as before; G/C/E/F no painted bangs) |
| Ink hulls face 0.0014 / hair 0.0019 | addInkHull | ink shader | ported; hair hull colour now includes texture / vertex colour |
| Anime face, iris presets, makeup 0/1/2, relaxed lid, shut line, brow | anime-face.js, iris-presets.js, eye-makeup.js | toon shader part 1 | ported (new 2026-11-11 version) |
| Blink | blink.js | `_update_blink` in `apply_pose` (driven by the game clock) | ported |
| Hair colour default per hair (A/B `#6F657F`, C–G white) | index.html updateColors | `_hair_linear` | ported |
| Iris style → default colour | index.html irisSelect | `set_appearance` (`iris_style`) | ported in the model; **no card option yet** (see OPEN) |
| Screen-space 1.5 px outline `#171224` (SVG feMorphology) | index.html filter | not ported (game uses its own `ink_outline` hull) | OPEN (as before) |
| In-place run (hips Z locked) | loadInPlaceRun | hips x/z locked when sampling | ported (as before) |
| Great Sword run keeps the `gs_run` arm grip on `gs_run_2` | keepGreatSwordGrip | game uses `gs_run` for running | equivalent arms; legs/bounce differ from `gs_run_2` — OPEN |
| Rig overlay, toon/eyes toggles, speed, orbit camera | index.html | n/a (preview tools) | not needed |

## 6. OPEN parity differences

1. **Card options not yet exposed**: iris style (0,1,3,6,7,9,10) and makeup "natural" are wired in the model, but the card
   data (`logic/card_deck.gd` MAKEUPS/PARTS, owned by the PO/logic side) has no iris part and maps the card's makeup
   "none" to Anime Soft (unchanged look). Needs a logic change: add `iris` part, and a decision whether "none" = Studio "natural".
2. **Outfit choice "none" now means the class outfit** (the Studio's "ชุดประจำคลาส"); "silver" = Silk + class weapons only.
   The starter cards for Great Sword / Longbow / Magic are `silver`, so they start in the silk, not the class armor.
   Decide whether starters should switch to the class outfit.
3. **Game item weapon is hidden** whenever the class gear draws a weapon (all four classes). The item weapon still sits in
   the socket for swing trails; weapon visuals no longer change with the equipped weapon item.
4. Great Sword run uses `gs_run`, Studio preview uses `gs_run_2` with `gs_run` arms.
5. Screen-space 1.5 px outline not ported.
6. Cape morph motion and Hair G motion not side-by-side compared with the web preview.
7. Silver Silk files for the other classes were not copied (silk mesh merged from our Sword & Shield silver file); outcome is the
   same geometry, skin and material.
8. Textures are imported VRAM-compressed with mipmaps (Godot default); 12 × 2048² maps — web memory cost not measured.
