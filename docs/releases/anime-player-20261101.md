# Approved Anime Toon player — 2026-11-01

Boss approved moving the Studio2400tri-head Anime Toon look into the game and explicitly required original GAME outline thicknesses. Live Web **627bb7d3b49f**, baseline **659a8eeb9299**; image `wiyazard:30500/zorx-web:anime-player-20261101-1@sha256:902f375be0e80cefaf8e7f62b982c573bfe9ae79e90bbde8c3007f80c14c2237`. Rollout Ready and live imageID/public downloaded model+core byte-exact verified. Web only; room worker, Nakama and profile image retained, including diagnostics rollback state.

## Model and look

- Simplified production `art/fashion/reference_player.glb` Head12,000 ->2,400tri, using the existing GAME rig/animation carrier. Did not replace game rig with donorStudio model. Original full carrier preserved in art_source/characters/reference_before_lowpoly/reference_player.glb.
- Full bare source geometry15,971 ->6,371tri (-60.1%), excluding hair/clothing/weapons/accessories and outline draw duplication. Visible skin masking under clothing can render less. Body3552 and otherfaceparts419 unchanged. Hair/clothing geometry untouched.
- Exact remaining position/normal/joint/weight subsets,96original neckline boundary edge coordinates preserved, no degenerate/nonmanifold triangles. All other mesh arrays, node hierarchy/rest transforms, inversebind matrices, animation sample values and embedded images identical. Modelrawbytes 15,691,224 ->14,967,860; this is not Web download size.
- Anime body/head three-band lighting: skin192/225/255 +6% skinfill; othercharacter materials95/175/250; eye12% mappedfill while preserving blink/iris/atlas. Helper identifies skin after existing material preparation.
- ORIGINAL GAME outlines deliberately retained. Existing renderer/outline shader untouched; named-mesh widths match actual deployed compiled baseline and generatedanonymous mesh normalized for comparison. No Studio .0016/.002/.003 outline settings migrated.

## Scoped packaging

Builder tools/web/build_anime_player_patch.py changes only four core scripts/shaders plus buildmetadata, and one existing character-pack entry `.godot/imported/reference_player.glb-0cee19094434737c1ee2f78e05274c5d.scn`. All other entries in that pack, otherpacks/engine/unrelated core entries proven byte-identical. Replaced the old model in its commonpack instead of appending a duplicate download. Player download change **-173,012bytes** (~173KB smaller); GPUtexturepacks unchanged.

## Evidence and limits

- Exact shipped extracted native check PASS: actualimportedhead2400, liveSkeletonbone/rest parity, exact old/newoutline values for threehair/outfit combinations, idle/walk/run,0/45/90views. Root/source numeric builder checks all animation samples, not only the reviewed clips.
- Exact shipped native_fashion_visibility PASS36checks. Source and exactshipped screenshots inspected; build/anime-live-red-(0, 45, 90).png.
- Full45s suite still known profile/cache/onlinefixtureFAIL+timeout; not allgreen. Native game-lighting review does not establish pixel-identical Three.js lighting or exhaustive armor/hat/weapon/skill visual parity. No physical-device FPS or authenticated browser gameplay claim. Actual publicWebcore/model bytes andReady imageID verified.
- No combat/economy/account/serverchanges, no account edits. Existing runtime blink/hair/cloth/weapon/skill code unchanged. Migration uses approved AnimeStudio look; material lighting differs by gameenvironment. Remaining broad Studio parity issues retain OPEN status.

## Deployment and rollback

Records /tmp/zorx-anime-player-release include beforedeployment, immutablebaseimage, four-file OCIoverlay manifest, tests/publicverification. Server game.yaml image synced with backup `.before-anime-player-20261101-1.bak`. Previousimage `wiyazard:30500/zorx-web:netfox-measure-20261031-1@sha256:bbd95f90faff2547a4048cfa803c000fd254d4c7108f0222c7a84bbcad1da6dd`. No broad dirty-tree source build or unrelated Git push. Develop fetched1e09287.

Future model regeneration: after root `tools/blender/finalize_reference_native.py` exports a fresh full carrier, run `python3 tools/art/prepare_anime_player.py` then Godotimport. Optimizer archives each fresh source byhash and preserves its current animations instead of restoring stale clips. Studio lowpoly generator is reused numerically without Blendergeometry export; native .blend source remains original.

Public verification:
- `core.db2d7a9b3c80.pck.wasm` SHA256 `1d8f99d6c324b044fbe35dca886aa3f79083ed7fcf7b51c98b1f26d07f201bbf`
- `characters.9bdc96cbee7f.pck.wasm` SHA256 `5890747f72d0eca157eb298ad269d05e34595cfd32668ec9bf8d911340023197`
