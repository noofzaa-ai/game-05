# Embergrey Cloth — ชุดผ้าเทาลายส้ม

เวอร์ชันสีใหม่ของชุดผ้าคราม/ดำแดง ใช้รูปทรง ข้อต่อ และ skin weight เดิม ผ้าหลักสีเทา ปลอกแขนและผ้าหุ้มหน้าแข้งสีเทาเข้ม รองเท้าหนังเทา ขอบ ลายไขว้ กระดุม ตะเข็บ และลายหน้าแข้งสีส้ม

## ไฟล์และ ID

ทุกชิ้นอยู่ใน `art/items/clothing/` มี GLB, JSON และ PNG ชื่อเดียวกัน Catalog ของ Studio อ่านพบแล้ว รีเฟรชเพื่อโหลดการ์ดใหม่

| Asset ID | Slot | Tri |
| --- | --- | ---: |
| `clothing_embergrey_cloth_tunic_01` | shirt | 264 |
| `clothing_embergrey_cloth_cuffs_01` | arms | 88 |
| `clothing_embergrey_cloth_skirt_01` | pants | 222 |
| `clothing_embergrey_cloth_boots_01` | shoes | 292 |
| **รวมครบชุด** | | **866** |

นับจาก GLB จริง ไม่รวมตัวฐาน ผม หน้า และอาวุธ อยู่ในงบ 1,500 tri Set ID: `outfit_embergrey_cloth_01`; asset_version 1 ใช้ ID ใหม่เหล่านี้สำหรับ mapping ใน Godot แยกจากสองสีเดิม

## Rig และ source

ใช้ GameRig 57 จุด เสื้อผสม Hips/Spine/Chest/UpperChest ชายผ้าสี่แผ่นผสม Hips กับ UpperLeg ของข้างนั้น ปลอกแขนตาม LowerArm ผ้าหุ้มหน้าแข้งตาม LowerLeg และรองเท้าตาม Foot ขอบและลายใช้ weight เดียวกับผ้า การขยับเป็น skin deformation ไม่มี cloth physics หรือ collision อัตโนมัติ รายละเอียดรูปทรงอยู่ใน `azure_cloth_outfit.md`

- Builder: `tools/blender/build_studio_embergrey_cloth_outfit.py`
- Assembly: `art/source/characters/chibi_embergrey_cloth_armor_preview.blend`
- Preview: `art/characters/chibi-studio/outfit_embergrey_cloth_preview.png`

ดูภาพประกอบของเวอร์ชันเทาส้มแล้ว ตัวเลือกในหน้า Studio ที่เปิดอยู่และชุดสีเดิมไม่ได้ถูกแก้ไข

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/blender/build_studio_embergrey_cloth_outfit.py
```

Builder ตรวจงบก่อน publish และไม่สร้างรายการที่อยู่ใน Archive กลับมาเอง
