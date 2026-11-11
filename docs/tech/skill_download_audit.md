# Skill release download audit — 2026-10-26

Local optimized Web build: `52c5302173fc`. **Not deployed.**

| Device texture format | Deployed UI release | Optimized export | Reduction |
| --- | ---: | ---: | ---: |
| s3tc | 98.32 MB | 81.05 MB | 17.27 MB (17.6%) |
| etc2 | 98.56 MB | 81.29 MB | 17.27 MB (17.5%) |

Decimal MB, includes engine/core/common packs + only the selected GPU texture format. Both GPU variants are published, but each device downloads one variant.

- Actual new icons:52PNGs128×128. Actual effect frames:936PNGs128×128. No oversized skill imagery found.
- Retired art/skills assets:13.22MB per-entry gzip estimate before removal, about12.95MB measured reduction in characters pack. Old sources retained for authoring; entire subtree excluded from Web archives. Existing legacy numerical metadata remains for combat compatibility and NPC special attacks.
- Six unused1254px combat-button images removed from Web export. The live v2atlas stays; imported UIatlas/shortcut sheet capped1024, keyboard512, alpha retained with WebPquality0.85. Combined measured core reduction about4.33MB. Original PNG sources unchanged.
- The atlas renderer now scales region and nine-slice coordinates to actual imported texture dimensions.
- Archive audit confirms0retired skill entries and0unused button images. Actual Godot mobile landscape1280×590 capture inspected: art_source/preview/skill_ui/mobile_hud_compressed_1280x590.png.
- Remaining major content: real goblin/mummy/hub scenery, native character/outfits/hair, current20skills/Gems and their effects. brush_ring is the active boss arena, not unused content. Further scenery geometry/animation/FXframe optimization requires visual comparison; no speculative savings claimed.

Full inventory: build/skill-size-before.json and build/skill-size-after.json; totals: build/skill-size-report.json. No deploy or physicalmobile/online performance claim.

2026-10-26 — bow-20261026-1 DEPLOYED with Boss explicit approval: Web e0e3e415f185 + matching digest-pinned profile/room workers; Nakama unchanged. Linux room-image focused bow authority checks passed; Web/headless rollouts successful, pods1/1+2/2ready0restarts, both worker startup logsready, publicmanifestmatches and15/15assetURLsHTTP200. New Studio bow atMerchant1000Gold with paidreskill familygate; no run/jump/airbasicattack. Includes retiredskill/UI payloadcleanup:PC81.26MB/mobile81.49MB from98.32/98.56MB. Actual device/co-op and fullhistorical suite acceptance remain unclaimed (oldfixtures fail/180secondtimeout). Release/rollback:build/bow-release.json,build/bow-rollback.json.
