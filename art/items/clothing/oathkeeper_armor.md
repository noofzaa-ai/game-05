# Azure Oathkeeper — เกราะพิทักษ์น้ำเงินทอง

ชุดจากภาพอ้างอิงผู้ใช้: เกราะอกน้ำเงินลายเส้นทอง เกราะไหล่ดำมีขอบโค้งทอง ปลอกแขนหนังน้ำตาล กางเกงดำ เกราะหน้าแข้งน้ำเงินทอง รองเท้าหนัง และวงแหวนดำประดับพลอยม่วงเหนือหัว

## ไฟล์แยก

โฟลเดอร์: `art/items/clothing/` ทุก ID มี GLB, JSON และ PNG ชื่อเดียวกัน ใช้รหัสคงที่สำหรับ mapping ใน Godot

| Asset ID | Slot | Tri |
| --- | --- | ---: |
| `clothing_oathkeeper_halo_01` | head | 104 |
| `clothing_oathkeeper_cuirass_01` | shirt | 431 |
| `clothing_oathkeeper_bracers_01` | arms | 140 |
| `clothing_oathkeeper_breeches_01` | pants | 158 |
| `clothing_oathkeeper_boots_01` | shoes | 244 |
| **รวมครบชุด** | | **1,077** |

นับจาก GLB จริง ไม่รวมตัวฐาน ผม ใบหน้า และอาวุธ อยู่ในงบ 1,500 tri Set ID: `armor_azure_oathkeeper_01`; asset_version 1

## Rig และการประกอบ

- ใช้ GameRig 57 จุดและ bind pose ของตัวฐาน Chibi ปัจจุบัน ไม่เพิ่มกระดูกใหม่
- เกราะอก/ท้องตาม Chest/Spine เกราะไหล่ตาม UpperArm ปลอกแขนตาม LowerArm แผ่นหลังมือตาม Hand
- ปลอกแขนคู่แยกเป็นช่อง arms ไม่รวมในเสื้อ แผ่นหลังมือไม่ได้หุ้มนิ้วทั้งมือ นิ้วตัวฐานยังขยับได้
- กางเกงตาม Hips/UpperLeg เกราะหน้าแข้งตาม LowerLeg รองเท้าตาม Foot
- วงแหวนตาม Head; `hide_hair: false`, `hide_head: false` จึงใช้ผมและใบหน้าที่เลือกแยกไว้ได้ ทรงผมสูงมากอาจชนวงแหวน ต้องปรับ fit ของชิ้นนั้น
- แผ่นเกราะและลายเส้นเป็น mesh low-poly ใช้ material สี ไม่มี cloth simulation หรือ collision อัตโนมัติ

## Source และภาพ

- Builder: `tools/blender/build_studio_oathkeeper_armor.py`
- Assembly: `art/source/characters/chibi_oathkeeper_armor_preview.blend`
- Render: `art/characters/chibi-studio/armor_azure_oathkeeper_preview.png`
- Studio screenshot: `tools/image_to_3d/studio-oathkeeper-armor.png`

ใส่ครบใน Studio และดูท่ายืนกับ Run แล้ว ตัวฐานและคลิปเดิมไม่ถูกแก้ไข ยังไม่ได้ตรวจครบทุกคลิป/ทุกเฟรม หรือการใช้งานใน Godot ทรงผมและใบหน้าตามภาพอ้างอิงไม่ได้รวมอยู่ในชุดนี้

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/blender/build_studio_oathkeeper_armor.py
python3 tools/register_studio_items.py
```

Builder เขียนเฉพาะชิ้นชุดนี้และ preview ไม่สร้างรายการที่อยู่ใน Archive กลับมาเอง
