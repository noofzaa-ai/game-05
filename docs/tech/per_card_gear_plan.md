# Per-card gear plan (Boss decision 2026-11-11)

Status: PLAN, not implemented. Owner: lead-programmer. Items marked **[Boss]** need a Boss/director decision before the code lands (they are expensive to change later).

Goal: each class card (`logic/card_deck.gd`, `Profile.card_deck`) owns its own 15-slot loadout (11 slot ids, earring/bracelet/ring x2, `data/items/rules.json`), the refine/upgrade state of those items, its own outfit and its own skill build. In a fight the 3 squad cards fight with their own gear, replacing the random guest profiles.

## 0. Where things are today (verified)

| Touch point | Today |
|---|---|
| `logic/profile.gd:23` | one `var loadout: Loadout` per player |
| `logic/profile.gd:58-64` | `new_player` equips starter blade/shirt/shoes, `skill_build = initial("blade")` |
| `logic/profile.gd:68-101` | `ensure_starter_weapons/armor` scan `loadout` for owned ids |
| `logic/profile.gd:130-148` | `equip_from_stash` / `unequip_to_stash` act on `loadout` |
| `logic/profile.gd:157,175` | `to_dict` writes `"loadout"`; `from_dict` requires it |
| `logic/card_deck.gd:9-11` | card = plain dict of looks + reserved empty `skills` (validate rejects non-empty, :144) |
| `logic/commands.gd:82` | duplicate-id scan covers stash, vault, `p.loadout`, run bag |
| `logic/commands.gd:106-140` | equip/unequip use `p.equip_from_stash` / `trip.equip_from_bag`; weapon gated by `skill_build.can_equip` (:124) and unequip of weapon blocked when skills enabled (:131) |
| `logic/commands.gd:193-196` | refine/upgrade/repair find the item by id; `repair_all` uses `profile.loadout.items()` (`logic/repair.gd:48`) |
| `logic/run.gd:37-47, 86-105` | `Run.loadout()`/`stats()`/bag equip all read `profile.loadout` |
| `logic/game_sim.gd:107-121` | `attach_run(id, run, ...)`: style from `run.loadout()`, skills from `run.profile.skill_build` |
| `logic/game_sim.gd:129-137` | `set_class_style` overrides style and replaces the build with `skill_build.initial(style)` |
| `logic/game_sim.gd:366-386` | coop: every living player gets its own drop per kill (:374-377); death calls `run.death()` + `Wear.death(run.loadout())` |
| `logic/game_sim.gd:481-507` | checkpoint saves `runs[id].to_dict()` (includes a full profile each); restore rebuilds one profile per run |
| `client/game_state.gd:141-146` | auto-battle guests = `Profile.new_player(...)` per squad slot 2..3 |
| `client/session/local_session.gd:77-85, 139-142` | `start_journey` builds a `PartyJourney` from guest profiles; class style applied per fighter id from `squad_classes` |
| `logic/coop_journey.gd:18` | `start_party` refuses two runs sharing one profile |
| `server/profile/runner.gd:6, 31, 76` | `ALLOWED` list; saved profile must have key `"loadout"`; wave-chest id repair walks `profile.loadout` |
| `server/rooms/room.gd:105-109` | online rooms: one profile per player id, requires `"loadout"` |
| `client/session/account_session.gd:21` | field list copied from server profile (needs the new field) |
| `logic/skill_build.gd:23, 142` | `ready_for_run` / `apply` read `profile.loadout` weapon |
| `logic/shop.gd:47,132`, `logic/test_kit.gd:17` | read `profile.loadout` |

## 1. Data model

**Recommended:** a new Profile field, not inside `card_deck`.

```
Profile.card_gear: Dictionary  # class_id -> CardGear
CardGear = {loadout: Loadout, skill_build: Dictionary}
saved as "card_gear": {class_id: {"loadout": Loadout.to_dict(), "skill_build": {...}}}
```

Why separate from `card_deck`: `card_deck` is plain JSON validated without `ItemRules` (`card_deck.gd:110`, `repaired` at :205); loadouts hold `Item` objects and need the rules to decode. Keeping them apart keeps `CardDeck` pure and lets `card_look`/`card_squad` stay unchanged. The class id is the shared key.

Per card: loadout (items carry their own `refine_level`/tier/durability, so refine/upgrade progress follows the item automatically), skill build, looks (already per card: hair/outfit/eyes/skin/makeup).

Shared (account): stash, vault, gold, materials, diamonds, `mall_owned` (fashion ownership), camp/facility levels (camp skill bonus `camp.gd:30` applies to all cards), farm, name. Relics: recommend account-wide owned list; equipped relics account-wide for v1 (see Q4).

Fashion: ownership stays in `mall_owned`; *wearing* moves per card later by adding `fashion`/`fashion_back` to `CardDeck.PARTS` with an ownership check (hats stay deferred per CLAUDE.md). `Profile.appearance` fashion fields become legacy.

**Migration (from_dict when `card_gear` missing):**
- Existing `Profile.loadout` -> card `sword_shield` (its class weapon is `blade`, `data/classes/sword_shield.json`; all catalog weapons are `blade`). Existing `skill_build` goes with it.
- Other cards: one-time grant `starter_card_kit_version = 1`, fresh starter set per card (`STARTER_LOOKS` shirt/shoes + weapon per Q3), ids `starter-card-v1-<class>-<slot>` (must stay unique across all containers). `skill_build = SkillBuild.initial(class weapon)`.
- New players: `new_player` builds all cards directly.
- Transition: keep a computed `loadout` property (getter -> `card_gear[squad[0]].loadout`) and keep writing `"loadout"` in `to_dict` until `runner.gd:31` and `room.gd:105` stop requiring it. Remove both in the last step.

## 2. Commands

- Add optional `"card": TYPE_STRING` to the schemas of `equip`, `unequip`, `skill_build`, `repair_all` (`commands.gd:17-18, 21, 29`). Validate: card is a known class in `p.card_deck.cards`, else `invalid_card`.
- `refine`, `upgrade`, `repair`, `enhance`, `upgrade_tier`, `shop_sell`, `storage_item`: no card needed - the item id already locates it. Extend the ownership scan (`commands.gd:82`) to every card's loadout; worn items stay unsellable/unstorable (`shop.gd:132` must check all cards).
- Moving gear between cards: v1 goes through the stash (unequip on card A, equip on card B). No new command type.
- Backwards compat: missing `card` = `p.card_deck.squad[0]` for one release, then required.
- Skill gate: `can_equip`/`follow_unspent_weapon`/`ready_for_run` take the card's build and the card's class style, not the weapon type (the class decides style today, `game_sim.gd:129`).
- `runner.gd:6` ALLOWED: no new types needed. `card_look`/`card_squad` already there. Only add a type if a direct card-to-card transfer is wanted later.
- Client field list `account_session.gd:21`: add `card_gear`.

## 3. Sim / journey

**Recommended:** one shared `Run` (one bag, one profile) plus a small per-fighter wrapper `logic/squad_member.gd`:

```
SquadMember: run (shared Run), card_id, died
  loadout() -> run.profile.card_gear[card_id].loadout
  stats(rules) -> Stats.totals(loadout().items()) + Camp.skill_bonus
  skill_build() -> card_gear[card_id].skill_build
  loot_into_bag(drop) -> run.loot_into_bag(drop)
  death() -> died = true; run.death() only when every member is down
  to_dict() -> {"card": card_id, "died": died}
```

- `local_session.start_journey` builds the squad from `profile.card_deck.squad` (no guests); `game_state.gd:141-146` guest loop is deleted for auto-battle (keep `--coop-debug` path).
- `GameSim.attach_run(id, member, ...)`: everything the sim uses from `Run` (`loadout()`, `stats()`, `loot_into_bag`, `death`, `died`, `profile`) is provided by the member. `set_class_style` keeps forcing style; the build comes from the card, not `initial(style)`.
- Journey: a single-player `Journey` with `squad_members` (not `PartyJourney`, which forbids a shared profile at `coop_journey.gd:18` and triple-pays drops at `game_sim.gd:374`). Today the auto-battle squad gets one drop per living fighter per kill; with a shared bag it becomes one drop per kill -> **economy change, needs a balance re-run** (`tools/balance/class_sim.gd`).
- Wear: `Wear.hit_landed/damage_taken/death` already take a loadout - pass the member's loadout.
- Checkpoint (`game_sim.gd:481`): save the shared run once plus `members: {fighter_id: {card, died}}`; restore rebuilds one Run and wraps it. Journey `to_dict` gains `"squad": [...]`. Bump a field version, reject old checkpoints cleanly.
- Online rooms (`room.gd`): out of scope for the first pass; local/solo auto-battle first, then the room builds members from the one player profile.

## 4. Class vs weapon slot

Today only `blade` items exist in the catalog; `greatsword/longbow/magic` are `class_only` styles, never items (`combat_data_loader.gd:622`). Style is already forced by class, so the weapon item is a stat stick.

**Recommend:** data-driven restriction. Each class file gets `"weapon_families": [...]`; equip rejects other families with `wrong_weapon_family`. Until the catalog has greatsword/longbow/magic items, those classes list `["blade"]` (a placeholder stat weapon, style unchanged), so no card is left weaponless. When real class weapons are added, change the data only.

## 5. Implementation steps (PR-sized)

1. **Profile model + migration.** `card_gear`, `loadout` getter, `to_dict/from_dict`, starter grant, id-uniqueness across cards. Tests: new `tests/test_card_gear.gd` (migration puts old gear on sword_shield; others get starters; round-trip; unique ids), adjust `test_serialization.gd`, `test_profile_diff.gd`, `real_profile_codec_probe.gd`.
2. **Commands.** `card` param, ownership scan over all cards, `repair_all` per card, shop/storage worn-check, skill gate per card. Tests: `test_commands.gd` (equip to card B leaves card A, wrong card, missing card default, sell worn on any card refused), `test_online_profiles.gd`.
3. **Server/runner.** `_repair_wave_chest_ids` over all cards, required keys, account_session field. Tests: runner round-trip in `test_online_profiles.gd`.
4. **SquadMember + sim.** Wrapper, `attach_run` typing, shared-bag loot, per-member death, per-card build. Tests: `test_sim_restore.gd` (checkpoint with 3 members restores one profile), `test_journey.gd` (one drop per kill, all-down ends run), new test that fighter stats differ when card loadouts differ.
5. **Session wiring.** `local_session.start_journey` from squad, delete auto-battle guests. Re-run `tools/balance/class_sim.gd` and report win-rate/loot change.
6. **Weapon families** in class data + equip check. Tests in `test_card_gear.gd`.
7. **Cleanup.** Remove `loadout` getter and `"loadout"` key, update `room.gd` (online squad).
8. Client menus (blacksmith/shop/storage/tailor side panels) pass the selected card - ui-programmer, after step 2.

## Risks

- Save migration on live accounts: a bad `from_dict` returns null and the runner rejects the account (`runner.gd:34`). Mitigate: migration test on real saved profiles (`real_profile_codec_probe.gd`), keep `"loadout"` written until step 7.
- Duplicate item ids across cards break every command (`commands.gd:87`).
- Loot economy: shared bag cuts squad drops to 1/3 of today's auto-battle rate.
- Checkpoint format change breaks in-flight local journeys (acceptable: reject and restart).
- `skill_build.enabled()` is true; weapon-type gating in commands must move to class-based before equip works for longbow/magic cards.
- Sim duck-typing (`var run: Run = runs[id]` casts in `game_sim.gd`) must be loosened or Run subclassed.

## Expensive to change later - confirm with Boss/director

1. Save schema: `card_gear` keyed by class id, separate from `card_deck`.
2. Shared squad Run/bag with SquadMember wrapper (vs three Runs with separate bags).
3. Loot rule: one drop per kill into the shared bag.
4. Which state is per card vs account (relics, fashion wearing, skill build).
5. Weapon slot restricted by class `weapon_families`.

## Open questions for the Boss (default in brackets)

1. Who gets the existing gear on migration? [Sword & Shield card; the other 3 cards get a starter set.]
2. Loot after a fight: one shared bag for the squad, one drop per kill? [Yes, shared bag; re-tune drop rates after.]
3. Weapon slot by class? [Restricted per class in data; greatsword/longbow/magic use blade weapons as placeholder stat items until their own weapon items exist.]
4. Relics: per card or per account? [Account-wide owned and equipped for now.]
5. Fashion: wear per card while buying stays account-wide? [Yes; hats stay deferred.]
