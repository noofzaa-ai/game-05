# Studio bow integration — 2026-10-26

**DEPLOYED: bow-20261026-1, Web e0e3e415f185, matching profile/room workers.** Web export `e0e3e415f185`; server profile/room workers must deploy with Web because catalog, shop and combat rules changed.

## Assets and parity

- Item `bow_01`, asset `weapon_bow_jade_01`; source `../art/items/weapons/bow.glb` copied unchanged:4028tri/cap5000, left `attach_weapon.L`, main grip at authored marker. Native93-joint skeleton/rest/weights unchanged. Three motion GLBs and timing JSONs copied unchanged from `../art/characters/reference-native/bow/`; includes StandBow/Bow_draw/Bow_shoot/Bow_heavy/bow_run/bow_dash. No old57-point or17-bone rig is introduced.
- Right-hand socket drives string contact using authored string_top/string_nock and source deformation weights. Dynamic vertex buffers avoid reallocating geometry every frame. Mint string tint follows source material. Held/flying arrow geometry follows Studio procedural dimensions/colors; flying position/hits belong to pure server simulation.
- Native Skill Lab bow casts keep their existing20clips. Held-arrow visibility follows Studio behavior allowlist and authored release time. Hair/blink/cloth/wing runtime remains shared native behavior.
- Godot poses inspected: idle/draw/release/heavy/run; capture directory `art_source/preview/bow_game/`. Inventory icon rendered from model at128px RGBA (transparent corners), not a white-background screenshot. Source Studio preview files stay outside game export.
- Reimport with `python3 tools/items/import_studio_bow.py`; render icon with Godot `--script res://tools/shots/bow_icon.gd`. Source hashes recorded in `build/studio-bow-import.json`.

## Gameplay

- Merchant offers only the new bow via explicit catalog_items allowlist, existing price1000Gold/tier0. Does not reopen the full retired merchant catalog. `shop_buy` performs server stock/price/capacity validation and atomic ownership/gold commit. No profile grant, item reroll or client ownership write.
- Existing paid full reskill100Gold is required before switching from another weapon tree; then equip bow and save bow Build. Same rules online/offline.
- Normal source GLB duration0.294117647s/release0.110726644s: quantized to60Hz18ticks(0.30s), release7(0.1167s). At0ATKSPD nominal3.33shots/s; one queued follow-up waits through full recovery, never resets the draw early.
- Heavy source2.5s/release1.5s:150ticks, release90. Normal power0.85/stamina4; heavy3.8/stamina14 are initial game tuning (Studio itself has no damage).
- Projectile base speed5m/s/range8m from Studio; bow-start passive adds10%speed after the base (5.5m/s). Tree projectile/range modifiers and equipment ATKSPD apply server-side. Frozen aim is normalized and exposed through existing skill_view, no new wire version. A queued follow-up can aim in a new direction.
- Release origin was measured from native rig + source release_nock_local, not client coordinates. `[forward,up,side]`: normal[0.039793,0.777480,0.238136], heavy[0.040243,0.587687,0.237836]. Projectiles collide with bodies/walls using existing authoritative combat/guard/i-frames/crit rules.
- Boss directive: **no sprint attack and no aerial attack**. Pure Combat rejects run/jump/air basic attacks; walking/running/jumping/dodging movement itself remains available. Bow never selects run/air attack variants. No old ultimate gauge/pack is added.
- Audio reuses existing short arrow/skill cues under bow aliases, with no new audio download. Gear info reports projectile range instead of unused melee hitbox reach and explains grounded shots.

## Validation and limits

Focused local authority checks pass: purchase+price+invalidSKU, mismatch+paidreset+readyBuild,7normal releases in2seconds, real damage, heavy release at1.5s/singlearrow, run/jump/air rejection, walls, checkpoint restore and free bow passive. Actual native/Godot gameplay renders inspected. Archive contains model +3motion carriers +3timingJSONs +icon, with0retired skill assets.

Web download: PC 81.26MB, mobile 81.50MB, about0.21MB added to optimized no-bow export. Full historical suite does not pass: legacy special/ultimate and removed wardrobe fixtures still fail; no full-suite, actual online two-client, physicalmobile or final balance acceptance claimed.

Final check: bow-equipped Run cast applied damage (enemyHP1000→920), SkillSystem checkpoint serialized/restored. Full historical suite stopped at180second timeout after legacy-special/ultimate and old wardrobe-fixture failures; not counted as passing. Final source also retains the held arrow during bow_run/bow_dash, matching Studio preview.
