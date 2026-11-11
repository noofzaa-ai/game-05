# Reviewed sculpt in Character Studio

Open: http://127.0.0.1:8765/?studio=character&variant=chibi-studio

- Source shape: `art/source/characters/chibi_sculpt.blend`, preserved in static A-pose.
- Animated source: `art/source/characters/chibi_sculpt_animated.blend`.
- Runtime asset: `art/characters/chibi-studio/chibi_sculpt_animated.glb`.
- Generator: `tools/blender/rig_chibi_sculpt.py`, run with Blender from the project root.
- 5,291 triangles, 26 mesh objects (with articulated hands), the 57-joint manifest names and hierarchy.
- In-place clips: Walk/Run/Run2 plus WalkBlade/RunBlade/Run2Blade and
  WalkDagger/RunDagger/Run2Dagger, at 60 FPS.
- Studio can play each clip, show bones, reset to A-pose, and download all or a
  selected subset as GLB/Blend. Blade and dual Dagger use separate weapon assets
  with the Studio angle controls. Jump/hit clips are still hidden on this variant.

Binding uses an inverse blended skin matrix to preserve the approved A-pose
while keeping T-pose bind axes compatible with the existing motion generator.
Skin is assigned using anatomy regions and joint transition bands: clothing
never receives hand weights, all head parts follow Head, boots follow Foot.
The production articulated hand topology and its finger chains are fitted to
the smaller wrists at 0.8 scale. Blade/Dagger weapon assets use a matching 0.8
root wrapper around grip origin, preserving all source markers. Dagger fingers
are fitted across the complete cycle with stable proximal bend/spread and
intermediate curls while the
wrist and weapon marker stay unchanged.

Run2 uses reduced ankle recovery, foot guides and hip bounce for the compact
sculpt. All three clips use sampled linear keys and consistent quaternion
signs. Exported loop endpoints are identical across all channels. This is an
initial skin/motion review, not a final combat or gameplay controller setup;
contact foot IK is not authored and locomotion is in place.

Validation: matching 57 joint names, exported triangle count, three named
clips, A-pose reconstruction maximum vertex error below 0.000001 m, identical
GLB loop endpoints, render review at four running phases and sprint, live
Studio play/stop/bone controls and selected-clip download.

## Body volume revision

The torso was widened roughly 17–27% through chest/waist, and given roughly
27–35% more depth through chest/abdomen, with a smaller change at shoulders.
Shorts follow the fuller hips. Static sculpt and animated derivative were
rebuilt together; topology remains 4,475 triangles. Previous slim source and
GLB are in `tools/image_to_3d/.cache/sculpt_revisions/slim_before_body_volume/`.

Rear head revision: +22% depth behind the head side plane on Face, Hair crown
and Bob rear shell. Front face/fringe positions are retained. Exported torso,
clothing, hand and boot positions were checked against the previous version
and are identical.

## Shoulder / hip / equipment revision

Shoulder pivot moved to the authored arm root; torso-side arm influence fades
according to the fuller body boundary. Shirt straps follow UpperChest instead
of Neck. Hip/thigh weights transition over a wider band and keep the central
crotch on Hips. The three overlapping shorts shells are voxel-unioned before
skinning; validation confirms one connected garment surface.

The right arm uses a 79.2 degree drop from T-pose in this variant, adding
outward clearance compared with the prior 84.6–90 degree drop.

Chibi weapons: `art/weapons/chibi/blade_chibi.glb` and `dagger_chibi.glb`.
Builder: `tools/blender/prepare_chibi_weapons.py`. Effective grip radii are
0.01924 m for Blade and 0.00872 m for Dagger. Equipment review script:
`tools/blender/review_chibi_equipment.py`. Blender review must rotate imported
asset coordinates from Blender Z-up back into socket-local glTF axes before
mounting; the production GLBs keep the original marker axes unchanged.


## Modular hair (2026-10-06)

Studio มีเมนูทรงผม: `original` บ๊อบเดิม, `bald` ถอดผม, `short` ผมสั้นปัดหน้า ชิ้นผมเดิมทั้ง 11 ชิ้นถูกติด tag `studio_hair_style=original` โดยไม่แก้ vertex/weight/transform ผมสั้นเป็น mesh ใหม่ที่ skin กับ Head และใช้ clay สีเข้มขึ้นเล็กน้อย; Face เดิมเป็นหัวปิดครบสำหรับหัวโล้น

- Preview GLB รวมตัวเลือกผมไว้พร้อม extras เพื่อสลับการแสดงผลในเว็บ แต่ดาวน์โหลดผ่าน Studio ใช้ `hair` query และ exporter ตัดทรงที่ไม่ได้เลือกออกจริง ทั้ง GLB/.blend
- จำนวนตัวละครที่แสดง: เดิม 5,291 tri / 26 meshes; หัวโล้น 4,611 tri / 15 meshes; ผมสั้น 4,909 tri / 16 meshes (อาวุธแยกไม่นับรวม)
- `tools/blender/chibi_hair.py` สร้างโมดูล; `prepare_chibi_hair.py` อัปเดต source rig เดิมโดยคง animation และเก็บ backup ก่อนแก้ไว้ใน `.cache/sculpt_revisions/before_modular_hair`
- `rig_chibi_sculpt.py` เรียก prepare_hair เมื่อสร้างใหม่ด้วย จึงไม่สูญเสียเมนูผมในรอบสร้างถัดไป
- อย่านำ preview GLB ที่รวมทั้งสองทรงเข้า Godot โดยตรง ควรใช้ปุ่มบันทึกใน Studio หรือไฟล์ `chibi_short_hair.glb` ที่เลือกทรงแล้ว

### ผมเด็กผู้ชายเพิ่มเติม

ตัวเลือกเพิ่ม `crew` รองทรงสั้นแนบหัว, `sidepart` ผมแสกข้างปัดเฉียง, `spiky` ผมสั้นตั้งพร้อมปอยด้านบน แต่ละแบบเป็น mesh แยก 1 ชิ้น skin กับ Head และ tagged `studio_hair_style` เพื่อให้ viewer ซ่อนทุกทรงที่ไม่ได้เลือก Export API และ CLI `--hair` รองรับทั้งสามค่า โดยตัดทรงอื่นออกจากไฟล์ดาวน์โหลดจริง ทรงบ๊อบเดิมยังคง geometry/weight เดิม


### ท่ายืนกลาง (2026-10-06)

ท่าตอนหยุดเปลี่ยนเป็นยืนสมดุลสองข้าง: กางต้นขาออกข้างละประมาณ 3.15 องศา เท้าชดเชยเพื่อวางราบ และลดแขนลงข้างตัวที่ 75.6 องศาจากแนวนอน ใช้ `chibi_stance.set_studio_stance` เก็บ pose ใน extras `studio_a_pose` เดิมเพื่อให้ viewer ใช้ตอนหยุด ไม่แก้ bind skeleton, skin weights หรือคลิปเคลื่อนไหว การเล่นใน Godot ยังใช้คลิป animation ที่ export ตามปกติ


### เสื้อทรงตรงและขาหนาขึ้น (2026-10-06)

เปลี่ยนเสื้อให้ช่วงเอวตรงขึ้น ลดชายบาน และยกคอกลางสูงขึ้น ขาเพิ่มความหนาสูงสุดประมาณ 10% โดยไล่ลดลงที่โคนขา/ข้อเท้าเพื่อคงรอยต่อ เดิมเป็นเสื้อไม่มีแขนและยังคงประเภทนี้ ไม่เปลี่ยนความยาวขา กระดูก หรือคลิป ใช้ `chibi_body_fit.py` ร่วมกับ builder; `refine_chibi_body_fit.py` อัปเดต static/animated sources โดยไม่สร้างคลิปใหม่ เก็บ source ก่อนแก้ใน `.cache/sculpt_revisions/before_straight_shirt`


### รองเท้าหนังหัวมนหุ้มข้อ (2026-10-06)

`chibi_shoes.py` เปลี่ยน Boot.L/R เป็นปลายมนด้วยหน้าตัดปลายหลายระดับ ใช้หนังสีน้ำตาลและพื้นหนังสีเข้ม คงจุดยึด Foot เดิมและความสูงหุ้มข้อประมาณ 0.188 m สร้างทั้ง static/animated และ integrate ใน builder สำรองไฟล์ก่อนแก้ไว้ที่ `.cache/sculpt_revisions/before_leather_shoes`


### Chelsea boot reference revision (2026-10-06)

อ้างอิงภาพรองเท้าหนังดำ Chelsea: ปลายมน พื้นสีน้ำตาลเข้มหนาขึ้น แผ่นยืดสองด้าน หูดึงหลัง และรอยเย็บสีทองแบบ low-poly ผูก Foot เดิม Source สำรองก่อนแก้ใน `.cache/sculpt_revisions/before_chelsea_shoes` ใช้ `chibi_shoes.py` version marker `chelsea_boots_v2` ไม่ใช้ texture/logotype จากภาพ
