# Oval B continuous surface draft — 2026-10-20

Replaces the rejected lower-jaw-only trial. Based on Boss-selected B + GAME HAIR concept. Actual Godot renders, not AI-generated review pictures. Production runtime still selects the old model.

## Current shape

- One closed manifold oval surface,48 longitude segments x28 latitude divisions,2592 triangles. No old/new splice below the eyes.
- Skull top1.523m,chin1.185m,max width.316m. Chin centre moves forward32mm; rear lower depth contracts28% to avoid a rear jaw pouch.
- Full skull now rebuilt, including upper surface: previous upper-skull-lock claim applies only to the rejected draft. Original overall max width/top retained; this does not establish all existing hats fit.
- Smooth normals across the surface; eyes/brows/nose/mouth are depth-fitted to it with1.5–6mm relief. X/height preserved.
- All11 face_*.glb expression assets now fitted in the draft catalog. Replacement-head items (head_*) are excluded because they replace the skull. Production face catalog not promoted.
- Three actual game hairstyles copied into draft and rear/lower cap fitted, original production files unchanged. Fringe design and mesh topology preserved.
- Rig rest unchanged; static draft export only. Motion/hat/full catalog acceptance remains outstanding before promotion.

## Review

`tools/art/review_oval_b.gd` captures FRONT,45deg,SIDE,BACK,LOW45deg,TOP45deg for short,silver,center-part hair and bare head. Camera centers on actual head AABB; desktop scale disabled so the right column is not clipped. Native final capture logs have no script errors. Closed manifold asserted in builder.

Images: `docs/art/previews/oval_b_{short,silver,center,bare}_angles.png`.

Rebuild using Blender `--background --factory-startup --python tools/blender/preview_chibi_oval_b.py`; source under art_source/characters/chibi-oval-b. This is a visual fitting trial and not a deployed hero replacement.

2026-10-20 Expression preview: tools/art/review_oval_b_faces.gd captures all11 actual expression GLBs on the same oval-B head and center-part hair, front and45deg. Native captures docs/art/previews/oval_b_faces_front.png and oval_b_faces_angle.png reviewed; no script errors. This confirms these visual previews, not full motion/hat acceptance.

Boss approved production promotion2026-10-20: live base now uses oval head plus fitted11 faces/48 hairs;31 embedded animations retained byte-exact. tools/art/promote_oval_b.py and immutable source backups provide rebuild/rollback. Runtime still uses original stable paths. Draft files excluded from export. Native idle/run +2 available helmets reviewed.
