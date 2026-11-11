# กติกาสร้างสกิลอาวุธ / Ultimate

## ข้อกำหนดที่ต้องทำตาม

1. ผูกสกิลกับ **weapon type** (`blade`, `dagger`, `spear`, `hammer`) ไม่ผูกกับไอเทมชิ้นใด ใช้ ID ถาวรของสกิลแยกจาก ID อาวุธ
2. **Ultimate ทุกชุดโจมตีไปข้างหน้า ระยะ 2 ช่วงตัวเสมอ**: 1 ช่วงตัว = ความสูงขณะยืนจากเท้าถึงศีรษะ ไม่รวมผม/หมวก/อาวุธ เก็บทั้งตัวคูณและความสูงอ้างอิงใน config ไม่เดาระยะจากความยาวดาบ
3. ตัวละครออกท่าอยู่กับที่ ส่วนคลื่นโจมตี/เอฟเฟคเคลื่อนไปข้างหน้า ไม่ bake root ให้พุ่งไป 2 ช่วงตัวซ้ำอีกครั้ง
4. ยึดทิศที่ตัวละครหัน **ตอนเริ่มใช้สกิล** แล้วล็อกจนจบ ห้ามตามกล้องหรือหมุนคลื่นตามตัวระหว่างฟัน
5. เปลว/สะเก็ดต้องมีการปลิวและลากหางไปตามการเคลื่อนที่ จังหวะปล่อยและถึงเป้าต้องตรงท่าฟัน เอฟเฟคตกแต่งรอบมือได้ แต่พื้นที่โจมตีหลักต้องอยู่ด้านหน้า
6. แยก **animation ตัวละคร / VFX / config / gameplay damage** ออกจากกัน สลับ pack หรืออาวุธได้โดยไม่ปั้น rig ใหม่ ไม่เขียนทับ production character หรือคลิปเดิม

## โครงไฟล์

```text
art/skills/ultimate_defaults.json          # กติกากลาง ห้ามเปลี่ยนเป็นโจมตีรอบตัว
art/skills/shared/weapon_skill_pack.gd     # Resource ของทุก pack
art/skills/shared/weapon_skill_controller.gd
art/skills/<weapon_type>/<skill_name>/
  skill.json
  motion.glb / motion.blend
  vfx.glb / vfx.blend
  <skill_name>.tres
  README.md / preview.mp4 / skill_pack.zip
```

Builder และ catalog ใช้ `tools/image_to_3d/web/skill_contract.py` เป็น validator กลาง Ultimate ที่ขาด config หรือไม่ตรงกติกาจะไม่ปรากฏเป็นสกิลที่ใช้ได้ใน Studio

## Config และแกนพิกัด

`skill.json` ต้องมี `id`, `weapon_type`, `slot: "ultimate"`, `rig_profile`, `animation`, `duration_s`, `in_place: true`, `attack`, `flight`, `gameplay_events` ค่า `attack` สร้างด้วย `ultimate_attack(reference_body_height_m)` แล้วเรียก `validate_skill_contract(manifest)` ก่อน publish

| ค่า | ความหมาย |
| --- | --- |
| `attack.direction = "forward"` | โจมตีด้านหน้า |
| `asset_forward_axis = [0,0,1]` | หน้าของ asset เป็น **glTF +Z** / Blender **-Y**; up เป็น glTF +Y / Blender +Z |
| `lock_direction_on_cast = true` | ล็อกทิศตั้งแต่เริ่มใช้ |
| `range_body_lengths = 2.0` | ระยะบังคับของอัลติทุกชุด |
| `reference_body_height_m` | ความสูงตัวฐานที่วัดจริง ไม่รวมอุปกรณ์ |
| `range_m` | `2 × reference_body_height_m` |
| `caster_motion = "in_place"` | ตัวไม่วิ่งตามคลื่น |
| `hit_shape = "forward_box"` | กล่องตรวจโจมตีด้านหน้า |
| `near_body_lengths = .05` | เริ่มกล่องข้างหน้าจุดยืน ไม่ล้ำไปด้านหลัง |
| `width_body_lengths = 1.1` / `height_body_lengths = 1.0` | ความกว้าง/สูงของ corridor |
| `max_hits_per_target_per_cast = 1` | ศัตรูเดียวรับได้ครั้งเดียวต่อการใช้สกิล |
| `vfx_space = "frozen_cast_origin"` | จุดเริ่มเอฟเฟคล็อกไว้ที่จุดใช้สกิล |
| `vfx_motion = "authored_in_glb"` | GLB มีการบินอยู่แล้ว **Godot ห้ามเลื่อน VFX root ไปข้างหน้าซ้ำ** |
| `damage_owner = "game"` | เกมกำหนดค่า damage/team/health/cooldown |

Godot มี convention ทิศ forward ของกล้อง/Node ต่างจากหน้าโมเดลได้ โปรเจกต์นี้กำหนดหน้า asset +Z ชัดเจน ให้ใช้ `facing_source.global_basis * Vector3(0,0,1)` หรือส่งเวกเตอร์ทิศที่ตัวละครหันจริงให้ `cast_ultimate()` ไม่แทนด้วย `Vector3.FORWARD` โดยไม่แปลงแกน ดู [Godot Vector3](https://docs.godotengine.org/en/stable/classes/class_vector3.html)

`flight` ระบุ `release_time_s`, `arrival_time_s`, `center_start_body_lengths`, `center_end_body_lengths`, `front_extent_body_lengths`, `ease: "smoothstep"` โดย **center_end + front_extent = 2** ให้หัวคลื่นถึงระยะที่ config บอก ไม่ทำให้ทั้ง effect root บินแล้วบวก motion ซ้ำ

`gameplay_events` เรียงตามเวลา แต่ละรายการมี `time_s`, `name`, `range_factor` ช่วง `(0,1]` ตัวอย่างไฟดาบ: `slash_hit` 1.04 s ใช้ระยะครึ่งหนึ่ง, `ultimate_burst` 1.91 s ใช้เต็ม 2 ช่วงตัว ตัวคูณนี้คือระยะ ณ จังหวะโจมตี ไม่ใช่ตัวคูณดาเมจ

## ทำ pack ใหม่ตามลำดับนี้

1. อ่าน `weapon_glb.md` และ script/README ของ pack ใกล้เคียง อ่าน marker จริง (`grip_main`, `grip_secondary`, `trail_start`, `trail_end`, `effect_point`) รักษา config/scales ของอาวุธ ห้ามเดาหรือเลื่อนจุดมือ
2. ใช้ rig production ปัจจุบันเป็นต้นทางอ่านอย่างเดียว สร้าง derivative ในโฟลเดอร์ skill; สำหรับ Chibi คือ `chibi_base_animated.blend` / 57 กระดูก อย่ารัน rig builder รุ่นเก่าทับไฟล์ production
3. วัดความสูงด้วย evaluated mesh ของตัว/เท้า/ศีรษะในท่ายืน สำหรับ Chibi ปัจจุบันคือ `Body continuous`, `Base foot.L/R`, `Face` ไม่รวมผมและชุด
4. ทำท่าชาร์จ → ฟัน/ปล่อยด้านหน้า → รับแรง → คืนสมดุล ใช้ข้อมือธรรมชาติ รักษาท่ากำตามรัศมีด้าม ไม่บิดแขนเพื่อชดเชยทิศใบอาวุธ และไม่หมุนตัวโจมตีรอบทิศ 360°
5. Export `motion.glb` เป็น carrier คลิปแยกบน rig เดิม ตัวฐานในไฟล์เป็น reference; runtime โหลดเฉพาะ animation library ไม่เพิ่มตัวละคร reference ลงฉาก
6. ทำ VFX ไป glTF +Z จาก origin ระยะคำนวณจาก config มีหางปลิว/สะเก็ดไหล ไม่วางวงใหญ่ค้างล้อมตัวผู้ใช้ เอฟเฟคพื้น/ระเบิดเกิดที่ด้านหน้า
7. Export `vfx.glb` **คลิปเดียว** รวมทุกชิ้น เริ่ม 0 s เวลาตรง motion; Blender ใช้ `export_anim_scene_split_object=False`, `export_anim_slide_to_zero=True` ไม่แยกชิ้นเป็นคนละคลิป
8. เขียน `skill.json` / `.tres` อ้าง shared Resource และ `manifest_path` ของ pack ใหม่ เก็บ ID ถาวร ระบุ asset version เมื่อแก้ motion/config
9. ปัจจุบันตั้งงบ VFX ของ pack ≤1,500 tri แยกจากงบอาวุธ/ชุด/ตัว ไม่เพิ่ม geometry ของอาวุธเพื่อทำเอฟเฟค และรักษาขีดจำกัดของไอเทมแต่ละชนิดเดิม
10. Render ตัวอย่างด้วยอาวุธจริง ให้เห็นทั้งตัวผู้ใช้และระยะด้านหน้าอย่างน้อยภาพข้าง/สามส่วนกับคลิปทั้งท่า ทำ README และ ZIP รวม shared runtime, defaults, `skill.md`, GLB, config และ preview

## Godot หยิบไปใช้

- วางไฟล์ใน path `res://art/skills/...` ตาม ZIP ให้ Godot import GLB ตามปกติ
- ใส่ Node ที่ใช้ `art/skills/shared/weapon_skill_controller.gd` เป็นลูกของตัวละคร ตั้ง `character_root`, `facing_source` (โมเดลที่หันจริง), `skeleton`, `animator`, `return_animation`; origin ของ asset อยู่จุดเท้าระดับพื้น ถ้า actor ใช้ pivot อื่นให้ตั้ง `cast_origin_source` เป็น Node จุดพื้นของตัวละคร
- `body_height_override_m = 0` ใช้ความสูงอ้างอิง × scale Y ของ visual root; ถ้าเกมใช้ตัวอื่นที่ retarget แล้ว ให้ส่งความสูงจริงหน่วยเมตรผ่าน override และตรวจว่า geometry VFX สเกลตามนั้น
- `target_collision_mask` ให้ตรง collision layer ของฝ่ายที่โจมตีได้ และตั้ง `self_collision_root` เป็น actor root เพื่อ exclude collider ของผู้ใช้ทั้งหมด
- `equip_skill(pack)` ตรวจ type และกติกากลาง `equip_skill(null)` ถอด; `set_weapon_type()` ถอดสกิลที่ชนิดไม่ตรง

```gdscript
controller.set_weapon_type(&"blade")
controller.equip_skill(load("res://art/skills/blade/inferno_ultimate/blade_inferno_ultimate.tres"))
controller.cast_ultimate() # อ่านหน้า +Z ของ facing_source และล็อกตั้งแต่ตอนนี้
```

เมื่อถึง hit event controller ส่ง `attack_requested(skill_id, event_name, context)` ใน physics tick โดย context มี `origin`, `forward`, `range_m`, `full_range_m`, `box_size_m`, `query_transform` เกมใช้ `controller.query_forward_targets(context)` เพื่อขอ collision candidates ด้านหน้าได้ จากนั้นตรวจฝ่าย/สิ่งกีดขวาง/เป้าหมายจริงและทำ damage ตามเกม

ให้ resolve collider/หลาย hurtbox เป็น receiver คนเดียว ตรวจ `can_hit_target(receiver)` ก่อนทำดาเมจ แล้ว `mark_target_hit(receiver)` หลัง hit ได้รับการยอมรับ เพื่อไม่โดนซ้ำจากสอง hit event ตัว helper ใช้ [Godot intersect_shape](https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate3d.html#class-physicsdirectspacestate3d-method-intersect-shape); ไม่ใช้ `motion` ของ query มาทำให้กล่องเดิน เพราะ API นี้ไม่ sweep กล่องด้วยค่านั้น

ถ้า player ใช้ script pose ต้องพัก script ระหว่าง animation สกิลเพื่อไม่แย่งกระดูก rig อื่นต้อง retarget ก่อน Motion/ไฟไม่ใช่ระบบค่า damage, ทีม, cooldown หรือการเคลื่อน CharacterBody3D

## ตัวอย่างปัจจุบัน

`blade_inferno_ultimate` v2: type `blade`, 3.2 s, ตัวสูง 1.506733 m → ระยะ 3.013467 m, หัวคลื่นไปด้านหน้า 2 ช่วงตัว, VFX 1,268 tri ดู `art/skills/blade/inferno_ultimate/README.md`

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/blender/build_blade_inferno_skill.py
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/blender/render_blade_inferno_skill.py -- --movie
```

ภาพ/คลิป native เป็นหลักฐานภาพที่สร้างจริง อย่าอ้างว่าเล่นใน browser/Godot หรือระบบดาเมจผ่านแล้วหากยังไม่ได้ทำ ผู้ใช้ยังไม่ได้ขอทดสอบ จึงไม่เพิ่ม/รัน tests โดยอัตโนมัติ
