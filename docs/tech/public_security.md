# Public origin hardening (2026-10-18)

- Apply `server/k3s/security.yaml` before attaching its Traefik middleware.
- Landing/Nakama: aggregate per-host bucket 100 requests/sec, burst200, body64KiB.
- Room upgrade: aggregate per-host bucket4/sec, burst8. Established gameplay frames are not HTTP requests and retain their own frame limits.
- These are origin-wide safety ceilings, not per-player quotas. They deliberately do not trust arbitrary forwarded IP headers. Tune using real traffic; large reconnect waves may receive429.
- Landing has an additional auth bucket5/sec burst40, max16 concurrent auth handlers. Session health reads are exempt; static assets cache1hour and successful file reads stay in bounded-by-file-set memory. Tokens/auth responses remain no-store.
- Worker reserves at most8 pending connections independently from32 player capacity, hard-closes pending TCP after3seconds, max40 total. Existing120frames/sec and frame-size limits remain.
- Nakama Service is ClusterIP only. Internal diagnostics must use kubectl port-forward or run within the cluster; port30350 is retired.

## Verification

Run full Godot suite, Python unittest discovery, TypeScript build/tests; then:
`godot --headless --path . --script res://tools/backend/security_admission_probe.gd`
The probe opens only loopback14175, verifies8 pending slots and hard timeout.
Use an isolated landing container to verify auth429/static cache/no-store; do not flood the public endpoint.

## Remaining edge controls

Cloudflare account rules and host/router firewalls are not managed by these manifests. Verify there is no public port-forward to Traefik80/443 or Nakama and restrict host access to Tunnel/Tailscale as appropriate without changing unrelated workloads. Configure Cloudflare WAF/rate limits for auth, API and WebSocket upgrades. Do not apply browser challenges to gameplay API responses indiscriminately.

Watch request429/5xx, room admission failures, peers, room tick backlog, CPU/memory and DB latency. Existing authenticated private worker metrics remain private; an external alert destination/monitoring stack must be configured separately. This is defense in depth, not a DDoS capacity guarantee.
