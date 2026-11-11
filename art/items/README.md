# Studio item library

Studio สแกน `art/items/hair/*.glb` และ `art/items/weapons/*.glb` รวมถึง `art/items/clothing/*.glb` ผ่าน `/api/studio-items` ทุกครั้งที่เปิดตัวละคร ไม่ต้องเพิ่มรายการใน app.js วางไฟล์ใหม่แล้วรีเฟรชหน้าเว็บ

## ตำแหน่งวางไฟล์บนเครื่องนี้

- ทรงผม: `/Users/user/godot-project/test01/art/items/hair/`
- อาวุธ: `/Users/user/godot-project/test01/art/items/weapons/`
- ชุด: `/Users/user/godot-project/test01/art/items/clothing/`

วางไฟล์ตรงในโฟลเดอร์หมวด ไม่ต้องสร้างโฟลเดอร์ย่อย เช่น:

```text
/Users/user/godot-project/test01/art/items/hair/my_hair.glb
/Users/user/godot-project/test01/art/items/hair/my_hair.json
/Users/user/godot-project/test01/art/items/hair/my_hair.png

/Users/user/godot-project/test01/art/items/weapons/my_blade.glb
/Users/user/godot-project/test01/art/items/weapons/my_blade.json
/Users/user/godot-project/test01/art/items/weapons/my_blade.png
```

PNG ไม่บังคับ หลังเพิ่มไฟล์ให้รีเฟรชหน้า Studio

แต่ละไอเทมมีไฟล์ชื่อเดียวกัน:

- `item.glb`: โมเดลจริง
- `item.json`: ชื่อภาษาไทย จุดติดตั้ง และประเภทท่า
- `item.png`: รูปตัวอย่าง (ไม่บังคับ ถ้าไม่มีเว็บ render จาก GLB)

GLB ที่ไม่มี JSON ยังขึ้นรายการด้วยชื่อไฟล์ แต่ข้อมูลการติดตั้งและชุดท่าควรระบุให้ครบ

## Hair

ตัวอย่าง `hair/crew.json`:

```json
{
  "name": "รองทรงสั้น",
  "socket": "attach_head",
  "fit_profile": "chibi-sculpt-v1",
  "thumbnail": "crew.png"
}
```

หน่วยเมตร, glTF Y-up/+Z ด้านหน้า, origin อยู่ที่ attach_head (ดู hair_spec.md และ hair_head_reference.glb) ผมเป็น rigid mesh ไม่มี armature เว็บติดผมกับ socket และ export จะให้ weight Head 1.0 เพื่อขยับตามหัว

ไฟล์ปัจจุบัน: original, bald, short, crew, sidepart, spiky รวม 6 GLB; bald เป็นไฟล์ marker ไม่มี mesh สำหรับถอดผม

ตัวละคร source ยังเก็บผมเดิมไว้สำหรับงาน Blender แต่เว็บนำผมที่ฝังไว้เดิมออกจาก preview แล้วใช้ GLB ในคลังจริง การ export GLB/.blend ก็อ่าน GLB ที่เลือกจากคลังแทนผมต้นฉบับ

## Weapons

ตัวอย่าง `weapons/blade.json`:

```json
{
  "name": "ดาบมือขวา",
  "family": "blade",
  "hands": ["R"],
  "fit_profile": "chibi-sculpt-v1",
  "clips": ["WalkBlade", "RunBlade", "Run2Blade"]
}
```

- `family: blade` ใช้จุดมือขวาและระบบมุมดาบ
- `family: dagger` ใช้มือซ้าย/ขวาและระบบมุมมีดคู่
- `clips` ระบุคลิปที่มีในตัวละครจริง คลิปที่ไม่มีจะไม่แสดง
- GLB ต้องเตรียม origin, ขนาด และแกนจับตาม weapon_glb.md ตัวในคลังนี้เป็น Chibi adapter แล้ว ไม่ย่อซ้ำตอนโหลด
- เพิ่มดาบอีกเล่มได้ด้วย GLB/JSON ใหม่ที่ใช้ family เดิม โดยไม่แก้รายการเว็บ
- ระบบนี้ไม่ได้สร้าง animation ให้อาวุธชนิดใหม่เอง ปัจจุบันรองรับการติดตั้ง Blade มือขวาและ Dagger คู่; family ใหม่หรือจำนวนมืออื่นต้องเพิ่มตัวติดตั้งและคลิป
- อาวุธเป็น asset แยกสำหรับ Godot ไม่รวม geometry อาวุธใน GLB ตัวละคร; ผมที่เลือกจะรวมในตัวละครที่ export

## Scope

คลังปัจจุบัน fit สำหรับ chibi-studio; การนำเข้าไอเทมต่างสัดส่วนต้องปรับ asset ตาม spec ก่อน ไม่ได้ปรับขนาด/จุดจับให้อัตโนมัติ ใช้ชื่อไฟล์ไม่ซ้ำภายในหมวด โฟลเดอร์สแกนหนึ่งระดับ และไฟล์ PNG thumbnail ต้องอยู่ในหมวดเดียวกัน

สคริปต์ `tools/blender/export_studio_items.py` ใช้เผยแพร่ชุดเริ่มต้นจาก Blender source เท่านั้น หากรันซ้ำจะเขียนทับไอเทมชื่อเดิมในชุดเริ่มต้น อย่ารันเพื่อ refresh รายการเว็บ


## Clothing

ตำแหน่ง: `/Users/user/godot-project/test01/art/items/clothing/`

ชุดเริ่มต้นแยกเป็น `shirt_basic.glb`, `shorts_basic.glb`, `boots_leather.glb` พร้อม JSON ของแต่ละชิ้น เว็บมีช่อง เสื้อ / กางเกง / รองเท้า และปุ่มถอดชุดทั้งหมด เริ่มต้นเป็นหุ่นฐานไม่ใส่ชุด ผมยังเลือกแยกได้

ตัวอย่างข้อมูลข้าง GLB:

```json
{
  "name": "เสื้อเริ่มต้น",
  "slot": "shirt",
  "fit_profile": "chibi-sculpt-v1",
  "skinned": true
}
```

`slot` ใช้ `head`, `shirt`, `arms`, `pants`, `shoes` ชุดต้องเป็น skinned GLB ที่ใช้ชื่อกระดูกและ bind pose ของ GameRig57 ตรงกับ chibi-studio รวมถึงพิกัด/หน่วยเดียวกับตัวฐาน เว็บใช้กระดูกตัวฐานขับ mesh ชุด ไม่เล่น animation จาก rig ของชุดเอง JSON อย่างเดียวไม่สามารถทำ weight ให้ชุดที่ไม่มี skin ได้ หมวกช่อง `head` ใช้น้ำหนัก Head; ตั้ง `hide_hair: true` เพื่อซ่อนทรงผมระหว่างใส่และไม่รวมผมนั้นตอน export ถอดหมวกแล้วผมที่เลือกไว้จะแสดงอีกครั้ง

ฐานใหม่: `art/characters/chibi-studio/chibi_base_animated.glb` และ `art/source/characters/chibi_base_animated.blend` สร้างจาก sculpt source ด้วย `tools/blender/export_studio_clothing.py` ไม่เขียนทับ sculpt source มีเท้าหุ่นเรียบๆ ใต้รองเท้า ชุดที่เลือกจะรวมใน GLB/.blend ที่บันทึก และการถอดรองเท้าจะใช้เท้าฐานแทน

สคริปต์เผยแพร่ชุดเขียนทับเฉพาะชุดเริ่มต้นสามชื่อด้านบนและไฟล์ฐาน อย่ารันเพื่อ refresh รายการเว็บหรือหลังแก้ไอเทมชื่อเดิมเอง

## Asset IDs สำหรับ Godot

ทุกชิ้นมี `id` ถาวรใน JSON แล้ว ดู `item_ids.md` สำหรับตารางครบ และ `item_manifest.json` สำหรับนำเข้า Godot หลักการ dummy/asset_id แยกจาก gameplay item_id อยู่ใน `godot_item_mapping.md` เพิ่มชิ้นใหม่แล้วรัน `python3 tools/register_studio_items.py` เพื่อสร้าง manifest ใหม่ ห้ามเปลี่ยนหรือใช้ซ้ำ ID เดิมเมื่อแก้ asset

## Archive / พักใช้ไอเทม

การ์ดไอเทมมีปุ่ม **เก็บเข้า Archive** และปุ่ม **Archive** ด้านบนเปิดรายการที่พักใช้ กด **นำกลับมาใช้** เพื่อคืนรายการ โดย ID และ asset_version คงเดิม

GLB และ JSON ย้ายไป `/Users/user/godot-project/test01/art/items/_archive/<category>/<asset_id>/` ภาพตัวอย่างสำเนาไว้ด้วย (ต้นทางภาพยังเก็บไว้เพื่อไม่กระทบภาพที่ใช้ร่วมกัน) ทุกการย้าย/คืนอัปเดต item_manifest.json และ item_ids.md อัตโนมัติ ไอเทมที่ Archive มี status `archived` ใน manifest และไม่แสดงในรายการใส่อุปกรณ์ Godot ควรใช้ dummy สำหรับสถานะที่ไม่ใช่ ready

คืนไฟล์ที่มีชื่อชนกันจะหยุดและแจ้งข้อผิดพลาด ไม่เขียนทับไฟล์ปลายทาง ถ้าไอเทมกำลังใส่อยู่ Studio จะถอดชิ้นนั้นหลังเก็บเข้า Archive การคืนจะทำให้เลือกได้อีกครั้ง แต่ไม่ใส่อัตโนมัติ

## Faces / ใบหน้าแยก

ตำแหน่ง `/Users/user/godot-project/test01/art/items/faces/` รองรับ GLB ชุดรายละเอียดตา/คิ้ว/ปากที่ติด attach_head มี ID, thumbnail, Archive และ export เช่นหมวดอื่น ชุดเริ่มต้น 4 สีหน้ากับตัวเลือกหัวเรียบ รายละเอียด contract อยู่ใน `faces/README.md` เป็นสีหน้าคงที่บนหัวเดิม ยังไม่ใช่ระบบเปลี่ยนรูปหัวหรือ facial animation

### งบชุดและปลอกแขน (6 ตุลาคม 2026)

- ชุดอุปกรณ์รวมทุกช่องต้องไม่เกิน **1,500 tri** รวมหมวกและปลอกแขน ไม่รวมตัวฐาน ผม ใบหน้า และอาวุธ
- `arms` คือปลอกแขนคู่ซ้าย/ขวาแยกจากเสื้อ ใช้ LeftLowerArm/RightLowerArm สามารถถอดหรือสลับกับชุดอื่นได้
- Catalog นับ `triangle_count` จาก GLB จริง (cache ตาม mtime/size) ไม่ใช้ค่าที่อาจเก่าใน JSON การเลือกชุดผสมและ API export ปฏิเสธผลรวมเกินงบ
- Manifest มี `set_id`, `triangle_count`, `set_triangle_budget` สำหรับ Godot
- เวอร์ชันชุดเกราะปัจจุบันคือ asset_version 2 รหัสชิ้นเดิมคงเดิม แต่เสื้อไม่รวมปลอกแขนแล้ว ต้องใส่ไอเทม `clothing_<knight|scout|sentinel>_bracers_01` เพิ่มในช่อง arms หากต้องการชุดครบ
