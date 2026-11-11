# ชุดลาดตระเวนม่วงเทา

สร้างตามภาพอ้างอิง Flyff ด้านหน้าและหลัง: เสื้อม่วงเทา หนังไหล่สีน้ำตาล ชายเสื้อเฉียง กางเกงขาสั้นสีพลัม ถุงมือเทา ข้อมือแดงม่วง และบูตสูงสายไขว้ลายผีเสื้อสีทอง

- Set ID: `cloth_lavender_ranger_01`
- ไฟล์อยู่ใน `art/items/clothing/` แยก GLB + JSON + PNG ทั้ง 4 ชิ้น
- รวม **1,500 tri** เฉพาะอุปกรณ์ทั้งชุด ไม่รวมตัวฐาน ผม ใบหน้า หรืออาวุธ
- ปลอกแขน แขนเสื้อช่วงล่าง และถุงมืออยู่ช่อง `arms`; เสื้อรวมแขนช่วงบน
- ใช้ GameRig57 เดิม ผิวถุงมือใช้กระดูกนิ้วเดิม ชายเสื้อแต่ละข้างผูก Hips กับต้นขาข้างเดียวกัน และบูตถ่วงข้ามข้อเท้า
- ไม่มี cloth simulation และไม่ได้เปลี่ยนคลิปหรือ source ตัวละคร
- เพิ่มรายการชุดและ stable IDs ใน `outfit_sets.json` และ `art/items/item_manifest.json`

| ชิ้น | Asset ID | Tri |
| --- | --- | ---: |
| เสื้อ | `clothing_lavender_ranger_tunic_01` | 444 |
| ปลอกแขนและถุงมือ | `clothing_lavender_ranger_gloves_01` | 420 |
| กางเกงขาสั้น | `clothing_lavender_ranger_shorts_01` | 188 |
| รองเท้า | `clothing_lavender_ranger_boots_01` | 448 |

## สร้างซ้ำ

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/blender/build_studio_lavender_ranger.py
python3 tools/register_studio_items.py
```

สคริปต์สร้างซ้ำเขียนทับเฉพาะไฟล์ของชุดนี้ และปฏิเสธ ID ที่อยู่ใน Archive

## ภาพและต้นฉบับ

ภาพหน้า หลัง ข้าง และสามส่วนสี่ รวมถึง `lavender_ranger_preview.blend` อยู่ใน `art/source/clothing/lavender_ranger_01/` ตรวจภาพใน Blender แล้ว; ยังไม่ได้ตรวจการเล่นใน Studio/Godot

ใน Studio รีโหลดรายการแล้วเลือก “ชุดลาดตระเวนม่วงเทา” ได้ทั้งชุด หรือเลือกชิ้นในแต่ละช่อง ชุดนี้ไม่รวมทรงผมและใบหน้า
