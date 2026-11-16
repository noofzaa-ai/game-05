extends RefCounted
## Equipment tier-up (Boss 2026-11-16; design/gdd/race-gear-sets.md "Tier-up path"; logic/tier_up.gd; data/items/tier_up.json):
## a level-1 starter piece becomes the level-15 piece of the card's race x class, keeping tier/durability ratio/refine/
## sockets/substats; card level must reach the target's req_level; 2500 gold flat; the old substat Upgrade is gone.
const Profile := preload("res://logic/profile.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Commands := preload("res://logic/commands.gd")
const CardDeck := preload("res://logic/card_deck.gd")
const TierUp := preload("res://logic/tier_up.gd")
const Runner := preload("res://server/profile/runner.gd")
const CLASSES := ["sword_shield", "greatsword", "longbow", "magic"]
const SLOTS := ["weapon", "shirt", "pants", "armband", "shoes"]
const RACES := ["human", "viking", "elf", "runeborn"]
const COST := 2500


func run(ctx) -> void:
	var rules = preload("res://logic/item_rules_loader.gd").load_default()
	var camp = preload("res://logic/camp_data_loader.gd").load_default(rules.tiers.size())
	var cosmetics = preload("res://logic/cosmetic_options.gd").load_default()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1117
	_data(ctx, rules)
	_matrix(ctx, rules, camp, cosmetics, rng)
	_gate_and_gold(ctx, rules, camp, cosmetics, rng)
	_raceless(ctx, rules, camp, cosmetics, rng)
	_worn_and_race_change(ctx, rules, camp, cosmetics, rng)
	_ineligible(ctx, rules, camp, cosmetics, rng)
	_old_upgrade_gone(ctx, rules, camp, cosmetics, rng)
	_runner(ctx, rules, camp, rng)


func _state(p, rules, camp, cosmetics) -> Dictionary:
	return {"profile": p, "rules": rules, "camp": camp, "location": "camp", "cosmetics": cosmetics}


func _prep(rules, camp, rng, card_level: int = 15, gold: int = 100000):
	var p = Profile.new_player(rules, camp, rng)
	for card in CLASSES:
		p.card_deck["cards"][card]["progress"] = {"level": card_level, "xp": 0}
		CardDeck.set_race(p.card_deck, card, CardDeck.starter_race(card))  # a new card has no race until the player picks one
	p.stash.gold = gold
	return p


## A level-1 piece in the stash: a starter instance (id starter-*), `tier`, odd durability / refine / level / relic.
func _starter_piece(rules, id: String, slot: String, tier: int, class_id: String, race: String):
	var catalog_id: String = rules.catalog.race_piece(race, class_id, slot)
	var item = ItemSystem.create_item(rules, id, slot, tier, RandomNumberGenerator.new(), "", catalog_id)
	item.durability = item.max_durability * 0.37
	item.refine_level = 3
	item.level = 2
	item.upgrade_count = 2
	item.substats[0]["upgrade_bonus"] = 1.5
	return item


func _data(ctx, rules) -> void:
	var cfg := TierUp.config()
	ctx.check("tier-up data: enabled, flat 2500 gold, a path for the 5 slots", bool(cfg.get("enabled", false)) and int(cfg.get("cost_gold", 0)) == COST and (cfg.get("paths", {}) as Dictionary).size() == 5)
	var ok := true
	for slot in SLOTS:
		ok = ok and (cfg["paths"] as Dictionary).has(slot) and rules.catalog.req_level(str(cfg["paths"][slot]).format({"race": "human", "class": "magic"})) == 15
	ctx.check("tier-up data: every path lands on a level-15 catalog item", ok)
	ctx.check("tier-up data: shield, back and boss accessories have no path", not (cfg["paths"] as Dictionary).has("offhand") and not (cfg["paths"] as Dictionary).has("back") and not (cfg["paths"] as Dictionary).has("ring"))


func _matrix(ctx, rules, camp, cosmetics, rng: RandomNumberGenerator) -> void:
	var all_ok := true
	var count := 0
	var first_bad := ""
	for card in CLASSES:
		for race in RACES:
			for tier in 4:
				var p = _prep(rules, camp, rng)
				CardDeck.set_race(p.card_deck, card, race)
				var state := _state(p, rules, camp, cosmetics)
				for slot in SLOTS:
					if slot == "weapon" and not CardDeck.class_data(card).has("weapon_families"):
						continue
					# The starter piece is of ANOTHER race on purpose: the weapon must become the CARD's race weapon.
					var other: String = RACES[(RACES.find(race) + 1) % 4]
					var piece = _starter_piece(rules, "starter-t-%s-%s-%d" % [card, slot, tier], slot, tier, card, other)
					p.stash.add_item(piece)
					var subs: Array = piece.substats.duplicate(true)
					var gold_before: int = p.stash.gold
					var res: Dictionary = Commands.apply(state, {"type": "tier_up", "item": piece.id, "card": card}, rng)
					var want: String = rules.catalog.race_piece(race, card, slot)
					var good: bool = res.get("ok", false) and piece.item_id == want and piece.tier == tier and not piece.id.begins_with("starter-") \
						and p.stash.gold == gold_before - COST and absf(piece.durability_ratio() - 0.37) < 0.001 and piece.refine_level == 3 and piece.level == 2 \
						and piece.upgrade_count == 2 and piece.substats == subs and p.stash.items.has(piece) and piece.slot == slot
					if slot == "weapon":
						good = good and piece.weapon_type == str(rules.catalog.entry(want).get("weapon_type", ""))
					good = good and Profile.slot_problem(card, piece, rules, 15).is_empty()
					count += 1
					if not good:
						all_ok = false
						if first_bad.is_empty():
							first_bad = "%s/%s/tier%d/%s -> %s %s" % [card, race, tier, slot, piece.item_id, str(res)]
	ctx.check("tier-up: lv15 item for 4 tiers x 5 slots x 4 classes x 4 races, tier/durability/refine/substats kept, gold exact (%d cases) %s" % [count, first_bad], all_ok and count >= 4 * 4 * 4 * 5 - 4 * 4)


func _gate_and_gold(ctx, rules, camp, cosmetics, rng: RandomNumberGenerator) -> void:
	var p = _prep(rules, camp, rng, 14, COST)
	var state := _state(p, rules, camp, cosmetics)
	var piece = _starter_piece(rules, "starter-gate", "shirt", 2, "magic", "human")
	p.stash.add_item(piece)
	var cmd := {"type": "tier_up", "item": "starter-gate", "card": "magic"}
	var low: Dictionary = Commands.apply(state, cmd, rng)
	ctx.check("tier-up: card level 14 is refused (card_level_too_low), nothing changes", low.get("error", "") == "card_level_too_low" and piece.id == "starter-gate" and p.stash.gold == COST)
	var q := TierUp.quote(p, rules, piece, "magic")
	ctx.check("tier-up quote shows target, need 15, card level 14, cost 2500 while refused", q["target"] == "armour_magic_shirt" and q["need_level"] == 15 and q["card_level"] == 14 and q["cost"] == COST and not q["ok"])
	p.card_deck["cards"]["magic"]["progress"] = {"level": 15, "xp": 0}
	p.stash.gold = COST - 1
	ctx.check("tier-up: 2499 gold is refused (not_enough_gold)", Commands.apply(state, cmd, rng).get("error", "") == "not_enough_gold" and piece.id == "starter-gate" and p.stash.gold == COST - 1)
	p.stash.gold = COST
	var ok: Dictionary = Commands.apply(state, cmd, rng)
	ctx.check("tier-up: card level 15 and 2500 gold is accepted, gold goes to 0", ok.get("ok", false) and p.stash.gold == 0 and piece.item_id == "armour_magic_shirt" and piece.tier == 2)
	ctx.check("tier-up: the piece is now level 15 (starter exemption gone): a level-14 card could not wear it", Profile.slot_problem("magic", piece, rules, 14) == "level_too_low")
	var again: Dictionary = Commands.apply(state, {"type": "tier_up", "item": piece.id, "card": "magic"}, rng)
	ctx.check("tier-up: a level-15 piece cannot be tiered up again (not_eligible)", again.get("error", "") == "not_eligible")
	var no_card: Dictionary = Commands.apply(state, {"type": "tier_up", "item": "nope"}, rng)
	ctx.check("tier-up: unknown item is refused (item_not_owned)", no_card.get("error", "") == "item_not_owned")


func _raceless(ctx, rules, camp, cosmetics, rng: RandomNumberGenerator) -> void:
	var p = Profile.new_player(rules, camp, rng)  # a brand new player: cards have no race yet
	p.card_deck["cards"]["magic"]["progress"] = {"level": 15, "xp": 0}
	p.stash.gold = COST
	var piece = _starter_piece(rules, "starter-raceless", "weapon", 0, "magic", "human")
	p.stash.add_item(piece)
	var res: Dictionary = Commands.apply(_state(p, rules, camp, cosmetics), {"type": "tier_up", "item": "starter-raceless", "card": "magic"}, rng)
	ctx.check("tier-up: a card without a race is refused (no_card)", res.get("error", "") == "no_card" and piece.id == "starter-raceless")


func _worn_and_race_change(ctx, rules, camp, cosmetics, rng: RandomNumberGenerator) -> void:
	var p = _prep(rules, camp, rng)
	var state := _state(p, rules, camp, cosmetics)
	var worn = p.loadout_of("longbow").item_at("weapon", 0)
	var old_id: String = worn.id
	ctx.check("tier-up: the new player's weapon is a starter piece", old_id.begins_with("starter-"))
	CardDeck.set_race(p.card_deck, "longbow", "elf")
	var res: Dictionary = Commands.apply(state, {"type": "tier_up", "item": old_id}, rng)
	ctx.check("tier-up: a worn piece needs no card, becomes the weapon of the card's CURRENT race, stays worn", res.get("ok", false) and p.loadout_of("longbow").item_at("weapon", 0) == worn and worn.item_id == "race_elf_longbow_weapon" and worn.weapon_type == "longbow")
	var bare: Dictionary = Commands.apply(state, {"type": "tier_up", "item": _stash_piece_id(p, rules, rng, "shoes", "magic")}, rng)
	ctx.check("tier-up: a stash piece without a card is refused (no_card)", bare.get("error", "") == "no_card")
	var stranger: Dictionary = Commands.apply(state, {"type": "tier_up", "item": _stash_piece_id(p, rules, rng, "pants", "magic"), "card": "ghost"}, rng)
	ctx.check("tier-up: an unknown card is refused (invalid_card)", stranger.get("error", "") == "invalid_card")
	var wrong: Dictionary = Commands.apply(state, {"type": "tier_up", "item": _stash_piece_id(p, rules, rng, "weapon", "magic"), "card": "greatsword"}, rng)
	ctx.check("tier-up: a magic staff for a greatsword card is refused (wrong_weapon_family)", wrong.get("error", "") == "wrong_weapon_family")


func _stash_piece_id(p, rules, rng, slot: String, class_id: String) -> String:
	var id := "starter-extra-%s-%s-%d" % [class_id, slot, p.stash.items.size()]
	p.stash.add_item(_starter_piece(rules, id, slot, 1, class_id, "human"))
	return id


func _ineligible(ctx, rules, camp, cosmetics, rng: RandomNumberGenerator) -> void:
	var p = _prep(rules, camp, rng)
	var state := _state(p, rules, camp, cosmetics)
	var shield = p.loadout_of("sword_shield").item_at("offhand", 0)
	var res: Dictionary = Commands.apply(state, {"type": "tier_up", "item": shield.id}, rng)
	ctx.check("tier-up: a shield is not eligible", res.get("error", "") == "not_eligible" and shield.id.begins_with("starter-"))
	var boss_id := ""
	for id in rules.catalog.items:
		if not str(rules.catalog.entry(id).get("boss", "")).is_empty() and rules.catalog.entry(id)["slot"] == "ring":
			boss_id = str(id)
	var ring = ItemSystem.create_item(rules, "boss-ring", "ring", 2, rng, "", boss_id)
	p.stash.add_item(ring)
	ctx.check("tier-up: a boss accessory is not eligible", Commands.apply(state, {"type": "tier_up", "item": "boss-ring", "card": "magic"}, rng).get("error", "") == "not_eligible")
	var gone = _starter_piece(rules, "starter-gone", "shirt", 1, "magic", "human")
	gone.destroyed = true
	p.stash.add_item(gone)
	ctx.check("tier-up: a destroyed piece is not eligible", Commands.apply(state, {"type": "tier_up", "item": "starter-gone", "card": "magic"}, rng).get("error", "") == "item_not_owned" or not TierUp.quote(p, rules, gone, "magic")["ok"])
	var dropped = ItemSystem.create_item(rules, "drop-1", "shirt", 1, rng, "", "armour_magic_shirt")
	p.stash.add_item(dropped)
	ctx.check("tier-up: a non-starter level-15 piece is not eligible", Commands.apply(state, {"type": "tier_up", "item": "drop-1", "card": "magic"}, rng).get("error", "") == "not_eligible")
	var vault_piece = _starter_piece(rules, "starter-vault", "pants", 1, "magic", "human")
	p.vault.capacity = 4
	p.vault.items.append(vault_piece)
	ctx.check("tier-up: a piece in the vault is refused", Commands.apply(state, {"type": "tier_up", "item": "starter-vault", "card": "magic"}, rng).get("error", "") == "item_not_in_container")
	var camp_only: Dictionary = Commands.apply({"profile": p, "rules": rules, "camp": camp, "location": "stage"}, {"type": "tier_up", "item": "starter-gone"}, rng)
	ctx.check("tier-up: not available outside camp", not camp_only.get("ok", false))


func _old_upgrade_gone(ctx, rules, camp, cosmetics, rng: RandomNumberGenerator) -> void:
	var p = _prep(rules, camp, rng)
	var res: Dictionary = Commands.apply(_state(p, rules, camp, cosmetics), {"type": "upgrade", "item": "x", "count": 0}, rng)
	ctx.check("old substat upgrade command is deprecated, not applied", res.get("error", "") == "deprecated")
	ctx.check("the old Upgrade rules file is gone and the tuning block is disabled", not FileAccess.file_exists("res://logic/upgrade.gd") and not bool(rules.upgrade.get("enabled", true)) and rules.errors.is_empty())
	# An old save keeps its substat upgrades: loading, saving and tier-up leave them as they were.
	var item = _starter_piece(rules, "starter-old", "shirt", 2, "magic", "human")
	item.substats[0]["upgrade_bonus"] = 2.5
	item.upgrade_count = 4
	var d: Dictionary = JSON.parse_string(JSON.stringify(item.to_dict()))
	var loaded = load("res://logic/item.gd").from_dict(d)
	ctx.check("old save: substat upgrade bonus and counter still load", loaded != null and is_equal_approx(float(loaded.substats[0]["upgrade_bonus"]), 2.5) and loaded.upgrade_count == 4)
	p.stash.add_item(loaded)
	var before: Array = loaded.substats.duplicate(true)
	var res2: Dictionary = Commands.apply(_state(p, rules, camp, cosmetics), {"type": "tier_up", "item": "starter-old", "card": "magic"}, rng)
	ctx.check("old save: tier-up keeps the substat upgrades and counter", res2.get("ok", false) and loaded.substats == before and loaded.upgrade_count == 4)


func _runner(ctx, rules, camp, rng: RandomNumberGenerator) -> void:
	var runner := Runner.new()
	ctx.check("tier-up: the profile runner still loads with the deprecated upgrade block", runner.ready())
	ctx.check("tier-up: tier_up is in the profile runner allow-list", Runner.ALLOWED.has("tier_up"))
	var made := runner.execute({"v": 1, "state": null, "seed": "abcdef012345678", "name": "", "command": null})
	var p = Profile.from_dict(made.profile, runner.rules, runner.camp)
	p.card_deck["cards"]["magic"]["progress"] = {"level": 15, "xp": 0}
	CardDeck.set_race(p.card_deck, "magic", "human")
	p.stash.gold = 5000
	var piece = _starter_piece(runner.rules, "starter-run", "shoes", 3, "magic", "viking")
	p.stash.add_item(piece)
	var saved := {"profile": p.to_dict(), "rng_state": made.rng_state}
	var cmd := {"type": "tier_up", "item": "starter-run", "card": "magic"}
	var online := runner.execute({"v": 1, "state": saved.duplicate(true), "seed": "abcdef012345678", "name": "", "command": cmd})
	ctx.check("tier-up: the profile runner accepts the command (%s)" % str(online.get("error", "")), online.get("ok", false))
	var offline = Profile.from_dict(JSON.parse_string(JSON.stringify(saved.profile)), runner.rules, runner.camp)
	var direct := Commands.apply({"profile": offline, "rules": runner.rules, "camp": runner.camp, "cosmetics": runner.cosmetics, "location": "camp"}, cmd, rng)
	var online_item: Dictionary = {}
	for entry in online.get("profile", {}).get("stash", {}).get("items", []):
		if str(entry.get("id", "")).begins_with("tier-up-"):
			online_item = entry
	var off_item = offline.stash.items.filter(func(i): return i.id.begins_with("tier-up-"))
	ctx.check("tier-up: online (runner) and offline (Commands) give the same piece and gold", direct.get("ok", false) and not off_item.is_empty() and online_item == off_item[0].to_dict() and int(online.profile.stash.gold) == offline.stash.gold and offline.stash.gold == 2500)
	var old := runner.execute({"v": 1, "state": saved.duplicate(true), "seed": "abcdef012345678", "name": "", "command": {"type": "upgrade", "item": "starter-run", "count": 0}})
	ctx.check("tier-up: the runner answers the old upgrade with deprecated", not old.get("ok", true) and old.get("error", "") == "deprecated")
