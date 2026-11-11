# M3-3 names / M3-4 authority worker — Godot + TypeScript bridge

Boss approved TypeScript and case-insensitive names on2026-10-17.

- Nakama3.37.0 handles authentication and authoritative storage. Runtime typings v1.44.2 match its pinned upstream go.mod; TypeScript5.9.3 emits ES5. package-lock pins package integrity.
- Godot4.7.2 runs the existing `Profile.name_problem` directly. No name-rule copy in TypeScript.
- Character display names are separate from Nakama usernames: our existing rules allow spaces and Thai, while Nakama usernames do not allow spaces.
- Names keep their selected case for display. Uniqueness uses `strip_edges().to_lower()` in Godot, then SHA256 in Nakama. Hero/hero collide; Unicode NFC/NFKC or full linguistic case-folding is not added to the existing rules.
- `zorx_name_get_v1` reads the authenticated player's name; `zorx_name_claim_v1` validates and claims/renames it. The caller cannot supply a user ID.
- Nakama `multiUpdate` reserves the new name, updates the owner and releases the previous name atomically. Create-only/version CAS prevents duplicate races and orphan reservations. Retrying the same name is idempotent; concurrent conflicting changes return conflict.
- `zorx_name_registry_v1` (system owner) and `zorx_character_v1/display_name` (player owner) are server-only. Client write/delete API hooks block both new and existing objects. No custom SQL table or migration.
- The private Godot worker has bounded HTTP bodies, connection/time limits and a shared token. It cannot access the database, exposes no public Service and has no egress in k3s.

M3-4 adds authoritative profile/commands RPC and the SDK adapter; see [profile README](../profile/README.md). The game UI still uses LocalSession until RemoteSession integration. A name claim is not proof of cloud inventory save or linked cross-device login. The checked-in deployment.yaml/RELEASE.md remain the historical M3-3 image release; regenerate with new image digests for M3-4.

## Local checks

```sh
python3 server/names/smoke_worker.py
npm ci --ignore-scripts --prefix server/names/runtime
npm run build --prefix server/names/runtime
npm test --prefix server/names/runtime
python3 server/names/build_images.py
python3 server/names/smoke_stack.py
```

The stack test creates isolated Docker containers/network and a disposable Postgres database. It tests duplicate races, rename/release, API bypass attempts, actual Godot SDK, portable backend diagnostics, both server/DB restarts and worker outage, then removes only its own containers/network. Failed container logs are private under ignored `build/names-smoke-private/`.

Images default to linux/amd64. `--platform linux/arm64` downloads a separately SHA256-pinned official Godot binary for ARM servers. Physical phones do not determine the server image architecture. Build contexts include only the required project scripts and compiled runtime, never the private deployment bundle or build caches.

## Publish images for manual k3s apply

Use the tested source commit on develop. Build/tag both images and push to the existing registry:

```sh
python3 server/names/build_images.py
# Replace TAG with the reviewed develop source commit.
docker tag zorx-nakama:m3-4-local wiyazard:30500/zorx-nakama:TAG
docker tag zorx-name-validator:m3-4-local wiyazard:30500/zorx-name-validator:TAG
docker push wiyazard:30500/zorx-nakama:TAG
docker push wiyazard:30500/zorx-name-validator:TAG
# Use RepoDigests from inspect, not mutable tags, in the manifest:
docker image inspect wiyazard:30500/zorx-nakama:TAG --format '{{json .RepoDigests}}'
docker image inspect wiyazard:30500/zorx-name-validator:TAG --format '{{json .RepoDigests}}'
```

Generate the **private complete overlay** on the dev machine; no Python/source is needed on k3s:

```sh
python3 server/names/deploy.py \
  --worker-image wiyazard:30500/zorx-name-validator@sha256:WORKER_DIGEST \
  --nakama-image wiyazard:30500/zorx-nakama@sha256:NAKAMA_DIGEST \
  --output build/k3s-remote/names-deployment.yaml
```

Keep this0600 file out of Git. It adds one new validator Secret and resources; the original `postgres-auth` and `nakama-config` Secrets and Postgres hostPath stay intact. Nakama loads an additional runtime config file from the new Secret. Subsequent updates must pass `--reuse-secret build/k3s-remote/names-deployment.yaml` and a new output path to retain the token; the tool never overwrites an existing file. Both Deployments carry a checksum so intentional token changes restart both sides together.

For a versioned review copy, add `--resources-only --reuse-secret PRIVATE_PREVIOUS_BUNDLE`. That output references an existing Secret and cannot be used alone for a first installation.

Copy the private complete overlay to the k3s node, review with kubectl diff, then apply there:

```sh
kubectl diff -f names-deployment.yaml
kubectl apply -f names-deployment.yaml
kubectl -n zorx-staging rollout status deployment/name-validator --timeout=180s
kubectl -n zorx-staging rollout status deployment/nakama --timeout=180s
```

Check the diff if the cluster's Nakama Deployment was customized since the original standalone manifest: the overlay includes the complete Nakama Deployment derived from that source. It does not change the API Service/Ingress, NodePort, original Secrets or DB StatefulSet. Preserve the original YAML and previous image references for rollback; name records remain in Postgres. Avoid downgrading to a module that exposes these authoritative collections to direct client writes.

After apply, use the existing smoke identity from the dev machine:

```sh
./tools/backend/test_backend.sh both --names \
  --secrets build/k3s-remote/deployment.yaml
```

`--names` claims one deterministic QA name on that isolated smoke account if it has no name, otherwise reuses its current name. It verifies RPC read/claim, invalid-name rejection and spoofed-ID rejection. It does not rename a real player's account or create extra identities by default. Run it only with the dedicated smoke state. Full race/bypass/restart tests are the isolated local stack suite.

Deploy the new backend before testing the new Web creator. An older backend returns a safe unavailable error, and the creator offers an explicit offline path; it never silently claims that a name was saved.
