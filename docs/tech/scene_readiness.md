# Scene presentation barrier

Gameplay WebSocket rooms (solo Journey/Farm and co-op) require a per-player,
per-epoch `scene_ready` acknowledgement. Receiving a snapshot is not presentation readiness.

StageView builds the map, actors, camera and HUD, then waits for two rendered
frames before acknowledging the epoch it actually built. Headless test scenes
use process frames or explicitly acknowledge their asset-free mock scenes.
Stale callbacks cannot acknowledge a newer scene. RemoteSession retries the
acknowledgement while the server still lists that player as waiting.

While any required player is loading, the authority does not advance GameSim,
room clock, AI, movement, damage or combat timers, and rejects gameplay input.
Client prediction is also suspended. Neutral input packets acknowledge snapshot
baselines without entering the simulation, avoiding repeated full inventory
snapshots during the loading interval. Ping and connection/lease handling continue.
The client shows a waiting message; every party member must become ready.

The barrier resets on stage changes, party departure and lobby rebuilds. A
reconnecting non-eliminated player also waits for readiness before play resumes.
Existing disconnect/empty-room deadlines still apply. Loading is bounded to120s;
a room that never becomes ready closes with `scene_load_timeout` and follows the
existing aborted-room settlement path. It never starts combat merely because
the loading deadline expired. This handshake is a start barrier, not proof of a
client's honesty or a permanent invulnerability flag.

Private in-process authority tests opt into the gate explicitly; the production
WebSocket transport enables it immediately after allocating the room. The scene
protocol requires matching Web/Room Worker versions. Existing old clients must
reload after rollout; there is no fallback that silently starts combat for them.

Validation2026-10-18: full Godot2405/0 with empty stderr, Python58/0, TS11groups.
Actual isolated Nakama/Postgres/Godot4-client party test withholds the fourth
client's presentation ACK for several seconds: all clients stay on the same
frozen tick, then start after its ACK; full party/leave/Friends flow passes.
Physical Safari/GPU warm-up acceptance remains manual.
