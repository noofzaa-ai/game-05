# Web build (macOS / Linux)

Requirements: Python 3.9+, Godot **4.7.2**, and its matching **Web export templates** (install through Godot's Export Template Manager). Uses the existing `Web` preset, PCK splitter, pack layout and HTML template. No Blender or PowerShell is required to run this pipeline on already prepared assets.

Run from any directory:

```sh
# macOS: auto-detects /Applications/Godot.app, imports and runs tests by default
./pipeline/build_web.sh

# Linux / CI, on our own host (no artifact-host 15 MiB file restriction)
GODOT_BIN=/opt/godot/godot ./pipeline/build_web.sh --max-file-mb 0

# Optional: host packs on a separate origin; configure CORS on that host
./pipeline/build_web.sh --pack-base https://cdn.example.com/zorx/ --max-file-mb 0

# Only when deliberately skipping the suite
./pipeline/build_web.sh --skip-tests
```

Options: `--godot-bin PATH`, `--timeout SECONDS` (per step, default600), `--max-file-mb N` (default15, 0 disables), `--pack-base URL`, `--skip-tests`, `--help`.

Output: **`build/web/`**, entry page **`play.html`**. Upload every file in this directory to the web container, not the source project. The pipeline builds/imports/tests/exports/splits/packages only; it does not build Docker images, deploy, commit or push.

Logs go to a unique `build/web-*/` directory. Failures keep the old output intact and retain incomplete staging output for diagnosis. Concurrent invocations of this script are blocked using `build/.web-build.lock`; this does not coordinate the older PowerShell script or a separate Godot editor. Avoid running those exports concurrently. After a killed process, inspect the lock PID before manually removing a stale lock.

Gzip-wrapped packs, texture variants, hashes and `packs.json` follow `tools/web/build_web.ps1`. Gzip timestamps are fixed for reproducible compressed output. Set Nginx to serve `play.html` as its index and use the MIME/cache/compression rules in `docs/tech/web_hosting.md`. Our own k3s hosting can use `--max-file-mb 0`; 15MiB is an artifact-host restriction, not a Godot requirement.

Full Web export and browser login/session restoration were verified on 2026-10-17. Physical iPhone and a deployment of the latest build remain separate acceptance steps.

## Nginx runtime container (Phase 0)

This packages the **playable Web export**, not a Godot build-tool image. The image runs Nginx only; players run the game in their browsers. No Python HTTP server or Godot headless process is needed on the hosting machine.

```sh
# 1. Export once (or let the next command do it with --build-web)
./pipeline/build_web.sh --max-file-mb 0

# 2. Package all runtime files into a Docker image
./pipeline/build_web_container.sh --image zorx-web:phase0

# 3. Run the container and open http://localhost:8060/
docker run --rm -p 8060:8080 zorx-web:phase0
```

Combined export + image command:

```sh
./pipeline/build_web_container.sh --build-web --image zorx-web:phase0
```

`Dockerfile.web` uses Nginx with `nginx-web.conf`: container port8080, entry `play.html`, `/healthz`, MIME/cache handling, no additional compression for the gzip-wrapped packs. Browser build failures are not replaced with a fake HTML200 response for missing assets.

Default target is `linux/amd64`. For ARM k3s nodes set `--platform linux/arm64`; the selected platform must match the cluster node. Use `--image registry.example.com/zorx/web:phase0` to tag for your registry. The script does not push or deploy; those are separate steps. HTTPS is terminated by the k3s ingress/reverse proxy, not this container.

Packaging checks the manifest's engine/core/content pack files and requires same-origin packs (build without `--pack-base`). It sends a temporary context containing only Web output + Nginx configuration to Docker. Python is used locally to inspect the manifest; it is not included or run as a server in the runtime image. Avoid exporting to `build/web/` concurrently with packaging.

Container image has not yet been built or run here; Docker connectivity and a completed Web export are prerequisites.

## Build and push to the local registry (manual k3s deployment)

**Boss policy (2026-10-17): k3s test releases use `develop`.** Keep online work in
`codex/online-coop`, promote tested changes to `develop`, then build from that branch.
The wrapper uses the current checkout; it does not select or pull a branch for you.

```sh
git switch develop
git pull --ff-only origin develop
# On a new build machine, prepare only public account connection settings first:
python3 pipeline/online_client_config.py --secrets build/k3s-remote/deployment.yaml
./pipeline/deploy_k3s.sh
# Or choose a release tag yourself:
./pipeline/deploy_k3s.sh --tag mobile-v2
# ARM cluster nodes:
./pipeline/deploy_k3s.sh --platform linux/arm64
```

This always runs a fresh Web build **including tests**, packages the output as
`wiyazard:30500/zorx-web:<git-sha>-<UTC-timestamp>`, and pushes that image. Local
changes add `-dirty` to the automatic tag. No Git pull is performed: the current
working tree is the build source. A failed build or packaging step stops before
push. A failed push exits nonzero and does not report success.

After success, copy the image reference printed at the end (also saved in
`build/pushed-image.txt`) into your k3s deployment and deploy there yourself.
The script does not use kubectl, change cluster context, or perform a rollout.

Use `--registry HOST[:PORT]` (or `ZORX_REGISTRY`) and `--image-name NAME` to change
the destination. Platform defaults to `linux/amd64`. Docker must already be able
to reach/authenticate to the registry; for an HTTP registry, configure the Docker
daemon's insecure-registry setting separately. The script does not change it.
Avoid running other Web builds/container packaging while publishing. Concurrent
runs of this wrapper are blocked with `build/.image-publish.lock`; inspect its
PID before removing a lock left by a killed process.
