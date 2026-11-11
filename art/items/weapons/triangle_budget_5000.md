# Weapon triangle budget — 2026-10-06

อาวุธในคลังใช้งานจำกัด **ไม่เกิน 5,000 tri ต่อ GLB หนึ่งเล่ม** มีดที่ใส่สองมือเป็นสอง instance จึงมี tri รวมสองเท่า ตารางนี้นับจาก GLB ที่ publish จริง ไม่รวมตัวละครหรืออุปกรณ์ชุดอื่น

| ID | ชื่อ | Tri ปัจจุบันต่อ GLB | ไฟล์คลัง |
| --- | --- | ---: | --- |
| `weapon_blade_01` | ดาบมือขวา | **4,899** | `blade.glb` |
| `weapon_dagger_01` | มีดคู่ | **4,898** | `dagger.glb` |
| `weapon_spear_01` | หอกมังกรแดง · สองมือ / พาดบ่า | **490** | `spear.glb` |
| `weapon_blade_02` | ซามูไร · ด้ามขาวใบดำ | **4,899** | `weapon_blade_02.glb` |
| `weapon_blade_03` | ซามูไร · ด้ามดำใบดำ | **4,899** | `weapon_blade_03.glb` |
| `weapon_blade_04` | ซามูไร · ด้ามขาวใบเงิน | **4,899** | `weapon_blade_04.glb` |
| `weapon_blade_05` | ซามูไร · ดอกไม้ทอง | **4,899** | `weapon_blade_05.glb` |
| `weapon_blade_06` | ซามูไร · ดอกไม้ทองด้ามขาว | **4,879** | `weapon_blade_06.glb` |
| `weapon_blade_07` | ซามูไร · ด้ามดำใบเงินโค้ง | **458** | `weapon_blade_07.glb` |
| `weapon_dagger_02` | มีดคู่ · เทาขอบเงิน | **4,896** | `weapon_dagger_02.glb` |
| `weapon_dagger_03` | มีดคู่ · เขี้ยวหยก | **4,894** | `weapon_dagger_03.glb` |
| `weapon_dagger_04` | มีดคู่ · กรงเล็บทอง | **4,896** | `weapon_dagger_04.glb` |
| `weapon_dagger_05` | มีดคู่ · เงาเงิน | **4,897** | `weapon_dagger_05.glb` |
| `weapon_dagger_06` | มีดคู่ · เขี้ยวโลหิต | **4,896** | `weapon_dagger_06.glb` |

## ไฟล์ที่ปรับ

ไฟล์คลังใน `art/items/weapons/` และไฟล์คู่กันใน `art/weapons/blade/`, `art/weapons/dagger/`, `art/weapons/chibi/` ลดด้วย geometry เดียวกัน ID, marker, hierarchy, transform, จุดจับ, radius, edge, socket และข้อมูล extras เก็บเดิม ส่วน normal ของผิวที่ลดถูกเฉลี่ยเพื่อให้ลดรอยแยกของ facet ได้ รายละเอียดเล็กและลายเส้นบางอาจหยาบขึ้นจากการลด geometry

`weapon_blade_06` คงรุ่นดอกไม้ทองด้ามขาวที่ 4,879 tri ส่วน `weapon_blade_07` เป็นรุ่นด้ามดำใบเงินโค้ง 458 tri ที่ใช้ geometry low-poly เดิม

## เครื่องมือสำหรับ rebuild ครั้งถัดไป

```sh
node tools/blender/optimize_weapon_glb.mjs input.glb reduced.glb 5000
```

เครื่องมือนี้ทำงานกับ GLB อาวุธ static ที่ใช้สี vertex ปัจจุบัน ไม่ต้องใช้ Blender และไม่ได้สร้าง extension compression ต้องตรวจสำเนาแล้วค่อย publish หลัง rebuild จากตัวสร้างเดิม ต้องรันตัวลดอีกครั้งเพื่อคงงบนี้

## สำรองและตรวจรับ

ต้นฉบับและ manifest SHA-256 อยู่ที่:
`tools/image_to_3d/.cache/weapon_revisions/before_5000_tri_20261006_181907`

`latest_manifest.json` ระบุไฟล์สำรองล่าสุดของแต่ละ path ส่วน `optimization_report.json` ระบุจำนวนก่อน/หลังและ SHA-256 ของผลลัพธ์ ไม่สร้างไอเทมจาก Archive กลับมา

ตรวจจำนวน tri จริง, index/accessor, finite values, bounding box และเปรียบเทียบ JSON ของ node/material/marker ครบทุกไฟล์ใช้งาน 37 GLB รวม placeholder ภาพเปรียบเทียบ representative Blade/Dagger จากหน้า, 45°, ข้างและหลังอยู่ในโฟลเดอร์ `review/` ของสำรอง ยังไม่ได้ตรวจรอบนี้ใน Godot หรือเล่นแอนิเมชันใน Studio


ใบดาบ Blade ปรับขนาดสำหรับอ่านรูปทรงในเกมแล้ว ดู `art/weapons/blade/blade_visual_scale.md`
