# Online Squads (card squads in online rooms)

Status: Designed 2026-11-13 (game-designer via PO). Tier: standard. All open points decided by PO default (Boss rule: pick the recommended option, log in `docs/po_defaults.md`).
Boss decision (2026-11-13): online rooms field CARD SQUADS like solo: class skills, races, race passives, synergies, ultimates, skill tree, auto-pilot.

## 1. Overview

Today an online room (`server/rooms/room.gd`) gives each player ONE plain weapon-led `Run` (`Run.start(profile)`), so no card, class skill, race, synergy, ultimate or tree node applies online. This GDD makes an online room build the same thing solo builds: each player's cards become `SquadMember` fighters from that player's server-side profile, the server's auto-pilot plays every card, and waves, loot and XP scale by the total cards in the room. The room fields at most 6 cards. Players do not steer combat; they watch their own cards, ping, and the leader makes the few route/rest choices.

## 2. Player Fantasy (short)

"My squad fights beside my friend's squad." Each player sees their own cards (their build, their races, their gear) doing real work in a bigger fight, and both get the same loot they would solo. Aesthetics: Fellowship (shared fight, pings), Expression (your build, visible), Submission/Sensation (auto-battle spectacle).

## 3. Detailed Rules

### 3.1 Cards per player (DECIDED)

The room fields `cards_per_player(n) = min(SQUAD_MAX, floor(ROOM_CARD_CAP / n))` cards per player, `ROOM_CARD_CAP = 6`, `SQUAD_MAX = 3`.

| Players | Cards each | Room total |
|---|---|---|
| 1 | 3 | 3 (= solo) |
| 2 | 3 | 6 |
| 3 | 2 | 6 |
| 4 | 1 | 4 |

- Every player in a room brings the SAME number of cards (fairness: nobody is the "1" in a 2+1 split, no host choosing for others).
- Which cards: the first `k` class ids of that player's saved `card_deck.squad` (squad order). A player with fewer cards in the squad than `k` brings what they have (min 1). Players reorder their squad in the lobby with the existing `card_squad` command (lobby only); the room rebuilds on change (same as `rebuild_lobby`).
- Why the cap of 6: readability on a phone (6 friendly fighters + goblins is the most that stays legible; 12 is not), server cost (6 auto-piloted fighters is 2x the solo squad, bounded), and wave tuning stays in a measured range.
- Rejected: "each brings 3, scale waves" (up to 12 fighters, unreadable, 4x server cost); "room always 3, host picks" (2+1 is unfair and the host decides others' fun).

### 3.2 Squad synergy across players (DECIDED)

- Synergy is computed per **synergy group**, once at run start, fixed for the run (same as solo, `SquadMember.squad_synergy`).
- 1-3 players: each player's own cards are one group (`RaceData.synergy_for(races of that player's cards)`). Your build stays yours; nobody's race choice breaks yours. A 3-player room (2 cards each) gives each player a Pair or none.
- 4 players (1 card each): the 4 cards form ONE room group (`synergy_for` of 4 races: 4 different = Alliance, 3+ same = Trio, 2 same = Pair). Without this, 4-player rooms would have no synergy at all.
- A group's effects apply only to the members of that group (`all allies` effects in a synergy = allies of the same group). Race passives and ultimates that target "allies" keep targeting every friendly fighter in the room (team-based, as today in `RacePassives._targets`) — helping your friend is good.

### 3.3 Player input (DECIDED: spectate + social, no combat input)

- The server auto-pilot (`logic/auto_pilot.gd` `AutoPilot.decide`) produces every card's input every tick, including ultimates (PO default 2026-11-13: ultimates are fully automatic). Client combat input packets are ignored for squad rooms.
- Players can: pan the camera / follow one of their cards, use `party_ping` (existing, rate limited), and the leader makes route/rest/finish choices. No targeting, no ultimate timing.
- Why: the Boss ruled players do not press skills; manual input online would make online a different game from solo and adds prediction/rollback cost for 6 fighters.

### 3.4 Wave power and enemy HP by total cards (DECIDED)

- Online uses the same content and populate path as solo: `data/journeys/goblin_waves.json` (wave_mode) through `PartyJourney.start_party` → `Journey.populate` / `_populate_waves`, NOT the room's `ink_road` goblin wave lab. `fighters` = total cards in the room.
- Enemy power = `wave_power_by_squad[fighters-1]` (HP and ATK of each wave) x `combat.coop.hp_multiplier[fighters-1]` (HP), exactly the solo rule. 3 cards online = solo difficulty, bit for bit.
- Extend both arrays to 6 entries (starting values, tuned by sim, see 4.2).

### 3.5 Loot, race drops, XP (DECIDED: personal loot)

- Each player has their own bag (their account `Run`, shared by their own cards, as solo).
- **Personal loot**: every kill rolls a drop separately for each player still in the run, with that player's own factor `loot_by_squad[k-1]` (k = that player's card count), into that player's bag. A player gets exactly what solo with k cards would pay; nobody competes for drops; the tank is not starved by the bow.
- Per-kill RNG: each player's roll uses its own seeded stream (`"kill-%d-%d" % [enemy_id, player]`), so the sim RNG stream does not depend on the number of players.
- Chests: each player gets their own chest piece (as today), with their own loot factor.
- Race pieces: `RaceDrops.picks_for` that player's own cards only (a race piece always fits one of YOUR cards).
- XP: every card that started the run gets full card XP (skill-tree 3.7, not scaled). Gold/material rules follow the loot path above (same per-player factor).

### 3.6 Disconnect and reconnect (DECIDED)

- A disconnected player's cards keep fighting under the auto-pilot (nothing changes: the server already plays them). Their loot keeps going into their bag and is saved to their profile at run end like everyone's.
- Reconnect: existing `presence(player, true)` + scene gate; the client resumes watching from the current snapshot.
- Leader = lowest-id **connected** human. Leader-only commands pass to the next connected player at once.
- No human connected: existing room TTL / `finalize(aborted)` path (counts as a loss: cleared waves still pay).
- Mid-run "leave" = disconnect (cards stay, loot still saved). Companion bots are not used in squad rooms (the 1-player room is the player's own 3 cards).

### 3.7 Automatic room flow (DECIDED)

- Wave chest: opens automatically on the server after the clear delay (no walking to it, no leader press); each player gets their piece.
- Rest/camp and route choices: the leader chooses; if no choice in `auto_continue_seconds` (20 s), the server takes choice 0 / continue.

### 3.8 Server-side profile authority (DECIDED)

Everything a card fights with comes from that player's profile as received by the server (`Room.create` → `Profile.from_dict`), never from the client:
- squad cards and order (`card_deck.squad`), each card's race (`CardDeck.race_of`), level/XP and tree (`skill_tree` block), worn gear (`card_gear[card]`), looks.
- Room creation fails (`invalid_payload`) when: the deck fails `CardDeck` validation, the squad is empty, a picked card has no `card_gear` entry, or the tree fails its loader check (spent points > earned, unknown node).
- In-run gear commands (rest) work per card: the request names `card`, and the server checks the card belongs to the sender.

## 4. Formulas

### 4.1 Cards per player
`k(n) = min(3, floor(6 / n))`, n = players 1..4 → 3, 3, 2, 1. Total `F = n x k(n)` (capped by each player's squad size) → 3, 6, 6, 4.

### 4.2 Enemy scale (same as solo)
`enemy_HP = base_HP x stage_power x wave_power_by_squad[F-1] x hp_multiplier[F-1]`, `enemy_ATK = base_ATK x stage_power x wave_power_by_squad[F-1]`.
Starting values (tune, target: a room of starter cards wins 72-75%, same as the solo starter squad):

| F | wave_power_by_squad | hp_multiplier |
|---|---|---|
| 1 | 0.5 (existing) | 1.0 (existing) |
| 2 | 1.0 (existing) | 1.6 (existing) |
| 3 | 2.01 (existing) | 2.2 (existing) |
| 4 | 2.3 (new, start) | 2.8 (existing) |
| 5 | 2.6 (new, start) | 3.4 (new) |
| 6 | 2.9 (new, start) | 4.0 (new) |

Example: F = 6, wave 1 goblin with 100 base HP, stage power 1.0 → 100 x 2.9 x 4.0 = 1160 HP (solo squad of 3: 100 x 2.01 x 2.2 = 442). Six cards have about 2x the solo DPS; the extra HP covers that plus ATK scaling taking longer to bite with more targets to spread over. Must be re-measured with `tools/balance/class_sim.gd` (6-card scenario) before release.

### 4.3 Loot
Player p's chance per source = solo chance x `loot_by_squad[k_p - 1]` (0.33 / 0.67 / 1.0). Room faucet = sum over players; per-player faucet = solo with k cards.

## 5. Edge Cases

- Player's squad has 1 card in a 2-player room: brings 1 (k is a maximum). F counts real cards, so wave power uses the real total.
- Same class in two players' squads (two Sword & Shield): allowed; they are different accounts' cards.
- Everyone's cards down: run lost (`PartyJourney.died` → all runs `death()`, cleared waves pay), as solo.
- One player's cards all down, others alive: that player's run ends as a death for loot purposes only when the room ends (their cards stay DOWNED/DEAD; they keep watching). Rewards already in their bag are kept (bag secured at room end).
- Disconnect during the chest: chest is automatic; the offline player still gets their piece.
- Player joins mid-run: not allowed (room is closed after depart), as today.
- Profile changed elsewhere during the run: the room's copy is authoritative for this run; save merge stays as today (`finalize` returns the room profiles).
- 4-player room group synergy with 4 of the same race: Trio (`synergy_for` uses >= 3).
- Old saves / non-squad room checkpoints (`party_v` 1/2): still load; squad rooms write `party_v` 3.
- Fighter ids: player slots stay 1..4 (connection ids); fighter ids are separate (see chunk 1), so no id collision with enemies (enemies start at 100 / 10000).

## 6. Dependencies

| System | Direction | Contract |
|---|---|---|
| `logic/squad_member.gd` | uses | `make_squad(base, cards)` per player; synergy group override for 4-player rooms |
| `logic/coop_journey.gd` | changes | several squads (one per player) in one party, up to 6 fighters |
| `logic/game_sim.gd` | uses | `attach_run` (SquadMember → race passives, class skills, ultimates), per-player loot roll in `_give_drop` |
| `logic/auto_pilot.gd` | uses | `decide()` run on the server for every friendly fighter |
| `logic/race_data.gd`, `race_passives.gd` | uses | `synergy_for`; group-scoped synergy effects |
| `logic/race_drops.gd` | uses | `picks_for(player's member)` |
| `logic/net_wire.gd` (+ skill_net / race_net fields, other agent) | uses | skill state, race/ultimate gauge on the wire |
| `server/rooms/room.gd`, `manager.gd` | changes | squad room build, auto input, auto chest, leader rule |
| races-and-classes.md 3.5, skill-tree.md 3.7, drops-and-rewards.md 3.8 | reads | this doc adds the online rules; those docs should link here |

## 7. Tuning Knobs

| Knob | File | Default | Range | Category |
|---|---|---|---|---|
| `room_card_cap` | `data/combat/combat.json` coop | 6 | 3-6 | gate |
| `wave_power_by_squad[3..5]` | `data/journeys/goblin_waves.json` | 2.3 / 2.6 / 2.9 | 1.5-4.0 | curve |
| `coop.hp_multiplier[4..5]` | `data/combat/combat.json` | 3.4 / 4.0 | 2.8-5.0 | curve |
| `coop.max_players` → fighters | `data/combat/combat.json` | 6 fighters | 4-6 | gate |
| `auto_continue_seconds` | `data/combat/combat.json` coop | 20 | 10-60 | feel |
| `loot_by_squad` | `goblin_waves.json` | unchanged | — | curve |

## 8. Acceptance Criteria

1. A 1-player online room builds 3 SquadMember fighters from the server profile; same seed + same profile gives the same outcome as solo `LocalSession` (win/loss, waves cleared, haul) — headless parity test.
2. 2/3/4-player rooms field 6/6/4 cards; each card has its class skills (`skill_state.class` = card class), race passive, ultimate move registered, tree nodes applied.
3. Synergy: 2 players with Elf+Elf+Human and Viking x3 → player 1 Pair Elf, player 2 Trio Viking; neither applies to the other's cards. 4 players (Human, Elf, Viking, Runeborn) → Alliance on all 4.
4. Client combat inputs in a squad room change nothing (test: random input bytes vs none → identical sim state hash).
5. Personal loot: in a 2-player room, each player's haul over 30 seeds is within 10% of a solo 3-card run's haul; race pieces only ever match that player's cards.
6. Disconnect at wave 4: that player's cards keep acting (they deal damage in waves 5+); their bag is saved at finalize. Reconnect resumes the snapshot. Leader disconnect: next player can send `journey_choose`.
7. Profile tamper: a profile whose tree spends more points than earned, or whose squad names a card without `card_gear`, is rejected by `manager.create` with `invalid_payload`.
8. Balance: class_sim 6-card starter room wins 72-75% over 60 seeds (tuning gate before release, not a unit test).
9. Experience (playtest): on a phone, a player can tell their own cards from a friend's within 2 seconds (owner tint/name plate), and 6 cards + wave stay readable at 30+ fps.

## 9. Implementation plan (headless first; each chunk keeps `tests/run_all.gd` green)

**Chunk 1 — Party of squads (logic only).**
- `logic/coop_journey.gd`: `start_party` accepts trips from several squads: members of one squad share a profile; different squads must have different profiles; size limit `coop.max_fighters` (6) instead of 4. Add `owner_by_fighter: Dictionary` (fighter id → player slot) and `fighters_of(player)`. `_paying_players` already pays once per bag (keep). `to_dict`/`from_dict`: `party_v` 3 = `squads: [{player, run (shared, with profile), members: [member_fields + fighter id]}]`; v1/v2 still load.
- `logic/squad_member.gd`: `make_squad(base, cards, synergy_override := {})` so a 4-player room can pass the room-group synergy.
- `logic/race_data.gd` / `logic/race_passives.gd`: synergy effects target only fighters whose run has the same `squad` (group) — add `group` id to `squad_synergy`.
- `data/combat/combat.json`: `coop.max_fighters` 6, `room_card_cap` 6, `hp_multiplier` 6 entries, `auto_continue_seconds` 20. `data/journeys/goblin_waves.json`: `wave_power_by_squad` 6 entries.
- Tests: new `tests/test_online_squads.gd` (registered in `run_all.gd`): party of two squads builds 6 fighters; synergy per group (AC 3); save/load v3 round trip; v2 still loads; same profile in two squads rejected.

**Chunk 2 — Room builds squads.**
- `server/rooms/room.gd` `create()`: per player `k = cards_per_player(n)`, cards = first k of `card_deck.squad`; `Run.start` → `SquadMember.make_squad`; fighter ids assigned 1..F in player order, `owner_by_fighter` kept on the room. Always `PartyJourney.start_party` (even 1 player with 3 cards, as solo). Validation per 3.8 → return null.
- `server/rooms/manager.gd`: squad rooms load `goblin_waves` (wave_mode) journey data; `ink_road` lab stays for farm/legacy only. `_start_stage`: skip `_start_goblin_waves` when `journey.data.wave_mode`; populate places all F fighters.
- `connected`/`queued`/`presence` stay keyed by player slot; `trip_for(player)` returns that player's shared run; `_names`, `owned_profiles`, `finalize` iterate players, not fighters.
- Tests: `test_online_squads.gd`: 1/2/3/4-player rooms field 3/6/6/4 (AC 2); tamper cases rejected (AC 7); update `tests/test_party_online.gd`, `test_room_worker.gd`, `companion_room_contract.gd` expectations (companions disabled in squad rooms).

**Chunk 3 — Auto-pilot authority.**
- `room.gd tick()`: for squad rooms, every friendly fighter's frame = `AutoPilot.decide(sim, sim.combat, fid, memory[fid], sim.tick_count)` (memory seed `fid * 7919 + 1`, same as `LocalSession.auto_input`); `input()` returns false (ignored) in squad rooms; held-input / melee-rewind code skipped for them.
- Auto chest: in `_tick_goblin_waves`/wave-mode chest, open after the clear delay without a command. Leader = lowest connected human (`party_state.gd leader()` takes `connected`). `auto_continue_seconds` timer for rest/route.
- Tests: AC 1 parity (1-player room vs `LocalSession` same seed/profile, compare waves cleared + haul + final HP), AC 4 input ignored, AC 6 disconnect/leader handover.

**Chunk 4 — Personal loot.**
- `logic/game_sim.gd _give_drop`: when the sim has `loot_players` (player → {run, factor}), roll once per living player with that player's factor and own RNG (`rng_for("kill", enemy_id, player)`), race picks from that player's run; else today's path. Room/`PartyJourney.populate` fills `loot_players`.
- `logic/journey.gd treasure_drop` / room chest: per-player factor.
- Tests: AC 5 (30 seeds haul within 10% of solo), race piece fits owner's cards; `tests/test_loot_by_squad.gd`, `tests/test_race_drops.gd` still pass.

**Chunk 5 — Wire and client display.**
- `logic/net_wire.gd`: depends on the skill_net / race_net fields (other agent; do not edit the same file at the same time). Add room meta `squads: {player: [{fighter, card, race}]}` and per-group synergy in `public_state`.
- Client (`client/session/remote_session.gd` or equivalent, `stage_view.gd`, `squad_panel.gd`): no local prediction for squad rooms (interpolate snapshots), squad panel shows own cards, owner name plate/tint on friends' cards. UI agents own this part.
- Tests: snapshot contains squad meta; wire size budget for 6 fighters checked in `tests/test_netcode.gd`.

**Chunk 6 — Balance pass.** `tools/balance/class_sim.gd` scenarios for 4/5/6 cards; tune `wave_power_by_squad[3..5]` to 72-75% (AC 8); log in `docs/po_defaults.md`.
