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

- 2026-11-11 | lead-programmer | (ยังไม่ push) | Boss สั่งตัดระบบเก่า: ลบฮับ/แคมป์/ร้านค้า/ฟาร์ม/warp/NPC/หน้าสกิล/ศูนย์กล้องอัลติ/ปุ่มมือถือเก่า (client + scenes/hub, workshops + tests/tools ที่เกี่ยวข้อง); `go_hub` ถูกตัดแล้ว ทุกทางกลับไป `GameState.go_card_deck()`; `camp_screen.gd` เหลือแค่หน้าต่าง Backpack ของการ์ด (ใช้ gear_panel); stage_view ไม่มีจุดพัก/กองไฟแล้ว

- 2026-11-11 | PO | (ยังไม่ push) | การ์ดซิงก์กับบัญชีออนไลน์ (`card_deck` ใน `account_session.gd`, `card_look`/`card_squad` ใน `server/profile/runner.gd` ALLOWED) · แก้ error `material is null` (ต้นเหตุ: `material_override` ของลูกธนู goblin_archer ใน `client/projectile_view.gd`) · เทสต์ 2404 ผ่าน/162 พังชุดเดิม

- 2026-11-11 | PO | (ยังไม่ push) | เริ่ม AI_SYNC ใหม่ · คลาสมีผลต่อกติกา · กล้องตามการ์ด · ทัพเริ่มต้นเปลี่ยนเป็นดาบโล่/ดาบใหญ่/ธนู · ติดตั้งเฟรมเวิร์ก + Codex CLI · มอบงานหน้าการ์ดให้ agent ของเรา
