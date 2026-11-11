---
name: pending-idle-stances-from-model-team
description: Weapon idle stances arrived 2026-10-08 (Stand*/Block*/Dash*); unarmed idle is ours to author (Boss order)
metadata:
  node_type: memory
  type: project
  originSessionId: a1c72c15-e852-412b-b2fb-ec31ac8cc862
  modified: 2026-10-08T09:34:54.171Z
---

2026-10-08: the model team delivered Stand/Pose/Block/Dash clips for blade, dagger, spear, hammer (no unarmed clip, no attack clips). They are wired via tools/blender/chibi_anims.py. Boss then said the PO handles the unarmed idle itself and wants it natural (breathing, movement); it is authored procedurally in chibi_anims.py (IDLE_UNARMED).

**Why:** the earlier rule "don't let the animator author idle stances" was only while waiting for the model team; Boss lifted it for empty hands.
**How to apply:** tune the unarmed idle in chibi_anims.py, not by asking the model team. If the model team later ships an unarmed clip, ask Boss which to keep. Attack clips for spear/hammer on the chibi are still missing. See [[remind-boss-pending-decisions]].
