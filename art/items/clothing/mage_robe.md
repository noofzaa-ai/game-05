# Violet Mage — ชุดคลุมจอมเวทม่วงทอง

ชุดจากภาพอ้างอิงผู้ใช้: ฮู้ดเปิดหน้าเขาแดงสองข้างยาวไม่เท่ากัน เสื้อคลุมม่วงขอบทอง ผ้าประดับอกและโบว์ดำ แขนเสื้อบาน ชายคลุมยาวลายดาว และรองเท้าสีเข้ม

## ไฟล์แยกใน art/items/clothing/

ทุก ID ใช้เป็นชื่อ GLB พร้อม JSON และ PNG ชื่อเดียวกัน:

| Asset ID | Slot | Tri |
| --- | --- | ---: |
| `clothing_mage_hood_01` | head | 252 |
| `clothing_mage_tunic_01` | shirt | 299 |
| `clothing_mage_sleeves_01` | arms | 92 |
| `clothing_mage_robe_01` | pants | 248 |
| `clothing_mage_boots_01` | shoes | 120 |
| **รวมชุดครบ** | | **1,011** |

นับจาก GLB จริง ไม่รวมตัวฐาน ผม ใบหน้า และอาวุธ อยู่ในงบ 1,500 tri Set ID: `armor_violet_mage_01`; asset_version 1

## ชุดยาวขยับอย่างไร

- เสื้อและผ้าประดับอกใช้ weight ผสม Hips/Spine/Chest/UpperChest เพื่อให้ช่วงเอวและอกขยับต่อกัน
- ชายคลุมแบ่งครึ่งซ้าย/ขวา มีขอบซ้อนกันในท่ายืนและรอยเปิดด้านหน้า/หลังเมื่อก้าวขา
- แผ่นซ้ายใช้ Hips/LeftUpperLeg/LeftLowerLeg; แผ่นขวาใช้ Hips/RightUpperLeg/RightLowerLeg น้ำหนักรวม 1.0 ต่อ vertex ไม่ผูกผ้าชิ้นเดียวข้ามสองขา
- ผสม UpperLeg/LowerLeg ในช่วงเข่า เพื่อให้ชายคลุมพับตามเข่า ไม่ใช่แผ่นเกราะแข็งยาวถึงข้อเท้า
- ลายดาวและขอบทองมี weight แบบเดียวกับผ้าตรงตำแหน่งนั้น ไม่ลอยแยกออกจากผ้าขณะขยับ
- แขนเสื้อบานอยู่ใน slot arms แยกจากเสื้อ ตาม LowerArm ของแต่ละข้าง รองเท้าตาม Foot
- ใช้ skeleton เดิม ไม่มี cloth physics, กระดูกชายผ้าใหม่ หรือ collision อัตโนมัติ การขยับผ้ายังเป็น skin deformation อาจชนกันหรือทะลุในท่ากว้างมาก ต้องตรวจและปรับเฉพาะท่าต่อไป

## ฮู้ดและใบหน้า

ฮู้ดตาม Head และใช้ `hide_hair: true` เพื่อไม่ให้ผมทะลุเนื้อฮู้ด แต่ `hide_head: false` คงหัวและใบหน้าที่เลือกไว้ ไม่รวมทรงผมหรือใบหน้าใหม่ใน GLB ชุด ใบหน้าที่กว้าง/สูงต่างจากฐานอาจต้องปรับ fit ช่องเปิด

## Source และสิ่งที่ดูแล้ว

- Builder: `tools/blender/build_studio_mage_robe.py`
- Assembly: `art/source/characters/chibi_mage_robe_preview.blend`
- Render: `art/characters/chibi-studio/armor_violet_mage_preview.png`
- Studio screenshot: `tools/image_to_3d/studio-mage-robe.png`

ใส่ครบใน Studio และดูท่ายืนกับ Run แล้ว ชายชุดแต่ละด้านขยับตามขาของตัวเอง ยังไม่ได้ตรวจครบทุกเฟรม/ทุกคลิป/ทุกมุม หรือใช้งานใน Godot ตัวฐานและคลิปเดิมไม่ถูกแก้ไข

ปุ่มรีเซ็ตมุมมองของ chibi-studio คำนวณ bounds จาก mesh ที่มองเห็นใน pose ปัจจุบัน จึงรวมฮู้ด/เขา/เครื่องประดับที่เพิ่มจากตัวฐานไว้ในมุมเต็มตัว โดยไม่ขยายช่อง viewer

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/blender/build_studio_mage_robe.py
python3 tools/register_studio_items.py
```

เขียนเฉพาะชุดนี้และ preview ไม่สร้างรายการที่อยู่ใน Archive กลับมาเอง
