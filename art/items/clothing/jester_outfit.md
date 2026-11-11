# Crimson Jester — ชุดผ้าตัวตลกแดงขาว

จากภาพอ้างอิงผู้ใช้: หมวกผ้าแดงขาวขอบทอง กระดิ่งสองข้าง เสื้อผ้าสีเข้มปักทองพลอยเขียว แขนเสื้อพองแดงขาว กางเกงผ้าม่วงแดง และรองเท้าผ้าปลายงอนประดับกระดิ่ง

## Asset แยก

โฟลเดอร์ `art/items/clothing/` แต่ละ ID มี `.glb`, `.json`, `.png` ชื่อเดียวกัน เป็น ID ถาวรสำหรับ map ใน Godot

| ID | Slot | Tri จาก GLB |
| --- | --- | ---: |
| `clothing_jester_cap_01` | head | 284 |
| `clothing_jester_bodice_01` | shirt | 136 |
| `clothing_jester_sleeves_01` | arms | 248 |
| `clothing_jester_bloomers_01` | pants | 184 |
| `clothing_jester_boots_01` | shoes | 372 |
| **ครบชุด** | | **1,224** |

Set ID: `outfit_crimson_jester_01`, asset_version 1, fit_profile `chibi-sculpt-v1` รวมชุดไม่เกิน 1,500 tri ไม่รวมตัวฐาน ผม ใบหน้า อาวุธ

## ผ้าและ rig

- ใช้ GameRig 57 จุดเดิม ไม่แก้ skeleton หรือลำดับคลิป
- เสื้อใช้ weight ผสม Hips/Spine/Chest/UpperChest ตามความสูง ลายปักและสายเสื้อมี weight แบบเดียวกัน
- แขนเสื้อทั้งส่วนต้นแขนและท่อนล่างแยกอยู่ใน slot arms มี loops ตรงช่วงพอง และ weight ผสม UpperArm/LowerArm ใกล้ศอก ผลรวมน้ำหนัก 1.0 ต่อ vertex
- กางเกงแยกซ้าย/ขวา ผสม Hips กับ UpperLeg ของข้างนั้น ไม่ผูก mesh ชิ้นเดียวข้ามสองขา
- รองเท้าส่วนหุ้มหน้าแข้งผสม LowerLeg/Foot ตรงข้อเท้า ปลายรองเท้างอนและกระดิ่งตาม Foot กระดิ่งบนหมวกตาม Head ไม่มีกระดูกกระดิ่งสำหรับแกว่งอิสระ
- ผ้าใช้วัสดุไม่มี metallic และใช้ skin deformation จึงพับตาม rig ได้ ยังไม่มี cloth physics, collision อัตโนมัติ หรือการแกว่งผ้ารองด้วยกระดูกใหม่
- หมวกเปิดหน้า ใช้ `hide_head: false`, `hide_hair: false` ผมและใบหน้าเลือกแยกได้ ฟิตกับผมบ๊อบของฐาน ทรงผมสูงมากอาจทะลุหมวก ต้องปรับ fit ของชิ้นนั้น
- ไม่รวมอาวุธ ทรงผมแดง ใบหน้าใหม่ หรือเอฟเฟกต์จากภาพอ้างอิงไว้ใน GLB ชุด

## Source และภาพ

- Builder: `tools/blender/build_studio_jester_outfit.py`
- Assembly: `art/source/characters/chibi_jester_robe_preview.blend`
- Render: `art/characters/chibi-studio/outfit_crimson_jester_preview.png`
- Studio: `tools/image_to_3d/studio-jester-outfit.png`

ใส่ครบใน Studio แล้ว ดูท่ายืนด้านหน้า/หลัง/ข้าง และ Run ยังไม่ได้ตรวจครบทุกคลิป ทุกเฟรม หรือการใช้งานใน Godot

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/blender/build_studio_jester_outfit.py
python3 tools/register_studio_items.py
```

Builder สร้างเฉพาะชุดนี้กับ preview และปฏิเสธการสร้าง ID ที่อยู่ใน Archive กลับมาเอง
