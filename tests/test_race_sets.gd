extends RefCounted
## Race gear sets (design/gdd/race-gear-sets.md 3.6-3.8, 3.14, 4.1-4.4; acceptance 5-9; Boss 2026-11-13): a race set is
## the race weapon + shirt, pants, armband, shoes (5 pieces), steps 2 / 4 / 5. The option boosts the race passive only
## when the card's race matches the set; a step uses the lowest tier of the N best pieces; set + tree share the caps.
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
		worn.equip(ItemSystem.create_item(f.rules, "set-%s-%s" % [card, slot], slot, int(tiers[i]), rng, "", "race_%s_%s_%s" % [race, card, slot]))


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
		ok = ok and str(info.get("kind", "")) == "race" and info["steps"].map(func(s): return int(s["pieces"])) == [2, 4, 5] and info["bonuses"].is_empty()
		for card in Deck.classes():
			for slot in SLOTS:
				ok = ok and rules.catalog.race_piece(race, card, slot) != ""
			ok = ok and rules.catalog.entry("race_%s_%s_weapon" % [race, card])["weapon_type"] in preload("res://logic/profile.gd").weapon_families(card)
	ctx.check("race sets: 4 sets of 5 pieces (race weapon + 4 armour) per class, steps 2/4/5, no flat bonus", ok)
	var ids: Array = ["race_viking_greatsword_weapon", "race_viking_greatsword_shirt", "race_viking_greatsword_pants", "race_viking_greatsword_armband", "race_viking_greatsword_shoes"]
	ctx.check("race sets: race pieces never feed the flat set bonus", rules.catalog.set_bonus(ids).is_empty())


## 3.7 / 4.1: gold, gold, purple, blue, blue -> step 2 gold (1.5), step 4 blue (1.0), step 5 blue (1.0).
func _lowest_tier(ctx) -> void:
	var f := squad_with(["human", "viking", "elf"], GS, "viking", [LEGENDARY, LEGENDARY, EPIC, RARE, RARE])
	var status: Array = RaceSets.status(f.rules, f.profile.loadout_of(GS).items(), "viking", GS)
	var steps: Array = status[0]["steps"] if status.size() == 1 else []
	ctx.check("lowest tier: steps use legendary / rare / rare (%s)" % [steps.map(func(s): return s["tier"])], steps.size() == 3 and steps[0]["tier"] == "legendary" and steps[1]["tier"] == "rare" and steps[2]["tier"] == "rare")
	ctx.check("lowest tier: m = 1.5 / 1.0 / 1.0", steps.size() == 3 and is_equal_approx(steps[0]["m"], 1.5) and is_equal_approx(steps[1]["m"], 1.0) and is_equal_approx(steps[2]["m"], 1.0))
	var white := squad_with(["human", "viking", "elf"], GS, "viking", [0, 0])
	var w: Array = RaceSets.status(white.rules, white.profile.loadout_of(GS).items(), "viking", GS)
	ctx.check("white starter pieces: the option works at x0.75 of blue", is_equal_approx(w[0]["steps"][0]["m"], 0.75) and w[0]["steps"][0]["active"])


## 4.4 / acceptance 5: Viking greatsword with 2 / 4 / 5 blue Viking pieces vs the same pieces on an Elf greatsword.
func _match_vs_mismatch(ctx) -> void:
	var base := RP.squad(["human", "viking", "elf"])
	var plain: float = berserker_at(fighter_of(base, GS), 0.5)
	ctx.check("4.4 no set: Berserker +25.0%% ATK at 50%% HP (%.3f)" % plain, absf(plain - 0.25) < 0.001)
	var two := squad_with(["human", "viking", "elf"], GS, "viking", [RARE, RARE])
	ctx.check("4.4 2 blue: +27.5%% at 50%% HP (%.3f)" % berserker_at(fighter_of(two, GS), 0.5), absf(berserker_at(fighter_of(two, GS), 0.5) - 0.275) < 0.001)
	var four := squad_with(["human", "viking", "elf"], GS, "viking", [RARE, RARE, RARE, RARE])
	ctx.check("4.4 4 blue: +29.3%% at 50%% HP (%.3f)" % berserker_at(fighter_of(four, GS), 0.5), absf(berserker_at(fighter_of(four, GS), 0.5) - 0.44 * 0.5 / 0.75) < 0.001)
	var five := squad_with(["human", "viking", "elf"], GS, "viking", [RARE, RARE, RARE, RARE, RARE])
	var gs5 = fighter_of(five, GS)
	var blood_up: Array = gs5.race_state["effects"].filter(func(e): return e["src"] == "passive" and e["effect"]["type"] == "trigger" and str(e["effect"]["on"]) == "self_low_hp")
	ctx.check("4.4 5 blue: same Berserker numbers plus Blood Up (rage 360 ticks below 50%)", absf(berserker_at(gs5, 0.5) - 0.44 * 0.5 / 0.75) < 0.001 and blood_up.size() == 1 and int(blood_up[0]["effect"]["actions"][0]["duration"]) == 360)
	var gold := squad_with(["human", "viking", "elf"], GS, "viking", [LEGENDARY, LEGENDARY, LEGENDARY, LEGENDARY, LEGENDARY])
	ctx.check("4.4 5 gold: +31.7%% at 50%% HP (%.3f)" % berserker_at(fighter_of(gold, GS), 0.5), absf(berserker_at(fighter_of(gold, GS), 0.5) - 0.46 * 0.5 / 0.725) < 0.001)
	# The same 5 Viking pieces on an Elf greatsword: same raw stats, Living Bark unchanged.
	var elf_plain := RP.squad(["human", "elf", "elf"])
	var elf_set := squad_with(["human", "elf", "elf"], GS, "viking", [RARE, RARE, RARE, RARE, RARE])
	var a = fighter_of(elf_plain, GS)
	var b = fighter_of(elf_set, GS)
	ctx.check("mismatch: an Elf greatsword in Viking pieces keeps its passive exactly", JSON.stringify(a.race_state["effects"]) == JSON.stringify(b.race_state["effects"]) and int(b.race_state.get("race_set", -1)) == 0)
	var stats_viking: Dictionary = Stats.totals(five.rules, five.profile.loadout_of(GS).items())
	var stats_elf: Dictionary = Stats.totals(elf_set.rules, elf_set.profile.loadout_of(GS).items())
	ctx.check("mismatch: the pieces' stats are the same whoever wears them", stats_viking == stats_elf)


## 3.6 / acceptance 6: changing the card's race turns the option on or off at the next attach.
func _race_toggle(ctx) -> void:
	var f := squad_with(["human", "viking", "elf"], GS, "viking", [RARE, RARE, RARE, RARE])
	ctx.check("toggle: Viking card in Viking pieces has the option", int(fighter_of(f, GS).race_state["race_set"]) > 0)
	Deck.set_race(f.profile.card_deck, GS, "elf")
	ctx.check("toggle: the hub preview turns off at once (status matched false)", not RaceSets.status(f.rules, f.profile.loadout_of(GS).items(), Deck.race_of(f.profile.card_deck, GS), GS)[0]["matched"])
	for id in f.sim.runs:
		f.sim.attach_run(id, f.sim.runs[id], f.rules, f.loot)
	ctx.check("toggle: after switching to Elf the option is off", int(fighter_of(f, GS).race_state["race_set"]) == 0)
	Deck.set_race(f.profile.card_deck, GS, "viking")
	for id in f.sim.runs:
		f.sim.attach_run(id, f.sim.runs[id], f.rules, f.loot)
	ctx.check("toggle: back to Viking turns it on again", int(fighter_of(f, GS).race_state["race_set"]) > 0)
	f.profile.loadout_of(GS).unequip("shirt", 0)
	f.profile.loadout_of(GS).unequip("pants", 0)
	f.profile.loadout_of(GS).unequip("armband", 0)
	for id in f.sim.runs:
		f.sim.attach_run(id, f.sim.runs[id], f.rules, f.loot)
	ctx.check("toggle: taking pieces off below 2 turns it off", int(fighter_of(f, GS).race_state["race_set"]) == 0)


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
	var f := squad_with(["human", "viking", "elf"], GS, "viking", [LEGENDARY, LEGENDARY, LEGENDARY, LEGENDARY, LEGENDARY], func(f): _learn(f, GS, [thick]))
	var gs = fighter_of(f, GS)
	ctx.check("caps: gold set + Thick Blood -> +35.4%% at 50%% HP (threshold capped 0.15) (%.3f)" % berserker_at(gs, 0.5), absf(berserker_at(gs, 0.5) - 0.46 * 0.5 / 0.65) < 0.001)
	# Scale cap: many scale_adds never pass passive_scale_cap.
	var merged: Dictionary = TreeEffects.combine_passive_mods([{"type": "cell_mod", "cell": "passive", "scale": 1.3}, {"type": "cell_mod", "cell": "passive", "scale_add": 0.15}, {"type": "cell_mod", "cell": "passive", "scale_add": 0.15}])
	ctx.check("caps: passive scale capped at %.2f (%.2f)" % [float(rules["passive_scale_cap"]), merged["scale"]], is_equal_approx(merged["scale"], float(rules["passive_scale_cap"])))
	# Cooldown floor: Drilled Ranks (0.75) + 4 Human pieces (0.85) -> 0.6375 >= floor 0.60; with gold 0.775 -> floored.
	var drilled := _node("human", func(e): return e["type"] == "cell_mod" and e.has("icd_mul") and e.has("scale"))
	f = squad_with(["human", "viking", "elf"], SS, "human", [LEGENDARY, LEGENDARY, LEGENDARY, LEGENDARY], func(f): _learn(f, SS, [drilled]))
	var drill: Array = fighter_of(f, SS).race_state["effects"].filter(func(e): return e["src"] == "passive" and e["effect"].has("cooldown_ticks"))
	var floor_ticks := int(round(600.0 * float(rules["cooldown_mul_floor"])))
	ctx.check("caps: Rallying Drill cooldown never below the 0.60 floor (%s ticks)" % [drill.map(func(e): return e["effect"]["cooldown_ticks"])], drill.size() == 1 and int(drill[0]["effect"]["cooldown_ticks"]) == floor_ticks)
	# Rune floor: Quick Glyphs (-1) + 4 Runeborn pieces (-1) on the bow: 6 -> 4; never below 2.
	var glyphs := _node("runeborn", func(e): return e["type"] == "cell_mod" and e.has("charges_max_add"))
	f = squad_with(["human", "viking", "runeborn"], LB, "runeborn", [RARE, RARE, RARE, RARE], func(f): _learn(f, LB, [glyphs]))
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
