# เกราะกะโหลกแดงทอง

สร้างจากภาพอ้างอิงหน้า–หลัง–ข้างของผู้ใช้ วันที่ 7 ตุลาคม 2026:
หมวกเปิดหน้าสีเขียวดำประดับกะโหลกทองแดงและปีกงาช้าง
เกราะแดงขอบทอง คอและไหล่ประดับขนงาช้าง ปลอกแขนหนามทอง
กางเกงหนังแดงเข้ม และบูตเกราะสูงแต่งเขี้ยวงาช้าง
ปรับสัดส่วนให้เข้ากับตัวฐาน Chibi ปัจจุบัน

Set ID: `armor_crimson_skull_01` — asset_version 1

## ไฟล์และ ID สำหรับ Godot

แต่ละ ID มี GLB, JSON และ PNG ชื่อเดียวกันอยู่ใน
`/Users/user/godot-project/test01/art/items/clothing/`

| ID | ช่อง | Tri |
| --- | --- | ---: |
| `clothing_crimson_skull_helmet_01` | head | 170 |
| `clothing_crimson_skull_cuirass_01` | shirt | 355 |
| `clothing_crimson_skull_bracers_01` | arms | 216 |
| `clothing_crimson_skull_pants_01` | pants | 258 |
| `clothing_crimson_skull_boots_01` | shoes | 370 |
| **รวมครบชุด** | | **1,369 / 1,500** |

ตัวเลขอ่านจาก indices ใน GLB ที่ export จริง ไม่รวมตัวฐาน ผม ใบหน้า และอาวุธ
Godot path คือ `res://art/items/clothing/<ID>.glb`
GLB ทั้งห้าชิ้นรวมประมาณ 227 KB ไม่รวม PNG ตัวอย่าง
ไม่มี bitmap texture ลายและสีใช้ geometry กับ material

## การผูกกระดูก

- ใช้ GameRig57 และ T-pose bind space เดิม ไม่มีคลิปใหม่ในไอเทม
- หมวกตาม Head; ซ่อนผมที่เลือกไว้ (`hide_hair: true`) แต่ไม่ซ่อนหัวหรือใบหน้า
- เกราะอกตาม Chest, คอตาม UpperChest, เอวตาม Spine
- เสื้อมีไหล่และต้นแขน; ปลอกแขนอยู่ในไฟล์ arms ตาม LowerArm
  ถุงมือแบบเปิดนิ้วตาม Hand จึงไม่ล็อกนิ้วเป็นก้อนเดียว
- กางเกงแยกตาม UpperLeg ของแต่ละข้าง ผสม Hips บริเวณเอว
  แผ่นเกราะต้นขาไม่เชื่อมสองขาเข้าด้วยกัน
- หน้าแข้งตาม LowerLeg; รองเท้าและเขี้ยวข้อเท้าตาม Foot
- ไม่มี cloth physics หรือ collision อัตโนมัติ

Studio อ่านไอเทมจาก JSON ข้าง GLB และชุดจาก `outfit_sets.json`
ใช้ชื่อ **เกราะกะโหลกแดงทอง** ในรายการชุด
ID ใช้ mapping กับรายการไอเทม Godot ได้ตาม manifest ของคลัง

## Source และภาพตัวอย่าง

- Builder: `/Users/user/godot-project/test01/tools/blender/build_studio_crimson_skull_armor.py`
- Assembly: `/Users/user/godot-project/test01/art/source/characters/chibi_crimson_skull_armor_preview.blend`
- ภาพรวม: `/Users/user/godot-project/test01/art/items/clothing/set_armor_crimson_skull_01.png`
- สามมุม: `/Users/user/godot-project/test01/art/items/clothing/armor_crimson_skull_01_front.png`,
  `armor_crimson_skull_01_back.png`, `armor_crimson_skull_01_side.png` ในโฟลเดอร์เดียวกัน

ดูภาพจาก Blender ทั้งหน้า–หลัง–ข้างแล้ว
ยังไม่ได้ตรวจการวิ่งกับชุดนี้ใน Studio หรือการนำเข้า Godot
สีผิว/ตาในภาพเป็น material สำหรับ assembly preview เท่านั้น
ไม่ได้เขียนทับตัวฐานหรือแอนิเมชันเดิม

## สร้างซ้ำ

```sh
cd /Users/user/godot-project/test01
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/blender/build_studio_crimson_skull_armor.py
```

Builder ตรวจงบทั้งชุดก่อน export และปฏิเสธ ID ที่ถูกย้ายเข้า Archive
การสร้างซ้ำเขียนเฉพาะไฟล์ของชุดนี้กับ assembly preview
รายการชุดใน `outfit_sets.json` เพิ่มครั้งเดียวแล้ว ไม่ต้องเพิ่มซ้ำ
