# M3-4 authoritative camp profile and commands

Nakama authenticates the caller, reads private storage and forwards trusted state to the existing private Godot worker. `runner.gd` loads production item/camp/cosmetic JSON and runs the original `Profile.new_player`, `Profile.from_dict` and `Commands.apply`. TypeScript contains transport, storage concurrency and retry bookkeeping; it does not reproduce game rules.

## Protocol

Authenticated RPC `zorx_profile_get_v1`:

```json
{"v":1}
```

The first call creates starter equipment/materials/gold from server data. It never imports a local save or applies TestKit. A concurrent first call reads the single winning create-only row.

Authenticated RPC `zorx_profile_command_v1`:

```json
{"v":1,"revision":1,"request_id":"a_unique_request_0001","command":{"type":"unequip","slot":"weapon","destination":"stash"}}
```

Request IDs are16–64 ASCII letters/digits/underscore/hyphen. Revision is a positive integral number below2147483647. Public payloads are limited to4096 characters; no user ID, profile, seed, RNG, location, rules, journey or rewards are accepted. Item references remain stable instance IDs.

Success returns `{v:1,ok:true,revision,profile,replayed,applied_revision}`. Profile is M1-1 JSON; gold stays a decimal string. No Nakama storage versions, RNG or receipt history are sent. Failure returns `{v:1,ok:false,error}`. Typical transport/storage errors: `invalid_payload`, `profile_required`, `revision_conflict`, `request_id_reused`, `unavailable`; game rule failures come from Godot unchanged.

`client/online/profile_client.gd` offers `fetch`, `prepare`, `submit`. Fetch first; prepare once, retain the complete envelope, and resend it unchanged after a timeout. Do not automatically retry a conflict at a newer revision: fetch/review the new state first. The adapter does not upload local inventory or silently fall back to local commands.

## Authority and persistence

- Private `zorx_profile_v1/camp`, owned by authenticated user. Read/write permissions0; Nakama API hooks deny client creation/write/delete of all objects in the collection.
- Persisted value: `{v:1,revision,profile,rng_state,receipts}`. RNG uses decimal text to retain Godot64-bit precision; initialization seed comes from server UUID randomness.
- Every successful command commits the entire next profile/RNG/receipt through version CAS in one DB transaction. Failed or losing commands do not mutate stored state or consume persisted RNG. Concurrent commands have one winner; callers explicitly fetch after conflict.
- Last32 successful request receipts are retained inside the same object. Exact retries return the latest snapshot plus original applied revision. Different content with the same remembered ID is rejected. Older evicted retries still fail their stale expected revision, so they cannot apply twice.
- Character name/created fields are projected from M3-3's reservation on every response, including after a rename. Commands cannot set names; use the name RPC. A name claim alone does not upload appearance.
- Location is server-owned camp only for this milestone. Supported commands: equip/unequip/discard/discard_material, repair/repair_all, upgrade_camp/upgrade_facility, appearance/randomize_appearance. Enhance/tier stay `not_configured` per Boss until pricing exists. Journey/reward commands are unavailable; M4 must add room ownership/active-run locks and trusted result settlement before enabling them.
- Existing snapshots can still be read while worker is down. New creation/commands fail unavailable; no fabricated success.

## Verification on the dev machine

```sh
npm run build --prefix server/names/runtime
npm test --prefix server/names/runtime
python3 server/names/smoke_worker.py
python3 server/names/build_images.py
python3 server/names/smoke_stack.py
python3 pipeline/build_web.py --max-file-mb 0
```

Image builds are **local test builds only**. No push is performed by these scripts. The stack uses disposable containers and covers actual Godot SDK, starter creation, equipment changes, payload tampering, direct-storage bypass, idempotence, CAS races, account isolation, worker outage and server/database restarts. It removes only its own containers/network.

## Manual release by Boss

The worker now needs `server/profile/` and production item/camp/cosmetic JSON; the image builder packages them automatically. Build both updated images together. Local tags are `zorx-nakama:m3-4-local` and `zorx-name-validator:m3-4-local`. Boss tags/pushes them to the registry and obtains their RepoDigests.

Generate an overlay with both new immutable image refs using the existing builder:

```sh
python3 server/names/deploy.py \
  --worker-image REGISTRY/WORKER@sha256:WORKER_DIGEST \
  --nakama-image REGISTRY/NAKAMA@sha256:NAKAMA_DIGEST \
  --reuse-secret build/k3s-remote/names-deployment.yaml \
  --output build/k3s-remote/profile-deployment.yaml
```

Reuse the private M3-3 bundle to retain the validator token. If no names bundle has ever been generated, omit `--reuse-secret`; it creates a new private first-install Secret. Copy the generated bundle to the k3s node and review/apply there as described in `server/names/README.md`. No original DB/signing Secret is rotated, no custom SQL migration is needed. The checked-in `server/names/deployment.yaml` and RELEASE.md are the historical M3-3 image release, **not updated M3-4 images**; do not use them to deploy this feature.

After manual apply, run from the dev machine:

```sh
./tools/backend/test_backend.sh both --names --profiles --secrets build/k3s-remote/deployment.yaml
```

This uses the existing dedicated smoke identity; no real player's inventory is modified.

## Remaining integration

The game still uses LocalSession. This milestone provides the server runner, storage/RPC and tested SDK adapter; it does not switch creator/camp/gameplay UI to cloud state. RemoteSession, online journey settlement and linked cross-device login are later work. Device-only accounts on two devices are different accounts unless explicitly linked. No physical iPhone or live k3s M3-4 claim is made. M3-5 adds shared per-account rate limits and redacted rejection monitoring; see `server/security/README.md`. Both milestones need manual image release and live staging verification. Off-machine backup/restore acceptance remains pending independently.

## Always-online account and staging kit (2026-10-18)

The camp now uses `client/session/account_session.gd`; solo and parties consume the same server account profile. The old local TestKit is for isolated tools only. Full catalog grants are retired (2026-10-18). New accounts receive only starter equipped gear. Version1 profiles are cleaned by the trusted profile runner and CAS-persisted on inactive profile fetch: remove exact `beta-v1-<catalog-id>` spare items from stash, retain all equipped gear and earned ownership, set `beta_kit_version=2`. Capacity shrinks to normal except slots needed to preserve earned overflow. A retained beta item may be unequipped later without deletion. Legacy environment flags cannot regrant items, and the manifest generator rejects `--beta-test-kit`. Active rooms defer lazy cleanup until their normal return/recovery; no client snapshots are accepted as a migration source.
