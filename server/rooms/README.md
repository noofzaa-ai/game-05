# M4 online rooms

A Godot4.7.2 headless worker owns each room's GameSim, Journey, player Runs, RNG,
input queues and rewards. Nakama owns admission and atomic profile persistence.
The game has an explicit **เล่นออนไลน์** entry in the hub. Offline inventory and
TestKit never enter an online room.

## Runtime flow

1. Authenticate and reserve a character name; fetch its server-created profile.
2. Create a room (1–4 slots), copy its invite, or join an existing invite.
3. Nakama chooses the configured staging worker and returns a one-use30s ticket.
4. RemoteSession opens the returned WebSocket URL; the worker redeems the ticket
   privately against Nakama. User ID, slot, profiles and seed are never accepted
   from a game packet. The room starts once its configured capacity has arrived.
5. The worker runs60Hz fixed ticks and sends acknowledged binary state deltas20Hz,
   plus numbered events. Clients predict their own inputs and interpolate peers.
6. Route/camp/treasure commands run the existing Journey/Commands rules on the
   server. A finished room atomically commits all player profiles through Nakama.
   Retry cannot apply a second result. The cloud-saved flag follows commit ACK.

This staging version routes one configured worker (`staging-0`, up to8 rooms).
Do not increase replicas behind the same Service: each room is fenced to one
process nonce. Multi-worker scheduling/load measurements are later capacity work.

## Authority and failure bounds

- One process requests/limits1 CPU; this is not exclusive CPU affinity. Fixed dt
  is1/60, catch-up max5 ticks/frame, backlog>250ms aborts the affected room safely.
- Inputs bind to the redeemed slot and epoch, cover the newest+three previous
  ticks, and admit at most24 future ticks. Missing/disconnected inputs are neutral.
  Disconnect clears queued inputs. Played/replaced/far-future inputs fail closed.
- Rejoin the same account within30s for a fresh ticket/full state. A replacement
  connection supersedes the old one; the old socket cannot disconnect the new one.
- Leases renew every10s, expire60s; the worker stops on an unrenewed45s lease.
  A restarted worker cannot replay an old room. Expired started-room recovery
  applies the original death/wear rules once before unlocking that profile.
- Empty rooms expire30s; finished60s; route/camp inactivity300s. No crash-resume
  checkpoint is promised: a lost worker fails the run safely.
- Game frames max64KiB. Large states max256KiB, max8 fragments, max4 incomplete
  transfers and5s assembly timeout. Baselines/events/command receipts are bounded.
  A slow consumer is disconnected instead of accumulating unlimited output.
- Other players receive visible equipment and combat state, never peer stash,
  private rewards, simulation RNG or private backend credentials.

Exact wire fields are in `docs/tech/online_netcode.md`. `/rooms` remains a private
Bearer-authenticated control endpoint on8051; `/healthz` is readiness only.
Gameplay uses8060. The existing bounded private HTTP adapter is shared with the
name/profile worker, which runs in its own process.

## Local testing

```sh
python3 server/names/build_images.py
python3 server/rooms/build_image.py
python3 server/names/smoke_stack.py --rooms
python3 server/names/smoke_stack.py --rooms --long-run
# Native room worker for long-run QA on an emulation host:
python3 server/names/smoke_stack.py --native-rooms --long-run
python3 server/rooms/smoke.py
python3 server/rooms/smoke.py --image zorx-room-worker:m4-1-local
python3 -m unittest discover -s tests -p 'test_*.py'
```

The stack is disposable Postgres/Nakama plus separate profile/room workers.
The long probe uses two actual Godot SDK accounts, server-created starter gear,
legal bot movement/skill inputs, application delay75ms each way, jitter10ms and
loss2%, including reconnect. It fixes only the disposable room-layout seed for
repeatability; it does not inject client inventory, kills or damage boosts.
Logs/configs remain private under ignored `build/`; do not publish them.

For manual native play against the configured backend:

```sh
python3 tools/netcode/play_clients.py --clients 2 --delay-ms 75 --jitter-ms 10 --loss .02
```

Each window has a separate cached account (`qa1`, `qa2`, ...). Create/copy/join
from the online hub entry. F2 toggles frame/network metrics. Equivalent flags:
`-- --net-account=qa1 --net-debug --net-sim=75,10,0.02`.
The shim affects binary application packets, not TCP transport or server time.
Browser instances need independent browser profiles/site storage for distinct
accounts. Physical iPhone/Android and human combat-feel acceptance are separate.

## Boss's manual image/deployment workflow

Build scripts only build local images. Boss tags/pushes the three images and
obtains immutable RepoDigests: Nakama runtime, name/profile worker, room worker.
Use the same tested develop commit for the Web build and all images.

Generate the Nakama/profile overlay while retaining the existing validator token:

```sh
python3 server/names/deploy.py \
  --worker-image REGISTRY/PROFILE_IMAGE@sha256:PROFILE_DIGEST \
  --nakama-image REGISTRY/NAKAMA_IMAGE@sha256:NAKAMA_DIGEST \
  --reuse-secret build/k3s-remote/names-deployment.yaml \
  --room-ws-url wss://zorxapi.daiyooo.com/room \
  --output build/k3s-remote/m4-names.yaml
python3 server/rooms/deploy.py \
  --image REGISTRY/ROOM_IMAGE@sha256:ROOM_DIGEST \
  --networking --secrets build/k3s-remote/deployment.yaml \
  --output build/k3s-remote/m4-rooms.yaml
```

Both outputs are private0600 files. The room renderer extracts only the original
Nakama runtime HTTP key into a new Secret. It does not replace Postgres or the
original API/signing/DB Secrets, nor create a Mac dependency.
Copy the bundles to the k3s machine, review and apply **there**:

```sh
kubectl diff -f m4-names.yaml
kubectl diff -f m4-rooms.yaml
kubectl apply -f m4-names.yaml
kubectl apply -f m4-rooms.yaml
kubectl -n zorx-staging rollout status deployment/name-validator --timeout=180s
kubectl -n zorx-staging rollout status deployment/nakama --timeout=180s
kubectl -n zorx-staging rollout status deployment/room-worker --timeout=180s
```

The new `/room` Ingress uses the existing API domain, Cloudflare443 tunnel and
Traefik80; no new domain is required. Gameplay ingress is allowed from Traefik,
private control from Nakama; worker egress allows only Nakama7350 and DNS.
An old names bundle without `--room-ws-url` leaves room creation safely disabled.
No remote apply or registry image push is performed by these tools.

## M5/M6 release

Shared camp/Friends/ready HUD, private operations, stable process pool and load/monitor tools are documented in [online_release.md](../../docs/tech/online_release.md). Actual-device, target-i5 capacity and off-machine restore sign-off remain manual gates.
