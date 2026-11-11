# Friends / Invites online menu

- Online entry uses two independently scrollable columns, waiting-room capacity and Create in the header, existing-room resume, and advanced character-name/invite-code entry.
- Short landscape screens keep the roster in view and move management/code tools behind More. Invite accept/reject remains inside its own scroll column.
- Accepted friends list includes server-derived room count/capacity/start/joinable status. No invite hash/code is returned in the roster.
- Direct join passes only the friend's account ID. Server verifies an accepted friendship, resolves the owner's current camp, rechecks owner/membership/start/capacity and atomically claims the member slot with existing profile/room fences. Friends of non-owner members still need an invitation. Started/full/expired rooms reject.
- Invite a camp friend creates the party camp then sends the existing persistent notification; cancellation is attempted if delivery fails. Existing link/code joins and friend management remain available.
- Client presence heartbeat25s; online expires75s after last heartbeat (or active room lease). The roster refreshes15s while open. It is not instantaneous presence.
- Acceptance/rejection of notifications remains owner-scoped. Invitation expiration/capacity is rechecked on actual join.

Validated: full Godot suite, Python/TypeScript regressions, actual isolated4-player party using one direct friend join plus nonfriend denial, native desktop and854x393 UI renders. Physical iPhone acceptance remains manual.

Friend pages use one parameterized SQL projection of names/presence/room metadata for at most50 server-provided friend IDs; inventory JSON is not returned or loaded into the runtime for presence display.

## Lobby Back recovery
Final leave controls are drained even after the socket begins/closes its handshake. A terminal room/membership rejection stops rejoin attempts; Back returns to main camp. If a leave was requested and its acknowledgment was lost, terminal membership rejection completes navigation without asserting a save occurred; the account snapshot is refreshed from the server. In-flight reconnect responses are generation-checked and cannot resurrect a deliberately closed session. Isolated party probe covers the last member leaving after1.2s without polling and intentionally discarded ACK.
