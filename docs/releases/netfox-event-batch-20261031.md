# Netfox reliable event delivery — 2026-10-31

Boss still reports lag after Netfox-only. LatestCourtyardreport confirmsNetfox, clocknetwork60387/reference60389, accepted174,rejected1startupframe,inputdelta-8,ping204ms; event/controlpackets161and106 in recentbuckets versus7–41inGate. This does NOT prove all latency caused by events. Inspection found service resent each unacked event individually every50ms over reliable RPC, multiplying work during delayed ACK.

Fix: connection-local reliable send highwater; up to32events/batch,4batches/snapshot, bounded by Wire frame and socketbuffer. Highwater advances only when queued; reconnect createsnew peer row withcursor0 so unackedevents are eligible again. Privacyfilter and clientACK dedupe retained; no gameplay/reward changes. Counters event_batches/event_records exposed in input_clock reports. Eventhistory retirement semantics unchanged.

Focused contract PASS100events/4packets, noACKresend, backpressure/failure noadvance, reconnectresends,privatefilter. ActualRoomsolo server+clientPASS movement/inputs0rejected. Fullsuite previouscutoverFAIL+timeout remains, noallgreenclaim. ActualWeb postpatch combat acceptance pending. Webcf4ac0c4dc0b unchanged.

Image: wiyazard:30500/zorx-room-worker:event-batch-20261031-1@sha256:b5cd17c0a0b128d71de8dc8d8d061b80debbea84ecfe07e7a871f1844f68fac3
Rollback: wiyazard:30500/zorx-room-worker:netfox-only-20261031-1@sha256:565c9a1931e26223e30e39c36a4a570cfa385e5fd64139efc3ba64d9110d3495
