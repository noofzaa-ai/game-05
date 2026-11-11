# M5 / M6 release and manual acceptance

2026-10-17 — implementation on `codex/online-coop`, test release on `develop`.
M1–M4 source baseline remains supported. M5 features and M6 operations are implemented;
**physical-device / target-i5 release gates below are not signed off**. No images were
pushed and no cluster resources were applied by this work.

## What changed

- Online creation opens a shared safe camp immediately (1–4 players). Actual Nakama
  Friends requests/acceptance, persistent invites and fragment invite links work.
  Inventory/profile stays server-owned. Readiness resets on join/leave/disconnect;
  only the leader can depart after all admitted members are connected and ready.
- Leaving camp saves and unlocks that owner's profile before releasing membership;
  a new membership generation protects reused slots from old leave retries.
  Leadership passes to the lowest remaining slot. Journey rooms retain existing
  disconnect/downed/wear/reward rules. A lost camp does not apply Journey death wear.
- Party names/HP/downed timers, hold-to-revive and four pings are presented locally.
  Revive uses existing server proximity/idle rules; the button sends neutral input.
  Ally sounds are6dB quieter. Each player's ultimate camera remains owner-only;
  boss presentation uses the server epoch/tick and yields to that local ultimate.
- Global admission maintenance, private worker metrics, explicit-context k3s
  CPU/RAM/restart monitor, stable worker-pool YAML and40-room load tool are available.
  Existing sessions can finish/reconnect during maintenance.

## Build/release (operator builds and pushes images)

Use one tested `develop` commit for Web, Nakama runtime, name/profile worker and
room workers. Existing Postgres data/Secrets are retained. Never regenerate the
original database credentials on an existing database.

```sh
git checkout develop
python3 server/names/build_images.py
python3 server/rooms/build_image.py
./pipeline/build_web.sh --max-file-mb 0
./pipeline/build_web_container.sh --image YOUR_REGISTRY/zorx-web:YOUR_TAG
```

Build scripts only build locally. Tag/push the resulting images yourself. Render
using their real immutable `@sha256:...` digests; angle-bracket placeholders are
not executable commands. See `server/names/README.md` and `server/rooms/README.md`
for the existing one-worker rollout and original private Secret bundle reuse.

For40-room capacity use5 independent processes ×8 rooms, with enough schedulable
CPU/RAM. Do not set replicas=5 behind the original shared WebSocket Service.

```sh
python3 server/rooms/pool_deploy.py \
  --image YOUR_REGISTRY/zorx-room-worker@sha256:REAL_DIGEST \
  --workers 5 --output build/k3s-remote/room-pool.yaml \
  --runtime-env-output build/k3s-remote/room-workers.json
python3 server/names/deploy.py \
  --worker-image YOUR_REGISTRY/zorx-name-validator@sha256:REAL_DIGEST \
  --nakama-image YOUR_REGISTRY/zorx-nakama@sha256:REAL_DIGEST \
  --room-ws-url wss://zorxapi.daiyooo.com/room \
  --room-workers-file build/k3s-remote/room-workers.json \
  --reuse-secret build/k3s-remote/names-deployment.yaml \
  --output build/k3s-remote/names-pool.yaml
```

The pool reuses `zorx-room-server` (HTTP key) and `zorx-names-runtime` (worker token)
from the existing one-worker installation. Generate that original room Secret
with `server/rooms/deploy.py --networking --secrets ...` first if not installed.
Review/copy manifests to `/data/k3s/volumes/zorx-game/manifests/` and apply on the
remote machine yourself. Pool worker identities/URLs must match the Nakama env.
Each URL is an exact Traefik path, e.g. `/room/room-0`, through the existing
Cloudflare Tunnel443 → Traefik80 route. Keep control8051 private. Drain existing
rooms before replacing/removing their original worker; changing pool config does
not migrate live rooms. Requests above pool capacity return `room_full`.

## Automated reproduction

All use disposable local containers/processes, never staging accounts or local saves.
Install Python requirements from `tools/backend/requirements.txt`, Docker and pinned
Godot4.7.2. Build the local server images above first.

```sh
python3 server/names/smoke_stack.py --native-rooms --party
python3 server/rooms/smoke.py
python3 server/rooms/smoke.py --image zorx-room-worker:m4-1-local
python3 server/k3s/local_smoke.py
python3 -m unittest discover -s tests -p 'test_*.py'
```

`--party` runs4 genuine server-created accounts, Friends request/accept/invite,
shared camp, leader leave/save/unlock/rejoin, ready/depart and ping. Nakama smoke
also exercises private maintenance/public status, persistence and rate limits.
M4's optional `--native-rooms --long-run` still runs the full legal-bot Journey
with75ms one-way delay,10ms jitter and2% loss. Physical-device acceptance is separate.

## Gate A — four people / two phones + two PCs

1. Open the same Web build. Create an online camp for4. Add/accept a friend, invite
   through Friends, and join another device using copied fragment link.
2. Walk in camp and equip gear. Verify peers' names/equipment, then leave/rejoin;
   check saved gear, leader handoff and ready reset. A full room rejects a fifth.
3. Ready all players. Nonleaders cannot depart/choose portals. Leader starts one
   Journey; all four see the same map, targets, portals and treasure decisions.
4. Cast simultaneous ultimates: each special camera follows its owner. Enter boss
   stage; shared intro returns to gameplay. Try all four pings and ally audio.
5. Down a teammate and hold Revive nearby on a phone. Moving/attacking or being
   out of range must not revive. Check bleedout/elimination and ally HP display.
6. Lose network temporarily, reconnect within30s and verify the same slot/state.
   Rotate phone portrait and back: gameplay input stops, network state catches up.
7. Finish Journey, reload accounts and compare gear, wear, stash and rewards.
   Record build commit, browser/device/OS, screenshots and failure steps.

## Gate B — target i5 load / monitoring

Run on the actual server (or equivalent isolated target), not on the Mac. The load
probe uses real GameSim with four synthetic starter profiles per room and legal
inputs, with repeated encounters; it never writes Nakama or awards real items.
It estimates encoded delta payload upload, **not real WebSocket/network throughput**.
It reports per-room ticks, per-process batch, encode/scheduler cost and host-normalized
CPU. A nonzero exit still preserves the report. Inspect pacing as well as p95:
finished simulation seconds must keep up with elapsed wall time.

```sh
python3 tools/netcode/load_rooms.py --godot /PATH/TO/Godot_v4.7.2 \
  --rooms 40 --seconds 300 --report load-i5-40.json
python3 tools/backend/monitor_k3s.py --context YOUR_K3S_CONTEXT \
  --samples 60 --interval 5 --report k3s-metrics.jsonl
```

Also run40 real admitted rooms /160 clients against staging to measure actual
WebSocket upload, ping and process scheduling; synthetic simulation is not that
acceptance. Use node/network counters alongside the private worker metrics below.
Thresholds: tick/batch<=16ms, steady node CPU<=70%, no overload/crashes or long
backlog; upload must fit the node uplink. Mac short-run tests are tool diagnostics
only. Repeated Mac runs showed timing/pacing failures under serialization contention. Shared snapshot/delta/TLV caches reduced the cost while preserving bytes/privacy; a30-second40-room diagnostic still required roughly34 seconds per process, so the gate remains open;
**40-room release remains gated pending target benchmark and any needed tuning**.

Port-forward each worker's private control8051 from the selected target context;
store the existing token in a local0600 file without printing it. The monitor
never prints bearer/HTTP keys or profiles.

```sh
python3 tools/backend/room_ops.py monitor \
  --workers http://127.0.0.1:18051 http://127.0.0.1:18052 \
  --token-file /PRIVATE/worker-token --samples 60 --interval 5 \
  --report room-metrics.jsonl
```

`/metrics` reports room/player counts, rolling4096-sample tick p95, lifetime max,
backlog, memory, bytes, peers, state-ack RTT and bounded room close reasons.
State-ack RTT includes client send cadence; use client F2 for ping. Node CPU/RAM
comes from `kubectl top`; metrics-server is required. Scripts emit alert rows /
nonzero status for inspection and do not send external notifications.

## Gate C — maintenance / restore

Close admissions on Nakama and the selected workers; existing rooms may finish.
Never kill all workers as the maintenance mechanism. Runtime env
`ZORX_MAINTENANCE=true` is a startup hard override and must be removed to reopen.

```sh
python3 tools/backend/room_ops.py maintenance-on \
  --nakama-url https://zorxapi.daiyooo.com \
  --http-key-file /PRIVATE/runtime-http-key --token-file /PRIVATE/worker-token \
  --workers http://127.0.0.1:18051 http://127.0.0.1:18052 \
  --report maintenance.jsonl
# Same arguments with maintenance-off reopens admissions.
```

The game shows maintenance text at entry and rejects new rooms/members. The Web
container also serves `/maintenance.html` for an operator-controlled Ingress
switch if desired. Do not replace an active game's assets mid-Journey.

Local real Postgres custom dump→scratch restore and account persistence were
retested. For actual off-machine backup/restore use the existing full procedure
in `online_ops.md` (backup prefix, private credentials and scratch `restore_*` DB)
and `server/k3s/restore_job.py`. Verify account/profile/name rows and sample gear
in the restored scratch database before signing off. Never restore over live
`nakama` or assume a hostPath directory is an off-machine backup.

## Domain ownership (Boss, 2026-10-17)

- `zorx.daiyooo.com`: landing/registration/start button, owned by the other team.
- `zorxplay.daiyooo.com`: this game Web build; landing links its start button here.
- `zorxapi.daiyooo.com`: Nakama HTTPS and room WSS (`/room`).

Add play/API public hostnames to the existing Cloudflare Tunnel targeting Traefik HTTP80, then apply the fixed staging ingress manifest. Rebuild Web so its bundled API host changes.
