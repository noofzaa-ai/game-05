# Reference character — production selection (local, 2026-10-23)

Boss approved replacing the old active player on 2026-10-23 after confirming the rig approach.

## Rig and appearance

- Production avatar: `art/fashion/reference_player.glb`, the original donor rig and native skin weights, with only weapon sockets and the donor accessory wing bones added. Base authored scale is 1.35m including the original reference hair/outfit; optional tall/floating hats extend above that. No 1.8m visual normalization.
- CORRECTION by Boss: preserve all 87 donor joints and original vertex groups/weights. Add 4 original donor wing joints and 2 weapon sockets = 93 joints. Hair chains are not merged into Head, wing chains are not merged into Chest. SecondaryHairRun, WingsIdle and WingsRun retain donor animation channels.
- Default: Red Jacket outfit, Men's Short hair, original eyes, Compass Explorer floating hat, no back accessory. Hat stays above the chosen hair and never hides it.
- 22 complete outfits, 10 hairstyles, 18 hats, 8 back accessories, 9 eye shapes and 8 iris colors. Fashion slots override old equipment geometry. Ordinary gear IDs, ownership, inventory icons, stats and refinement data remain intact.
- Fashion is stored in `Profile.appearance`, validated through the existing server `appearance` command and CosmeticOptions data. It cannot grant equipment, currency or stats. New profiles use deterministic starter defaults. Legacy cosmetic IDs resolve to the new defaults when absent from the new catalogue.
- Actual loadout levels supply aura separately for hat/shirt/armband/pants/shoes/weapon. Exposed skin is partitioned into those equipment regions so short sleeves still show the real armband aura. Hair/back accessories grant no aura or stats themselves.

## Animation and gameplay

- The approved 38-clip Studio library includes the four ultimate carriers; original VFX, throw/recall timing and hit events remain authoritative.
- Regular attacks are retargeted INTO the native rig and stored as Blade_/Dagger_/Spear_/Hammer_ clips inside the player library, preserving phase metadata. The earlier 57-joint runtime files were moved out of the game tree. Knockdown uses the new authored resting pose with the existing whole-body fall transform; no old bind-space procedural pose is used.
- FighterView, camp, plaza peers, paper doll and title traveller now create the reference adapter. SkillVfx loads its motion library from the new player carrier. VFX scale follows configured gameplay body length / pack reference height, independently of the smaller visual avatar.
- Collision dimensions, movement, damage and reach are unchanged. Live multiplayer gameplay acceptance and mobile performance remain to be checked after a coordinated release; no automated gameplay tests were run in this change.

## Assets and release

- Root authoring scripts: `build_reference_native_rig.py`, `animate_reference_native.py`, `preserve_reference_secondary.py`, `export_reference_native.py`, plus `tools/blender/build_reference_fashion.py`, `publish_reference_cosmetics.py`, `retarget_reference_runtime.py`, `reference_asset_budget.py`. Studio originals and source rigs are retained outside the active web pack.
- Native hats now retain their original geometry/weights per Boss’s instruction to carry over the whole asset; the earlier 300-triangle simplification is superseded. Some outfit+hat combinations exceed the legacy 1,500 cap; no silent decimation is applied. Thumbnail PNGs are 192px.
- Old player bodies, old clothing/hair/face GLBs and old skill motion carriers are excluded from the Web export. New fashion assets belong to the characters content pack; JSON/config and shaders remain core.
- Godot asset imports completed without script parse errors. Native Godot generated catalogue thumbnails and the per-slot aura review. Full gameplay/multiplayer/mobile performance testing has not been claimed.
- Local changes only: not deployed. Client and profile worker must release the same cosmetics files together so server validation recognizes new choices.

## Rig correction — authoritative decision
Boss explicitly rejected replacing the donor rig with our 57-point rig. Preserve the donor skeleton, weights, morphs and accessory joints; adapt game animations and weapon grips to it. The old 57-point derivative is superseded and must never be used as production input. Original donor run, hair and wing actions are kept. Studio reference-studio routes to the new native-rig export too.

## Native donor review (2026-10-23)
- Native Godot rendered all four weapon holds, four ultimate sample poses, and black hair + angel wings; no script/shader runtime errors in the art-render log.
- All published hair/outfit/hat/back skins list the same 93 native joints. Original 87 joint names are retained; added joints are donor wing roots/tips and game weapon sockets only.
- DonorRun duration restored to source 0.6666667s. Original SecondaryHairRun/WingsIdle/WingsRun channels retained. All four packs rebuilt after updating tf_skill_docs.md.
- Remaining visual acceptance: close-up hand/finger contact (donor base hand skin does not deform through all named finger joints), raised HammerGroundDragPreview clearance around the large head/floating hat, cloth/hair intersections during full motion. Do not claim final combat acceptance from the static shots.

Hair correction: retaining weighted chains alone did not reproduce donor motion. The retargeted clips key unmapped joints at rest, so red hair must overlay HairTail-only channels from DonorRun during locomotion. This now runs after primary motion in Godot and Studio. Black Cap retains its own SecondaryHairRun channels. No newly invented spring motion is substituted.


### 2026-10-23 — Boss deferred hats
Cosmetic hats are out of the current migration scope. Game and generated Game Studio force no cosmetic hat, hide hat choices, and do not auto-equip Halloween hats. Original source Studio/assets remain intact. Real equipment ownership/stats/refine levels are preserved. Hat fitting/visual acceptance is deferred; remaining parity work covers character, hair, eyes, outfits, back accessories and weapon motions.


2026-10-23 reference-native-20261023-1 DEPLOYED (Boss authorized): headless profile+room containers and game-test Web rolled out successfully; new containers ready with0 restarts. Public https://zorxplay.daiyooo.com/packs.json returns build16a75e173fc2; HTML/engine/core/11 content packs all14 HTTP200. Immutable image refs and rollback images:build/reference-native-release.json. Hat migration remains deferred. No Git push. Full physical-device/multiplayer visual acceptance remains separate.


### Studio UI art + toe-axis repair — 2026-10-23 (Boss steering)
- Boss requested Studio art in both Bag/Player Info and Customize. Customize prioritizes original source SVG icons. ItemAssets centrally resolves visual-only source wardrobe thumbnails (Scouts/red, Knights/black, Sentinels/mono, Aegis/purple) via art/fashion/item_icons.json; item IDs/names/stats/refinement are unchanged. 192px actual-piece renders are tiny PNGs; source hats are icon-only while hat meshes remain deferred. Weapons keep their matching existing Studio weapon art.
- Foot closeups confirmed bind shoes normal but migrated StandBlade folds the foot. Foot/ToeBase tracks in71 converted game clips now transfer canonical bind-axis rotation deltas into the donor bind axes. Donor clips/rig/weights/hair/clothing and clip timing/events remain intact. Reproducible fix and before-asset backups are in the root authoring tools/cache. Native retarget generator now includes the correction for future rebuilds. Export and visual acceptance in progress.


2026-10-23 toe repair visual result: final native carrier exported/imported without errors. Godot closeups at bind, StandBlade and original DonorRun rendered; StandBlade after correction no longer presents the folded-up toe seen in the before shot. Evidence:/tmp/reference_feet_before.png and /tmp/reference_feet_StandBlade.png. Four native ultimate ZIPs repackaged after tf_skill_docs.md correction notes. Preparing combined Web hotfix.


2026-10-23 reference-ui-camera-20261023-2 DEPLOYED (continuing Boss-authorized release fixes): public build5e87357efe9d, game-test rollout complete/ready/0 restarts; all14 public HTML/engine/pack endpoints available. Includes atomic UI appearance, original Studio option icons + small actual-piece equipment thumbnails, gameplay-only free orbit with MMB or Alt+LMB drag/wheel and right-side touch drag/pinch, screen-relative movement, and native Foot/ToeBase axis correction across71 migrated clips. 93 native joints/75 clips preserved; original donor animations untouched; hats deferred. Worker/auth/DB untouched in this hotfix. No automated suites run; art closeups and build/import/export logs checked. Manual mobile/online camera acceptance remains pending. Immutable image/rollback:build/reference-ui-camera-release.json.

2026-10-23 native leg-axis v3: supersedes foot-only correction. Applied source-rest delta transfer to UpLeg/Leg/Foot/ToeBase in71 migrated clips; native rig/weights and original donor actions untouched. Purple outfit bind/standing/original Run closeups rendered without runtime errors; visible ankle no longer has helical deformation. Evidence /tmp/reference_feet_StandBlade.png, authoring leg_axes_report.json. Combined Web release leg-axes-20261023-4 in progress; no gameplay rules or combat item icon changes.
