# New v1 character integration — 2026-10-19

Default visual: `newv1_base_animated.glb`, adapted from `assets/new-v1.fbx`
in the parent art workspace. 1,636 triangles, two mesh objects, production
57-bone hierarchy. The original FBX's body/head proportions are retained;
articulated production hands replace the solid mittens, and forearms taper
to their wrist openings. Skin color remains configurable.

## Motion and weapons

Six `art/animations/newv1*.glb` libraries provide 39 runtime clips with the
existing gameplay timing metadata. Locomotion, stance, attacks, guard and
dodge are retargeted in rest-space; pelvis height follows foot contact.
Two-handed poses use actual weapon grip markers and preserve grip spacing.
The largest measured two-hand grip marker residual in runtime samples is
0.0000251 m. This numerical check does not establish perfect finger contact
or absence of all mesh intersections.

Native Godot review captures: `build/screenshots/new-v1/`. Idle/run captures
were generated for fists, blade, dagger, spear and hammer. Visual review
covered unarmed run, spear shoulder carry and two-handed hammer run.
Physical-device acceptance is still needed. Separate external ultimate
motion packs have not received a complete visual review on the new body.

## Deliberately deferred

Old clothing, hair and face meshes are fitted to the old proportions, so
CharacterModel suppresses their geometry on New v1. Profile equipment,
stats and saved cosmetic choices remain intact. This is a neutral body
stage; facial detail and wardrobe fitting follow separately.

## Authoring / rollback

Parent workspace source: `art/source/characters/new_v1_game.blend`.
Builders in parent `tools/blender/`: `build_new_v1_game.py`,
`fit_new_v1_fingers.py`, `refine_new_v1_wrists.py`,
`retarget_new_v1_sets.py`, `publish_new_v1.py`.
Run those stages in that order (finger fitting is also called by the base
builder); wrist refinement is guarded against a duplicate application.
Studio: `http://127.0.0.1:8765/?studio=character&variant=new-v1`.
Studio offers its 31 source clips; the game uses the six adapted runtime
libraries above. Full GLB/Blend downloads preserve all source clips.

The old `art/characters/chibi-studio/chibi_base_animated.glb` and `chibi*`
animation libraries remain available. Restoring CharacterModel.MODEL_PATH
and StageView.PLAYER_MODEL to that path restores the prior visual body.

## Local follow-up (not built/deployed)

Equipment paper-dolls now request the source Stand<Weapon> resting clip,
rather than the combat idle re-pose. Other game views keep their idle.
Studio Run2 playback uses the current game run duration and sprint rate
(1.4 after CharacterModel's clamp), with crossfade warping disabled when
retiming. Face/hair menus are exposed as preparation panels; legacy assets
remain disabled until fitted to New v1. User explicitly paused build/deploy.

## Local integration 2026-10-19
Four approved ultimate motion derivatives now replace canonical game motions (Solar Slam, Lightning Spear Recall, Shadow Extraction, Hammer Ground Drag). Spear default changed to lightning. Hair and faces use fitted New v1 paths; unfitted clothing geometry and124 catalog items removed, leaving the three fitted Scout pieces and weapons. Basic shirt/pants use the fitted Scout vest/breeches. Existing account saves are untouched. Godot import and shadow script parsing completed; no full gameplay/device visual QA or build/deploy in this change.
