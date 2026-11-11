# ADR 0003 — One server-owned character for solo and co-op

Accepted by Boss, 2026-10-18. Supersedes ADR 0002's separate offline progression policy.

- Player-facing gameplay requires an authenticated connection. Solo uses an authoritative one-player Godot room; co-op uses the same authority with more players.
- Camp inventory, equipment, appearance and upgrades use authenticated profile commands. The client only displays returned snapshots, including after ambiguous failures.
- No local-save inventory import, merge or offline reward upload. LocalSession remains an internal simulation/test tool, not an account progression path.
- Leaving a room reloads the same account profile after server settlement. Reconnection resumes the server room; it never converts the current fight into local authority.
- Staging may set ZORX_BETA_TEST_KIT=1 on BOTH Nakama runtime environment and private profile worker. An account receives the catalog kit once (beta_kit_version=1), with persisted bonus stash slots. Discarded items do not respawn on login. This flag is absent in production. No client grant command exists.
- Appearance is selected through server commands and carried in each player's room profile, alongside their equipped items.
- Single-map Farm is a server-built one-stage room using validated PvE map content. PvP remains unavailable.

This reduces client-side item fabrication; it is not a guarantee against every cheat or implementation exploit. The target-host capacity and physical-device acceptance gates from M6 remain open.
