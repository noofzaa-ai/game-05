# Crimson Crane — ชุดผ้ากระเรียนขาวแดง

ชุดผ้าตามภาพผู้ใช้: เสื้อขาวแขนหลวม ขอบแดง ผ้าด้านในสีกรมท่าลายปักทอง ผ้าคาดเอวแดง ชายชุดบานสั้น และรองเท้าขาวผูกแดง พร้อมปีกประดับขมับ ไม่รวมอาวุธ ผม หรือใบหน้าใน GLB ชุด

## ไฟล์

วางใน `art/items/clothing/` แต่ละ ID มี `.glb`, `.json` และ `.png` ชื่อเดียวกัน Catalog ของ Studio อ่านไฟล์เหล่านี้โดยตรง

| Asset ID | Slot | Tri |
| --- | --- | ---: |
| `clothing_crane_wings_01` | head | 78 |
| `clothing_crane_jacket_01` | shirt | 290 |
| `clothing_crane_sleeves_01` | arms | 148 |
| `clothing_crane_skirt_01` | pants | 228 |
| `clothing_crane_boots_01` | shoes | 266 |
| **รวมครบชุด** | | **1,010** |

นับจาก GLB จริง รวมทุกช่องและเครื่องประดับหัว ไม่รวมตัวฐาน ผม ใบหน้า และอาวุธ อยู่ในงบ 1,500 tri Set ID: `outfit_crimson_crane_01`; asset_version 1

## ผ้าขยับอย่างไร

- เสื้อและลายที่อยู่บนเสื้อผสม weight ของ Hips / Spine / Chest / UpperChest ตามระดับความสูง ไม่มีวัสดุ metallic ในผ้าหรือเส้นปัก
- แขนเสื้อมีวง vertex รอบข้อศอก ผสม UpperArm / LowerArm ภายในระยะ 66 mm รอบข้อศอกของ bind pose ชิ้นต้นแขนใน shirt และชิ้นปลายแขนใน arms ซ้อนกันเล็กน้อยด้วย weight แบบเดียวกัน
- ปลายแขนเสื้อเป็นช่องเปิดจริง ไม่มี cap ปิดตันที่ข้อมือ ไม่ผูก sleeve กับนิ้วหรือมือ จึงใช้ท่ากำและอาวุธเดิมได้
- ชายชุดมี mesh ครึ่งซ้ายและขวาแยกกัน ผสม Hips กับ UpperLeg ของข้างนั้น ชายชุดสั้นเหนือเข่า จึงไม่มี vertex ที่ผูกข้ามสองขาหรือผูกถึงน่อง
- ลายปักชายชุดใช้ weight แบบเดียวกับผ้าที่ตำแหน่งนั้น ขอบหน้า/หลังซ้อนกันในท่ายืน และเปิดตามขาขณะก้าว
- ปีกประดับตาม Head ใช้ `hide_hair: false` / `hide_head: false` ผมและใบหน้าสลับแยกได้ ผมทรงสูงหรือกว้างอาจชนปีก ต้องปรับ fit ของเครื่องประดับ
- ส่วนรองเท้าตาม Foot ถุงน่อง/ผ้าหุ้มหน้าแข้งตาม LowerLeg

การขยับเป็น skin deformation จาก skeleton เดิม ไม่มี cloth simulation, collision อัตโนมัติ หรือกระดูกผ้าเพิ่ม ในท่ากางขา/งอศอกรุนแรงผ้าอาจชนกัน ต้องเก็บเฉพาะท่าต่อไป

## Source และภาพสำหรับดูต่อ

- Builder: `tools/blender/build_studio_crane_outfit.py`
- Assembly ท่ายืน: `art/source/characters/chibi_crane_robe_preview.blend`
- ภาพท่ายืน: `art/characters/chibi-studio/outfit_crimson_crane_preview.png`
- ด้านข้าง/หลัง: `outfit_crimson_crane_side.png`, `outfit_crimson_crane_back.png` ในโฟลเดอร์เดียวกัน
- ภาพ Run: `art/characters/chibi-studio/outfit_crimson_crane_run.png`

ดูภาพท่ายืน ข้าง หลัง และ Run เฟรม 10 ใน Blender แล้ว ยังไม่ได้ดูครบทุกเฟรม/ทุกคลิป หรือลองใน Godot ไม่มีการเปลี่ยนตัวฐาน คลิป หรือสถานะหน้าจอ Studio ที่ผู้ใช้เปิดอยู่

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/blender/build_studio_crane_outfit.py
python3 tools/register_studio_items.py
```

Builder เขียนเฉพาะชุดนี้และ preview พร้อมตรวจงบก่อน publish และป้องกันสร้าง ID ที่อยู่ใน Archive กลับมา
