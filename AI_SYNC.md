# AI_SYNC — ประสานงานคน/AI ที่ทำ zorx (เริ่มใหม่ 2026-11-11)

ไฟล์นี้ประสานงานระหว่างคนและ AI หลายฝั่งใน repo นี้ **อ่านก่อนเริ่มงาน และอัปเดตก่อน push ทุกครั้ง**
ของเก่า (บันทึกงานก่อน 2026-11-11: online co-op, ย้ายตัวละคร, parity ฯลฯ) ถูกลบออกจากไฟล์นี้แล้ว ดูย้อนหลังได้จาก git history (`git log -- AI_SYNC.md`)
ลำดับอ่านตอนเริ่ม: `CLAUDE.md` → `AI_SYNC.md` (ไฟล์นี้) → `PROGRESS.md` → `docs/handoff/auto_battler_handoff.md` (AI ที่ไม่ใช่ Claude เริ่มที่ `AGENTS.md`)

---

## 1. ใครทำอยู่

| ฝั่ง | เครื่องมือ | หมายเหตุ |
|---|---|---|
| Boss (director) | — | เจ้าของโปรเจกต์ ตัดสินเรื่องใหญ่ คุยกับ PO คนเดียว (ไทย) |
| PO | Claude Code (main session) | ประสานงาน มอบงาน สรุปให้ Boss |
| ทีม agent | `.claude/agents/` (27 ตัว) | รายงานผ่าน PO เท่านั้น ภาพ 2D สร้างผ่าน Codex CLI (`docs/tech/codex_image_workflow.md`) |

## 2. กติกา git

1. แยก branch ตาม scope งาน ห้าม force push, ห้าม `reset --hard`/`clean -f` (มีกฎ deny ใน `.claude/settings.json`)
2. รวมเข้า `main` ผ่าน Pull Request เท่านั้น
3. **ไม่ commit/push เองจนกว่า Boss สั่ง** เลือก add เฉพาะไฟล์ที่แก้จริง (ไฟล์ `.import` ที่ Godot สร้างใหม่ตอน import อย่าใส่)
4. ก่อน push: รันเทสต์ทั้งชุด (`commands.test` ใน `project.yaml`) เทียบรายชื่อข้อที่พังกับ baseline อัปเดตหัวข้อ 3–4 ของไฟล์นี้ และ `PROGRESS.md` เมื่อมีการตัดสินใจสำคัญ

## 3. กติกาโค้ดและไฟล์ (ถ้าขัดกับ CLAUDE.md ให้ยึด CLAUDE.md)

- `logic/` = กติกาเกมล้วน ห้ามอ้างโหนด/ภาพ/`client/`/`GameState` (มีเทสต์ตรวจ) · `client/` = ภาพ/ปุ่ม/กล้อง · `data/` = เนื้อหาเป็นไฟล์ · ไคลเอนต์ห้ามคุยฐานข้อมูลตรง
- ไฟล์ที่สร้างจากสคริปต์ ให้แก้สคริปต์ ไม่แก้ผลลัพธ์ตรง (เช่น ด่าน goblin จาก `tools/blender/build_goblin_stages.py`)
- ไฟล์ที่ merge ยาก ห้ามสองฝั่งแก้พร้อมกัน ต้องจองในหัวข้อ 4 ก่อน: `.tscn`, `.glb`, `.blend`, รูปภาพ, `project.godot`, `client/stage_view.gd`, `client/character_model.gd`, `data/items/catalog.json`
- เรื่องที่ Boss ต้องตัดสินก่อน: โครงกระดูกตัวละคร, เปลี่ยนโครง logic/client, ทิศทางเกม, ลบ/เปลี่ยนชื่อระบบหลัก
- เครื่องมือ: Godot **4.7.2**, Blender **4.5.10 LTS**
- ห้าม commit: ของใน `.gitignore` (`.godot/`, `build/`, `art_source/`, `audio_source/`), ความลับ/โทเคน (`data/online.local.json`), ไฟล์เกิน 100 MB
- รักษา line ending เดิมของไฟล์ (LF/CRLF) เมื่อแก้ด้วยสคริปต์ · ไฟล์ `.sh` ต้องเป็น LF (`.gitattributes`)

## 4. งานที่กำลังทำ / ไฟล์ที่จอง

| ใคร | งาน | ไฟล์ที่จอง | สถานะ |
|---|---|---|---|
| ux-ui-designer via PO | Skills tab บนมือถือ (layout แบบ compact) | `client/skill_tree_tab.gd`, `client/card_tokens.gd` (TREE_COMPACT_* / TREE_SHEET_W / TREE_NODE_MIN_COMPACT) | เสร็จ ยังไม่ commit 2026-11-13 |
| PO + ทีม | เกจ/ชื่อท่าอัลติบนจอ, VFX อัลติ, กลไก skill tree 37 ช่อง, ลด VFX หนัก 5 ท่า, ทำนายสกิลเคลื่อนที่ออนไลน์, Skills tab บนมือถือ, วัด solo/duo | (จองตอนมอบงาน) | เริ่ม 2026-11-13 |
| gameplay-programmer via PO | กลไก skill tree 37 ช่อง + reflect/death_save + event/pilot_mod ของ node | `logic/skill_tree_mechanics.gd`, `tests/test_skill_tree_mechanics.gd` (+ hook เล็กๆ ใน race_passives, combat, effects, class_skills/engine, use_rules, auto_pilot, skill_tree_effects, race_ultimates) | กำลังทำ 2026-11-13 |
| network-programmer via PO | online squads chunk 1-4 (design/gdd/online-squads.md 9) | `logic/coop_journey.gd`, `logic/squad_member.gd`, `logic/combat_data_loader.gd` (coop parse), `data/combat/combat.json` (coop), `data/journeys/goblin_waves.json` (wave_power_by_squad), `server/rooms/room.gd`, `server/rooms/manager.gd`, `tests/test_online_squads.gd` (ใหม่); แก้เล็กเฉพาะจุด: `logic/race_passives.gd` (synergy group), `logic/game_sim.gd` (enable_coop cap, _give_drop ต่อผู้เล่น) | กำลังทำ 2026-11-13 |
| ui-programmer via PO | เกจอัลติ + ป้ายชื่ออัลติ + VFX อัลติ 20 ตัว | `client/squad_panel.gd`, `client/stage_view.gd` (เฉพาะจุด ultimate_cast), `client/card_tokens.gd` (โทเคน SQUAD_HUD_ULT*/สตริง ult_*), `client/skills/race_ult_vfx.gd` (ใหม่), `art/vfx/race_ult/` (ใหม่), `tools/web/pack_layout.json` | เกจ+ป้ายชื่อเสร็จ (ยังไม่ commit), VFX ยังไม่เริ่ม 2026-11-13 |
| network-programmer via PO | online squads chunk 5 (wire + client): meta.squads/synergy/auto_continue, client spectates, my-cards camera, owner name plates/tint, squad panel mine-first, synergy banner, leader route buttons + countdown, hub "Play online" entry | `server/rooms/room.gd` (`_squad_meta` + 1 line in `public_state`), `client/session/online_session.gd` (squad helpers), `client/session/netfox_session.gd` (spectate guards), `client/squad_panel.gd` (owners), `client/stage_view.gd` (squad room hooks), `client/online/squad_room_hud.gd` (new), `client/card_deck_screen.gd` (online button), `tests/test_online_squads.gd`, `server/rooms/smoke.py` (--squad-rooms) | done, not committed 2026-11-13 |
| network-programmer (skill net) via PO | ทำนาย/แสดงสกิลเคลื่อนที่ออนไลน์ (skill_net/race_net, wire v3) | `logic/net_wire.gd`, `logic/net/skill_net.gd` (ใหม่), `client/session/online_session.gd`, `client/session/netfox_session.gd`, `runtime/netfox/remote_state.gd`, `client/fighter_view.gd` (เฉพาะ `_show_class_skill`), `tests/test_skill_net.gd` (ใหม่); `logic/game_sim.gd` (`_predict_class_travel` ใหม่ + เรียก 1 บรรทัดใน `tick`), `server/rooms/room.gd` (1 บรรทัดใน `public_state`), `server/rooms/netfox/service.gd` (protocol 4), `data/perf/scenario.gd`, `tests/run_all.gd`; engine.gd ไม่ได้แก้ | เสร็จ ยังไม่ commit 2026-11-13 |
| combat-designer via PO | จูน solo/duo (Option A) | `data/journeys/goblin_waves.json` (เฉพาะ wave_power_by_squad[0..1]), `data/classes/*.json` (บล็อก `solo`), `logic/race_passives.gd` (`fights_alone` + แนบบล็อก solo ใน attach), `logic/race_data.gd` (ตรวจบล็อก solo), `tests/test_race_passives.gd` (_synergy), `tools/balance/class_sim.gd` (power<N>= / only=solo:x) | เสร็จ ยังไม่ commit 2026-11-13 (solo 65-73%, duo 77%, ทัพ 3 ตัว 73%; เทสต์ fail ชุดเดิม 38) |
| gameplay-programmer via PO | remove legacy item system (po_defaults 'Remove legacy item system'), chunks 1-3 | `tools/items/build_race_gear.py`, `data/items/{catalog,sets,starter_kits,shop,armor_migration,equipment_tuning}.json`, `data/loot/race_drops.json`, `logic/race_drops.gd`, `logic/item_catalog.gd` (race_shield), `logic/profile.gd` (starter kit/shield, legacy_item_version), `logic/legacy_items.gd` (new), `logic/run.gd` (bag conversion, 3 lines), `server/profile/runner.gd` (1 line), `tests/test_legacy_items.gd` (new), `tests/run_all.gd` (1 line), `logic/armor_migration.gd`, `client/item_assets.gd`, legacy art deletion (art/armor/{ash,obsidian,royal}_*, art/weapons/blade*, art/items/), `export_presets.cfg` / `tools/web/pack_layout.json` (filters only), tests: test_race_drops, test_starter_kit, test_offhand_slot, test_item_catalog, test_race_sets, test_beta_cleanup | chunks 1-2 done, not committed 2026-11-14 |
| character-artist via PO | race greatsword / longbow / staff (MID tier, 12 GLB + 12 icons + 9 textures) | `tools/items/split_race_outfits.py`, `art/weapons/race_<race>/{greatsword,longbow,magic}.glb` + `icon-*.png`, `art/weapons/race_shared/*_weapons_*.png`, `client/characters/studio05_character_model.gd` (`_wear_race_weapon` + `weapon_kind`), `tools/shots/race_outfit_shots.gd`, `tools/shots/race_outfit_sheet.py`, `docs/art/race_gear_handoff.md` | done, not committed 2026-11-13 |
| ui-programmer (boot) via PO | no title screen: boot -> hub always, failed sign-in -> hub offline + "Offline · Reconnect" pill; loading page restyled to the hub look | `client/pack_loader.gd`, `client/online/online_account.gd` (reconnect pill), `client/card_deck_screen.gd` (back target only), `client/character_creator.gd` (close target), `client/card_tokens.gd` (online_reconnect/online_sign_in strings), `tests/test_title.gd`, `tools/web/play_template.html`, `tools/web/static/` (new), `pipeline/build_web.py`, `tools/web/build_web.ps1` | done, not committed 2026-11-14 |
| character-artist (race heads) via PO | Boss race heads: import + race look on cards/battle | `art/characters/studio05/v1111/race/` (race_heads.glb + extracted paint PNG + README), `data/races/*.json` (`look` only), `client/characters/studio05_character_model.gd` (race head merge, `set_race_look`), `client/characters/studio05_toon.gdshader` + `studio05_ink.gdshader` + `card_ink_hull.gdshader` (`rest_in_custom`, paint uniforms), `client/item_assets.gd` (`card_appearance` race), `client/card_character_screen.gd` (`_change_race` portrait refresh), `tests/test_race_look.gd` (new) + `tests/run_all.gd`, `tools/shots/race_heads_shots.gd` / `race_heads_battle.gd` / `race_heads_sheet.py` (new) | done, not committed 2026-11-14 |
| character-artist (hair I) via PO | Boss hair I: import + Tailor option | `art/characters/studio05/v1111/hair/hair_i.glb` (+ texture), `art/characters/studio05/split/manifest.json`, `tools/characters/split_studio05_hair.py`, `data/classes/*.json` (`hair_options` only), `client/characters/studio05_character_model.gd` (hair lists only), `client/hub_tailor_panel.gd` (default hair colour list), `tools/shots/hair_i_shots.gd` + `hair_i_sheet.py` (new) | done, not committed 2026-11-13 |
| network-programmer via PO | squad room live bugs (ghost enemies, stacked HP bars, wave label, old HUD buttons, smoothness) | `client/stage_view.gd` (one view per id, wave label, ult move stub), `client/session/online_session.gd` (`known_move`), `client/session/remote_journey.gd` (wave), `client/network_status.gd` + `client/party_hud.gd` (old buttons hidden in squad rooms), `server/rooms/room.gd` (`_prune_corpses`, meta.wave_mode/wave), `tests/test_online_squads.gd` | done, not committed 2026-11-14 |
| ui-programmer (fight loading) via PO | FIGHT: summon animation removed, carved loading overlay with real progress (pack download + threaded stage/resource load, "Connecting…" online) | `client/fight_loading.gd` (new), `client/card_deck_screen.gd` (summon removed, `_start_fight`), `client/card_tokens.gd` (FIGHT_LOAD_* tokens + strings; SUMMON_*/BURST_* removed), `client/online/room_panel.gd` (1 line), `tools/shots/fight_loading_shots.gd` + `fight_freeze_measure.gd` (new), `tools/shots/card_deck_smoke.gd`/`card_deck_live.gd` | done, not committed 2026-11-14 |

## 5. สถานะปัจจุบัน (สรุปสั้น)

- Auto-battler: จัดทัพ 3 การ์ด สู้เอง 12 เวฟ การ์ด = คลาส (ดาบโล่/ดาบใหญ่/ธนู/เวท) × เผ่า (Human/Viking/Elf/Runeborn) เลือกเผ่าฟรีในหน้าตัวละคร
- ระบบ: พาสซีฟ+อัลติเผ่า 16+16, synergy ทัพ, สกิลคลาสใหม่ 16 ท่า + VFX (daiyooo-vfx MCP), skill tree การ์ด 25 ช่อง (37 กลไกพิเศษยังไม่ต่อ), เลเวลการ์ด, ชุดเผ่า (อาวุธ+เสื้อ/กางเกง/ปลอกแขน/รองเท้า, ออปชัน 2/4/5 เมื่อเผ่าตรง), ไม่มีช่องหัวแล้ว
- ระบบสกิลเก่า, แฟชั่น, หน้า/ผม/ตาโมเดลเก่า ลบแล้ว · HP สเกล 100 · ทัพเริ่มต้นชนะ ~75% (wave power 2.01)
- ภาพ: drawn style ink_c เป็นค่าเริ่มต้น + พื้นสีน้ำ · ชุดเผ่าเริ่มต้นจาก Studio (`race_outfits.glb`) ใช้ทุกคลาสชั่วคราว รอ 16 ชุด + อาวุธเผ่า 16 ชิ้น (`docs/art/race_gear_handoff.md`)
- เทสต์: **3024 ผ่าน / 38 พัง** (baseline เทียบรายชื่อ), SCRIPT ERROR 3 ตัวเดิม · ค่าที่ PO เลือกแทน Boss: `docs/po_defaults.md`
- เว็บ dev: `pipeline/build_web.py` บน Windows, เล่นผ่าน Tailscale Serve `https://wp.taild7b145.ts.net/play.html` (tailnet เท่านั้น)

## 6. บันทึก sync (ใหม่สุดอยู่บน, บรรทัดละครั้งที่ push)

- 2026-11-14 | tech-artist via PO | develop | landing trail v2: ทัพ 4 เผ่าที่กองไฟเป็นตัวละคร Studio ของเกมจริง (`server/landing/dashboard/assets/squad_<race>.glb` 2.31 MB สร้างด้วย `tools/landing/build_landing_squad.mjs`, idle 1 ท่า), ลุคหมึก toon + เส้นขอบทุกสถานี, จุดที่ 08 LOGIN หลังประตู FIGHT; server เสิร์ฟ .glb; live `zorx-landing:trail3d-v2-20261114@sha256:1ea463b8` (checklist §10, ตัวเลข perf ใน performance_budget.md)
- 2026-11-14 | gameplay-programmer via PO | fix/autopilot-checkpoint (not pushed) | Boss: game is just ZORX (loading page title/subtitle "Squad of Four Races", title screen tagline) and the Relic system is removed (logic/relics.gd, relic_effects.gd, data/relics, art/relics, client/relic_orbit.gd, relic_equip, boss relic drop, relic_goblin_poison, hub Relics entry -> 5-entry menu step 140). Old saves with relics/relic_loot load and drop the field (tests/test_relics_removed.gd). **net_wire VERSION 3 -> 4** (relic_state left FIGHTER_FIELDS): web + headless room-worker + Nakama runtime (plaza.ts) must deploy together. Tests 3260 pass / 32 fail (baseline 3244/34, no new failures)
- 2026-11-14 | PO + release-manager | develop 6c8724f -> k3s zorx-staging | FULL (net_wire 3 -> 4, Relics removed): web zorx-web@sha256:65b62628a663 (build 6947cceda7ce, boot 41.10 MiB, online.local.json in) + headless rooms zorx-room-worker@sha256:6f27267d72b8 + profiles zorx-name-validator@sha256:43b422e297d7 set together, ZORX_SQUAD_ROOMS=1 kept; nakama NOT rebuilt (upstream 429; old plaza runtime compatible, client ignores the extra relics field); pods Ready, 0 SCRIPT ERROR, room-v2 101; rollback (web + headless together): build/k3s-staging-before-6c8724f.yaml + docs/tech/k3s_release_checklist.md section 9.
- 2026-11-14 | ux-ui-designer via PO | develop | เว็บ landing zorx.daiyooo.com เปลี่ยนเป็นลุคไม้แกะสลัก/หมึก (overlay `server/landing/dashboard/` + ซอร์ส `../zorx_web` git ในเครื่อง, baseline = ซอร์สของ Boss) ขึ้น staging แล้ว digest `cd7056e9…` · ขั้นตอน/rollback: `docs/tech/k3s_release_checklist.md` §10 · การล็อกอิน Google/Guest ต้องให้คนทดสอบ
- 2026-11-14 | character-artist via PO | fix/autopilot-checkpoint (not committed) | Race heads: `v1111/race/race_heads.glb` (same 102-joint rig/binds) shown per card race (Elf ears, Viking war paint, Runeborn runes; Human = default head) on hub cards, character screen, Tailor and battle; data in `data/races/*.json` "look"; shots `art_source/codex_review/race_heads_2026-11-14/`
- 2026-11-14 | PO + ui-programmer + tech-artist | develop | My Cards hub rebuilt to Boss target (art_source/boss_refs/hub_inkwash_2026-11-14/hub_TARGET_carved.png): carved gilded-wood frames per class, art/ui/hub_carved/ (34 Codex images), client/carved_strip.gd; card portraits get card-only ink look (card_ink flag, client/characters/card_ink_hull.gdshader); battle/Studio unchanged
- 2026-11-14 | PO + release-manager | develop 2caa255 -> k3s zorx-staging | web only: zorx-web@sha256:d15e4f18ef2a (build 659998a286cd, status VFX in core pack, online.local.json in), headless unchanged (no server/logic/data change), ZORX_SQUAD_ROOMS=1 kept; pods Ready, 0 SCRIPT ERROR; boot download +2.0 MiB; rollback: build/k3s-staging-before-2caa255.yaml + docs/tech/k3s_release_checklist.md section 9.
- 2026-11-14 | PO + release-manager | develop 491a821 -> k3s zorx-staging | web only: zorx-web@sha256:e000247fd46e (build 72b76b00f9a1, art/ui/hub_carved in core pack, online.local.json in), headless unchanged (no server/logic/data change), ZORX_SQUAD_ROOMS=1 kept; pods Ready, 0 SCRIPT ERROR; boot download +11.9 MiB (lossless hub_carved PNGs); rollback: build/k3s-staging-before-491a821.yaml + docs/tech/k3s_release_checklist.md section 9.
- 2026-11-14 | PO + release-manager | develop 899797d -> k3s zorx-staging | web only: zorx-web@sha256:49ff224f71a0 (build 2ab88cc3a193, boot download 68.8 -> 41.1 MiB, art/vfx/status in vfx battle pack, carved loading page webp 200, online.local.json in), headless unchanged, ZORX_SQUAD_ROOMS=1 kept; pods Ready, 0 SCRIPT ERROR; rollback: build/k3s-staging-before-899797d.yaml + docs/tech/k3s_release_checklist.md section 9.
- 2026-11-14 | PO + release-manager | develop ab543cd -> k3s zorx-staging | web only: zorx-web@sha256:5d1bcc12657b (build dc6a09b24cb7, boot download 41.44 MiB, online.local.json in), headless unchanged, ZORX_SQUAD_ROOMS=1 kept; pods Ready, 0 SCRIPT ERROR, 0 web 5xx; rollback: build/k3s-staging-before-ab543cd.yaml + docs/tech/k3s_release_checklist.md section 9.
- 2026-11-14 | PO + release-manager | develop 2fd4ce4 -> k3s zorx-staging | web only: zorx-web@sha256:b134ed738dae (build 28a9beed4275, boot download 41.41 MiB, race_heads.glb + fight_loading in packs, online.local.json in), headless unchanged (race look field is client-only), ZORX_SQUAD_ROOMS=1 kept; pods Ready, 0 SCRIPT ERROR, 0 web 5xx; rollback: build/k3s-staging-before-2fd4ce4.yaml + docs/tech/k3s_release_checklist.md section 9.
- 2026-11-14 | PO + tech-artist + ui-programmer | develop | status tint removed (statuses no longer recolour fighters; hit flash 18%/0.08s), 11 daiyooo status loops + cyan immune ring (client/status_vfx.gd, art/vfx/status/), tap squad plate = camera follows that fighter, result panel with tappable buttons (client/result_panel.gd) replaces Enter/Esc/R hints
- 2026-11-13 | PO + release-manager | develop a4744e5 -> k3s zorx-staging | first k3s deploy from this dev PC (kubeconfig scoped to zorx-staging/zorx-production): web a2bae67f9c20, room-worker and name-validator from a4744e5, equipment-tuning ConfigMap HP-100; https://zorxplay.daiyooo.com/ smoke OK; nakama unchanged (upstream 429); ZORX_SQUAD_ROOMS off; rollback: build/k3s-staging-before-20261113.yaml + docs/tech/k3s_release_checklist.md 9
- 2026-11-13 | character-artist via PO | fix/autopilot-checkpoint (not committed) | Hair I added for every class (Tailor hair button "Hair I"): `v1111/hair/hair_i.glb` same rig/binds as body, head-weighted like G, tinted by card hair_color; shots `build/hair_i/`
- 2026-11-13 | PO | develop (push) | รวมงานวันที่ 13 พ.ย. 26 commit: ลบสกิลเก่า/แฟชั่น, สกิลคลาสใหม่+VFX MCP, อัลติเผ่าครบ, skill tree+Skills tab, UI เผ่า, HP 100+จูน 75%, ชุดเริ่มต้น+ชุดเผ่า+ดรอป (ไม่มีช่องหัว), drawn style+พื้นสีน้ำ, หน้าตั้งค่าใหม่, ถาดทัพแบบสัญลักษณ์, touch การ์ด · เทสต์ 3024/38
- 2026-11-13 | character-artist via PO | fix/autopilot-checkpoint (not committed) | race starter outfits + race S&S weapons on the Studio body: `art/armor/race_shared/` (16 GLB + atlas + 16 icons), `art/weapons/race_<race>/` (sword_shield.glb, shield.glb, 2 icons each) + `art/weapons/race_shared/` textures, `tools/items/split_race_outfits.py`, fallback chain in `client/item_assets.gd`, per-slot Studio-rig armour/weapon/shield + body cover in `client/characters/studio05_character_model.gd`, `build_race_gear.py` (OUTFIT_SCOPE, race shields `race_<race>_shield`), shots `tools/shots/race_outfit_shots.gd` / `race_outfit_sheet.py`; handoff + GDD 3.11 + parity doc updated
- 2026-11-13 | gameplay-programmer via PO | fix/autopilot-checkpoint | race gear drops: `data/loot/race_drops.json` + `logic/race_drops.gd` (kill drops in game_sim, chest in journey + room; gold race only from boss, race from the squad) · item detail race set line (`ItemText.race_set_lines`, card_tokens `set_race_*`) · docs: race-gear-sets.md fixed (no hat, weapon in set, 80 pieces), drops-and-rewards.md 3.8, `docs/art/race_gear_handoff.md` · tests 3005/39 (same failure names)
- 2026-11-13 | tech-artist | (ยังไม่ push) | VFX สกิลคลาสลด draw call: `class_skill_vfx.gd` `_slim` เปลี่ยน phase ที่ซ่อนด้วย scale 0.0001 เป็น visible (ภาพเหมือนเดิม 100%) + สร้าง crater_leap/hook_sweep/starfall/intercept/iron_guard ใหม่ให้อนุภาคน้อยลง · ทุกตัว <=100 draw/ชิ้น · เว็บ 844x390 26.8→30.7 fps · VFX อัลติเผ่า (race_ult, รับต่อจาก ui-programmer) ค้าง: daiyooo-vfx quota เต็ม 19:59
- 2026-11-13 | tech-artist | (ยังไม่ push) | VFX สกิลคลาส 16 ตัว (daiyooo-vfx) เข้าเกมแล้ว: `client/skills/class_skill_vfx.gd` (pool+prewarm, เล่นตาม event `class_skill_*`) ต่อจาก `stage_view.gd`; `art/vfx/class_skills/` อยู่ pack `vfx` (battle); UI `art/ui/skill_tree`+`class_cards` ย้ายไป pack `ui` (boot) และ import เป็น Lossy 0.85 → core 38.7→4.2 MiB; ปุ่มทดสอบเว็บ `play.html?class_vfx=0`

- 2026-11-13 | PO | develop | การ์ดในฮับขยับทุกเฟรม (เดิมการ์ดที่ไม่ได้ชี้ redraw 5 ครั้ง/วิ) `card_deck_screen.gd` · วัดบนเดสก์ท็อป 1920x1080 ไม่มีเมาส์ชี้: เฉลี่ย ~1,560 fps, ต่ำสุด 354 fps (`tools/perf/hub_fps.gd`) · ยังไม่ได้วัดบนมือถือ/เว็บ

- 2026-11-13 | gameplay-programmer via PO | develop | ท่าไม้ตาย Human 4 ท่าใช้ได้จริงในการสู้ (Commander's Call, Masterstroke, Called Shot, Grand Recital) + ตรวจข้อมูลท่าไม้ตายเข้มงวดตอนโหลด · GDD 3.6 เพิ่มฟิลด์พิเศษ 5 ตัว · เทสต์ 2622/80

- 2026-11-13 | gameplay-programmer x2 via PO | develop | เลเวลการ์ด: `logic/card_progress.gd`, `data/progression/card_levels.json`, XP จ่ายตอนจบรอบ (`journey.card_xp`) · เครื่องยนต์ท่าไม้ตายเผ่า: `logic/race_ultimates.gd` (cast/ยกเลิกเมื่อมึน/ตาย, zone, skill_refresh, burst v2, revive), pilot ยิงตามเงื่อนไข, status valor/unbowed/recital · ยังไม่มีท่าไม้ตายในข้อมูลเผ่า (C2-C5) · เทสต์ 2581/80

- 2026-11-13 | ux-ui-designer via PO | develop | อาร์ต skill tree เข้าเกมแล้ว `art/ui/skill_tree/` (ไอคอน 112, กรอบ 11, ตรา 4, แผนที่, `manifest.json` node id -> ไอคอน) · ยังไม่มีโค้ดแท็บ Skills ใช้ · Codex รวม 145 ครั้ง

- 2026-11-13 | gameplay-programmer via PO | develop | เกจท่าไม้ตายเผ่ากลับมา (`ultimates_enabled`, กติกาเกจใน rules.json, อัตราต่อคลาสใน data/classes, เติมใน race_passives) ระบบสกิล/motion prediction ไม่ล้างเกจของการ์ดเผ่าแล้ว · เกจเต็มแต่ยังไม่มีท่าไม้ตายให้ใช้ (chunk C) · class_sim ใช้ reaction ของคลาส · ห้องออนไลน์ยังไม่ได้ทดสอบ · เทสต์ 2486/81

- 2026-11-13 | gameplay-programmer via PO | develop | คลาสต่างกันชัดขึ้น: `pilot` ต่อคลาสใน data/classes (ดาบโล่ peel, ดาบใหญ่ densest+heavy ทุก 3, ธนู lowest_hp/บอส+kite, เวท hold skill/frost_armor), Cleave (+15%/ศัตรูเพิ่ม max 45%), Hunter's Mark (sunder ตีแรกเป้าใหม่ + ทัพรุมเป้ามาร์ค) · class_sim ยังส่ง reaction 0.85 ทับค่าคลาส · เทสต์ 2454/81

- 2026-11-13 | gameplay-programmer via PO | develop | เผ่า ขั้น 4.5: taunt ใน `enemy_ai.gd` (`GameSim.taunt_enemy`), `pulse_aggro`, Bulwark ของดาบโล่ (signature ใน sword_shield.json), Unbroken pulse · passive เผ่าครบ 16 ช่อง · class_sim นับ race_burst_hit · ทัพชนะ 100% ยังไม่จูน · เทสต์ 2424/81

- 2026-11-13 | gameplay-programmer via PO | develop | เผ่า ขั้น 4.4: `charges` (อักษร Runeborn สะสมข้ามเวฟ, เก็บใน checkpoint) + `burst` (ระเบิดวง ATK x atk_mul หัก DEF) ทั้ง 4 ช่อง Runeborn + Trio rune gain · event race_runes/race_burst/race_burst_hit · class_sim ยังไม่นับดาเมจ burst · เทสต์ 2404/81

- 2026-11-13 | gameplay-programmer via PO | develop | เผ่า ขั้น 4.3: `skill_mod` ใน `skills/system.gd` cast() (Human greatsword/longbow crit/magic, Viking Blood Rite, Human default/Pair/Trio), cooldown ต่ำสุด 0.6x · event ใหม่ race_hp_cost · เทสต์ 2383/81

- 2026-11-13 | gameplay-programmer via PO | develop | เผ่า ขั้น 4.2: `low_hp_scaling` (Viking Berserker, Viking Pair/Trio/default ATK ตอนเลือดน้อย) คิดสดใน `Fighter.stat()` · เทสต์ 2370/81

- 2026-11-13 | gameplay-programmer via PO | develop | เผ่า ขั้น 4.1: โล่ของนักสู้ (cap 30% max HP, ดูดดาเมจก่อน HP ทุกทาง, หายตอนจบเวฟ, event race_shield/race_shield_end) · ยังไม่ส่งผ่าน net_wire ออนไลน์ · เทสต์ 2360/81

- 2026-11-13 | gameplay-programmer via PO | develop | เผ่า ขั้น 2+5: `logic/race_passives.gd` (stat_mod/trigger, event จาก sim) ทำงานในฉากสู้ + โบนัสทัพ (Trio/Pair/Alliance) คิดตอนเริ่มรอบ, `journey.synergy()` · event ใหม่ race_proc/race_heal (เสียงยืม buff_up/rest) · ทัพชนะ 100% (ปิดเผ่า 70%) ยังไม่จูน รอขั้น 4+ท่าไม้ตาย · เทสต์ 2344/81

- 2026-11-13 | gameplay-programmer via PO | develop | เผ่า ขั้น 1: `data/races/*.json` (4 เผ่า + rules.json), `logic/race_data.gd` (ตรวจเข้มงวด), การ์ดมี `race` (เซฟเก่าได้เผ่าเริ่มต้น), คำสั่ง `card_race` · ยังไม่มีผลในการสู้ (ขั้น 2) · เทสต์ 2297/81

- 2026-11-13 | game-designer via PO | develop | GDD skill tree ใหม่ `design/gdd/skill-tree.md` (25 ช่อง/การ์ด: คลาส 16 + เผ่า 8 + combo 1, แต้มถาวรจากเลเวลการ์ด, ไอคอน 112 ชิ้น) ยังไม่ทำโค้ด ตัวเลขยังไม่วัด

- 2026-11-13 | game-designer via PO | develop | GDD เผ่า v2: ท่าไม้ตายเผ่า 16 ท่า + กติกาเกจ + action ใหม่ `zone`, `skill_refresh` + สวิตช์ `ultimates_enabled` (ยังไม่ได้ทำโค้ด ตัวเลขยังไม่วัด)

- 2026-11-13 | tech-artist via PO | develop | ลดขนาดเว็บ: ตัดของเก่าออกจาก export (`export_presets.cfg` exclude_filter), texture ชุดเกราะ/Hair G 1024 (metal-rough 512), โหลด 2 ช่วง boot/battle (`pack_layout.json` stage, `client/pack_fetcher.gd`, FIGHT รอ battle pack) · โหลดแรก 222 MB -> 65 MB, เบื้องหลัง 21 MB · ทางเข้าสู้ใหม่ต้องเช็ก `PackFetcher.battle_ready()` · เทสต์ 2255/81

- 2026-11-13 | game-designer via PO | develop | GDD เผ่า × คลาส `design/gdd/races-and-classes.md` (ร่าง ตัวเลขยังเป็น placeholder ยังไม่ได้วัด) รอ Boss ตอบ 4 ข้อ

- 2026-11-13 | character-artist via PO | develop | แยกผมออกจากตัว: `art/characters/studio05/split/` (body ต่อคลาส + hair_*.glb + outfit_silver_silk) จาก `tools/characters/split_studio05_hair.py` (คัดลอก byte ตรง, rig/weights ไม่เปลี่ยน) 200 MB -> 30 MB · ไฟล์ตัวละครเต็มตัวเก่า 28 ไฟล์เกมไม่ใช้แล้ว (ยังไม่ลบ) · เทสต์ 2238/81

- 2026-11-13 | PO | develop | Boss: ตัดหน้า title ออก boot -> หน้าการ์ดเลย (`client/pack_loader.gd` `_open_game`): มี session บัญชีจากหน้าเว็บ = ล็อกอินออนไลน์ก่อน (ล้มเหลวถึงกลับหน้า title), ไม่มี = เล่นออฟไลน์ · เว็บ build 8442ee5d7712 · เทสต์ 2225/81

- 2026-11-13 | PO | develop | `play_template.html`: บน localhost/127.0.0.1 ข้ามการล็อกอินบัญชีออนไลน์ (เล่นออฟไลน์บนเครื่อง dev) เว็บจริงยังต้องล็อกอิน · ขนาดดาวน์โหลดครั้งแรก 222 MB

- 2026-11-13 | PO | develop | build เว็บสำเร็จบนเครื่อง dev (Windows): `build/web` build 1a135457db4a, Godot 4.7.2 web templates ติดตั้งแล้ว · บน Windows ต้องรัน `python -X utf8 pipeline/build_web.py` (python3 เป็น Store stub, log เป็น cp1252) · ขั้นเทสต์ใน pipeline ต้องการ 0 fail แต่ baseline มี 81 ข้อเก่า -> ใช้ --skip-tests หลังรันชุดเทสต์แยก · Docker Desktop ยังไม่ได้ติดตั้ง (ต้องสิทธิ์ admin)

- 2026-11-13 | PO | develop | Boss: เครื่อง Windows นี้ = dev (build/run Docker ที่นี่), k3s = prod ยังไม่ขึ้น · สร้าง `develop` จาก feature/class-weapons-card-screen

- 2026-11-13 | character-artist via PO | feature/class-weapons-card-screen | แก้สีชุดเกราะคลาสซีด: texture ถูกแปลง sRGB ซ้ำ 2 รอบบน gl_compatibility (`source_color` ไม่ decode) -> decode เองใน `studio05_toon/ink.gdshader` (Hair G ด้วย) ตรงกับ Studio แล้ว · เทสต์ 2224/82

- 2026-11-13 | gameplay-programmer via PO | feature/class-weapons-card-screen | การ์ดมีสีผม `hair_color` (#rrggbb, ""=ค่า Studio) ตามช่องสีอิสระของ Studio · Tailor มีที่เลือกสีผม · ผู้เล่นใหม่สุ่มสีผม 4 ใบไม่ซ้ำ (`data/cosmetics/starter_hair_colors.json`) · เทสต์ 2224/82

- 2026-11-13 | gameplay-programmer via PO | feature/class-weapons-card-screen | วัตถุดิบเป็นตัวนับไม่กินช่องกระเป๋า (`logic/inventory.gd`) · การ์ดผู้เล่นใหม่สุ่มแบบม่านตา/สีตา/ขอบตาไม่ซ้ำกัน (`CardDeck.vary_starter_looks`) · เทสต์ 2212/82

- 2026-11-13 | ui-programmer via PO | feature/class-weapons-card-screen | ฉากในการ์ด 3 ชั้น (far/mid/near + เงาใต้เท้า) `client/card_scene_layers.gd`, art `art/ui/class_cards/scene/` (VRAM compress, 768px) เลื่อนตามการเอียง; หน้าตัวละครใช้ฉากนิ่ง · เทสต์ 2197/82

- 2026-11-13 | ui-programmer via PO | feature/class-weapons-card-screen | การ์ดสลับท่า idle (`idle_variants` ใน data/classes, `play_idle_clip()` ในโมเดล, เฉพาะการ์ด/หน้าตัวละคร) · แถบทัพเป็นภาพครึ่งตัวพอดีช่อง · เทสต์ 2196/82

- 2026-11-13 | ui-programmer x2 via PO | feature/class-weapons-card-screen | การ์ดฮับเอียง 3D + ความลึก + แสงวาว (`client/card_tilt*.gdshader`), ชื่อการ์ดไม่ถูกตัด · HUD ฉากสู้เป็นแผ่นหนัง (squad_panel/hud แถบบอส/ขวาบน) · ป้าย Offline/Online อังกฤษบนฮับ · ชื่อยาวในร้าน/คลัง/Tailor ย่อพอดี · เทสต์ 2196/82

- 2026-11-12 | ui-programmer via PO | feature/class-weapons-card-screen | หน้าสรุปหลังสู้แบบหนัง/กระดาษ (VICTORY/DEFEAT, เวฟที่ผ่าน, ของที่ได้: `GameState.run_loot` เก็บจาก event loot ใน stage_view) · ไอคอนโล่เรนเดอร์จากโมเดล Studio (`tools/shots/shield_icon.gd`, catalog icon_path) · `client/hub_look.gd` helper · ยังไม่ได้: HUD ฉากสู้, ป้ายออนไลน์, ชื่อยาวถูกตัด · เทสต์ 2195/82

- 2026-11-12 | PO | feature/class-weapons-card-screen | ดาบโล่โชว์โล่จากชุดเกราะ Studio แทนโล่กลมวาดด้วยโค้ด (`shield_kind`: procedural ใช้เฉพาะเมื่อชุดไม่มีโล่) ค่าตีบวกโล่ยังมาจากช่อง offhand · เทสต์ 2194/82

- 2026-11-12 | gameplay-programmer via PO | feature/class-weapons-card-screen | ชื่ออังกฤษ: แฟชั่น/cosmetics (`tools/items/cosmetic_names.py`, ไทยเก็บใน name_th), สกิล (`display_name` + `display_name_th`) · สต็อกร้าน 11 ชิ้น (ดาบ 2, โล่, เกราะ 8) · กัน `_nose` Nil ใน fighter_view · เทสต์ 2194/82

- 2026-11-12 | gameplay-programmer via PO | feature/class-weapons-card-screen | การ์ดเริ่มต้นใส่ชุดเกราะคลาส · ตัวเลือกม่านตา 7 แบบ (`data/cosmetics/iris_styles.json`, part `iris_style`) ใน Tailor · makeup none = natural · ชื่อเกราะ/เซ็ตเป็นอังกฤษ (`tools/items/armor_names.py`, เก็บไทยใน name_th) · เทสต์ 2194/82

- 2026-11-12 | tech-artist via PO | feature/class-weapons-card-screen | เอฟเฟกต์สกิล: ทุกสกิลของ 4 คลาสมีภาพ (skill_cast/burst/trail/struck ใน vfx.json), ลูกไฟใหม่, เลิกก้อนดำ, frost_armor ชัดขึ้น, ชื่อสกิลขึ้นเหนือการ์ดทัพ, ตัวเลข/ของดรอปไม่บัง HUD, HP ไม่เกิน max · ยังไม่ได้วัดบนเว็บ/มือถือ

- 2026-11-12 | character-artist via PO | feature/class-weapons-card-screen | ไฟล์ตัวละคร Studio 2026-11-11: ชุดเกราะ+อาวุธของคลาส (`art/characters/studio05/v1111/`), ผม A-G ทุกคลาส, ตา 7 แบบ/เมคอัพ 3/กะพริบใหม่ ใน `studio05_toon.gdshader`, โล่ที่ใส่จริงโชว์บนตัว (`item_assets.looks()` offhand) · รายการ `docs/tech/studio_v20261111_inventory.md` · rig 102 เหมือนเดิม

- 2026-11-12 | ui-programmer via PO | feature/class-weapons-card-screen | เมนู Tailor (แต่งตัวต่อการ์ด card_look + แฟชั่นนับชิ้น mall_buy/card_fashion, แท็บ Outfit เปิดหน้านี้) และ Shop (ขาย/ขายหลายชิ้น/ขายวัตถุดิบ; หน้าซื้อว่างเพราะ shop.json มีแค่ bow_01 ที่ไม่อยู่ใน catalog) · `hub_tailor_panel.gd`, `hub_shop_panel.gd`

- 2026-11-12 | ui-programmer via PO | feature/class-weapons-card-screen | เมนู Blacksmith (ตีบวก/อัปเกรด/ซ่อม ของทุกการ์ดและคลัง) และ Storage (คลัง/ห้องนิรภัย/ใส่ให้การ์ด/ทิ้ง) ใช้ได้จริง · แยก `hub_item_cell.gd`/`hub_item_details.gd`/`hub_service_panel.gd` · Shop/Tailor ยังไม่ทำ · เทสต์ 2166/83 ชุดเดิม

- 2026-11-12 | ui-programmer via PO | feature/class-weapons-card-screen | หน้าตัวละครของการ์ด `client/card_character_screen.gd` (แท็บ Equipment: 15 ช่องรวม off-hand, ค่าสถานะ, รายละเอียด, คลังกลาง, ใส่/ถอด/ตีบวก/ซ่อม ผ่านคำสั่งที่มี card) · Outfit/Skills ยังเป็นตัวว่าง · เทสต์ 2156/83 ชุดเดิม

- 2026-11-12 | gameplay-programmer+PO | feature/class-weapons-card-screen | ของลดตามขนาดทัพ `loot_by_squad` [0.33,0.67,1.0] (drop/gold/material/relic/challenge/treasure) · loot.json ดรอป x1.5 · กระเป๋า 16 ช่อง · ทัพ 2 ตัว power 1.0 · เทสต์ 2154/83 ชุดเดิม

- 2026-11-12 | ui-programmer via PO | feature/class-weapons-card-screen | หน้าฮับใหม่ในเกม (ฉากซากปรักหักพัง, กรอบหนัง 4 คลาส, เมนูซ้าย 6 อัน, แถบทัพ, FIGHT, อังกฤษ, Taviraj/Sarabun, ปุ่ม >=96px บนมือถือ) `card_deck_screen.gd`/`card_tokens.gd`/`card_portrait.gd` + `art/ui/class_cards/` · เมนูอื่นยัง Coming soon · ระวัง: `godot --import` crash แล้วแก้ .import ราว 3,200 ไฟล์ในเครื่อง ไม่ได้ commit · เทสต์ 2134/83

- 2026-11-12 | gameplay-programmer via PO | feature/class-weapons-card-screen | ช่อง `offhand` (โล่) เฉพาะ sword_shield: `rules.json` slot classes, `ItemRules.slot_open_for`, equip คืน `slot_closed`, โล่เริ่มต้น `starter-offhand-v1-sword_shield` (+migration), refine ได้, catalog `round_shield` (procedural) ผ่าน `tools/items/publish_offhand_catalog.py` · ยังไม่มีโมเดล/ไอคอนโล่ และตัวละครยังโชว์โล่ของคลาส · เทสต์ 2134/83 ชุดเดิม

- 2026-11-11 | gameplay-programmer via PO | feature/class-weapons-card-screen | อุปกรณ์ต่อการ์ด ขั้น 4-5: ทัพสร้างจากการ์ด 3 ใบในทัพ (`logic/squad_member.gd`) ใช้ของ/สกิลของการ์ดเอง กระเป๋ากลาง ดรอป 1 ชิ้น/kill · checkpoint_v 2, party_v 2 (v1 ยังโหลดได้) · ตัด guest สุ่มใน `game_state.gd` · ห้องออนไลน์ยังไม่เปลี่ยน · เทสต์ 2116/83 ชุดเดิม

- 2026-11-11 | tech-artist via PO | feature/class-weapons-card-screen | บังคับแนวนอน: `project.godot` handheld orientation=4 (sensor landscape) · `tools/web/play_template.html` หน้า Rotate your device (CSS, จอสัมผัสแนวตั้ง) + lock landscape ตอนเต็มจอ · `ink_ui.gd` เลิกใช้ layout แนวตั้ง · ยังไม่ได้ build/deploy เว็บ · เทสต์ 2098/83 ชุดเดิม

- 2026-11-11 | gameplay-programmer via PO | feature/class-weapons-card-screen | อุปกรณ์ต่อการ์ด ขั้น 1-3 (`Profile.card_gear`, migration ไปดาบโล่, คำสั่ง equip/unequip/skill_build/repair_all รับ `card`, `weapon_families` ในคลาส, แฟชั่นนับชิ้น `card_fashion`) · `Profile.loadout` ยังเป็น stand-in ของการ์ดดาบโล่จนถึงขั้น 4 · เทสต์ 2098/83 ชุดเดิม

- 2026-11-11 | combat-designer via PO | feature/class-weapons-card-screen | จูนโหมดเวฟ: ทัพเริ่มต้นชนะ ~72% (40 seed) บอสยากสุด · แก้ HP มอนคูณ co-op ซ้ำ 2 รอบ · บอสได้ poise_mult · `wave_power_by_squad` · ดาบใหญ่ได้บัฟป้องกัน/ฟื้นเลือด · class_sim นับการล้ม · เทสต์ 2070/83

- 2026-11-11 | ux-ui-designer via PO | feature/class-weapons-card-screen | auto-battle ไม่สร้างป้ายชื่อ/HP บนหัวทัพเรา (`stage_view.gd` `party_status_shown`) · Boss ปฏิเสธหน้าการ์ดแนวท้องฟ้า/v8 เลือกแนวดาร์กแฟนตาซีวาดมือ (กำลังทำ v9) · เทสต์ 83 พังชุดเดิม

- 2026-11-11 | PO | feature/class-weapons-card-screen | Boss: ใช้สกิล ยังไม่ทำอัลติ → ซ่อนเกจอัลติ (`squad_panel.gd` SHOW_ULTIMATE) · สกิล 4 ช่องต่อคลาส (`integration.json` class_skills + weapon_starts greatsword/longbow/magic; `GameSim.set_class_style` แนบ build ของคลาส) · แก้ auto_pilot จองช่องสกิลทิ้ง · เทสต์ 2065/83 ชุดเดิม

- 2026-11-11 | PO | feature/class-weapons-card-screen | กล้องกระดานซูม/เลื่อนตามจุดที่สู้อัตโนมัติ (`camera_rig.gd` `_auto_frame`, `stage_view.gd` `_action_points`; หมุน/ซูมเองแล้วปิด) แตะ `stage_view.gd` · เทสต์ 2065/83 ชุดเดิม

- 2026-11-11 | PO | feature/class-weapons-card-screen | ซ่อนป้ายสถานะออนไลน์ในฉากสู้/หน้าสรุป (`online_account.gd`) · หน้าสรุปโหมดเวฟใช้สไตล์การ์ตูนของหน้าการ์ด (`journey_screen.gd` `_build_wave_summary`) · เทสต์ 2061/83 ชุดเดิม

- 2026-11-11 | PO | feature/class-weapons-card-screen | ลองเล่นเต็ม 12 เวฟในหน้าต่างจริง (`tools/shots/full_run_review.gd`) ชนะสบาย ทัพไม่ล้ม · อัปเดต PROGRESS

- 2026-11-11 | PO | feature/class-weapons-card-screen | เซฟ/โหลด sim เก็บ `wave_heal_fraction` และ `class_styles` แล้ว (+เทสต์ใน test_sim_restore) · ลองแก้ auto_pilot จองช่องสกิลทิ้งตอนคอมโบแล้วทัพ 2 ตัวแพ้บอส 3/6 seed จึงถอยคืน รอจูนพร้อมสกิลต่อคลาส · เทสต์ 2061 ผ่าน/83 พังชุดเดิม

- 2026-11-11 | lead-programmer | (ยังไม่ push) | Boss สั่งตัดระบบเก่า: ลบฮับ/แคมป์/ร้านค้า/ฟาร์ม/warp/NPC/หน้าสกิล/ศูนย์กล้องอัลติ/ปุ่มมือถือเก่า (client + scenes/hub, workshops + tests/tools ที่เกี่ยวข้อง); `go_hub` ถูกตัดแล้ว ทุกทางกลับไป `GameState.go_card_deck()`; `camp_screen.gd` เหลือแค่หน้าต่าง Backpack ของการ์ด (ใช้ gear_panel); stage_view ไม่มีจุดพัก/กองไฟแล้ว

- 2026-11-11 | PO | (ยังไม่ push) | การ์ดซิงก์กับบัญชีออนไลน์ (`card_deck` ใน `account_session.gd`, `card_look`/`card_squad` ใน `server/profile/runner.gd` ALLOWED) · แก้ error `material is null` (ต้นเหตุ: `material_override` ของลูกธนู goblin_archer ใน `client/projectile_view.gd`) · เทสต์ 2404 ผ่าน/162 พังชุดเดิม

- 2026-11-11 | PO | (ยังไม่ push) | เริ่ม AI_SYNC ใหม่ · คลาสมีผลต่อกติกา · กล้องตามการ์ด · ทัพเริ่มต้นเปลี่ยนเป็นดาบโล่/ดาบใหญ่/ธนู · ติดตั้งเฟรมเวิร์ก + Codex CLI · มอบงานหน้าการ์ดให้ agent ของเรา
