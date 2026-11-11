# M3-3 staging release — 2026-10-17

Source commit: `792b58c6a877719347edda1274f7d4b1004bb8ff` (included in develop). Images: **linux/amd64**, Godot4.7.2, Nakama3.37.0.

| Image | Published immutable reference |
|---|---|
| Nakama runtime | `wiyazard:30500/zorx-nakama@sha256:1372ab7b12c43af9c96c669df71e61876d89985a0f950b07c69035ba0aa457fd` |
| Godot name validator | `wiyazard:30500/zorx-name-validator@sha256:68da4f18b36c6c1856538077664811e38726a669332292c10bd541fccfc64655` |

Registry tags: `online-names-792b58c6a877` on both repositories. Runtime JS SHA256: `63211bdc370cf058e4bfb5063b1a36d3162c76f76a74ce45c245dd7a3189f94a`. Images were pushed; cluster deployment has **not** been performed.

## First installation on the k3s node

Copy the private complete `build/k3s-remote/names-deployment.yaml` from the dev machine to that node as `names-deployment.yaml`. It contains the new validator token; keep it private. The versioned deployment.yaml in this directory has only resources/Secret references and is not sufficient for first installation.

```sh
kubectl diff -f names-deployment.yaml
kubectl apply -f names-deployment.yaml
kubectl -n zorx-staging rollout status deployment/name-validator --timeout=180s
kubectl -n zorx-staging rollout status deployment/nakama --timeout=180s
```

This updates Nakama and adds a private Godot validator. Postgres data, original Secrets, API Service and public route are unchanged. Review the full Nakama Deployment diff if customized since original installation. Keep the private overlay for token reuse on later updates. See README.md for regeneration and rollback considerations.

Then run on the dev machine:

```sh
./tools/backend/test_backend.sh both --names --secrets build/k3s-remote/deployment.yaml
```

Local checks: Godot2208 passed/0 failed, stderr empty; Python32; real isolated backend24 checks; official Kubernetes schema5; native phone creator preview inspected. Web build `28af07e0f024` prepared locally. Live staging names RPC and physical iPhone checks await manual apply. Character appearance/inventory cloud save is M3-4.
