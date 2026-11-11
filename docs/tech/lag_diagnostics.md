# Live gameplay latency diagnostics

**Disabled at Boss’s request after the phone reproduction.** Client timing collection,
performance reports, worker timing rings/input counters and periodic ROOM_PERF logs
have been removed. Existing Ping/FPS HUD and original private operational metrics
remain. The details below document the temporary investigation build; they are not
active in the snapshot optimization release. Historical logs remain until normal
log rotation.


The Web client sends a bounded numeric performance report over its already authenticated
room socket every 10 seconds. The worker logs `ROOM_PERF=` every 10 seconds while rooms
exist. No names, account IDs, room IDs, tokens, inventory or free text are logged.
Connection numbers are ephemeral process-local values. Client reports are untrusted,
allowlisted, finite, bounded, rate limited and never used for gameplay/admission.

## Capture on k3s

While reproducing on a phone for at least 30 seconds:

```sh
bash diagnose_lag.sh 5m > lag-report.txt
```

The script is `tools/backend/diagnose_lag.sh`; run on the k3s host. It reads node/pod
CPU and memory and filtered headless logs in `zorx-staging`. No Secrets are read.
Alternatively:

```sh
kubectl logs -n zorx-staging deployment/headless -c rooms --since=5m --timestamps=true | rg 'ROOM_PERF='
```

Private bearer-protected `/metrics` also includes `loop`, `performance.snapshot` and
`performance.clients_untrusted`. Nothing is exposed publicly. Fresh client reports
expire from metrics after 30 seconds; old deployed clients simply omit reports.

## Interpret together

- `frame_ms`: interval between client polls (includes rendering, browser scheduling,
  physics, and background/tab/keyboard pauses). `fps` is Godot's frame estimate.
- `receive_ms`: packet decode, delta application, reconciliation and synchronous
  callbacks together; `apply_ms` isolates delta application.
- `accept_ms`: reconciliation including prediction rebuild/replay, profile handling,
  journey update and synchronous signals before state-ready emission.
- `rebuild_ms`, `replay_ms`, `predict_tick_ms`: client prediction work. Replay is
  included in accept; these durations must not be added together.
- `snapshot_gap_ms`: time between complete snapshots accepted by the client. Expected
  steady delivery is about 50ms at 20Hz, with normal transport/frame variation.
- `state_age_ms`: elapsed local time since the last accepted snapshot, not clock-synced
  one-way network latency. `ping_ms` is application RTT and includes polling delays.
- `lead_ticks` and `corrections`: client prediction lead and position corrections (>5cm)
  since its last report. Server `input_lead_ticks` is the latest input tick minus
  authority tick; negative/zero means that newest input is already late.
- Worker `missing_inputs / input_slots`: connected, non-eliminated player ticks with
  no queued input (neutral input was used). Large ratios during sustained movement
  can explain rubber-banding even with healthy FPS. Counts reset at worker reports,
  include brief startup gaps, and do not prove intentional input loss.
- `rx_kbps`: received wire bitrate over the client report interval.
- worker `loop_gap_ms`: interval between worker loops. `simulation_ms` is manager
  advance including catch-up. `transport_ms` includes polling, packet parsing,
  commands and outgoing state. `snapshot_ms` is per-peer snapshot construction,
  diff and encoding/enqueue; it excludes actual network delivery.

Healthy worker but high client frame/receive/replay durations points to client CPU or
rendering; healthy client processing with irregular snapshot gaps requires comparison
with server transport/loop times and direct-vs-public network probes. High worker
transport with low simulation points to snapshot/codec work, not monster AI.
Do not attribute every slow frame or RTT spike to network.

Each timing keeps only the latest 180 samples per named phase, resets every report
interval, and reports p95/max. At high rates this covers the tail of that interval,
not every frame. Client and worker report boundaries are asynchronous. Hidden tabs
can inflate samples. This is lightweight diagnostic sampling, not a full trace or a
GPU profiler. No per-frame logging or per-frame HTTP/database calls.

## Initial capacity investigation (2026-10-18)

Isolated k3s Job, same production worker image and 1 CPU/512Mi limit; synthetic legal
bot input, 155-item test kit per player, 10 simulated seconds, no database/network:

| Rooms / players | Wall seconds | Codec batch p95 ms |
|---|---:|---:|
| 1 / 1 | 10.00 | 14.71 |
| 1 / 4 | 10.00 | 39.02 |
| 8 / 32 | 33.53 | 164.03 |

Codec batch covers all recipients at each 20Hz snapshot cycle. This shows a capacity
limit at eight full rooms on one CPU, not proof of the cause of solo phone lag.
Idle production samples had no backlog and negligible CPU throttling. Mac WebSocket
RTT was variable on both Tailscale and Cloudflare; device playback must be measured
with this instrumentation before assigning the remaining cause. Temporary benchmark
Job/ConfigMap/NetworkPolicy were deleted after collecting results.
