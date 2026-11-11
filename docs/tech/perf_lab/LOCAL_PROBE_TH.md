# Local gameplay + packet probe (2026-10-27)

URL: https://zorxplay.daiyooo.com/?local_perf=1

Build f39e05a19d80 adds three in-page modes. Gameplay remains LocalSession on an independent authenticated profile copy. None applies network state or uploads rewards.

- 0 Local: no diagnostic socket.
- 1 Receive: isolated /perf-lab-ws traffic, binary payloads counted then discarded. No Wire.parse/decode.
- 2 Decode: same synthetic fixture, Wire.parse + Wire.decode + NetState.apply to private baselines (cap32). No RemoteSession, prediction, reconciliation, entity views, or gameplay mutation.

The worker is existing perf-worker v2 / Scenario. It executes deterministic synthetic 720tick rounds and automatically restarts after the completion control message. It is NOT a shadow of the actual player's inputs/profile/map, and production packet volume can differ. Results locate overhead under this test workload, not definitive production transport causation. Phase0 excludes worker traffic/load too, so compare phases1/2 closely for decode attribution.

Select each mode in the SAME scene and graphics setting, wait at least 15s, use comparable movement/skills, then Copy local lag report. Repeat 0/1/2/2/1/0. Prefer report windows near10s. For phases1/2 require ws_open=true, packets>0; for phase2 require decoded_states>0 and invalid=0. Disconnected or empty-traffic reports cannot establish a pass. Changes in scene reset window; network counters reported as end-minus-start across retained frame samples. poll_including_decode_ms contains decode_ms: do not add them. max_queue covers mode/scene selection lifetime. Packet connection lasts at most600s on existing worker; reselect a mode if disconnected.

Validation: isolated 40 real-format delta packets pass discard/decode independence and32baseline bound; no gameplay mutation. Public WSS transport smoke verified10binary packets (25,411bytes). These are correctness/connectivity checks, NOT browser FPS results. User reported initial local-only mode eliminated lag; phases1/2 await actual browser measurements.


## State layers suite (phase3)

URL `https://zorxplay.daiyooo.com/?state_lab=1`. Normal HTML authentication remains; scene uses only synthetic profiles and has no account/reward writes. Reuses existing lab scenery, camera, renderer and fixed Scenario. Four modes run720ticks each: 0 local simulation;1local+receive/discard;2local+decode/private snapshots;3server snapshots applied via RemoteProbe C into render simulation, no local ticking/prediction/replay. Mode3 replaces local simulation rather than adding apply work on top of full local simulation: compare apply/decode timings as well as totalframe results. No interpolation is added in phase3, so20Hz snapshot motion can appear stepped even at good FPS.

`Run0-3x3` automatically executes0/1/2/3,3/2/1/0,0/1/2/3 (around2.5minutes); first run can include shader warmup. Input script and map/profile are the same at source and worker, but state arrival latency/bursts can alter visible timing and VFX overlap. Worker is authoritative for phase3 only. No result asserts exact render workload from timing alone; inspect drawcalls, worker ticks/bytes and validity. Phase3 produces40state apply contract validation with prediction=null/replay=0 in native correctness test. Actual performance must be measured in deployed browser.

Phase3 counter definitions: wire_decode_ms is Wire.decode only; receive_including_inline_apply_ms wraps RemoteSession receive and can include inline accept on event ordering; accept_ms includes construct/apply. poll_ms wraps all drain/flush work. These overlap: do not sum them. decode_private_snapshot_ms in mode2 includes Wire.parse/decode and NetState.apply. Phase3 uses Probe C and intentionally omits production ownership refresh, prediction reconstruction and reconciliation; those remain later phases. New suite uses the shared lab camera and disables vsync equally in every mode, so compare0–3 internally rather than absolute FPS against older free-play reports.


## Phase4 metadata / production accept

Mode4 uses RemoteProbe M: production RemoteSession._accept_state, including route/ownership diff, Profile.from_dict / Run.from_dict, journey update, signals and sample history. Shared `_uses_prediction()` defaults true in production and is overridden false ONLY in diagnostic M. Neither prediction simulator construction nor replay runs in M. A stage-style ownership callback computes ItemAssets looks, compares equality and calls FighterView.set_looks only when changed; it does not open or refresh inventory/HUD/menu panels. Counters report ownership_checks/changes, equality-check cost and dress_calls. Synthetic fixture may not exercise every ownership change that real gameplay has.

Button `Run3-4x3` runs3/4,4/3,3/4 (~75s), same scene/scripted fixture. Keep tab foreground and device awake; prior results showed 73-175s stalls marked invalid. Do not infer their cause. Only valid runs count. Existing individual0–4 buttons remain. Metadata contract test40states verifies profile/run, nullprediction, zero replay; production default stilltrue. Fiveweapon x240tick correctness regression passed. Full suite has previously documented unrelated fixture failures; this build skips that known-failing suite. All timing conclusions still require deployed Web reports.

User phase0–3 report adf65b883ad5: warm valid repetitions1/2 FPS0=57.9/60.0,1=57.9/58.6,2=54.4/59.4,3=55.3/60.2; no frame>50ms in those repetitions. Equal297packets/392967bytes per network trial; worker720ticks/4casts. First repetition modes0/2/3 invalid due73–175s frame gaps; cause unknown. Graphics combatVFX/outline/shadows/fog/glow OFF, scale.5/AA2. This does not reproduce heavy production lag; metadata/prediction/replay remain untested. Raw report results/user_state_layers_20261027.json.

User phase3/4 reports99c0252db27b: first attachment6runs duplicated at front of second18run attachment; count18unique runs (3batches), allvalid. All network trials297packets/392967bytes/240states/720worker ticks,4casts. Mode4 ownership changes78/trial, lookschecks78, actualdress_calls0, replay0. Batch medianFPS3/4 approximately60.2/58.9,53.4/52.2,52.2/50.4; p95medians17.6/22.1,25.2/28.0,24.6/26.5ms. Metadata addswork but heavy original lag remains unreproduced. Both modes slow between batches; cause unmeasured. GraphicsVFX and other costlyeffectsOFF. Next separate prediction reconstruction/live advancement from replay. Raw results/user_state_metadata_20261027.json.
