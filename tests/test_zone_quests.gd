extends RefCounted
## Zone unlock quests (logic/zone_quests.gd, data/world/zone_quests.json; Boss 2026-11-17): the Sand Pyramid opens
## only with the goblin boss beaten AND a card at level 15+; the server paths refuse a locked zone's journey.
const Zones := preload("res://logic/world_zones.gd")
const Quests := preload("res://logic/zone_quests.gd")
const Commands := preload("res://logic/commands.gd")
const Profile := preload("res://logic/profile.gd")
const F := preload("res://tests/online_fixture.gd")
const Manager := preload("res://server/rooms/manager.gd")


func _set_levels(p, levels: Array) -> void:
	var ids: Array = p.card_deck["cards"].keys()
	for i in ids.size():
		var lv: int = int(levels[i]) if i < levels.size() else 1
		p.card_deck["cards"][ids[i]]["progress"] = {"level": lv, "xp": 0}


func run(ctx) -> void:
	var zone_ids: Array = Zones.zones().map(func(z): return str(z.id))
	ctx.check("quest data has no problems %s" % [Quests.problems(zone_ids)], Quests.problems(zone_ids).is_empty())
	ctx.check("the pyramid has the quest, the goblin base none", Quests.has_quest("pyramid") and not Quests.has_quest("goblin_base"))
	var f := F.make()
	var p = Profile.new_player(f.rules, f.camp, F.rng(5))
	ctx.check("goblin zone without quest: met", Quests.met(p, "goblin_base") and Quests.progress(p, "goblin_base").is_empty())
	_set_levels(p, [])
	var steps: Array = Quests.progress(p, "pyramid")
	ctx.check("two steps, none done for a new player", steps.size() == 2 and not steps[0].done and not steps[1].done and steps[1].current == 1 and steps[1].target == 15)
	ctx.check("quest text shows best card Lv 1/15", "Lv 1/15" in str(steps[1].text_en) and "1/15" in str(steps[1].text_th))
	_set_levels(p, [14])
	ctx.check("level 14 without boss: not met", not Quests.met(p, "pyramid") and Quests.progress(p, "pyramid")[1].current == 14)
	p.unlocks["boss_goblin_base"] = true
	ctx.check("boss beaten + level 14: not met", not Quests.met(p, "pyramid"))
	_set_levels(p, [3, 15])
	ctx.check("boss + one card at 15: met", Quests.met(p, "pyramid") and Quests.progress(p, "pyramid")[1].done)
	_set_levels(p, [25, 25])
	ctx.check("level 25 counts, progress capped at target", Quests.met(p, "pyramid") and Quests.progress(p, "pyramid")[1].current == 15)
	p.unlocks["boss_goblin_base"] = false
	ctx.check("level 15 without the boss: not met", not Quests.met(p, "pyramid"))
	ctx.check("a null profile fails closed", not Quests.met(null, "pyramid"))
	ctx.check("a needing-two-cards quest counts cards", _count_quest(ctx, f))
	# state: needs the zone to have a real journey. The shipped data keeps journey "" (dev only), so use a fake table.
	var saved = Zones._cache
	Zones._cache = {"zones": [
		{"id": "goblin_base", "order": 1, "journey": "goblin_waves"},
		{"id": "pyramid", "order": 2, "journey": "mummy_waves"}]}
	var q = Profile.new_player(f.rules, f.camp, F.rng(6))
	_set_levels(q, [])
	ctx.check("pyramid LOCKED for a new player", Zones.state(q, "pyramid") == Zones.LOCKED)
	q.unlocks["boss_goblin_base"] = true
	ctx.check("boss only: still LOCKED", Zones.state(q, "pyramid") == Zones.LOCKED)
	_set_levels(q, [15])
	ctx.check("boss + level 15: OPEN", Zones.state(q, "pyramid") == Zones.OPEN and Zones.start_journey_for(q, "pyramid") == "mummy_waves")
	var locked = Profile.new_player(f.rules, f.camp, F.rng(8))
	F.past_tutorial(locked)
	ctx.check("journey_problem: locked zone journey refused, goblin and ink_road allowed",
		Zones.journey_problem(locked, "mummy_waves") == "zone_locked" and Zones.journey_problem(locked, "goblin_waves") == "" and Zones.journey_problem(locked, "ink_road") == "")
	ctx.check("fight_problem refuses a locked zone journey (server room path)", Commands.fight_problem(locked, "mummy_waves") == "zone_locked")
	ctx.check("fight_problem unchanged for the goblin journey", Commands.fight_problem(locked, "goblin_waves") == Commands.fight_problem(locked))
	_set_levels(locked, [15])
	locked.unlocks["boss_goblin_base"] = true
	ctx.check("fight_problem accepts it once the quest is done", Commands.fight_problem(locked, "mummy_waves") == Commands.fight_problem(locked))
	# the room manager refuses a locked zone's journey through the real create() path
	var mgr = Manager.new()
	ctx.check("manager: squad room journey id is goblin_waves (the gate sees the zone)", mgr.squad_journey.id == "goblin_waves")
	Zones._cache = saved
	ctx.check("shipped data: the pyramid is locked until the quest is done, goblin open", Zones.state(Profile.new_player(f.rules, f.camp, F.rng(9)), "pyramid") == Zones.LOCKED and Zones.state(locked, "goblin_base") == Zones.OPEN)
	ctx.check("a new player cannot start the mummy journey (zone locked)", Zones.journey_problem(Profile.new_player(f.rules, f.camp, F.rng(9)), "mummy_waves") == "zone_locked")


func _count_quest(ctx, f) -> bool:
	var saved = Quests._cache
	Quests._cache = {"quests": {"z": {"steps": [{"type": "card_level", "min": 5, "count": 2, "text_th": "{cur}/{target}", "text_en": "{cur}/{target}"}]}}}
	var p = Profile.new_player(f.rules, f.camp, F.rng(5))
	_set_levels(p, [5, 4, 5])
	var ok: bool = Quests.met(p, "z") and Quests.progress(p, "z")[0].target == 2
	_set_levels(p, [5, 4])
	ok = ok and not Quests.met(p, "z") and Quests.progress(p, "z")[0].current == 1
	Quests._cache = saved
	return ok
