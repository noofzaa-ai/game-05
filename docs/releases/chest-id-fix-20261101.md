# Wave chest duplicate item IDs — 2026-11-01

Root cause: wave chest rewards called Journey.treasure_item while Journey.completed remained zero throughout the single arena. Every chest reused treasure-SEED-1, although wave loot differed. Commands correctly rejected ambiguous ownership with duplicate_item_id, blocking sales and other inventory mutations.

Fix: new rewards use wave-chest-SEED-WAVE-PLAYER. Trusted profile runner repairs only duplicate legacy treasure IDs across worn gear/stash/vault, preserving every item and its stats and retaining the first original ID. Profile GET detects those collisions, invokes the trusted worker outside active rooms, and persists repair through existing revision/CAS. Command ownership and duplicate rejection are unchanged. Reload profile before retrying a basket containing pre-migration IDs.

Deployed profiles and Rooms chest-id-fix-20261101-1; Nakama chest-id-fix-20261101-2. Both deployments Ready, remote manifests synchronized and backed up. Web stays build 9b77e80430dc; server-only patch.

Validation: Godot repair fixture preserves item count/stat serialization, is idempotent, and sells repaired gear through Commands.shop_sell_batch with correct gold. Same check passed inside deployed Linux profile worker using synthetic state, no player DB writes. Room 1–11 check asserts all three chest reward IDs distinct. Exact patched live Nakama JS passes equipment bridge, one-time CAS migration, duplicate chest trigger and repeat-read idempotency tests. Old fixture lacked diamonds/mall ownership and repeatedly triggered unrelated migration; corrected fixture supplies those fields.

Evidence/images: /tmp/zorx-chest-id-fix/*-image.json. No authenticated player sell interaction is claimed; user acceptance pending.
