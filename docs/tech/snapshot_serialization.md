# Room snapshot serialization

The Room Worker hot path uses `public_state(viewer, true)`, an immutable borrowed
snapshot. The default `public_state(viewer)` still returns a detached writable copy
for external callers. Live simulation objects are never frozen or exposed.

`server/rooms/snapshot_cache.gd` caches serialized items, inventories, loadouts and
profiles within a room. It compares all persisted item fields and nested substats
against detached native values, not hashes or event notifications. Consequently
wear, loot, repair, equip, bank, materials, item ordering, appearance and facility
changes invalidate the relevant serialized data even if changed directly by logic.
Unchanged serialized ownership subtrees retain identity. Removed objects are pruned
on each snapshot cycle; ownership leaves with the room.

`NetState._meta_diff` skips identical subtree references before descending. Inventory
and item serialization no longer re-encodes every float/string and deep-copies the
full stash every 20Hz snapshot. Full snapshots, per-recipient redaction, baseline ACKs,
fragmentation, existing wire schema and authoritative gameplay are unchanged.
When adding persisted Item/Profile/Inventory fields, update this cache and its tests
alongside the canonical `to_dict()` schema.

The temporary client/worker performance telemetry introduced for the phone
investigation is removed at Boss's request: no timing rings, periodic reports,
ROOM_PERF logs or input-starvation counters. Existing Ping/FPS HUD and original
private worker health metrics remain. Cached older-client reports are ignored without
storing or logging them, so disabling collection does not break their sockets.

## Validation

- Full-kit cache equality with canonical serialization; every persisted item field,
  in-place substats, durability, balances/order/appearance/facilities.
- Nested immutable transport snapshots, caller copy isolation, prior baseline
  preservation, pruning, peer inventory privacy and real client delta reconciliation.
- Native Mac synthetic 155-item profiles, same 600 ticks and snapshot cadence:
  codec p95 1 player 3.79 → 1.42ms; 4 players 15.99 → 5.16ms. Encoded delta byte
  rate and initial full snapshot bytes stayed identical for these fixtures.
  These are controlled benchmarks, not a promise of device FPS improvement.
- Actual Linux/k3s benchmark and matched deployment results recorded in AI_SYNC.

### Isolated k3s follow-up

Same node, 1 CPU/512Mi limit, 155-item test kits and 600 ticks at 20Hz snapshot
cadence. CPU/no-network benchmark Job, no real users or database. Codec batch p95:

| Rooms / players | Before ms | After ms | After wall seconds per 10 simulated seconds |
|---|---:|---:|---:|
| 1 / 1 | 14.71 | 5.85 | 10.00 |
| 1 / 4 | 39.02 | 20.30 | 10.00 |
| 8 / 32 | 164.03 | 47.84 | 11.77 |

Full/delta byte totals stayed equal for every scenario. Eight full rooms on one CPU
still failed real-time acceptance (also simulation batch max20.57ms); this change
does not certify eight-room capacity or fix mobile rendering/input timing. Probe
used the same serializer as final release; the only subsequent transport change
ignores legacy telemetry without collecting it. Temporary Job, ConfigMap and
NetworkPolicy were deleted.
