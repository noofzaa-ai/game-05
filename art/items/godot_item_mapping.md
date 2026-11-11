# Stable asset ID → Godot item mapping

## Source of truth

- ID ถาวรอยู่ใน `id` ของ JSON ข้าง GLB ทุกชิ้น
- ทะเบียนสำหรับ Godot: `res://art/items/item_manifest.json`
- ตารางอ่านง่าย: `art/items/item_ids.md`
- Studio แสดง ID ใต้การ์ดและใช้ ID เดียวกันในการเลือก/export
- Manifest ออนไลน์ปัจจุบัน: `http://127.0.0.1:8765/api/studio-items/manifest`

ใช้ string ID ที่สื่อความหมาย ไม่ใช้ลำดับช่องใน UI, index ใน array หรือชื่อแสดงภาษาไทยเป็น key เปลี่ยนชื่อแสดงหรือชื่อไฟล์ได้ แต่ **ห้ามเปลี่ยน ID เดิมหรือใช้ ID ที่ยกเลิกแล้วกับ asset อื่น** อัปเดตงานชิ้นเดิมให้เพิ่ม `asset_version`; งานคนละแบบให้มี ID ใหม่

## ฝั่ง Godot

แยกข้อมูลเกมจากข้อมูล asset เช่น:

```json
{
  "item_id": "starter_blade",
  "asset_id": "weapon_blade_01",
  "damage": 10
}
```

`item_id` เป็นรหัสไอเทม/ข้อมูลเกมฝั่ง Godot ส่วน `asset_id` ใช้ค้นใน manifest ของ Studio ดาบหลายระดับสามารถอ้าง asset เดียวกันได้ ตัวอย่าง manifest:

```json
{
  "id": "weapon_blade_01",
  "category": "weapons",
  "asset_path": "res://art/items/weapons/blade.glb",
  "family": "blade",
  "asset_version": 1,
  "status": "ready"
}
```

คัดลอก `art/items/` ไป project เกมโดยรักษาโครงสร้าง หรือปรับ prefix `asset_path` ใน importer ของฝั่งเกมให้ตรงกับโฟลเดอร์ปลายทาง อย่าใช้ path `/Users/...` เป็น resource path ใน Godot

ตัวอย่าง logic ใน Godot (ยังไม่ผูกกับระบบเกมปัจจุบัน):

```gdscript
var assets_by_id: Dictionary = {}

func load_asset_manifest() -> void:
    var data = JSON.parse_string(FileAccess.get_file_as_string(
        "res://art/items/item_manifest.json"))
    for entry in data["items"]:
        assets_by_id[entry["id"]] = entry

func scene_for_asset(asset_id: String) -> PackedScene:
    var entry: Dictionary = assets_by_id.get(asset_id, {})
    var path: String = entry.get("asset_path", "")
    if entry.get("status", "dummy") != "ready" or not ResourceLoader.exists(path):
        return null # ระบบเกมเลือก dummy ของหมวดนี้แทน
    return load(path) as PackedScene
```

ทรงผมเป็น rigid attachment ที่หัว; ชุดเป็น skinned mesh ต้องใช้ skeleton ตัวละครร่วมกัน; อาวุธใช้จุดจับตาม spec การค้น ID ได้ไม่ได้แทนขั้นตอนติดตั้ง mesh เหล่านี้

## Dummy และการของาน

ตกลง `asset_id` ก่อนเริ่มทำ asset แล้วให้คำของานระบุ ID, หมวด/slot, fit_profile และ reference ฝั่ง Godot เก็บ ID นี้ไว้แม้ไฟล์ยังไม่พร้อม และใช้ dummy เมื่อ ID ไม่อยู่ใน manifest หรือโหลด resource ไม่ได้ เมื่อส่ง asset จริง ให้ JSON ใช้ ID ที่ตกลงไว้และ refresh manifest จึงไม่ต้องเปลี่ยน item/save game ที่อ้างรหัสนั้น

ตอนนี้ manifest รวมไฟล์พร้อมใช้ (`status: ready`) และรายการใน Archive (`status: archived`) ไม่ได้รวมรายการของานที่ยังไม่มี GLB และไม่ได้สร้าง dummy scene ให้ระบบเกมโดยอัตโนมัติ ปุ่มมือเปล่า/ไม่ใส่เป็น state ของช่องอุปกรณ์ ไม่ใช่ asset ID; bald เป็น GLB marker สำหรับถอดผม มี ID ของตัวเอง

## เพิ่ม asset ใหม่

1. วาง GLB และ JSON ชื่อเดียวกันใน hair/weapons/clothing ตามหมวด
2. กำหนด `id` ที่ไม่ซ้ำทั้งคลังใน JSON; ใช้ ID ที่ฝั่ง Godot ของานไว้ หากมี
3. รันจาก project root:

   ```sh
   python3 tools/register_studio_items.py
   ```

   สคริปต์คง ID ที่มีอยู่ เติม ID ให้ชิ้นที่ยังไม่มี และสร้าง manifest/ตารางใหม่ เมื่อมี ID ซ้ำจะรายงานข้อผิดพลาด
4. Refresh Studio และส่งไฟล์ asset พร้อม manifest ให้ฝั่ง Godot

ชื่อเก่าของชุดเริ่มต้นเก็บใน `legacy_ids` เพื่อรองรับตัวเลือก export เก่า ฝั่ง Godot ใหม่ควรใช้ `id` เป็นหลัก

## ปลอกแขนและงบชุด (6 ตุลาคม 2026)

ช่องชุดของ Studio คือ `head`, `shirt`, `arms`, `pants`, `shoes` ให้ระบบเกม map ไอเทมปลอกแขนกับ slot `arms` ซึ่ง GLB หนึ่งชิ้นมีปลอกแขนทั้งซ้ายและขวา เสื้อไม่รวมปลอกแขนแล้วใน asset_version 2

```json
{
  "item_id": "sentinel_bracers",
  "asset_id": "clothing_sentinel_bracers_01",
  "slot": "arms"
}
```

Manifest มี `triangle_count` จาก GLB จริงกับ `set_id` และ `set_triangle_budget` จาก metadata ชุดครบจำกัด 1,500 tri รวมหมวก/ปลอกแขน ไม่รวมตัวฐาน ผม ใบหน้า และอาวุธ ต้องประกอบ skinned mesh กับ Skeleton3D ตัวเดียวกัน การเพิ่มช่องและกติกานี้ใน Studio ไม่ได้เพิ่มระบบสวมปลอกแขนใน Godot ให้อัตโนมัติ
