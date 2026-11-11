# Online runtime migration gates

This folder is excluded from the main Godot import with `.gdignore`. No library autoload or peer endpoint is enabled in the production game by these checks.

Run on the configured Mac:

```sh
python3 tools/netcode/migration/check_netfox.py
```

The runner builds a disposable project under `/private/tmp`, copies pinned MIT netfox1.35.3, the actual game's `logic/` and data, then checks:

1. Godot4.7.2 imports the exact library release.
2. Netfox NetworkTime and RollbackSynchronizer can drive the production GameSim through an actor adapter at60Hz.
3. Two separate native processes exchange client-owned input and server-owned actor continuation over Godot WebSocketMultiplayerPeer on **127.0.0.1:19477 only**.
4. Both actors advance and the client receives authoritative state history. The world bounds are enlarged so merely reaching a common clamped map edge does not imply synchronization.

These are correctness/API/RPC contracts. They are NOT a performance benchmark, not real account admission, not a deployed test room, not a claim about Web/Cloudflare lag, and not proof of full skill or economy parity. Scripted rightward input is only an adapter contract.

Artifacts: `build/netfox-migration/compatibility.json`, `import.log`, `contract.log`, `server.log`, `client.log`. Network-restricted sandboxes need localhost socket permission; do not mistake bind/connect denial for library incompatibility.

`logic/net/actor_continuation.gd` is a versioned immutable body/fighter snapshot. It rejects missing/extra/wrongly typed fields, nonfinite values and wrong actor IDs before mutation, including typed-array element mismatches. It excludes local Callable hooks and computed facing aliases. It does not claim to capture private skill runtime queues or global AI/RNG; those remain explicit migration gates.

`actor_bridge.gd` is an isolated Node adapter around the actual shared simulation. The actor/state authority is server, input-child authority is assigned separately; input broadcast is disabled. It is not wired to the live game and must not be exposed to public clients without the authenticated room gate described in ADR0019.

Architecture and rollout requirements: `docs/adr/0019-online-runtime-migration.md`.
