# Player Lag report

A small button to the right of ULT captures the previous ten one-second buckets in memory.
Press after a hitch; it sends through the existing authenticated Feedback RPC,
visible under Admin Feedback with prefix `[LAG REPORT v1]`.

Each bucket records frame count, summed/max wall-clock frame interval, intervals
above50ms, network poll/reconciliation CPU time, input prediction step CPU time,
decoded states, reconciliations and correction count. Frame intervals include
browser suspension. Poll may call idle step: poll/step timings overlap and must
not be added. GPU/GC/render are not directly measured or attributed.

Reports also contain current application echo RTT/age, prediction lead, map,
epoch, loading flag, viewport, platform and source commit. No screenshot, full
inventory, browser URL or credentials. Server assigns authenticated identity/time.
No automatic upload or console logging. At most ten buckets; report <=2000chars.
Existing Feedback one-minute quota is shared. Retry preserves request ID/body;
success or rate limit starts local60s cooldown. Scene teardown discards unsent
in-memory reports. This is client-reported diagnostic data, not trusted gameplay.
