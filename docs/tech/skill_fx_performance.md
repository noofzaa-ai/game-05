# Skill VFX performance patch v1 — 2026-10-26

DEPLOYED at Boss request: skill-fx-20261026-1. Build `a6e2729d5063`.

## Evidence

User reports about48–51FPS, ping37–44ms, physics1.8–7.3ms, frame maxima52–54ms in supplied samples. These reports do not mark cast timing and cannot establish every hitch's cause. Independent scene inspection found fireball904meshinstances/1017source nodes and repeated full scene/material instantiation; direct native benchmark measured904drawcalls for one fireball effect.

## Changes

- Build-time `tools/art/optimize_skill_scenes.gd` folds eight mutually exclusive phase meshes into one MeshInstance per authored sprite. It preserves parent native transform tracks, all8original frame meshes/materials and exact STEP phase times. Nonconforming groups fall back unchanged.27assets/1139groups; track count11357→2667. Generated `runtime.scn` loaded by adapter; sourceGLB/Studio untouched.
- Adapter caches clips and lengths, shared material variants perinstance, removes repeated AnimationPlayer animation-list scans, swaps native frames at phase boundaries and updates only actually used shaders. Render geometry/scale/colour/timing retained. Root authored movement remains unchanged.
- Presenter uses bounded pool2idle instances perkey/12total. Completed effects and ended statuses are stopped/hidden and reused, preventing repeated node/material construction every cast. No cap on active gameplay effects and no server rule changes.
- Local equipped4skills, projectile/beam variants, burn/bleed and cast animation library prepared under scene-loading gate. Loading ACK occurs after prewarm. Heavy status effects use same optimized adapter with original material mode. Missing fire_ring adapter was added to point at existing source effect.
- LagReportv2 gains fx_setup_last_ms/max_ms and fx_created/reused for diagnosing actual device follow-up. Warmup times are excluded from cast setup metrics.
- Web pipeline rebuilds derivatives after import, before export. Current download about82.33MBPC/82.56MBmobile, +1.07MB versusbow release because native fallback and runtime derivatives coexist; no oversized source image added.

## Local results (same native renderer machine, not device FPS promise)

| Fireball | Before | Folded |
| --- | ---: | ---: |
| Nodes |1020|228|
| Draw calls |904|112|
| Cold play setup ms |313.526|120.780|
| Frame p50/p95 ms |11.277 /24.577|8.387 /18.524|

After prewarm/pooling:12casts reused1instance, node count637→637, event setup p50.850ms/max1.345ms.7representative skills×3timestamps=21image comparisons had zero changed channels.20skills×4presentation phases instantiated/sampled without script errors. Isolated actual exported core/character/S3TC packs mounted and rendered228nodes/112drawcalls. Actual game scene entered after prewarm without script errors; existing material-null teardown diagnostics persist.

Evidence: build/skill-fx-performance-report.json, skill-flipbook-report.json, skill-fx-visual-comparison.json. Reproduce with tools/shots/skill_fx_runtime_review.gd, skill_fx_pool_review.gd, skill_fx_compare.gd. Fulltimeline, Web/mobile and live two-player performance acceptance remain open; not deployed.

2026-10-26 — skill-fx-20261026-1 DEPLOYED at Boss request: Weba6e2729d5063 digestbf3915fe750b632e9f2f788f844880e61e57982a0bf4aa438f52558c218f3b8b. Folded native8phaseVFX, boundedpool, loadingprewarm+castinglibrary warmup,missingfire_ring adapter and FXLagReport metrics. Webrollout successful,publicmanifestmatches,15/15assetURLsHTTP200. Clientonly; profile/room/Nakama unchanged. ActualWeb/mobile/onlineFPS improvement awaits Boss trial; localmeasurements only. Release/rollback build/skill-fx-release.json,build/skill-fx-rollback.json.
