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
| after this cleanup (scratch build) | 9.59 | 6.49 | 11.97 | 8.84 | 21.80 | 4.02+0.64 | **3.40** | 1.56+2.08 | 2.25+2.58 | 63.62 | 11.87 | 75.49 |

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

## 3. Proven unused and deleted (shipped, nothing references them)

Method (`tools/assets/unused_assets.py`, listing from `tools/web/pack_files.gd` = every entry of the real exported pack):
reachability from project.godot, every script/scene/data file under client/ logic/ scenes/ data/ addons/, the export
include list, `ext_resource` paths (relative ones too), `uid://` ids, `.import` params, binary `.res/.scn` strings, glb
`uri` entries (percent-decoded), and the dynamic names: `{race}`/`%s` templates against data/races, the `_lv15` variants
of `client/item_assets.gd`, `class_skill/<id>` and status VFX scenes, folder prefixes. Tests, tools and docs are NOT
roots. 1,201 shipped files had no direct reference; the ones loaded by name at run time (hub UI art
`card_tokens.gd` prefixes `card_frame_`, `hub_icon_`, `hub_sys_`, `frame_`, `window_`, `icon_`, `scene/<class>_far|mid|near`)
were checked by hand and kept. The rest are loose textures that sit next to a GLB which already EMBEDS the same image
(checked in the GLB json: `bufferView` images, no `uri`), left over from the VFX/character deliveries.

| Group | files (+.import) | pack cost | why unused | risk |
|---|---|---|---|---|
| `art/vfx/class_skills/*/effect_* phase N.png` | 904 (+904) | ~9.2 MB raw | the 16 skill `effect.glb` embed all frames; the `.tscn` loads only effect.glb + effect_player.gd | none: glb has no `uri`, tests + windowed shot |
| `art/vfx/status/*/effect_* phase N*.png` | 184 (+184) | ~2.1 MB raw | same, 11 status loops | none |
| `art/characters/studio05/v1111/{outfits,hair}/*_texture_pbr_20250901*.jpg|png` | 20 (+20) | ~3.9 MB raw | outfit/hair GLBs embed their textures | none: GLBs unchanged |
| `.../v1111/race/race_heads_Viking War Paint and Right Temple Tattoo.png` | 1 (+1) | 0.02 MB | `race_heads.glb` embeds it | none |
| `art/maps/verdant_reach/props/{bush,oak}_painted_leaves.png` | 2 (+2) | 0.3 MB | no GLB/script names them | low |

Result: 1,107 files (+1,107 `.import`), 17.05 MB on disk, first load -2.50 MiB (characters), battle download -10.45 MiB
(vfx 13.41 -> 3.40, stages -0.2), total per device 88.44 -> 75.49 MiB (-12.95).
Also removed from git: 66 tracked `.import` files whose source is gone (`art/skills/**`, `art/skill_system/**`; the import
step had already deleted them from the working tree).

Added to `export_presets.cfg` exclude (kept in the repo, not shipped): `art/props/mummy_tomb/mummy_kit.glb` (146 KB; the
Blender arena tool `tools/blender/prepare_mummy_kit.py` needs it, the game never loads it) and
`art/props/goblin_base/meshes/drum.res` (98 KB; map builder output no scene uses).

## 4. Kept on purpose

- `art/armor/race_shared/<race>_<slot>.glb` + icons (interim starter files): used as the fallback chain for `starter-*`
  pieces and when a lv15 file is missing. MID race weapons: still the level-1 look. Old class armour GLBs
  (`v1111/outfits/armor_<class>.glb`): the class starter outfit. All referenced.
- `art/ui/**` dynamic-name art (see 3), `art/weapons/blade.glb`, `art/ui/diamond.svg` (tiny, weak evidence).
- Audio: every `.ogg` is named in data/audio. No fonts or shaders were unreferenced.

## 5. Probably unused, needs a decision (not deleted)

1. Loose monster textures in `art/monsters/` (`goblin_{archer,chief,knight,mage}_*_albedo.jpg`, `goblin_goblin_albedo.jpg`,
   `mummy_texture_pbr_20250901*.png`: 8 files, about 2.9 MB in the monsters packs per device). The same kind of embedded
   duplicate as above, but `art/monsters` belongs to monster-rigger's current work. Options: A) monster-rigger deletes
   them in their next commit (recommended), B) I delete them after their pilot lands, C) leave.
2. Race outfit / weapon atlases at lv15 (see 6): decide lossy or not.
3. `weapons` pack (21.8 MiB) is `boot` stage: every player downloads all lv15 weapon textures before the card screen,
   although a new player owns no level-15 weapon. Options: A) re-encode (6, saves ~15 MiB), B) move lv15 weapons to the
   background (`battle`) stage, C) both.

## 6. Size reductions that are not deletions (numbers only, import settings NOT changed)

lv15 atlases are lossless WebP today. Measured with libwebp (the encoder Godot uses) against the lossless pixels:

| File | lossless now | lossy q85 | q92 | mean abs err q92 | p99.9 err q92 | colour bias q92 (RGB, 0-255) | hue dev q92 (saturated px) |
|---|---|---|---|---|---|---|---|
| longbow_weapons_lv15_0 | 4.2 MB | 0.56 | 0.79 | 1.5 | 9 | +0.1/+0.1/+0.03 | 0.9 / 256 |
| magic_weapons_lv15_0 | 4.2 MB | 0.56 | 0.79 | 1.5 | 8 | same | 0.9 |
| ss_weapons_lv15_0 | 3.3 MB | 0.38 | 0.56 | 1.2 | 7 | +0.05/+0.1/0 | 1.0 |
| greatsword_weapons_lv15_0 | 2.6 MB | 0.38 | 0.55 | 1.1 | 7 | n/a | n/a |
| race_wardrobe_atlas_lv15 | 4.1 MB | 0.49 | 0.74 | 1.5 | 12 | +0.07/+0.07/-0.01 | 1.8 |

Setting those 5 files to Lossy 0.92 would take them from 18.9 MB to about 3.5 MB: **about -15 MiB on the first load**
(66 -> ~51 MiB after the cleanup; with q85 -16.5 MiB). The mean colour bias is under 0.2 of 255 and the hue deviation under
2 of 256, so the earlier "colour shift" is not from libwebp at q0.92; it needs a windowed before/after shot of the
lv15 set to be sure (the previous test may have used the default q0.7 and mipmaps). The metal masks (5 weapon PNG +
1 armour PNG, 1.5 + 0.4 MB) are NOT worth it: lossy gives p99.9 errors of 40+ on a mask the shader thresholds, and the
saving is only about 1.3 MB: keep lossless.
Other options: 2048 -> 1024 `size_limit` (like the MID atlases) is -75% but visibly softer on the staff/bow detail
(not measured on screen); VRAM compression would double the packs (s3tc + etc2) for no download gain.
Decision for the Boss: lossy q0.92 for the 5 lv15 atlases (recommended, after a windowed colour check I can run), or keep.

## 7. Guard against regrowth

`tests/test_unused_assets.gd` fails when a new file appears in the shipped art folders that nothing references (loose
`effect_* phase N.png` next to a GLB, `*_texture_pbr_*` next to a character GLB), with an allowlist for the documented
by-name art. Run `python tools/assets/unused_assets.py --shipped <pack_files.tsv>` for the full report.

## 8. Verification

(see the end of this file, filled in after the deletion commit)
