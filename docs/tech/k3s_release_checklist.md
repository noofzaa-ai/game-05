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
- [ ] **Registry access**: `wiyazard:30500` is a plain-HTTP registry. In Docker Desktop -> Settings ->
      Docker Engine, add `"insecure-registries": ["wiyazard:30500"]`, then Apply & restart. This machine
      must resolve and reach `wiyazard` (Tailscale/LAN): `curl http://wiyazard:30500/v2/` should return `{}`.
- [ ] **kubectl + kubeconfig** on this machine (`winget install Kubernetes.kubectl`, plus a kubeconfig
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

## 8. Known state on 2026-11-13 (prep run; nothing pushed, nothing applied)

| Item | Status |
|---|---|
| Web build (`build_web.py --skip-tests --max-file-mb 0`) | **FAILS at import**: `logic/skill_tree_mechanics.gd` (untracked, in progress by another agent) has parse errors at 446/555/706. `build/web/` is the older build `4ec5df6a06cf` (db31050 + local changes). |
| Web image from existing `build/web` | Built `zorx-web:k3s-prep-local`; served on :8070, all headers in section 3 correct, healthcheck healthy |
| Rooms image | Built `zorx-room-worker:k3s-prep-local`, but **the worker fails to start**: it copies the same broken script. Rebuild after that file compiles. |
| Name/profile worker image | Built `zorx-name-validator:k3s-prep-local` (with `--skip-tests`). Process smoke 10/10 PASS. |
| Nakama runtime image | Not built: `registry.heroiclabs.com` answered 429 (rate limit), so retry later. `npm test` fails: `initializer.registerMatch is not a function` (test stub lacks `registerMatch`; pre-existing, runtime unchanged since ffa3a51). |
| kubectl / kubeconform | Not installed, so manifests are not schema-linted on this machine |
