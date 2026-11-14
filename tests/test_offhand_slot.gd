extends RefCounted
## Off-hand slot (Boss 2026-11-11): shields go in an `offhand` slot that only the Sword & Shield card may use
## (data/items/rules.json slots[].classes); shields carry stats, refine and drop; every Sword & Shield card
## (new or migrated) starts with one shield.
const Profile := preload("res://logic/profile.gd")
const Commands := preload("res://logic/commands.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Loot := preload("res://logic/loot.gd")
const Stats := preload("res://logic/stats.gd")
const Refine := preload("res://logic/refine.gd")


func run(ctx) -> void:
	var rules = preload("res://logic/item_rules_loader.gd").load_default()
	var camp = preload("res://logic/camp_data_loader.gd").load_default(rules.tiers.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	ctx.check("offhand: the rules load without errors", rules.errors.is_empty() and not rules.slot("offhand").is_empty())
	ctx.check("offhand: open to Sword & Shield only", rules.slot_open_for("offhand", "sword_shield") and not rules.slot_open_for("offhand", "greatsword") and not rules.slot_open_for("offhand", "longbow") and not rules.slot_open_for("offhand", "magic"))
	ctx.check("offhand: other slots stay open to every class", rules.slot_open_for("ring", "magic") and rules.slot_open_for("weapon", "longbow"))
	ctx.check("offhand: the catalog has a shield item per race", ["human", "viking", "elf", "runeborn"].all(func(r): return rules.catalog.entry(Profile.starter_shield(rules, r)).get("slot") == "offhand"))

	# New player: the Sword & Shield card wears a starter shield; the other cards do not.
	var p = Profile.new_player(rules, camp, rng)
	var STARTER_SHIELD := Profile.starter_shield(rules, preload("res://logic/card_deck.gd").gear_race(p.card_deck, "sword_shield"))
	var shield = p.loadout_of("sword_shield").item_at("offhand", 0)
	ctx.check("offhand: a new Sword & Shield card wears the starter shield", shield != null and shield.id == "starter-offhand-v1-sword_shield" and shield.item_id == STARTER_SHIELD and STARTER_SHIELD.ends_with("_shield"))
	ctx.check("offhand: other cards get no shield", ["greatsword", "longbow", "magic"].all(func(c): return p.loadout_of(c).item_at("offhand", 0) == null))
	ctx.check("offhand: the shield adds stats", Stats.totals(rules, p.loadout_of("sword_shield").items()).get("DEF", 0.0) > Stats.totals(rules, p.loadout_of("sword_shield").items().filter(func(i): return i.slot != "offhand")).get("DEF", 0.0))

	# Old save (before the off-hand slot): migrated once, deterministically; an emptied slot stays empty.
	var old: Dictionary = JSON.parse_string(JSON.stringify(p.to_dict()))
	old.erase("starter_shield_kit_version")
	old["card_gear"]["sword_shield"]["loadout"]["equipped"].erase("offhand:0")
	var migrated = Profile.from_dict(old, rules, camp)
	ctx.check("offhand: an old save's Sword & Shield card gets the starter shield", migrated != null and migrated.loadout_of("sword_shield").item_at("offhand", 0) != null and migrated.starter_shield_kit_version == 1)
	var again = Profile.from_dict(JSON.parse_string(JSON.stringify(old)), rules, camp)
	ctx.check("offhand: the migration is deterministic", again.to_dict() == migrated.to_dict())
	var saved: Dictionary = JSON.parse_string(JSON.stringify(p.to_dict()))
	saved["card_gear"]["sword_shield"]["loadout"]["equipped"].erase("offhand:0")
	var emptied = Profile.from_dict(saved, rules, camp)
	ctx.check("offhand: a granted-then-removed shield is not granted again", emptied != null and emptied.loadout_of("sword_shield").item_at("offhand", 0) == null)

	# Commands: equip on Sword & Shield works; other classes get slot_closed.
	var state := {"profile": p, "rules": rules, "camp": camp, "location": "camp", "cosmetics": preload("res://logic/cosmetic_options.gd").load_default()}
	var spare = ItemSystem.create_item(rules, "test-shield", "offhand", 2, rng, "", STARTER_SHIELD)
	p.stash.add_item(spare)
	for card in ["greatsword", "longbow", "magic"]:
		var refused: Dictionary = Commands.apply(state, {"type": "equip", "item": "test-shield", "source": "stash", "card": card}, rng)
		ctx.check("offhand: %s cannot equip a shield (slot_closed)" % card, refused.get("error") == "slot_closed" and p.stash.items.has(spare))
	var ok: Dictionary = Commands.apply(state, {"type": "equip", "item": "test-shield", "source": "stash", "card": "sword_shield"}, rng)
	ctx.check("offhand: Sword & Shield equips a shield, the old one goes to the stash", ok.get("ok", false) and p.loadout_of("sword_shield").item_at("offhand", 0) == spare and p.stash.items.has(shield))
	ctx.check("offhand: a direct stash equip is also refused for other classes", not p.equip_from_stash(p.stash.items.find(shield), 0, "magic"))
	var off: Dictionary = Commands.apply(state, {"type": "unequip", "slot": "offhand", "destination": "stash", "card": "sword_shield"}, rng)
	ctx.check("offhand: the shield can be taken off", off.get("ok", false) and p.loadout_of("sword_shield").item_at("offhand", 0) == null)

	# Refine and drops.
	ctx.check("offhand: shields can be refined", Refine.quote(spare, rules, camp).get("ok", false))
	var dropped := false
	var drop_rng := RandomNumberGenerator.new()
	drop_rng.seed = 3
	for i in 400:
		var piece = Loot.roll_piece(rules, "drop-%d" % i, 0, 5, ["blade"], drop_rng)
		if piece != null and piece.slot == "offhand":
			dropped = piece.item_id.begins_with("race_") and piece.item_id.ends_with("_shield")
			break
	ctx.check("offhand: shields can drop", dropped)
