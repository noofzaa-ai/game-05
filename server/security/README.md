# M3-5 RPC request controls

All four public name/profile RPCs are registered through top-level callbacks calling `rpcDispatch` in `server/names/runtime/src/security.ts`. Every request requires an authenticated Nakama user; an HTTP runtime key without a user cannot impersonate one. Client payloads cannot choose identity or trusted game state.

## Per-account budget

A token bucket is persisted in server-only `zorx_rpc_budget_v1/shared` under the authenticated user. It is shared across all four RPCs, runtime VMs and Nakama replicas. Storage version CAS prevents concurrent callers multiplying their quota; after three CAS collisions the request fails closed. Restarting Nakama does not reset a budget. A DB error returns unavailable; business handlers are not invoked before the gate succeeds.

Production defaults, emitted explicitly by `server/names/deploy.py`:

| Environment setting | Default | Meaning |
|---|---:|---|
| ZORX_RPC_BURST |20|Maximum saved request credits per account|
| ZORX_RPC_REFILL |5|Credits regenerated each second|
| ZORX_RPC_AUDIT_THRESHOLD |8|Log every eighth rejected request in a five-minute window|

One RPC costs one credit, including retries and invalid requests. These are initial staging tuning values, not measured production capacity. Configure them in the server runtime Secret, not game client config. Startup rejects invalid/out-of-range settings. Keep server clocks synchronized; backward clock steps cannot create credits. Built-in authentication/device-account creation and HTTP infrastructure limits are separate from this per-account RPC budget; public production exposure still needs gateway abuse controls.

RPC wrappers cap payloads at4096 characters, then each handler enforces its exact schema (name handler1024). The private HTTP worker caps bodies at512KiB, headers4KiB,32 active connections and2.5s deadlines. It has no DB access or egress and only the Nakama pods can reach its ClusterIP service. Profiles remain server-side inputs; no client snapshot upload exists.

Direct client storage create/write/delete hooks protect all name, profile and budget collections. Storage read/write permissions0 prevent direct reads/updates; hook coverage includes pre-creation of absent objects.

## Audit

Rejected command/name/transport responses increment a bounded-window counter through CAS. Every configured threshold Nakama writes one warning containing RPC ID, machine error code, count and a12-hex SHA256 pseudonym of the internal account ID. No raw names, commands, request IDs, device IDs, IP addresses, tokens or local saves are logged by this module. Logs remain operational data and need retention/access controls at the operator level. A heavily contended audit write can be skipped; these warnings are diagnostics, not a financial journal.

Client key remains the public Nakama application key. Validator token, DB password, session/refresh signing keys and runtime HTTP key remain only in backend Secrets. Export exclusions and PCK audit keep server/build/test files out of Web bundles.

## Tests / release

`npm test --prefix server/names/runtime` tests shared storage budget, account isolation, refill, backward clocks, CAS contention, payload bound, protected quota storage and audit redaction. `python3 server/names/smoke_stack.py` repeats actual RPC burst rejection and restart persistence against isolated Nakama/Postgres, using a tiny test-only bucket. Its functional tests use a high disposable quota; production defaults remain20/5/8.

M3-4 and M3-5 ship in the same updated worker/runtime pair. Follow `server/profile/README.md` for local builds and **Boss's manual image push/deployment**. No image publication or remote apply is performed by these changes. Physical phone/live staging tests and off-machine restore acceptance remain pending.
