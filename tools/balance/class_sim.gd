extends SceneTree
## Class balance check (auto-battler): fixed-seed scripted fights of the goblin wave journey
## (data/journeys/goblin_waves.json) through the real rules, with logic/auto_pilot.gd driving our fighters.
##   godot --headless --path . --script res://tools/balance/class_sim.gd [-- seeds=8 only=solo,squad,greatsword]
##   journey=mummy_waves level=15 gear=1 power3=1.8 stat:mummy:ATK=2.5 rule:guard_damage_reduction=0.45
##   react:sword_shield=0.7 (measurement-only overrides, see _init)
## Scenarios: each class solo, the starter squad (logic/card_deck.gd STARTER_SQUAD), and each class x3
## (a measurement only: a real squad never repeats a class). Prints one table row per scenario and one
## row per class inside the squads: win rate, waves reached, time to clear, damage dealt/taken, deaths,
## ultimates fired, share of ticks a fighter spent attacking vs walking (kiting/stall detector).
## Tool only: nothing in the game loads this file.

const Pilot := preload("res://logic/auto_pilot.gd")
const Party := preload("res://logic/coop_journey.gd")
const Journey := preload("res://logic/journey.gd")
const JourneyData := preload("res://logic/journey_data.gd")
const Fighter := preload("res://logic/fighter.gd")
const SimInput := preload("res://logic/sim_input.gd")
const Map := preload("res://logic/map_loader.gd")
const World := preload("res://logic/sim_world.gd")
const Sim := preload("res://logic/game_sim.gd")
const Deck := preload("res://logic/card_deck.gd")
const Rules := preload("res://logic/item_rules_loader.gd")
const Camp := preload("res://logic/camp_data_loader.gd")
const Loot := preload("res://logic/loot_data_loader.gd")
const CombatLoader := preload("res://logic/combat_data_loader.gd")
const Profile := preload("res://logic/profile.gd")
const Run := preload("res://logic/run.gd")

const MAX_TICKS := 60 * 600  ## 10 minutes of fight at 60 ticks/s
const REACTION := -1.0  ## < 0: each card uses its class pilot's reaction (data/classes/<id>.json pilot), as the game does

var rules
var camp
var loot
var combat
var no_skills := false  ## "noskills": detach the skill-build skills (measurement only, to see what they add)
var gear_tier := -1  ## "gear=N": every card also wears a tier-N piece in each open slot (0 normal .. 3 legendary); measurement only
var card_level := 1  ## "level=L": every card is level L and spends its points greedily down its class, race and combo nodes
var journey_id := "goblin_waves"  ## "journey=mummy_waves": measure another wave journey (data/journeys/<id>.json) with the same pilots
var power_override := {}  ## "power1=X" / "power2=X" ...: wave_power_by_squad[N-1] for this measurement only (sweeps without editing data)


func _init() -> void:
	rules = Rules.load_default()
	camp = Camp.load_default(rules.tiers.size())
	loot = Loot.load_default(camp.materials.keys(), rules.tiers.size())
	combat = CombatLoader.load_default()
	var seeds := 8
	var only := ""
	var first := 0  ## first=N: start at seed index N (lets several processes split one measurement)
	no_skills = OS.get_cmdline_user_args().has("noskills")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("seeds="):
			seeds = int(arg.substr(6))
		elif arg.begins_with("first="):
			first = int(arg.substr(6))
		elif arg.begins_with("journey="):
			journey_id = arg.substr(8)
		elif arg.begins_with("only="):
			only = arg.substr(5)
		elif arg.begins_with("gear="):
			gear_tier = int(arg.substr(5))
		elif arg.begins_with("level="):
			card_level = int(arg.substr(6))
		elif arg.begins_with("power") and arg.contains("="):
			power_override[int(arg.substr(5, arg.find("=") - 5))] = float(arg.substr(arg.find("=") + 1))
		elif arg.begins_with("rule:") and arg.contains("="):
			# "rule:guard_damage_reduction=0.45": a combat.json rule for this measurement only
			combat.rules[arg.substr(5, arg.find("=") - 5)] = float(arg.substr(arg.find("=") + 1))
		elif arg.begins_with("react:") and arg.contains("="):
			# "react:sword_shield=0.7": a class pilot's reaction for this measurement only (patches the class cache)
			var pilot: Dictionary = Deck.class_data(arg.substr(6, arg.find("=") - 6)).get("pilot", {})
			pilot["reaction"] = float(arg.substr(arg.find("=") + 1))
		elif arg.begins_with("wstamx:") and arg.contains("="):
			# "wstamx:magic=1.6": multiplies the stamina cost of every generated move of that weapon (<weapon>_*), measurement only
			var weapon := arg.substr(7, arg.find("=") - 7)
			for move_id in combat.moves:
				if str(move_id).begins_with(weapon + "_"):
					combat.moves[move_id]["energy_cost"] = float(combat.moves[move_id]["energy_cost"]) * float(arg.substr(arg.find("=") + 1))
		elif arg.begins_with("wpow:") and arg.contains("="):
			# "wpow:magic=0.8": multiplies the power (damage) of every generated move of that weapon, measurement only
			var wp := arg.substr(5, arg.find("=") - 5)
			for move_id in combat.moves:
				if str(move_id).begins_with(wp + "_"):
					combat.moves[move_id]["power"] = float(combat.moves[move_id]["power"]) * float(arg.substr(arg.find("=") + 1))
		elif arg.begins_with("sstam:") and arg.contains("="):
			# "sstam:arcane_orb=14": a class skill's stamina cost (patches the cached skill data), measurement only
			var all_skills: Dictionary = preload("res://logic/class_skills/skill_data.gd").load_default().skills
			if not all_skills.has(arg.substr(6, arg.find("=") - 6)):
				printerr("unknown skill in ", arg)
				quit(1)
				return
			all_skills[arg.substr(6, arg.find("=") - 6)]["stamina"] = float(arg.substr(arg.find("=") + 1))
		elif arg.begins_with("sstat:") and arg.contains("="):
			# "sstat:arcane_orb:damage=0.9": multiplies one stat of a class skill (cached skill data), measurement only
			var sp := arg.substr(6, arg.find("=") - 6).split(":")
			var sk: Dictionary = preload("res://logic/class_skills/skill_data.gd").load_default().skills[sp[0]]
			sk["stats"][sp[1]] = float(sk["stats"][sp[1]]) * float(arg.substr(arg.find("=") + 1))
		elif arg.begins_with("stat:") and arg.contains("="):
			# "stat:mummy:ATK=2.5" multiplies the base ATK of every enemy whose id starts with "mummy" (measurement only,
			# applied in argument order, so "stat:mummy:ATK=2 stat:mummy_boss:ATK=0.8" leaves the Pharaoh at 1.6x).
			var parts := arg.substr(5, arg.find("=") - 5).split(":")
			var factor := float(arg.substr(arg.find("=") + 1))
			for enemy_id in combat.enemies:
				if str(enemy_id).begins_with(parts[0]):
					var stats: Dictionary = combat.enemies[enemy_id]["stats"]
					stats[parts[1]] = float(stats.get(parts[1], 0.0)) * factor
	var scenarios := []
	for class_id in ["sword_shield", "greatsword", "longbow", "magic"]:
		scenarios.append({"name": "solo " + class_id, "classes": [class_id], "kind": "solo"})
	scenarios.append({"name": "starter squad", "classes": Array(Deck.STARTER_SQUAD), "kind": "squad"})
	scenarios.append({"name": "starter duo", "classes": Array(Deck.STARTER_SQUAD).slice(0, 2), "kind": "duo"})  # loot by squad size (Boss 2026-11-12)
	# A squad with magic (magic is not in the starter squad): measures the magic kit (class-skills.md 4.5).
	scenarios.append({"name": "magic squad", "classes": ["sword_shield", "longbow", "magic"], "kind": "squad"})
	for class_id in ["sword_shield", "greatsword", "longbow", "magic"]:
		scenarios.append({"name": "3x " + class_id, "classes": [class_id, class_id, class_id], "kind": "mono"})
	for arg in OS.get_cmdline_user_args():  # "squad=sword_shield,greatsword,magic": one extra custom squad (only=custom)
		if arg.begins_with("squad="):
			scenarios.append({"name": "custom " + arg.substr(6).replace("sword_shield", "ss").replace("greatsword", "gs").replace("longbow", "lb").replace("magic", "mg"), "classes": Array(arg.substr(6).split(",")), "kind": "custom"})
	print("CLASS SIM  seeds=%d  reaction=class pilot  max=%ds  gear=%s  level=%d" % [seeds, MAX_TICKS / 60, "starter" if gear_tier < 0 else "tier %d" % gear_tier, card_level])
	print("scenario            | win  | waves avg/min | clear s | dmg dealt | dmg taken | deaths | ults | timeouts")
	var per_class := {}
	for scenario in scenarios:
		if not only.is_empty() and not _picked(only, scenario):
			continue
		var wins := 0
		var waves_total := 0
		var waves_min := 99
		var clear_ticks := 0
		var dealt := 0.0
		var taken := 0.0
		var deaths := 0
		var ults := 0
		var timeouts := 0
		var wave_taken := []
		wave_taken.resize(13)
		wave_taken.fill(0.0)
		var loot_total := {"drops": 0, "gold": 0, "items": 0, "materials": 0, "lost_items": 0}
		var kinds_total := {}
		var hp_sum := {"start": {}, "pre": {}, "min": {}, "n": {}, "low": {}}  ## per wave: summed fractions over the runs that reached it
		for s in range(first, first + seeds):
			var result := play(scenario["classes"], 1000 + s * 17)
			for w in result["hp_start"]:
				hp_sum["n"][w] = int(hp_sum["n"].get(w, 0)) + 1
				hp_sum["start"][w] = float(hp_sum["start"].get(w, 0.0)) + float(result["hp_start"][w])
				hp_sum["pre"][w] = float(hp_sum["pre"].get(w, 0.0)) + float(result["hp_pre"][w])
				hp_sum["min"][w] = float(hp_sum["min"].get(w, 0.0)) + float(result["hp_min"].get(w, result["hp_start"][w]))
				if float(result["hp_start"][w]) < 0.5:
					hp_sum["low"][w] = int(hp_sum["low"].get(w, 0)) + 1
			for field in loot_total:
				loot_total[field] += int(result["loot"][field])
			for kind in result["loot"]["kinds"]:
				kinds_total[kind] = int(kinds_total.get(kind, 0)) + int(result["loot"]["kinds"][kind])
			if result["won"]:
				wins += 1
				clear_ticks += int(result["ticks"])
			if result["timeout"]:
				timeouts += 1
			waves_total += int(result["waves"])
			waves_min = mini(waves_min, int(result["waves"]))
			for w in 13:
				wave_taken[w] += result["wave_taken"][w]
			for m in result["members"]:
				dealt += m["dealt"] + m["skill_dealt"]
				taken += m["taken"]
				deaths += m["deaths"]
				ults += m["ults"]
				if true:
					var key := "%s in %s" % [m["class"], scenario["name"]]
					if not per_class.has(key):
						per_class[key] = {"dealt": 0.0, "taken": 0.0, "deaths": 0, "ults": 0, "attack": 0, "walk": 0, "alive": 0, "kills": 0, "n": 0, "gauge_full": 0, "skill_dealt": 0.0, "casts": 0, "casting": 0, "ult_dealt": 0.0, "ult_support": 0.0, "support": 0.0, "ult_lost": 0, "ult_gap_ticks": 0, "ult_gaps": 0, "ult_first": 0, "ult_firsts": 0, "race": "", "per_skill": {}, "hits": 0, "atk": 0.0, "in_hits": 0, "in_blocked": 0, "in_dmg": 0.0, "prevented": 0.0, "broken": 0, "oos": 0, "starved": 0, "skill_starved": 0}
					for field in ["hits", "atk", "dealt", "taken", "deaths", "ults", "attack", "walk", "alive", "kills", "gauge_full", "skill_dealt", "casts", "casting",
							"ult_dealt", "ult_support", "support", "ult_lost", "ult_gap_ticks", "ult_gaps", "ult_first", "ult_firsts",
							"in_hits", "in_blocked", "in_dmg", "prevented", "broken", "oos", "starved", "skill_starved"]:
						per_class[key][field] += m[field]
					per_class[key]["race"] = m["race"]
					for skill in m["per_skill"]:
						if not per_class[key]["per_skill"].has(skill):
							per_class[key]["per_skill"][skill] = {"dmg": 0.0, "casts": 0, "ticks": 0, "hits": 0}
						for field in ["dmg", "casts", "ticks", "hits"]:
							per_class[key]["per_skill"][skill][field] += m["per_skill"][skill][field]
					per_class[key]["n"] += 1
		print("%-19s | %3d%% | %5.1f / %2d    | %7s | %9.0f | %9.0f | %6.2f | %4.1f | %d" % [scenario["name"], 100 * wins / seeds, float(waves_total) / seeds, waves_min,
			("%.0f" % (clear_ticks / 60.0 / wins)) if wins > 0 else "-", dealt / seeds, taken / seeds, float(deaths) / seeds, float(ults) / seeds, timeouts])
		print("  loot per run: drops %.1f gold %.0f items %.2f (lost, bag full: %.2f) materials %.1f" % [float(loot_total["drops"]) / seeds, float(loot_total["gold"]) / seeds, float(loot_total["items"]) / seeds, float(loot_total["lost_items"]) / seeds, float(loot_total["materials"]) / seeds])
		var kind_names := kinds_total.keys()
		kind_names.sort()
		print("  dropped pieces (id@tier: per run): %s" % [", ".join(kind_names.map(func(k): return "%s %.2f" % [k, float(kinds_total[k]) / seeds]))])
		print("  taken per wave 1..12: %s" % [", ".join(range(1, 13).map(func(w): return "%.0f" % (wave_taken[w] / seeds)))])
		# Squad HP % per wave (runs that reached the wave): before the between-wave heal, at the start (after the heal),
		# the lowest reached during the wave, and the share of runs starting the wave under 50% HP.
		var hp_waves: Array = hp_sum["n"].keys()
		hp_waves.sort()
		var row := func(field: String) -> String:
			return " ".join(hp_waves.map(func(w): return "%3.0f" % (100.0 * float(hp_sum[field][w]) / int(hp_sum["n"][w]))))
		print("  HP%% wave           : %s" % [" ".join(hp_waves.map(func(w): return "w%-2d" % w))])
		print("  HP%% before heal    : %s" % [row.call("pre")])
		print("  HP%% at wave start  : %s" % [row.call("start")])
		print("  HP%% lowest in wave : %s" % [row.call("min")])
		print("  runs reaching wave : %s" % [" ".join(hp_waves.map(func(w): return "%3d" % int(hp_sum["n"][w])))])
		print("  start < 50%% HP     : %s" % [" ".join(hp_waves.map(func(w): return "%3d" % int(hp_sum["low"].get(w, 0))))])
		var mid := hp_waves.filter(func(w): return int(w) >= 2 and int(w) <= 8)
		var mid_sum := 0.0
		var mid_n := 0
		for w in mid:
			mid_sum += float(hp_sum["start"][w])
			mid_n += int(hp_sum["n"][w])
		print("  HP%% at start of waves 2-8, mean over runs: %.1f%%" % [100.0 * mid_sum / maxf(1.0, mid_n)])
		# One machine-readable line so split runs (first=N) can be merged: sums, not means.
		print("RAW|%s|wins=%d|seeds=%d|%s" % [scenario["name"], wins, seeds, "|".join(hp_waves.map(func(w): return "w%d:%d:%.4f:%.4f:%.4f:%d" % [w, int(hp_sum["n"][w]), float(hp_sum["pre"][w]), float(hp_sum["start"][w]), float(hp_sum["min"][w]), int(hp_sum["low"].get(w, 0))]))])
	print("")
	print("member (per run avg)              | weapon dmg | skill dmg | casts | dmg taken | kills | deaths | ults | gauge-full s | attacking% | walking% | casting%")
	for key in per_class:
		var c: Dictionary = per_class[key]
		var n := float(c["n"])
		var alive := maxf(1.0, float(c["alive"]))
		print("%-34s | %10.0f | %9.0f | %5.1f | %9.0f | %5.1f | %6.2f | %4.1f | %12.1f | %9.0f%% | %7.0f%% | %7.0f%%" % [key, c["dealt"] / n, c["skill_dealt"] / n, c["casts"] / n, c["taken"] / n, c["kills"] / n, c["deaths"] / n, c["ults"] / n, c["gauge_full"] / 60.0 / n, 100.0 * c["attack"] / alive, 100.0 * c["walk"] / alive, 100.0 * c["casting"] / alive])
	# Stamina (measurement only): refused moves (out_of_stamina events), share of alive time below the weapon's
	# light_1 cost, share of alive time with a skill off cooldown but not enough stamina for it.
	print("")
	print("stamina (per run avg)              | refused | starved% (no light) | skill short%")
	for key in per_class:
		var c: Dictionary = per_class[key]
		var alive := maxf(1.0, float(c["alive"]))
		print("%-34s | %7.1f | %18.1f%% | %11.1f%%" % [key, c["oos"] / float(c["n"]), 100.0 * c["starved"] / alive, 100.0 * c["skill_starved"] / alive])
		print("STAM|%s|%.1f|%.2f|%.2f" % [key, c["oos"] / float(c["n"]), 100.0 * c["starved"] / alive, 100.0 * c["skill_starved"] / alive])
	# Guard (measurement only): enemy weapon/projectile hits on each card, the share blocked, damage taken from
	# them, the damage the guard prevented (estimate) and guard breaks (not enough stamina for the blow).
	print("")
	print("guard (per run avg)                | hits in | blocked | blocked% | dmg taken (hits) | prevented | prevented% of raw | breaks")
	var g_tot := {"in_hits": 0.0, "in_blocked": 0.0, "in_dmg": 0.0, "prevented": 0.0, "broken": 0.0}
	for key in per_class:
		var c: Dictionary = per_class[key]
		var n := float(c["n"])
		for f in g_tot:
			g_tot[f] += float(c[f])
		print("%-34s | %7.1f | %7.1f | %7.1f%% | %16.0f | %9.0f | %16.1f%% | %5.2f" % [key, c["in_hits"] / n, c["in_blocked"] / n, 100.0 * c["in_blocked"] / maxf(1.0, float(c["in_hits"])), c["in_dmg"] / n, c["prevented"] / n, 100.0 * c["prevented"] / maxf(1.0, c["prevented"] + c["in_dmg"]), c["broken"] / n])
	print("GUARD|all|hits_in=%.0f|blocked=%.0f|dmg=%.0f|prevented=%.0f|broken=%.0f" % [g_tot["in_hits"], g_tot["in_blocked"], g_tot["in_dmg"], g_tot["prevented"], g_tot["broken"]])
	# Class skills per skill (class-skills.md 4.5): share of the class's damage, share of its skill damage (rule: none
	# above 60%), casts, enemies hit per cast and time spent in the clip (share of the card's alive time).
	print("")
	print("skill (per run avg)                               | casts | hits/cast | skill dmg | % of class dmg | % of class skill dmg | in clip %")
	for key in per_class:
		var c: Dictionary = per_class[key]
		var n := float(c["n"])
		var own: float = c["dealt"] + c["skill_dealt"]
		print("%-49s | %5s | %9s | %9.0f | %13.1f%% | %19s | %8.0f%%" % [key + " (all skills)", "%.1f" % (c["casts"] / n), "", c["skill_dealt"] / n, 100.0 * c["skill_dealt"] / maxf(1.0, own), "", 100.0 * c["casting"] / maxf(1.0, float(c["alive"]))])
		print("%-49s | ATK %.0f, weapon hits %.0f, %.0f per hit, %.0f per attacking second" % ["  (weapon)", c["atk"] / n, c["hits"] / n, c["dealt"] / maxf(1.0, float(c["hits"])), c["dealt"] / maxf(1.0, float(c["attack"]) / 60.0)])
		for skill in c["per_skill"]:
			var k: Dictionary = c["per_skill"][skill]
			print("%-49s | %5.1f | %9.2f | %9.0f | %13.1f%% | %18.1f%% | %8.1f%%" % ["  " + str(skill), k["casts"] / n, float(k["hits"]) / maxf(1.0, float(k["casts"])), k["dmg"] / n,
				100.0 * k["dmg"] / maxf(1.0, own), 100.0 * k["dmg"] / maxf(1.0, c["skill_dealt"]), 100.0 * k["ticks"] / maxf(1.0, float(c["alive"]))])
	# Race ultimates (GDD races section 8): per card, then the squad share of damage and of heal+shield.
	print("")
	print("ultimates (per run avg)            | race      | fired | first s | mean gap s | lost | ult dmg | ult dmg % | ult heal+shield | heal+shield % of own")
	var squad_dmg := 0.0
	var squad_ult_dmg := 0.0
	var squad_support := 0.0
	var squad_ult_support := 0.0
	for key in per_class:
		var c: Dictionary = per_class[key]
		var n := float(c["n"])
		var own_dmg: float = c["dealt"] + c["skill_dealt"]
		squad_dmg += own_dmg
		squad_ult_dmg += c["ult_dealt"]
		squad_support += c["support"]
		squad_ult_support += c["ult_support"]
		print("%-34s | %-9s | %5.2f | %7s | %10s | %4.2f | %7.0f | %8.1f%% | %15.0f | %18.1f%%" % [key, c["race"], c["ults"] / n,
			("%.1f" % (c["ult_first"] / 60.0 / c["ult_firsts"])) if c["ult_firsts"] > 0 else "-",
			("%.1f" % (c["ult_gap_ticks"] / 60.0 / c["ult_gaps"])) if c["ult_gaps"] > 0 else "-",
			c["ult_lost"] / n, c["ult_dealt"] / n, 100.0 * c["ult_dealt"] / maxf(1.0, own_dmg), c["ult_support"] / n, 100.0 * c["ult_support"] / maxf(1.0, c["support"])])
	print("ultimate share of all damage: %.1f%%   of all heal+shield: %.1f%%" % [100.0 * squad_ult_dmg / maxf(1.0, squad_dmg), 100.0 * squad_ult_support / maxf(1.0, squad_support)])
	quit(0)


## only=solo,squad picks by kind; only=greatsword picks every scenario whose name contains it.
func _picked(only: String, scenario: Dictionary) -> bool:
	for part in only.split(","):
		if part == str(scenario["kind"]) or str(scenario["name"]).contains(part.replace(":", " ")):  # "solo:magic" = only "solo magic"
			return true
	return false


func _trip(seed: int):
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var profile = Profile.new_player(rules, camp, r)
	for card in Deck.classes():  # tutorial.md 2: new cards are raceless; the tutorial gives S&S/GS/Bow Human/Viking/Elf
		Deck.set_race(profile.card_deck, card, Deck.starter_race(card))
	for arg in OS.get_cmdline_user_args():  # "race:magic=human": a card's race for this measurement only
		if arg.begins_with("race:") and arg.contains("="):
			Deck.set_race(profile.card_deck, arg.substr(5, arg.find("=") - 5), arg.substr(arg.find("=") + 1))
	profile.unlocks["magic_runeborn"] = true
	if gear_tier >= 0 or card_level > 1:
		_progress(profile, r)
	return Run.start(profile, camp)


## gear= / level= (measurement only): a progressed account. Gear: one tier-`gear_tier` piece in every slot the
## card may use (random substats from the seed; the class's own weapon family). Level: `card_level` reached
## and its points spent greedily: class nodes in data order, then race, then the combo (first legal pick wins).
func _progress(profile, r: RandomNumberGenerator) -> void:
	const Items := preload("res://logic/item_system.gd")
	const Tree := preload("res://logic/skill_tree.gd")
	const TreeData := preload("res://logic/skill_tree_data.gd")
	const Progress := preload("res://logic/card_progress.gd")
	var tree_data = TreeData.load_default()
	for card in Deck.classes():
		var worn = profile.loadout_of(card)
		if gear_tier >= 0 and worn != null:
			for slot in rules.slots:
				if not rules.slot_open_for(str(slot["id"]), card):
					continue
				for index in int(slot["count"]):
					var family := str(Profile.weapon_families(card)[0]) if slot["id"] == "weapon" else ""
					var looks := family + "_01" if slot["id"] == "weapon" else ""
					var item = Items.create_item(rules, "sim-%s-%s-%d" % [card, slot["id"], index], str(slot["id"]), gear_tier, r, family, looks)
					if item != null:
						worn.equip(item, index)
		if card_level > 1 and profile.card_deck.get("cards", {}).has(card):
			profile.card_deck["cards"][card][Progress.PROGRESS] = {"level": card_level, "xp": 0}
			var race := Deck.race_of(profile.card_deck, card)
			var order: Array = tree_data.class_nodes(card) + tree_data.race_nodes(race)
			var combo: Dictionary = tree_data.combo_node(race, card)
			if not combo.is_empty():
				order.append(combo)
			for _pass in 3:  # later tiers open once earlier ones are paid for
				for n in order:
					Tree.learn(profile.card_deck, card, str(n["id"]), tree_data)


## One fight of the wave journey with these classes (1 = solo). Returns totals and one entry per member.
func play(classes: Array, seed: int) -> Dictionary:
	var data = JourneyData.load_by_id(journey_id, combat.enemies.keys())
	for arg in OS.get_cmdline_user_args():  # "heal=0.6": wave_heal_fraction, "stage9=1.2": a stage's power (measurement only)
		if arg.begins_with("heal="):
			data.wave_heal_fraction = float(arg.substr(5))
		elif arg.begins_with("stage") and arg.contains("="):
			data.stages[int(arg.substr(5, arg.find("=") - 5)) - 1]["power"] = float(arg.substr(arg.find("=") + 1))
		elif arg.begins_with("count="):
			data.wave_count_scale = float(arg.substr(6))
		elif arg.begins_with("bosshp="):
			data.boss["hp_mult"] = float(arg.substr(7))
	for size in power_override:
		if size >= 1 and size <= data.wave_power_by_squad.size():
			data.wave_power_by_squad[size - 1] = float(power_override[size])
	var trips := {}
	var distinct := {}
	for class_id in classes:
		distinct[class_id] = true
	if distinct.size() == classes.size():
		# The real game (plan step 5): one account, one shared bag, each card fights in its own starter gear and build.
		var members: Array = preload("res://logic/squad_member.gd").make_squad(_trip(seed), classes)
		for i in members.size():
			trips[i + 1] = members[i]
	else:
		for i in classes.size():  # "3x class": a measurement only, separate accounts
			trips[i + 1] = _trip(seed + i)
	var journey = Party.start_party(data, trips, rules, loot, combat.weapon_ids, seed) if classes.size() > 1 else Journey.start(data, trips[1], rules, loot, combat.weapon_ids, seed)
	while journey.state != journey.IN_STAGE and not journey.is_over():
		if journey.state == journey.CHOOSING:
			journey.choose(0)
		elif journey.state == journey.AT_NODE:
			journey.leave_node()
	var map = Map.load_by_id(str(journey.current.map))
	var world := World.new()
	world.half_width = map.half_width
	world.half_depth = map.half_depth
	for solid in map.solids:
		world.add_solid(solid.box)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var sim := Sim.new(world, combat, rng)
	var ids: Array = range(1, classes.size() + 1)
	if classes.size() == 1:
		sim.add_player(1, map.spawn)
		sim.attach_run(1, journey.run, journey.item_rules, journey.loot_data)
	journey.populate(sim, map, 1, 100)
	if no_skills:
		for id in ids:
			sim.fighters[id].skill_state = {}  # class skills v2 off for this card (logic/class_skills/engine.gd)
			if sim.skill_system != null:
				sim.skill_system.attach(id, {})  # an invalid build detaches an old skill-build caster too
	var members := {}
	var memories := {}
	for i in ids.size():
		var id: int = ids[i]
		sim.set_class_style(id, str(Deck.class_data(str(classes[i])).get("weapon", "")))
		if no_skills:
			sim.fighters[id].skill_state = {}  # (set_class_style gives a skill-less fighter its class skills)
		memories[id] = Pilot.new_memory(id * 7919 + 1 + seed)
		members[id] = {"class": classes[i], "dealt": 0.0, "taken": 0.0, "deaths": 0, "ults": 0, "attack": 0, "walk": 0, "alive": 0, "kills": 0, "gauge_full": 0, "skill_dealt": 0.0, "casts": 0, "casting": 0, "ult_dealt": 0.0, "ult_support": 0.0, "support": 0.0, "ult_lost": 0, "ult_gap_ticks": 0, "ult_gaps": 0, "ult_first": 0, "ult_firsts": 0, "race": "", "per_skill": {}, "hits": 0, "atk": 0.0, "in_hits": 0, "in_blocked": 0, "in_dmg": 0.0, "prevented": 0.0, "broken": 0, "oos": 0, "starved": 0, "skill_starved": 0}
		members[id]["atk"] = sim.fighters[id].stat("ATK")
		for skill in sim.fighters[id].skill_state.get("skills", []):
			members[id]["per_skill"][str(skill)] = {"dmg": 0.0, "casts": 0, "ticks": 0, "hits": 0}
		members[id]["race"] = str(sim.fighters[id].race_state.get("race", ""))
	var waves := 1
	var loot_seen := {"drops": 0, "gold": 0, "items": 0, "materials": 0, "lost_items": 0, "kinds": {}}  ## "loot" events: what reached a run bag
	var wave_taken := []
	wave_taken.resize(13)
	wave_taken.fill(0.0)
	# "hp" (measurement only): squad HP fraction (sum of HP / sum of max HP, a fallen card counts 0) at each wave
	# start, before and after the between-wave heal, and the lowest fraction reached during each wave.
	var hp_start := {}
	var hp_pre := {}
	var hp_min := {}
	var hp_last := _squad_hp_fraction(sim, ids)
	hp_start[1] = hp_last
	hp_pre[1] = hp_last
	hp_min[1] = hp_last
	var tick := 0
	var gauge_max := float(combat.rules["ultimate_gauge_max"])
	while tick < MAX_TICKS and sim.living_enemy_count() + sim.pending_wave_count() > 0:
		var any_alive := false
		for id in ids:
			if sim.fighters[id].is_alive() and not sim.fighters[id].incapacitated:
				any_alive = true
			sim.set_input(id, SimInput.decode(Pilot.decide(sim, combat, id, memories[id], tick, REACTION).encode()))
		if not any_alive:
			break
		sim.tick()
		tick += 1
		for event in sim.events:
			match str(event["type"]):
				"hit", "blocked":
					var a := int(event.get("attacker", -1))
					var t := int(event.get("target", -1))
					if members.has(a) and not members.has(t):
						members[a]["dealt"] += float(event["damage"])
						members[a]["hits"] += 1
					if members.has(t) and not members.has(a):
						members[t]["taken"] += float(event["damage"])
						wave_taken[waves] += float(event["damage"])
						# guard measurement: incoming enemy weapon/projectile hits, blocked share, damage the guard
						# prevented (estimated from the blocked damage: raw = blocked / (1 - reduction); the min_damage floor is ignored)
						members[t]["in_hits"] += 1
						members[t]["in_dmg"] += float(event["damage"])
						if str(event["type"]) == "blocked":
							members[t]["in_blocked"] += 1
							var keep := maxf(0.01, 1.0 - float(combat.rules["guard_damage_reduction"]))
							members[t]["prevented"] += float(event["damage"]) / keep - float(event["damage"])
				"out_of_stamina":
					if members.has(int(event.get("player", -1))):
						members[int(event["player"])]["oos"] += 1
				"guard_broken":
					if members.has(int(event.get("target", -1))):
						members[int(event["target"])]["broken"] += 1
				"skill_hit", "skill_dot":
					var a := int(event.get("attacker", -1))
					var t := int(event.get("target", -1))
					if members.has(a) and not members.has(t):
						members[a]["skill_dealt"] += float(event["damage"])
						var per: Dictionary = members[a]["per_skill"]
						var skill_id := str(event.get("skill", "?"))
						if not per.has(skill_id):
							per[skill_id] = {"dmg": 0.0, "casts": 0, "ticks": 0, "hits": 0}
						per[skill_id]["dmg"] += float(event["damage"])
						per[skill_id]["hits"] += 1
					if members.has(t) and not members.has(a):
						members[t]["taken"] += float(event["damage"])
						wave_taken[waves] += float(event["damage"])
				"race_burst_hit":  # race rune bursts (Runic Edge) and ultimates: dealt damage, counted with the weapon hits
					var a := int(event.get("attacker", -1))
					if members.has(a) and not members.has(int(event.get("target", -1))):
						members[a]["dealt"] += float(event["damage"])
						if bool(event.get("ultimate", false)):
							members[a]["ult_dealt"] += float(event["damage"])
				"race_heal", "race_shield":  # heal + shield given to the squad (ultimate part measured apart)
					var a := int(event.get("player", -1))
					if members.has(a):
						members[a]["support"] += float(event["amount"])
						if bool(event.get("ultimate", false)):
							members[a]["ult_support"] += float(event["amount"])
				"race_ult_lost":
					if members.has(int(event.get("player", -1))):
						members[int(event["player"])]["ult_lost"] += 1
				"skill_cast":
					if members.has(int(event.get("player", -1))):
						members[int(event["player"])]["casts"] += 1
						var per: Dictionary = members[int(event["player"])]["per_skill"]
						if per.has(str(event.get("skill", ""))):
							per[str(event["skill"])]["casts"] += 1
				"dot":
					var t := int(event.get("target", -1))
					if members.has(t):
						members[t]["taken"] += float(event["damage"])
						wave_taken[waves] += float(event["damage"])
				"killed":
					var t := int(event.get("target", -1))
					if members.has(t):
						members[t]["deaths"] += 1
					elif members.has(int(event.get("by", -1))):
						members[int(event["by"])]["kills"] += 1
				"downed":  # a squad member falls (co-op): counted as a death here, revived or not
					if members.has(int(event.get("player", -1))):
						members[int(event["player"])]["deaths"] += 1
				"attack_started":
					var p := int(event.get("player", -1))
					if members.has(p) and str(event.get("move", "")).ends_with("ultimate"):
						members[p]["ults"] += 1
						if members[p].has("last_ult"):
							members[p]["ult_gap_ticks"] += tick - int(members[p]["last_ult"])
							members[p]["ult_gaps"] += 1
						else:
							members[p]["ult_first"] += tick
							members[p]["ult_firsts"] += 1
						members[p]["last_ult"] = tick
				"wave_arrived":
					waves = int(event["wave"])
					hp_pre[waves] = hp_last
					hp_start[waves] = _squad_hp_fraction(sim, ids)
					hp_min[waves] = hp_start[waves]
				"loot":
					loot_seen["drops"] += 1
					loot_seen["gold"] += int(event["gold"])
					loot_seen["items"] += event["items"].size()
					for it in event["items"]:  # which pieces dropped: item_id@tier (gear-level cap check)
						var kind := "%s@%d" % [it["item_id"], int(it["tier"])]
						loot_seen["kinds"][kind] = int(loot_seen["kinds"].get(kind, 0)) + 1
					loot_seen["lost_items"] += int(event["lost_items"])  # dropped but the run bag was full
					for material in event["materials"]:
						loot_seen["materials"] += int(event["materials"][material])
		hp_last = _squad_hp_fraction(sim, ids)
		hp_min[waves] = minf(float(hp_min.get(waves, hp_last)), hp_last)
		for id in ids:
			var f: Fighter = sim.fighters[id]
			if not f.is_alive() or f.incapacitated:
				continue
			members[id]["alive"] += 1
			if f.skill_view.get("casting", false) or f.skill_view.get("moving", false):
				members[id]["casting"] += 1
				var now_skill := str(f.skill_state.get("cast", {}).get("skill", ""))
				if members[id]["per_skill"].has(now_skill):
					members[id]["per_skill"][now_skill]["ticks"] += 1
			elif f.state == Fighter.State.ATTACK:
				members[id]["attack"] += 1
			elif sim.bodies[id].velocity.length() > 0.5:
				members[id]["walk"] += 1
			if f.gauge >= gauge_max:
				members[id]["gauge_full"] += 1
			# stamina starvation (measurement only): too little stamina for the weapon's first light attack,
			# or for the cheapest class skill that is off cooldown
			var light_cost := float(combat.moves.get(str(f.style) + "_light_1", {}).get("energy_cost", 0.0))
			if f.energy < light_cost:
				members[id]["starved"] += 1
			for skill in f.skill_state.get("skills", []):
				var sd: Dictionary = preload("res://logic/class_skills/skill_data.gd").load_default().skill(str(skill))
				if int(f.skill_state.get("cd", {}).get(skill, 0)) <= sim.tick_count and f.energy < float(sd.get("stamina", 0.0)):
					members[id]["skill_starved"] += 1
					break
	var alive := 0
	for id in ids:
		if sim.fighters[id].is_alive() and not sim.fighters[id].incapacitated:
			alive += 1
	var cleared: bool = sim.living_enemy_count() + sim.pending_wave_count() == 0 and alive > 0
	return {"won": cleared, "ticks": tick, "timeout": tick >= MAX_TICKS, "waves": 12 if cleared else waves, "members": members.values(), "wave_taken": wave_taken, "loot": loot_seen,
		"hp_start": hp_start, "hp_pre": hp_pre, "hp_min": hp_min}


## Squad HP fraction: sum of current HP over sum of max HP (a fallen or downed card counts 0 HP).
func _squad_hp_fraction(sim, ids: Array) -> float:
	var hp := 0.0
	var full := 0.0
	for id in ids:
		var f: Fighter = sim.fighters[id]
		full += f.max_hp()
		if f.is_alive() and not f.incapacitated:
			hp += maxf(0.0, f.hp)
	return hp / maxf(1.0, full)
