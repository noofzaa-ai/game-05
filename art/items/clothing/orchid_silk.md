# Orchid Silk — ชุดผ้ากล้วยไม้ม่วงชมพู

ชุดผ้าสำหรับ Chibi ดัดแปลงจากภาพอ้างอิงผู้ใช้: ปิ่นดอกไม้ม่วงชมพู เสื้อคอสูงลายปักทอง ผ้าคลุมหลังสั้น ปลอกแขนผ้าบาน ชายผ้าหน้ายาวไม่เท่ากัน และรองเท้าผ้าสูง ใช้ material ไม่เป็นโลหะ ไม่รวมทรงผมหรืออาวุธจากภาพ

## ไฟล์แยกใน art/items/clothing/

ทุก ID มี GLB, JSON และ PNG ชื่อเดียวกัน ระบบ catalog อ่านไฟล์จากโฟลเดอร์นี้โดยตรง

| Asset ID | Slot | Tri |
| --- | --- | ---: |
| `clothing_orchid_comb_01` | head | 64 |
| `clothing_orchid_bodice_01` | shirt | 279 |
| `clothing_orchid_cuffs_01` | arms | 88 |
| `clothing_orchid_skirt_01` | pants | 164 |
| `clothing_orchid_boots_01` | shoes | 348 |
| **รวมครบชุด** | | **943** |

นับจาก GLB จริง ไม่รวมตัวฐาน ผม ใบหน้า และอาวุธ Set ID: `outfit_orchid_silk_01`; asset_version 1; fit_profile `chibi-sculpt-v1` อยู่ในงบชุด 1,500 tri

## การเคลื่อนไหวผ้า

- ใช้ GameRig 57 จุดเดิม ไม่มีการแก้ตัวฐาน skeleton socket หรือคลิป
- เสื้อ ผ้าคลุมหลัง และลายปักที่ติดบนเสื้อใช้ weight ผสม Hips/Spine/Chest/UpperChest ตามระดับความสูง
- แขนเสื้อบานแยกช่อง arms ส่วนบนใกล้ศอกผสม UpperArm/LowerArm ส่วนปลายตาม LowerArm นิ้วเดิมไม่ถูกดึงโดยผ้า
- ชายผ้าแบ่งซ้ายขวา หน้าและหลัง ผูก Hips/UpperLeg/LowerLeg ของข้างตัวเอง ไม่ให้ชิ้นเดียวเชื่อมสองขา
- ลายปักชายผ้าใช้ weight แบบเดียวกับผ้าตามตำแหน่ง
- รองเท้าผ้าส่วนบนตามต้นขา ส่วนล่างตามหน้าแข้ง ผสมช่วงเข่าและข้อเท้าเข้ากับ Foot
- ปิ่นตาม Head; `hide_hair: false`, `hide_head: false` ใช้ผมและหน้าแยกได้ ทรงผมที่สูงหรือกว้างมากอาจต้องปรับ fit ปิ่น
- การขยับผ้าเป็น skin deformation ไม่มี cloth physics หรือ collision อัตโนมัติ แผ่นผ้าอาจชนหรือทะลุในท่ากว้างมาก ต้องเก็บต่อเป็นรายท่า

## Source และภาพ

- Builder: `tools/blender/build_studio_orchid_silk.py`
- Assembly: `art/source/characters/chibi_orchid_armor_preview.blend`
- ภาพยืน: `art/characters/chibi-studio/outfit_orchid_silk_preview.png`
- ภาพจาก Run เฟรม 7: `art/characters/chibi-studio/outfit_orchid_silk_run.png`

ดูรูปทรงท่ายืนและภาพหนึ่งเฟรมจาก Run เดิมใน Blender แล้ว ยังไม่ได้ตรวจทุกเฟรม/ทุกคลิป หรือการใช้งานใน Godot ไม่มีการสลับรายการในหน้า Studio ที่เปิดอยู่ เพื่อคงงานของแชตหลัก

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/blender/build_studio_orchid_silk.py
```

Builder เขียนเฉพาะชิ้นชุดนี้และ preview ไม่สร้างรายการที่อยู่ใน Archive กลับมาเอง
