# k3s release checklist (from the Windows dev machine)

Owner: release-manager. Written 2026-11-13 for Boss's "prepare to deploy to k3s".
Rules: this Windows machine builds and pushes; **nobody SSHes into the k3s node**. Cluster changes go
through `kubectl` on this machine with a kubeconfig Boss provides. Every rollout uses an immutable
`repo@sha256:...` digest, and the previous digest is recorded first so rollback is a single command.

Scope: internal staging (`zorx-staging` namespace) on our own k3s. There is no storefront or
console certification (web game on our own host), so that part of the generic `/release-checklist` is omitted.

## 0. Boss must do (one time)

- [x] Install Docker Desktop (done 2026-11-13, 29.9.2, per-user install). The CLI is at
      `%LOCALAPPDATA%\Programs\DockerDesktop\resources\bin` and is **not on PATH** in Git Bash. Add it:
      `export PATH="/c/Users/wanwi/AppData/Local/Programs/DockerDesktop/resources/bin:$PATH"`.
- [x] **Registry access** (done 2026-11-13: `192.168.1.99:30500` and `wiyazard:30500` in insecure-registries; push verified. Use the IP if the name does not resolve). `wiyazard:30500` is a plain-HTTP registry. In Docker Desktop -> Settings ->
      Docker Engine, add `"insecure-registries": ["wiyazard:30500"]`, then Apply & restart. This machine
      must resolve and reach `wiyazard` (Tailscale/LAN): `curl http://wiyazard:30500/v2/` should return `{}`.
- [ ] **kubeconfig** (kubectl installed 2026-11-13 at `%LOCALAPPDATA%/Microsoft/WinGet/Packages/Kubernetes.kubectl_Microsoft.Winget.Source_8wekyb3d8bbwe/kubectl.exe`; API `https://192.168.1.99:6443` answers 401, so only the kubeconfig is missing). kubectl + kubeconfig on this machine (`winget install Kubernetes.kubectl`, plus a kubeconfig
      for the k3s API, limited to namespace `zorx-staging` if possible). Without this, step 5 cannot run
      from here, and the only other route is someone running the commands on the node (which Boss
      ruled out).
- [ ] Tell us the **web Deployment/container names** in `zorx-staging`. The web manifest (`game.yaml`)
      lives only on the node and is not in the repo. Once kubectl works, read them with
      `kubectl -n zorx-staging get deploy -o wide` instead.
- [ ] Private secret bundles are needed for the server renders: `build/k3s-remote/deployment.yaml` and
      `build/k3s-remote/names-deployment.yaml` (never committed). Only needed when re-rendering
      names/rooms manifests; an image-only update does not need them.

## 1. Preconditions (each release)

- [ ] Build from a tested `develop` commit (Boss policy 2026-10-17). A `-dirty` tag means local changes;
      do not ship a dirty build to prod.
- [ ] Nobody else is mid-edit in `logic/`. Server images copy **all of `logic/`**, including untracked
      files, and a half-written script breaks the worker at startup (seen 2026-11-13, see section 8).
- [ ] Full suite green, with a timer and stderr checked:
      `"$GODOT_BIN" --headless --path . --script res://tests/run_all.gd`
- [ ] Shell: **Git Bash**, with `GODOT_BIN` set to the console Godot:
      `export GODOT_BIN="/c/Users/wanwi/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe"`
- [ ] Python: use `python` (3.11). `python3` on this machine is the Microsoft Store stub. The `.sh`
      scripts now pick a working interpreter automatically (`PYTHON=` overrides). For direct calls
      use `python -X utf8 ...`.

## 2. Build (all local, nothing leaves this machine)

```sh
cd /c/Users/wanwi/orca/workspaces/game05/game-05
export PATH="/c/Users/wanwi/AppData/Local/Programs/DockerDesktop/resources/bin:$PATH"
export GODOT_BIN=...   # see above
TAG="$(git rev-parse --short=12 HEAD)-$(date -u +%Y%m%dT%H%M%SZ)"

# Web: import, tests, export, split, pack (no 15 MiB cap on our own host)
./pipeline/build_web.sh --max-file-mb 0
./pipeline/build_web_container.sh --image "wiyazard:30500/zorx-web:$TAG"

# Rooms worker (Godot headless; downloads the official Linux Godot once into build/names-binaries)
python -X utf8 server/rooms/build_image.py --image "wiyazard:30500/zorx-room-worker:$TAG"

# Name/profile worker + Nakama runtime (needs Node/npm; npm test currently fails, see section 8)
python -X utf8 server/names/build_images.py \
  --worker-image "wiyazard:30500/zorx-name-validator:$TAG" \
  --nakama-image "wiyazard:30500/zorx-nakama:$TAG"
```

Only rebuild what changed. Web and rooms change with almost every game change. The profile worker
also changes, because it runs `logic/` and `data/`, so rebuild it whenever profile rules or data change.
Nakama changes only when `server/names/runtime/` changes. Landing (`pipeline/build_landing_container.py`)
needs the sibling `zorx_web` checkout, which is not on this machine.

## 3. Local verification (before any push)

- [ ] Web image serves correctly:
      `docker run -d --name zorx-web-check -p 127.0.0.1:8070:8080 <web image>`, then
      `curl -sD- -o/dev/null http://127.0.0.1:8070/<path>` for each path in the table:

      | Path | Expect |
      |---|---|
      | `/`, `/play.html` | 200 `text/html`, `Cache-Control: no-cache` |
      | `/packs.json` | 200 `application/json`, `no-cache` |
      | `/index.js`, worklets | 200 `application/javascript`, `no-cache` |
      | `/engine.<hash>.wasm`, `/<pack>.<hash>.pck.wasm` | 200 `application/wasm`, `public, max-age=31536000, immutable`, **no** `Content-Encoding` (body starts `1f 8b`; the loader unwraps it) |
      | `/healthz` | 200 `ok` |
      | missing pack | 404 (never an HTML 200) |
      | `/config/npc_guides.json` | 404 locally (on k3s it comes from the `zorx-npc-guides` ConfigMap mount) |

      `docker inspect --format '{{.State.Health.Status}}'` should report `healthy`. Remove the container afterwards.
- [ ] Rooms image: `python -X utf8 server/rooms/smoke.py --image <rooms image>` -> all PASS, stderr empty.
- [ ] Name/profile worker process: `python -X utf8 server/names/smoke_worker.py --godot "$GODOT_BIN"`
      -> 10 PASS (includes the new-player `/profile` check).
- [ ] Open `http://127.0.0.1:8070/` in a browser and reach the hub. This checks the boot packs and
      the battle-pack background fetch.

## 4. Push and record digests

```sh
for img in zorx-web zorx-room-worker zorx-name-validator zorx-nakama; do
  docker push "wiyazard:30500/$img:$TAG"     # only those you rebuilt
  docker image inspect --format '{{index .RepoDigests 0}}' "wiyazard:30500/$img:$TAG"
done | tee -a build/pushed-images.log
```

For web only, `./pipeline/deploy_k3s.sh --tag "$TAG"` does build, package and push in one step. It
appends `time, commit, tag, repo@sha256` to `build/pushed-images.log`.

## 5. Roll out (kubectl from this machine; image-only, never a broad apply)

History (docs/tech/input_trace_20261028_TH.md): re-applying stale full manifests rolled back images and
resources. Default to **`kubectl set image`**, and only change what was rebuilt.

```sh
NS=zorx-staging
# 5a. Record what is live now (this is the rollback point)
kubectl -n $NS get deploy -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.template.spec.containers[*]}{.name}={.image}{" "}{end}{"\n"}{end}' \
  | tee "build/k3s-before-$TAG.txt"
# 5b. Image-only updates (names from 5a; use the @sha256 digests from step 4)
kubectl -n $NS set image deployment/<web-deploy> <web-container>=wiyazard:30500/zorx-web@sha256:...
kubectl -n $NS set image deployment/name-validator name-validator=wiyazard:30500/zorx-name-validator@sha256:...
kubectl -n $NS set image deployment/nakama nakama=wiyazard:30500/zorx-nakama@sha256:...
# rooms: one Deployment per pool worker (room-worker-N); set each one
kubectl -n $NS rollout status deployment/<name> --timeout=300s   # for each changed Deployment
```

Use `kubectl apply` only for ConfigMaps that changed, after `kubectl diff -f` is reviewed. Today
that is `server/k3s/equipment-tuning.yaml`, regenerated 2026-11-13 because the live one still has
the hat slot and pre-HP-scale numbers. Shape changes (new ports/env/Deployments) are a separate,
reviewed change, never part of an image rollout.

## 6. Smoke after rollout

- [ ] `kubectl -n zorx-staging get pods`: all Ready, restarts not climbing over 5 minutes.
- [ ] `curl -sI https://zorxplay.daiyooo.com/packs.json`: 200 and the new `build` id
      (`curl -s .../packs.json | python -c "import json,sys;print(json.load(sys.stdin)['build'])"`);
      a `.pck.wasm` returns `application/wasm` + `immutable` through the ingress/tunnel.
- [ ] `https://zorxapi.daiyooo.com/healthcheck` (Nakama) 200.
- [ ] Browser: sign in (Google or guest), new player gets 4 cards, change a card's race, learn a
      tree node, run one solo stage, return to hub. Profile saves survive a reload.
- [ ] Online: two browsers join one room (room-v2 path) and finish a stage.
- [ ] `kubectl -n zorx-staging logs deploy/name-validator --since=10m` and the room workers show no
      `SCRIPT ERROR`.
- [ ] Watch crash/error reports for 24 h (session crash target < 0.1%), then write the 24 h and 72 h notes.

## 7. Rollback

```sh
# exact previous digest from build/k3s-before-$TAG.txt
kubectl -n zorx-staging set image deployment/<name> <container>=<previous repo@sha256>
kubectl -n zorx-staging rollout status deployment/<name> --timeout=300s
```

`kubectl rollout undo deployment/<name>` also works for a single bad step, but the recorded
digest is authoritative. Data: Postgres is not touched by an image rollout. Profile saves written by a
new build may carry new fields. Old builds ignore unknown keys, but check `logic/profile.gd` from_dict
before rolling back across a save-format change.

## 8. Release fdf9fbb84e7d-20261113 (built from a clean `git worktree` at fdf9fbb; uncommitted work excluded)

Pushed to `192.168.1.99:30500` (the same registry as `wiyazard:30500`), logged in `build/pushed-images.log`:

| Image | Status | Digest |
|---|---|---|
| zorx-room-worker | pushed. Linux image smoke all PASS (room alloc, clock, close) | `192.168.1.99:30500/zorx-room-worker@sha256:1db3c1622679f3e78a2a43815890bc7160b7a0d173e7495fc8abd3b5a992eccd` |
| zorx-name-validator | pushed. Process smoke 10/10; Linux image: healthz ok, new player has 4 cards, 0 SCRIPT ERROR | `192.168.1.99:30500/zorx-name-validator@sha256:891dfce5d80901f2d66e54b401dabbab5ac66ecf3339a22bfd5c3d0ef8ebf84f` |
| zorx-web | **NOT built**: Web export fails at fdf9fbb. Committed `client/skill_tree_tab.gd` uses `CardTokens.TREE_SHEET_W`, `TREE_COMPACT_BELOW`, `TREE_COMPACT_BUTTON_W` and `TREE_NODE_MIN_COMPACT`, which exist only in the uncommitted `client/card_tokens.gd` | none |
| zorx-nakama | **NOT built**: upstream `registry.heroiclabs.com` still returns 429. Runtime `npm test` stub also lacks `registerMatch` | none |

Tests at fdf9fbb (clean worktree): passed=3143 failed=39. 38 of the 39 also fail in the dirty main tree, so they
are not caused by local edits. Examples: catalog armour/race items missing from `art/items/item_manifest.json`,
57-bone rig check, M1-2/M3-4 command tests. Owners must clear these before prod.

Do **not** roll out the room or name/profile images until the web image from the same commit exists. Online
rooms check protocol and wire versions against the client (`7a09410` raised netfox protocol to 4), so a new
room worker behind the old web client breaks online play.

### Rollback targets (newest tag per repo in the registry, 2026-11-13; confirm with step 5a, which is authoritative)

| Repo | Tag | Digest |
|---|---|---|
| zorx-web | combat-feel-20261104-1 | `sha256:d2993d8a8c38493db57951c1eb430928510c3a0deb72ff4adb377703a8ff44e4` |
| zorx-room-worker | combat-feel-20261104-1 | `sha256:0bbf6b8ac534e7d3e13a74854a10273db46672764c17e7780342262fb2db9504` |
| zorx-name-validator | combat-lockout-fix-20261102-1 | `sha256:7299e2e43e9449e26d504724cfc734d4ee96093093a390a8c5b4af094f1c06f8` |
| zorx-nakama | chest-id-fix-20261101-2 | `sha256:64ed2fe98550902cbfe1f13cbac1567f01b0a0322b7f8b4890eb380895e9c998` |

### Commands for Boss (run on the k3s node, or here once a kubeconfig exists; once the web image is pushed)

```sh
NS=zorx-staging
# 1. Record the live images (rollback point)
kubectl -n $NS get deploy -o jsonpath='{range .items[*]}{.metadata.name}{"	"}{range .spec.template.spec.containers[*]}{.name}={.image}{" "}{end}{"
"}{end}' | tee before-fdf9fbb.txt
# 2. Name/profile worker (container "validator")
kubectl -n $NS set image deployment/name-validator validator=wiyazard:30500/zorx-name-validator@sha256:891dfce5d80901f2d66e54b401dabbab5ac66ecf3339a22bfd5c3d0ef8ebf84f
kubectl -n $NS rollout status deployment/name-validator --timeout=180s
# 3. Room workers: one Deployment per pool worker (room-worker-1..N, container "rooms"); ZORX_SQUAD_ROOMS stays unset
for d in $(kubectl -n $NS get deploy -o name | grep room-worker); do
  kubectl -n $NS set image $d rooms=wiyazard:30500/zorx-room-worker@sha256:1db3c1622679f3e78a2a43815890bc7160b7a0d173e7495fc8abd3b5a992eccd
  kubectl -n $NS rollout status $d --timeout=180s
done
kubectl -n $NS get deploy -o yaml | grep -c ZORX_SQUAD_ROOMS   # expect 0
# 4. Web (names from step 1; digest from the web push)
kubectl -n $NS set image deployment/<web-deploy> <web-container>=wiyazard:30500/zorx-web@sha256:<web digest>
# 5. Equipment tuning ConfigMap (regenerated: no hat slot, current upgrade numbers)
kubectl diff -f server/k3s/equipment-tuning.yaml; kubectl apply -f server/k3s/equipment-tuning.yaml
```

Rollback: `kubectl -n zorx-staging set image deployment/<name> <container>=<repo@sha256 from before-fdf9fbb.txt>`,
or use the table above. The ConfigMap rollback is `git show 27116b6:server/k3s/equipment-tuning.yaml | kubectl apply -f -`.

## 9. LIVE on staging: release 2caa255db372-20261114 (rolled out 2026-11-14 ~00:36 UTC, web only)

Built from the release worktree `zorx-release-fdf9fbb` checked out (detached) at 2caa255 = origin/develop, with
`data/online.local.json` copied in (enabled=true, exact bytes verified inside the core pack). `--import`, then
`pipeline/build_web.py --skip-tests --max-file-mb 0` -> web build **659998a286cd** (tag `2caa255db372-20261114`).
Contents: statuses no longer recolour fighters (hit flash), 11 status VFX loops + immune ring (`art/vfx/status/`, in the
core pack: 478 refs), tap a squad plate to follow that fighter, result panel with tappable buttons.
Headless NOT rebuilt: the room/profile images copy only `server/`, `logic/` and `data/`, and 2caa255 changes none of them
(client, art, tests, docs only). `ZORX_SQUAD_ROOMS=1` kept.
Before-state: `build/k3s-staging-before-2caa255.yaml` and `build/k3s-before-2caa255.txt` (main tree).

| Deployment/container | Live image |
|---|---|
| game-test/game-test | `wiyazard:30500/zorx-web@sha256:d15e4f18ef2a6b0f5715b3684eb3d8243d691b0bbd55ecfca42da8f11425246d` (build 659998a286cd) |
| headless/profiles | unchanged: `wiyazard:30500/zorx-name-validator@sha256:73c06c3ffbf823a4e14749d68f0a8ed641cf03d934773bb0cc3b58c4b232ac44` |
| headless/rooms | unchanged: `wiyazard:30500/zorx-room-worker@sha256:4c75507955e73d07c6907699940e01d309368642faf41695f8f82a7bb4a5f314` |

Download size: core pack 4.37 -> 6.38 MiB (+2.0 MiB, the status flipbooks); boot total (engine+core+boot packs)
57.1 -> 59.1 MiB; everything incl. battle packs 82.7 -> 84.7 MiB. Other packs byte-identical.
Local checks: web image paths 200 with correct types, `.wasm` immutable, missing pack 404, container healthy.
Smoke after rollout: pods Ready, game-test 0 restarts; live `packs.json` build 659998a286cd; live core `.pck.wasm`
`application/wasm` + `immutable` and contains `art/vfx/status/`, `status_vfx.gd`, `result_panel.gd`; Nakama healthcheck 200;
0 `SCRIPT ERROR` in rooms/profiles logs, 0 web 5xx. Sign-in and in-battle look: OPEN for a person (Turnstile blocks automation).

Rollback (web only, to e202ae6):
```sh
kubectl -n zorx-staging set image deployment/game-test game-test=wiyazard:30500/zorx-web@sha256:dd22a508e7c449402bb9b59ff02daabd4048119a5cc37f59de55c2df91db3f8d
```

### Previous: release e202ae64b407-20261114 (rolled out 2026-11-13 ~18:01 UTC, web superseded; headless still live)

Built from the release worktree `zorx-release-fdf9fbb` checked out (detached) at e202ae6 = origin/develop, with
`data/online.local.json` copied in (enabled=true, verified inside the core pack). `--import`, then
`pipeline/build_web.py --skip-tests --max-file-mb 0` -> web build **99bfc6a3db38**. Contents: squad-room fixes,
boot straight to the hub plus the hub-style loading page (`loading.<hash>.webp` = `tools/web/static/loading_ruins.webp`,
Sarabun/Taviraj woff2), legacy item removal plus old-save conversion, hair I, solo/duo balance, 16 race weapons.
Before-state: `build/k3s-staging-before-e202ae6.yaml` and `build/k3s-before-e202ae6.txt` (main tree).

| Deployment/container | Live image |
|---|---|
| game-test/game-test | `wiyazard:30500/zorx-web@sha256:dd22a508e7c449402bb9b59ff02daabd4048119a5cc37f59de55c2df91db3f8d` (build 99bfc6a3db38) |
| headless/profiles | `wiyazard:30500/zorx-name-validator@sha256:73c06c3ffbf823a4e14749d68f0a8ed641cf03d934773bb0cc3b58c4b232ac44` |
| headless/rooms | `wiyazard:30500/zorx-room-worker@sha256:4c75507955e73d07c6907699940e01d309368642faf41695f8f82a7bb4a5f314` (`ZORX_SQUAD_ROOMS=1` kept) |

Unchanged: nakama (image not rebuilt, upstream heroiclabs registry still 429), landing, perf-lab, postgres, equipment-tuning ConfigMap.
Local checks before push: room image smoke `--squad-rooms` all PASS, stderr empty; name worker process smoke 11 PASS;
web image paths 200 with correct types, missing pack 404. Name-validator image label says `-dirty` only because of
untracked Godot `.uid` files the import created in `logic/` (no tracked change).
Smoke after rollout: pods Ready, 0 restarts; live `packs.json` build 99bfc6a3db38; `play.html` has the ruins/leather/parchment
markers and the ruins webp + fonts serve 200; `.pck.wasm` is `application/wasm` + `immutable`; Nakama healthcheck 200;
`wss://zorxapi.daiyooo.com/room-v2` upgrade gives 101 (`/room-v2` lives on zorxapi, not zorxplay, which gives 404).
At 18:10 UTC (9 min after rollout): 0 restarts, 0 `SCRIPT ERROR` in rooms/profiles logs (whole pod life), 0 web 5xx.
**Precondition for every web build:** `data/online.local.json` must exist in the build tree (git-ignored, absent in a
fresh `git worktree`); otherwise the export silently falls back to `data/online.json` (`enabled: false`).
Sign-in: OPEN for a person (an automated browser stops at the landing page's Cloudflare Turnstile).

Rollback (to the previous live release a4744e5d582d, exact digests from the before-file):
```sh
kubectl -n zorx-staging set image deployment/game-test game-test=wiyazard:30500/zorx-web@sha256:d23b08d73de47ee3ab10c755fa380fc5e583b047f897d42999f0e243daf42df2
kubectl -n zorx-staging set image deployment/headless profiles=wiyazard:30500/zorx-name-validator@sha256:cc356e99818cac48fe0beb865b3a9bc7fd6e85bba999a13624a2014f871959ee rooms=wiyazard:30500/zorx-room-worker@sha256:4a004408eeda80609353bf9e4ce90fe92b1a77d38883c149de5c9b5d0908fd34
```
Saves: e202ae6 converts legacy gear in old saves to race pieces once (`logic/legacy_items.gd`). After a rollback, the a4744e5
build already knows race pieces, so converted saves should load (not verified); check `logic/profile.gd` from_dict before rolling back.

### Previous: release a4744e5d582d-20261113 (rolled out 2026-11-13 ~16:40 UTC, superseded)

Built from a clean worktree at a4744e5 (uncommitted legacy-item removal excluded). Before-state: `build/k3s-staging-before-20261113.yaml`
(coordinator) and `zorx-release-fdf9fbb/build/equipment-tuning-before-20261113.yaml` (ConfigMap).

| Deployment/container | Live image |
|---|---|
| game-test/game-test | `wiyazard:30500/zorx-web@sha256:d23b08d73de47ee3ab10c755fa380fc5e583b047f897d42999f0e243daf42df2` (web build b29a1f42352a, tag `a4744e5d582d-online-20261114`, rolled out 2026-11-13 ~17:02 UTC) |
| headless/profiles | `wiyazard:30500/zorx-name-validator@sha256:cc356e99818cac48fe0beb865b3a9bc7fd6e85bba999a13624a2014f871959ee` |
| headless/rooms | `wiyazard:30500/zorx-room-worker@sha256:4a004408eeda80609353bf9e4ce90fe92b1a77d38883c149de5c9b5d0908fd34` |
| ConfigMap zorx-equipment-tuning | regenerated from data (HP-100 increments, no hat slot) |

Nakama, landing, perf-lab and postgres were not changed. `ZORX_SQUAD_ROOMS` is unset. Nakama image not rebuilt (upstream 429).

Web re-roll (same commit a4744e5): the first web image (`sha256:80687fa4…`, build a2bae67f9c20) was exported
without the git-ignored `data/online.local.json`, so the game booted with online disabled ("Offline" title).
Rebuilt with the file present. `export_presets.cfg` already includes `data/*.json`, so no filter fix was
needed. The enabled config's bytes were verified inside `core.7eacac1a1ca9.pck.wasm`. Before-state:
`build/k3s-before-web-online-20261114.txt`. Live `packs.json` reports build b29a1f42352a. Headless was not changed.
**Precondition for every web build:** `data/online.local.json` must exist in the build tree (it is
git-ignored, so a fresh `git worktree` does not have it). Otherwise the export silently falls back to
`data/online.json` (`enabled: false`).
Sign-in: OPEN. An automated browser is stopped at the landing page's Cloudflare Turnstile ("Verification failed"),
so the Google/Guest path and the in-game online state must be checked by a person.

Web-only rollback: `kubectl -n zorx-staging set image deployment/game-test game-test=wiyazard:30500/zorx-web@sha256:80687fa49e505f21b640c6e1b8ad2950ca5664f710f9fd4736bd042665f38d8d`
(note: that build is the offline one).

Rollback:
```sh
kubectl -n zorx-staging set image deployment/game-test game-test=wiyazard:30500/zorx-web:combat-feel-20261104-1
kubectl -n zorx-staging set image deployment/headless profiles=wiyazard:30500/zorx-name-validator@sha256:7299e2e43e9449e26d504724cfc734d4ee96093093a390a8c5b4af094f1c06f8 rooms=wiyazard:30500/zorx-room-worker:combat-feel-20261104-1
kubectl apply -f <equipment-tuning-before-20261113.yaml>   # only together with the old images
```
