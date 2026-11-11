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
| ui-programmer | หน้า Class Card แทนฮับ + `card_portrait` ตาม `docs/ui/class_card_ui_handoff.md` | `client/card_deck_screen.gd`, `client/card_portrait.gd`, `client/card_tokens.gd`, `scenes/card_deck_screen.tscn`, `client/game_state.gd` (ทางเข้าหน้าใหม่), `tests/test_ui_tokens.gd` | กำลังทำ (ยังไม่ commit) |
| ux-ui-designer (แทน art-director ที่ไม่มี Bash) | อาร์ตการ์ดรอบ 1 ผ่าน Codex | `art_source/codex_review/`, `art_source/ui/class_cards/` (ยังไม่เข้า `art/`) | กำลังทำ |
| PO | คลาสมีผลต่อกติกา, กล้องตามการ์ดที่เลือก, ทัพเริ่มต้นดาบโล่/ดาบใหญ่/ธนู, ติดตั้งเฟรมเวิร์ก | `logic/game_sim.gd`, `logic/auto_pilot.gd`, `logic/combat_data_loader.gd`, `logic/card_deck.gd`, `data/combat/weapons.json`, `data/classes/*.json`, `data/audio/audio.json`, `client/squad_panel.gd`, `client/stage_view.gd`, `client/session/local_session.gd`, `.claude/`, `project.yaml`, `design/`, `production/` | เสร็จ ยังไม่ commit |

## 5. สถานะปัจจุบัน (สรุปสั้น)

- เกมเป็น auto-battler: จัดทัพ 3 การ์ด แล้วสู้เอง 12 เวฟ (บอสท้าย) บนเกาะลอยฟ้า 16×9 ม.
- 4 คลาส: ดาบโล่ ดาบใหญ่ ธนู เวท (เวทปลดล็อกหลังเควส ยังไม่สร้างระบบเควส) แต่ละคลาสมีสไตล์การสู้ของตัวเอง
- เทสต์: **2397 ผ่าน / 162 พัง** (162 เป็น baseline เดิม เทียบรายชื่อ ไม่ใช่จำนวน) รันด้วย `godot --headless --path . --script res://tests/run_all.gd`
- ตัดสินใจแล้ว (Boss 2026-11-11): ตัดฟาร์ม/แคมป์/ร้านค้า/ฮับ NPC ทั้งหมด (ยังไม่ได้ลบ ซ่อนไว้จนกว่าหน้าการ์ดมาแทน) · co-op ยังไม่ทำ แต่ซิมต้องรันบน Godot headless · เป้าหมาย: hobby/portfolio · ได้ของแบบ RPG (ไอเท็ม อุปกรณ์ แฟชั่น ของบอส)
- เฟรมเวิร์ก Claude Code Game Studios (flow standard) ติดตั้งแล้ว: เอกสารแนวคิดอยู่ `design/concepts/auto-battler-concept.md` รายงานสถานะ `production/project-stage-report.md`

## 6. บันทึก sync (ใหม่สุดอยู่บน, บรรทัดละครั้งที่ push)

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
