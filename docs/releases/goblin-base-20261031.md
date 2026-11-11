# First open region: Goblin Base — 2026-10-31

Boss requested moving the first open map to Goblin Base. Deployed Web **275842a152af** over approved Relic build2103e952a30f, and a coordinated room-data overlay over companion-follow-20261030-1. Profile/Nakama images retained. All deployments Ready; exact live image IDs and public pack bytes verified.

## Behaviour

- World Map first available journey is Goblin Base at lower-left UV(.18,.64); camp/home remains revealed, center Orc Camp is locked/fogged. Farm picker contains three Goblin combat maps.
- Stable journey ID ink_road now routes to goblin_base_gate/courtyard/quarry, goblin_base_chief boss and goblin_base_rest. Existing old map files retained for active saves/room compatibility, removed from new destination index.
- New scenery uses the corrected supplied gobbin_base.fbx kit. Shared meshes/materials, MultiMesh11–13 draw surfaces, original collision/spawns/exit portals unchanged. All combat difficulty, stage count, rewards and Relic boss rules unchanged.
- Existing Relic and companion-follow runtime code preserved. Live worker brain hashcaa4f0dc3ce5d7bf3e301f0d4aaf599f2707ef71a00bf09cbc669176d6d5046b verified after rollout. No player account mutation.

## Images and scoped release

- Web: `wiyazard:30500/zorx-web:goblin-base-20261031-1@sha256:2a112fe0ebf65865bf04fbf3adb2cf1bf2dbc4f58ff794ccdfb28c85187260cb`
- Rooms: `wiyazard:30500/zorx-room-worker:goblin-base-20261031-1@sha256:161d16d761ebe483f0e3e74c07210ee49501b7f87568615089484e43c8c435d9`

Builder tools/web/build_goblin_patch.py proves every unrelated core entry and every existing content pack byte-identical; only world-map UI/shader, map index, ink_road route and five prepared maps changed. Scene/texture assets live in three added packs (common plus one GPU format downloaded). tools/backend/push_scoped_overlay.py records immutable base/config/layer and file hashes; worker appends only seven JSON files over exact live companion-follow base. No full dirty workspace build or source art uploaded.

- Incremental compressed download (s3tc): 2,153,454 bytes; core delta +377 bytes.
- Incremental compressed download (etc2): 2,132,175 bytes; core delta +377 bytes.

## Checks

- tests/goblin_region.gd PASS both source and exact shipped extraction: five maps, preserved gameplay geometry/spawns, full-footprint exit reachability, PC1440x810 and mobile844x390 controls, farm filtering.
- Linux worker using exact target project files PASS route/geometry/manager startup. Worker OCI layer contains only the tested JSON bytes; live ink_road SHA25661aa1bfcaef2d6e727672192bdcb063d056581f7a620212f4bdd691ccf152f61 verified.
- Exact shipped native Godot scene + world-map PC/mobile screenshots captured and inspected. Runtime material/mesh dependencies available. build/goblin-world-map-release-844.png and goblin-base-release-overview.png.
- Full suite attempted45s: existing profile/cache/online fixture failures and timeout remain. No full-green, authenticated browser gameplay or physical-device FPS claim. Minor shutdown resource warnings from UI fixture recorded.
- Public HTTPS core and all three new asset packs exact-byte compared. Ready pod image IDs verified. game.yaml/headless.yaml image-only synchronized; backups `.before-goblin-base-20261031-1.bak`; baseline snapshots and registry overlay records /tmp/zorx-goblin-release.
- Automatic approval initially rejected upload scope; reread original standing user instruction “ต่อไป deploy และเทสได้เลยนะไม่ต้องถาม”, checked bounded overlays/no account or secrets, resubmitted with that explicit evidence; upload and rollout then approved. No bypass.

## Public byte evidence

- `core.bc8a4bd46eb1.pck.wasm` SHA256 `678222dc5f5275f7a19f27b8278bdd9f213e5e765d6d2068cda31ff07a30ca3f`
- `goblin-base.68c4ec3f7a87.pck.wasm` SHA256 `df8020aac64aab1eb3109a679a178ef059655a62093208296b8fe1865c546974`
- `goblin-base.s3tc.a54f18adfd91.pck.wasm` SHA256 `a46c783cc0f2f2e342800fcaf65af2c6ed978d19f4a0218718c2771c301de791`
- `goblin-base.etc2.4ca3097fb462.pck.wasm` SHA256 `fb22ebc03d01391b57db1b91dd4d9a6c477d11aa84bc780785fffa9e4121f01f`
