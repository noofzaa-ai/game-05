# Navy Scout armor — Chibi Studio

เกราะระดับรองจาก Dark Knight ตามภาพอ้างอิงผู้ใช้: เสื้อแขนกุดน้ำเงินเข้ม เกราะคอเงินประดับแดง ปลอกแขน กางเกงสั้นเหนือเข่า สนับแข้งและรองเท้าหนังแต่งเงิน ลดแผ่นเกราะใหญ่และเปิดไหล่/เอว ระดับนี้เป็นการออกแบบภาพลักษณ์ ยังไม่ได้กำหนดค่าพลังป้องกันใน Godot

## ไฟล์

ไฟล์ GLB, JSON และ PNG อยู่ใน `art/items/clothing/`:

| Asset ID | ช่อง |
| --- | --- |
| `clothing_scout_vest_01` | shirt — เสื้อ |
| `clothing_scout_breeches_01` | pants — กางเกงและเกราะเอวเล็ก |
| `clothing_scout_boots_01` | shoes — สนับแข้งและรองเท้า |
| `clothing_scout_bracers_01` | arms — ปลอกแขนคู่ |

Set ID ใน sidecar: `armor_navy_scout_01` ใช้ประกอบชุดจากสี่ไอเทม สลับผสมกับชุดอื่นทีละช่องได้

## Rig และข้อจำกัด

- ใช้ GameRig เดิมและ bind pose ของ `chibi-sculpt-v1`
- เสื้อแบ่ง Chest/Spine; ปลอกแขนตาม LowerArm; สายรัดต้นแขนตาม UpperArm
- เข็มขัดตาม Hips; ขากางเกงและแผ่นเอวแต่ละด้านตาม UpperLeg ข้างเดียว
- สนับแข้งตาม LowerLeg; รองเท้าตาม Foot แผ่นแข็งไม่ blend ข้ามข้อ
- รวม mesh ต่อช่อง ลด draw calls และคง vertex groups แยกไว้
- ไม่มี cloth simulation หรือ collision ระหว่างชิ้นเกราะ และยังไม่ได้ตรวจครบทุกมุม/ทุกเฟรมหรือใช้งานใน Godot
- ภาพอ้างอิงมีส่วนศีรษะด้วย งานชุดนี้สร้างเฉพาะเสื้อผ้า/เกราะสี่ช่อง ทรงผมและใบหน้าเลือกจากไอเทมเดิมของ Studio

## Source และภาพ

- `tools/blender/build_studio_scout_armor.py`
- `art/source/characters/chibi_scout_armor_preview.blend`
- `art/characters/chibi-studio/armor_navy_scout_preview.png`
- `tools/image_to_3d/studio-scout-armor.png`

ชุดปัจจุบันแยกสี่ชิ้น รวม 1,008 tri ไม่รวมตัวฐานและผม

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/blender/build_studio_scout_armor.py
python3 tools/register_studio_items.py
```

คำสั่งนี้เขียนเฉพาะเกราะลาดตระเวนและ preview ไม่เขียนทับชุด Dark Knight หรือตัวฐาน และปฏิเสธ ID ที่อยู่ใน Archive

## Revision 2 — ปลอกแขนแยกและงบ 1,500 tri

เสื้อรุ่นนี้ไม่รวมปลอกแขน ต้องเลือกปลอกแขนคู่ในช่อง `arms` เพิ่ม ชุดครบรวมทุกช่องมี 1,008 tri (นับจาก GLB จริง) ดูตัวเลขรายชิ้นและ ID ใน `README.md` ของโฟลเดอร์นี้ ค่าเก่าก่อนแยกชิ้นไม่ใช้เป็นงบปัจจุบัน
