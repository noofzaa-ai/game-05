# Crimson Cloth — ชุดผ้าดำลายแดง

เวอร์ชันสีใหม่ของชุดผ้าคราม ใช้รูปทรง จำนวน tri ข้อต่อ และ skin weight เดิม เปลี่ยนผ้า ปลอกแขน สายคาด ผ้าหุ้มหน้าแข้ง และรองเท้าเป็นดำ/ถ่าน พร้อมขอบ ลายไขว้ ตะเข็บ และลายหน้าแข้งสีแดง

## ไฟล์และ ID แยก

ทุกชิ้นอยู่ใน `art/items/clothing/` มี GLB, JSON และ PNG ชื่อเดียวกัน Catalog ของ Studio อ่านพบแล้ว รีเฟรชเพื่อโหลดการ์ดชุดใหม่

| Asset ID | Slot | Tri |
| --- | --- | ---: |
| `clothing_crimson_cloth_tunic_01` | shirt | 264 |
| `clothing_crimson_cloth_cuffs_01` | arms | 88 |
| `clothing_crimson_cloth_skirt_01` | pants | 222 |
| `clothing_crimson_cloth_boots_01` | shoes | 292 |
| **รวมครบชุด** | | **866** |

ตัวเลขจาก GLB จริง ไม่รวมตัวฐาน ผม หน้า และอาวุธ Set ID: `outfit_crimson_cloth_01`; asset_version 1 เป็นไอเทมใหม่สำหรับเลือกแยกจากชุดขาวคราม ใช้ ID นี้ mapping ใน Godot

## Rig

GameRig 57 จุดและ bind pose เดิม เสื้อใช้ Hips/Spine/Chest/UpperChest ชายผ้าสี่แผ่นผสม Hips กับ UpperLeg ของข้างนั้น ปลอกแขนตาม LowerArm ผ้าหุ้มหน้าแข้งตาม LowerLeg และรองเท้าตาม Foot ขอบและลายใช้ weight เดียวกับพื้นผิวผ้า การขยับเป็น skin deformation ไม่มี cloth physics หรือ collision อัตโนมัติ

## Source

- Builder: `tools/blender/build_studio_crimson_cloth_outfit.py`
- Assembly: `art/source/characters/chibi_crimson_cloth_armor_preview.blend`
- Preview: `art/characters/chibi-studio/outfit_crimson_cloth_preview.png`
- รายละเอียดรูปทรงและการดู pose ของชุดต้นแบบ: `art/items/clothing/azure_cloth_outfit.md`

ดูภาพประกอบของเวอร์ชันดำแดงแล้ว ไม่ได้เปลี่ยนตัวเลือกในหน้า Studio ที่เปิดอยู่ หรือแก้ชุดขาวคราม ตัวฐาน และคลิปเดิม

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/blender/build_studio_crimson_cloth_outfit.py
```

Builder ตรวจงบ 1,500 tri ก่อน publish และไม่สร้างรายการที่อยู่ใน Archive กลับมาเอง
