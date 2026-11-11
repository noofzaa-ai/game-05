# Retire the staging full-catalog grant

Boss requested one equipped weapon/outfit instead of every catalog item (2026-10-18).
The private profile runner no longer grants full kits, even if a legacy environment
flag remains. New accounts retain the normal starter equipped gear. Existing v1
profiles remove spare stash entries whose instance ID is exactly `beta-v1-` plus
its catalog ID. All currently equipped pieces (including beta pieces), earned stash
items, gold, materials, appearance and RNG are preserved. No bulk player reset.

The migration marks `beta_kit_version=2`. A retained beta piece can be unequipped
later without being removed. Temporary bonus slots are retired except capacity
needed to preserve earned items/material stacks. The kit marker is not a version of
the item schema. The all-item TestKit remains available for isolated art/QA tools.

Nakama profile fetch calls trusted Godot migration and CAS-persists it once for
inactive v1 profiles. Active rooms defer until normal return/recovery. New and cleaned
accounts cannot receive the full catalog again. The manifest generator rejects the
retired `--beta-test-kit` flag.

## Operator migration

Run `tools/backend/retire_catalog.py` on the k3s host, namespace `zorx-staging` only.
Default is dry-run. `--apply` requires zero rooms/peers and enabled maintenance.
Private Godot rules produce every candidate. The tool verifies equipped gear,
earned items, balances, appearance and RNG against the source before CAS-updating
storage and incrementing profile revision. Concurrent changes cause a conflict,
never an overwrite. Active-room records are skipped.

A full private profile-row backup is written on the host before application, under
`/home/wiyazard/deployment/game-test/zorx-staging/.backups/` with directory0700 and
file0600. No profile contents or worker tokens are printed or copied to the Mac.
Rollback must respect later revisions: do not restore old rows over new player
progress. Retain the backup for scoped manual recovery.

Only API and profile-worker images need updating. Fixed `deployment.yaml` and
`headless.yaml` also disable legacy kit flags in the runtime Secret/profile env.
Web/Room Worker, scene routing and original source secrets remain unchanged.
After rollout, dry-run, apply, and dry-run again; reopen admissions and refresh game.

Validation: trusted Godot preservation/idempotence/overflow/legacy-flag tests;
TypeScript CAS/active-room deferral tests; actual disposable Nakama/Postgres v1
fixture fetch→v2 storage transition; Python pre-write preservation checks.

## Staging result

API/profile-worker `kit-retire-56731fb` ready; grant flags disabled. Backed-up CAS
migration processed10 inactive profiles and removed1,542 spare grant items, preserving
8 equipped grant pieces and2 other stash items. No conflicts or active-room deferrals.
Post-write preservation checks passed for all10 profiles; repeated dry-run found0
eligible profiles. Fresh private profile creation returns0 spare items. Maintenance
reopened. Refresh existing clients to replace cached inventory/revision.
