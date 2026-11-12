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
