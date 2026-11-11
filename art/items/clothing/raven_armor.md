# Obsidian Raven — ชุดเกราะอีกาดำ

ชุดจากภาพอ้างอิงผู้ใช้: ปีกขนนกประดับขมับขวาพร้อมพลอยสีอำพัน เกราะอกสั้นสีดำพลอยม่วง ไหล่ขนนกซ้อน ปลอกแขนหนาม ชายเกราะแยกแผ่น และรองเท้าเกราะสูง ขอบเกราะใช้สีเทาโลหะเพื่ออ่านรูปทรงได้

## ไฟล์แยก

โฟลเดอร์: `art/items/clothing/` ทุก ID มี GLB, JSON และ PNG ชื่อเดียวกัน สำหรับการ์ดใน Studio และ mapping ใน Godot

| Asset ID | Slot | Tri |
| --- | --- | ---: |
| `clothing_raven_temple_01` | head | 62 |
| `clothing_raven_cuirass_01` | shirt | 360 |
| `clothing_raven_bracers_01` | arms | 162 |
| `clothing_raven_tassets_01` | pants | 142 |
| `clothing_raven_greaves_01` | shoes | 292 |
| **รวมครบชุด** | | **1,018** |

นับจาก GLB จริง ไม่รวมตัวฐาน ผม ใบหน้า และอาวุธ อยู่ในงบ 1,500 tri Set ID: `armor_obsidian_raven_01`; asset_version 1

## Rig และการประกอบ

- ใช้ skeleton/bind pose เดียวกับตัวฐาน Chibi GameRig 57 จุด ไม่เพิ่มกระดูกหรือแก้คลิป
- เกราะอกตาม Chest และคอตาม UpperChest ขนนกไหล่ตาม UpperArm ปลอกแขนตาม LowerArm แผ่นหลังมือตาม Hand นิ้วของตัวฐานยังเปิดไว้ ไม่ใช่ถุงมือหุ้มนิ้ว
- ปลอกแขนคู่แยกเป็นช่อง arms ไม่รวมในเสื้อ
- เข็มขัดตาม Hips; ชายเกราะหน้า/หลังแยกซ้ายขวาตาม UpperLeg ของตัวเอง ไม่มีแผ่นเดียวผูกข้ามสองขา
- เกราะเข่า/หน้าแข้งตาม LowerLeg รองเท้าตาม Foot
- ปีกขมับตาม Head ใช้ `hide_hair: false`, `hide_head: false` ไม่รวมผมหรือใบหน้าตามภาพไว้ในชุด ทรงผมต่างจากฐานอาจต้องปรับ fit เครื่องประดับ
- เกราะแข็งและขนนกเป็น mesh วัสดุสี ไม่มี cloth simulation หรือ collision อัตโนมัติ ท่ากว้างมากอาจมีแผ่นเกราะชนกัน ต้องตรวจรายคลิปต่อไป

## Source และภาพ

- Builder: `tools/blender/build_studio_raven_armor.py`
- Assembly: `art/source/characters/chibi_raven_armor_preview.blend`
- Render: `art/characters/chibi-studio/armor_obsidian_raven_preview.png`
- Studio screenshot: `tools/image_to_3d/studio-raven-armor.png`

ใส่ครบใน Studio และดูท่ายืนกับ Run แล้ว ยังไม่ได้ตรวจครบทุกเฟรม/ทุกคลิป หรือการใช้งานใน Godot

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/blender/build_studio_raven_armor.py
python3 tools/register_studio_items.py
```

Builder เขียนเฉพาะชุดนี้และ preview ไม่สร้างรายการที่อยู่ใน Archive กลับมาเอง
