---
name: artifact-update-only-on-boss-order
description: Do not re-export/republish the zorx web playtest artifact during dev; only when Boss says so
metadata:
  node_type: memory
  type: feedback
  originSessionId: cd4c38fb-e1d3-4d72-88bb-0642aef89254
  modified: 2026-10-05T15:12:00.564Z
---

Do not update the web playtest artifact (re-export + publish play.html) as part of normal dev work. Only push a new build when Boss explicitly orders it. Applies to PO and every agent brief (especially tech-artist).

**Why:** Boss said (2026-10-04) "while we're developing, don't update the artifact; wait until I tell you to push it."
**How to apply:** Agents may still export locally to build/web/ for testing, but never call Artifact publish for it; add this rule to any brief that touches the web build. See [[boss-communication-rules]].

**When Boss says "อัป artifact" (2026-10-05):** run `powershell -ExecutionPolicy Bypass -File tools\web\build_web.ps1` (stops if tests fail), then publish `build/web/play.html` with files `index.js`, `engine.gz.wasm`, `gamedata.pck.wasm`, `index.audio.worklet.js`, `index.audio.position.worklet.js` to the existing URL https://claude.ai/artifact/Spy7vviYLBgJtwVWyBuZjm (keep its link; read it first if this session hasn't).
