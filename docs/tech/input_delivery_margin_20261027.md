# Server-measured input arrival margin

Replaces the flawed b51 accumulator feedback: target-latest snapshot contains inbound transit/age and must not control send-ahead rate. Worker observes newest tick ONCE per validated INPUT packet, not its redundant frames; ignores same/older newest tick, rejects out-of-window future tick. Store at most128samples/1second per player, epoch scoped. Snapshot delivery includes p10margin, samplecount, packetlate cumulative, sequence, age and polling-observed packet-gap p50/p95/max. These times are Worker receive/poll times, not NIC timestamps; they cannot alone attribute delay to Cloudflare.

Client only updates from newer feedback sequence. Margin target2ticks; ±5% rate, late-newest =>1.05, margin2=>1, excessmargin slows. Feedback older1.5s/measurement older1s =>neutral1.0. FixedDT, monotonicinputIDs, edgequeue unchanged. desired_lead_ticks retained as legacy bootstrap heuristic only, explicitly labelled. Rebase does not normally change target; firstRTTseed/worldclockovertake explicitreanchor traced in input_schedule, held-only fills unchanged.

Transport size audit: previous snapshot carried32verbose input audit entries even during sustained late packets, growing state size. Reduce wire recent trace to8 while retaining32server-side. Adds compact delivery metrics, no new entity/interpolation payload. Unexpected corrections retained separately last4 in client report (never sent by Worker); window adds missing-inputticks/late-newestpackets/inputgapcorrections, avoiding cumulative/window confusion.

Native contracts validate stale-snapshot cannot slow lateinput, redundant packet newest not doublecounted, margin2stable, stalefeedbackneutral, actualRoom300msRTT+jitter/RTTdrop0reverse/0missing/0tickIDregression. Wire20skillsx90ticks pass max15546beforelivearrival traces. Actual browser subjective acceptance and Tunnel-vs-direct route comparison remain OPEN. No Tunnel config/VPS change or unsupported causal conclusion.

## 2026-10-28 arrival_recent_v2 (supersedes rate rule above)
Actual Web trace on0e89025318b2/input-trace worker: early margins4,7,10 followed by late0; tick1680 waited149ms for its worldtick. A stale p10=-4 / newlatest10 / latecounterincrease reproducibly selected1.05 under oldcontroller (build/margin-overshoot-before.log). This proves a controller branch error, not that it caused every live latency spike.

Worker retains1sp10 as diagnostic, adds margin_latest (last accepted newest-packet observation), margin_recent (median of observations over200ms), margin_recent_samples. Epoch and monotonic packet dedup unchanged. Client rate uses recent median relative to2ticktarget; newest>=6tickarrival always brakes even if prior latecount increased; newest<=0 still catchesup at1.05. Rate limited0.95–1.05; feedback measurement age plus elapsed time since reception >1000ms neutralizes stale feedback. Old-worker fallback still uses margin_low for compatibility during rollout. No snapshot-relative lead rate control.

SimulationDT, input IDs, queued one-shot actions, hitrules,AI,interpolation andsnapshotcadence unchanged. No rewind of live tick IDs. Small±5% scheduling adjustment cannot eliminate sudden browser/network stalls; actualWeb missing/late/correction and observedtrace queuewait remain acceptance criteria. Future work on remote snapshot delivery or skillpose divergence must remain separately measured.

Correctness: reproduced oldFAIL; updated regressionPASS using actualRoom generatedmetrics (oldtail−4/latest10/recent10), late recovery,targetsteady,composedage. Existing inputmargin/clock pass; actualRoom scheduled300ms+jitter andRTTdrop pass0reverse/0missing/0IDregression;20skills×90ticksWire15878B max. Native results do not establish Web latency improvement.

- RELEASE COMPLETE margin-brake-20261028-1: Weba3ab761b5fc9@64a96ddd +Rooms@94ebb5fd,Profilesunchanged@60fee3c0. Bothrollouts/publicmanifest/Roomsmarkerverified;allCPU/RAMunchanged. Remoteheadless.yaml/game.yamlimage-onlysyncedwithbackups. ActualWebgameplayacceptancepending;comparemissing/600ticks(last93),samplemarginrange/workerwait,corrections. build/margin-brake-release.json.

## Actual Web margin-brake follow-up (a3ab761b5fc9)
Both valid A/replayenabled, worker margin-brake-20261028-1 confirmed from trace. Same room epoch2→3, not controlled paired before/after.
| map | missing/world ticks | late newest packets | input-gap corrections | replay ticks | hard corrections in window |
|---|---|---|---|---|---|
| goblin_arena_b | 119/577 (20.6%) | 113 | 4 | 190 | 0 |
| goblin_arena_a | 214/598 (35.8%) | 205 | 21 | 224 | 0 |
Prior report93/600=15.5%; new20.6% and35.8%. Cannot call gameplay fix successful. Updatedcontroller active:recent2/latest4/rate1.0 and recent3/latest4/rate.99. Latest sampled applied arrivals2–5ticks (epoch3all2–3), workerwait14–65ms (epoch3 17–33), observation75–274ms (epoch3 75–125). Earlier unbounded samplelead10/149ms notseen inthese samples, but no pairedproof allvariationgone.
No disconnects,unexpected0. Windowhardsnap0, yet inputgapcorrections4/21 and smoothing10/26. Smooth doesnotmean inputproblemfixed. Epoch3remoteunderrun112/1245≈9%cumulative, notwindowcount.
2tickarrivaltarget≈33ms is less than some inputproduction callback intervals. StageView generatesinput fromphysics callbacks; browser may execute several catch-up physics ticks inone renderiteration and emitpacketbursts. This is a code-backed hypothesis for misseddeadline, NOT proof that rendering/CPU or Tunnel causes all lateness. Newestpackets themselves late113/205, so cannotexplainonly redundant olderframes. Need retain bounded eventtrace of actual late newest packets (not1Hzsampling), matching clientpacketseq and inputticks: previousinputcallback gap, numberinputticks inburst, clientcreation/sendtime, Workerarrival worldtick. This discriminates production gaps vs delayafterputpacket without cross-clocksubtraction. Do not silentlyincrease fixedlead orreworkAI/snapshotcadence before evidence.
