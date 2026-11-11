# Main character replacement prompt

Measured 2026-10-20 from the live default `client/character_model.gd::MODEL_PATH`: `art/characters/chibi-studio/chibi_base_animated.glb`. Measurements describe this specific asset, not the generic 1.8m skeleton manifest. No asset or deployment changed.

## Measurements (source metres)

Source visible bounds: minimum(-0.6316,0.015,-0.25412), size(1.2632,1.596,0.46812). These bounds include outstretched hands and selected hair, not weapons/clothing. Game preview/gameplay normalization scales this base by1.1278195 and offsets source sole Y0.015 to the actor origin, producing1.8m total height.

- Total height including selected hair:1.596m
- Head/face mesh dimensions: width0.316m, height0.358m, depth0.29386m (not including hair).
- Shoulder joint separation:0.322m.
- Upper arm shoulder-to-elbow:0.133m per side.
- Forearm elbow-to-wrist:0.192m per side.
- Wrist-to-outermost fingertip extent in T-pose: approximately0.1456m.
- Upper-leg joint separation:0.1512m.
- Thigh hip-to-knee: approximately0.28909m.
- Shin knee-to-ankle:0.287m.
- Hip joint to source sole plane:0.699m.
- Hips central joint to neck joint:0.378m.
- Bare left foot mesh bounds: width0.068m, height0.170m, depth0.142m. This includes the ankle section, not just the sole.

Joint origins in source glTF coordinates (+Y up, +Z front; X follows supplied skeleton):

| Joint | X | Y | Z |
| --- | --- | --- | --- |
| Hips |0|0.728|0|
| Spine |0|0.825|0|
| Chest |0|0.954|0|
| Neck |0|1.106|0|
| Head |0|1.153|0|
| LeftShoulder |0.078|1.064|0|
| LeftUpperArm |0.161|1.064|0|
| LeftLowerArm |0.294|1.064|0|
| LeftHand |0.486|1.064|0|
| LeftUpperLeg |0.0756|0.714|0|
| LeftLowerLeg |0.0828|0.425|0|
| LeftFoot |0.0828|0.138|0|
| LeftToes |0.0828|0.1035|0.1105|
| attach_weapon.L |0.558|1.064|0|
| attach_weapon.R |-0.558|1.064|0|

The corresponding right limb rest origins mirror X, but do not infer bone rolls/rotations from this table. Copy exact matrices from the supplied GLB.

## Prompt to copy

Create a production-ready stylized low-poly chibi main character for an existing Godot 4 game, using the supplied `chibi_base_animated.glb` as the mandatory technical template. This is a replacement mesh on the existing rig, not a newly auto-rigged character.

VISUAL STYLE
- Friendly chibi adventurer; large softly rounded head, gentle cheeks and rounded chin, slender readable torso, compact hands and tapered legs. Preserve the supplied character's silhouette and joint proportions.
- Attractive from front, back, side and three-quarter views. Smooth silhouette on cheeks, chin, shoulders, elbows and knees; preserve low-poly visual character without a pointed or box-shaped jaw.
- Neutral basic body/clothes only. Keep hair, face and modular equipment separable. Do not bake armor, boots, helmet or weapons into the base body.

EXACT SOURCE SCALE AND PROPORTIONS
- Work in metres and preserve the supplied file's source scale; do not pre-scale it to1.8m. The game already performs that normalization.
- Height including reference hair1.596m; original sole plane Y=0.015m.
- Face/head bounding size0.316m wide ×0.358m tall ×0.29386m deep, excluding hair.
- Shoulder joint span0.322m. Upper arm0.133m, forearm0.192m, wrist-to-fingertip extent approximately0.1456m.
- Hip joint span0.1512m. Thigh0.28909m, shin0.287m; hip joint-to-sole height0.699m. Central Hips-to-Neck distance0.378m.
- Bare foot/ankle mesh envelope0.068m wide ×0.170m high ×0.142m deep.
- Match the supplied mesh around neck, shoulder, waist, hip, wrist and ankle attachment regions; existing armor must retain its clearance. Do not change proportions to achieve a different style.

RIG AND ANIMATION COMPATIBILITY — REQUIRED
- Reuse the exact existing57-bone skeleton, including all finger and attachment bones.
- Preserve all bone names, hierarchy, local/global rest transforms, bone roll, inverse bind matrices and attachment/socket orientations byte-for-byte where possible. Numeric joint origins alone are insufficient.
- Preserve `attach_weapon.R` and `attach_weapon.L` and all other attachment nodes. Never reposition sockets to fit a different weapon grip.
- Bind the new geometry to that skeleton in the original T-pose bind space. Transfer and refine skin weights; preserve original joint pivots.
- Keep all existing animation clips, animation tracks, durations and root-motion behavior unchanged. Do not generate replacement locomotion or combat animations.
- No unintended cross-body weighting: hands must not drag torso/clothing; left/right legs and sleeves must deform independently. Check idle, run, both hands holding a weapon, and all four existing ultimate animations.

MESH AND EXPORT
- Base character target5000–6000triangles, hard cap10000; do not spend the budget on hidden internal faces. Current source file totals5585triangles across28meshes, including its stored hair geometry.
- Preserve functional mesh names and modular structure from the supplied template. Retain required metadata and skin materials used by the game's skin/hair coloring. Do not arbitrarily rename or merge meshes.
- Preserve material assignments, UVs and vertex colors where reusing regions; embed all required textures in GLB. Use textures no larger than1024×1024 for new assets.
- Deliver a self-contained glTF2.0 binary `.glb` and editable `.blend`, with embedded textures, skeleton, skin bindings and original animation libraries. glTF +Y up and +Z forward; preserve supplied node transforms. Blender source convention is +Z up/-Y forward.
- No extra scene cameras/lights, no loose unbound geometry, no new root scale/rotation compensation and no missing external files.
- Do not claim compatibility until the replacement has been imported into Godot and checked with existing armor, sockets and animation clips.

## What is required beyond the prompt

A text/image-to-3D generator may produce only an unrigged mesh or an incompatible skeleton. A prompt cannot guarantee exact matrices, weights, topology, names or working animations. Supply the original GLB plus representative equipped/animated references and use a workflow that can preserve/rebind to the original rig. If the generator cannot accept this template, treat its output as a visual sculpt reference requiring rig/weight fitting, not an import-ready replacement. Even with the template, an import/deformation review is required before swapping the production asset.
