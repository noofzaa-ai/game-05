# Frostguard / เกราะฟ้าเงิน ผ้าคลุมแดง

เพิ่มจากภาพอ้างอิงผู้ใช้วันที่ 2026-10-07 สำหรับ Chibi Studio / GameRig57

Set ID: `armor_frostguard_01` — งบรวม **1,083 / 1,500 tri** จาก GLB จริง

| ช่อง | ID / ชื่อไฟล์ GLB | Tri |
| --- | --- | ---: |
| shirt | `clothing_frostguard_cuirass_01.glb` | 417 |
| arms | `clothing_frostguard_bracers_01.glb` | 172 |
| pants | `clothing_frostguard_breeches_01.glb` | 186 |
| shoes | `clothing_frostguard_boots_01.glb` | 308 |

## ไฟล์และการนำเข้า

- ไอเทมทั้ง 4 ชิ้น: `art/items/clothing/` มี GLB, sidecar JSON และ PNG ชื่อเดียวกัน
- Mapping ใน Godot: ใช้ ID จาก JSON และ path `res://art/items/clothing/<ชื่อไฟล์>.glb`
- รูปทั้งชุด: `art/items/clothing/set_armor_frostguard_01.png`
- ภาพอ้างอิง: `art/source/clothing/frostguard/reference.png`
- Blender assembly: `art/source/characters/chibi_frostguard_armor_preview.blend`
- สคริปต์สร้าง: `tools/blender/build_studio_frostguard_armor.py`
- สร้างซ้ำด้วย Blender: `/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/blender/build_studio_frostguard_armor.py`

## การเคลื่อนไหว

เกราะแต่ละส่วนตามกระดูกแขน/ขาที่เกี่ยวข้อง เกราะต้นขาแยกซ้าย–ขวา
ผ้าคลุมรวมใน shirt และผสม weight Chest → Spine → Hips ไม่ผูกเชื่อมขาสองข้าง
ไม่มี cloth physics; อาจต้องเก็บการชนผ้าคลุมกับขาเมื่อใช้งานท่าเคลื่อนไหวจริง
ไม่มีการเปลี่ยนตัวฐาน กระดูก คลิปแอนิเมชัน จุดจับหรือ config อาวุธ
ไม่ได้รวมดาบ ผม หรือหูแมวจากภาพ

ตรวจภาพนิ่งด้านหน้า ข้าง และหลังจาก Blender แล้ว ยังไม่ได้ตรวจการเคลื่อนไหวใน Studio หรือ Godot
