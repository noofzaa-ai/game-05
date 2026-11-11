# Guest Login — deployed and configured

Public Site key: `0x4AAAAAAFfYmmETLpxucNy3` (not a secret).
Widget: Managed, hostname `zorx.daiyooo.com`, action `guest_login`.

## Activation

1. Build/deploy Guest-capable Nakama runtime and landing images together. Game web changes only replace Google-specific loading wording.
2. On the k3s host, run `python3 guest_setup.py` interactively from a secure terminal. It asks for the Turnstile Secret key with hidden input; never pass it as a command argument or send it in chat. Requires existing cluster credentials and PyYAML.
3. Setup preserves existing Google settings, updates `landing-auth` and runtime config Secret, and saves private manifests under the existing staging deployment directory. Restart Nakama first, then landing. No script-driven deployment/restart happens automatically.
4. Until configuration is present Guest is unavailable. Live sign-in and CAPTCHA acceptance have not been checked.

## Security and behavior

- CAPTCHA verification happens at the landing backend with a timeout, exact hostname and action checks. Browser tokens alone cannot authenticate directly with Nakama.
- Gateway generates random Guest IDs, signs a 30-second custom-auth request with a separate shared secret; runtime verifies it, consumes its nonce through a private CAS record, clears proof vars from the resulting session.
- Durable quota: **20 Guest authentication attempts per rolling minute across all replicas** (including existing Guest logins). Concurrent CAS conflicts fail closed. Existing landing auth concurrency/token budget limits pre-verification work per process. This is not a substitute for edge DDoS protection.
- Native/test stacks retain their prior flag behavior. Public Device, Email, Custom without gateway proof, etc. stay closed under `ZORX_REQUIRE_GOOGLE=1`.
- Allowed Guest identities use server-created `zorx_guest_` custom IDs. Disabled accounts remain denied. Guest sessions have no email and gain no admin permission.
- Same browser can recover the Guest through an encrypted HttpOnly cookie for 180 days; browser data loss or another device cannot recover it. Logout invalidates game tokens but retains the Guest recovery cookie, so logging out/in does not farm fresh accounts.
- No automatic account merge or Google linking is added. Current explicit proof-of-ownership Google linking remains available through its existing flow.
- New public login files are versioned in `server/landing/dashboard/`, mirrored in the local `zorx_web` source; landing builder applies the overlay.

## Remaining manual acceptance

Valid/expired/duplicate CAPTCHA, hostname/action mismatch, direct Custom bypass, quota and concurrent requests, browser recovery/logout, Google login, Guest game/session refresh, disabled account, and mobile landscape layout. No automated tests were added or run.

## Deployment 2026-10-22

Nakama `guest-login-20261022-1@sha256:e0a8ad094974a2fe55cea239f8375db87753986fbb9fff645cae88191eca1beb`; landing `guest-login-20261022-1@sha256:8b11ecc97945432fe2b3dc1a5a065c3328ca833555ab424c649595a1af5bdaa9`. Both rollouts complete. Google configured=true. Guest configured=false: `landing-auth` lacks `TURNSTILE_SECRET_KEY`; no end-to-end Guest acceptance yet. Shared signing configuration was installed using `guest_setup.py --prepare` (preserves absent CAPTCHA Secret, stays closed). After Boss applies CAPTCHA Secret, restart landing to load it. No game export/profiles/rooms rollout.


2026-10-22 Guest activation: Boss reapplied landing-auth; all four Guest/Turnstile settings present (values not exposed). Restarted landing only; rollout complete. Public /auth/session now Google configured=true and guest configured=true. Real human CAPTCHA and in-game Guest acceptance still pending.
