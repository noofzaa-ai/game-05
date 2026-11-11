# Goblin ground + Netfox sync — 2026-10-31

Boss superseded prior ground deployhold and requested coordinated map/lag runtime release.

Build a3f120128320 directly over Netfox-only cf4ac0c4dc0b. Web wiyazard:30500/zorx-web:ground-netfox-20261031-1@sha256:426481ba11350bd5968d7477b72be0b3af31793e597782a69a91545ac4113713. Room event-batch-20261031-1 digestb5cd17c remains unchanged. No old runtime restored, map gameplay JSON/collision/rewards unchanged. Ground5scenes+duplicatefloorvisualhelper only. Download +198139B, all unrelated core/packs byteidentical. Native actual shipped compiled StageView with newwrapper/helper finalscenes PASS5maps, PC/mobilelandscape. Screenshot /tmp/zorx-goblin-ground-release/ground-844.png. Initial sandboxGUI run emitted nooutput, ignored; actual native elevatedrunEXIT0+PASS retained /tmp/zorx-ground-netfox-release/ground-check.log. Fullsuite prior failures remain, no fullpassclaim.

Lag: latestBossreports stillworker netfox-only, beforeeventbatch. Currentcandidate does not establish latencyfixed; event duplicate/burst code defect addressed separately, boundedinput/clock symptoms need actual postpatchreport. Authoritative diagnosis refs docs/releases/netfox-event-batch-20261031.md. No syntheticFPS result substituted for player responsiveness.

RollbackWeb feed9f96 Netfox-only image. image-onlygame.yaml backup retained. Profiles/Nakama and workerunchanged.
