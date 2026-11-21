extends RefCounted
## Boss option (Boss 2026-11-21; logic/boss_procs.gd, data/items/boss_options.json): every boss-drop piece is boss gold and
## has one status-on-hit proc. Checks: the data (one option per boss piece, chance band, icd > duration, control only on a
## weapon and short, distinct per boss, the themes), the proc rules (chance x RES layers, CTRL_RES 100 bosses immune to
## control, internal cooldown, own RNG streams: the sim stream is untouched, a seed repeats), the gear path (worn pieces ->
## Fighter.boss_procs, broken-down / duplicates), checkpoints, a real fight, and the gold UI tokens / texts.

const F := preload("res://tests/online_fixture.gd")
const BossProcs := preload("res://logic/boss_procs.gd")
const Effects := preload("res://logic/effects.gd")
const Fighter := preload("res://logic/fighter.gd")
const GameSim := preload("res://logic/game_sim.gd")
const SimWorld := preload("res://logic/sim_world.gd")
const SimInput := preload("res://logic/sim_input.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Codec := preload("res://logic/state_codec.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")

## The intended statuses (themes from the Boss brief): mummy curse/wound/sunder/weaken (+ the cobra ring's poison),
## crook greatsword bleed, scarab staff burn; goblin chief weaken/exhaust/sunder/slow/bleed.
const THEMES := {
	"boss_mummy_high_wizard_necklace": "weaken", "boss_mummy_high_wizard_earring": "wound", "boss_mummy_high_wizard_bracelet": "sunder",
	"boss_mummy_high_wizard_ring": "poison", "boss_mummy_high_wizard_back": "curse",
	"boss_mummy_boss_crook": "bleed", "boss_mummy_high_wizard_staff": "burn",
	"boss_goblin_chief_necklace": "weaken", "boss_goblin_chief_earring": "exhaust", "boss_goblin_chief_bracelet": "sunder",
	"boss_goblin_chief_ring": "slow", "boss_goblin_chief_back": "bleed",
}

var _combat
var _rules


func run(ctx) -> void:
	_combat = CombatDataLoader.load_default()
	_rules = preload("res://logic/item_rules_loader.gd").load_default()
	_data(ctx)
	_validator(ctx)
	_chance_and_res(ctx)
	_immune_boss(ctx)
	_cooldown(ctx)
	_determinism(ctx)
	_gear_path(ctx)
	_fight(ctx)
	_ui(ctx)


# ---------------------------------------------------------------- data

func _data(ctx) -> void:
	var errors := BossProcs.validate(_rules, _combat)
	ctx.check("boss options: data valid against the catalog and effects %s" % [errors], errors.is_empty())
	var boss_ids: Array = []
	for id in _rules.catalog.items:
		if not str(_rules.catalog.items[id].get("boss", "")).is_empty():
			boss_ids.append(str(id))
	boss_ids.sort()
	ctx.check("boss options: 12 boss-drop pieces (2 sets of 5 + 2 weapons), each with an option (%d)" % boss_ids.size(),
		boss_ids.size() == 12 and boss_ids.all(func(id): return not BossProcs.option(id).is_empty()))
	ctx.check("boss options: no zone drop has one (only catalog boss pieces)", _rules.catalog.items.keys().all(func(id):
		return not BossProcs.option(str(id)).is_empty() == not str(_rules.catalog.items[id].get("boss", "")).is_empty()))
	var themed := true
	for id in THEMES:
		themed = themed and BossProcs.option(id).get("status", "") == THEMES[id]
	ctx.check("boss options: one themed status per piece (mummy weaken/wound/sunder/poison/curse, crook bleed, staff burn, goblin weaken/exhaust/sunder/slow/bleed)", themed)
	for id in boss_ids:
		var o := BossProcs.option(id)
		var group := Effects.group_of(_combat.effects[o["status"]])
		ctx.check("boss option %s: %s %d%% for %.1fs, cooldown %.1fs, never control" % [id, o["status"], int(o["chance"]), o["duration"] / 60.0, o["icd"] / 60.0],
			o["chance"] >= 5.0 and o["chance"] <= 15.0 and o["icd"] > o["duration"] and group != "control")
	var names: Dictionary = BossProcs.data().get("status_names", {})
	ctx.check("boss options: every option status has a Thai and English name", boss_ids.all(func(id):
		var n = names.get(BossProcs.option(id)["status"], [])
		return n is Array and n.size() == 2 and not str(n[0]).is_empty() and not str(n[1]).is_empty()))
	var orc: Dictionary = preload("res://logic/boss_loot.gd").boss("orc_camp")
	var orc_pieces := preload("res://logic/boss_loot.gd").set_pieces(_rules, str(orc.get("set", "")))
	ctx.check("boss options: the Orc Warlock placeholder set's pieces carry options (data-only swap later)", not orc_pieces.is_empty() and orc_pieces.all(func(id): return not BossProcs.option(id).is_empty()))


## validate() catches each rule; the shipped data is restored afterwards.
func _validator(ctx) -> void:
	var saved: Dictionary = BossProcs.data().duplicate(true)
	var cases := {
		"chance 40 is outside the band": {"boss_goblin_chief_ring": {"status": "slow", "chance": 40, "duration": 180, "icd": 480}},
		"icd not longer than duration": {"boss_goblin_chief_ring": {"status": "slow", "chance": 10, "duration": 480, "icd": 300}},
		"control on an accessory": {"boss_goblin_chief_ring": {"status": "stun", "chance": 10, "duration": 20, "icd": 480}},
		"long control on a weapon": {"boss_mummy_boss_crook": {"status": "stun", "chance": 10, "duration": 120, "icd": 480}},
		"a buff as status": {"boss_goblin_chief_ring": {"status": "haste", "chance": 10, "duration": 180, "icd": 480}},
		"status repeated within one boss": {"boss_goblin_chief_ring": {"status": "weaken", "chance": 10, "duration": 180, "icd": 480}},
		"a zone item with an option": {"armour_sword_shield_shirt": {"status": "slow", "chance": 10, "duration": 180, "icd": 480}},
	}
	for label in cases:
		var edited: Dictionary = saved.duplicate(true)
		for id in cases[label]:
			edited["options"][id] = cases[label][id]
		BossProcs._cached = edited
		ctx.check("boss options validator rejects: %s" % label, not BossProcs.validate(_rules, _combat).is_empty())
	var missing: Dictionary = saved.duplicate(true)
	missing["options"].erase("boss_mummy_high_wizard_ring")
	BossProcs._cached = missing
	ctx.check("boss options validator rejects: a boss piece without an option", BossProcs.validate(_rules, _combat).any(func(e): return "boss_mummy_high_wizard_ring" in e))
	var short_stun: Dictionary = saved.duplicate(true)
	short_stun["options"]["boss_mummy_boss_crook"] = {"status": "stun", "chance": 10, "duration": 30, "icd": 480}
	BossProcs._cached = short_stun
	ctx.check("boss options validator allows a short (0.5 s) stun on a weapon", BossProcs.validate(_rules, _combat).is_empty())
	BossProcs._cached = saved


# ---------------------------------------------------------------- proc rules (driven by synthetic hit events)

func _arena(seed_value: int = 1, enemy: String = "dummy_grunt") -> GameSim:
	var world := SimWorld.new()
	world.half_width = 30.0
	world.half_depth = 3.0
	world.add_solid(AABB(Vector3(-40, -0.4, -5), Vector3(80, 0.4, 10)))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var sim := GameSim.new(world, _combat, rng)
	sim.add_player(1, Vector3(0, 0.05, 0), {"CRIRATE": 0})
	sim.add_enemy(2, Vector3(1.5, 0.05, 0), enemy)
	sim._ai.erase(2)
	sim.fighters[2].stats["HP"] = 1.0e9
	sim.fighters[2].hp = 1.0e9
	return sim


## `n` landed hits of fighter 1 on fighter 2, one per tick (effects cleared between so stacking never hides a landing).
## Returns {"triggers", "landed", "resisted", "events": [boss_proc events]}.
func _hits(sim: GameSim, n: int, kind: String = "hit") -> Dictionary:
	var out := {"triggers": 0, "landed": 0, "resisted": 0, "events": []}
	for i in n:
		sim.tick_count += 1
		sim.events.clear()
		sim.fighters[2].effects.clear()
		Effects.refresh(sim.fighters[2], _combat)
		sim.fighters[2].control_immune_left = 0
		sim.events.append({"type": kind, "attacker": 1, "target": 2, "damage": 5, "effect": "hit", "periodic": false})
		BossProcs.step(sim)
		for e in sim.events:
			if e["type"] == "boss_proc":
				out["triggers"] += 1
				out["landed"] += 1 if e["landed"] else 0
				out["resisted"] += 0 if e["landed"] else 1
				out["events"].append(e.duplicate())
	return out


func _opt(status: String, chance: float, duration: int = 60, icd: int = 0) -> Dictionary:
	return {"item": "test_" + status, "status": status, "chance": chance, "duration": duration, "icd": icd}


func _chance_and_res(ctx) -> void:
	var sim := _arena()
	sim.fighters[1].boss_procs = [_opt("weaken", 10.0)]
	var r := _hits(sim, 4000)
	ctx.check("proc: 10%% per hit with no cooldown triggers about 10%% (%d / 4000)" % r["triggers"], r["triggers"] > 330 and r["triggers"] < 470)
	ctx.check("proc: on a target with no RES every trigger lands (%d / %d)" % [r["landed"], r["triggers"]], r["landed"] == r["triggers"])
	sim = _arena()
	sim.fighters[1].boss_procs = [_opt("weaken", 100.0)]
	sim.fighters[2].stats["EFFECT_RES"] = 30.0
	sim.fighters[2].stats["DEBUFF_RES"] = 20.0
	r = _hits(sim, 1000)
	ctx.check("proc: EFFECT_RES 30 + DEBUFF_RES 20 lands about 50%% of triggers (%d / 1000)" % r["landed"], r["landed"] > 430 and r["landed"] < 570)
	sim.fighters[1].stats["DEBUFF_ACC"] = 20.0
	r = _hits(sim, 1000)
	ctx.check("proc: the wearer's DEBUFF_ACC 20 raises it to about 70%% (%d / 1000)" % r["landed"], r["landed"] > 630 and r["landed"] < 770)
	sim = _arena()
	sim.fighters[1].boss_procs = [_opt("burn", 100.0)]
	sim.fighters[2].stats["DOT_BURN_RES"] = 100.0
	r = _hits(sim, 200)
	ctx.check("proc: per-effect DOT_BURN_RES 100 = immune, every trigger resisted (%d)" % r["resisted"], r["landed"] == 0 and r["resisted"] == 200)
	sim = _arena()
	sim.fighters[1].boss_procs = [_opt("sunder", 100.0)]
	sim.events.clear()
	sim.events.append({"type": "blocked", "attacker": 1, "target": 2, "damage": 1})
	sim.events.append({"type": "skill_hit", "attacker": 1, "target": 2, "damage": 1, "effect": "reflect", "periodic": false})
	sim.events.append({"type": "skill_hit", "attacker": 1, "target": 2, "damage": 1, "effect": "redirect", "periodic": false})
	sim.events.append({"type": "dot", "target": 2, "damage": 1})
	BossProcs.step(sim)
	ctx.check("proc: blocked hits, reflects, redirects and DoT ticks never trigger", not sim.events.any(func(e): return e["type"] == "boss_proc"))
	r = _hits(sim, 5, "skill_hit")
	ctx.check("proc: a class skill hit triggers it too", r["triggers"] == 5)
	sim = _arena()
	sim.fighters[1].boss_procs = [_opt("sunder", 100.0)]
	sim.fighters[2].team = "player"
	r = _hits(sim, 20)
	ctx.check("proc: never on an ally", r["triggers"] == 0)


func _immune_boss(ctx) -> void:
	for boss in ["mummy_high_wizard", "orc_warlock", "goblin_chief"]:
		if not _combat.enemies.has(boss):
			continue
		var sim := _arena(3, boss)
		var target: Fighter = sim.fighters[2]
		var res := target.stat("EFFECT_RES") + target.stat("CTRL_RES")
		sim.fighters[1].boss_procs = [_opt("stun", 100.0, 30)]
		var r := _hits(sim, 300)
		if res >= 100.0:
			ctx.check("proc: %s (control RES %d) never takes a stun proc (%d triggers, %d landed)" % [boss, int(res), r["triggers"], r["landed"]], r["landed"] == 0 and r["triggers"] == 300)
		var debuff_res := Effects.resistance_total(target, "debuff", "sunder")
		sim.fighters[1].boss_procs = [_opt("sunder", 100.0)]
		r = _hits(sim, 1000)
		var expected := clampf(100.0 - debuff_res, 0.0, 100.0) * 10.0
		ctx.check("proc: %s takes sunder at 100 - its RES %d = about %d / 1000 (%d)" % [boss, int(debuff_res), int(expected), r["landed"]], absf(r["landed"] - expected) < 80.0)


func _cooldown(ctx) -> void:
	var sim := _arena()
	sim.fighters[1].boss_procs = [_opt("weaken", 100.0, 60, 300)]
	var r := _hits(sim, 900)
	var ticks: Array = []
	for e in r["events"]:
		ticks.append(e)
	ctx.check("cooldown: a certain proc with icd 300 triggers exactly 3 times in 900 hits (%d)" % r["triggers"], r["triggers"] == 3)
	var sim2 := _arena()
	sim2.fighters[1].boss_procs = [_opt("weaken", 100.0, 60, 300)]
	var at: Array = []
	for i in 700:
		sim2.tick_count += 1
		sim2.events.clear()
		sim2.events.append({"type": "hit", "attacker": 1, "target": 2, "damage": 5})
		BossProcs.step(sim2)
		if sim2.events.any(func(e): return e["type"] == "boss_proc"):
			at.append(sim2.tick_count)
	ctx.check("cooldown: triggers 300 ticks apart (%s)" % [at], at == [1, 301, 601])
	var sim3 := _arena()
	sim3.fighters[1].boss_procs = [_opt("weaken", 100.0, 60, 300), _opt("sunder", 100.0, 60, 300)]
	r = _hits(sim3, 10)
	ctx.check("cooldown: each piece has its own cooldown (two options: 2 triggers in 10 hits)", r["triggers"] == 2)
	var sim4 := _arena()
	sim4.fighters[1].boss_procs = [_opt("weaken", 100.0, 60, 300)]
	sim4.fighters[2].stats["EFFECT_RES"] = 100.0
	r = _hits(sim4, 400)
	ctx.check("cooldown: a resisted trigger still starts the cooldown (2 triggers in 400 hits)", r["triggers"] == 2 and r["landed"] == 0)


func _determinism(ctx) -> void:
	var a := _arena(42)
	var b := _arena(42)
	for s in [a, b]:
		s.fighters[1].boss_procs = [_opt("weaken", 12.0, 60, 120), _opt("bleed", 8.0, 60, 120)]
	var ra := _hits(a, 2000)
	var rb := _hits(b, 2000)
	ctx.check("determinism: the same seed gives the same procs (%d triggers)" % ra["triggers"], ra["events"] == rb["events"] and ra["triggers"] > 0)
	var c := _arena(43)
	c.fighters[1].boss_procs = [_opt("weaken", 12.0, 60, 120), _opt("bleed", 8.0, 60, 120)]
	ctx.check("determinism: another seed gives other procs", _hits(c, 2000)["events"] != ra["events"])
	var d := _arena(42)
	d.fighters[1].boss_procs = [_opt("weaken", 50.0)]
	d.fighters[2].stats["EFFECT_RES"] = 50.0
	var before: int = d.rng.state
	_hits(d, 300)
	ctx.check("determinism: procs and their landing rolls never draw from the sim RNG stream", d.rng.state == before)


# ---------------------------------------------------------------- gear -> fighter

var _serial := 0


func _piece(id: String, tier: int = 1):
	var slot := str(_rules.catalog.entry(id)["slot"])
	_serial += 1
	return ItemSystem.create_item(_rules, "t-%s-%d" % [id, _serial], slot, tier, F.rng(5), "", id)


func _gear_path(ctx) -> void:
	var ring_a = _piece("boss_mummy_high_wizard_ring")
	var ring_b = _piece("boss_mummy_high_wizard_ring")
	var cloak = _piece("boss_mummy_high_wizard_back")
	var opts := BossProcs.options_for([ring_a, ring_b, cloak])
	ctx.check("gear: two copies of the ring give ONE option, plus the cloak's (sorted by id)", opts.map(func(o): return o["item"]) == ["boss_mummy_high_wizard_back", "boss_mummy_high_wizard_ring"])
	cloak.durability = 0.0
	ctx.check("gear: a broken-down piece gives no option", BossProcs.options_for([cloak]).is_empty())
	cloak.durability = cloak.max_durability
	cloak.destroyed = true
	ctx.check("gear: a destroyed piece gives no option", BossProcs.options_for([cloak]).is_empty())
	var zone_piece = ItemSystem.create_item(_rules, "t-zone", "shirt", 3, F.rng(5), "", "armour_sword_shield_shirt")
	ctx.check("gear: a zone drop (even legendary) gives none", zone_piece != null and BossProcs.options_for([zone_piece]).is_empty())
	# through the real sim: attach_run -> _refresh_run_stats
	var f := F.make()
	f.profile.loadout.equip(_piece("boss_mummy_high_wizard_necklace"), 0)
	f.profile.loadout.equip(_piece("boss_mummy_high_wizard_ring"), 0)
	var sim = F.simulation(f, false)
	var ids: Array = sim.fighters[1].boss_procs.map(func(o): return o["item"])
	ctx.check("gear: attach_run fills Fighter.boss_procs from the worn pieces (%s)" % [ids], ids == ["boss_mummy_high_wizard_necklace", "boss_mummy_high_wizard_ring"])
	ctx.check("gear: monsters have no boss options", sim.fighters.keys().all(func(id): return id == 1 or sim.fighters[id].boss_procs.is_empty()))
	f.profile.loadout.unequip("necklace", 0)
	sim.gear_changed(1)
	ctx.check("gear: taking a piece off (gear_changed) drops its option", sim.fighters[1].boss_procs.map(func(o): return o["item"]) == ["boss_mummy_high_wizard_ring"])


# ---------------------------------------------------------------- a real fight + checkpoints

## A real sim: a player on a trip wearing the 5 mummy pieces next to a passive, very tough grunt (seeded).
func _fight_sim(seed_value: int):
	_serial = 0
	var f := F.make(seed_value)
	for id in ["boss_mummy_high_wizard_necklace", "boss_mummy_high_wizard_earring", "boss_mummy_high_wizard_bracelet", "boss_mummy_high_wizard_ring", "boss_mummy_high_wizard_back"]:
		f.profile.loadout.equip(_piece(id), 0)
	var sim := _arena(seed_value)
	sim.attach_run(1, f.run, f.rules, f.loot)
	sim.fighters[1].stats["HP"] = 1.0e7
	sim.fighters[1].hp = 1.0e7
	sim.fighters[1].direction = Vector2i(1, 0)
	return [f, sim]


func _drive(sim, ticks: int) -> Dictionary:
	var out := {"hits": 0, "procs": 0, "landed": 0, "by_item": {}, "trace": []}
	for i in ticks:
		var input := SimInput.new()
		input.light = (i % 2) == 0
		input.aim = Vector2(1, 0)
		sim.set_input(1, input)
		sim.bodies[2].position = sim.bodies[1].position + Vector3(1.2, 0, 0)  # pinned in reach (hits push it away)
		sim.bodies[2].knockback = Vector2.ZERO
		sim.tick()
		for e in sim.events:
			if e["type"] == "hit" and int(e["attacker"]) == 1:
				out["hits"] += 1
			if e["type"] == "boss_proc":
				out["procs"] += 1
				out["landed"] += 1 if e["landed"] else 0
				out["by_item"][e["item"]] = int(out["by_item"].get(e["item"], 0)) + 1
				out["trace"].append([sim.tick_count, e["item"], e["target"], e["landed"]])
	return out


func _fight(ctx) -> void:
	var a = _fight_sim(77)
	var b = _fight_sim(77)
	var ra := _drive(a[1], 1800)
	var rb := _drive(b[1], 1800)
	ctx.check("fight: a 30 s light-attack fight with the 5 mummy pieces: %d hits, %d procs (%d landed), per piece %s" % [ra["hits"], ra["procs"], ra["landed"], ra["by_item"]],
		ra["hits"] > 20 and ra["procs"] > 0)
	ctx.check("fight: the same seed replays the same procs and state", ra["trace"] == rb["trace"] and Codec.digest(a[1].snapshot()) == Codec.digest(b[1].snapshot()))
	var per_piece_max := 0
	for item in ra["by_item"]:
		per_piece_max = maxi(per_piece_max, int(ra["by_item"][item]))
	ctx.check("fight: no piece procs more often than its cooldown allows (max %d in 30 s, icd 8 s -> <= 4)" % per_piece_max, per_piece_max <= 4)
	# checkpoint mid-fight: a restored sim continues exactly
	var c = _fight_sim(91)
	_drive(c[1], 600)
	var saved: Dictionary = c[1].snapshot()
	var restored = GameSim.new(c[1].world, c[1].combat, RandomNumberGenerator.new())
	restored.item_rules = c[0].rules
	restored.loot_data = c[0].loot
	var ok: bool = restored.restore(saved, c[0].camp)
	ctx.check("checkpoint: restores with boss_procs and proc_ready (%s)" % [restored.fighters.get(1).proc_ready if ok else "restore failed"],
		ok and restored.fighters[1].boss_procs == c[1].fighters[1].boss_procs and restored.fighters[1].proc_ready == c[1].fighters[1].proc_ready and not c[1].fighters[1].boss_procs.is_empty())
	if ok:
		var after_a := _drive(c[1], 600)
		var after_b := _drive(restored, 600)
		ctx.check("checkpoint: the restored sim replays the same procs as the original (%d)" % after_a["procs"], after_a["trace"] == after_b["trace"])


# ---------------------------------------------------------------- UI: gold tokens and texts

func _ui(ctx) -> void:
	var InkUi = preload("res://client/ink_ui.gd")
	var UiThemes = preload("res://client/ui_themes.gd")
	var ItemText = preload("res://client/item_text.gd")
	var CardTokens = preload("res://client/card_tokens.gd")
	InkUi.reset_tokens()
	ctx.check("ui: a 'boss' rarity token exists in menus and over the world", InkUi.RARITY.has(InkUi.RARITY_BOSS) and InkUi.RARITY_WORLD.has(InkUi.RARITY_BOSS))
	ctx.check("ui: boss gold differs from legendary gold", InkUi.RARITY["boss"] != InkUi.RARITY["gold"])
	for theme_name in UiThemes.NAMES:
		UiThemes.apply(theme_name)
		ctx.check("ui: theme '%s' keeps a boss rarity colour" % theme_name, InkUi.RARITY.has("boss") and InkUi.RARITY_WORLD.has("boss"))
	UiThemes.apply("current")
	InkUi.reset_tokens()
	var boss_piece = _piece("boss_mummy_high_wizard_staff", 0)
	var zone_piece = ItemSystem.create_item(_rules, "t-zone-ui", "shirt", 3, F.rng(5), "", "armour_sword_shield_shirt")
	ctx.check("ui: a boss piece is boss gold at any tier (white tier here)", ItemText.rarity_key(boss_piece, _rules) == "boss" and ItemText.tier_color(boss_piece, _rules) == InkUi.RARITY["boss"])
	ctx.check("ui: a legendary zone piece keeps its tier gold", ItemText.rarity_key(zone_piece, _rules) == "gold" and ItemText.tier_color(zone_piece, _rules) == InkUi.RARITY["gold"])
	ctx.check("ui: loot popup key for a boss drop summary is boss", ItemText.rarity_key_for("boss_goblin_chief_ring", 1, _rules) == "boss" and ItemText.rarity_key_for("armour_sword_shield_shirt", 1, _rules) == "blue")
	for lang in ["en", "th"]:
		CardTokens.language = lang
		var text: String = ItemText.boss_option_text("boss_mummy_high_wizard_staff")
		var name: String = BossProcs.status_name("burn")[0 if lang == "th" else 1]
		ctx.check("ui (%s): boss option text '%s' names the status and numbers" % [lang, text], not text.is_empty() and name in text and "12" in text and "3" in text and "6" in text)
		ctx.check("ui (%s): a zone piece has no boss option text" % lang, ItemText.boss_option_text("armour_sword_shield_shirt") == "")
	CardTokens.language = "en"
	ctx.check("ui: boss name text on parchment reads (contrast %.1f >= 4.5)" % _contrast(CardTokens.HUB_BOSS_TEXT, CardTokens.HUB_PAPER), _contrast(CardTokens.HUB_BOSS_TEXT, CardTokens.HUB_PAPER) >= 4.5)
	ctx.check("ui: boss frame gold on the dark outline reads (contrast %.1f >= 3)" % _contrast(CardTokens.HUB_BOSS_GOLD, CardTokens.HUB_OUTLINE), _contrast(CardTokens.HUB_BOSS_GOLD, CardTokens.HUB_OUTLINE) >= 3.0)
	var lines: Array = ItemText.boss_set_lines(_piece("boss_mummy_high_wizard_ring"), _rules, [])
	ctx.check("ui: a boss set piece lists its set header + 3 steps (%d lines)" % lines.size(), lines.size() == 4 and str(lines[0]["text"]).contains("1/"))
	ctx.check("ui: a weapon outside any set has no set lines", ItemText.boss_set_lines(boss_piece, _rules, []).is_empty())
	var Cell = preload("res://client/hub_item_cell.gd")
	var cell = Cell.new()
	cell.setup()
	cell.card_race = "human"
	cell.show_item(boss_piece, _rules, "")
	var plain = Cell.new()
	plain.setup()
	plain.card_race = "human"
	plain.show_item(zone_piece, _rules, "")
	ctx.check("ui: the hub item cell marks a boss piece (gold frame) and not a zone piece", cell.boss and not plain.boss)
	cell.free()
	plain.free()
	var Details = preload("res://client/hub_item_details.gd")
	var details = Details.new()
	details.cell.card_race = "human"
	details.cell.card_level = 30
	details.layout_box(780.0, 300.0, 56.0, 0.5, false)
	details.show_item(boss_piece, _rules)
	var boss_shown: bool = details.boss_line.visible and not details.boss_line.text.is_empty()
	var below: bool = details.dur_key.position.y >= details.boss_line.position.y + details.boss_line.size.y - 0.5
	details.show_item(zone_piece, _rules)
	ctx.check("ui: details show the boss option line for a boss piece, above the durability row, and hide it for a zone piece", boss_shown and below and not details.boss_line.visible)
	details.free()


static func _luminance(c: Color) -> float:
	var parts := []
	for v in [c.r, c.g, c.b]:
		parts.append(v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4))
	return 0.2126 * parts[0] + 0.7152 * parts[1] + 0.0722 * parts[2]


static func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)
