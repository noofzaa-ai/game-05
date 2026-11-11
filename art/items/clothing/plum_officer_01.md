# ชุดนายทหารม่วง

ชุดใหม่จากภาพอ้างอิงด้านหน้าและหลัง: หมวกพับขอบเงิน เสื้อม่วงเข้มคอสูงและปกสีอ่อน เชือกร้อยหน้าอก สายหนังไขว้ หลังเสื้อลายเส้น หางเสื้อแยกสองข้าง ข้อมือแต่งชายหยัก ถุงมือเข้ม กางเกงขาสั้น ถุงน่องสีอ่อน และบูตสามหัวเข็มขัด

- Set ID: `cloth_plum_officer_01`
- คลัง: `art/items/clothing/` มี GLB + JSON + PNG แยก 5 ชิ้น
- งบรวม 1402 tri รวมหมวกและปลอกแขน ไม่รวมตัวฐาน ผม ใบหน้า และอาวุธ
- ใช้ GameRig57 เดิม ไม่เปลี่ยน skeleton หรือคลิปตัวละคร
- ชายเสื้อแต่ละข้างผูกกับ Hips และต้นขาข้างเดียวกัน ไม่ถ่วงกับขาอีกข้าง ไม่มี cloth simulation
- ถุงมือรักษากระดูกนิ้วเดิม ถุงน่องถ่วงข้ามเข่า บูตถ่วงข้ามข้อเท้า
- หมวกไม่ซ่อนทรงผม; ออกแบบตำแหน่งให้ใส่กับผมบ๊อบปัจจุบัน
- รูปชุดและรายชิ้นลงคลังแล้ว พร้อม stable IDs และชุดรวมใน `outfit_sets.json`

| ชิ้น | ID | Tri |
| --- | --- | ---: |
| หมวก | `clothing_plum_officer_hat_01` | 78 |
| เสื้อหางยาว | `clothing_plum_officer_coat_01` | 394 |
| แขนเสื้อและถุงมือ | `clothing_plum_officer_gloves_01` | 318 |
| กางเกงและถุงน่อง | `clothing_plum_officer_shorts_01` | 192 |
| บูต | `clothing_plum_officer_boots_01` | 420 |

## สร้างซ้ำ

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/blender/build_studio_plum_officer.py
python3 tools/register_studio_items.py
```

สร้างซ้ำเขียนทับเฉพาะชุดนี้ ปฏิเสธ ID ใน Archive หรือ ID ที่ระบุ set อื่นไว้แล้ว

ภาพหน้า หลัง ข้าง สามส่วนสี่ และไฟล์ `plum_officer_preview.blend` อยู่ใน `art/source/clothing/plum_officer_01/` ภาพใช้สีตัวฐานสำหรับรีวิว ไม่เขียนทับ source ตัวละคร

รีเฟรช Studio แล้วเลือก “ชุดนายทหารม่วง” เพื่อใส่ทั้งชุด หรือเลือกแยกในช่อง head/shirt/arms/pants/shoes ได้ ตรวจภาพหน้า/หลัง/ข้างและเฟรมหนึ่งของท่า Run ใน Blender แล้ว ยังไม่ได้ตรวจการเล่นใน Studio/Godot
