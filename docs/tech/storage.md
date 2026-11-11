# Storage ownership and UI

2026-10-20 — Storage NPC now opens a separate dark brass panel.

- Left: a new persistent `Profile.vault`, 20 slots (`data/camp/camp.json: bag.bank_slots`).
- Right: existing permanent camp inventory `Profile.stash`, labelled Backpack in this screen. Existing items/materials/gold remain untouched during migration. The separate Journey/run loot bag remains unchanged.
- Equipment takes one slot; materials retain the existing stack sizes. Transfer a single equipment instance or one material stack. Gold remains in the common wallet; it is not transferred.
- Desktop drag/drop between panes; mobile horizontal drag or hold then drag, vertical swipe to scroll, tap plus Deposit/Withdraw as an alternative.
- Empty legacy profiles acquire an empty vault on decode; first successful profile transaction persists it. No starter items are granted by creating the vault.
- Equipped gear is never included in the transfer list. Withdraw stored gear before equip/refine/upgrade.

## Authority and duplicate prevention

- Commands accept only an owned item ID, or a known material ID plus positive integral quantity, and a source container. Destination is derived by the server.
- Camp-only command handling; Nakama rejects camp commands while an active room holds the account lease.
- Duplicate instance IDs across backpack, vault, equipped gear and run bag reject the operation. Shop ID collision checks and one-time starter ownership scans include the vault.
- Server validates source ownership and destination capacity before mutation; transfer removes the existing instance and appends the same instance. It never creates an equipment copy.
- Both containers serialize in one profile CAS transaction. Existing revision checks, unique request IDs/fingerprints and receipts protect repeated/racing requests; no direct client database writes or profile uploads.
- Client never moves inventory optimistically. Pending operations lock transfers. Ambiguous network failures require a successful authoritative refresh before another transfer.
- Room snapshots, reconnects, account refresh, profile save/recovery and settlement preserve the vault.

## Operations / verification status

Native UI capture and compile/import checks only; no automated security suite or live-account inventory mutation was run for this request. Review actual staging interactions before treating this as an audited anti-cheat guarantee.
After any real deposit, do not roll the backend back to code that predates `Profile.vault`: old profile writers would drop the unknown field. Roll forward or preserve this field in a rollback patch.

Deployed `storage-20261020-1` to `zorx-staging`; public web build `d7a5853b5830`. Headless profiles/rooms both ready, Nakama and game ready; fixed remote manifests updated.
