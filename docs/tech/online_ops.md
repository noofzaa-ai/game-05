# Online operations — M3-1 preparation

Status, 2026-10-17: base Postgres/Nakama deployed by Boss; internal HTTP/WS and public HTTPS/WSS authentication/persistence verified. M3-2 device login is integrated. Boss approved TypeScript for the Nakama bridge; Godot retains game/name rules.

M3-3 name validation/atomic uniqueness passes the isolated real backend stack and native SDK. Its additional worker/runtime overlay is ready for manual deployment; it has not been applied to staging. See [names README](../../server/names/README.md). M3-4 server profile/command RPC and SDK adapter plus M3-5 shared per-account limits/audit are implemented and locally tested; [profile README](../../server/profile/README.md) describes manual image release. M4 game UI/session integration and M5 friends/parties are implemented and locally tested. M5/M6 rollout and remaining physical iPhone, target-i5 and off-machine restore gates are in [online_release.md](online_release.md).

## Apply-only installation on Boss's remote node

For the separate node at `100.78.133.27`, with host storage under
`/data/k3s/volumes/zorx-game/`, use [REMOTE_DEPLOY.md](../../server/k3s/REMOTE_DEPLOY.md).
A complete private YAML is generated on the dev machine and copied to k3s;
the k3s machine only applies it. It does not need this repository, Python,
`online_prepare.sh`, or access to the Mac. The versioned `server/k3s/deployment.yaml`
is the resources-only review copy; first installation uses the private complete bundle.

## Approved Cloudflare/Traefik route

Boss selected `zorxapi.daiyooo.com` through the existing Cloudflare
Tunnel443 → Traefik80 path. `server/k3s/ingress.yaml` is a separate two-resource
overlay for that route; see [TUNNEL_INGRESS.md](../../server/k3s/TUNNEL_INGRESS.md).
It adds the Traefik pod/namespace allowance to the API NetworkPolicy and routes
HTTP7350 internally. External TLS stays at Cloudflare. Public HTTPS/WSS endpoint checks passed after Boss applied the route.

## Files and isolation

- `server/k3s/render.py`: emits Kubernetes JSON (valid YAML) for **zorx-staging**
  or **zorx-prod**. Separate DB PVCs, Secrets, services and backup prefixes.
- Postgres17 and Nakama3.37.0 images are pinned by multi-platform SHA256 digest.
  Updates require a reviewed image/digest change and restore drill first.
- One Postgres StatefulSet and one Nakama Deployment, with Recreate updates and
  migration init container. Non-root execution, resource bounds and no pod API
  token. Initial app database role owns `nakama`, not the Postgres superuser.
- Both services are cluster-internal. Only API7350 may receive network traffic;
  Postgres5432 accepts the same namespace's Nakama/backup pods. Console7351 is
  loopback-only and has no public Service. K3s NetworkPolicy enforcement must be on.
- Optional Ingress requires **all** of hostname, ingress class and TLS Secret.
  No default domain, TLS issuer or controller is installed. Configure the selected
  controller's HTTPS redirect and WebSocket timeout; a TLS stanza alone does not
  guarantee HTTP is disabled. Cloudflare Tunnel can instead route to the internal
  Nakama API Service with no Ingress resource.
- PVC requests10Gi using the cluster's default StorageClass. Review capacity,
  retention and node placement before applying. K3s local-path storage on one node
  is **not HA or an off-machine backup**.

## Local checks (safe to run without a cluster)

```sh
./pipeline/online_prepare.sh staging
./pipeline/online_prepare.sh prod \
  --host coop.example.com --ingress-class YOUR_CLASS --tls-secret YOUR_TLS_SECRET
python3 -m unittest discover -s tests -p test_online_infra.py
python3 server/k3s/local_smoke.py
```

Replace the uppercase example names with real lowercase Kubernetes names. Rendered
files are under ignored `build/online/<environment>/resources.json`. The prepare
script only checks/renders. It never calls kubectl or pushes images. Unit checks
cover isolation, private services, pinned images, TLS options, secret consistency/
permissions/no-overwrite, suspended backup jobs and restore safeguards.

The Docker smoke creates uniquely named containers, network and volumes, binds
only a random **127.0.0.1** TLS port, then removes its containers/network/volumes.
It verifies six things with the pinned real images: migration, healthcheck, device
authentication via trusted local HTTPS, authenticated WSS upgrade, Postgres custom
dump/restore into a scratch DB and identical account ID after DB/server restarts.
Test-only nginx terminates local TLS; this does not select the production gateway.
Docker images remain cached. The local TLS key/credentials are temporary private
files and are removed at exit. The smoke does not upload backups or use k3s.

Optional schema check (requires Python `jsonschema`; fetch the official schema
matching the target cluster version and keep it outside git):

```sh
python3 server/k3s/validate_schema.py --schema /PRIVATE/PATH/swagger.json \
  build/online/staging/resources.json build/online/prod/resources.json
```

The local check used [Kubernetes v1.34.1's official OpenAPI](https://github.com/kubernetes/kubernetes/blob/v1.34.1/api/openapi-spec/swagger.json).

## Manual first installation (operator only; not run by this change)

1. Confirm `kubectl config current-context` and select staging first. Review the
   rendered JSON, PVC policy/resources and NetworkPolicy support.
2. Create namespace `zorx-staging`. Generate **new** credentials into a private,
   ignored directory; never commit these files or paste their values in logs:

   ```sh
   mkdir -p build
   python3 server/k3s/prepare_secrets.py --environment staging \
     --output-dir build/online-secrets-staging
   kubectl -n zorx-staging apply -f build/online-secrets-staging/postgres-auth.json
   kubectl -n zorx-staging apply -f build/online-secrets-staging/nakama-config.json
   ```

   Directory0700/files0600; existing directory is refused to avoid accidental
   rotation against an existing PVC. Store a recovery copy securely outside git.
   Separate admin/app DB passwords, API key, session/refresh keys, runtime key and
   console password/signing key are generated. Do not reuse staging credentials
   in prod. Nakama YAML is stored wholly in a Secret, not command-line flags.
3. Apply the reviewed resources manually:

   ```sh
   kubectl apply -f build/online/staging/resources.json
   kubectl -n zorx-staging rollout status statefulset/postgres --timeout=180s
   kubectl -n zorx-staging rollout status deployment/nakama --timeout=300s
   ```

   Init migrations retry if Postgres is not ready. Never run multiple independent
   schema migrations concurrently. Stop here on any failed migration; inspect the
   init container log privately. Do not delete PVCs to resolve startup errors.
4. Supply a real TLS certificate Secret and chosen gateway, then test external
   HTTPS and **wss://** from PC and actual iPhone. Verify cleartext HTTP redirects
   or is rejected and the WebSocket survives the gateway idle timeout. Local
   smoke is not evidence of public DNS/certificate/Cloudflare behavior.
5. Console maintenance uses local port forwarding to the pod, not a public route:
   `kubectl -n zorx-staging port-forward deployment/nakama 7351:7351 --address 127.0.0.1`.
   The API `socket.server_key` is an application identifier, not user identity;
   protect runtime/console/DB/session signing secrets from clients.
6. Repeat with **new prod credentials**, namespace and hostname only after staging
   restore/WSS tests and ownership/monitoring decisions are accepted.

## Off-machine daily backups (operator configuration required)

`server/backup/backup.py` produces Postgres custom archives with pg_dump, checks
pg_restore can read them, uploads to a private S3-compatible bucket and checks
remote length/SHA256 metadata. Restore downloads and verifies bytes before any DB
write, uses one transaction and refuses primary `nakama` as a target. It accepts
only an existing scratch database named `restore_*`. It does not delete backups.

Build/publish the backup image to the operator's registry using their normal
credentials, targeting the i5 server's linux/amd64 architecture:

```sh
docker buildx build --platform linux/amd64 \
  -t wiyazard:30500/zorx-online-backup:REVIEWED_TAG --push server/backup
docker buildx imagetools inspect wiyazard:30500/zorx-online-backup:REVIEWED_TAG
```

Use the returned image **@sha256:...**, not a mutable tag, in `--backup-image`.
The preparation here built/tested only a local image; nothing was published.

Provide an operator-owned private env file outside git with keys
`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`, `S3_BUCKET`
and optional `S3_ENDPOINT_URL`. HTTPS is required for custom endpoints. The default
S3 server-side encryption is AES256; configure bucket encryption/permissions and
object lifecycle retention explicitly. Credentials should be limited to the
selected environment prefix's put/get/head operations. Set `S3_ENCRYPTION` only
when the bucket's chosen encryption requires a different configuration.

```sh
kubectl -n zorx-staging create secret generic backup-s3 \
  --from-env-file=/PRIVATE/PATH/staging-backup.env
./pipeline/online_prepare.sh staging \
  --backup-image YOUR_REGISTRY/backup@sha256:YOUR_64_HEX_DIGEST
```

Review/apply the new rendered JSON. CronJob is **suspended by default**, scheduled
02:00 UTC daily with no overlap and a30-minute deadline. Prefixes are
`zorx-staging/` and `zorx-prod/`. The bucket must physically survive loss of the
k3s machine; a local MinIO on that same machine does not satisfy the plan.

Run one manual Job from the CronJob, verify upload in that off-machine bucket,
then run a restore drill:

```sh
kubectl -n zorx-staging create job --from=cronjob/postgres-backup backup-check-001
kubectl -n zorx-staging wait --for=condition=complete job/backup-check-001 --timeout=1800s
kubectl -n zorx-staging logs job/backup-check-001
kubectl -n zorx-staging exec postgres-0 -- \
  createdb -U postgres -O nakama restore_check
python3 server/k3s/restore_job.py --environment staging \
  --backup-image YOUR_REGISTRY/backup@sha256:YOUR_64_HEX_DIGEST \
  --key zorx-staging/YYYY/MM/DD/KEY.dump --database restore_check \
  --job-name restore-check-001 > build/online/staging/restore-job.json
```

Review/apply that Job manually; verify table counts and a known account/profile in
`restore_check`, then record evidence. Only after the real off-machine restore
passes, unsuspend scheduling with
`kubectl -n zorx-staging patch cronjob postgres-backup --type=merge -p '{"spec":{"suspend":false}}'`.
Monitor failed/missing daily Jobs and remote object freshness. Cleanup of the
scratch DB and old Jobs is an operator action. Restoring a primary database during
an incident requires a separate reviewed runbook, downtime and an explicit plan;
this tool intentionally cannot overwrite it.

## Verification / gates

Locally observed: **6/6** Docker checks passed; backup image builds and starts;
**11 Python unit tests pass**; both environment manifests and restore Job render.
Generated resources also pass offline official Kubernetes v1.34.1 OpenAPI validation
(with IntOrString normalized to its accepted integer/string union). This does not
replace validation against the actual k3s version/admission policies. Secrets/private files
were generated only as disposable fixtures. No production credential was read.

Still required for **M3-1 acceptance**: actual k3s apply/schema validation, public
TLS/WSS from PC/iPhone, chosen gateway, off-machine scheduled upload and restore,
monitoring/retention ownership. No live cluster or external storage was touched.
M2 balance approval is also outstanding, so M4/M5/M6 are not declared ready.

## References

- [Nakama configuration and secret settings](https://heroiclabs.com/docs/nakama/getting-started/configuration/)
- [Official Docker/migration/healthcheck setup](https://heroiclabs.com/docs/nakama/getting-started/install/docker/)
- [Nakama CLI commands](https://heroiclabs.com/docs/nakama/getting-started/commands/)

## M4-1 private room worker foundation

`server/rooms/README.md` describes the separate one-CPU fixed-clock Godot room process and its local/native/Linux checks. Its deployment builder emits private control resources only; it is not yet wired to Nakama admission or public WebSocket gameplay. Boss owns image push and remote apply. M4-2 onward must add admission, active-room fencing, transport and trusted settlement before enabling real online play.

## In-game latency readout

Solo/Farm and co-op rooms show `Ping … ms · FPS …` beneath the trip counters on desktop and phones. Ping is smoothed application round-trip time to the authoritative Godot room over the real gameplay WebSocket (including routing and server scheduling), not ICMP or just Nakama authentication latency. It uses the existing once-per-second PING/PONG; the label refreshes twice/second and adds no network probes. Unknown samples display `—`; replies older than five seconds display waiting, and a disconnected room displays reconnecting. F2 on desktop retains prediction/correction/drop details.

High Ping with stable FPS and low FPS with stable Ping suggest different investigations; neither alone proves a bottleneck. `kubectl top` CPU units are millicores (`562m` = 0.562 core); inspect per-container limits and CPU throttling separately.
