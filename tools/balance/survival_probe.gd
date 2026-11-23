extends SceneTree
## Squad survival diagnosis (Boss 2026-11-23: "our AI stands there while the boss hits it to death"). A BEHAVIOUR probe,
## not a win-rate study: fixed seeds, the real rules, logic/auto_pilot.gd driving the squad, against the boss wave of
## a journey. For every squad death it logs the last 5 seconds (which boss move hit, telegraphed or not, did the pilot
## decide to react, guard/dodge, stamina, distance, HP, was the card the boss's target, allies alive, skills/ultimate
## ready but unused) and classifies the main cause; per boss it counts the telegraphed boss hits that threatened a card
## (it stood in the warning marker) and how many it avoided, and the squad's survival time in the boss wave.
##   godot --headless --path . --script res://tools/balance/survival_probe.gd [-- seeds=8 bosses=goblin,orc,mummy full=1 verbose=1]
## Default: the boss wave only (the queue is cut to the last wave, the squad starts it at full HP) so the numbers are
## about the boss fight; full=1 plays all 9 waves (deaths before the boss are listed too).
## Tool only: nothing in the game loads this file.

const Pilot := preload("res://logic/auto_pilot.gd")
const Party := preload("res://logic/coop_journey.gd")
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
const Combat := preload("res://logic/combat.gd")
const Profile := preload("res://logic/profile.gd")
const Run := preload("res://logic/run.gd")
const ClassSkills := preload("res://logic/class_skills/engine.gd")
const SkillData := preload("res://logic/class_skills/skill_data.gd")
const RaceUltimates := preload("res://logic/race_ultimates.gd")

const WINDOW := 300  ## the last 5 s before a death
## The reference squads per zone (the journeys' own _tuning notes): goblin level 1 starter gear, mummy level 15 tier 1,
## orc level 20 tier 1.
const ZONES := {
	"goblin": {"journey": "goblin_waves", "level": 1, "gear": -1},
	"mummy": {"journey": "mummy_waves", "level": 15, "gear": 1},
	"orc": {"journey": "orc_waves", "level": 20, "gear": 1},
}
const SQUADS := [["sword_shield", "greatsword", "longbow"], ["sword_shield", "longbow", "magic"]]
const MAX_TICKS := 60 * 240

var rules
var camp
var loot
var combat
var verbose := false
var landed_why := {}  ## telegraphed boss hits that landed: the pilot's decision + the card's state the tick before
var full := false


func _init() -> void:
	rules = Rules.load_default()
	camp = Camp.load_default(rules.tiers.size())
	loot = Loot.load_default(camp.materials.keys(), rules.tiers.size())
	combat = CombatLoader.load_default()
	var seeds := 8
	var zones: Array = ["goblin", "orc", "mummy"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("seeds="):
			seeds = int(arg.substr(6))
		elif arg.begins_with("bosses="):
			zones = Array(arg.substr(7).split(","))
		elif arg == "verbose=1":
			verbose = true
		elif arg == "full=1":
			full = true
	var causes := {}
	var flags := {}
	print("SURVIVAL PROBE  seeds=%d  mode=%s" % [seeds, "full journey" if full else "boss wave only, full HP"])
	for zone in zones:
		var z: Dictionary = ZONES[zone]
		var agg := {"threat": 0, "avoided": 0, "blocked": 0, "hit": 0, "alive_s": 0.0, "fighters": 0, "deaths": 0, "runs": 0, "wins": 0, "wave_s": 0.0, "by_move": {}}
		for squad in SQUADS:
			for s in seeds:
				var r := play(z, squad, 3000 + s * 31)
				agg["runs"] += 1
				agg["wins"] += 1 if r["won"] else 0
				agg["wave_s"] += float(r["wave_ticks"]) / 60.0
				for k in ["threat", "avoided", "blocked", "hit", "deaths", "fighters"]:
					agg[k] += r[k]
				agg["alive_s"] += r["alive_s"]
				for m in r["by_move"]:
					var row: Dictionary = agg["by_move"].get(m, {"threat": 0, "avoided": 0, "blocked": 0, "hit": 0})
					for k in row:
						row[k] += r["by_move"][m][k]
					agg["by_move"][m] = row
				for d in r["death_log"]:
					causes[d["cause"]] = int(causes.get(d["cause"], 0)) + 1
					for f in d["flags"]:
						flags[f] = int(flags.get(f, 0)) + 1
					if verbose:
						print("  DEATH %s %s seed %d: %s" % [zone, d["class"], s, d["text"]])
		print("BOSS %-7s runs %d  boss wave won %d  deaths %d (%.2f/run)  mean card alive in boss wave %.1f s  boss wave length %.1f s" % [zone, agg["runs"], agg["wins"], agg["deaths"], float(agg["deaths"]) / agg["runs"],
			agg["alive_s"] / maxf(1.0, agg["fighters"]), agg["wave_s"] / agg["runs"]])
		print("  telegraphed boss hits threatening a card: %d  avoided %d (%.0f%%)  guarded %d  landed %d" % [agg["threat"], agg["avoided"], 100.0 * agg["avoided"] / maxf(1.0, agg["threat"]), agg["blocked"], agg["hit"]])
		for m in agg["by_move"]:
			var row: Dictionary = agg["by_move"][m]
			print("    %-24s threat %4d avoided %4d guarded %4d landed %4d" % [m, row["threat"], row["avoided"], row["blocked"], row["hit"]])
		print("PROBE|%s|threat=%d|avoided=%d|guarded=%d|landed=%d|deaths=%d|alive_s=%.2f|wins=%d|runs=%d" % [zone, agg["threat"], agg["avoided"], agg["blocked"], agg["hit"], agg["deaths"], agg["alive_s"] / maxf(1.0, agg["fighters"]), agg["wins"], agg["runs"]])
	print("LANDED TELEGRAPHED BOSS HITS, why (all bosses):")
	for w in landed_why:
		print("  %-70s %d" % [w, landed_why[w]])
	print("DEATH CAUSES (main cause per death, all bosses):")
	for c in causes:
		print("  %-44s %d" % [c, causes[c]])
	print("DEATH FLAGS (any number per death):")
	for f in flags:
		print("  %-44s %d" % [f, flags[f]])
	quit(0)


func _trip(seed: int, z: Dictionary):
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var profile = Profile.new_player(rules, camp, r)
	for card in Deck.classes():
		Deck.set_race(profile.card_deck, card, Deck.starter_race(card))
	profile.unlocks["magic_runeborn"] = true
	_progress(profile, r, int(z["gear"]), int(z["level"]))
	return Run.start(profile, camp)


## The same progressed account as tools/balance/class_sim.gd gear= / level=.
func _progress(profile, r: RandomNumberGenerator, gear_tier: int, card_level: int) -> void:
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
			for _pass in 3:
				for n in order:
					Tree.learn(profile.card_deck, card, str(n["id"]), tree_data)


static func inside_shape(shape: Dictionary, point: Vector3, margin: float = 0.3) -> bool:
	return Pilot.in_telegraph(shape, point, margin)


func play(z: Dictionary, classes: Array, seed: int) -> Dictionary:
	var data = JourneyData.load_by_id(str(z["journey"]), combat.enemies.keys())
	var trips := {}
	var members: Array = preload("res://logic/squad_member.gd").make_squad(_trip(seed, z), classes)
	for i in members.size():
		trips[i + 1] = members[i]
	var journey = Party.start_party(data, trips, rules, loot, combat.weapon_ids, seed)
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
	journey.populate(sim, map, 1, 100)
	if not full:  # the boss wave only: clear the field, keep the last queued wave (it arrives on the first tick)
		for e in sim.fighters.keys():
			if sim.fighters[e].team == "enemy":
				sim.remove_player(e)
		sim._waves = [sim._waves.back()]
	var memories := {}
	var mem := {}
	for i in ids.size():
		var id: int = ids[i]
		sim.set_class_style(id, str(Deck.class_data(str(classes[i])).get("weapon", "")))
		memories[id] = Pilot.new_memory(id * 7919 + 1 + seed)
		mem[id] = {"class": classes[i], "samples": [], "damage": []}
	var bosses: Array = []
	var boss_wave_tick := -1
	var inst := {}  ## boss id -> the current telegraphed move instance
	var area_inst := {}  ## area id -> instance
	var instances: Array = []
	var death_log: Array = []
	var alive_ticks := {}
	var tick := 0
	var end_tick := -1
	while tick < MAX_TICKS and sim.living_enemy_count() + sim.pending_wave_count() > 0:
		var any_alive := false
		for id in ids:
			if sim.fighters[id].is_alive() and not sim.fighters[id].incapacitated:
				any_alive = true
			sim.set_input(id, SimInput.decode(Pilot.decide(sim, combat, id, memories[id], tick).encode()))
		if not any_alive and ids.all(func(i): return not sim.fighters[i].is_alive()):
			break
		sim.tick()
		tick += 1
		for event in sim.events:
			var kind := str(event["type"])
			if kind == "wave_arrived":
				for e in event["enemies"]:
					if Pilot.is_boss(sim.fighters[int(e)]):
						bosses.append(int(e))
						boss_wave_tick = tick
			elif kind == "attack_started" and bosses.has(int(event.get("player", -1))):
				var mv: Dictionary = combat.moves.get(str(event["move"]), {})
				if bool(mv.get("telegraph", false)):
					var i := {"boss": int(event["player"]), "move": str(event["move"]), "tick": tick, "threat": {}, "hit": {}, "blocked": {}}
					inst[int(event["player"])] = i
					instances.append(i)
			elif kind == "area_placed" and inst.has(int(event.get("player", -1))):
				var i: Dictionary = inst[int(event["player"])]
				area_inst[int(event["area"])] = i
				i["areas"] = i.get("areas", []) + [int(event["area"])]
				for id in ids:
					if sim.fighters[id].is_alive() and Pilot._flat(sim.bodies[id].position - Vector3(event["pos"])).length() <= float(event["radius"]) + 0.3:
						i["threat"][id] = true
			elif (kind == "hit" or kind == "blocked") and mem.has(int(event.get("target", -1))):
				var t := int(event["target"])
				var a := int(event.get("attacker", -1))
				var mv_id := str(event.get("move", ""))
				var tele := bool(combat.moves.get(mv_id, {}).get("telegraph", false)) and bosses.has(a)
				var react = null
				var dec: Dictionary = memories[t]["decided"]
				if dec.has(a) and dec[a][0] == mv_id:
					react = dec[a][1]
				if dec.has("t%d" % a) and dec["t%d" % a][0] == mv_id:  # the survival pilot's telegraph decision (auto_pilot._threats key)
					react = dec["t%d" % a][1]
				if not str(event.get("area", "")).is_empty() and inst.has(a):
					for area_id in inst[a].get("areas", []):
						if dec.has("area%d" % area_id):
							react = dec["area%d" % area_id][1]
				if tele and inst.has(a) and inst[a]["move"] == mv_id:
					inst[a]["blocked" if kind == "blocked" else "hit"][t] = true
					inst[a]["threat"][t] = true
					if kind == "hit":  # why a telegraphed boss hit landed: the pilot's decision and what the card was doing the tick before
						var before: Dictionary = mem[t]["samples"].back() if not mem[t]["samples"].is_empty() else {}
						var why := "no decision (out of reaction reach / not seen)" if react == null else ("decided to ignore" if react == false else "decided to react")
						why += " | was " + str(before.get("what", "?"))
						landed_why[why] = int(landed_why.get(why, 0)) + 1
				mem[t]["damage"].append({"t": tick, "move": mv_id, "from": sim.fighters[a].enemy_type if sim.fighters.has(a) else "?", "boss": bosses.has(a), "tele": tele,
					"dmg": float(event["damage"]), "blocked": kind == "blocked", "state": Fighter.State.keys()[sim.fighters[t].state], "react": react,
					"area": not str(event.get("area", "")).is_empty(), "energy": sim.fighters[t].energy})
			elif kind == "dot" and mem.has(int(event.get("target", -1))):
				mem[int(event["target"])]["damage"].append({"t": tick, "move": "dot:" + str(event.get("effect", "")), "from": "dot", "boss": false, "tele": false, "dmg": float(event["damage"]), "blocked": false, "state": "", "react": null, "area": false, "energy": 0.0})
			elif (kind == "downed" or kind == "killed") and mem.has(int(event.get("player", event.get("target", -1)))):
				var who := int(event.get("player", event.get("target", -1)))
				if kind == "killed" and sim.fighters[who].state == Fighter.State.DOWNED:
					continue
				death_log.append(_death(sim, who, mem[who], tick, bosses, ids, boss_wave_tick))
		# telegraph threat: a living card inside a boss's warning marker
		for b in bosses:
			if sim.fighters.has(b) and sim.fighters[b].is_alive() and Combat.is_telegraphing(sim.fighters[b], combat) and inst.has(b):
				var shape := Combat.telegraph_shape(b, sim.fighters, sim.bodies, combat)
				for id in ids:
					if sim.fighters[id].is_alive() and inside_shape(shape, sim.bodies[id].position):
						inst[b]["threat"][id] = true
		# per-tick samples for the death window
		for id in ids:
			var f: Fighter = sim.fighters[id]
			if boss_wave_tick >= 0 and f.is_alive():
				alive_ticks[id] = int(alive_ticks.get(id, 0)) + 1
			var nb := -1
			var nd := INF
			for b in bosses:
				if sim.fighters.has(b) and sim.fighters[b].is_alive():
					var d: float = Pilot._flat(sim.bodies[b].position - sim.bodies[id].position).length()
					if d < nd:
						nd = d
						nb = b
			var targeted := false
			if nb >= 0:
				targeted = sim._ai[nb].pick_target(sim.fighters[nb], sim.bodies[nb], sim.bodies, sim.fighters) == id
			var ready_skills := 0
			for sk in f.skill_state.get("skills", []):
				if ClassSkills.cooldown_left(sim, f, str(sk)) <= 0.0 and f.energy >= float(SkillData.load_default().skill(str(sk)).get("stamina", 0.0)):
					ready_skills += 1
			var allies := ids.filter(func(o): return o != id and sim.fighters[o].is_alive()).size()
			var samples: Array = mem[id]["samples"]
			samples.append({"t": tick, "hp": f.hp / maxf(1.0, f.max_hp()), "en": f.energy, "state": f.state, "dist": nd, "targeted": targeted, "skills": ready_skills,
				"ult": RaceUltimates.ready(sim, id), "allies": allies,
				"what": "STUNNED" if f.incapacitated else ("CASTING SKILL" if ClassSkills.busy(f) else ("ROOTED" if f.rooted else str(Fighter.State.keys()[f.state])))})
			if samples.size() > WINDOW:
				samples.pop_front()
		var dmg_keep: int = tick - WINDOW
		for id in ids:
			mem[id]["damage"] = mem[id]["damage"].filter(func(d): return int(d["t"]) > dmg_keep)
		if boss_wave_tick >= 0 and end_tick < 0 and bosses.all(func(b): return not sim.fighters.has(b) or not sim.fighters[b].is_alive()):
			end_tick = tick
	if end_tick < 0:
		end_tick = tick
	var out := {"won": sim.living_enemy_count() + sim.pending_wave_count() == 0, "threat": 0, "avoided": 0, "blocked": 0, "hit": 0, "by_move": {}, "death_log": death_log,
		"deaths": death_log.filter(func(d): return d["boss_wave"]).size(), "fighters": ids.size(), "alive_s": 0.0, "wave_ticks": maxi(0, end_tick - boss_wave_tick)}
	for id in ids:
		out["alive_s"] += float(alive_ticks.get(id, 0)) / 60.0
	for i in instances:
		var row: Dictionary = out["by_move"].get(i["move"], {"threat": 0, "avoided": 0, "blocked": 0, "hit": 0})
		for id in i["threat"]:
			row["threat"] += 1
			if i["hit"].has(id):
				row["hit"] += 1
			elif i["blocked"].has(id):
				row["blocked"] += 1
			else:
				row["avoided"] += 1
		out["by_move"][i["move"]] = row
	for m in out["by_move"]:
		for k in ["threat", "avoided", "blocked", "hit"]:
			out[k] += out["by_move"][m][k]
	return out


## One death: the last WINDOW ticks summarised and the main cause.
func _death(sim, id: int, m: Dictionary, tick: int, bosses: Array, ids: Array, boss_wave_tick: int) -> Dictionary:
	var dmg: Array = m["damage"]
	var total := 0.0
	var by := {"boss_tele": 0.0, "boss_plain": 0.0, "adds": 0.0, "dot": 0.0}
	var tele_no_react := 0.0
	var tele_react_hit := 0.0
	var in_attack := 0.0
	var moves := {}
	for d in dmg:
		total += d["dmg"]
		var k := "dot" if d["from"] == "dot" else ("boss_tele" if d["tele"] else ("boss_plain" if d["boss"] else "adds"))
		by[k] += d["dmg"]
		moves[d["move"]] = float(moves.get(d["move"], 0.0)) + d["dmg"]
		if d["tele"]:
			if d["react"] == true:
				tele_react_hit += d["dmg"]
			else:
				tele_no_react += d["dmg"]
		if d["state"] == "ATTACK" and d["boss"]:
			in_attack += d["dmg"]
	var samples: Array = m["samples"]
	var guard := 0
	var dodge := 0
	var targeted := 0
	var low_en := 0
	var skills_ready := 0
	var ult_ready := 0
	var near := 0
	var min_en := INF
	for s in samples:
		guard += 1 if s["state"] == Fighter.State.GUARD else 0
		dodge += 1 if s["state"] == Fighter.State.DODGE else 0
		targeted += 1 if s["targeted"] else 0
		low_en += 1 if s["en"] < float(combat.rules["dodge_energy"]) else 0
		skills_ready += 1 if s["skills"] > 0 else 0
		ult_ready += 1 if s["ult"] else 0
		near += 1 if s["dist"] < 3.0 else 0
		min_en = minf(min_en, s["en"])
	var n := maxf(1.0, samples.size())
	var last: Dictionary = samples.back() if not samples.is_empty() else {}
	var cause := "?"
	var top := ""
	var top_d := -1.0
	for k in by:
		if by[k] > top_d:
			top_d = by[k]
			top = k
	match top:
		"boss_tele":
			cause = "telegraphed boss move, pilot chose not to react" if tele_no_react >= tele_react_hit else "telegraphed boss move, reacted but still hit"
		"boss_plain":
			cause = "untelegraphed boss attacks while trading blows" if in_attack >= by["boss_plain"] * 0.5 else "untelegraphed boss attacks (not swinging)"
		"adds":
			cause = "adds (non-boss monsters)"
		"dot":
			cause = "damage over time (bleed/burn)"
	var flags: Array = []
	if targeted > n * 0.5:
		flags.append("was the boss's target")
	if ["longbow", "magic"].has(m["class"]) and near > n * 0.3:
		flags.append("back-line within 3 m of the boss")
	if low_en > n * 0.25:
		flags.append("stamina under a dodge for >25% of the window")
	if guard + dodge == 0:
		flags.append("never guarded or dodged in the last 5 s")
	if skills_ready > n * 0.5:
		flags.append("a class skill ready >50% of the window")
	if ult_ready > n * 0.3:
		flags.append("ultimate ready >30% of the window")
	if last.get("allies", 2) == 0:
		flags.append("died last (no ally alive)")
	if tele_no_react > 0.0:
		flags.append("took a telegraphed hit it decided to ignore")
	var parts: Array = []
	for mv in moves:
		parts.append("%s %.0f" % [mv, moves[mv]])
	var text := "%s | dmg 5s %.0f (tele %.0f plain %.0f adds %.0f dot %.0f; no-react tele %.0f) | guard %d dodge %d ticks | min stamina %.0f | targeted %.0f%% | <3m %.0f%% | skills ready %.0f%% ult %.0f%% | %s" % [
		cause, total, by["boss_tele"], by["boss_plain"], by["adds"], by["dot"], tele_no_react, guard, dodge, min_en, 100.0 * targeted / n, 100.0 * near / n, 100.0 * skills_ready / n, 100.0 * ult_ready / n, ", ".join(parts)]
	return {"class": m["class"], "cause": cause, "flags": flags, "text": text, "boss_wave": boss_wave_tick >= 0}
