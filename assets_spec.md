# ZORX — มาตรฐาน Assets สำหรับเกมเว็บ

อนุมัติโดย Boss: **2026-10-20** เพื่อรักษาคุณภาพและเหลือพื้นที่สำหรับเพิ่ม assets
ใช้กับ **ไฟล์อนุพันธ์ที่ส่งเข้าเกม** ทั้ง PC และมือถือแนวนอน เก็บต้นฉบับ FBX/Blend/ภาพความละเอียดสูงแยกจากไฟล์ export เกม

## 1. Texture budget

### มูท สี และวัสดุของเกม (Boss 2026-10-29)

- Asset ใหม่ทุกประเภท ทั้งฉาก พร็อพ อุปกรณ์ และ UI icon ต้องอยู่ในทิศทางภาพเดียวกับเกม ตรวจเทียบ asset เดิมและภาพในเกมจริงก่อนใช้งาน ไม่พิจารณาเพียงความสวยของภาพเดี่ยว
- ใช้โทนแฟนตาซี low-poly แบบหม่น: น้ำเงินอมเทา หนังน้ำตาล ไม้ธรรมชาติ ทองเหลืองเก่า และสีดิน/ป่า ตาม reference ของตำแหน่งนั้น หลีกเลี่ยงสีสดจัด ทองเหลืองเรืองแสง ความเงาจัด หรือแสงฟุ้งที่โดดจากของเดิม เว้นแต่เป็น VFX/จุดเน้นที่อนุมัติเฉพาะ
- รักษาลาย UV และรายละเอียดต้นฉบับ แต่ปรับสี material/texture และความเงาให้สอดคล้องกัน โดยทำใน derivative และบันทึกขั้นตอนให้ rebuild ได้ ไม่แก้ต้นฉบับผู้ใช้ทับ
- ตรวจภายใต้กล้องและแสงจริงของเกม ทั้ง PC และมือถือแนวนอน สำหรับไอคอนต้องเทียบกับปุ่มข้างเคียงที่ขนาดใช้งานจริง; ฉากต้องเทียบพื้น ต้นไม้ อาคาร และตัวละครรอบข้าง ไม่ให้โทนสีหลุดจากกลุ่ม
- ตรวจรอยต่อ พื้น และ collision ของ asset ที่เดินหรือกระโดดผ่านได้ด้วย ขนาดไฟล์ผ่าน spec ไม่ได้แปลว่าวางใช้งานแล้วถูกต้อง

ขนาดด้านที่ยาวที่สุด เป็น **เพดาน ไม่ใช่ขนาดที่ต้องขยายให้ถึง** รักษาอัตราส่วนภาพ ไม่ upscale ของเล็ก

| แผนที่ | ขนาดสูงสุด | การอ่านสี / ข้อกำหนด |
| --- | ---: | --- |
| Base Color / Albedo (สีหลัก) | **1024 px** | sRGB; รักษาสี ลาย และ alpha เดิม |
| Normal | **512 px** | Linear/data, tangent-space ตาม glTF; ตั้ง Godot เป็น Normal Map |
| Metallic / Roughness | **512 px** | Linear/data; รวมเป็นแผนที่เดียวตาม glTF: Roughness ช่อง G, Metallic ช่อง B |
| Ambient Occlusion หากมี | **512 px** | Linear/data; ORM ใช้ AO ช่อง R ได้เมื่อ UV/texture transform ตรงกัน |
| Emissive หากมี | **1024 px** | เพดานเดียวกับสีหลัก ใช้เล็กกว่านี้ถ้ารายละเอียดไม่จำเป็น |

- โมเดลที่ใช้สีพื้น/vertex color อยู่แล้ว ไม่ต้องเพิ่ม texture หรือ Normal Map ให้ครบชุด
- ไม่สร้าง normal/metallic/roughness ที่ไม่ได้ใช้งานจริงใน material
- รักษา UV, material factors, opacity, skin weights, bones, sockets, animation, ขนาด และตำแหน่งเดิมเมื่อปรับ texture
- แผนที่ข้อมูลต้องไม่ถูกแปลงแบบ sRGB; อย่ารวม color และ data map ไว้ในภาพเดียวกัน
- Normal ลดรายละเอียดเฉพาะพื้นผิว ไม่ใช้แทน geometry ที่กำหนด silhouette
- **UI / icons / fonts / loading artwork เป็นงานคนละประเภท** ไม่ใช้เพดานโมเดล 3D นี้ไปย่อรวมโดยอัตโนมัติ

## 2. Godot import และ web packs

- Texture 3D ใช้ **VRAM Compressed** (`compress/mode=2`), mipmaps เปิด
- `process/size_limit`: Color 1024, Normal/Metallic/Roughness/AO 512
- `compress/normal_map=1` เฉพาะ Normal; แผนที่อื่นใช้ 0
- เก็บ S3TC สำหรับ PC และ ETC2 สำหรับมือถือใน format-specific packs ตามระบบปัจจุบัน โหลดเฉพาะ format ที่เครื่องใช้
- ลดภาพจริงใน derivative GLB ด้วย ไม่ใช้ import limit อย่างเดียว: เครื่องมืออื่นที่เปิด GLB ต้องได้ขนาดตรงกัน
- Godot อาจแตก PNG ออกข้าง GLB ต้อง import ใหม่และใช้ค่าที่ตรงกัน ห้ามย่อเฉพาะ PNG แล้วปล่อยภาพที่ฝังใน GLB เป็นขนาดเก่า
- Orc camp derivative PNG และ runtime import ใช้สี 1024 / normal 512 ตรงกัน; ภาพต้นฉบับ 4096 อยู่ใน `art_source/props/orc_camp/orc_source.glb` แยกจาก export เกม
- ไม่ใส่ FBX, Blend, backup หรือภาพต้นฉบับที่ไม่ใช้ลงใน web export

## 3. Geometry / Rig

- ชุดเกราะรวม 5 ช่อง (`head/shirt/arms/pants/shoes`) **ไม่เกิน 1,500 triangles ต่อชุด** ไม่รวมตัวฐาน ผม หน้า อาวุธ
- อาวุธและ VFX ใช้งบของ asset/skill นั้นตาม metadata/คู่มือเดิม ไม่เพิ่มเพียงเพื่อให้ครบเพดาน
- NPC และ prop: บันทึก tri จริงใน README/metadata; ลดเฉพาะ geometry ที่ไม่ทำให้รูปทรงเสียเมื่อมองจากกล้องเกม
- ไม่เปลี่ยน stable ID, rig, socket, จุดจับอาวุธ หรือสัดส่วนเพื่อแก้ขนาดไฟล์
- อาวุธอ่าน marker จากไฟล์ ตาม `weapon_glb.md`; สกิลใช้ `skill.md` / `tf_skill_docs.md`

## 4. ขั้นตอนนำ asset ใหม่เข้าเกม

1. เก็บต้นฉบับไว้นอกชุดส่งเกม ทำ derivative GLB พร้อมขนาด/พื้น/ทิศ/rig ที่ถูกต้อง
2. Export texture ตามตาราง; ถ้าใช้ตัวสร้าง ให้แก้ตัวสร้างด้วยเพื่อไม่ให้ regenerate กลับไปขนาดเก่า
3. รันเครื่องมือจากราก repo เกม (Python 3.9+ และ Pillow):

   ```sh
   python3 tools/art/apply_texture_budget.py path/to/asset.glb
   ```

   เครื่องมืออ่าน **material slots จริง** เพื่อจำแนกสี/normal/metallic-roughness/AO และย่อ embedded PNG โดยคงข้อมูล mesh/rig/animation เดิม รองรับ GLB 2.0 แบบหนึ่ง embedded BIN และ local external PNG ใต้ `art/`; compressed extension ต้องเตรียมผ่าน pipeline ที่ตรงชนิดก่อน

4. Import Godot เพื่อให้ได้ PNG และ resource ใหม่ จากนั้นตั้งค่า import ตามข้อ 2 และ import อีกครั้ง

   สำหรับชุด hub ที่มีอยู่:

   ```sh
   python3 tools/art/apply_texture_budget.py --report build/texture-budget/asset-sizes.json
   # Godot --headless --path . --import
   python3 tools/art/optimize_npc_textures.py
   # Godot --headless --path . --import
   ```

   คำสั่งแรกเมื่อไม่ระบุ path ครอบคลุม NPC 5 ตัวและเตา; เพิ่ม `--scenes` เพื่อครอบคลุมทุก GLB ใต้ `art/maps/` และ `art/props/` รวม PNG ที่อ้างร่วมกัน; คำสั่ง import settings ครอบคลุม NPC/props/maps ทั้งหมด

5. ดูภาพจากกล้องและแสงเดียวกัน ทั้งภาพรวมและระยะใกล้ ถ้ามี rig ให้ดูขณะขยับด้วย; UI มือถือดูเฉพาะแนวนอน ปุ่มต้องอยู่ในจอ
6. บันทึกขนาดก่อน/หลัง **แยกกัน**: GLB, GPU textures และดาวน์โหลดเกมจริง (engine + core + packs ของ format เดียว)
7. Build web แล้ววัด `packs.json` อย่าสรุปว่า GLB ลดเท่าไรแล้วดาวน์โหลดเกมต้องลดเท่ากัน รวมทั้งไม่บวก S3TC และ ETC2 เข้าด้วยกัน
8. อัปเดต README/metadata, `AI_SYNC.md`, `PROGRESS.md` และ deploy ตามคำสั่ง Boss

## 5. ตัวสร้างปัจจุบัน

- เตา: `tools/blender/prepare_blacksmith_forge.py` — color 1024 / data maps 512
- บ้าน Tailor: `python3 tools/art/prepare_tailor_house.py` — source `../assets/tailor.glb`, color1024/data512, ขนาดกว้าง4.8m และวางพื้นY=0; จากนั้น rebuild `build_camp_hub.py` เมื่อต้องปรับ footprint
- NPC ทั้ง 5: **`tools/blender/prepare_hub_npcs.py` ใน repo เกมนี้** — color 1024 / data maps 512; source FBX อยู่ `../assets/`
- ลด GLB ที่มีอยู่โดยไม่ export rig ใหม่: `tools/art/apply_texture_budget.py`
- ค่า import ของ hub: `tools/art/optimize_npc_textures.py` (ล้างเฉพาะ hash cache ที่สร้างใหม่ได้ เมื่อค่าหรือ format ยังไม่ตรง แล้ว import ใหม่)

## 6. การปรับใช้ 2026-10-20

- NPC ครบ 5 ตัว: Blacksmith, Merchant, Quest board, Storage, Tailor
- เตา Blacksmith: geometry 6,035 tri, สีหลักเดิม 1024; Normal และ Metallic/Roughness 512
- Orc camp: runtime normal 512, สีหลัก 1024
- ไม่ลดหรือเปลี่ยน geometry/rig/animation/ขนาดตัวละครในงานนี้
- ผลขนาดดาวน์โหลดจริงบันทึกใน `PROGRESS.md` หลัง build/deploy

### ผลส่งขึ้น staging

Web build `815bad07882c` / source `302d96a` เทียบกับรุ่นก่อน `c944db9eb355`:

| รายการ | ก่อน | หลัง | ลดลง |
| --- | ---: | ---: | ---: |
| GLB รวม NPC 5 ตัว + เตา | 19.20 MB | 11.82 MB | 7.38 MB / 38.45% |
| ดาวน์โหลด PC (S3TC) | 73.40 MB | 66.93 MB | 6.47 MB / 8.82% |
| ดาวน์โหลดมือถือ (ETC2) | 73.19 MB | 66.92 MB | 6.27 MB / 8.57% |

MB ฐาน 1,000,000 bytes; ดาวน์โหลดรวม engine + core + plain packs + GPU format เดียว ไม่รวม HTML/JS/ภาพหน้าโหลดและผลจาก cache ตรวจภาพ NPC/เตาใน Godot แนวนอนแล้ว ไม่ได้รันชุด automated tests ในงานนี้

## 7. มาตรฐานฉากและ Orc — 2026-10-20

- ทุก GLB ใต้ `art/maps/` และ `art/props/` ตรวจ texture ตาม material slots; คงภาพที่เล็กกว่าเพดานไว้ ไม่ขยายให้ใหญ่ขึ้น
- Color1024 / Normal+Metallic-Roughness+AO512 ใช้กับทั้ง embedded และ external PNG; texture 3D ทุกฉากใช้ GPU compression/mipmaps และอยู่ใน stages format packs รวม `art/maps/`
- Camp หลัก, Verdant terrain/props และหีบที่ geometry เบาอยู่แล้วคงรูปทรงเดิม
- ชุด Orc: กำแพง รั้ว กระท่อม กรง โทเทม ธง บัลลังก์ เก็บประมาณ85% ของ source triangles; ประตู หอคอย เตา และกองไฟเก็บเต็มเพื่อรักษาพื้นผิวเปลวไฟและ light anchors
- เปอร์เซ็นต์เป็นจุดเริ่มต้นแบบอ่อนสำหรับ **ชุด Orc นี้** ไม่ใช่เพดาน tri เดียวที่บังคับทุก asset; ต้องดูภาพจากกล้องเดิมก่อน publish และห้ามลดต่ำกว่า85% ในตัวสร้างนี้
- ชื่อเดิม `_lo` เป็น alias ของ mesh ตาม spec ปัจจุบัน ยังไม่มีระบบสลับ LOD runtime แยก; ไม่เพิ่ม mesh ซ้ำเพื่อให้ตรงชื่อ
- ตำแหน่งพร็อพ, collision, spawn, portal และกติกาแมพต้องคงเดิมเมื่อทำ art optimization
- สร้างฉากใหม่เฉพาะภาพ: Blender `--python tools/blender/build_goblin_stages.py -- --art-only` เพื่อไม่เขียน gameplay JSON
- ตัวสร้าง Orc `tools/blender/build_orc_kit.py -- --no-render` ใช้ source4096 เดิม, ส่งออก color1024/normal512 และ ratios ต่อชิ้นใน `PROPS`

| ฉาก | Tri ก่อน | Tri หลัง |
| --- | ---: | ---: |
| Arena A | 100,321 | 89,435 |
| Arena B | 47,551 | 43,351 |
| Arena C | 52,065 | 48,646 |
| Rest camp | 56,234 | 52,217 |
| Brush Ring | 92,500 | 84,987 |
| ชุด Orc อย่างละชิ้น | 49,495 | 44,861 |

### ผลฉากรุ่นล่าสุด

Deploy staging `scene-spec-20261020-1`, source `d521af5`, web build `5c4b63db8784`.

- ตรวจ19 GLB ของ map/prop; ทุกภาพที่ใช้จริงตรงเพดานตามชนิด ไม่ขยาย texture เดิมที่เล็กกว่า
- 5 ฉาก Orc รวม **348,671 ->318,636tri** ลด **30,035tri /8.61%**; material groups4ต่อฉากเหมือนเดิม
- GLB รวม5ฉาก **23.04 ->21.27MB**; เป็นขนาดไฟล์ต้นทาง ไม่ใช่ขนาดดาวน์โหลด
- ดาวน์โหลด PC **66.93 ->65.97MB** / มือถือ **66.92 ->65.94MB** เทียบ build815bad07882c; ลดอีกประมาณ0.96–0.98MB
- เทียบภาพ native ก่อน/หลังด้วยกล้องและแสงเดียวกันครบ5ฉาก และดู Verdant terrain/props หลังตั้งค่า GPU แล้ว ไม่มี script errors; ไม่ได้รัน automated tests หรือวัด FPS มือถือจริง

- Merchant shop: `tools/art/prepare_merchant_shop.py`, unchanged source `../assets/merchance_shop.glb`;3975tri,color1024/normal512/MR512,grounded4.8m width. Metadata in `art/props/merchant_shop/asset.json`.

- Storage station: `tools/blender/prepare_storage_station.py`, source `../assets/storage_item.fbx` unchanged;3607tri,width4.8m,color1024/normal512/MR512. Metadata in `art/props/storage_station/asset.json`.

- Gathering plaza extension (2026-10-20): camp base23020tri,vertex-painted ground/benches/lanterns; no new textures or prop duplication. Shared avatars capped24/channel,created at most2 per movement snapshot; real-device capacity still needs acceptance.

- Crystal warp: `tools/blender/prepare_warp_crystal.py`; source `../assets/crystal.fbx` unchanged,1706tri,color1024/normal512/MR512,width4.8m. Split only disconnected central crystal for world-up rotation; procedural VFX24sparkles+20mist,no external VFX texture downloads.

## Mummy scene2 preparation (2026-10-21)

- `tools/blender/prepare_mummy_kit.py`:11 reusable props from supplied single-mesh kit,5283tri preserved,shared albedo1024/normal512/MR512; external PNGs shared across scenes.
- `tools/blender/build_mummy_stage.py`:three separate pyramid drafts (exterior27142tri/interior26296tri/apex22356tri),generated art+map collision/spawn data;shared one texture set,not connected to existing Journey.
- Texture helper accepts explicit directories: `python3 tools/art/optimize_npc_textures.py art/props/mummy_tomb art/maps/mummy_tomb`; `_mr`/`_orm` suffixes are data maps512.
- Native full-resolution overview/game-camera captures in `art_source/preview/mummy_tomb/`;editable blends/source outside game export. No draft deployment.

## UI/Skill download budget follow-up (2026-10-26)

- Current skill/Gem icons128px; current animated VFX texture frames128px. Preserve alpha. Do not upscale these assets to the1024px3Dcolor ceiling.
- Runtime UIatlas and hubshortcut sheet import limit1024; keyboard shortcut512. LossyWebP0.85 retains alpha. SourcePNG files stay at authoring resolution. Atlas regions/nine-slice caps must scale from authored coordinates to imported texture dimensions; see client/mobile_ui_art.gd.
- Retired art/skills visual assets and sixold single-button PNGs are excluded from Web export. Keep active Skill Lab visual assets under art/skill_system. Do not re-enable retired packs through broad export changes.
- Measure selected-device download as engine + core + common content + ONE GPUformat, never bothS3TC/ETC2. Record actual postgzip numbers; see docs/tech/skill_download_audit.md.

- Goblin Base (2026-10-30): tools/art/prepare_goblin_kit.py + native tools/maps/build_goblin_base.gd; ten full-detail kit pieces, shared colour1024/normal512/MR512, VRAM+mips. Map .tscn references shared mesh .res resources; no repeated embedded kit textures per scene. Native renderer required when serializing MultiMesh buffers; inspect actual rendered persisted scene. Original FBXs/intermediates outside runtime export. Metadata art/props/goblin_base/manifest.json.
