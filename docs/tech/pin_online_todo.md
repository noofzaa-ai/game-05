# Card pin online: TODO (Boss 2026-11-26)

Offline pinning is done in `logic/` (`GameSim.set_pin / clear_pin / get_pin`, `Fighter.pin = {x, z}`, `AutoPilot._pinned`).
The server room runs the same `AutoPilot.decide` (`server/rooms/room.gd` `_auto_inputs`), so pinned cards behave the same once the room receives pins.

## Steps
1. **Command path.** `room.gd:384` drops all client combat input in squad rooms (`if squads and not lobby: return false`). Do not reopen that path; add a command like `party_ping` (`room.gd` ~596) with its own rate limit.
2. **Messages.** `card_pin {card: int, x: float, z: float}` and `card_unpin {card: int}`. `card` = fighter id.
3. **Validation (server).** Card owned by the sender (`owner_by_fighter[card] == player`), card alive and on the player team, x/z finite (GameSim clamps into the arena), rate <= 5 per second per player (drop the extras). Call `sim.set_pin(card, x, z, own_card_ids)` so a player keeps one pin (pinning another of their cards releases the first). Other players' cards are never affected.
4. **Replication.** `set_pin`/`clear_pin` emit `card_pinned {player, x, z}` / `card_unpinned {player}` events; pins also auto-clear (death, wave arrives, stage cleared) with the same events. Forward these to all players so everyone sees each pin. `Fighter.pin` is in checkpoints already (state_codec), so resyncs carry it.
5. **Client feel.** Show the pin marker instantly on tap (optimistic), then confirm/correct from the server event; drop the local marker if no confirm arrives in ~1 s.
6. **Tests.** Room test: own card pinned, foreign card rejected, 6th pin in one second dropped, events reach the second player. Latency: `tools/localstack/lagproxy.py` at 150 ms and 300 ms; the marker must appear at once and the card must start walking within one RTT.
7. **Deploy.** `logic/` changed: rebuild and redeploy the room-worker image, not only the web client.
