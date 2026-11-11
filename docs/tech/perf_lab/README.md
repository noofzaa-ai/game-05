# Web performance isolation laboratory

Dedicated test deployment `perf-lab` in `zorx-staging`, static page at https://zorxplay.daiyooo.com/perf-lab/ and WS at `/perf-lab-ws`. Does not replace production Web/headless, hold real account credentials, read/write profiles or grant items. User explicitly authorized lab Web/worker pushes and revisions to registry wiyazard:30500.

Build has custom feature `perf_lab`; normal boot remains unchanged. Only lab container HTML skips account session/redirect, since the data is synthetic. Production authentication and room admission remain intact. Worker has no DB/Secret/service-account mounts;2concurrent peers/600secondTTL, memory512MiB/CPU1 limits. Delete dedicated ingress/service/deployment after diagnosis if no further device comparisons are needed.

## Controlled workload

Same `goblin_arena_c` scenery/player/native models/up to8enemies, seeded2662026.720ticks:3seconds idle,3seconds movement,3seconds attack,3seconds4skills. Server simulation60Hz, snapshots20Hz, real production Wire/NetState binarycodec and RemoteSession acceptance/prediction functions. Browser is actual headed Chrome/WebGL, not native Godot. Initial loading and prewarm precede timed runs. ALL executes8modes×3repeats; rendering controls same across modes.

Server uses the canonical deterministic input script to ensure identical authority outcome; client sends validated input packets over WS for transport measurement. Therefore this is **not** a production input scheduling, admission or end-to-end input latency acceptance test. Production reverse proxy/HTTPS/remote network is exercised. Profile/run metadata are synthetic initial snapshots; production ownership/CAS/DB paths are excluded. Seeing a hitch here can establish those services are not necessary for that hitch, but cannot establish they never contribute in real accounts.

|Mode|Enabled|
|---|---|
|N|Remote wire/decode/reconcile/current prediction; scenery and effects hidden/disabled. Records exact packets/states/events for replay. Recording itself adds some allocation overhead.|
|A|Render prerecorded states/events; no live network or GameSim ticks. State-to-view object application remains included.|
|B|Local authoritative GameSim+AI+skills+render, no WS.|
|C|Remote snapshots+render, no prediction. Dedicated diagnostic accept path omits full ownership refresh and input responsiveness is intentionally sacrificed.|
|D|Production acceptance and prediction construction, but replay only local Movement.step.|
|E|Current production acceptance+GameSim prediction/replay+render.|
|R|Exact N wire packet tape, timed replay with production decode/reconcile/current prediction+render, no live WS input/state.|
|Z|Exact N packet tape Wire.decode+NetState.apply only; no simulation/reconcile/render.|

C/D/E differences require care: C omits both prediction reconstruction and some metadata/ownership work; D/E is the closer controlled pair for replacing full GameSim replay with local movement. Fixed mode ordering means first-repeat shader/cache warmup is reported separately; later repeats are warm comparisons. Native renderer timings from previous VFX work are not used as these browser results.

## Measurements

Godot Web frame intervals p50/p95/p99/max/over50, perframe tick/view/drain durations, drawcalls, RemoteSession construct count/time, accept time, replay ticks and WSqueue; remote authority tick distribution, encode totals and observed input packet counts. `ingest_total_ms` includes `_receive` and any acceptance it invokes; do not add it to `accept_total_ms` as disjoint costs. Browser requestAnimationFrame traces collected independently by Playwright. Same page/browser viewport1335×720/deviceScale1; hardware is local Mac, not user'sRTX3070Ti. No final device FPS promise.

Local code compilation is allowed for preflight only; results are collected exclusively from the deployed Web page. Browser results are published to `window.zorxPerfReport`; source runner `tools/perf/run_browser.cjs` (requires playwright-core and installed GoogleChrome). No native benchmark numbers are substituted.


## Input-driven follow-up (27 October)

V2/V3 execute `RemoteSession._step_impl` and actual tick-addressed `Wire.inputs` at the worker (same future bound +24); all snapshots refresh profile/run metadata. Worker polling is capped at 60Hz to match production. V3 fixes the diagnostic lead at a modeled RTT of 150ms (11 ticks) and holds skill requests for six ticks to tolerate single-frame packet loss; this is a controlled test parameter, not a production RTT change. Results include accepted skill casts and actually consumed input ticks. V2 had insufficient lead; do not compare its FPS as equal-workload trials.

Additional modes: F reuses the prediction simulator (diagnostic only); H disables combat VFX; J excludes cooldown-only run changes from ownership refresh (diagnostic only); K advances only the local actor using the same combat-pose/movement code, leaving other actors, hits, projectiles, AI and economy authoritative. R replays exact N packets using full prediction; P replays the same tape using K. Both use the actual Web decoder and reconciliation; no live transport/worker workload during R/P.

The candidate production change is K, not movement-only D. `GameSim.tick()` defaults to the unchanged authoritative simulation; only `RemoteSession` passes its own player ID. Attack buffering, block, dodge, jump, movement, timers and hitstop still execute for that actor. No predicted damage/rewards are committed. `tests/prediction_local_actor.gd` verifies five weapon families over 240 ticks each, including casts freezing movement, hitstop, guard and knockback, and verifies that remote actors/projectiles remain untouched. These are correctness checks, not native performance measurements.
