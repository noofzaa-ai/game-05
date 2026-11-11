# Admin portal

URL: https://zorx.daiyooo.com/admin . Uses verified Google website session.
Every HTML/asset/API route checks the server email allowlist. Private Nakama admin
RPC additionally rejects user bearer sessions and requires a separate service key.
No Nakama console, DB credentials or Kubernetes API permissions are exposed to a browser.

Features: worker rooms/players/RTT/tick/backlog/memory, database query latency and
account counts; bounded search and UUID cursor pagination; ban/unban with mandatory
reason, self/system-account protection; server-only durable requested/completed/failed audit.
Ban prevents login/game RPCs and new room-ticket redemption. It does not immediately
kick existing headless-room sockets. No inventory edits, account deletion or admin-grant UI.
Dashboard includes current snapshot (manual/15s) and30-day minute history collected by a private Nakama match without an admin browser. Chart24h/7d/30d averages5/60/180min buckets. Active heartbeat = seen within120s; room-player occupancy is separate and must not be summed. Missing worker samples are null,not zero; no fabricated backfill. Restart gaps remain visible. SQL retention deletes only server-owned metric collection records older than30days. Single Nakama node collector (current deployment); future multi-node needs leader election.
Worker metrics are for the current single room-worker service, not Kubernetes CPU usage.

## Email configuration

On k3s, `/home/wiyazard/deployment/game-test/zorx-staging/admin-config.json`:

```json
{"emails":["wanwit.phbn@gmail.com"]}
```

Add further exact verified emails to the array (case-insensitive; no domain wildcard).
Run `server/k3s/admin_setup.py` ON that host (or stream it over verified SSH), then
restart landing and Nakama. The helper synchronizes both runtime allowlists, reuses
the dedicated existing token, updates admin-secret.yaml / landing-secret.yaml0600,
and keeps existing secret.yaml copies in sync. It never exports credentials.
Public config.js is not an authorization source. Empty/invalid runtime allowlist denies access.
Changing the allowlist takes effect after both services restart; Google sessions need not
be recreated unless their8-hour lifetime has expired.

## Tests

- `npm run build --prefix server/names/runtime && npm test --prefix server/names/runtime`
- `python3 server/names/smoke_stack.py --admin`: real isolated Nakama/Postgres SQL,
  service-only boundary, ban/unban/audit on generated QA accounts only.
- Landing image: `docker run --rm --entrypoint node IMAGE server/test_admin.mjs`:
  synthetic cookies, unlisted403/anonymous401, tamper/CSRF, protected config and no-store/CSP.
- Never test ban/unban on production players without an explicit reason/authorization.

Admin source overlay is versioned in server/landing/dashboard; build_landing_container.py overlays it over sibling zorx_web. All route authorization/CSRF remains existing protected server boundary; history read uses same private admin RPC/allowlist. Metrics collection protected from client storage write/delete and read permissions0.

Character inspector: GET /admin/api/character?target=UUID,private service admin RPC. Read-only explicit profile-field projection,never calls profileWorker or writes storage. Shows saved name/appearance/camp/facilities/gold/materials/equipment/bag/vault,refine/upgrade/durability and serialized substat values. Excludes RNG/receipts/room IDs/fences/tokens. Active-room indicator and saved-data warning; no computed live combat totals,no item mutations. Uses textContent for all player data.

## Security review (2026-10-21)

Private Admin `security` operation lists accounts with observed rejection signals for 24h/7d/30d and per-account grouped reason/command/first/last/count. Same admin email/service-token boundary; read-only, no automatic ban. UUID cursor pagination (50 accounts), detail up to100 groups. Revision conflicts appear only as context on accounts with other signals, never independently qualify an account. Ordinary insufficient funds/full inventory are excluded. Rejections can also be client bugs or stale item references; investigate before enforcement.

Coverage: authenticated profile command RPC invalid payload/schema/count, unknown/disallowed commands, unowned items, changed request-ID reuse; protected Nakama storage write/delete attempts. Does not instrument room WS commands, movement, combat simulation or external database edits. No client build or extra WS messages. Existing authorization and game logic unchanged.

Telemetry uses a private no-join Nakama match. Rejected RPC/hook sends a bounded runtime match signal (no database write in signal handler); collector aggregates minute buckets and writes one batch after the minute ends. `matchSignal` is synchronous enqueue/handler transport, so not a guarantee of zero request latency; writes occur in collector ticks, not rejection handlers. VM sender budget50 signals/second, collector100/second,256 bucket keys maximum, counts capped100000 per bucket. Overflow telemetry is omitted; counts are observed bounded signals, not a forensic complete ledger. Retains pending rows on flush failure; shutdown best-effort flush. Crash/restart before flush can lose pending telemetry. Persistence failure never changes authorization/rejection. Collector logs capacity/persistence warnings. Raw payloads, request IDs, credentials and IP/device identifiers are not retained. Server-only `zorx_security_events_v1`,30-day retention. Single Nakama node, same topology limit as activity collector; multi-node requires coordinated collection before scaling.
