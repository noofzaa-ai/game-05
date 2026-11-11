# Navy Artificer — ชุดผ้าช่างกล

ชุดจากภาพอ้างอิงผู้ใช้: หมวกกรมท่าแถบน้ำตาลแดงและขนนก เสื้อสั้นผ้าพันเฉียงสีครีม/น้ำตาลแดง แขนเสื้อบานขอบครีม ชายชุดกรมท่าพร้อมกระเป๋าและหัวเข็มขัดเฟือง รองเท้าผ้าพร้อมสายรัดและหัวเข็มขัด

## ไฟล์และ ID

วางทุกชิ้นใน `art/items/clothing/` มี GLB, JSON และ PNG ชื่อเดียวกัน Studio อ่านเป็นการ์ดอัตโนมัติ ไม่ฝังรายการชุดไว้ในเว็บ

| Asset ID | Slot | Tri |
| --- | --- | ---: |
| `clothing_artificer_cap_01` | head | 145 |
| `clothing_artificer_tunic_01` | shirt | 282 |
| `clothing_artificer_cuffs_01` | arms | 132 |
| `clothing_artificer_skirt_01` | pants | 247 |
| `clothing_artificer_boots_01` | shoes | 380 |
| **รวมครบชุด** | | **1,186** |

ตัวเลขจาก primitive indices ของ GLB จริง ไม่รวมตัวฐาน ผม ใบหน้า และอาวุธ งบ 1,500 tri ต่อชุด Set ID: `cloth_navy_artificer_01`; asset_version 1

## การเคลื่อนไหวของผ้า

- ใช้ GameRig 57 จุดและ bind pose ของ Chibi ปัจจุบัน ไม่แก้ตัวฐานหรือคลิป
- เสื้อและลายผ้าใช้ weight ผสมตามความสูงระหว่าง Hips/Spine/Chest/UpperChest เพื่อพับตามลำตัว
- ชายชุดแบ่งซ้าย–ขวา ใช้ Hips กับ UpperLeg ของข้างนั้น แถบขอบใช้ weight เดียวกับผ้า ไม่มีผ้าชิ้นเดียวผูกข้ามสองขา
- กระเป๋าตามขาขวา ส่วนหัวเข็มขัดเฟืองตาม Hips โลหะไม่ยืดตามผ้า
- แขนเสื้อบานแยกช่อง arms ตาม LowerArm แผ่นหลังมือผ้าตาม Hand นิ้วตัวฐานและจุดจับอาวุธยังใช้ของเดิม ไม่ใช่ถุงมือหุ้มทุกนิ้ว
- รองเท้ามี shaft ตาม LowerLeg และปลายเท้าตาม Foot ช่วงข้อเท้า blend สองกระดูกเพื่อให้ต่อกันขณะงอเท้า
- หมวกตาม Head; `hide_head: false`, `hide_hair: false` เลือกผมและใบหน้าแยกได้ ทรงผมสูง/กว้างกว่าฐานอาจทะลุหมวก ต้องปรับ fit
- ใช้ผิว low-poly กับวัสดุผ้าความเงาต่ำ ไม่มี cloth simulation, กระดูกผ้าเพิ่ม หรือ collision อัตโนมัติ ท่ากว้างมากอาจเกิดการชน/ทะลุ ต้องเก็บ fit รายท่าต่อไป

## Source และภาพ

- Builder: `tools/blender/build_studio_artificer_cloth.py`
- Assembly: `art/source/characters/chibi_artificer_robe_preview.blend`
- Render: `art/characters/chibi-studio/cloth_navy_artificer_preview.png`
- Studio screenshot: `tools/image_to_3d/studio-artificer-cloth.png`

ใส่ครบใน Studio ดูด้านหน้า/ด้านหลัง และดู Walk/Run แล้ว ยังไม่ได้ตรวจทุกเฟรม/ทุกคลิปหรือใช้งานใน Godot ประแจใหญ่ ผม และใบหน้าตามภาพเป็นคนละไอเทม ไม่รวมในชุดผ้านี้

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/blender/build_studio_artificer_cloth.py
```

Builder เขียนเฉพาะชุดนี้และ preview มี guard ป้องกันสร้างรายการที่อยู่ใน Archive กลับมาเอง ID ต้องคงเดิมเมื่อปรับ asset รอบถัดไป
