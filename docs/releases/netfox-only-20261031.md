# Netfox-only online runtime — 2026-10-31

Boss requested removing the old networking completely after normal URL selected the custom prediction path despite latest Web build.

## Released

Web build `cf4ac0c4dc0b`: `wiyazard:30500/zorx-web:netfox-only-20261031-1@sha256:feed9f96a07b814e914f9a4207fa687e5c03d5f1eacd1e7908a6469ecc64409d`

Rooms: `wiyazard:30500/zorx-room-worker:netfox-only-20261031-1@sha256:565c9a1931e26223e30e39c36a4a570cfa385e5fd64139efc3ba64d9110d3495`

All online room admission uses Netfox regardless of URL, solo/party/farm or companion. No query enables the retired custom session. Removed client custom prediction/reconcile/control clock/interpolation and lab runtime; Netfox inherits only the extracted online account/lifecycle/read-view helper. Server uses only SceneMultiplayer WSS8061; old raw WSS8060 listener and transport file are absent. Live `/proc/net/tcp` shows1F7D(8061)LISTEN and no1F7C(8060). Existing API ticket URL `/room` is translated to `/room-v2` by the sole client; auth/backend lifecycle unchanged. Raw Wire codec remains solely for command/event receipts, not movement.

Readonly false compatibility properties remain for compiled camp UI; no query/branch can enable those modes. Local game simulation remains necessary for training/shared prediction and is not an alternate online session.

## Verification

- Actual Room native solo,epoch,reconnect PASS; co-op initialFAIL then per-peer-open broadcast fix, rerun server+bothclients PASS. Inputs accepted without window rejections in final runs.
- Netfox-only source cutover + settlement receipt idempotence/expired-room behavior PASS.
- Exact shipped core parse PASS, explicit absence of legacy session/compiled baseline/labfiles checked; unrelated core/content bytes identical; core download119622bytes smaller.
- Godot Linux exact candidate worker parse PASS in isolated/tmp copy of productionproject.
- Public packs/core exact-byte verified; both rolloutsReady; live worker file absent/port check PASS. game.yaml/headless.yaml image-only synchronized with .before-netfox-only-20261031-1.bak. Profiles,Nakama,data/balances unchanged.
- Fullsuite40s FAIL+timeout: cleanup/profile/account/co-opcheckpoint fixtures, not fullgreen.
- Safari actual normal URL observed loading build and Guest login. First profile fetch failed transiently; retry connected. Extended Web combat/co-op acceptance pending; no performance claim.

## Evidence/rollback

Local `/tmp/zorx-netfox-only-release`: patch-report,core,web.json,rooms.json,cutover.log,shipped.log,linux-check.log,full-suite.log. Room logs under build/netfox-migration. Retired tests preserved verbatim at docs/tech/legacy-netcode-tests. Source changes retained, no unrelated workspace fullbuild.

Rollback Web `wiyazard:30500/zorx-web:lag-report-20261031-1@sha256:487821cde94b91a52f44d9631ae3a259a7fd5c118a13215b9f064c248686f48c`; Rooms `wiyazard:30500/zorx-room-worker:goblin-base-20261031-1@sha256:161d16d761ebe483f0e3e74c07210ee49501b7f87568615089484e43c8c435d9`. Old cached pages must reload; no old listener fallback.

## Actual Web follow-up

Safari perftest-01, normal URL with no netfox/replay flags: authenticated, entered Practice Field, moved, dodged and cast skill; report button accepted upload. Retrieved report confirms mode netfox_authoritative_room and worker netfox-only-20261031-1,accepted7070,source_input21474,network/reference21487/21490. Rejected47(frame1,past_history46) cumulative; low11–13FPS and startup delays remain, so this proves cutover/control/upload only, not elimination of every latency/performance issue. Native co-op is not Web two-player acceptance. Temporary opt-in HTML stderr overlay was deployed during diagnosis then removed by restoring the same Netfox-only Web image; core/build unchanged. Web room entry initially delayed and recovered after assets/sync; keep this as OPEN investigation, do not call responsiveness fully accepted.
