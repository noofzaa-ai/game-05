# Modular Chibi faces

## ใบหน้าแบบนูนปัจจุบัน

ใบหน้าที่ใช้งาน 12 แบบปรับเป็น geometry นูนแล้ว และคุม **ไม่เกิน 250 tri ต่อหน้า**
ใช้ ID / `attach_head` เดิม รายช่องและคู่มือ rebuild อยู่ที่
`art/source/faces/relief/README.md`; ภาพรวมคือ `faces_relief_grid.png` ในโฟลเดอร์เดียวกัน

Builder ปัจจุบัน: `tools/blender/build_studio_faces_relief.py`
และ `tools/blender/build_face_bright_blue.py` สำหรับตาฟ้า
อย่าใช้ `build_studio_faces.py` รุ่นพื้นผิวแบนเพื่อ refresh คลังแบบนูน
ไอเทมใน Archive และหัวทรงพิเศษไม่ถูกคืนกลับหรือเปลี่ยนในงานนี้

วางไฟล์ที่ `/Users/user/godot-project/test01/art/items/faces/`

ชุดแรกมี 4 GLB และ JSON/PNG ชื่อเดียวกัน:

- `face_neutral_01`: ปกติ ใช้รายละเอียดหน้าของ sculpt เดิม
- `face_smile_01`: ตาปิดยิ้ม ปากยิ้มเห็นฟัน
- `face_annoyed_01`: หงุดหงิด ตาครึ่งปิดและปากคว่ำ
- `face_playful_01`: ตากลมมีประกาย แลบลิ้น

ตัวเลือกหัวเรียบไม่ใส่ใบหน้าเป็น state ไม่ใช่ไอเทม

## Contract

หมวด `faces` เป็นชุดรายละเอียดหน้ารวมชิ้นเดียว ไม่รวมผิวหัวฐานและผม ตอนนี้เปลี่ยนทั้งชุดตา คิ้ว ปาก ไม่ได้แยกเลือกตา/ปากคนละไอเทม และเป็นสีหน้าคงที่ ไม่มี facial animation หรือ lip sync

- หน่วยเมตร glTF Y-up ด้านหน้า +Z
- `socket: attach_head`
- `attachment_mode: rigid`
- `fit_profile: chibi-sculpt-v1`
- origin/พิกัดร่วมกับ hair_head_reference.glb และผมในคลัง
- ไม่มี skeleton ของตัวเอง หน้าเคลื่อนตามกระดูกหัว
- geometry รายละเอียดเกาะผิวหัวเดิม ไม่ใช้ plane แบนกว้างที่ลอยนอกหัว
- ไฟล์ภายนอกต้องทำให้พอดีกับหัวอ้างอิงนี้ก่อน ระบบไม่ได้ wrap ใบหน้าให้หัวรูปทรงอื่นอัตโนมัติ

ตัวอย่าง JSON:

```json
{
  "id": "face_smile_01",
  "name": "ยิ้ม",
  "asset_version": 1,
  "socket": "attach_head",
  "attachment_mode": "rigid",
  "fit_profile": "chibi-sculpt-v1",
  "thumbnail": "face_smile_01.png"
}
```

ใช้ `python3 tools/register_studio_items.py` อัปเดต manifest หลังเพิ่มไอเทม ห้ามใช้ ID ซ้ำ ชุดหน้าเลือกแล้วรวมกับตัวละครเมื่อบันทึก GLB/.blend หรือใช้ GLB แยกติด attach_head ใน Godot ตาม asset_id ได้ Archive/Restore รักษา ID เหมือนไอเทมหมวดอื่น

สคริปต์ต้นทาง `tools/blender/build_studio_faces.py` สร้างชุดเริ่มต้นและ thumbnail จากหัวจริง ไม่แก้ sculpt source; รันซ้ำเขียนทับสี่ asset เดิม อย่ารันเพื่อ refresh Studio

## ครบทุกช่องที่เห็นในภาพอ้างอิง

| ช่องในภาพ | Asset ID |
| --- | --- |
| Woman Face | `face_soft_smile_01` |
| Devious Smile | `face_devious_01` |
| Err… | `face_err_01` |
| Smooth Brain Head | `head_smooth_brain_01` |
| Animated Annoyed Chibi | `face_annoyed_01` |
| Short Hair Head | `head_short_hair_01` |
| Tattletale Eyebrow Slit | `face_shout_01` |
| Prankster | `face_prankster_01` |
| Black Anime Chibi Eyes | `face_anime_bored_01` |
| หน้ากังวล/เศร้า แถวล่างซ้าย | `face_sad_01` |
| หัวแบน แถวล่างกลาง | `head_flat_01` |
| ยิ้มเขี้ยวแลบลิ้น แถวล่างขวา | `face_vampire_01` |

รวมใบหน้า/หัว 15 แบบเมื่อรวมปกติ ยิ้ม และขี้เล่นชุดแรก (รายการที่ผู้ใช้ Archive ไว้ไม่แสดงในคลังใช้งาน)

หัวทรงพิเศษสามชิ้นมี `replaces_head: true` และ `hide_hair: true`: แทนผิวหัวฐาน และพักการแสดงผมที่เลือกไว้ เพื่อไม่ให้ผมเดิมครอบหัวทรงใหม่ สลับกลับใบหน้าปกติจะได้หัวและผมเดิมคืน การ export และ Godot manifest เก็บ flags เหล่านี้ด้วย ยังเป็นสีหน้าคงที่ ไม่มี facial animation

สคริปต์สร้างชุดจะข้ามไอเทมที่อยู่ใน Archive เพื่อไม่สร้าง ID ซ้ำหรือคืนไอเทมที่ผู้ใช้พักไว้
