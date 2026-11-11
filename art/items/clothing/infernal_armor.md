# Crimson Infernal — เกราะรัตติกาลดำแดง

ชุดดำแดงตามภาพอ้างอิงผู้ใช้: จันทร์เสี้ยวด้านหลังหัว ขอบเงิน ลายแดง เขี้ยว เกราะไหล่ทรงปีก ปลอกแขนปลายแหลม ชายเอวแยก และรองเท้าดำแต่งลายแดง

## ไอเทมแยก / Triangle budget

ทุกชิ้นเป็น GLB+JSON+PNG ใน `art/items/clothing/` ใช้ ID ต่อไปนี้เป็นชื่อไฟล์:

| Asset ID | Slot | Tri |
| --- | --- | ---: |
| `clothing_infernal_crescent_01` | head | 250 |
| `clothing_infernal_cuirass_01` | shirt | 354 |
| `clothing_infernal_bracers_01` | arms | 100 |
| `clothing_infernal_tassets_01` | pants | 155 |
| `clothing_infernal_boots_01` | shoes | 276 |
| **รวมชุดครบ** | | **1,135** |

นับจาก indices ใน GLB จริง ไม่รวมตัวฐาน ผม ใบหน้า และอาวุธ อยู่ภายในงบ 1,500 tri ต่อชุด Set ID: `armor_crimson_infernal_01`; asset_version 1

## ลักษณะการใช้งาน

- เครื่องประดับ head เป็นจันทร์เสี้ยวเปิดหน้า ใช้ Head 1.0 และไม่ซ่อนผมหรือหัว (`hide_hair: false`, `hide_head: false`)
- ผมไม่รวมอยู่ในเครื่องประดับหัว สามารถเลือกทรงเดิมจาก Studio ได้ แต่ทรงที่ใหญ่ต่างจากฐานอาจชนจันทร์เสี้ยว ต้องปรับ fit ของไอเทม
- เสื้อมีอกและไหล่ ปลอกแขนคู่แยกใน arms ตาม LeftLowerArm/RightLowerArm
- ชายชุดและสายรัดต้นขาแต่ละข้างใช้ UpperLeg ของข้างนั้น ไม่มี vertices เชื่อมขาสองข้าง
- เกราะหน้าแข้งตาม LowerLeg ส่วนรองเท้าตาม Foot
- ลายแดงสร้างเป็น geometry ไม่ใช้ texture bitmap จึงไม่มีไฟล์ texture เพิ่ม
- ใช้ skeleton และ bind pose เดิม ไม่มี cloth physics หรือ collision อัตโนมัติ ยังไม่ได้ตรวจ motion ครบทุกมุม/ทุกเฟรม หรือใช้งานชุดนี้ใน Godot

## Source

- Builder: `tools/blender/build_studio_infernal_armor.py`
- Assembly: `art/source/characters/chibi_infernal_armor_preview.blend`
- Render: `art/characters/chibi-studio/armor_crimson_infernal_preview.png`
- Studio: `tools/image_to_3d/studio-infernal-armor.png`

เปิดใส่ครบห้าชิ้นใน Studio ท่ายืนแล้ว ระบบแสดงชุด 1,135 / 1,500 tri ส่วนตัวละครรวมบ๊อบเดิมและชุดอยู่ที่ 5,217 tri ตัวฐานและ animation ไม่ถูกแก้ไข

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/blender/build_studio_infernal_armor.py
python3 tools/register_studio_items.py
```

การสร้างซ้ำเขียนเฉพาะชุดนี้และ preview และปฏิเสธ ID ที่อยู่ใน Archive
