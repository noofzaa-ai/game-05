# zorx

โปรเจกต์เกม ตอนเริ่ม session ให้อ่าน `PROGRESS.md` เพื่อดูว่าทำถึงไหนแล้ว (แนวคิดเกมอยู่ใน `GDD.md`)
**เกมเปลี่ยนเป็น Auto-battler แล้ว (Boss 2026-11-10/11):** อ่าน `docs/handoff/auto_battler_handoff.md` ก่อน (ทิศทาง, สถานะ, งานต่อไป, การย้ายเครื่อง) ซึ่งใหม่กว่า GDD.md
ถ้าเป็นเครื่องใหม่ (ความจำ Claude ยังว่าง) ให้อ่าน `docs/handoff/claude_memory/` แล้วคัดลอกเข้าความจำของเครื่องนั้น
ก่อนจบช่วงงานหรือเมื่อมีการตัดสินใจสำคัญ ให้อัปเดต `PROGRESS.md` (สั้นๆ เฉพาะสิ่งที่ดูจากโค้ดไม่ได้)
repo นี้มีหลายฝั่ง/หลาย AI ทำพร้อมกัน: อ่าน `AI_SYNC.md` ก่อนเริ่มงาน และ**อัปเดต `AI_SYNC.md` ทุกครั้งก่อน push** (งานที่จอง, ฟีเจอร์ที่เปลี่ยน, บันทึก sync 1 บรรทัด)

## กฎสถาปัตยกรรม (ดู docs/adr/0001-layered-architecture.md)
- `logic/` = กติกาเกมล้วนๆ **ห้าม** อ้างโหนด/ภาพ/ปุ่ม/`client/`/`GameState` (ตรวจอัตโนมัติ)
- `client/` = ภาพ ปุ่ม เมนู กล้อง ใช้ `logic/` ได้ ไม่ตัดสินกติกาเอง
- `data/` = เนื้อหาเป็นไฟล์ (แมพ ฯลฯ) เพิ่มเนื้อหาด้วยไฟล์ ไม่ใช่โค้ด
- ไคลเอนต์ห้ามคุยฐานข้อมูลตรง (เซิร์ฟเวอร์เท่านั้น)
- ของที่เปลี่ยนแล้วแพงทีหลัง (โครงกระดูกตัวละคร, ระบบ logic/client) ต้องถาม director ก่อน

## ทดสอบ (ต้องผ่านทั้งหมดก่อนบอกว่างานเสร็จ)
`godot --headless --path . --script res://tests/run_all.gd` (godot อยู่ใน WinGet packages ถ้า PATH ยังไม่รู้จัก ใช้ไฟล์ `Godot_v*_console.exe`; บน Mac ใช้ `/Applications/Godot.app/Contents/MacOS/Godot`)
- หลังเพิ่ม/เปลี่ยนไฟล์โมเดลหรือภาพ รัน `godot --headless --path . --import` ก่อนหนึ่งครั้ง
- รันด้วยตัวจับเวลา (ตัวรันทดสอบเคยค้างเมื่อไฟล์ทดสอบเสีย) และดู stderr ด้วย
- ตรวจภาพจริงได้โดยรัน Godot แบบมีหน้าต่าง (ไม่ใส่ --headless) ด้วยสคริปต์ที่บันทึก viewport เป็น PNG

## ทีมและการสื่อสาร (director สั่ง 2026-10-04)
- PO (session หลัก) คุยกับ director คนเดียวเป็น**ภาษาไทย** และเรียก director ว่า **Boss** PO คุยกับทีมเป็น**ภาษาอังกฤษ** ทีมทุกตัว (ทั้ง 8 ตัวของเราและตัวจากเฟรมเวิร์ก รวม creative-director/technical-director/producer) **รายงานผ่าน PO เท่านั้น ไม่คุยหรือถามผู้ใช้ตรง** เรื่องที่ต้องตัดสินให้ใส่ในรายงานเป็นคำถาม 2-4 ตัวเลือกพร้อมคำแนะนำ แล้ว PO ส่งต่อให้ Boss
- โมเดล (Boss สั่ง 2026-11-11): agent ของเรา 8 ตัวและ creative-director, technical-director, producer ใช้ Opus 5.5 effort medium (ปรับจาก Sonnet high เมื่อ Boss สั่งอีกครั้ง); agent ที่เหลือทั้งหมดใช้ตามโมเดลของ session ที่เรียก (`model: inherit`) ทีมอยู่ใน `.claude/agents/` (27 ตัว) สร้างด้วยมือ ไม่มี Kiro แล้ว
- **PO ตอบ Boss สั้น กระชับ ได้ใจความ (Boss สั่ง 2026-11-11):** ขึ้นด้วยผลลัพธ์ทันที ไม่เขียนยาว ไม่ทวนสิ่งที่ถามหรือที่ทำไปแล้ว ใส่เฉพาะที่ต้องรู้/ต้องตัดสินใจ (รวมสิ่งที่ล้มเหลวหรือยังไม่ได้ตรวจ) รายละเอียดยาวเก็บในไฟล์แล้วชี้ลิงก์
- **งานสร้างรูปภาพ 2D ทุกชนิด (Boss สั่ง 2026-11-11):** PO มอบให้ agent สายภาพ (`art-director`, `character-artist`, `ux-ui-designer`, `ui-programmer`, `technical-artist`, `tech-artist`) และ agent ต้องสร้างผ่าน Codex CLI (gpt-6.1-sol, effort high) เสมอ ตามขั้นตอนใน `docs/tech/codex_image_workflow.md` รูปรอ Boss ตรวจก่อนนำเข้าเกม (โมเดล 3D ยังใช้ Blender)
- PO เป็นคนมอบงาน/ประสานงาน/สรุปให้ Boss; เรื่องที่ต้องให้ Boss ตัดสิน (โครงกระดูก, ระบบ logic/client ฯลฯ) ทีมต้องหยุดและรายงานผ่าน PO
- งานที่แตะไฟล์เดียวกัน (เช่น `character_model.gd`) อย่าให้สองคนทำพร้อมกัน

## Character Studio parity — Boss directive 2026-10-23 (authoritative)

- The source of truth for the new player is `art/characters/mmorpg-reference-base/red_jacket/index.html` (http://127.0.0.1:8872/art/characters/mmorpg-reference-base/red_jacket/index.html), its imported modules, config files and referenced original assets. Another team has reviewed this Studio. Preserve its options AND visible behaviour, not merely the model's outline or a successful import.
- Preserve the original rig, bone hierarchy, bind transforms, skin weights, morph targets, materials/textures, hair/cloth/wing motion, eye shapes/colours/blink, skin controls, head ornaments/masks, per-piece visibility, hat/hair fitting, backpack/cape fitting, budgets and render settings. Inventory the source options directly; never invent substitute lists, colours, default rules or animations.
- Adapt our game's weapon sockets, grip/finger contact and game animations TO the original rig. Never put our 57-point rig on the donor mesh. Additional attachment nodes must not remove or merge donor joints/weights.
- Port browser-side runtime behaviour as well as GLB content. A feature that lives in JS (blinking, fitting, secondary animation, toon/outline, visibility) is part of the required result. Bone names or weights existing in a file do NOT establish equivalent motion.
- An engine-specific implementation is allowed only when output/behaviour matches the source and has comparison evidence. Record differences as OPEN until visually accepted. Do not describe approximations or static shots as full parity.
- Boss's explicit game exceptions remain: max 135cm character scale; migrate game weapons/4 ultimates; fashion overlays actual equipment while stats and per-slot refine aura come from real equipment; approved starter set/floating show-hair hat. Apply exceptions narrowly, not to all source options. Ask before other intentional deviations.
- Before claiming the migration complete, compare every source option and each runtime subsystem, including front/side/back/low/high views, standing/running/transitions, clothing+hair+hat/back combinations, four weapon grips/ultimates and remote player display. Maintain `docs/tech/reference_studio_parity.md` and evidence. Do not deploy as parity-complete while OPEN issues remain.


### 2026-10-23 — Boss deferred hats
Cosmetic hats are out of the current migration scope. Game and generated Game Studio force no cosmetic hat, hide hat choices, and do not auto-equip Halloween hats. Original source Studio/assets remain intact. Real equipment ownership/stats/refine levels are preserved. Hat fitting/visual acceptance is deferred; remaining parity work covers character, hair, eyes, outfits, back accessories and weapon motions.

- Boss correction 2026-10-23: Studio fashion art belongs to Tailor/Customize. Combat item icons in Inventory/Bag/Player Info must use the actual original combat item art, never mapped to fashion pieces. Fashion overlays do not change equipment identity or thumbnails.

## Deploy preference (Boss, 2026-10-27)

Boss อนุญาตว่า “ต่อไป deploy และเทสได้เลยนะไม่ต้องถาม” สำหรับงานเกมนี้ ให้ดำเนินการ build, deploy และทดสอบตามงานที่สั่งได้โดยไม่ขอยืนยันซ้ำ และตรวจ rollout/เว็บจริงพร้อมเก็บ rollback ตามเดิม.


## Studio framework (Claude Code Game Studios v1.3.0, MIT — เพิ่ม 2026-11-11, flow แบบ standard)
นำเฟรมเวิร์ก https://github.com/Donchitos/Claude-Code-Game-Studios มาใช้ครบชุด: agent 27 ตัว (`.claude/agents/`, ตัดและรวมจาก 55 เมื่อ 2026-11-11), skill 77 ตัว (`.claude/skills/`), hook (`.claude/hooks/`), กฎตามโฟลเดอร์ (`.claude/rules/`), เอกสารอ้างอิง (`.claude/docs/`), `project.yaml` (ค่า rigor/engine/commands ของเรา), `design/` `production/` `docs/architecture/`
- **ลำดับทำงาน:** `/next-step` บอกขั้นถัดไป · `/project-stage-detect` / `/adopt` ดูสถานะโปรเจกต์ที่มีโค้ดอยู่แล้ว · `/design-system` (GDD ทีละระบบ) → `/architecture-decision` → `/create-epics` → `/create-stories` → `/sprint-plan` → `/dev-story` → `/story-done` · `/gate-check` ก่อนข้ามช่วง · `/balance-check` `/playtest-report` `/bug-report` ตามต้องการ · ตั้งค่า `/project-settings`
- **เมื่อกฎซ้อนกัน ยึดของ zorx เหนือเฟรมเวิร์ก:** PO คุยกับ Boss เป็นภาษาไทย / ทีมคุยกับ PO เป็นอังกฤษ ทีมไม่คุย Boss ตรง (ข้อ "ทีมและการสื่อสาร" ด้านบน) · ต้องอ่าน/อัปเดต `AI_SYNC.md` และ `PROGRESS.md` · ต้องรันชุดเทสต์ของเรา (`commands.test` ใน `project.yaml`) · กฎสถาปัตยกรรม `logic/` กับ `client/` · ห้าม commit/push เองโดยไม่ได้รับคำสั่ง
- **agent ของเรา 8 ตัวเดิมยังอยู่และชนะชื่อซ้ำ** (`level-designer`, `sound-designer` ใช้ของเรา ไม่ใช้ของเฟรมเวิร์ก) ตัวอื่นของเฟรมเวิร์กใช้เสริมได้ (เช่น `producer`, `systems-designer`, `economy-designer`, `ai-programmer`, `godot-*-specialist`)
- **โหมด:** `modes.rigor: standard`, `modes.automation: guided` (ตัดสินเรื่องเล็กเอง ถามเรื่องใหญ่/ย้อนกลับไม่ได้) ปิดการเช็กอัปเดตผ่านเน็ต (`updates.check: false`)
- **ข้อจำกัดที่รู้:** เฟรมเวิร์กรับ `engine.code_root` ได้โฟลเดอร์เดียว เราตั้งเป็น `logic/` ดังนั้นการสแกน TODO/หนี้เทคนิคไม่ครอบคลุม `client/` · `commands.test` ใช้ตัวรันของเรา (`tests/run_all.gd`) ไม่ใช่ gdUnit4 · สกิลสาย web prototype (`/prototype` ฯลฯ) ไม่เกี่ยวกับเกมนี้ · hook ต้องมี Git Bash + Python (เครื่องนี้มีแล้ว)
- hook: สแกนหาคำสั่งเครือข่าย/ลบ/eval แล้ว และทดสอบรัน 4 ตัว (session-start, detect-gaps, validate-commit, validate-push) ยังไม่ได้อ่านครบทุกบรรทัด; ตัวเช็กอัปเดตผ่านเน็ตปิดไว้ ตั้งค่าหลักอยู่ที่ `.claude/settings.json` (deny: `git push --force`, `git reset --hard`, `rm -rf` ฯลฯ)
