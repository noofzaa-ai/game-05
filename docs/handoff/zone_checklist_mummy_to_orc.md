# Zone checklist: what the Mummy Pyramid took (template for the Orc Camp)

Written 2026-11-20 by the PO from the real work on the Sand Pyramid zone (commits 10860a44, 12e51169, 8fb8dad3 and the staging deploys of 2026-11-18/19). Use it as the starting list for `orc_camp` (zone order 3 in `data/world/zones.json`, boss "Orc Warlord"). Items marked **LESSON** are mistakes or surprises we hit; do them right the first time.

Rules fixed by the Boss that apply to every zone: the game is the NEW auto-battler (one fight, one 16x9 floating-island map picked from the zone's `arena_maps`, 9 waves, wave 9 = boss, no camps, no rest, no map switching, class = animation set, outfit follows the CLASS). Every zone has its OWN monster family (no family shared between two zone journeys: `tests/test_journey_families.gd`). Every boss except the goblin family has `CTRL_RES: 100`. Win rate target at the zone's level with tier-1 gear: about 70 percent. The Boss said players enhance gear and win more easily by themselves.

## 0. Decide first (ask the Boss before any agent starts)
- Orc identity: what are the 5 types (grunt, archer, knight, mage, boss) or another set? Boss decided for the mummies: the goblin family 1:1 and the boss is a PAIR in wave 9 (a big caster plus the zone's mini boss). Is the Orc finale also a pair, and what is the big boss?
- Boss's own model files? For the mummies the Boss supplied an FBX (189 MB, squeezed to 4.3k triangles). Ask for files early; compress to the budget.
- Zone unlock quest (data/world/zone_quests.json) and gear level (data/world/gear_levels.json, pyramid = 15): numbers for orc_camp.
- Zone theme words for the map: three island maps like the goblin and mummy ones (same size 16x9, spawns 3 players / 8 enemies, walls on 3 sides, open cliff in front).

## 1. Data and rules (combat-designer, level-designer)
- `data/journeys/orc_waves.json` (copy the shape of `mummy_waves.json`: `wave_mode: true`, 9 stages, `wave_power_by_squad` for 1 to 6 players, `wave_heal_fraction`, `arena_maps` = 3 maps, `_tuning` notes). **LESSON:** the loader still wants `boss_map` / `camp_map` keys of valid maps; point them at one of the three maps. Do not build separate boss or rest maps (we built and then deleted two for the pyramid).
- `data/maps/orc_*.json` x3 + `data/maps/index.json` + `data/ui/enemy_bars.json` map frames.
- Monsters in `data/combat/combat.json` (moves, areas, projectiles, AI, `looks[]`, `clips`, `run_clip_speed`, `model_height`, `hips_scale`), `data/combat/monster_vfx.json`, `data/loot/loot.json` tables, `data/races/rules.json` (`boss_types`, `elite_types`), `data/combat/vfx.json` keys.
- **LESSON:** monsters need real clips wired. For the mummies, four types had NO clips in fights for a day (the loader takes the first `looks` entry whose model exists, and none named `animations`), so they hopped on a sine and looked like floating. Always run `tools/monsters/mummy_wiring_probe.gd`-style check: which model and which clip set the fight really plays.
- **LESSON:** set `run_clip_speed` from the measured foot speed (3.8 m/s x (1 + MOVESPD/100)) or the feet slide.
- Damage and HP: the goblin family is the base. Boss 2026-11-19: mummies hit about 2x the original ATK with HP near the original. Check the player's HP actually drops (class_sim prints damage per wave). **LESSON:** the between-wave heal (`wave_heal_fraction` 0.4) hid all early damage; measure squad HP at each wave start and keep it carried forward.
- Statuses: bosses and elites must inflict statuses on the squad (bleed, curse, burn, slow, weaken, exhaust, wound, sunder; control only on telegraphed big moves, chance below 100). Resistance/accuracy have three layers now: general EFFECT_*, group CTRL_/DOT_/DEBUFF_, per effect (CTRL_STUN_RES, DOT_BURN_ACC ...); summed RES >= 100 = immune.
- Boss kit: more than one skill needs the data list `ai.skills` (each skill its own cooldown); the AI otherwise has only attack / special / escape. A "summon" mechanic does NOT exist (the Wizard's summon is visual only).
- Balance tool: `tools/balance/class_sim.gd -- journey=orc_waves seeds=60 level=<zone level> gear=0..1` (starter squad and a magic squad; record every sweep in `_tuning`).

## 2. Models and animation (monster-rigger, animator, character-artist)
- Role brief: `.claude/agents/monster-rigger.md`. **LESSON:** the harness could not call `monster-rigger` as an agent type in a running session (new agent files load at session start); use a general-purpose agent told to read the brief, or restart the session.
- Request sheets first: `docs/art/monster_requests/<monster>.md`. Rules in every sheet: at most 5,000 triangles, one flat-colour material (no baked ink, no PBR maps), model and each texture <= 450 KB, textures <= 1024 px lossy, shared 102-joint studio05 rig, extra bandage-style bones allowed, never touch `art/characters/studio05/**`.
- Clip libraries `art/animations/monster_clips_<stance>.glb/.json` built by `tools/monsters/build_clip_library.gd`. Give each type its own walk (grunt shamble, knight stomp, boss regal, caster hunch); only a floating boss may hover. Death should read (a plain fall shipped for the mummies; a dust/shatter effect was recommended).
- Tests: `tests/test_monster_rig.gd` (triangle/joint/size budgets, clip names, run_clip_speed equals the measured foot speed, run inside the 0.6 to 1.4x clamp, foot never leaves the floor). Windowed shots of idle/run/attack/hit/death at fight camera and phone size 844x390, LOOK at them.

## 3. Maps (level-designer)
- Three islands per zone built from the zone's own kit by `tools/maps/build_<zone>.gd` (see `build_mummy_pyramid.gd`, `build_goblin_base.gd`), meshes under `art/maps/<zone>/`, three merged meshes per map (floor, dressing, kit), triangles about 22 to 25k per map (goblin camps are 49 to 58k), stays in the battle pack folder.
- The client dresses `arena` maps through `client/arena_props.gd` (goblin: `build_camp`; pyramid: `add_pyramid_island` plus `GoblinGround.dressed`-style checks in `client/stage_view.gd`). A new zone needs its own variant check; do not copy goblin code. Debris and dust colours follow the map (`violent_vfx.gd` has goblin brown earth and mummy sandstone: add orc colours).
- Tests: `tests/test_map_data.gd`, a zone map test like `tests/test_mummy_pyramid.gd` (3 boards, same bounds and spawns, walls N/E/W, open front, budgets).

## 4. Boss loot and items (economy-designer, character-artist)
- Zone boss set `boss_<zone_boss>` with 5 stats-only pieces (necklace, earring, bracelet, ring, back) in `data/items/catalog.json` + `data/items/sets.json`, coin and relic materials in `data/camp/camp.json`, icons `art/items/boss/<boss>/` (96x96, same painted style as the goblin ones, tone checked against them: the first mummy batch was too saturated and had to be toned down), alias icons in `client/brass_icons.gd`, `data/loot/boss_loot.json` entry keyed by the zone id.
- **LESSON:** the gear level of a zone (`req_level`, `drop_level`) and `gear_purge` (removes non-starter req_level > 1 pieces once per account): check new pieces are not purged.
- Drops of weapons and shields now take a random race and class (Boss 2026-11-20, `data/loot/race_drops.json` `pick` block); no per-zone work.

## 5. VFX (tech-artist, daiyooo MCP)
- Boss skills with bundles under `art/vfx/monster/<id>/` (+ `data/combat/monster_vfx.json` keys) and the L3 light set in `data/combat/vfx.json` (`violence` block: preset, colour, scale per skill; phone variants; at most 3 violent blows per second on phones). **LESSON:** keep web pack growth in view (the pyramid bundles added about 10 MB; `tools/web/pack_layout.json`), and use sky_* presets for anything that falls.

## 6. World map, quest and unlock (game-designer, ux-ui-designer)
- `data/world/zones.json`: set `journey` for the zone (it stays "coming soon" while `journey` is empty). **LESSON:** wiring the zone to the map is not enough; check ONLINE: squad rooms must host the zone's journey (server/rooms/manager.gd derives the allowed journeys from zones.json; Nakama `rooms.ts` carries the `journey` field; the local Nakama container must be restarted after rebuilding `build/names-runtime/index.js`).
- Quest steps in `data/world/zone_quests.json`, shown by the hub quest box and the Quests panel (th/en text). Boss name on the map must match the real boss (we had "Mummy Pharaoh" after the High Wizard became the zone boss).

## 7. Verify and ship (qa, release)
- Order: `godot --headless --import`, touched tests, full suite vs `build/localstack/f2.txt` (31 known failures; report any NEW), `tests/test_squad_zone_rooms.gd`, then a REAL online solo FIGHT of the zone on the local stack with windowed shots at wave 1, a middle wave and the boss wave (`tools/localstack/scenario.gd -- --fixture <strong fixture> --open go_pyramid`-style mode; add `go_orc`). **LESSON:** we declared the online fix done before ever seeing the room start; it failed on the local stack only because the local Nakama was old, but the check found that. Do it every time.
- Deploy order when `server/`, `logic/` or `data/` changed: rooms/profiles worker first, then Nakama (only if `server/names/runtime` changed; build FROM the registry's last zorx-nakama image + `build/names-runtime/index.js` to dodge the heroiclabs 429), then web last. Keep `build/k3s-before-<TAG>.txt`, log digests in `build/pushed-images.log`, add a line to `AI_SYNC.md`.
- Phone: the Boss's iPhone is slow (16 to 30 fps after minutes of play). Every new effect and map needs a phone variant and a perf note in `docs/tech/performance_budget.md`.

## 8. Rough effort and order (mummy actuals as a guide)
1. Boss decisions + request sheets (day 0).
2. Models + rig + clips, maps and combat data in parallel (the long poles: models and clips).
3. Quest + zone wiring + loot set (small once ids are agreed; use fixed ids like `boss_<id>` so two agents can work at once).
4. VFX pass, win-rate tuning, online check, deploy.
