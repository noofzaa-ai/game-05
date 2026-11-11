# Backend HTTPS/WSS through the existing Cloudflare Tunnel

Approved hostname: **zorxapi.daiyooo.com**.
Path: client HTTPS/WSS443 → Cloudflare Tunnel → existing Traefik HTTP80 →
`nakama.zorx-staging.svc:7350`. TLS terminates at Cloudflare. The origin leg is the
same HTTP path Boss already uses for the game.

## 1. Apply just the overlay on k3s

Copy `ingress.yaml` to the server and run:

```sh
kubectl apply -f ingress.yaml
kubectl -n zorx-staging get ingress nakama-public
```

Two resources only: Ingress `nakama-public` and replacement NetworkPolicy
`nakama-api-only` permitting API7350 from the existing Tailscale/same-namespace
sources plus **Traefik pods in kube-system**. No Secret regeneration, database
changes, pod restart, TLS Secret, cert-manager or new Traefik install is involved.
Postgres policy is unchanged. Console7351 is not exposed.

The overlay uses standard k3s defaults: IngressClass `traefik`, entrypoint `web`,
namespace `kube-system`, pod label `app.kubernetes.io/name=traefik`. Check these
with the actual controller if routing fails:

```sh
kubectl get ingressclass
kubectl -n kube-system get pods -l app.kubernetes.io/name=traefik --show-labels
```

The namespaceSelector and podSelector are in the **same peer** (AND), not two
separate entries that would allow all pods in kube-system. If Traefik uses a
custom namespace/label, update the builder options and generate the matching
policy. Do not replace it with an allow-all rule.

This overlay is applied **after** the original deployment. Reapplying the original
resources-only deployment later resets this policy; reapply this overlay after it.
Do not regenerate/reapply fresh credentials for this routing change.

## 2. Add a published application/hostname to the same Cloudflare Tunnel

Use the same origin Service URL that the existing `zorxplay.daiyooo.com` entry
uses to reach **Traefik80**. Do not point this entry straight at Nakama NodePort.

| Field | Value |
|---|---|
| Hostname | `zorxapi.daiyooo.com` |
| Service type | `HTTP` |
| Service URL | Copy the existing Traefik80 origin from the game entry |
| HTTP Host Header / `httpHostHeader` | `zorxapi.daiyooo.com` |

Preserve the API hostname in the origin Host header; Traefik selects this Ingress
by that header. No path rewrite/prefix is needed: `/healthcheck`, `/v2/...` and
`/ws` all go to Nakama. WebSocket upgrade is supported by Traefik without a custom
Upgrade-header middleware. Ensure Cloudflare WebSockets is enabled for the zone.
Use the existing edge HTTPS-redirect policy so HTTP does not remain the public
client endpoint. Do not add an origin HTTP→HTTPS redirect loop to this HTTP80 route.

If the tunnel is managed with a local config instead of the dashboard, add this
hostname before the catch-all and preserve the rest of the existing config:

```yaml
# Insert into the EXISTING tunnel's ingress list; origin is the existing Traefik80 URL.
- hostname: zorxapi.daiyooo.com
  service: http://EXISTING_TRAEFIK_ORIGIN:80
  originRequest:
    httpHostHeader: zorxapi.daiyooo.com
```

No tunnel credentials are required in this repository or chat. An interactive
Cloudflare Access/login page returned instead of the API is not a passing SDK/API
check; inspect that hostname's Access policy if encountered.

## 3. Verify after both changes are active

```sh
curl --fail https://zorxapi.daiyooo.com/healthcheck
```

Expected HTTP200 with `{}`. After Boss confirms the hostname is active, repeat the
existing-account checks and a real authenticated **wss://zorxapi.daiyooo.com/ws**
upgrade + ping/pong. Verify the public certificate normally; no certificate bypass.
An iPhone must also reach the endpoint with a valid certificate, then the actual
Web client needs its backend endpoint configured when M3-2/M4 integration lands.
These manifests alone do not wire the current game client to Nakama.

404 suggests host header/IngressClass/routing;502/504 suggests Traefik→Nakama
connectivity/policy or pod readiness. Existing Tailscale NodePort is retained for
comparison. This change has not been applied remotely by the dev machine.

## Rebuild on the dev machine only

```sh
python3 server/k3s/tunnel_ingress.py --output build/another-overlay/ingress.yaml
```

References:
- [Traefik Kubernetes Ingress routing](https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/ingress/)
- [Cloudflare WebSockets](https://developers.cloudflare.com/network/websockets/)
- [Cloudflare Tunnel origin parameters](https://developers.cloudflare.com/tunnel/configuration/)
