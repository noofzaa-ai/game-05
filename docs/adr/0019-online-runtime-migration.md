> 2026-10-31: Boss ordered removing the legacy online path. Netfox-only is now deployed for every room. See [cutover release](../releases/netfox-only-20261031.md). Earlier opt-in/default-legacy notes below are historical.

# Online runtime migration

> สถานะล่าสุดและสรุปผลจากผู้ใช้: [สรุปออนไลน์หน่วง → Netfox (2026-10-28)](../tech/online_lag_netfox_summary_20261028_TH.md). หัวข้อด้านล่างเก็บประวัติระหว่างพัฒนา สถานะ “ยังไม่ deploy” ในย่อหน้าเก่าไม่ได้แทนสถานะล่าสุด.

Status: migration authorized by Boss 2026-10-28; design accepted for implementation by agent. Production cutover NOT complete.

## Problem and evidence

The current runtime has custom clock/rate feedback, prediction history, snapshot coalescing, world-tick input deadlines, remote interpolation and raw WebSocket transport coupled across StageView/RemoteSession/Room. Correctness patches reduced replay but actual Web still misses input deadlines and shows rubber-banding. Real packet traces prove both client production pauses and post-put_packet arrival batching. Neither FPS averages nor CPU/RAM usage identify all causes. A standard library cannot guarantee that an engine/browser pause or transport burst disappears.

Boss authorizes substantial restructuring and expects the agent to perform implementation, deployment, migration and testing. No player-account migration or gameplay balance changes are implied.

## Target ownership

| Component | Owns | Must not own |
|---|---|---|
| Godot shared simulation in logic/ | Fixed60Hz movement, combat/skill state transition functions | Nodes, rendering, RPC, database |
| netfox pinned runtime | Network clock, bounded input/state history, prediction/rollback scheduling | Damage policy, loot ownership, profile writes |
| Authority room | NPC AI/RNG, hit/damage/status, inventory commands, rewards and final persistence | Client animation-driven timing |
| Owner actor adapter | Prediction-safe continuation of local movement/skill phases; value-only state | Client-authored HP/loot; replay side effects |
| Remote entity adapter | Authoritative snapshots + interpolation of NPCs/other players | Mutating canonical simulation positions for rendering |
| Transport adapter | Godot MultiplayerPeer connection, admission and bounded peer/room routing | Assuming another user's room/actor authority |
| Client presentation | Input capture, animation, camera, VFX/audio deduplication | Clock correction, damage adjudication |
| Nakama/Profile/PostgreSQL | Existing authentication, trusted commands, persistence | Per-frame gameplay simulation |

One owner for each clock/history/position. Do not run old ControlClock and NetworkTime simultaneously for an actor. Do not reconcile old snapshots into a netfox-owned actor. No double interpolation.

## Dependency decision

Use netfox as the first integration candidate, pinned to v1.35.3, commit c7fc6ea52b4e9087c980d9ca1f8c3826e3a6caa4, MIT notices preserved. Source in tools/netcode/vendor/netfox-1.35.3 is currently isolated; NOT an enabled production addon. Upgrade only with the same compatibility/correctness gates.

Godot4.7.2 compatibility gate passed: library import/autoloads and synchronizer scripts load, NetworkTime60Hz calls actual production GameSim. This is ONLY API compatibility, not a network/latency result. Reproducible runner: python3 tools/netcode/migration/check_netfox.py; logs build/netfox-migration/. Do not ask Boss to test this gate as if it were a game room.

netfox expects Godot's multiplayer RPC peer model. It cannot be plugged into our raw ticket+Wire socket without an adapter/new gameplay endpoint. Rollback also requires complete continuation state; inserting a synchronizer around position alone would reproduce desync. Reference-type state must be copied or flattened, not shared across histories.

## Transport

First standard transport: WebSocketMultiplayerPeer behind existing TLS/Cloudflare ingress, using a new versioned gameplay endpoint. This keeps the existing reachable hosting setup. WSS is NOT claimed to be the final best latency path.

Admission remains Nakama-issued short-lived one-use room tickets. Unauthenticated peers cannot join replicated nodes, influence the clock, receive profiles/state, or send gameplay RPCs. Bind authenticated peer->room->actor on server; do not trust a client-provided actor ID. Limit handshake time, payload size, input rate/future history and room capacity. Disable object deserialization. Avoid sending other rooms through global RPC broadcasts; use visibility and room-scoped multiplayer roots. Evaluate library time-sync/RPC surfaces as part of this gate.

WebRTC remains a replaceable transport option, NOT a parallel rewrite of gameplay. Native server WebRTC requires its native extension and connection infrastructure (signaling/STUN/TURN as needed). No public-IP, TURN expense or different hosting silently assumed. ENet raw UDP cannot serve the current browser clients. SSE does not supply the bidirectional unreliable gameplay channel this needs.

## Continuation/state contract before rollout

- Separate server/world tick from per-peer input receipt and simulation history labels explicitly.
- Define one versioned owner actor continuation including all movement/combat/skill-phase values read by predicted transitions; exact float/value capture, no mutable reference aliasing. Include externally imposed hitstun/knockback/status events with stable IDs.
- Clients predict cast/phase/root motion/cooldowns only after shared parity exists. Actual damage, projectile hits and target statuses remain authoritative. Current owner skill prediction only supports blink completely; this is an OPEN migration item, not full skill parity.
- Replay must not create sound/VFX/RPC/profile writes. Presentation events use stable epoch/actor/cast/event IDs and freshness.
- NPC AI, hidden RNG and economy never run as client authority. Remote actors render authoritative interpolated states. Headless world simulation remains server-owned.
- Every build report includes Web content hash AND immutable worker release identity/protocol version. Resource manifests on k3s must be synchronized with the deployed images, not left on old tags.

## Execution order and exit gates

1. **Library/API gate (DONE):** exact version pinned, license retained, Godot4.7.2 import and actual shared-sim tick compatibility pass. No performance claims.
2. **Actor contract/adapter:** explicit value-only continuation; restore/replay parity using production character, actual equipment and skills. Missing fields fail the gate. Separate incoming authority events from unexpected divergence.
3. **Authenticated real-room vertical slice:** new endpoint, real Room content/AI/terrain, existing login/profile, original Web UI and manual controls. Movement/dash/basic attacks first, followed by every equipped skill/Gem. No synthetic scripted room used as substitute for user-play acceptance. Internal scripted tests are correctness checks only.
4. **Co-op/authority:** two actual browsers see the same other player/NPC/hits; rooms cannot see/control each other; reconnect/scene epoch/save acknowledgement verified. Forced pauses, packet delays/bursts and loss must stay bounded and not duplicate one-shot actions or rewards.
5. **Web acceptance and profiling:** record real browser performance timeline (not just custom scopes), plus packet references. Compare actual perceived pullback/action latency, missed/late inputs, correction reasons/distances and remote interpolation starvation under the same content/scenario. FPS is supporting context, not the user's responsiveness criterion. Changing to netfox does not waive this gate.
6. **Production cutover:** deploy matching Web+Rooms versions, synchronize host manifests and retain image rollback; preserve profiles/items/resource settings. Remove legacy paths only after real play acceptance and reconnect/persistence parity. No permanent accumulating A/B/C code in the final player UI.

## Implemented foundation

- `logic/net/actor_continuation.gd`: immutable value-only actor history, fixed schema/version/size, exact body/fighter roundtrip, validation before mutation. Native actual GameSim tick replay parity passed, including malformed fields/nonfinite/wrong actor/typed-array rejection. Private skill runtime is not yet included and remains OPEN.
- `tools/netcode/migration/actor_bridge.gd`: isolated adapter lets netfox RollbackSynchronizer drive the production GameSim. Network ticks explicitly set simulation tick labels, rather than incrementing unrelated clocks during replay.
- Local two-process protocol contract passed: client-owned input reaches server, actor state travels back through netfox RPC. This checks integration, NOT Web gameplay/latency or account admission. No production endpoint is opened.
- Initial sandbox socket denial was distinguished from code failure; final localhost-enabled checks passed. Initial snapshot check exposed Vector2i facing omission in validator, fixed before accepting roundtrip.

## Current concrete result

Compatibility runner and pinned source are in the workspace. build/netfox-migration/compatibility.json records PASS on Godot4.7.2. Production remains Web2e5490007e8c / Rooms late-packet-20261028-1; no new runtime has been deployed and the lag incident remains OPEN.

## Primary references

- https://github.com/foxssake/netfox/tree/c7fc6ea52b4e9087c980d9ca1f8c3826e3a6caa4
- https://foxssake.github.io/netfox/latest/faq/ (latest docs can differ from release; consult pinned source)
- https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html
- https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html

- FinalnetfoxintegrationgatePASS20261028: actualserveractorx14.7567/client14.6934(unclamped100mworld),clientauthoritativestate_tick280;all4import/clock+rollback/serverRPC/clientRPCchecksPASS. This islocalhostAPIcontractonly,notWebperformance. FoundationreadyfornextauthenticatedrealRoomintegration;productionnotchanged.

### 2026-10-28 — active integration (NOT production cutover)

- Pinned addons copied into `addons/netfox*`; autoload clocks remain inactive until a v2 session/service starts. `?netfox=1` selects v2; default and existing A/B/C remain legacy during acceptance.
- `runtime/netfox/` provides client input ownership, bounded transport adapters, immutable full actor continuation and library rollback histories. Authority world is NEVER restored/replayed; `Room.tick()` remains sole damage/AI/economy authority.
- `server/rooms/netfox/` shares existing trusted redeem/start/heartbeat/finalize fences via a lease adapter, uses SceneMultiplayer authentication, room-scoped visibility and a receipt inbox. Inbox accepts late action edges once; its counters are separate from old world-tick missing counters.
- V2 continuation includes owner skill caster/jobs/cooldowns, combat-only target context; no bag/profile/credentials. 235 compatible skill/Gem cases x120ticks passed phase/cast/stamina/position and midcast restore. This does not prove live hostile-target parity.
- Actual RoomManager + new session connected in native localhost solo and 2-client co-op, inputs and authoritative state advanced. A fixture backend supplies admission only; not account/persistence or Web acceptance. Logs in `build/netfox-migration/`.
- Found/fixed metadata alias overwriting predicted actor, pre-connect peer assignment, server rollback notification leaking old input tick, and state publication missing simulated-node notification.
- Wire-only compression adapter and delayed remote presentation added after those passes; revalidation still required.
- Main suite currently has fixture failures (ownership/profile/account/co-op checkpoint) and exceeded timeout. No all-green claim.
- OPEN before cutover: reconnect/epoch/command persistence, peer isolation/malformed RPC, exact Linux image, actual browser/account session, WAN correction and NPC contact behavior. New runtime NOT deployed. Existing release remains Web2e5490007e8c / late-packet room image.

### Follow-up gates
- Skill graph restore now reuses unchanged topology instead of rebuilding casters/signals every rollback tick;235skill/Gem cases revalidated PASS. Wire compression occurs only during transmission; local history retains immutable raw values.
- Native reconnect and epoch switch gates PASS. Fixed reconnect-ready flag, NetworkTime restart, peer visibility before replica-ready, and stale epoch traffic using suspended receivers during a bounded2s drain. Co-op2clients PASS; this remains an internal correctness gate.
- Linux general smoke reached private-auth/maintenance and real two-room creation, but existing duplicate-room fixture expectation failed; full smoke NOT green. Exact new transport Linux gate is separate.
- Test runner previously omitted stage_changed->scene_presented and bound a container fixture to loopback; repaired fixtures, not gameplay fixes. Never count timeout rounds as performance results.

### Candidate deployed — 2026-10-28 (migration still OPEN)
Web build `a05e76925f10`, image `zorx-web:netfox-20261028-1@sha256:9f071cef57998a2a99b18abbdc1865451e896ff2287fe9e1ee76256f72ec2c63`; Room `zorx-room-worker:netfox-20261028-1@sha256:43107a1ba9ff0ca28e78664bef27a1cd394b17a013fd2bc59a1c52a897ec5ebd` on existing registry. Profiles/Nakama unchanged. Remote headless/game image lines synchronized with backups; resource settings preserved.

`https://zorxplay.daiyooo.com/?netfox=1` selects the new actual Room endpoint `/room-v2`; no synthetic/lab room is used by that URL. Normal URL still selects legacy session pending acceptance. Public manifest and HTTP1.1 WSS101 verified. Native co-op/reconnect/epoch and235skill/Gem contracts passed; these are not Web play acceptance.

**Important negative evidence:** emulated amd64 Linux gate connected and exchanged state but rejected185 input packets, so behavioral acceptance is NOT green (the initial runner's overly weak PASS was corrected). Full suite remains non-green with fixture failures/timeout. Do not claim migration/lag resolution complete.

Web acceptance blocked by stale Mac API hosts mapping `192.168.1.99 ... # zorx-lan-api-test` while LAN SSH times out; Tailscale works. sudo unavailable; user asked to remove the marked mapping and flush DNS. Native browser control reached Safari, but no accepted gameplay session on the new release was verified. Optional LAN TLS route addition was rejected by automatic approval as an exposure/security-boundary change; no TLS/key change was made. Public route is the fallback.

Release/rollback details: `build/netfox-migration/release.json`. Next: actual browser account gameplay -> collect v2 report/input rejection/contact behavior -> address failures -> verify account save/return/reconnect -> only then change default and remove legacy production clock/history.

### 2026-10-28 follow-up from Boss actual Web reports (candidate3)
`boss-current-report.txt`: practice_field world tick1, cloud saved/finished, prediction0. Root cause: Room.tick automatically cleared a zero-monster practice stage. Guard only practice_field from automatic victory; preserve death and normal combat victory. Lifecycle regression passed 120 movement ticks, remains active, death finishes, cleared combat finishes.
`boss-combat-report.txt`: normal goblin room accepts154 inputs but prediction898 ticks costs4.7932s; client reference404747 vs network404508, pong age7490ms. Confirms long main-thread/network-scheduling backlog in that run, not an input-rejection-only issue; no claim of pure network latency or FPS root cause.
Candidate3 adapter resumes completed owner history only when no newer authoritative tick and no mutation; fresh authority still uses standard netfox restore/replay. No tick-ID skipping or relaxed validation. Quiet-state actual Room native contract PASS (2s publication pause,410 redundant replay ticks avoided, inputs339 accepted/0 rejected). This is correctness evidence, not Web lag acceptance. Two-client behavior passes movement/input/state, but server gate still flags one internal closed-WebSocket send at teardown after adapter send guards reduced prior repeated errors; do not call full co-op gate green. Native solo earlier failed on heavy-load history/close warnings; retained logs.
Web build18fcd0ff74fe ready, deploy pending at this entry. Includes smaller v2 report to retain clock/input evidence under2000 characters. Runtime close-peer send guards are server-only extra changes in Rooms candidate3. Normal URL stays legacy; no migration completion claim.

- Candidate4 clock fix: deterministic old pause-clock drift+26/-28ticks after2s stall; active addon scheduler phase patch gives2ticks bothcases. Actual Room native pause case PASS after1.4s stall: client tick/reference553/553, accepted330,0future/past rejections (one startupframe rejection). Web288ff8cb2bbc built; image push/deploy in progress. This fixes proven scheduler defect; does not establish all lag solved. Vendor untouched, documented local patch.

- Candidate4 ACTUAL SAFARI practice report captured (`build/netfox-migration/web-real-practice-4.txt`): NetworkTime10300/reference10301, latestserver10285/reference10284; accepted1188, consumedactions2, rejected frame1+past_history6, **future_window0**; prediction2034ticks/2.361s, redundant replay avoided2709ticks. Practice remains active(worldtick1181), movement/dodge/skill visuals observed; this validates removal of permanent future-tick phase error in that run. Six old-history packets and RTT229ms remain; no claim all lag/normal-combat/co-op acceptance complete. Candidate3 prior actual run accepted68/rejected1273future, network4050/reference4009. Different elapsed windows: raw counters are not a paired performance benchmark.
