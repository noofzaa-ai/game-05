---
name: boss-token-budget
description: "Boss worries about token cost; avoid heavy agent loops, esp. scripted Blender modeling"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 96a0606f-8450-48c4-9f86-2b27c4442898
  modified: 2026-10-12T00:00:00.000Z
---

Boss said (2026-10-05) team modeling in Blender "เปลือง token มากๆ" and doesn't want lots of model-building by agents.

**Why:** scripted mesh building + render/review loops burn tokens; Boss tried Modly (local AI image→3D) but dropped it from this project on 2026-10-06.

**How to apply:** keep agent tasks narrow and specific, prefer one reusable pipeline script over per-asset agent work, use qa (now Opus 5.5 too, Boss 2026-10-12) for checks, do small wiring edits myself. Ask Boss for references before UI/art work to avoid iteration. See [[zorx-team-roles]].
