# Network flight recorder — 2026-10-31

Boss authorized complete diagnostic instrumentation, deployment and actual Web verification. This release collects evidence; it does not claim to fix lag.

## Deployment

Web build `4513d8b89b65`: `wiyazard:30500/zorx-web:flight-20261031-1@sha256:02e64bf1aaa8656f41c4748939f0e6d89eb4facb7ba0d9155eaf4e0fff366a11`.

Rooms: `wiyazard:30500/zorx-room-worker:flight-20261031-1@sha256:f0dfa6ee3675493a62ef3537847af1b952e3204c642447c137622371e0b1fd09`.

Nakama: `wiyazard:30500/zorx-nakama:flight-20261031-1@sha256:f71b326eb9ba55d2368984675564d54d59d0cb455e4acb28949b84e3426721c7`.

All three rollouts succeeded in `zorx-staging`; remote declarative image lines backed up and synchronized. Profiles image/resources/secrets unchanged. Public core bytes equal candidate bytes. Nine scoped client scripts over build659a; all unrelated content/engine bytes identical; compressed core grows3169bytes. Worker overlay limited to eight diagnostics/input-trace scripts. Nakama compiled diff audited to endpoint registration, endpoint implementation and its payload limit.

## Behavior

See `../tech/network_flight_recorder.md` for schema, limits, clock interpretation, reader and thresholds. Thirty-second bounded client/worker rings, frozen pre/post incidents, input IDs across capture/enqueue/inbox/use/present/ACK, receipt and after-tick application RTT, correction first-field, remote interpolation starvation, scheduling/simulation scopes, build context. Lag report requests worker capture and uploads bounded gzip through a separate authenticated private RPC. Three slots/account; one report/minute. Ordinary feedback limit unchanged. No automatic upload.

## Validation

- Recorder ring/caps/nulls/counter resets/frozen incidents/codec tamper/disabled path PASS. Native incremental overhead about12us/record in this run; not a Web performance guarantee.
- Backend auth/schema/size/owner/private permissions/quota/idempotence/three-slot retention PASS.
- Actual native Room direct and80ms per-direction TCP proxy: known client160ms and worker140ms stall detection, receipt/after-tick echoes, input lifecycle and compressed capture PASS. Synthetic admission only, not a live-player mirror.
- Additional actual Room forced0.8m fixture desync detected as correction PASS. No production position mutation.
- Full suite attempted45s; existing beta-cleanup missing-profile fixture assertion and timeout. Full suite is not green.
- Actual Safari public4513 own perftest-01 reached hub, but Practice/Goblin online transition displayed a gray world/header with no HUD. A clean reload repeated the transition. Chrome4513 new tab reached hub; initial console showed existing asset UID fallback warnings and HTTP timeout/retry messages, no identified diagnostic script cause yet. CUA then returned startup failure and empty app/browser inventory, preventing further UI verification. No private diagnostic upload exists for the Safari test account. Web acceptance remains OPEN; do not treat native checks as Web acceptance.

## Rollback

Web: prediction measurement digest `bbd95f90faff2547a4048cfa803c000fd254d4c7108f0222c7a84bbcad1da6dd` (build659a8eeb9299). Rooms event-batch digest `b5cd17c0a0b128d71de8dc8d8d061b80debbea84ecfe07e7a871f1844f68fac3`. Nakama relic digest `69fe089ff00003fb3436dd2cc305268964a9d3c78ee89e5e75702b3c29eb936d`. Image-only rollback; diagnostics private storage can remain inert.

2026-10-31: Boss independently reproduced gray screen entering Goblin on4513. Web rolled back to netfox-measure-20261031-1 digestbbd95f90faff2547a4048cfa803c000fd254d4c7108f0222c7a84bbcad1da6dd, public659a8eeb9299 verified. Worker/Nakama diagnostics retained; no RPC signature change. Root cause unconfirmed; new suite Web acceptance failed. Await real-device recovery confirmation.
