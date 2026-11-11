# Mummy private Solo preview

Owner UUID `76f7165a-18c4-4300-9c0d-9996173c6ae9` (ff). This identifier is an admission allowlist,not a secret; character name is not an authorization input.

World Map shows an extra bottom-left `ทดสอบพีระมิด · Solo` button only for that authenticated account. It requests existing room-create transport with capacity1/farm_map=mummy_ascent. Nakama authoritatively rejects all mummy_* farm entry except this owner+exact route+capacity1+noncamp. Direct mummy_arena_* entry is rejected even for owner. Ticket creation/resume rechecks ownership/capacity and join rejects other accounts. Worker receives route selection only from authenticated private Nakama backend;not from client WS packets.

Manager builds a3-stage Journey from current Mummy map spawns and fixes ordered nodes to mummy_arena_a,b,c. No random camp/treasure/boss injected. Existing clear→exit selection→next epoch/scene loading and final Journey completion/return-to-camp logic retained. Map index/normal Ink Road unchanged. Existing item wear,death and loot rules apply;this is not an inventory sandbox. Existing in-match resume behavior remains.

Mummy has no dedicated clips yet;static-model movement/attack fallback is expected. Scenery uses existing stage rendering and scene-loading acknowledgment. Private entry is an access restriction,not asset confidentiality: web clients can download packaged art. No authenticated owner playthrough or performance benchmark performed. No automated tests requested.

Deployed2026-10-21 from3644c31: web/Nakama/rooms `mummy-private-20261021-1`;public build1cadb2ce242c exact local manifest match. All three deployment rollouts successful;room startup ready,runtime registered. No automated tests or authenticated ff playthrough performed.
