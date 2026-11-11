# Gilded Sentinel — เกราะองครักษ์

ชุดเหล็กขอบทองจากภาพอ้างอิงผู้ใช้ มีหมวกปิดหน้าพู่ดำ ช่องมองและช่องระบายอากาศ อกเหล็ก แขนผ้าแดงเข้ม ปลอกแขนยาว ชายชุดแยกแผ่น และรองเท้าเกราะ

## ไฟล์แยกใน art/items/clothing/

| Asset ID / ชื่อไฟล์ GLB | ช่อง | Tri |
| --- | --- | ---: |
| `clothing_sentinel_helmet_01` | head | 378 |
| `clothing_sentinel_cuirass_01` | shirt | 300 |
| `clothing_sentinel_tassets_01` | pants | 194 |
| `clothing_sentinel_sabatons_01` | shoes | 416 |
| `clothing_sentinel_bracers_01` | arms | 200 |
| **รวมชุด** | | **1,488** |

นับ triangles จาก indices ของทุก mesh primitive ใน GLB ไม่รวมตัวฐาน ผม ใบหน้า และอาวุธ ตัวเลือกใน Studio โหลดจาก GLB+JSON+PNG เหล่านี้ Set ID ใน sidecar คือ `armor_gilded_sentinel_01`

## ช่องหมวกใหม่

- `slot: head` ใช้ skinned GLB พิกัดเดียวกับตัวฐาน น้ำหนัก Head 1.0
- หมวกปิดหน้าชุดนี้ใช้ `hide_hair: true` และ `hide_head: true` ซ่อนผม หัว และใบหน้าด้านในเพื่อไม่ให้ทะลุหมวก
- ตัวเลือกผม/ใบหน้ายังคงอยู่ ถอดหมวกแล้วคืนการแสดงผลตามตัวเลือกเดิม
- Export ตัวละครรวมชุดอ่านกติกาเดียวกันและไม่นำผม/หัว/ใบหน้าที่ซ่อนไปด้วย ยังไม่ได้ตรวจไฟล์รวมใน Godot
- หมวกเปิดหน้าตัวอื่นสามารถตั้ง flags เป็น false ได้

## การขยับ

ใช้ GameRig57 และ bind pose เดิม แต่ละแผ่นแข็งมี vertex group กระดูกเดียว อกตาม Chest ท้องตาม Spine ไหล่ตาม UpperArm ปลอกแขนตาม LowerArm เข็มขัดตาม Hips ชายชุดแยกซ้าย/ขวาตาม UpperLeg ของข้างนั้น หน้าแข้งตาม LowerLeg เท้าตาม Foot

ชายชุดเป็นแผ่นเกราะแยก ไม่ใช่ผ้าจำลอง ไม่มี collision หรือการหลบขาอัตโนมัติ ดูท่ายืนและ Run ใน Studio แล้ว แต่ยังไม่ได้ตรวจการชนกันครบทุกเฟรม/ทุกมุม

## Source

- Generator: `tools/blender/build_studio_sentinel_armor.py`
- Blender assembly: `art/source/characters/chibi_sentinel_armor_preview.blend`
- Render: `art/characters/chibi-studio/armor_gilded_sentinel_preview.png`
- Studio screenshot: `tools/image_to_3d/studio-sentinel-armor.png`

ไม่เปลี่ยน skeleton หรือตัวฐาน ไม่เขียนทับชุดก่อนหน้า การสร้างซ้ำปฏิเสธ ID ที่เก็บใน Archive

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/blender/build_studio_sentinel_armor.py
python3 tools/register_studio_items.py
```

## Revision 2 — ปลอกแขนแยกและงบ 1,500 tri

เสื้อรุ่นนี้ไม่รวมปลอกแขน ต้องเลือกปลอกแขนคู่ในช่อง `arms` เพิ่ม ชุดครบรวมทุกช่องมี 1,488 tri (นับจาก GLB จริง) ดูตัวเลขรายชิ้นและ ID ใน `README.md` ของโฟลเดอร์นี้ ค่าเก่าก่อนแยกชิ้นไม่ใช้เป็นงบปัจจุบัน
