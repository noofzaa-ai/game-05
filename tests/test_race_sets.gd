extends RefCounted
## Race gear sets (design/gdd/race-gear-sets.md 3.6-3.8, 3.14, 4.1-4.4; acceptance 5-9; Boss revision 2026-11-16): a race set
## is the race WEAPON only (one step at 1 piece); armour is class-bound and gives no race bonus. The option boosts the race
## passive only when the card's race matches the weapon's race; the step uses the weapon's tier; set + tree share the caps.
const RP := preload("res://tests/test_race_passives.gd")
const RaceSets := preload("res://logic/race_sets.gd")
const RacePassives := preload("res://logic/race_passives.gd")
const TreeEffects := preload("res://logic/skill_tree_effects.gd")
const SkillTree := preload("res://logic/skill_tree.gd")
const TreeData := preload("res://logic/skill_tree_data.gd")
const Progress := preload("res://logic/card_progress.gd")
const Deck := preload("res://logic/card_deck.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Stats := preload("res://logic/stats.gd")
const GS := "greatsword"
const SS := "sword_shield"
const LB := "longbow"
const SLOTS := ["weapon", "shirt", "pants", "armband", "shoes"]
const RARE := 1
const EPIC := 2
const LEGENDARY := 3


func run(ctx) -> void:
	_data(ctx)
	_lowest_tier(ctx)
	_match_vs_mismatch(ctx)
	_race_toggle(ctx)
	_caps_with_tree(ctx)


## Dresses `card` in `race`'s set: `tiers` = one tier per piece in SLOTS order (fewer = fewer pieces worn).
static func dress(f: Dictionary, card: String, race: String, tiers: Array) -> void:
	var worn = f.profile.loadout_of(card)
	for i in tiers.size():
		var slot: String = SLOTS[i]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([card, slot])
		worn.unequip(slot, 0)
		var item_id := "race_%s_%s_weapon" % [race, card] if slot == "weapon" else "armour_%s_%s" % [card, slot]
		worn.equip(ItemSystem.create_item(f.rules, "set-%s-%s" % [card, slot], slot, int(tiers[i]), rng, "", item_id))


## A squad whose `card` wears `race`'s set at `tiers` (the other cards plain), fighters attached after dressing.
static func squad_with(races: Array, card: String, race: String, tiers: Array, prepare: Callable = Callable()) -> Dictionary:
	var f := RP.squad(races)
	dress(f, card, race, tiers)
	if prepare.is_valid():
		prepare.call(f)
	for id in f.sim.runs:
		f.sim.attach_run(id, f.sim.runs[id], f.rules, f.loot)
	return f


static func fighter_of(f: Dictionary, card: String):
	for id in f.sim.runs:
		if str(f.sim.runs[id].card_id) == card:
			return f.sim.fighters[id]
	return null


static func berserker_at(fighter, h: float) -> float:
	fighter.hp = fighter.max_hp() * h
	return RacePassives.scaling_mul(fighter, "ATK")


func _data(ctx) -> void:
	var rules = preload("res://logic/item_rules_loader.gd").load_default()
	var ok := true
	for race in ["human", "viking", "elf", "runeborn"]:
		var info: Dictionary = rules.catalog.sets.get("race_" + race, {})
		ok = ok and str(info.get("kind", "")) == "race" and info["steps"].map(func(s): return int(s["pieces"])) == [1] and info["bonuses"].is_empty()
		for card in Deck.classes():
			for slot in SLOTS:
				ok = ok and rules.catalog.race_piece(race, card, slot) != ""
				ok = ok and (slot == "weapon" or (str(rules.catalog.entry("armour_%s_%s" % [card, slot]).get("set", "x")) == "" and rules.catalog.race_piece(race, card, slot) == "armour_%s_%s" % [card, slot]))
			ok = ok and rules.catalog.entry("race_%s_%s_weapon" % [race, card])["weapon_type"] in preload("res://logic/profile.gd").weapon_families(card)
	ctx.check("race sets: 4 weapon-only sets (one step at 1 piece), class armour has no set, no flat bonus", ok)
	var ids: Array = ["race_viking_greatsword_weapon", "armour_greatsword_shirt", "armour_greatsword_pants", "armour_greatsword_armband", "armour_greatsword_shoes"]
	ctx.check("race sets: race pieces never feed the flat set bonus", rules.catalog.set_bonus(ids).is_empty())


## One step at 1 piece: the weapon's tier decides m, whatever the armour tiers are.
func _lowest_tier(ctx) -> void:
	var f := squad_with(["human", "viking", "elf"], GS, "viking", [LEGENDARY, RARE, RARE, RARE, RARE])
	var status: Array = RaceSets.status(f.rules, f.profile.loadout_of(GS).items(), "viking", GS)
	var steps: Array = status[0]["steps"] if status.size() == 1 else []
	ctx.check("weapon tier: one step at the weapon's tier (%s)" % [steps.map(func(s): return s["tier"])], steps.size() == 1 and steps[0]["tier"] == "legendary" and is_equal_approx(steps[0]["m"], 1.5) and status[0]["count"] == 1 and status[0]["total"] == 1)
	var white := squad_with(["human", "viking", "elf"], GS, "viking", [0])
	var w: Array = RaceSets.status(white.rules, white.profile.loadout_of(GS).items(), "viking", GS)
	ctx.check("white starter weapon: the option works at x0.75 of blue", is_equal_approx(w[0]["steps"][0]["m"], 0.75) and w[0]["steps"][0]["active"])
	var armour_only := squad_with(["human", "viking", "elf"], GS, "viking", [])
	for slot in ["shirt", "pants", "armband", "shoes"]:
		armour_only.profile.loadout_of(GS).equip(ItemSystem.create_item(armour_only.rules, "arm-" + slot, slot, EPIC, RandomNumberGenerator.new(), "", "armour_greatsword_" + slot))
	ctx.check("armour: class armour alone gives no race set status", RaceSets.status(armour_only.rules, armour_only.profile.loadout_of(GS).items(), "viking", GS).is_empty())


## 4.4 / acceptance 5: Viking greatsword with 2 / 4 / 5 blue Viking pieces vs the same pieces on an Elf greatsword.
func _match_vs_mismatch(ctx) -> void:
	var base := RP.squad(["human", "viking", "elf"])
	var plain: float = berserker_at(fighter_of(base, GS), 0.5)
	ctx.check("4.4 no set: Berserker +25.0%% ATK at 50%% HP (%.3f)" % plain, absf(plain - 0.25) < 0.001)
	var weapon := squad_with(["human", "viking", "elf"], GS, "viking", [RARE])
	var w_at: float = berserker_at(fighter_of(weapon, GS), 0.5)
	ctx.check("4.4 blue Viking weapon: +29.3%% at 50%% HP (%.3f)" % w_at, absf(w_at - 0.44 * 0.5 / 0.75) < 0.001)
	var all_blue := squad_with(["human", "viking", "elf"], GS, "viking", [RARE, RARE, RARE, RARE, RARE])
	var gs5 = fighter_of(all_blue, GS)
	var blood_up: Array = gs5.race_state["effects"].filter(func(e): return e["src"] == "passive" and e["effect"]["type"] == "trigger" and str(e["effect"]["on"]) == "self_low_hp")
	ctx.check("armour adds nothing: weapon + 4 armour = the weapon alone, no 5-piece Blood Up", absf(berserker_at(gs5, 0.5) - w_at) < 0.001 and blood_up.is_empty())
	var armour_only := squad_with(["human", "viking", "elf"], GS, "viking", [])
	armour_only.profile.loadout_of(GS).unequip("weapon", 0)
	for slot in ["shirt", "pants", "armband", "shoes"]:
		armour_only.profile.loadout_of(GS).equip(ItemSystem.create_item(armour_only.rules, "arm-" + slot, slot, EPIC, RandomNumberGenerator.new(), "", "armour_greatsword_" + slot))
	for id in armour_only.sim.runs:
		armour_only.sim.attach_run(id, armour_only.sim.runs[id], armour_only.rules, armour_only.loot)
	var armour_at: float = berserker_at(fighter_of(armour_only, GS), 0.5)
	ctx.check("armour gives no race bonus (Berserker %.3f = no set %.3f, race_set 0)" % [armour_at, plain], absf(armour_at - plain) < 0.001 and int(fighter_of(armour_only, GS).race_state["race_set"]) == 0)
	var gold := squad_with(["human", "viking", "elf"], GS, "viking", [LEGENDARY])
	ctx.check("4.4 gold Viking weapon: +31.7%% at 50%% HP (%.3f)" % berserker_at(fighter_of(gold, GS), 0.5), absf(berserker_at(fighter_of(gold, GS), 0.5) - 0.46 * 0.5 / 0.725) < 0.001)
	# The same 5 Viking pieces on an Elf greatsword: same raw stats, Living Bark unchanged.
	var elf_plain := RP.squad(["human", "elf", "elf"])
	var elf_set := squad_with(["human", "elf", "elf"], GS, "viking", [RARE, RARE, RARE, RARE, RARE])
	var a = fighter_of(elf_plain, GS)
	var b = fighter_of(elf_set, GS)
	ctx.check("mismatch: an Elf greatsword in Viking pieces keeps its passive exactly", JSON.stringify(a.race_state["effects"]) == JSON.stringify(b.race_state["effects"]) and int(b.race_state.get("race_set", -1)) == 0)
	var stats_viking: Dictionary = Stats.totals(all_blue.rules, all_blue.profile.loadout_of(GS).items())
	var stats_elf: Dictionary = Stats.totals(elf_set.rules, elf_set.profile.loadout_of(GS).items())
	ctx.check("mismatch: the pieces' stats are the same whoever wears them", stats_viking == stats_elf)


## 3.6 / acceptance 6: changing the card's race turns the option on or off at the next attach.
func _race_toggle(ctx) -> void:
	var f := squad_with(["human", "viking", "elf"], GS, "viking", [RARE])
	ctx.check("toggle: Viking card with the Viking weapon has the option", int(fighter_of(f, GS).race_state["race_set"]) > 0)
	Deck.set_race(f.profile.card_deck, GS, "elf")
	ctx.check("toggle: the hub preview turns off at once (status matched false)", not RaceSets.status(f.rules, f.profile.loadout_of(GS).items(), Deck.race_of(f.profile.card_deck, GS), GS)[0]["matched"])
	for id in f.sim.runs:
		f.sim.attach_run(id, f.sim.runs[id], f.rules, f.loot)
	ctx.check("toggle: after switching to Elf the option is off", int(fighter_of(f, GS).race_state["race_set"]) == 0)
	Deck.set_race(f.profile.card_deck, GS, "viking")
	for id in f.sim.runs:
		f.sim.attach_run(id, f.sim.runs[id], f.rules, f.loot)
	ctx.check("toggle: back to Viking turns it on again", int(fighter_of(f, GS).race_state["race_set"]) > 0)
	f.profile.loadout_of(GS).equip(ItemSystem.create_item(f.rules, "other-weapon", "weapon", RARE, RandomNumberGenerator.new(), "", "race_elf_greatsword_weapon"))
	for id in f.sim.runs:
		f.sim.attach_run(id, f.sim.runs[id], f.rules, f.loot)
	ctx.check("toggle: wearing another race's weapon turns it off", int(fighter_of(f, GS).race_state["race_set"]) == 0)


static func _learn(f: Dictionary, card: String, ids: Array) -> void:
	Progress.grant(f.profile.card_deck, card, 10000000)
	var tree := SkillTree.empty()
	var data = TreeData.load_default()
	for id in ids:
		tree[data.branch_of(id)].append(id)
	f.profile.card_deck["cards"][card]["skill_tree"] = tree


## 3.14 / 4.3 / acceptance 8: set + tree never pass the caps.
func _caps_with_tree(ctx) -> void:
	var rules: Dictionary = preload("res://logic/race_data.gd").load_default().rules
	# Threshold cap: 5 gold Viking (+0.075) + Thick Blood (+0.10) -> capped at +0.15: full_at 0.35 (4.4 last row).
	var thick := _node("viking", func(e): return e["type"] == "cell_mod" and e.has("hp_threshold_add"))
	var f := squad_with(["human", "viking", "elf"], GS, "viking", [LEGENDARY], func(f): _learn(f, GS, [thick]))
	var gs = fighter_of(f, GS)
	ctx.check("caps: gold set + Thick Blood -> +35.4%% at 50%% HP (threshold capped 0.15) (%.3f)" % berserker_at(gs, 0.5), absf(berserker_at(gs, 0.5) - 0.46 * 0.5 / 0.65) < 0.001)
	# Scale cap: many scale_adds never pass passive_scale_cap.
	var merged: Dictionary = TreeEffects.combine_passive_mods([{"type": "cell_mod", "cell": "passive", "scale": 1.3}, {"type": "cell_mod", "cell": "passive", "scale_add": 0.15}, {"type": "cell_mod", "cell": "passive", "scale_add": 0.15}])
	ctx.check("caps: passive scale capped at %.2f (%.2f)" % [float(rules["passive_scale_cap"]), merged["scale"]], is_equal_approx(merged["scale"], float(rules["passive_scale_cap"])))
	# Cooldown floor: Drilled Ranks (0.75) + 4 Human pieces (0.85) -> 0.6375 >= floor 0.60; with gold 0.775 -> floored.
	var drilled := _node("human", func(e): return e["type"] == "cell_mod" and e.has("icd_mul") and e.has("scale"))
	f = squad_with(["human", "viking", "elf"], SS, "human", [LEGENDARY], func(f): _learn(f, SS, [drilled]))
	var drill: Array = fighter_of(f, SS).race_state["effects"].filter(func(e): return e["src"] == "passive" and e["effect"].has("cooldown_ticks"))
	var floor_ticks := int(round(600.0 * float(rules["cooldown_mul_floor"])))
	ctx.check("caps: Rallying Drill cooldown never below the 0.60 floor (%s ticks)" % [drill.map(func(e): return e["effect"]["cooldown_ticks"])], drill.size() == 1 and int(drill[0]["effect"]["cooldown_ticks"]) == floor_ticks)
	# Rune floor: Quick Glyphs (-1) + 4 Runeborn pieces (-1) on the bow: 6 -> 4; never below 2.
	var glyphs := _node("runeborn", func(e): return e["type"] == "cell_mod" and e.has("charges_max_add"))
	f = squad_with(["human", "viking", "runeborn"], LB, "runeborn", [RARE], func(f): _learn(f, LB, [glyphs]))
	var charges: Array = fighter_of(f, LB).race_state["effects"].filter(func(e): return e["effect"]["type"] == "charges")
	ctx.check("caps: Glyph Shot runes 6 -> 4 with tree + set", charges.size() == 1 and int(charges[0]["effect"]["max"]) == 4)
	var low: Dictionary = TreeEffects.cell_mod_effect({"type": "charges", "gain_on": ["hit"], "gain": 1, "max": 3, "actions": []}, {"charges_max_add": -5})
	ctx.check("caps: rune max never below %d" % int(rules["charges_max_floor"]), int(low["max"]) == int(rules["charges_max_floor"]))
	# every_n floor: Moonwell Arrows (combo -2) + 4 Elf pieces (-1): every 5th -> 2nd, the floor.
	var n: Dictionary = TreeEffects.cell_mod_effect({"type": "trigger", "on": "hit", "every_n": 5, "actions": []}, TreeEffects.combine_passive_mods([{"every_n_add": -2.0}, {"every_n_add": -1}, {"every_n_add": -1}]))
	ctx.check("caps: every_n never below %d (%d)" % [int(rules["every_n_floor"]), int(n["every_n"])], int(n["every_n"]) == int(rules["every_n_floor"]))


static func _node(race: String, pred: Callable) -> String:
	for n in TreeData.load_default().race_nodes(race):
		for e in n["effects"]:
			if pred.call(e):
				return n["id"]
	return ""
