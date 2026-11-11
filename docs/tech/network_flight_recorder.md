# Network flight recorder v2

## Purpose and scope

Capture one causally linked window from actual Netfox rooms. A successful upload is not proof that lag is fixed. Native known-cause tests check instrumentation correctness; actual Web tests check deployed execution and upload. No production gameplay/clock/smoothing tuning is part of this change.

The reference is room/player/epoch/input_tick. Timestamps use independent monotonic clocks per client and worker. Never subtract timestamps belonging to different processes. Receipt app RTT includes transport plus browser/server scheduling. After-tick app RTT additionally includes measured worker wait until the next NetworkTime tick. Neither is pure network ping.

## Collection

- Client and worker retain a 30-second ring, capped128samples/768events; scalar values sampled250ms, held-input trace every12ticks, actions traced on capture/inbox/use. Caps and missing joins mean unavailable evidence, not zero latency or proof of dropped input.
- Automatic triggers: client scheduling gap100ms, worker scheduling gap100ms, worker step25ms, snapshot gap500ms, interpolation starvation300ms, corrected same-tick position delta0.25m, outbound queue65536bytes. Triggers are rate-limited30s, freeze before and2s after, retain3incidents locally. They do not auto-upload.
- The same reliable authenticated Room connection carries a capture request. Worker routes it to the authenticated peer's room/actor;5s minimum interval, bounded262144raw capture envelope. No client-selected player or arbitrary file path.
- Lag report collects worker evidence (up to3.5s wait), then sends client+worker evidence through zorx_diagnostics_v1, independent of ordinary feedback's2000-character limit. Retry retains request ID and exact payload. Offline/missing worker data is explicitly marked unavailable/cached with age. Historical incidents survive scene epochs per connection.

## Evidence fields

Client capture, wire enqueue, predicted present; worker wire receive/inbox/use; metadata includes latest inputACK. Held controls may legitimately supersede intermediate inputs; action_tick is separate from latest held input_tick. Queue means RPC accepted, not NIC transmit. Matching is sampled, not a lossless keylogger.

Correction uses a previously predicted tick and re-executes that same tick; normal forward movement is not counted as correction. First differing movement/combat field is stored with values and replay range. Authority event types/IDs/ticks help associate hit/stun; reasons are not automatically classified as expected merely because HP changed. Skill/Gem build IDs are included, no inventory/profile serialization.

Client samples: frame scheduling, snapshot age, app RTT when measured, network/reference/authority ticks, outbound queue, edge queue, entity/projectile/area counts, remote snapshot age/interpolation starvation. Counter deltas: prediction,restore,metadata decode/apply,owner-state decode,owner-state payload/packets,input enqueue calls. Reset counters omit deltas. Render counts/viewport/graphics, browser visibility/focus/longtask support are context. Scheduling incidents attach existing bounded work scopes (including Stage/VFX work where instrumented). Unsupported browser tasks are marked unsupported, not assumed zero. No claim of direct GPU duration/GC attribution.

Worker samples: simulation step duration, frame scheduling gap, input age/action queue, entity/projectile/area counts. Trace includes receipt/use, snapshot encode duration/bytes/outbound queue and scene epoch. Client/worker traces share IDs, never clock origins.

Reports include thresholds, sampling policy, Web content build when available, source metadata, worker release, protocol, scene/loading context. Numeric summaries include sample count/p50/p95/max; absent/unmeasured data is null or omitted, not synthetic zero. Percentiles are of the stated250ms samples, not every frame. Incidents preserve individual stalls.

## Storage and safeguards

Client JSON max256KiB, gzip max64KiB, base64 max87384characters, digestSHA256. Under size pressure the codec removes oldest detail batches and marks removed_oldest_details; JSON remains complete. Encoding work is bounded24trimming attempts. Normal gameplay does not compress or upload periodically.

Nakama accepts only the exact envelope schema under authentication/shared RPCbudget; validates size/base64/digest, one report/min/account, idempotent request, atomic private storage. Three rotating slots/account in zorx_diagnostics_v1; old reports are replaced, storage cannot grow unbounded per account. No public read API, tokens,credentials,profile inventories,chat or device identifiers in the capture. Server treats compressed contents as opaque diagnostic evidence, never trusted gameplay input. Reader verifies digest and decompresses with a256KiB bound.

Reader: python3 tools/backend/read_diagnostics.py --player <authorized-player-uuid> --output /tmp/report.json. It performs read-only SQL via the existing authorized SSH boundary and prints same-clock joined timings. Missing joins stay missing. A stale or unavailable worker capture cannot establish a current transport fault.

## Tests and limitations

- tests/flight_recorder_contract.gd: age/cap bounds, frozen before/after evidence,cooldown,missing values,counter reset,gzip/digest,disabled path and overhead benchmark.
- server/names/runtime/test_diagnostics.cjs: authentication,owner identity,exact schema,private permissions,oversize rejection,quota,idempotence,three-slot retention.
- tools/netcode/migration/check_diagnostics.py: actual native Room direct vs80ms per-direction TCPproxy, explicit client160ms and worker140ms stalls. Asserts both stall categories, receipt+after_tick echoes, input lifecycle traces,capture roundtrip and codec. Not a live player mirror/Web performance claim.
- Existing complete suite has profile/cleanup/online fixture failures and timeout. Never describe it as green based on these focused tests.

Interpretation: high receipt RTT with small worker wait suggests transport/client scheduling; high worker gap/step shows worker scheduling/load; high client gap with attached scope supports client blocking; fresh snapshots plus large same-tick corrections supports simulation divergence; interpolation starvation with stable owner prediction concerns remote presentation. These can overlap. The report is evidence for those distinctions, not an automatic root-cause verdict.
