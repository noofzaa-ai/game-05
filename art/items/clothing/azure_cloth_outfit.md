# Azure Cloth — ชุดผ้าขาวคราม

สร้างจากภาพอ้างอิงผู้ใช้: เสื้อผ้าขาวแขนกุดคอจีน ขอบน้ำเงิน กระดุมสองเม็ด สายคาดเอว ชายผ้าเฉียง ปลอกแขนลายไขว้ ผ้าหุ้มหน้าแข้งน้ำเงิน และรองเท้าหนังเหลืองพื้นสีอ่อน ผม หน้า และอาวุธในภาพไม่ได้รวมในชุด

## ไฟล์แยกและ ID

วางอยู่ใน `art/items/clothing/` ทุก ID มี GLB, JSON และ PNG ชื่อเดียวกัน Catalog ของ Studio อ่านพบทั้งสี่ชิ้นแล้ว โหลดรายการใหม่ด้วยการรีเฟรชหน้า โดยไม่ต้องเพิ่มรายชื่อในโค้ดเว็บ

| Asset ID | Slot | Tri |
| --- | --- | ---: |
| `clothing_azure_cloth_tunic_01` | shirt | 264 |
| `clothing_azure_cloth_cuffs_01` | arms | 88 |
| `clothing_azure_cloth_skirt_01` | pants | 222 |
| `clothing_azure_cloth_boots_01` | shoes | 292 |
| **รวมครบชุด** | | **866** |

ตัวเลขจาก indices ใน GLB จริง ไม่รวมตัวฐาน ผม หน้า และอาวุธ อยู่ในงบ 1,500 tri Set ID: `outfit_azure_cloth_01`; asset_version 1 รักษา ID เหล่านี้สำหรับ mapping ใน Godot

## การขยับของผ้า

- ใช้ GameRig 57 จุดและ bind pose ของ Chibi ปัจจุบัน ตัวฐานและคลิปไม่ถูกแก้ไข
- เสื้อและตะเข็บหน้าใช้ weight ผสม Hips/Spine/Chest/UpperChest ตามความสูง น้ำหนักรวม 1 ต่อ vertex
- ชายผ้าแบ่งสี่แผ่น: หน้า/หลังของขาซ้าย และหน้า/หลังของขาขวา มีรอยเปิดด้านข้างและขอบซ้อนกลางตัว
- แต่ละแผ่นผสม Hips กับ UpperLeg ของข้างนั้นช่วงเอว ไม่มี vertex ผูกข้ามสองขา ขอบครามใช้ weight แบบเดียวกับผ้าตรงตำแหน่งนั้น
- ปลอกแขนคู่แยกเป็น slot arms ตาม LowerArm สายต้นแขนและขอบวงแขนเป็นส่วนของ shirt ตาม UpperArm
- ผ้าหุ้มหน้าแข้งตาม LowerLeg รองเท้าตาม Foot
- การเคลื่อนไหวเป็น skin deformation ไม่ใช่ cloth physics ไม่มี collision อัตโนมัติ ท่ากว้างมากยังอาจทำให้ผ้าชนกันหรือทะลุ ต้องเก็บ fit รายท่าต่อไป

## Source และภาพที่ดูแล้ว

- Builder: `tools/blender/build_studio_azure_cloth_outfit.py`
- Assembly: `art/source/characters/chibi_azure_cloth_armor_preview.blend`
- ภาพรวม: `art/characters/chibi-studio/outfit_azure_cloth_preview.png`
- มุมหน้า/ข้าง/หลัง: `outfit_azure_cloth_front.png`, `outfit_azure_cloth_side.png`, `outfit_azure_cloth_back.png` ในโฟลเดอร์ภาพเดียวกัน
- ท่าวิ่งตัวอย่าง: `art/characters/chibi-studio/outfit_azure_cloth_run.png` ใช้ Run เดิมเฟรม 7 ใน assembly แยก

ดูภาพนิ่งจากหน้า ข้าง หลัง และหนึ่ง pose ของ Run แล้ว ไม่ได้ตรวจครบทุกเฟรม/ทุกคลิปหรือใน Godot ไม่ได้เปลี่ยนการเลือกอุปกรณ์บนหน้า Studio ที่เปิดอยู่

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/blender/build_studio_azure_cloth_outfit.py
```

Builder ตรวจงบก่อน publish สร้างเฉพาะชุดนี้และ preview ไม่สร้างไอเทมที่อยู่ใน Archive กลับมาเอง
