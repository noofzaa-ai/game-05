# Orchid Gray Orange — ชุดผ้ากล้วยไม้เทาลายส้ม

สีแยกจากชุดผ้ากล้วยไม้เดิม: ผ้าเทาถ่าน ขอบดำ ลายปักส้ม เปลี่ยนเฉพาะสี material Geometry, skin weights, bind matrices และ node transforms คัดลอกจาก GLB สีม่วงชมพูเดิม

Set ID: `outfit_orchid_grayorange_01`; asset_version 1 ทุกชิ้นมี `color_variant_of` ชี้ ID สีต้นทาง

| Asset ID | Slot | Tri |
| --- | --- | ---: |
| `clothing_orchid_grayorange_comb_01` | head | 64 |
| `clothing_orchid_grayorange_bodice_01` | shirt | 279 |
| `clothing_orchid_grayorange_cuffs_01` | arms | 88 |
| `clothing_orchid_grayorange_skirt_01` | pants | 164 |
| `clothing_orchid_grayorange_boots_01` | shoes | 348 |
| **รวม** | | **943** |

GLB+JSON+PNG อยู่ใน `art/items/clothing/` ใช้ ID ใหม่เพื่อเลือกสีแยกใน Studio ไม่เขียนทับสีม่วงชมพูหรือเทาดำ ข้อจำกัดการขยับผ้าใช้ตาม `orchid_silk.md`

- Builder: `tools/blender/build_studio_orchid_grayorange.py`
- Assembly: `art/source/characters/chibi_orchid_grayorange_preview.blend`
- ภาพตัวอย่าง: `art/characters/chibi-studio/outfit_orchid_grayorange_preview.png`

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/blender/build_studio_orchid_grayorange.py
```
