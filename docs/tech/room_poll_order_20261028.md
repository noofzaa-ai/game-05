# Worker input receive order

Latest LAN Web report8de:48msappRTT yet214latenewestpackets/231missingworldticks in10s;inputarrival p50=1ms/p95=145ms/max167ms. NoCPUquota throttling inliveRoomscgroup: nr_throttled=0/throttled_usec=0,quota1core. Does not rule out host scheduling/browserstalls ornetworkjitter. No measured directroute RemoteAddress bundled in report;LANclaim userprovided.

Confirmed code-order issue: Worker `_process` previously advanced simulation before draining socket input. A packet already waiting for nextworldtick could be rejected after thattick had advanced. Split transport receive/maintenance from flush_states; neworder receive→fixedworldtick→snapshot/after_tickecho. Defaulttransport.poll retains receive+flush behavior forcallers. No tickrate/inputauthority/CPUquota/renderchange.

Contract uses queued binary INPUT through actual Transport parsing/Room admission, not directroom.input: oldorder tick1 ACK0/missing1;neworder tick1ACK1/missing0;post-stepstate tick/ACKverified. Native correctness only, not live latency acceptance orrealnetwork performanceproof.

Worker adds lastpollgap and lifetime maxpollgap toexisting deliveryfeedback; no auth/state payloads oruser IDs. Compare inputpacketgap with Workerloopgap;cannot infer browser-versusnetwork frompacketgapalone. Lifetime maxmayincludeidle/startup;lastpollgapmorelocal,neitherwholewindowp95.

Checked upstream Godot websocket implementation: accept_stream already setsTCP_NODELAY. Do NOT claim missingexplicitset_no_delayinourcode isrootcause orshipredundantfix. https://github.com/godotengine/godot/blob/master/modules/websocket/wsl_peer.cpp . This sourcecheckisnotversion-pinned4.7.2binarytrace.

OPEN:147–167msbursts cannotbeexplainedbyone60Hzlooporderalone;latestbrowsermaxframe281ms can delay inputemission butnotprovenaligned. B/Cfeel andvisualhitboxmisalignmentstillneedactualevidence. Patchonlyremovesknownavoidableworkerwait;doesnotclaimalllagresolved. Workeronlyrelease,Webbuildstays8de2c27815b7.
