# Relic asset and gameplay specification

Approved by Boss: 2026-10-30. Read together with `assets_spec.md`.

## Geometry and scale

- Floating Relics: **maximum **1,000** triangles per complete equipped item**, including every decorative piece. Count actual exported triangles; do not infer from FBX size or image appearance.
- Goblin approved baseline: medallion 998 tri and lantern 998 tri, 1,996 combined. Earlier4700total and600peritem trials are superseded. Reference `art/relics/goblin/runtime.json` and `build/relic-1000-baked-comparison.png`.
- Prepared height 15 cm, footY0, centeredXZ; must remain substantially smaller than the player's head while recognizable at real landscape mobile scale. Future scale changes must preserve a consistent visual hierarchy.
- Capacity 3 slots; currently only slot0 unlocked. Do not unlock more slots implicitly when adding art. Same relic type must not activate twice.
- Keep high-detail FBX/GLB, previous trials and intermediates in excluded `art_source/`; never ship them as fallback models. Set1/Set2 are source preparation only and still need runtime optimization before activation.

## UV, texture and materials

- Simplification alone is insufficient when UVs stretch. Rebuild UVs and bake source colour, tangent-space normals and metallic/roughness to the low mesh. Check face, side, rear and three-quarter under the same light as source.
- Small floating item defaults: colour 512, normal 256, packed MR 256 perpiece. These are ceilings for this item class; use smaller/omit unused maps where visually adequate. MR is linear: Groughness/Bmetallic. Normal is linear/data, never sRGB. Colour is sRGB.
- Raw bake texels must preserve colour space. Avoid Blender float-image display-transform conversion when saving maps; do not double-gamma colour/data maps.
- GPU-compressed3Dtextures+mipmaps, normal-map flag only onnormal. UI icons are separate 128 px assets; don't apply3DVRAM rules to them.
- Aim for one mesh/material/draw surface per Relic and reuse cached resources across players. Do not duplicate texture sets per equipped instance.
- No orbital physics, dynamic lights, shadows or continuous particle emitters by default. Do not add outlined duplicate meshes without measuring their cost. Orbit transforms are local visuals, never streamed everyframe.
- Match muted existing game palette/material response. User-approved source look takes precedence over arbitrary recolouring.

## Ownership, drops and effects

- Server owns boss rewards, instance IDs, equipment and effect math. Clients send equip intent only through existing profile Commands; no grant/damage/stack/timer command is allowed.
- Activate only known catalog types that are both owned and equipped in unlocked slots. Catalog `data/relics/catalog.json` is source of display/effect configuration.
- Goblin Chief currently drops one random Goblinmedallion/lantern per eligible participant at configured100%chance; other monsters don't drop these. Preserve kill idempotency, pending run loot, securing/abandon and co-op isolation.
- Medallion: landed basic/heavy attacks earn one stack at most every30ticks(.5s); after5stacks NEXT valid basic/heavy hit deals1.25x, then resets. Guarded/filtered hits, skills andDOT don't stack/consume. Multi-target hits cannot accelerate stacking.
- Lantern: successful server-authorized skill cast arms next landed basic/heavy for240ticks(4s), with480tick(8s) cooldown starting on that cast. Poison total30%sourceATK over180ticks(3s), one instance, no stacking. Exact fractional ticks must not exceed total through minimum-damage rounding. Failed casts never arm. DOT cannot trigger Relics recursively.
- Charge/timers are percombat-scene transient state, reset on newscene/trainingreset. Death clears charge/armedwindow. Full simulation checkpoint restores active states exactly; coordinated client/server wire schema required.
- Rules remain in `logic/`; presentation stays in `client/`. Training mirrors read-only equip and has no profile writes/loot/wear. Plaza exposes only worn definitions, never private owned inventory or currency.

## Verification and release

1. Validate <=1000actualtri, bounds/15cm scale, UV/dependencies and texture sizes; preserve originalsourcehash.
2. Native source vs low/baked views(front/45/side/rear), plus actual-size equipped character onPC/landscape mobile. User-approved images do not establish browser FPS.
3. Tests cover owned-only equipment, lockedslot rejection, dropidempotency,5+1/.5scharge,8s/4s/3spoison,blocked/failedcast/no recursion,kill attribution,checkpoint+wireroundtrip,traininginvariance.
4. Measure per-item GLB, selected GPUformat and final Webpack download separately. Never sum PC S3TC and mobile ETC2 for one device. Check multi-player3slot worstcase before expansion.
5. Deploy additive profile schema/effects with profileworker,roomworker,Nakama+Web as needed; retain rollback images and match public artifacts to tested candidates. No test account grants or forged ownership for live verification.

## Rebuild approved Goblin assets

`tools/art/prepare_goblin_relic_runtime.py` → `prepare_relic_rebake.py` → `bake_relic_surface.py` → `finish_relic_rebake.py`, then native import/GPUsettings and `tools/shots/relic_baked_review.gd`. Blender helper projects read-only high-surface data into numeric texture arrays; it does not export geometry. Geometry/UV export is purePythonGLB. Preserve runtime approvals if regenerating.

## Approved deployment

2026-10-30: live build **2103e952a30f**, image tag `relic-20261030-1`; coordinated Web/room/profile/Nakama rollout and public pack-byte verification passed. See [release evidence](docs/releases/relic-20261030.md).
