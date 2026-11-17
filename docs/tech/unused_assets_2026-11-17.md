# Download size growth and unused files (2026-11-17, tech-artist)

Boss asked why the web download grew since the level-15 gear and for every unused file to go. All sizes are MiB of the
gzip-9 packs the player downloads (one texture format, s3tc; `pipeline/build_web.py --skip-tests --max-file-mb 0`), the
same numbers as the release logs (`zorx-release-*/build/web.log`). A scratch copy of the 3c5602f release worktree
rebuilt to the same pack hashes (weapons.d9757c0ac800, items.5abed26cede7), so the before/after below is measured with
the real script, not estimated.

## 1. What grew

| Build | engine | core | characters | items | weapons | ui | vfx | monsters | stages | **First load (boot)** | battle | **Total** |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 88cb6f8 (= a39980d art, before lv15) | 9.59 | 6.50 | 14.46 | 6.35 | 3.68 | 4.02+0.64 | 13.41 | 1.56+2.08 | 2.46+2.81 | 45.50 | 22.76 | 68.26 |
| 0569f74 / f8cb6f6 (lv15 armour) | 9.59 | 6.50 | 14.46 | 8.82 | 3.68 | 4.02+0.64 | 13.41 | 1.56+2.08 | 2.46+2.81 | 47.97 | 22.32 | 70.29 |
| 3c5602f (lv15 weapons) | 9.59 | 6.51 | 14.46 | 8.84 | **21.80** | 4.02+0.64 | 13.41 | 1.56+2.08 | 2.46+2.81 | 66.12 | 22.32 | 88.44 |

(Boss's "4x -> 6x" is the `weapons` pack: 3.68 -> 21.80 = 5.9x, +18.1 MiB; "another +20" is the same jump. The whole
first load went 45.5 -> 66.1 MiB, +45%.)

What the 84 new non-import files (a39980d -> 3c5602f) cost in the pack (raw bytes in the pack, ctex included):

| Group | files | source on disk | in the pack |
|---|---|---|---|
| lv15 weapon atlases (`*_weapons_lv15_0.jpg`, `ss_weapons_lv15_1.jpg`) | 5 | 2.16 MB | **14.58 MB** |
| lv15 armour atlas + metal mask | 2 | 2.14 MB | **4.54 MB** |
| lv15 weapon GLB | 20 | 4.12 MB | 2.12 MB |
| lv15 armour GLB | 16 | 2.88 MB | 1.65 MB |
| lv15 weapon metal masks (PNG) | 5 | 1.22 MB | 1.47 MB |
| lv15 weapon + armour icons | 36 | 0.38 MB | 0.30 MB |

Cause: the lv15 atlases are 2048x2048 JPEGs of 0.5-1.9 MB, but their `.import` says `compress/mode=0` (lossless), so
Godot stores them as lossless WebP: 2.9-4.3 MB each, 6-9x bigger than the JPEG they came from. The MID (level-1) atlases
are lossy at 1024 (0.24 MB). The mid-tier armour (commit 08f9655) was reverted in 14a475d and left no files. The old
class armour GLBs and the MID race weapons are still used (starter look and level-1 weapon look) and did not grow.

## 2. Top 40 files in the shipped packs (raw bytes in the pack, one texture format)

| # | MB | pack | file |
|---|---|---|---|
| 1 | 4.18 | weapons | `art/weapons/race_shared/longbow_weapons_lv15_0.jpg` (lv15 atlas, lossless) |
| 2 | 4.16 | weapons | `art/weapons/race_shared/magic_weapons_lv15_0.jpg` (lv15 atlas, lossless) |
| 3 | 4.13 | items | `art/armor/race_shared/race_wardrobe_atlas_lv15.jpg` (lv15 armour atlas, lossless) |
| 4 | 3.33 | characters | `art/characters/studio05/split/body_sword_shield.glb` (body + embedded textures) |
| 5 | 3.30 | weapons | `art/weapons/race_shared/ss_weapons_lv15_0.jpg` (lv15 atlas, lossless) |
| 6 | 2.88 | characters | `art/characters/studio05/split/body_magic.glb` |
| 7 | 2.86 | weapons | `art/weapons/race_shared/greatsword_weapons_lv15_0.jpg` (lv15 atlas, lossless) |
| 8 | 1.82 | characters | `art/characters/studio05/split/body_greatsword.glb` |
| 9 | 1.49 | characters | `art/characters/studio05/split/body_longbow.glb` |
| 10-13 | 0.67 each | monsters | `art/monsters/goblin_{archer,chief,knight,mage}/*_albedo.jpg` (loose duplicate, UNUSED, see 3) |
| 14 | 0.67 | stages | `art/props/mummy_tomb/mummy_kit_albedo.png` (arena texture, used) |
| 15 | 0.67 | monsters | `art/monsters/mummy/mummy_texture_pbr_20250901.png` (loose duplicate, UNUSED) |
| 16 | 0.67 | stages | `art/props/goblin_base/shared/relic_colour.png` (used) |
| 17, 19, 21 | 0.66, 0.60, 0.51 | stages | `art/maps/mummy_tomb/mummy_arena_{a,b,c}_painted.glb` |
| 18 | 0.60 | vfx | `art/vfx/class_skills/arcane_orb/effect.glb` |
| 20 | 0.54 | characters | `art/characters/studio05/v1111/outfits/armor_sword_shield.glb` |
| 22 | 0.47 | weapons | `art/weapons/race_shared/weapon_metal_lv15_magic.png` (metal mask) |
| 23 | 0.45 | core | `art/ui/world_map/archipelago.png` |
| 24, 26 | 0.42, 0.40 | core | `audio/music/hub_ember_waltz.ogg`, `stage_ink_trail.ogg` |
| 25 | 0.41 | items | `art/armor/race_shared/race_wardrobe_atlas_lv15_metal.png` |
| 27 | 0.39 | core | `art/ui/hub_carved/backdrop.png` |
| 28 | 0.39 | characters | `.../v1111/outfits/armor_sword_shield_texture_pbr_20250901.jpg` (loose duplicate, UNUSED) |
| 29-36 | 0.39 each | ui | `art/ui/class_cards/scene/<class>_{mid,near}.png` (card scene layers, used) |
| 37 | 0.37 | characters | `.../v1111/outfits/armor_longbow.glb` |
| 38 | 0.36 | weapons | `art/weapons/race_shared/weapon_metal_lv15_greatsword.png` |
| 39-40 | 0.35 each | characters | `.../v1111/hair/hair_i_texture_pbr_20250901.jpg`, `.../outfits/armor_greatsword_texture_pbr_20250901.jpg` (UNUSED) |

Per source folder the pack is dominated by: `art/weapons/race_shared` 17.6 MB, `art/characters/studio05` 14.5,
`art/vfx/class_skills` 12.2, `art/armor/race_shared` 8.9 (raw, before this cleanup).

## 3. Result of the unused-file hunt: almost nothing is safely deletable

The finder (`tools/assets/unused_assets.py`, with `tools/web/pack_files.gd` listing every entry of the real exported
pack) first reported 1,107 shipped files nobody names: 1,088 loose `effect_* phase N.png` frames beside the VFX
`effect.glb`, 20 outfit/hair `*_texture_pbr_20250901*` textures, a race head overlay png and two painted leaf pngs.
I deleted them, and the full suite passed except for status VFX and race head checks; a windowed fight then logged
"Failed loading resource ... armor_sword_shield.glb". **All of these are loaded**: Godot's glb importer stores the
extracted textures as external references inside the imported `.scn` (the `.import` and the GLB itself never name
them), so a file reference graph cannot see them. Everything was restored (commits b1762a6 then 88f1292 and the next
one); the windowed fight shows the squad, goblins, VFX and HUD and the log has no missing-resource lines.
Lesson recorded: do not delete a texture sitting next to a GLB without reimporting and loading the GLB; the unit tests
do NOT catch a missing outfit texture (the outfit failure only showed in a real run). No guard test was added for that
reason (a "loose texture" rule would be wrong).

What was really removed:
- 66 tracked `.import` files whose source is gone (`art/skills/**`, `art/skill_system/**`): repo only, no download gain.
- `art/props/goblin_base/meshes/drum.res` is excluded from the web export (98 KB raw; map builder output no scene uses;
  file kept). The same for `mummy_kit.glb` was dropped on PO's order: all mummy/pyramid assets are KEEP (mummy map planned).

Measured after (real script, scratch copy): 88.44 -> 85.67 MiB total (-2.8 incl. the 3 wrongly deleted groups, so the
true cleanup saving is under 0.1 MiB). Do not quote -13 MiB.

Verified unused-nothing list (kept): race_shared starter files (fallback chain), MID race weapons (level-1 look), old
class armour GLBs (class starter outfit), `art/ui/**` by-name art (`card_tokens.gd` prefixes), audio (all in data/audio),
fonts, shaders. Ash Steel armour, mid-tier armour and 4K textures: none exist in the shipped set.

## 4. Needs a decision (not changed)

1. lv15 atlas encoding (section 5): the only large saving available.
2. `weapons` pack (21.8 MiB) is `boot` stage: every player downloads all lv15 weapon textures before the card screen,
   although a new player owns no level-15 weapon. A) re-encode (saves ~15 MiB), B) move lv15 weapons to the background
   `battle` stage, C) both.
3. Loose monster textures in `art/monsters/` look duplicated but, by the lesson above, are probably referenced by the
   imported scenes: left alone (also monster-rigger's area).

## 5. Size reductions that are not deletions (numbers only, import settings NOT changed)

lv15 atlases are lossless WebP today. Measured with libwebp (the encoder Godot uses) against the lossless pixels:

| File | lossless now | lossy q85 | q92 | mean abs err q92 | p99.9 err q92 | colour bias q92 (RGB, 0-255) | hue dev q92 (saturated px) |
|---|---|---|---|---|---|---|---|
| longbow_weapons_lv15_0 | 4.2 MB | 0.56 | 0.79 | 1.5 | 9 | +0.1/+0.1/+0.03 | 0.9 / 256 |
| magic_weapons_lv15_0 | 4.2 MB | 0.56 | 0.79 | 1.5 | 8 | same | 0.9 |
| ss_weapons_lv15_0 | 3.3 MB | 0.38 | 0.56 | 1.2 | 7 | +0.05/+0.1/0 | 1.0 |
| greatsword_weapons_lv15_0 | 2.6 MB | 0.38 | 0.55 | 1.1 | 7 | n/a | n/a |
| race_wardrobe_atlas_lv15 | 4.1 MB | 0.49 | 0.74 | 1.5 | 12 | +0.07/+0.07/-0.01 | 1.8 |

Lossy 0.92 for these 5 files: 18.9 MB -> about 3.5 MB, **about -15 MiB on the first load** (85.7 -> ~70 MiB total; q85
-16.5). Mean colour bias under 0.2 of 255, hue deviation under 2 of 256, so the earlier "colour shift" is not libwebp at
q0.92; a windowed before/after of the lv15 set is still needed (the earlier test may have used the default q0.7).
Metal masks (5 weapon PNG + 1 armour PNG, 1.9 MB): keep lossless (p99.9 error 40+ on a thresholded mask, saving ~1.3 MB).
`size_limit` 2048 -> 1024 is -75% but softer (not measured on screen). VRAM compression would double the packs.

## 6. Tools

`python tools/assets/unused_assets.py --shipped <tsv>` (reference graph, report only; treat its output as candidates, see 3).
`godot --headless --path . --script res://tools/web/pack_files.gd -- <index.pck> tools/web/pack_layout.json <out.tsv>`
lists every file of an exported pack with size and pack (export first with `--export-release Web`).

## 7. Boss/PO decision applied: lv15 atlases lossy 0.92 (2026-11-17)

The 4 weapon atlases and the armour atlas (`*_weapons_lv15_0.jpg`, `race_wardrobe_atlas_lv15.jpg`) are now
`compress/mode=1`, `lossy_quality=0.92` (metal masks stay lossless). Atlas bytes in the pack: ss 3.46 -> 0.61 MB,
greatsword 2.99 -> 0.59, longbow 4.38 -> 0.85, magic 4.36 -> 0.86, armour 4.33 -> 0.85 (18.5 -> 3.8 MB).
Colour check (windowed, same camera, before/after): armour lv15 for all 4 races (72 shots: desktop, phone, close-ups,
440 px card) and race_outfit_shots `wcompare` (128 shots: every class x race, MID and lv15 weapon, idle/run/skill).
Mean RGB difference of figure pixels 0.03 (worst image 0.6, that one is a blink); mean-colour shift in metal, gold and
dark regions at or under the run-to-run noise (0.04 to 0.9 of 255); lv15 weapon diff amplified 16x shows no banding or
blocks; the only differing pixels are eye blinks. 0.95 was not needed.
Web build (real script, scratch copy): first load 66.12 -> 51.25 MiB, battle 22.32 -> 22.25, total 88.44 -> 73.49 MiB
(weapons pack 21.80 -> 10.23, items 8.84 -> 5.53).
Option 2 (lv15 weapons to a background pack) would need: a `weapons_lv15` pack in `tools/web/pack_layout.json` with
`stage: battle`, `art/weapons/race_*/*_lv15.glb` and `race_shared/*_lv15*` split out of `weapons`; the loader
(`client/pack_fetcher.gd`) already waits for battle packs before FIGHT, and `client/item_assets.gd` already falls back to
the MID file when `ResourceLoader.exists` is false, so the look would show MID until the pack lands and then change
(re-dress after the fetch signal); the Equipment screen icons are in `items`/`weapons` and must stay boot.
