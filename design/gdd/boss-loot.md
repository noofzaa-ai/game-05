# Boss Loot: Boss Sets, Relics, Boss Coins

Status: Approved direction (Boss 2026-11-16), spec v1 (PO). Owner: gameplay-programmer (rules), ui-programmer (screens),
art (icons). Game: a boss-farming loop. Each world-map zone (data/world/zones.json) is 9 waves with its boss at wave 9.

## 1. Overview

Every zone boss drops three things:

- pieces of that boss's **accessory set**;
- a rare **Relic** that sockets into gear;
- one **Boss Coin**.

Race sets (data/items/sets.json, weapon + 4 armour pieces) stay as they are. Boss sets live only in the accessory
slots, so the two never compete for a slot.

## 2. Detailed Rules

### Boss set (one per boss; v1 = the Goblin Chief)

- **Pieces.** Five items, one each for necklace, earring, bracelet, ring and back. Earring, bracelet and ring have
  2 slots each, so the same piece can be worn twice. That makes 8 worn pieces at most.
- **Set bonus.** Count the boss set pieces worn on a card (the steps live in sets.json, kind "boss"):
  - 2 pieces: ATK +5%
  - 4 pieces: max HP +8%
  - 6 pieces: ATK +10% while 3 or more enemies are within 4 m. This answers the next zone's swarms. If the condition
    is too much for v1, a flat ATK +6% is acceptable; say so.
- **Tiers.** Pieces roll tiers like other items. The set step numbers scale with the lowest tier worn among the counted
  pieces, the same way race sets use tier_mul.

### Drops (server-side, the run end on the authority)

- **Every boss kill:**
  - 1 Boss Coin of that boss, a stack material.
  - A 25% chance of one random piece from that boss's set. Its tier comes from the boss table.
  - A 1% chance of that boss's Relic.
- **First kill of each boss** (the same moment as `unlocks.boss_<zone>`): one set piece is guaranteed, at rare tier
  or better.
- **Squad size.** loot_by_squad scales the piece and Relic chances, as it does other loot. The coin is always 1.

### Relic (one per boss; v1 = the Goblin Chief's Relic)

- **What it is.** A stack item that is never worn on its own. It goes into an item's socket.
- **Sockets.** Boss set pieces and legendary items have 1 socket. Other items have none in v1.
- **Socket and unsocket.** Socketing is free. Removing a Relic is free and returns it intact (Boss: "too rare to
  break").
- **Effect.** The Relic's effect counts while the socketed item is worn. v1 Goblin Chief Relic: ATK +6% and crit
  +5%. Say so if a special effect is easier.
- **Commands.** These are new and server-validated: `relic_socket {item, relic}` and `relic_unsocket {item}`.

### Shop (Boss: clear the shop page, sell boss items)

- **Stock.** The shop sells only boss set pieces now. Each one costs **500 Boss Coins** of that boss, and only that one coin type per boss. The piece's tier is random: rolled at purchase on the server from the boss's `shop_tier_weights` (data/loot/boss_loot.json; white/blue/purple/gold all possible, placeholder 60/28/8/4), using the command's own rng. The shop card says "random tier".
- **Not sold.** Relics are never sold; they only drop.
- **Selling.** Selling gear for gold stays as it is.
- **Removed.** The old catalogue (race pieces for gold) is removed from the stock.

## 3. Formulas

- Coin farm time: 500 coins at 1 per boss kill is 500 wins. At about 3 minutes per run, that is about 25 hours per
  bought piece. **This needs a Boss check.**

## 4. Edge Cases

- **Online squad rooms.** Each player gets their own coin and rolls. The first-kill guarantee is per account.
- **A lost run.** No coin and no boss drops; only the waves' normal loot.
- **A socketed item that is sold or discarded.** The Relic returns to the stash first. A full stash refuses.
- **Durability 0.** The Relic's effect stops while the item is broken, the same as the item's stats.

## 5. Dependencies

- data/items/sets.json (kind "boss"), data/items/catalog.json (the new pieces and Relics), data/items/shop.json,
  data/loot/ (boss drops).
- logic/: loot / race_drops (drop path), item / item_system (sockets), race_sets (set steps), commands
  (relic_socket / unsocket, coin shop), world_zones (first kill).
- server/profile/runner.gd ALLOWED, server/rooms (run-end drops).
- Icons: 2D only. These items are never shown on the 3D model. They use the same style as the race gear icons in
  art/armor/race_shared/icon-*.png.

## 6. Acceptance Criteria

1. A goblin boss kill gives 1 coin. Pieces drop at about 25% and Relics at about 1% over a seeded sweep.
2. The first kill guarantees a piece, and a second kill does not.
3. Wearing 2, 4 or 6 boss pieces turns each step on, and removing one turns it off.
4. relic_socket and relic_unsocket work, the Relic returns intact, and a non-socket item refuses.
5. The shop lists only boss pieces at 500 coins. Buying spends the coins, and with too few coins it refuses.
6. A lost run gives no coin.
7. Everything works the same online, through the profile worker and rooms.
