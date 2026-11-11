# Movement synchronization patch (2026-10-27)

Goal: stop input stalls/rubber-banding under delayed authoritative snapshots. FPS is not the acceptance criterion. User reports WSS receive/discard and socket-closed modes feel smooth; applying authoritative state feels worst. Diagnostic A previously disabled historical replay and could itself induce pullback; it now uses the actual production prediction/replay path. This distinction must be retained when interpreting previous reports.

Code findings and fixes:
- `_step_impl` used `latest_snapshot.tick + 24` as a hard stop, even while worker clock kept advancing. Use bounded elapsed time + one-way app RTT estimate for the input scheduling ceiling. Do not claim application RTT is pure network latency.
- `_accept_state` clamped target back to `snapshot.tick+18`, risking reuse of already sent tick IDs. Targets stay monotonic within an epoch; stage change still resets.
- Scheduling lead changes could create unsent gaps. Fill only missing future tick slots with held move/aim/run/guard; never repeat edge-triggered attacks, jumps, dodges or skill casts. Existing queued ticks are never rewritten. Wire protocol4frame limit and worker24tick validation unchanged. Snapshot replay remains based on snapshot world tick; ACK is not treated as an earlier world state.
- Small residual movement corrections <=0.75m are presentation-only offsets decayed over100ms. Simulation/collision bodies, HP, combat, rewards and persistence remain authoritative. Forced hitstun/down/death/knockback and large corrections reset offset immediately. Camera follows the visual local actor. Other actors unchanged.
- Normal Lag report adds movement_sync counters; diagnostic A labels Replay ON, B/C retain their independent local-sim isolation behaviour.

Correctness evidence (native only): actual Room input queue + production RemoteSession with deterministic300msRTT and TCP-ordered snapshot jitter: original54stationary ticks/54missingworkerinputs during held walk; patched0/0, no backward ticks/positions.5weapon x240local-only prediction parity passes. Held padding does not repeat one-shot actions; visual position smoothing leaves authoritative body exact and does not mask forced hitstun. A/B and C control regression tests pass. No actual browser movement acceptance yet. No claim to eliminate network transit time, all corrections or every cause of lag.
