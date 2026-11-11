# Remote k3s: copy YAML and apply

This package is for the single k3s machine reachable at **100.78.133.27** over
Tailscale. It does not require the Mac, this repository, Python, a shared dev
folder or `online_prepare.sh` on that machine after the YAML is copied.

## Ready-to-apply file

The dev machine creates `build/k3s-remote/deployment.yaml` with fresh private
credentials plus every resource. Copy that **complete private file** to the server,
for example `/data/k3s/volumes/zorx-game/manifests/deployment.yaml`, and retain a
secure recovery copy. The file is0600 and ignored by Git; do not paste it in chat
or commit it. Reuse the same file when reapplying. Creating a new credential bundle
does not rotate the password in an existing database.

The versioned `server/k3s/deployment.yaml` contains resources only and intentionally
has **no passwords**. It is for review and later resource updates once Secrets
already exist. Do not mistake it for the complete first-install bundle.

On the k3s machine:

```sh
kubectl apply -f /data/k3s/volumes/zorx-game/manifests/deployment.yaml
kubectl -n zorx-staging rollout status statefulset/postgres --timeout=180s
kubectl -n zorx-staging rollout status deployment/nakama --timeout=300s
kubectl -n zorx-staging get pods -o wide
```

If kubectl needs root in that installation, use `sudo k3s kubectl` in place of
`kubectl`. The machine pulls the pinned official Postgres/Nakama images directly;
no image is pulled from the Mac and no game image is rebuilt.

## What the manifest contains

- `zorx-staging` Namespace and two private Secrets in the complete bundle.
- Postgres17 StatefulSet, internal headless Service and persistent hostPath:
  **`/data/k3s/volumes/zorx-game/postgres-staging/pgdata`**.
- An init container prepares ownership of that dedicated directory for UID/GID70.
  It does not delete data or recursively change the shared parent path. Actual
  Postgres runs non-root. Fresh initialization creates a separate Nakama DB role.
- Nakama3.37.0 Deployment, database-migration init container and health probes.
  Account/session data is in Postgres; Nakama's runtime directory can be ephemeral.
- API NodePort **30350 →7350**, `externalTrafficPolicy: Local`. NetworkPolicy
  permits Tailscale source range100.64.0.0/10 and same-namespace pods. K3s must have
  NetworkPolicy enforcement enabled. PostgreSQL and console have no NodePort.

This hostPath manifest assumes the stated single k3s node. If the cluster has
multiple nodes, pin Postgres to the node that owns this directory before applying;
rescheduling to another machine would use that other machine's filesystem.

## First checks from the Mac / another Tailscale client

```sh
curl --fail http://100.78.133.27:30350/healthcheck
```

This first step is HTTP/WS over the Tailscale network. It is **not yet a public
HTTPS/WSS endpoint**; the HTTPS game page on iPhone needs the TLS gateway/Tunnel
step before it can connect directly without mixed-content blocking.

After health passes, test device authentication, WebSocket, persistence after pod
restart and a backup/restore drill. `docs/tech/online_ops.md` has those acceptance
requirements. The Mac's access to the IP alone is not evidence of SSH access or a
successful deployment; this change does not log in or apply resources remotely.

Troubleshooting on k3s:

```sh
kubectl -n zorx-staging logs postgres-0 -c prepare-data-directory
kubectl -n zorx-staging logs postgres-0 -c postgres
kubectl -n zorx-staging logs deployment/nakama -c migrate
kubectl -n zorx-staging logs deployment/nakama -c nakama
kubectl -n zorx-staging get events --sort-by=.lastTimestamp
```

Inspect logs privately. Do not delete the host directory to resolve a startup error.
Backups are not included in this first pod-install manifest; add the off-machine
backup configuration after the database and endpoint are verified.

## Rebuild on the dev machine only

Requires PyYAML locally; the remote server does not use it:

```sh
python3 server/k3s/standalone.py --output build/ANOTHER_PRIVATE_FOLDER/deployment.yaml
```

Generation refuses an existing output file. Edit the builder, then regenerate the
versioned resources-only manifest when changing resource settings; keep the same
private credentials for an existing installation.


## Add the approved public backend hostname

For `zorxapi.daiyooo.com` through Boss's existing Cloudflare Tunnel443 →
Traefik80 route, apply the separate `ingress.yaml` overlay and follow
[TUNNEL_INGRESS.md](TUNNEL_INGRESS.md). It contains no credentials and does not
replace the database/deployment. Reapply it after any future base deployment
manifest apply so the Traefik-specific API NetworkPolicy allowance stays active.

- **Staging namespace correction (2026-10-17):** Boss requires all game/backend resources in `zorx-staging`; `game-test` namespace is scheduled for removal. Fixed remote game.yaml and ingress.yaml migrated Web Deployment/Service/Ingress into zorx-staging, using existing working Web image f7324c7 while 6c46c06 is absent. Old namespace itself is retained for Boss cleanup.

- **Live release 8008975 (2026-10-18):** Web build 7032cd0a7faa and all backend images 8008975 published/applied to zorx-staging using fixed remote files. Web1/1, Nakama1/1, Headless2/2; source metadata clean, timestamp 2026-10-18 00:32:16 UTC+07:00, SHA80089757bf50. Internal/public backend diagnostics36/36. Isolated live SDK accounts verify one-time kit/no duplicates, persisted appearance, distinct correct party appearances, same profile on party return, authoritative solo Farm1stage; stderr empty, ACCOUNT_RELEASE_FAILED=0. Actual Web browser loads beta title and server-backed creator with no offline option. Physical iPhone and target-host capacity gates remain open.
