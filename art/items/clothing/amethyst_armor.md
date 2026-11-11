# ชุดเกราะอเมทิสต์

ชุดเกราะม่วงอ่อนและทองตามภาพอ้างอิง: หมวกปิดหน้า หงอนทอง ไหล่แหลม ปลอกแขนใหญ่ เกราะเข่าและรองเท้าปลายแหลม

- Set ID: `armor_amethyst_lancer_01`
- Fit profile: `chibi-sculpt-v1`; ใช้กระดูก GameRig ของตัวละคร Chibi ปัจจุบัน
- ทั้งชุด **1,110 tri** จาก GLB จริง; งบไม่เกิน 1,500 tri ไม่รวมตัวฐาน ผม หน้า และอาวุธ
- แต่ละไอเทมมี `.glb`, `.json`, `.png` ในโฟลเดอร์นี้ Studio สแกนไฟล์โดยตรง; รีโหลดหน้าเพื่อแสดงรายการใหม่
- หมวกปิดหน้าใช้ `hide_head` และ `hide_hair`; ถอดหมวกแล้ว Studio แสดงหัวและทรงผมที่เลือกคืน
- ไม่เปลี่ยนตัวฐาน โครงกระดูก หรือคลิปการเคลื่อนไหว

| ช่อง | ID ถาวร / ชื่อไฟล์ | Tri |
| --- | --- | ---: |
| head | `clothing_amethyst_helmet_01` | 320 |
| shirt | `clothing_amethyst_cuirass_01` | 164 |
| arms | `clothing_amethyst_bracers_01` | 152 |
| pants | `clothing_amethyst_tassets_01` | 126 |
| shoes | `clothing_amethyst_sabatons_01` | 348 |

Godot path ใช้ `res://art/items/clothing/<ID>.glb` และ map ด้วย ID ใน JSON ของแต่ละชิ้น

## การเคลื่อนไหว

แผ่นเกราะแต่ละส่วนผูกกับกระดูกเดียว ปลอกแขนกับแผ่นหุ้มมือใช้ LowerArm และ Hand ตามลำดับ แผ่นสะโพกแยกซ้าย/ขวาตาม UpperLeg; เกราะหน้าแข้งตาม LowerLeg และรองเท้าตาม Foot จึงไม่มีแผ่นเดียวพาดขาทั้งสองข้าง ไม่ใช้ cloth simulation การชนกับร่างกายหรืออาวุธยังต้องดูในท่าเล่นจริง

## แหล่งสร้าง

- Builder: `tools/blender/build_studio_amethyst_armor.py`
- Source assembly: `art/source/characters/chibi_amethyst_armor_preview.blend`
- ภาพทั้งชุด: `art/characters/chibi-studio/armor_amethyst_lancer_preview.png`

สร้างซ้ำจากรากโปรเจกต์:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/blender/build_studio_amethyst_armor.py
```

คำสั่งเขียนทับเฉพาะไฟล์ของชุดอเมทิสต์ รักษา ID เดิมและหยุดเมื่อชุดเกินงบหรือพบไอเทมนี้ใน Archive
