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

## 9. LIVE on staging: release a4744e5d582d-20261113 (rolled out 2026-11-13 ~16:40 UTC)

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
