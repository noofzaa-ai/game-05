# Native combat armor migration — 2026-10-24

## Scope
9 native sets (Obsidian/Royal/Ash × heavy/light/cloth),45 catalog pieces replace18 retired armor definitions;31 weapon definitions unchanged. Fashion remains visual-only and overrides each displayed garment slot; choose **แสดงชุดต่อสู้ที่สวมใส่** in Tailor to see combat armor. Actual combat helmets now enabled; cosmetic hats remain deferred. Heavy helmets hide hair as the source Studio specifies.

## Existing item migration
Deterministic aliases in `data/items/armor_migration.json`, applied while decoding trusted saved items in stash, vault, loadout and run bags. Knight→Obsidian heavy; Sentinel→Royal heavy; Scout/Aegis→Ash heavy; old unnamed armor→Ash heavy by slot. Existing object IDs, ownership, quantity, rarity, legacy enhancement, refine, upgrade_count, substat quality/boosts/upgrade_bonus, durability and destroyed flag remain. Only catalog identity changes; old shoes switch main MOVESPD to DEF. Never create an item or reroll a stat during migration. Repeated decoding of new IDs does nothing. The authoritative backend persists the canonical ID in its normal profile save; no production DB edit has run locally. Starter kit versions prevent repeat grants.

Old Scout/Aegis become separate items of the same Ash catalog piece, retaining distinct object IDs. Original heavy set bonus patterns are retained by family; Light/Cloth share their family's set thresholds. Scout/Aegis previously distinct families now count together as Ash (intentional consequence of4→3 families).

## Base stats before refine/upgrade/durability
Heavy multipliers HP1/DEF1; Light HP0.7/DEF0.6; Cloth HP0.4/DEF0.25. Same values for all3 visual families. Hat/pants main HP; shirt/arms/shoes main DEF.

| Main / type | Normal | Rare | Epic | Legendary |
|---|---:|---:|---:|---:|
| HP heavy (per hat/pants) |200|350|550|800|
| HP light |140|245|385|560|
| HP cloth |80|140|220|320|
| DEF heavy (per shirt/arms/shoes) |15|27|42|60|
| DEF light |9|16.2|25.2|36|
| DEF cloth |3.75|6.75|10.5|15|

Full Normal armor base totals: Heavy HP400/DEF45; Light HP280/DEF27; Cloth HP160/DEF11.25. These are equipment contributions, not character totals. Rolled substats and family bonuses add normally. Refine1.3% applies to the new class-specific main Base; upgrade remains substats only.

## Weight
Slot proportions shirt40%, pants25%, shoes15%, hat10%, arms10%. Full-class penalties Heavy30%, Light15%, Cloth5%. Per-piece = slot proportion×class penalty. Empty slots0; destroyed gear ignored; broken durability retains weight. Armor factor=(1−sum armor penalties); weapon factor dagger/fists1,blade0.95,spear0.92,hammer0.88. Final mobility factor=armor factor×weapon factor. This modifies walk/run speed and initial dodge impulse (same dodge duration, invulnerability,cooldown,stamina and friction); it does not alter ultimate travel, attack movement, knockback from enemies, attack speed,power or monsters. Existing MOVESPD gear/buffs multiply walk/run afterwards; they do not extend dodge. Base walk/run constants stay unchanged; no extra global15% cut.

Config: `data/items/equipment_tuning.json`, generated `server/k3s/equipment-tuning.yaml`. Publish matching Web+profile+room and apply matching ConfigMap together at release. ConfigMap changes affect server after reload/restart; clients must receive matching tuning through existing authority sync. No live deploy performed for this change.

## Assets
Source `art/characters/mmorpg-reference-base/armor`; publisher `tools/blender/publish_combat_armor.py` (root authoring repo). Native93joint skeleton,original garment weights/materials and morph targets preserved with uniform game-scale transform.15 original armor cloth tracks copied by `extract_native_armor_cloth.py`. Runtime coverage uses exact source armorRegion; native per-piece PNG icons shown through catalog icon_path. Armor art is in content pack items. No old wardrobe assets reintroduced.

## Release verification
Deployed native-armor-20261024-2, public Web build a870e9ec89e1; all three deployments ready with matching public ConfigMap and profile/room/Nakama versions. Tests:248 focused armor,11 live synthetic authority migration (no storage writes),9 private transport,4 JS tuning bridge checks passed. Inventory and forge constructed in desktop/mobile landscape; camp and orbit rendered. Historical full Node runtime harness remains blocked by its preexisting missing registerMatch mock; no claim of full suite success. Shutdown-only plaza_chat release_focus error remains. Browser account login and physical mobile play were not completed (no authenticated test browser). Source Studio unchanged.

## Cleanup and Backpack controls (local only)
Boss requested local-only after the approval review blocked server image pushes. Current live build is unchanged. Canonical armor whitelist and profile migration marker are v2; unmapped retired IDs in hat/shirt/armband/pants/shoes always migrate into Ash heavy. Login CAS migration runs once outside active rooms, retaining rolled data and item identities.31 weapon definitions/models/icons remain. Runtime old wardrobe register entries and export resources are removed; authored sources remain. If republishing the source register, run `python3 tools/items/retire_legacy_wearables.py`. Render armor PNGs with `tools/shots/native_armor_icons.gd`; never copy white-background Studio thumbnails.

Backpack cosmetic slot is atcolumn4,row5 next to combat backslot3,5; fashion checkbox uses emptyboard4,4, adding no board rows. `appearance.fashion_display` is authoritative on/off; switching off preserves chosen fashion and combat ownership/refine/stats. All fashion garments or all combat garments are rendered, never a mixed fallback. Combat helmet is hidden visually only while fashion is shown. White/black wings stay visible in either mode; other fashion backs follow fashion visibility. Back wings have their own geometry budget exception and are never removed by toggling the outfit. Selecting an outfit re-enables display. In-stage room commands permit only the validated visibility toggle; selecting a new outfit stays camp-only. All changes are local, with no deployment.

2026-10-24 armor-fashion-20261024-1 DEPLOYED after explicit renewed Boss authorization. Public build7df081ebb9c0 verified; Web/profile/room/Nakama digest-pinned images rolled out, all deployments ready1/1. Includes45 tightly framed transparent armor icons, retirement of all old wearable runtime assets, complete whitelist/fallback armor migration v2 with one-time login CAS persistence, Thai bold glyph fix, Backpack fashion slot/checkbox and whole-fashion/whole-combat visuals with wings independent.31 weapons retained. Tests279 armor+36 fashion passed,9 private HTTP/security passed, JS tuning bridge and one-time CAS checks passed, live synthetic authority11/11 passed with no DB writes. Public engine/core/content files all HTTP200. Rollback:build/armor-fashion-rollback-deployments.json; report:build/armor-fashion-release.json. No physical mobile/account play test claimed; earlier960x540 layout checks and actual asset renders remain evidence.
