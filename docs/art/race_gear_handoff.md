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
- One outfit = one class × race look (16 looks). It is 4 armour meshes plus 1 race weapon. Every tier (white, blue, purple, gold) shares the same mesh. The tier shows through the item frame colour and the existing refine aura, so there are no per-tier meshes.
- The sword-and-shield offhand stays the existing `round_shield`. The race set has no shield.

## 2. Rig rule (Character Studio parity, CLAUDE.md, Boss 2026-10-23)

- Skin every armour piece to the **Studio rig** used by the player body (`art/characters/studio05/...`; inventory in `docs/tech/studio_v20261111_inventory.md`). Use its exact bone names, hierarchy and bind transforms. **Add no new joints.** Never remove, rename or merge donor joints or weights. Never use our old 57-point rig.
- **One GLB per slot, per class × race.** This lets a card mix a Viking shirt with Elf pants: the client loads each slot's file on its own over the same skeleton. Do not merge the slots into one file. Do not include the body, the head or the hair.
- Pieces must fit the class body that wears them. A `greatsword` piece is fitted on the greatsword class body, and so on for each class. Keep the per-piece visibility rules of the Studio (the shirt hides the torso skin under it, and so on).
- The weapon GLB is held through our existing weapon sockets (grip and finger contact adapted TO the Studio rig). Use the same orientation and grip point as the class weapon already in `art/characters/studio05/v1111/outfits/armor_<class>.glb` (`Sword`, `Bow`, `Staff` meshes) so the existing animations line up. The race weapon's family must match the class: a sword for `sword_shield`, a greatsword, a longbow, a staff for `magic`.
- Keep the Studio budgets, materials and render settings (toon/outline). Visual acceptance stays **OPEN** until it is compared front, side and back, standing and running, with mixed races, as `docs/tech/reference_studio_parity.md` requires.

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

- **Armour mesh**: `fallback_asset_path` = the class's starter weight look (`art/armor/ash_steel/` for heavy, `ash_leather/` for longbow, `ash_cloth/` for magic). The armband uses `arms.glb`. Code: `client/item_assets.gd`.
- **Armour icon**: `fallback_icon_path` = the same Ash icon (`icon-arms.png` for the armband).
- **Weapon**: `procedural: true`. The class weapon from the class armour GLB is drawn. For the sword it uses `asset_id` `weapon_blade_01`. Weapon icon `fallback_icon_path` = `art/items/icons/weapon_starter_<greatsword|longbow|staff>.png`. The sword uses the blade icon.
- So a race piece today looks like the starter piece of that class. The set, stats and set option all work. Only the look waits for the art.
- After adding files, run `godot --headless --path . --import` once, then the test suite.

## 5. Checklist per outfit (class × race)

1. Make 4 GLBs (shirt, pants, armband, shoes) on the Studio rig, with no new joints. Then 1 weapon GLB.
2. Make 5 icons, 192 × 192, through Codex, and get the Boss's review.
3. Put the files at the exact paths in section 1, then run the import.
4. Take comparison shots (front, side, back; standing, running; mixed with another race; with the class weapon) for the parity doc. They stay OPEN until the Boss accepts them.
