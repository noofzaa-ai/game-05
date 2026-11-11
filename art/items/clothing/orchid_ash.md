# Orchid Ash — ชุดผ้ากล้วยไม้เทาดำ

เวอร์ชันสีเทา–ดำของ `orchid_silk.md` เปลี่ยนเฉพาะ material base color ผ้าเทาถ่าน ขอบดำ และลายปักเทาอ่อน Geometry, index buffer, skin weights, bind matrices และ node transforms คัดลอกจาก GLB ชุดม่วงชมพูเดิม ไม่มีการแก้ skeleton หรือ animation

Set ID: `outfit_orchid_ash_01`; asset_version 1; แต่ละชิ้นมี `color_variant_of` ชี้ ID ของสีเดิม

| Asset ID | Slot | Tri |
| --- | --- | ---: |
| `clothing_orchid_ash_comb_01` | head | 64 |
| `clothing_orchid_ash_bodice_01` | shirt | 279 |
| `clothing_orchid_ash_cuffs_01` | arms | 88 |
| `clothing_orchid_ash_skirt_01` | pants | 164 |
| `clothing_orchid_ash_boots_01` | shoes | 348 |
| **รวม** | | **943** |

ไฟล์ GLB+JSON+PNG ใน `art/items/clothing/` มี ID แยกเพื่อเลือกทั้งสองสีใน Studio ได้ ไม่เขียนทับสีเดิม ข้อจำกัดการขยับผ้าและการ fit ใช้เหมือนชุดต้นทาง

- Builder: `tools/blender/build_studio_orchid_ash.py`
- Assembly: `art/source/characters/chibi_orchid_ash_preview.blend`
- ภาพตัวอย่าง: `art/characters/chibi-studio/outfit_orchid_ash_preview.png`

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/blender/build_studio_orchid_ash.py
```
