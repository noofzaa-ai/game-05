# Dark Knight armor — Chibi Studio

ชุดเกราะทดลองจากภาพอ้างอิงผู้ใช้ 6 ตุลาคม 2026 เป็นเกราะแยกส่วนสำหรับตัวฐาน `chibi-sculpt-v1` ไม่ใช่ชุดผ้ายาวหรือโมเดลที่ถอดจากภาพโดยตรง

## ไฟล์และช่องใส่

วางใน `art/items/clothing/` พร้อม JSON และภาพตัวอย่างชื่อเดียวกัน:

| Asset ID / ชื่อไฟล์ GLB | ช่อง | ส่วนประกอบ |
| --- | --- | --- |
| `clothing_knight_cuirass_01.glb` | shirt | อก คอ ท้อง ไหล่ และต้นแขน |
| `clothing_knight_tassets_01.glb` | pants | เข็มขัด กางเกงชั้นใน และแผ่นชายเอวซ้าย/ขวา |
| `clothing_knight_greaves_01.glb` | shoes | เกราะเข่า หน้าแข้ง และเท้า |
| `clothing_knight_bracers_01.glb` | arms | ปลอกแขนและเกราะข้อศอกคู่ |

เลือกทั้งสี่ไอเทมใน Studio ได้ทีละช่อง ใช้คลิปเดิมของตัวละคร ไม่ต้องสร้าง skeleton ใหม่

## วิธีผูกกระดูก

- แต่ละแผ่นมีน้ำหนัก 1.0 กับกระดูกเดียว ไม่ผูกแผ่นแข็งข้ามสองข้อ
- อกตาม Chest; คอตาม UpperChest; ท้องตาม Spine; เข็มขัดตาม Hips
- ไหล่และต้นแขนตาม UpperArm; เกราะข้อศอกและปลายแขนตาม LowerArm
- ชายเอวแต่ละด้านตาม UpperLeg ของขานั้น แยก vertices ซ้าย/ขวา ไม่มีแผ่นเชื่อมขาสองข้าง
- หน้าแข้งและเกราะเข่าตาม LowerLeg; เท้าตาม Foot
- รวม geometry ต่อช่องก่อน export เพื่อลดจำนวน mesh โดยเก็บ vertex groups แยกตามกระดูก

## ข้อจำกัด

- ชายเกราะหมุนไปกับต้นขา ไม่มี cloth physics, secondary motion หรือ collision หลบขาอัตโนมัติ
- การไม่ยืดแผ่นเกราะไม่ได้รับประกันว่าจะไม่ชนกันเมื่อยกเข่าสูงหรือยกแขนมาก ต้องปรับช่องว่าง/รูปทรงตามท่าที่ใช้งาน
- ชุดนี้เข้ากับสัดส่วนและ bind pose ของ Chibi ปัจจุบัน ไม่รับประกันพอดีกับตัวละครที่สูงหรืออ้วนต่างกัน
- ยังไม่ได้ตรวจการใช้งานชุดนี้ใน Godot หรือ export ตัวละครรวมชุดทุกคลิป
- ถ้าทำเสื้อคลุมยาวจริง ต้องออกแบบกระดูกชายผ้าและ motion เพิ่ม ไม่ใช้ tassets ชุดนี้แทนระบบผ้า

## Source

- Generator: `tools/blender/build_studio_knight_armor.py`
- Blender assembly: `art/source/characters/chibi_knight_armor_preview.blend`
- ภาพรวม: `art/characters/chibi-studio/armor_dark_knight_preview.png`
- ไม่แก้ตัวฐาน `chibi_base_animated.blend` หรือคลิปเดิม
- Generator ปฏิเสธการสร้าง ID ที่อยู่ใน Archive เพื่อไม่คืนของที่ผู้ใช้เก็บไว้เอง

## สิ่งที่ดูใน Studio แล้ว

- เลือกเกราะครบสามช่องได้ และเห็นบนตัวละครในท่ายืนกับ Run
- ชุดครบรุ่นปัจจุบันมี 1,076 tri ไม่รวมตัวฐานและผม
- ภาพหน้าจอ: `tools/image_to_3d/studio-knight-armor.png`
- ยังไม่ได้ตรวจการทะลุครบทุกเฟรม ทุกมุม หรือทุกคลิป

คำสั่งสร้างใหม่จากรากโปรเจกต์ (เขียนทับเฉพาะชุดเกราะนี้และ preview):

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/blender/build_studio_knight_armor.py
python3 tools/register_studio_items.py
```

## Revision 2 — ปลอกแขนแยกและงบ 1,500 tri

เสื้อรุ่นนี้ไม่รวมปลอกแขน ต้องเลือกปลอกแขนคู่ในช่อง `arms` เพิ่ม ชุดครบรวมทุกช่องมี 1,076 tri (นับจาก GLB จริง) ดูตัวเลขรายชิ้นและ ID ใน `README.md` ของโฟลเดอร์นี้ ค่าเก่าก่อนแยกชิ้นไม่ใช้เป็นงบปัจจุบัน
