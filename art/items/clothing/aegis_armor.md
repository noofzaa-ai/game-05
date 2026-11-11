# White Blue Aegis — เกราะเอจิสขาวน้ำเงิน

ชุดตามภาพอ้างอิงผู้ใช้: หมวกเปิดหน้า หงอนน้ำเงินและปีกแดงรูป V เกราะไหล่แหลมกว้าง เสื้อเกราะน้ำเงิน แผ่นท้องสีอ่อน ปลอกแขน และเกราะขาขาวน้ำเงิน

## ไฟล์และรหัสถาวร

วางใน `art/items/clothing/` ทุก ID มี GLB, JSON และ PNG ชื่อเดียวกัน Catalog ของ Studio สแกนไฟล์โดยตรง ไม่ต้องเพิ่มรายชื่อในเว็บ รีเฟรช Studio เพื่อโหลดรายการใหม่

| Asset ID | Slot | Tri |
| --- | --- | ---: |
| `clothing_aegis_helmet_01` | head | 182 |
| `clothing_aegis_cuirass_01` | shirt | 345 |
| `clothing_aegis_bracers_01` | arms | 100 |
| `clothing_aegis_tassets_01` | pants | 167 |
| `clothing_aegis_sabatons_01` | shoes | 338 |
| **รวมชุด** | | **1,132** |

นับจาก GLB จริง ไม่รวมตัวฐาน ผม ใบหน้า และอาวุธ ไม่เกินงบ 1,500 tri Set ID: `armor_white_blue_aegis_01`; asset_version 1; fit_profile `chibi-sculpt-v1`

## Rig

- ใช้ GameRig 57 จุดของตัวฐานปัจจุบัน ไม่เพิ่มกระดูกใหม่
- หมวกตาม Head มี `hide_hair: true`, `hide_head: false` ใช้ใบหน้าแยกที่เลือกไว้ได้
- เสื้อและแผ่นท้องตาม Chest/Spine ไหล่ตาม UpperArm แผ่นไหล่สร้างในท่ายืนแล้วแปลงกลับเข้า bind pose เพื่อรักษาทรงแหลมด้านข้าง
- ปลอกแขนคู่เป็นช่อง arms ตาม LowerArm ไม่รวมกับเสื้อ มือและนิ้วใช้ตัวฐานเดิม
- เกราะต้นขาแต่ละด้านตาม UpperLeg ไม่ผูกแผ่นเดียวข้ามสองขา
- เกราะหน้าแข้งตาม LowerLeg รองเท้าตาม Foot
- ไม่มี cloth physics หรือ collision อัตโนมัติ ท่าแขนยกสูงอาจทำให้แผ่นไหล่ชนศีรษะ ต้องตรวจเฉพาะท่าเพิ่มเติม

## Source / ภาพประกอบ

- Builder: `tools/blender/build_studio_aegis_armor.py`
- Assembly: `art/source/characters/chibi_aegis_armor_preview.blend`
- Render: `art/characters/chibi-studio/armor_white_blue_aegis_preview.png`

สร้าง GLB และภาพประกอบท่ายืนแล้ว Catalog อ่านทั้ง 5 ชิ้นได้ ตัวฐานและคลิปเดิมไม่ถูกแก้ไข ยังไม่ได้ตรวจ motion ใน Studio หรือการนำเข้า Godot ไม่มีการเปลี่ยนรายการที่เลือกอยู่ในหน้า Studio ของงานอื่น

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/blender/build_studio_aegis_armor.py
```

Builder ตรวจงบก่อน export และปฏิเสธการสร้าง ID ที่อยู่ใน Archive กลับมาเอง
