# Zorx image retention

Boss approved shared registry maintenance on 2026-10-18. The registry is shared:
manifest selection is restricted to the five configured Zorx repositories, while
GC marks references across the entire registry. It never uses `--delete-untagged`.

## Policy

`tools/backend/image_retention_policy.json` is the source. Its installed copy and
manifests are in `/home/wiyazard/deployment/game-test/zorx-staging/maintenance/`.

- Protect images referenced by Pods, Deployments, StatefulSets, DaemonSets,
  ReplicaSets, Jobs and CronJobs across **all namespaces**, including rollback images.
- Keep the newest **10 distinct digests per repository**, and everything less than
  **14 days** old. Unknown dates are retained.
- Always keep `latest`, `stable`, `main`, `develop`, `prod*`, `local-*` tags.
- A retained tag protects every alias of its digest. Unsupported/index manifests
  cause their entire repository to be retained.
- Enumeration failures, changed workload references, invalid policy or an existing
  maintenance lock abort deletion. A resourceVersion test acquires the shared lock.

## Schedule and safety

Namespace `registry`:

- CronJob **zorx-registry-retention**: daily **03:30 Asia/Bangkok**.
- CronJob **zorx-registry-retention-recovery**: every **5 minutes**.
- No expired candidates means no write interruption and no GC.
- With candidates: delete eligible manifest references, switch to the read-only
  config, wait until every old writable pod has gone, run GC with a 600-second
  process timeout, then restore writable config and await readiness.
- A failed/lost exec connection terminates its registry pod before writes resume.
  The independent recovery job does the same after a lock expires (20 minutes),
  covering abrupt maintenance-runner termination. It leaves writes frozen if it
  cannot confirm the old pod disappeared. Cluster/node outages still need operator attention.
- Jobs do not overlap; retention runner deadline 15 minutes. Logs retained up to
  7 days, bounded to 3 successful + 3 failed Jobs per CronJob.
- Registry rollouts retain service via readiness checks. Pushes during read-only
  maintenance fail and should be retried afterwards. Avoid deploying very old
  releases or pushing during this window. Already running game containers continue running.

The runner service account has read-only workload enumeration across namespaces;
registry-only deployment patch, pod termination and exec. It has no Secret access
or permissions to modify application workloads. No admin kubeconfig is mounted.

Registry 2.8.3 cannot synthesize the nested maintenance map from an environment
override alone (startup panic). Two explicit files in `zorx-registry-config`
ConfigMap provide writable/read-only configs; the runner switches container args.
Storage PVC/root path remain the same.

Official GC requirements: [Distribution garbage collection](https://github.com/distribution/distribution/blob/main/docs/content/about/garbage-collection.md).

## Installation / updates (on k3s host)

Files are versioned under `server/k3s/maintenance/`. Build/push the image with
`pipeline/Dockerfile.registry-maintenance` before applying a changed image reference.
The YAML is JSON, valid Kubernetes YAML. It contains ConfigMaps, limited RBAC and
both CronJobs; it does not replace the registry PVC or application manifests.

```sh
cd /home/wiyazard/deployment/game-test/zorx-staging
kubectl apply -f maintenance/registry-retention.yaml
kubectl patch deployment docker-registry -n registry --type strategic \
  --patch-file maintenance/registry-config-patch.json
kubectl rollout status deployment/docker-registry -n registry --timeout=180s
```

Change policy in source and the manifest ConfigMap together, then apply the YAML.
The separate `.json` policy copy is for manual report inspection only.

## Inspect / run now

```sh
kubectl get cronjobs,jobs -n registry
kubectl logs -n registry job/JOB_NAME
kubectl create job -n registry --from=cronjob/zorx-registry-retention \
  zorx-retention-manual-$(date +%s)
kubectl get deployment docker-registry -n registry \
  -o jsonpath='{.metadata.annotations.zorx\.io/maintenance-deadline}'
```

Report-only, with host kubectl access:

```sh
python3 maintenance/image_retention.py --registry http://127.0.0.1:30500
```

Do not run this CLI with `--apply` while the scheduled job is active: use the
CronJob instead so locking/GC/recovery are coordinated. Manifest deletion alone
frees no blob storage. Do not use blanket Docker/system prune or remove volumes.
Kubelet cache GC and Mac Docker build cache are separate from registry retention.

## Recovery

If a runner failed, inspect its log and the registry pods. The recovery CronJob
normally restores writes after the expired lock. Do not manually switch writable
until any possible GC process is confirmed stopped. To suspend future cleanup:

```sh
kubectl patch cronjob zorx-registry-retention -n registry \
  --type merge -p '{"spec":{"suspend":true}}'
```

Keep the recovery job enabled until maintenance has fully finished.

## Acceptance — 2026-10-18

- Godot 2381/0, empty stderr; Python 58/0; TypeScript 11 groups pass.
- Isolated Registry2: delete one eligible digest; newest10 + live old digest and
  unrelated application survive GC with configs readable.
- Real k3s runner: 51 Zorx tags, zero expired manifests. One explicit initial GC
  reclaimed 30.99 MiB of unreferenced blobs (9435788 → 9404052 KiB).
- All 99 pre-maintenance tags across all repositories preserve their digests;
  registry writes restored. The maintenance image adds one new tag.
- Deep post-GC check: 159 distinct manifests / 1140 referenced layers available;
  upload202 and upload-cancellation204 pass. Scheduled recovery and manual normal
  jobs complete; normal zero-candidate run skips write interruption.
- Validation summary: fixed remote `maintenance/retention-validation.json`.
- Maintenance image pinned by digest in the CronJobs. Game images are unchanged.
