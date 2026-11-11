# Adventurer companions — implementation record

2026-10-30. Requested by Boss: named adventurers using the main player model/assets,
no BOT badge, wandering camp, occupying one party slot, following/fighting/casting/
dodging/reviving through the ordinary player rules. Conversation uses a real LLM;
Boss selected a server-side OpenAI-compatible adapter. No provider or secret is set yet.

## Authoritative phase split — Boss 2026-10-30

**Phase 1 is the playable companion in the real game, without LLM/chat.**
Acceptance requires the main player model visibly wandering camp, an invite action
that occupies an ordinary party slot, real co-op stage entry, follow/combat/skills/
dodge/revive under unchanged player rules, stage transitions and safe human-only
account persistence. A brain-only test or a model preview is not Phase 1 complete.

**Phase 2 is typed conversation only using the LLM.** The existing isolated dialogue
adapter is parked; do not spend Phase 1 work on provider setup, conversation UI,
history or LLM deployment. No model/key decision is a blocker for Phase 1. LLM
never controls movement, combat, party admission or persistence in either phase.

## Status

**Phase 1 integrated locally; release in progress.** Arun uses the main renderer
in Gathering Plaza (route X±3, Z−17..−23), proximity invite opens a four-slot camp
party with slot4 reserved. Nakama alone authors the descriptor; humans get remaining
slots. Room authors a fresh starter build, runs ordinary SimInput, excludes companion
scene ACK/socket ownership and account saves. Netfox remote entity replication is
used for companion parties even on the normal URL. No LLM adapter is in the patch.

Camp wander is currently client presentation on the same authored plaza route,
not globally unique shared Nakama presence; different clients can see different
wander phase. Party combat is server authoritative. No claim of a single globally
persistent autonomous resident across plaza shards.

- `logic/companions/brain.gd`: input-only authority brain. Follow leash, nearest
  hostile selection, dodge requests, ready skill selection, ordinary light attacks,
  and idle proximity for existing co-op reviving. Does not mutate fighter state,
  health, stamina, inventory, cooldowns or positions. No LLM calls in simulation.
- `server/companions/dialogue.gd`: asynchronous, text-only Chat Completions
  compatible transport. Four concurrent requests, 12-second timeout, 32KB response
  limit, 500-character input/output, per-user request spacing, no redirects, no
  tools/game commands, no credentials or profiles in prompts/logs. Currently
  single-turn: bounded conversation history and caller authentication still need
  integration. The trusted caller supplies the character and authenticated user.
- `tests/companion_foundation.gd`: actual two-player Room state used to check
  follow/rescue/dodge/cast decisions and no authority mutation, plus protocol
  request/parser/configuration checks. This is not Web/co-op acceptance.

## Deployment configuration (server only)

- `ZORX_COMPANION_LLM_URL`: full HTTPS Chat Completions endpoint, including path.
- `ZORX_COMPANION_LLM_MODEL`: provider model identifier.
- `ZORX_COMPANION_LLM_KEY`: optional bearer token, Kubernetes Secret only.

No default external destination; unconfigured requests return `not_configured`.
Do not put these secrets in exported Web packs or Nakama public configuration.
LLM outages must affect conversation only. Player chat sent to the model must be
limited to the conversation, never stash, auth tokens, email or account metadata.

## Required integration order

1. Server-authored roster/appearance/personality + bounded navigation through
   actual camp/stage collision. The current brain has direct steering only;
   obstacle routing, cliffs, ranged line-of-sight and skill-specific target
   selection remain OPEN. Do not enable it in real rooms before these checks.
2. Backend trusted companion reservation: capacity shared with humans; leader-only
   invite/remove; durable roster identity separate from account UUID; no fabricated
   login, ticket, socket or public profile writes. Define per-party companion
   instances so two parties cannot drive the same mutable actor.
3. Transport/Room lifecycle: add companion slots to authoritative simulation and
   public roster, but do not require scene-ready/socket presence for those slots.
   Netfox replicates them as remote entities; no owner prediction socket required.
   Preserve invitation/removal across stage transitions/reconnect; release slot on
   party teardown. Human reconnect must never inherit a companion slot.
4. Persistence firewall: current `Room.finalize`, `owned_profiles`, lobby rebuild
   and backend finish/start/member-leave expect human accounts. Separate trusted
   companion runs from human persistence; never submit companion profiles to
   account storage. Test human rewards/save fencing with mixed-party endings,
   death, reconnect and empty-room cleanup. Do not use cloned player inventory as
   a shortcut to production companion equipment.
5. Camp presentation: use existing reference `CharacterModel`/appearance/loadout
   projection and normal animation selection, server-authored names. Current
   Nakama plaza is only the northern plaza, not the entire camp; a plaza-only
   actor does not satisfy camp wandering. Add an actual camp interaction for
   conversation/invite/dismiss; no BOT badge requested. Character dialogue must
   not falsely claim it is a human if directly asked.
6. Dialogue gateway: authenticated membership, per-account/provider cost limits,
   bounded per-conversation history/TTL, stale reply rejection after party/session
   changes. Run network I/O outside simulation; no synchronous HTTP from plaza
   match tick. Configure endpoint/model/secret only after provider selection.
7. Real Web acceptance: invite in camp, occupied capacity/full-party rejection,
   stage entry, follow around obstacles, real hit/skill/dodge/stamina/cooldown,
   revive, portal/stage switch, human co-op, reconnect and reward persistence.
   Add LLM mock timeout/malformed/error tests and an actual configured-provider
   conversation. No synthetic-only acceptance or claim of complete integration.

## Validation so far

Foundation contract passed native Godot 4.7.2. Initial fixture issues (reserved
`Input` class name and multiplayer farm-map restriction) were fixed before the
passing run. Full suite and actual HTTP/provider/Web gameplay have not passed
for this feature. No deployment was made.

## 2026-10-30 Phase 1 integration evidence

- Native main-source and exact shipped-pack camp review PASS PC1280×720/mobile844×390:
  `build/companion-camp-*.png`, `/tmp/zorx-companion-shipped-native.log`.
- `tests/companion_room_contract.gd` PASS actual shared damage/stamina and revive,
  occupied party readiness, human-only finish profiles, rebuild and empty-human TTL.
- Navigation contract PASS wall detour with body clearance and unsupported-floor guard.
- Backend TypeScript compilation + `test_companion_room.cjs` PASS reserved slot,
  full-room rejection, no account creation, human-only persisted profiles;
  diagnostic/ordinary expiry regression PASS.
- Actual native separate Netfox server/client companion gate PASS: lobby ready/depart,
  named remote companion moves, client input accepted without rejects. Not Web acceptance.
- Full run_all attempted45s: FAIL+timeout on existing profile/login/checkpoint fixtures;
  general npm test fails older initializer mock missing registerMatch. No full-green claim.
- Web candidate `7dea6c36f2d9` overlays live `1a8ceb4960a4`, all unrelated core/engine/content
  bytes retained; no new model/textures; gzip core−3353bytes. Contexts/records:
  `/private/tmp/zorx-companion-release2`. Live image backup `/tmp/zorx-companion-live.json`.
- Actual browser walkthrough pending: IAB explicitly disabled in Work settings;
  native Safari selection timed out. Do not label native evidence as real Web acceptance.

## Release companion-20261030-1

Web build `7dea6c36f2d9`; Nakama, Rooms, Web rollouts succeeded. Image-only remote manifest updates retain resources and Secrets. Before-companion backups on host plus `/tmp/zorx-companion-live.json` retain rollback. Profiles image unchanged.

- web: `wiyazard:30500/zorx-web:companion-20261030-1@sha256:8566e63083e6edb28853b8846b03d17b2f9e35e7356777a453968688157d7182`
- room: `wiyazard:30500/zorx-room-worker:companion-20261030-1@sha256:713cf0647b03ad90196c3feb21074c26c9f5cbc238b88514d1551f830723cf57`
- nakama: `wiyazard:30500/zorx-nakama:companion-20261030-1@sha256:7d198eef4decde733acf926786ec3e14b0546d423fd6221ba1e7fc31664a4f60`

## Random adventurer per round (2026-10-30)

Boss requested randomized name/character/items/skills. A NEW party room uses its
existing server-authored seed + reserved slot to generate a companion. Neither a
client item list nor client stats are accepted. Reconnect, lobby rebuild and stage
transitions retain the existing run/profile; fresh seeded recreation is repeatable.
The camp recruitment resident is still Arun; the randomized party identity is
assigned when creating the party, so the recruiter and recruited adventurer can
look/name differently. Do not claim camp-to-party identical randomized identity.

Pool:12Thai names +2digits, main-rig cosmetic catalog choices,5weapon families
(blade/dagger/spear/hammer/bow),6real catalog items including5armor slots, ordinary
tiers0–2 and normal substat rolls. No refine bonuses, currency or item gifts to
humans.4distinct skills sampled from the20skill catalog; tree start matches the
weapon. No gems in this revision.32seed contract verifies deterministic profiles,
all5weapon families, legality and visual/build diversity. Actual randomized Web
combat/visual parity remains an acceptance item; no full suite green claim.

- Companion random-round RELEASE verified: headless rollout SUCCESS, readyReplicas1, startup ready; rooms image wiyazard:30500/zorx-room-worker:companion-random-20261030-1@sha256:10ebc7b64b4284d047c3440c7e16841211ce2dfe45f8be6747720ea70ba63bd0. Remote headless.yaml backed up/image-only synced; web/Nakama/profiles unchanged. New party rooms reroll, existing rounds retain identity.

## Identity correction (Boss directive, supersedes recruiter exception above)

The plaza resident and recruited party member MUST be the same character. Private
server offer under ROOM_COLLECTION binds authored ID +13hex seed to the account.
Authenticated discovery reveals seed; client reconstructs the same main-model
appearance/equipment/name through the shared seeded generator. Room creation
atomically claims the offer seed; the worker uses descriptor seed without reroll.
The offer is stable across plaza refresh; only closed/expired previous round allows
next random offer. No client seed/gear/stats accepted. Legacy existing rooms without
seed retain their previous fallback until finished. Backend contract verifies
preview==room seed, repeated discover stable, next round changes seed.

## Shared human/companion interaction — Boss approved 2026-10-30

No companion-only proximity button. Click/tap a character within4m in Gathering
Plaza, then choose the same Invite action. Humans receive a normal party invite
notification, surfaced in-camp as Accept/Decline popup (polled every3s while no
other modal is open). Acceptance uses the existing room join/notification ACK.
Nonfriend invitation needs authoritative same-plaza near-distance proof through
Nakama matchSignal, not merely client coordinates. Friend-list invites remain.

Companion invitations go through the same invite operation/UI with server-owned
recipient ID. The offer seed is claimed atomically, pending slot reserved, but no
companion member/body is created until >=10s. Backend rechecks room open/notstarted,
capacity and30s expiry. Worker joins only with connected humans, rebuilds lobby,
installs the same seeded profile and resynchronizes epoch. Leaving/cancelled rooms
cannot create a companion. Start is blocked while its invite is pending. All camp
party tickets advertise Netfox to keep human/companion joins on one transport.

Evidence: backend contract covers10s/one-time accept/startgate/cancel/proximity;
actual separate native client-worker delayed invite gate PASS; source +exact packed
PC/mobile menu tests select both human and companion, and exercise recipient
Accept/Decline routing. `build/shared-character-{invite,confirm}.png`. Existing
plaza_chat focus teardown warning remains; fullsuite notgreen, actual two-browser
online acceptance is stillOPEN. This is not claimed as a full human-account bot
implementation: no bot account, permanent stash or economic rewards are persisted.

## shared-invite-20261030-1 candidate release

Build3b78467c3d65; all unrelated base core/content/engine bytes retained. Exact packaged menu/popup test PASS(known plaza-chat teardown warning persists). Delayed Netfox server/client10s join gate PASS. Backend cancellation/proximity/identity/capacity tests PASS. Fullsuite latest45s attempt FAIL+timeout on profile/login/checkpoint fixtures. Actual two-deviceWeb acceptanceOPEN.

- room: `wiyazard:30500/zorx-room-worker:shared-invite-20261030-1@sha256:0eed7438b44ae9d209fefa8733eb8f727d2c3fd6ff538b08f3c6501b738d36a3`
- nakama: `wiyazard:30500/zorx-nakama:shared-invite-20261030-1@sha256:c71ce70e8dd9935da00eb6a4b4fa63a9b7f6d2886c8c9a4d855c07b29dc7fd76`
- web: `wiyazard:30500/zorx-web:shared-invite-20261030-1@sha256:b09e55e5dcb577c994bcc5cf0bb4f8375610d526def4bf894f407b47fea946d9`

- shared-invite-20261030-1 rollout SUCCESS on rooms/nakama/web; remote headless.yaml/deployment.yaml/game.yaml image-only synced with backups. Candidateweb3b78467c3d65. Browser attempt again blocked explicitly by Work setting “Local browser use is disabled”; no two-browser live acceptance claim. Exactpack native and delayed10s nativeNetfox checks passed; public verification in progress.

- Shared invitation public verification COMPLETE: build3b78467c3d65 and downloaded core exact-byte match tested pack; game-test/headless/nakama each readyReplicas1, startup ready. Live records /private/tmp/zorx-shared-invite-release/live-deployments.json.

## Party follow fix — 2026-10-30

Previous brain returned to leader immediately beyond7m before selecting a nearby enemy. It now engages targets within12m detection and14m party leash first; regroups only when beyond14m. In idle travel, follow begins beyond4m and stops at2.75m, preventing oscillation/clinging. Beginning a new follow leg resets cached navigation to avoid waypoints from before combat/idle. Revive priority, legal skill/stamina/dodge and long-distance regroup retained. Regression tests: tests/companion_combat_priority.gd, existing navigation/room/foundation contracts. Worker-only rollout; no Web UI changes.

- Companion-follow RELEASE verified: rooms wiyazard:30500/zorx-room-worker:companion-follow-20261030-1@sha256:95dabe5daaa5fc8fc802a281b24e66d28da6ef8649c52720d1262609f3f115a0; rollout SUCCESS,headless2/2 Running0restarts,readyReplicas1; live brain SHA256 exactly matches tested source caa4f0dc3ce5d7bf3e301f0d4aaf599f2707ef71a00bf09cbc669176d6d5046b. Exact Linux current-base+patch contract PASS. Remote headless.yaml image-only synced/backup, rollback and verification under /private/tmp/zorx-companion-follow-release. Only brain source layer1904B; Web/Nakama/profiles retained. Actual Web party gameplay still user acceptance OPEN; no browser check claimed.

- 2026-10-31 Plaza companion idle(Boss requested): stand45–90s between short <=2s walking bursts at35% walking input; never run; pause near player or invitation menu; offer-seeded local rest schedule. Only client/companions/camp_adventurer.gd changes in scoped core over live2103e952a30f; candidate78ac5bc44c8e,core+932B gzip,all other core/content bytes identical. Source and exactcandidate PCK idle contracts PASS. Fullsuite timeout gate running; prior fixture failures remain. No party combat AI changes. Release pending.

- camp-idle-20261031-1 RELEASE verified: Webbuild78ac5bc44c8e image sha256:360c0f05d1bff9c140a253df8a73823d8f094829d805396d346d0f15a970ece3; game-test rolloutSUCCESS readyReplicas1, public packs metadata and downloaded core byteexact. Source+exact-PCK camp-idle contract PASS. Fullsuite45s FAIL+timeout(existing cleanup/profile/cache/reconcile fixtures); no browser-play acceptance claim. Room worker companion-follow release remains unchanged. Verification/rollback /private/tmp/zorx-camp-idle-release.
