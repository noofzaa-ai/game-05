# Input reference trace

Reference: room/player/epoch/input_tick; same input retransmissions keep the reference. Sample once per60tick (~1/s/player), client32samples/server4rows/player, reports latest6client samples. Never logs bearer tokens, names, inventory or command payloads. No additional RPC/input packet size, no client clock accepted as authority.

Client local times: raw input capture at advance_controls, scheduled tick creation, first successful WebSocket put_packet, repeated sends, response observation and first applied-state observation. put_packet acceptance is NOT NIC transmit. No browser onmessage/kernel timestamp claimed. callback_gap_max_ms is lifetime process-callback gap and may include tab/background/loading/dialog pauses.

Server local times: first received sampled input, worldtick/margin, queued/applied/late_rejected/future_rejected, used_ms, snapshot-prepared emitted_ms. Duplicate redundancy never downgrades applied to rejected. Samples epoch scoped. Worker snapshot is frozen, so trace is constructed before freezing; string keys required by codec. No new StringName fields on Wire.

Valid durations: capture→send on client, receive→apply on Worker, apply→snapshotprepare on Worker, client send→observation roundtrip. Never subtract server absolute timestamps from client timestamps. Transport remainder includes bothdirections, browsercallbacks, snapshotcadence andqueues; cannot identifyonewaypurelatency without clockoffsetbounds. No fake subtraction advertised as network RTT.

Trace is passive. Does not alter lead, AI, input acceptance, skills or damage. Existing return-to-camp save receipt and unspent-weapon source changes in workingtree are separately validated and must ship with matching Profile/Room logic if included in Web release. No fullsuitegreen claim; existing fixture issues remain.

Deployment: set image only, never apply staleheadless.yaml. LiveRoom memorylimit1Gi,CPU1;localbuild/k3s-fixed/headless.yaml still512Miandoldtags;preserveactualuser-editedlimits. Found liveimageshadrolledbackto20261021mummy-private/merchant-basket;restoreknownrecentbases andmatchedsourceinrelease. Capturedresources/images in build/input-trace-rollback-and-resources.txt. Do not overwrite resource requests/limits.

## Release identity regression, 2026-10-28
Kubernetes ReplicaSet history confirms receive-first headless-875bf68b7 creation at2026-10-27T23:07:17Z (28Oct06:07:17ICT), then old mummy-private/merchant-basket headless-7d648b6968 creation at23:37:57Z (06:37:57ICT), currentlyactive. This proves revision regression; it does not identify actor/command, exact pod cutover or every prior user report worker identity. Do not invalidate all historical tests or assert latest patches were never deployed. New sampled rows include worker_release from process environment to bind reports to worker version.
Native targeted input trace, receive-before-tick,20skills×90ticksWire(max15864B),finishedsaveack andunspentweapon pass. Fullsuite notgreen; actual Web gameplay latency acceptance stillpending.

Additional correctness checks: control_clock and remote_correction pass after trace instrumentation. Native checks verify correctness only. Exact Linux image initial trace contract passed; final candidate adds worker_release marker and is under recheck.

- RELEASED inputtrace20261028-1: Web0e89025318b2@11ed708f,Rooms@b30a5e19,Profiles@60fee3c0; headless669ddf5c78-9vkxt2/2,rollouts/digests/releasemarker/startup/publicmanifestverified. Allresourcesunchanged(Room1CPU/1Gi,Profile1CPU/512Mi). Native/exactimagecorrectnesspass;actualWebplayacceptancepending. build/input-trace-release.json. Needreload/newroom.

- 2026-10-28 Boss accidentally reapplied stale server manifest. Restored pinned input-trace images with setimage only; synchronized remote ~/deployment/game-test/zorx-staging/headless.yaml and game.yaml image lines ONLY, backup .before-image-sync-20261028.bak. Allotherbytes/resources/secrets preserved; no broad manifest apply. Rollout recheck inprogress.

## Actual Web report 0e89025318b2: worker identity confirmed
Inputtrace rows confirm input-trace-20261028-1. A/replayenabled,valid; epoch2 window600worldticks,93missingticks/93latepackets,3inputgapcorrections,379replayticks,0hard/8smooth corrections. Samples capture→put_packet0–1ms only; notproof all clientcallbacks timely.
| input tick | client capture→send ms | worker received→used ms | used→first observed snapshot-prepared ms | client send→applied observation ms | outcome |
|---|---|---|---|---|---|
| 1560 | 1 | 47 | 87 | 246 | applied |
| 1620 | 1 | 97 | 54 | 272 | applied |
| 1680 | 1 | 149 | 54 | 235 | applied |
| 1740 | 0 | 48 | 104 | 273 | applied |
| 1800 | 0 |  |  |  | late_rejected |
| 1860 | 1 | 45 | 20 | 103 | applied |
Workerqueue47–149ms for earlyinputs is target-worldtick scheduling, not proven CPUexecutiondelay. First-observed snapshot-prepared offset20–104ms is notproof worker withheld all earlier snapshots: clientcoalescesreceivedstates. Tick1800 sentimmediately,firstreceivedatworld1800→late_rejected confirms misseddeadline; sourceofpre-receipt delay (client/browser/transport/workerpoll) notyetisolated. No cross-machineclocksubtraction.
Controlfeedback uses rolling1sp10margin; sampled margins4→7→10→4→0→4 and rate1.05 oncurrentmargin_low−4 indicate variablelead/laggedfeedback, not proof oscillationcause. Inputtrace alone doesnotidentifyTunnelcause. Workerlastpoll17/lifetimemax99ms; clientcallbacklifetime4604ms cannotassigncurrentwindow.
Unexpected1:epoch2tick1286 skill.pose.skill clientnull/serverfire_ring atsameposition; actual skillpredictiondivergence needs targetedreproduction. Remoteinterpolation129underruns/898frames cumulative≈14.4%,needsarrival/snapshotvisibilitytimeline; no blanketFPSdiagnosis.

## v2 late packet capture
Fixed1Hzsample rows retained. Worker newestvalidINPUT observation with margin<=0 records8bounded events/player/epoch: packet_sequence,input_tick,arrivalworldtick,margin,receiveclock,priornewestarrivalgap,pollgap,release. Olderredundantnewest notdoublecounted; future/outofepochvalidationunchanged.
Client caches512inputcapture+512sentINPUTpacket records keyedtick/sequence, joins lateevents bysequence,retains12matches/epoch. Reports explicit client_found=false ifringexpired. Recordscontrols callbackgap, controls_batch (consecutivecallbacks<=2ms, NOT provenengineframeidentity), controls_burst_gap_ms (gapbeforethatgroup), previoussuccessfulINPUTsendgap,creation/capture/put_packet times. No new timestamps sentfromclient; Workerdoesnottrustclientclock. Sameclockonlydurations.
Eventrowsareboundedlast-N,notexhaustiveeventlog; packetburst>8beforelatestobservedsnapshotmayevictolderevents. Firstbadpacket canstillbeevicted,so donotclaimfullcoverage. Longgap+manytightcallbacks supportsproductionbatching;normalproductionwithchangedarrivalspacing supportsdelayafterputpacket butdoesnotdifferentiatebrowserbuffer/TCP/Tunnel/serverpollalone. Keepalive/ACK/gamesim unchanged. Profilesnotupdated.
Nativeunsampledtick18/sequence23contractchecksclient50msburstgapmatching,epochreset,dedupe,bounds/Wire;oldtrace/margin/receiveorder/Wirecontracts pass. ActualWebevidencepending.

- RELEASED passiveLatePacketTrace: Webc8952484f508@fd94f901,Rooms@c20a9645/late-packet-20261028-1,Profilesunchanged@60fee3c0. headless57c87fc5db-cstzd2/2;bothrollouts/startup/marker/publicmanifestverified,CPU/RAMunchanged,remoteYAMLimage-onlysynced. Native/exactimagecorrectnesspass;actualWeblatepacketdiagnosisawaitinguserplay. Report input_trace.version2/late_packets. build/late-packet-release.json.

## Real late-event evidence c8952484f508 (3 reports)
Same room1b7943a99f06406a9bf8f2eda56adfd6 epochs1/2/3, A, workerlate-packet1 confirmed. No disconnect/windowhard/unexpected.
| epoch/map | missing/worldticks | late newest packets | input-gap corrections | replay ticks |
|---|---|---|---|---|
| 1/goblin_arena_a | 134/602 (22.3%) | 122 | 3 | 55 |
| 2/goblin_arena_b | 131/598 (21.9%) | 118 | 7 | 426 |
| 3/goblin_arena_c | 113/605 (18.7%) | 102 | 9 | 67 |

Confirmed production gaps: epoch3tick3591/seq3603 controls_gap295ms and previoussuccessfulINPUTsendgap295ms, Workerarrivalgap299ms/pollgap17ms, margin−14. Followingseq3604–3610 created/sent1–3msapart, received0–15msapart andlate−13..−8; thenworldovertookreanchor/fill. This directlyproves a clientcontrolsproduction/sendpause before put_packet for thisincident. Doesnotidentifywhichmainthreadoperation/OS/browserbackground causedpause. Epoch1seq606/607 retains preceding346mscontrolsburstgap withbatch7/8 andlate−12/−11,consistentcatch-up, thoughfullburststarterevicted. Other55/79mssendgapsmatch66msarrivalgaps. Thisisnotmerelya lowFPSdiagnosis; the causalchainis noINPUTproduction→misseddeadline→heldfallback/correction.
Separate post-putpacket spacing distortion: epoch2seq2150tick2140 previousINPUTsendgap34ms vs Workerarrivalgap150ms,pollgap16,margin−3. seq2161tick2150 sendgap38ms vsarrival166,poll17,margin−4; followingpacketsarrive0–1msapart. Bothsameclockintervals,notcrossclockabsolute subtraction. Supports delay/batchingbetween successfulput_packet and applicationreceipt. DoesnotseparatebrowserWebSocketflush/TCP/Tunnel/OSsocketqueue/workerindividualpolltime. Globalworkerpollgap17 attheseeventsdoesnotbounddelayofallpriorpolls. Roundtripobservation134–309ms alsoincludesdownlink/mainthread/snapshotobservation;notpurenetwork.
Scope now twoconcrete paths, notwholearchitecture: (1) identifyboundedstage/input/networkcallbackwork immediatelybeforeclient295/346msgaps; respectbrowserforegroundstate, actualframegaptimeline. (2) trackafterputpacketflush/browserdeliverytoactualworkerreceipt onmatchingpacketwithoutchanginggamephysics. Avoidfixedlead+300ms tocoverpause, preserveinputIDs,donotpretendCPU/RAMortunnelaloneproved. Existing2tickmargin cannotcover295mspause; smoothercorrectiondoesnotrecovermissedbuttonedges. Noadditionalpatch/deployfromreportalone.

## Work scopes attached to production gaps (Web-only)
InputTrace owns InputWorkTrace bounded256completed walltime spans. Oncontrols gap>=40ms capture unioncoverage over[lastcontrols,currentcontrols], clippedintervals andlongest6scopes; parent/childdurations are NOT summed. Controlsburst inheritscontext. Packetcreation/trace andserverlogic unchanged. Longerunobservedgap couldevictscopehistory,so coverageislowerbound,notproofnothingexecuted.
Scopes: socket_poll,network_receive_decode_events,parentnetwork_poll_decode,reconcile,prediction_step_send,stageinput+aim,controlspredict,remoteviews+events,skill/VFX/projectiles/audio,fightervisuals,cameraHUDexits,parentstagephysics. Completedpriorwork isclippedatcurrentinput; currentcall'sfutureworknotincluded. Stage_process,fighter autonomousprocess,rendering,driverwait,GC,OS andotherunscopedcode remain outsidecoverage. `outside_instrumented_ms` explicitlydoesNOTmeanbrowserwasidle. `stage_physics_total`parentmaybeincludeschildreconcile;inspectchildscopes notadditive. WalltimeincludespossibleOSpreemption.
Browser: optionalbounded16 PerformanceObserverlongtaskrecords (featuredetected;Safari mayunsupported), visibility/documentfocus queriedatresume only. JSperformance.now/starttimes are samebrowserclock; donotsubtractGodotTimeorigins. Observercallbackdeliverymaylagmainthreadblockingtask,so absenceatfirstresume notproofnolongtask. Atresumevisibilitycannotestablishvisibilitythroughoutgap. No pagecontent/accountdataread.
No Worker/Profile change needed; retainRooms late-packet-20261028-1 andschema2latepacketmatch. New Webreportsclient.work_gapcontextonlatepackets. Targetedcontractverifiesnestedunion/clipping/burstretention/bounds/stagecompile. Initialtestduringeditingtimedoutfromstageindentation,correctedandfinalcontractpassed; no fullsuitegreenclaim. ActualWebdiagnosisstillpending.

- Workgapcandidate1Webb0cb23ba0fd8@ecdad317temporarilydeployed,notfinal: found<=2msburstcontextwoulddiscardprecedingpauseon3mscatchupcallbacksandserver8eventringcanomitfirstpacket. V2retainslastgapcontext500mswithwork_gap_age_msexplicit,so laterlatepacketscanstillreferencepausewithoutclaimingtheircreationitselfpaused. V2Webbuildongoing;worker/Profileunchanged.

Workgap finalcontext rule: retain latestgapcontextfor500ms even if consecutivecatch-upcallbacksexceed2ms. `work_gap_age_ms` is capturetime minusgapresume. A laterpacketreferringtopreviousgapdoesnotmeanthatpacketstalleditself; compareage/controls_gap/sendgap. Serverlast8canstillomitentireburst; nofullcaptureclaim.

- RELEASE COMPLETE work-gap-v2: Web2e5490007e8c@bbdedb3c;Rooms late-packet1@c20a9645/Profile@60fee3c0unchangedverified. Publicmanifest/rolloutverified;game.yamlimage-onlysynced,CPU/RAMunchanged. Passiveworkscopes+500msagedcontext+browseroptionalobserver. Targetedcontracts/JS mockPASS,actualWebworkgapdiagnosisawaitingplay. build/work-gap-release.json.

## Workgap actual Web reports 2e5490007e8c — user says INTERNET, not LAN
BothvalidA, mapgoblin_arena_c, sameepoch1;notcontrolledroutepair andmustnotcomparelatencydirectlyasTunnelcausalexperiment.
| report | ping app ms | missing/worldticks | late newest | gap corrections | windowhard |
|---|---|---|---|---|---|
| 1 | 152 | 313/610 (51.3%) | 320 | 2 | 0 |
| 2 | 132 | 71/595 (11.9%) | 71 | 0 | 0 |

Measuredwork evidence: report1gap41ms=9msunion+32msoutside;networkdecode4ms/reconcile2ms/stage3ms. Gap59=14union+45outside,decode7. Report2seq2887 controls118/send119ms vsarrival116;union11ms/outside107ms,decode5/reconcile3/stage3. This rulesoutthose measuredcallsbeingtheentire118mspause,notallpossiblemainthreadwork. No sampledlongVFXscope. Scopesoutside includeengine/render/othernodecallbacks/OSandbrowser; noassignmenttoGPU/GC/shader without evidence. Longtaskunsupportedfalse (cannotdeterminebrowserfamily);tasks[]isNOTnegativeevidence. Visibilityvisible;report2focusedfalsearound118msgapthenfocusedtrue,whichiscontextnotcausalproof/backgroundthrottlingclaim. Report1focusedtruealreadyhasothergaps.
Postputspacing: report1seq1313sendgap41 vsarrival167,then1/0msarrivals;seq1348send59 vsarrival149. Report2seq2869send4→arrival83,seq2921send53→arrival99. Same-clockgapcomparisonsconfirmdeliverybatchingremainsonInternet too. Cannotisolatebrowserbuffer/transport/workerreceiveorclaimallnetpurelatency. Workerpollgapcurrent16–17,lifetimemax101doesnotcharacterizeentireprecedingdelay. Appping132/152ms notpurenetwork.
Notresolved: actualdeadlinefailurewidevariation51.3%→11.9%undersamebuild;zero unexpected/windowharddoesnotmeanresponsivenessfixed. Stilltwo scopedpaths. Next meaningfulmeasurement should captureactualbrowser/engineframe phases/otherprocessing aroundout-of-scopepause and/or controlledmatchingtransport path;avoidmorebroadreplaytestsorclaimingVFXculprit. Noadditionalcode/deployfromreportsalone.
