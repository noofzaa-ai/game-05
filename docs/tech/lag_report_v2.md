# Lag report investigation — 2026-10-24

Local only. Four user reports show initial long hitches (max888ms), then~33FPS even with reduced graphics. They differ inmap/time, so this is not a controlled GPU comparison. No explicit client FPS cap found. Old step_ms excludes prediction replay inside reconcile; do not interpret it as allsimulation cost.

## Changes
- Cache immutable collision world bymap; each snapshot retains fresh independent dynamic sim. Movement/AI/projectiles read world solids and bounds; no runtime worldmutation found.
- Sample only AccessoryWing channels for WingsIdle/WingsRun, HairTail. channels for secondary hair. Same authored channelvalues, phase andblend.
- V2 rows append decode_ms,reconcile_ms,packets,replay_ticks. poll_ms includes these nested stages; never sum them as separate totalcost.
- runtime snapshot:configured FPS cap,VSync,process/physics CPU time,drawcalls,objects,primitives,lifetime max packet queue,scene construction andfirst-present delay. Runtime render counters/timings are latest samples, not10second averages; they do not directly measureGPU time.
- Manual upload only. No new background requests.

## Next device measurement
Same map anddevice: collect a report after entering, andanother after20seconds; keep graphics unchanged. Compare startup scene timings vsdecode/reconcile vsprocess time anddrawcalls. Compare identicalmap withonlyrender_scale changed to isolate resolution sensitivity. Thispatch has notbeen deployed or measured onthe affected device; no claimed FPS improvement.

2026-10-24 lag-v2-20261024-1 DEPLOYED at Boss explicit request. Public Web build b19d60a48796, game-test rollout successful;13 engine/core/content endpoints HTTP200. Client-only immutable collider cache + filtered native wing/hair sampling + manual Lag Report v2. Server authority images unchanged. Compile/import/export/split completed; no actual device FPS improvement claimed. Disk full interrupted first two generated builds; removed only failed generated staging folders and authorized regenerable Docker build cache (19.42GB cache +397MiB old staging); source assets/model backups/rollback records preserved. Release/rollback build/lag-v2-release.json and build/lag-v2-rollback-deployment.json.

## Outline comparison control — 2026-10-25 (local only)
Graphics → เส้นขอบโมเดล (Outline). Device-local bool defaults on; Lag Report graphics.outline records it. Setting switches real outline mesh visibility and material next_pass references, preserving toon shaded material, original width (.005/.0015–.002), refinement VFX and UI borders. Native source exclusions remain excluded after off→on. Apply onsettings transition and deferredmesh entry, no repeated globalframe scan. Material chains keep unrelated non-outline passes. Newmodels follow current preference. Compare samemap/standingposition/camera/AA with setting on/off afterclosing settings; capture one report permode. No performance improvement claimed yet. Not deployed.
