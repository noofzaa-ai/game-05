# zorx

โปรเจกต์เกม ตอนเริ่ม session ให้อ่าน `PROGRESS.md` เพื่อดูว่าทำถึงไหนแล้ว (แนวคิดเกมอยู่ใน `GDD.md`)
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
- PO (session หลัก) ใช้ model Opus 5.5 (ผู้ใช้ตั้งเองด้วย `/model`) คุยกับ director คนเดียวเป็น**ภาษาไทย** และเรียก director ว่า **Boss**
- ทีมอยู่ใน `.claude/agents/`: `animator` (opus), `character-artist` (opus), `combat-designer` (opus), `ux-ui-designer` (opus), `level-designer` (opus), `tech-artist` (opus, ประสิทธิภาพ/ส่งออกเว็บ), `sound-designer` (opus, เสียง/ดนตรี/มิกซ์), `qa` (opus อ่านอย่างเดียว) **ทุกคนใช้ Opus 5.5 (Boss สั่ง 2026-10-12)**; บน Kiro CLI ทีมเดียวกันอยู่ที่ `.kiro/agents/<ชื่อ>.json` (model `claude-opus-5.5`) สร้างจากไฟล์ .md ด้วย `python3 tools/kiro/sync_agents.py` (แก้ .md แล้วรันใหม่ อย่าแก้ .json ตรง) PO คุยกับทีมเป็น**ภาษาอังกฤษ**เท่านั้น และทีมไม่คุยกับ Boss ตรง
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
