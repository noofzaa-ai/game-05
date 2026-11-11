# Gathering plaza — camp north extension

Boss approved 2026-10-20: keep camp as the main map; extend behind the old warp, move warp farther north, automatically see online players in a similarly sized plaza.

## Layout

- Existing spawn, campfire, shops and account services stay in the original southern camp.
- Northern clearing x±12.5m,z -33..-13m; connecting path x±3m.
- Entry z-12.2; plaza center(0,-22); warp(0,-29.5),arch z-30.8.
- Shared stone square, benches, lanterns and painted warm ground lighting. No new image textures.
- Enlarged centered physics bounds have an explicit south-limit blocker; original corner blockers retained and path edges blocked. Terrain stays flat within the walking area.

## Presence

- `client/online/plaza_client.gd` joins automatically when walking north of entry and closes the socket on return to private camp or scene exit.
- Dedicated Nakama authoritative match `zorx_plaza`,5Hz movement snapshots,24 accounts per channel. Discovery uses a server-only CAS channel registry plus labelled matches with space; concurrent first arrivals converge on the registry winner, creates another when full. Registry writes occur only at channel creation/replacement, never for movement. Empty matches retire after20s.
- Channels are automatic. Existing friend invitation and co-op departure remain in their existing menus; this first plaza does not add a new click-player party UI/chat UI/channel picker.
- Public identity comes from authenticated Nakama session. Only named Google-linked eligible accounts admitted; duplicate account sessions in the same match rejected.
- Gear and appearance read from server-owned profile on join. Only worn loadout/appearance/name projected; stash,vault,currency,receipts,RNG excluded.
- Avatar interpolation on client; no player-vs-player collision. Appearance payload once/sec,positions5Hz; at most2 new character rigs instantiated per snapshot to bound joining spikes. Ownership changes reconnect to refresh visible gear.
- No SQL/storage writes for movement. Match input is bounded finite x/z/facing/speed,256bytes,one processed message/account/tick; displacement clamped and coordinates restricted to plaza. This is cosmetic social presence, not authoritative combat physics.
- No economy commands/rewards/trade/profile snapshots accepted here. Existing account Commands and gameplay room fencing still own all equipment and progression.
- Private-camp players are absent from shared snapshots. Camp Level remains account-owned and is not replaced by the social channel.

## Operational scope / limits

Web + Nakama runtime updates only. No Postgres migration,headless simulation changes,ConfigMap balance changes or namespace beyond zorx-staging.
Actual24-player phone performance and two signed-in human clients still need acceptance; capacity is a conservative initial cap, not a measured promise. No automated tests requested/run in this task. Native layout/source loading and TypeScript compilation are recorded separately in PROGRESS.

## Release

2026-10-20: public web010730885df8(source4e2e160), Nakama gathering-plaza-20261020-3(sourcee6984de); both deployments1/1 ready/available. Runtime uses named global match callbacks required by Nakama, CAS canonical channel discovery. Two signed-in humans and phone24-player performance remain acceptance work; do not report them as passed.
