# Card pin online: DONE (Boss 2026-11-26)

Offline rules live in `logic/` (`GameSim.set_pin / clear_pin / get_pin`, `Fighter.pin`, `AutoPilot._pinned`). The room
runs the same `AutoPilot.decide` (`server/rooms/room.gd` `_auto_inputs`), so a pin received by the room moves the card.

## What was built
- **Commands** (`server/rooms/room.gd` `_card_pin_command`): `card_pin {type, card:int, x:number, z:number}` and
  `card_unpin {type, card:int}` over the normal CONTROL command path (raw combat input stays ignored in squad rooms).
  Exact key set (extra keys = `invalid_command`), x/z finite, card owned by the sender (`fighters_of(player)`), not an
  enemy/companion, only while `status == "active"`, the journey is IN_STAGE, not lobby, not scene loading
  (`not_available_here`), 5 commands per rolling second per player (`rate_limited`). Calls
  `sim.set_pin(card, x, z, own cards)` (clamped by logic; result `{ok, pin:{x,z}}`) or `sim.clear_pin`.
- **Replication**: `card_pinned {player:<fighter id>, x, z}` / `card_unpinned {player}` go out as numbered room events
  (the same stream as every sim event). Command-time events are relayed at once. When `set_pin` silently releases the
  player's other pin, the room also sends `card_unpinned` for it. Auto-clears (death, wave, win) come from the tick's
  sim events. Cost is about 40 B per pin event, only on taps.
- **Client** (`client/session/online_session.gd`): `set_pin` checks the card is the local player's (`own_cards()` from
  meta.squads), sends `card_pin`, and returns the locally clamped prediction at once. The prediction is held until the
  command result (ok -> server pin, refused -> dropped) or 1.5 s. Pins also follow `card_pinned/unpinned` events, and
  pins are cleared on a new epoch or outside a fight (`pin_allowed()`). `client/card_pin.gd` is enabled for sessions
  with `pin_allowed` (room fight sessions; the camp AccountSession stays off). It only selects the local player's own
  cards (`own_cards`). `stage_view.gd` no longer excludes squad rooms.
- **Tests**: `tests/test_card_pin_online.gd`.
- **Lag check** (local stack + `lagproxy.py`, 2026-11-26): marker at once. Server confirm at 148 ms (150 ms RTT) and
  297 ms (300 ms RTT). At 150 ms the card reached about 1.5 m of the pin within about 4 s.

## Deploy
`server/rooms/room.gd` and the client changed (`logic/` unchanged in this step): rebuild the room-worker image and the
web client. The profile worker is unchanged.
