# Race gear: art handoff for the Studio team

**Date**: 2026-11-13 · **For**: the Studio 3D team (meshes, race weapons) and the 2D/Codex art agents (icons) · **Design**: `design/gdd/race-gear-sets.md` (3.5, 3.11) · **Data**: `data/items/catalog.json` (80 entries `race_<race>_<class>_<slot>`), generator `tools/items/build_race_gear.py`

Every path below is read from `data/items/catalog.json` (`asset_path`, `icon_path`). Drop a file at its path and the game uses it on the next import. No code or data change is needed. Until then the fallback below is shown.

## 1. What is needed

| Kind | Count | Path pattern (exact) |
|---|---|---|
| Armour meshes | 4 races × 4 classes × 4 slots = **64** | `res://art/armor/race_<race>/<class>/<slot>.glb` |
| Race weapons | 4 races × 4 classes = **16** | `res://art/weapons/race_<race>/<class>.glb` |
| Armour icons | **64** | `res://art/armor/race_<race>/<class>/icon-<slot>.png` |
| Weapon icons | **16** | `res://art/weapons/race_<race>/icon-<class>.png` |

- `<race>`: `human`, `viking`, `elf`, `runeborn`
- `<class>`: `sword_shield`, `greatsword`, `longbow`, `magic`
- `<slot>`: `shirt`, `pants`, `armband`, `shoes`. There is **no hat** (the head armour slot was removed by the Boss on 2026-11-13).
- Example: `res://art/armor/race_viking/greatsword/shirt.glb`, `res://art/armor/race_viking/greatsword/icon-shirt.png`, `res://art/weapons/race_viking/greatsword.glb`, `res://art/weapons/race_viking/icon-greatsword.png`.
- One outfit = one class × race look: **16 armour looks** (4 races × 4 classes, 4 pieces each = 64 GLBs) plus **16 race weapons** (4 races × 4 classes: each race has its own sword-and-shield, greatsword, longbow and staff). Every tier (white, blue, purple, gold) is the same item id, so one file serves all tiers. The tier shows through the item frame colour and the existing refine aura. No per-tier files are planned; if the Studio later sends tier looks, they need a small data change first (ask the PO).
- **Interim look (delivered 2026-11-13):** the Studio's `race_outfits.glb` holds ONE look per race (Human, Viking, Elf, Runeborn × Shirt, Pants, Gloves, Boots). `tools/items/split_race_outfits.py` splits it into `art/armor/race_shared/<race>_<slot>.glb` (Gloves = armband, Boots = shoes) plus one shared atlas `race_wardrobe_atlas.jpg`, with 16 icons `icon-<race>_<slot>.png` rendered from the meshes. Every class wears its race's shared look at every tier until that class's own file arrives (section 4). The source file stays in `art_source/race_gear/` (not shipped).
- The sword-and-shield offhand stays the existing `round_shield`. The race set has no shield.

## 2. Rig rule (Character Studio parity, CLAUDE.md, Boss 2026-10-23)

- Skin every armour piece to the **Studio rig** used by the player body (`art/characters/studio05/...`; inventory in `docs/tech/studio_v20261111_inventory.md`). Use its exact bone names, hierarchy and bind transforms. **Add no new joints.** Never remove, rename or merge donor joints or weights. Never use our old 57-point rig.
- **One GLB per slot, per class × race.** This lets a card mix a Viking shirt with Elf pants: the client loads each slot's file on its own over the same skeleton. Do not merge the slots into one file. Do not include the body, the head or the hair.
- Pieces must fit the class body that wears them. A `greatsword` piece is fitted on the greatsword class body, and so on for each class. Keep the per-piece visibility rules of the Studio (the shirt hides the torso skin under it, and so on).
- The weapon GLB is held through our existing weapon sockets (grip and finger contact adapted TO the Studio rig). Use the same orientation and grip point as the class weapon already in `art/characters/studio05/v1111/outfits/armor_<class>.glb` (`Sword`, `Bow`, `Staff` meshes) so the existing animations line up. The race weapon's family must match the class: a sword for `sword_shield`, a greatsword, a longbow, a staff for `magic`.
- Keep the Studio budgets, materials and render settings (toon/outline). Visual acceptance stays **OPEN** until it is compared front, side and back, standing and running, with mixed races, as `docs/tech/reference_studio_parity.md` requires.

### Weapons arrive in batches

- The Studio makes the 16 race weapons in batches, **mid tier first, greatswords first** (in progress 2026-11-13). Each batch only needs to be placed at its path (`art/weapons/race_<race>/<class>.glb`, icon `art/weapons/race_<race>/icon-<class>.png`), then the import is run. No code or data change. A race × class weapon file serves every tier of that race × class. Without it, the class weapon shows.
- **File layout the client reads** (`client/characters/studio05_character_model.gd` `_wear_race_weapon()`):
  - **Preferred: skinned to the Studio rig**, like the class gear in `armor_<class>.glb`. The client merges every skinned mesh of the file onto the body and hides the class gear's weapon pieces. Name the meshes with the class gear's labels: `... | Sword`, `... | Shield`, `... | Bow`, `... | Quiver`, `... | Staff`, `... | Spellbook` (for example `Viking | Sword`, `Viking | Shield`).
  - **Sword and shield in one file:** a mesh whose name contains `| Shield` replaces the class shield. It follows the off-hand rules (shown when the off-hand slot is empty or holds the starter `round_shield`; an equipped shield with its own model file still wins, held at the left-hand socket `attach_weapon.L`). The off-hand item's refine aura goes on it. All other meshes count as the weapon and take the weapon's refine aura. A file without a `| Shield` mesh keeps the class shield.
  - **Or an unskinned prop** (no skin in the file): it is held in the right-hand socket `attach_weapon.R` (a child of `mixamorig_RightHand`), the same socket as the model team's weapons. The blade runs along +Y, and the grip point is at the origin. Optional marker nodes `trail_start`, `trail_end` and `effect_point` give the swing trail. The grip for this path is not tuned yet (OPEN).
- Match the class weapon's size, grip point and orientation in `armor_<class>.glb` so the existing clips line up.

## 3. Icons

- Square PNG with a transparent background. **192 × 192** for armour (same as `art/armor/ash_steel/icon-shirt.png`). The weapon icons use the same 192 × 192 (the starter weapon icons in `art/items/icons/` are 96 × 96; the gear panel scales both).
- They are combat item art (Boss rule 2026-10-23), never a fashion thumbnail. One object, centred, about 10% margin, the same painted style and light direction as the existing Ash armour icons and the starter weapon icons. Make each race readable at a glance:
  - Human: banner blue and steel.
  - Viking: fur, iron and red-brown leather.
  - Elf: leaf green, bark and silver.
  - Runeborn: dark stone with glowing rune lines.
- The icon carries no tier colour. The game draws the tier frame.
- Make them through Codex CLI only (`docs/tech/codex_image_workflow.md`). The Boss reviews them before import.

## 4. Fallback until the files exist (already in the game)

- **Armour mesh, a chain** (`client/item_assets.gd` `armor_file()`; the catalog's `fallback_asset_path` lists the steps separated by `|`, written by `tools/items/build_race_gear.py`, `OUTFIT_SCOPE = "race"`):
  1. the race × class file `art/armor/race_<race>/<class>/<slot>.glb` (final; drop it in and it wins);
  2. the race's shared interim file `art/armor/race_shared/<race>_<slot>.glb` (delivered, shown now for every class and tier);
  3. the class's starter weight look (`art/armor/ash_*`). This is on the old 93-joint rig, so the Studio body keeps its class suit for it.
- **Armour icon**, the same chain: the race × class icon, then `art/armor/race_shared/icon-<race>_<slot>.png`, then the Ash icon.
- **Studio body:** any worn race piece switches the body to "base body + worn pieces + class weapon" (the Studio's 'weapons' mode, like Silver Silk). With no race piece worn, the class suit shows as before. The skin a piece covers is cut from the body so it cannot poke through. Cover rules are in `BODY_COVER`; the forearm is cut only when both shirt and armband are worn.
- **Weapon**: `procedural: true`. The class weapon from the class armour GLB is drawn. For the sword it uses `asset_id` `weapon_blade_01`. Weapon icon `fallback_icon_path` = `art/items/icons/weapon_starter_<greatsword|longbow|staff>.png`. The sword uses the blade icon.
- So a race piece today looks like the starter piece of that class. The set, stats and set option all work. Only the look waits for the art.
- After adding files, run `godot --headless --path . --import` once, then the test suite.

## 5. Checklist per outfit (class × race)

1. Make 4 GLBs (shirt, pants, armband, shoes) on the Studio rig, with no new joints. Then 1 weapon GLB (it can come in a later batch).
2. Make 5 icons, 192 × 192, through Codex, and get the Boss's review.
3. Put the files at the exact paths in section 1, then run the import.
4. Take comparison shots (front, side, back; standing, running; mixed with another race; with the class weapon) for the parity doc. They stay OPEN until the Boss accepts them.
