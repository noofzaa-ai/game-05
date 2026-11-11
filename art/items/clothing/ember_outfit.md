# Ember Fighter — ชุดนักสู้แดงทอง

ชุดจากภาพอ้างอิงผู้ใช้: เสื้อแดงคอ V แขนสั้น ขอบและเชือกถักทอง ผ้าพันแขนสีขาว กางเกงแดงขาสั้นทรงหลวม และรองเท้าแตะสายฟ้า

## ไฟล์แยก

โฟลเดอร์: `art/items/clothing/` ทุก ID มี GLB, JSON และ PNG ชื่อเดียวกัน พร้อม stable ID สำหรับ mapping ใน Godot

| Asset ID | Slot | Tri |
| --- | --- | ---: |
| `clothing_ember_vest_01` | shirt | 319 |
| `clothing_ember_wraps_01` | arms | 200 |
| `clothing_ember_shorts_01` | pants | 240 |
| `clothing_ember_sandals_01` | shoes | 332 |
| **รวมครบชุด** | | **1,091** |

นับจาก GLB จริง ไม่รวมตัวฐาน ผม ใบหน้า และอาวุธ อยู่ในงบ 1,500 tri Set ID: `outfit_ember_fighter_01`; asset_version 1 ไม่มีไอเทม head ในชุดนี้ ผมแดงและ VFX สายฟ้าในภาพไม่ได้รวมอยู่ใน GLB ชุด

## Rig และการประกอบ

- ใช้ GameRig 57 จุดและ bind pose เดิมของตัวฐาน Chibi ไม่แก้ตัวฐานหรือคลิป
- เสื้อช่วงอกตาม Chest ช่วงเอวตาม Spine แขนเสื้อตาม UpperArm
- ผ้าพันแขนคู่แยกช่อง arms ตาม LowerArm นิ้วมือของตัวฐานยังใช้ท่ากำเดิม
- ส่วนสะโพกกางเกงตาม Hips; ขากางเกงซ้ายขวาผสม Hips กับ UpperLeg ของข้างนั้นช่วงรอยต่อด้านบน ไม่เชื่อม weight ข้ามสองขา
- รองเท้าแตะมีพื้น สาย V สายส้น และ mesh หน้าเท้าเปล่าอยู่ใน shoes ตาม Foot เมื่อใส่ Studio จะซ่อน Base foot เดิม จึงยังเห็นเท้าในรองเท้าแตะได้ ตัวเลข 332 tri รวมหน้าเท้าของรองเท้าแล้ว
- ผิวเท้าและแผงคอใช้ material ของตัวฐานปัจจุบัน หากเปลี่ยนสีผิวฐานในอนาคตต้องส่งสีไปยังส่วนผิวในไอเทมนี้ด้วย
- ใช้ material สีและ geometry สำหรับลาย ไม่มี cloth simulation หรือ collision อัตโนมัติ

## Source และภาพ

- Builder: `tools/blender/build_studio_ember_outfit.py`
- Assembly: `art/source/characters/chibi_ember_armor_preview.blend`
- Render: `art/characters/chibi-studio/outfit_ember_fighter_preview.png`
- Studio screenshot: `tools/image_to_3d/studio-ember-outfit.png`

ใส่ครบใน Studio และดูท่ายืนกับ Run แล้ว ยังไม่ได้ตรวจครบทุกคลิป/ทุกเฟรม หรือการใช้งานใน Godot

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/blender/build_studio_ember_outfit.py
python3 tools/register_studio_items.py
```

Builder เขียนเฉพาะชุดนี้และ preview ไม่สร้างรายการที่อยู่ใน Archive กลับมาเอง
