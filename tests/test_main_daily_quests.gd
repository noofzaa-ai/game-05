extends RefCounted
## Main quest chain + Orc Camp unlock + daily quests (Boss 2026-11-21; logic/zone_quests.gd, logic/daily_quests.gd,
## data/world/zone_quests.json, data/world/daily_quests.json). Main #1 = the pyramid (goblin boss + a level 15 card),
## main #2 = the orc camp (pyramid boss + EVERY card level 10 + one card level 20), shown locked until #1 is done.
## Dailies: counted at a run's end on the authority, reset at the server day boundary, claimed once for gold.
const Zones := preload("res://logic/world_zones.gd")
const Quests := preload("res://logic/zone_quests.gd")
const Daily := preload("res://logic/daily_quests.gd")
const Commands := preload("res://logic/commands.gd")
const Profile := preload("res://logic/profile.gd")
const Runner := preload("res://server/profile/runner.gd")
const F := preload("res://tests/online_fixture.gd")

## A fixed server time: 2026-11-21 12:00 UTC (19:00 Bangkok), well inside one daily day.
const T0 := 1795262400


func _set_levels(p, levels: Array) -> void:
	var ids: Array = p.card_deck["cards"].keys()
	for i in ids.size():
		var lv: int = int(levels[i]) if i < levels.size() else 1
		p.card_deck["cards"][ids[i]]["progress"] = {"level": lv, "xp": 0}


func _cmd(f, p, command: Dictionary, now: int) -> Dictionary:
	return Commands.apply({"now": now, "profile": p, "rules": f.rules, "camp": f.camp, "location": "camp"}, command, F.rng(1))


func run(ctx) -> void:
	var f := F.make()
	var zone_ids: Array = Zones.zones().map(func(z): return str(z.id))
	ctx.check("quest data has no problems %s" % [Quests.problems(zone_ids)], Quests.problems(zone_ids).is_empty())
	ctx.check("daily data has no problems %s" % [Daily.problems()], Daily.problems().is_empty())
	# --- chain
	ctx.check("main chain = pyramid, orc_camp %s" % [Quests.chain()], Quests.chain() == ["pyramid", "orc_camp"])
	ctx.check("orc camp quest needs the pyramid boss, all cards 10 and one card 20", _orc_steps_ok())
	var p = F.past_tutorial(Profile.new_player(f.rules, f.camp, F.rng(21)))
	_set_levels(p, [5, 5, 5, 5])
	ctx.check("new player: #1 active, #2 locked", Quests.main_state(p, "pyramid") == Quests.MAIN_ACTIVE and Quests.main_state(p, "orc_camp") == Quests.MAIN_LOCKED and Quests.active_main(p) == "pyramid")
	ctx.check("previous of orc_camp is pyramid", Quests.previous_main("orc_camp") == "pyramid" and Quests.previous_main("pyramid") == "")
	# the orc conditions alone do not skip quest 1
	p.unlocks["boss_pyramid"] = true
	_set_levels(p, [20, 10, 10, 10])
	ctx.check("orc steps met but #1 not done: #2 still locked", Quests.met(p, "orc_camp") and Quests.main_state(p, "orc_camp") == Quests.MAIN_LOCKED)
	p.unlocks.erase("boss_pyramid")
	p.unlocks["boss_goblin_base"] = true
	_set_levels(p, [15, 5, 5, 5])
	ctx.check("#1 done: #1 done, #2 active", Quests.main_state(p, "pyramid") == Quests.MAIN_DONE and Quests.main_state(p, "orc_camp") == Quests.MAIN_ACTIVE and Quests.active_main(p) == "orc_camp")
	# --- orc condition: every card >= 10 AND one card >= 20 (plus the pyramid boss)
	p.unlocks["boss_pyramid"] = true
	_set_levels(p, [19, 10, 10, 10])
	ctx.check("all 10, best 19: not met", not Quests.met(p, "orc_camp"))
	var steps: Array = Quests.progress(p, "orc_camp")
	ctx.check("progress: all-10 step 4/4 done, level-20 step 19/20 %s" % [steps], steps[1].done and steps[1].current == 4 and steps[1].target == 4 and not steps[2].done and steps[2].current == 19 and "4/4" in str(steps[1].text_en) and "19/20" in str(steps[2].text_th))
	_set_levels(p, [20, 10, 10, 9])
	steps = Quests.progress(p, "orc_camp")
	ctx.check("one card 20, one card 9 (mixed): not met, 3/4", not Quests.met(p, "orc_camp") and steps[1].current == 3 and not steps[1].done and steps[2].done)
	_set_levels(p, [20, 10, 10, 10])
	ctx.check("one 20 + the rest 10: met", Quests.met(p, "orc_camp"))
	_set_levels(p, [25, 25, 25, 25])
	ctx.check("all 25: met", Quests.met(p, "orc_camp") and Quests.active_main(p) == "")
	p.unlocks.erase("boss_pyramid")
	ctx.check("without the pyramid boss: not met", not Quests.met(p, "orc_camp"))
	p.unlocks["boss_pyramid"] = true
	var deck_saved: Dictionary = p.card_deck["cards"]
	p.card_deck["cards"] = {}
	steps = Quests.progress(p, "orc_camp")
	ctx.check("0 cards: card_level_all fails closed (0/1)", not Quests.met(p, "orc_camp") and not steps[1].done and steps[1].target == 1 and steps[1].current == 0)
	p.card_deck["cards"] = deck_saved
	ctx.check("a null profile fails closed", not Quests.met(null, "orc_camp") and Quests.main_state(null, "orc_camp") == Quests.MAIN_LOCKED)
	# --- the zone gate: works as soon as the orc journey is set (fake table with a journey)
	var saved = Zones._cache
	Zones._cache = {"zones": [
		{"id": "goblin_base", "order": 1, "journey": "goblin_waves"},
		{"id": "pyramid", "order": 2, "journey": "mummy_waves"},
		{"id": "orc_camp", "order": 3, "journey": "orc_waves"}]}
	var q = F.past_tutorial(Profile.new_player(f.rules, f.camp, F.rng(22)))
	q.unlocks["boss_goblin_base"] = true
	q.unlocks["boss_pyramid"] = true
	_set_levels(q, [15, 5, 5, 5])
	ctx.check("orc journey set, pyramid beaten, cards low: LOCKED, journey refused", Zones.state(q, "orc_camp") == Zones.LOCKED and Zones.journey_problem(q, "orc_waves") == "zone_locked" and Commands.fight_problem(q, "orc_waves") == "zone_locked")
	_set_levels(q, [20, 10, 10, 10])
	ctx.check("quest done: OPEN, start_journey_for gives the orc journey", Zones.state(q, "orc_camp") == Zones.OPEN and Zones.start_journey_for(q, "orc_camp") == "orc_waves")
	Zones._cache = saved
	ctx.check("shipped data: the orc camp stays coming soon while its journey is empty", Zones.state(q, "orc_camp") == Zones.SOON)
	# --- daily: day boundary and reset
	var hour := int(Daily.data().get("reset_hour_utc", 0))
	var boundary := (Daily.day_of(T0) + 1) * Daily.DAY + hour * 3600
	ctx.check("day turns over exactly at reset_hour_utc", Daily.day_of(boundary - 1) == Daily.day_of(T0) and Daily.day_of(boundary) == Daily.day_of(T0) + 1)
	ctx.check("seconds_to_reset counts down to the boundary", Daily.seconds_to_reset(boundary - 60) == 60 and Daily.seconds_to_reset(boundary) == Daily.DAY)
	ctx.check("no clock: day 0, nothing recorded", Daily.day_of(0) == 0)
	var d = F.past_tutorial(Profile.new_player(f.rules, f.camp, F.rng(23)))
	var rows: Array = Daily.progress(d, T0)
	ctx.check("3 dailies, none done for a new player", rows.size() == 3 and rows.all(func(r): return not r.done and not r.claimed and r.current == 0))
	Daily.record_run(d, T0, 6, false)
	Daily.record_run(d, T0 + 60, 9, true)
	rows = Daily.progress(d, T0 + 120)
	var by := {}
	for r in rows:
		by[r.id] = r
	ctx.check("two runs: fights 2/3, waves 15/15 done, boss 1/1 done %s" % [rows], by.daily_fights.current == 2 and not by.daily_fights.done and by.daily_waves.done and by.daily_waves.current == 15 and by.daily_boss.done)
	ctx.check("progress text filled th/en", "2/3" in str(by.daily_fights.desc_en) and "2/3" in str(by.daily_fights.desc_th))
	Daily.record_run(d, 0, 9, true)
	ctx.check("a run without a clock records nothing", Daily.progress(d, T0 + 120)[0].current == 2)
	ctx.check("claimable = 2", Daily.claimable(d, T0 + 120) == 2)
	# claim through the real command path
	var gold: int = d.stash.gold
	var r1 := _cmd(f, d, {"type": "daily_claim", "quest": "daily_boss"}, T0 + 200)
	ctx.check("claim the boss daily: ok, gold paid %s" % [r1], r1.get("ok", false) and d.stash.gold == gold + int(by.daily_boss.reward_gold) and r1.changes.has("daily"))
	ctx.check("claiming twice is refused", _cmd(f, d, {"type": "daily_claim", "quest": "daily_boss"}, T0 + 210).get("error", "") == "already_claimed")
	ctx.check("claiming an unfinished daily is refused", _cmd(f, d, {"type": "daily_claim", "quest": "daily_fights"}, T0 + 210).get("error", "") == "quest_not_done")
	ctx.check("unknown daily refused", _cmd(f, d, {"type": "daily_claim", "quest": "nope"}, T0 + 210).get("error", "") == "unknown_quest")
	ctx.check("claim without a server clock refused", _cmd(f, d, {"type": "daily_claim", "quest": "daily_waves"}, 0).get("error", "") == "clock_unavailable")
	ctx.check("claim outside camp refused", Commands.apply({"now": T0, "profile": d, "rules": f.rules, "camp": f.camp, "location": "rest", "run": null}, {"type": "daily_claim", "quest": "daily_waves"}, F.rng(1)).get("ok", true) == false)
	ctx.check("the profile runner allows daily_claim", Runner.ALLOWED.has("daily_claim"))
	# save round trip keeps today's block
	var back = Profile.from_dict(d.to_dict(), f.rules, f.camp)
	ctx.check("save round trip keeps counts and claims", back != null and Daily.progress(back, T0 + 300).filter(func(x): return x.claimed).size() == 1 and Daily.progress(back, T0 + 300)[0].current == 2)
	ctx.check("a tampered save is cleaned (unknown stat, negative count)", Daily.sanitized({"day": 3, "counts": {"fights": -5, "gold": 99}, "claimed": ["a", "a"]}) == {"day": 3, "counts": {"fights": 0}, "claimed": ["a"]})
	# next day: reset
	rows = Daily.progress(d, boundary + 10)
	ctx.check("after the reset: every daily back to 0 and unclaimed", rows.all(func(x): return x.current == 0 and not x.claimed) and Daily.claimable(d, boundary + 10) == 0)
	Daily.record_run(d, boundary + 20, 9, true)
	rows = Daily.progress(d, boundary + 30)
	ctx.check("a new day counts from 0 again (boss done, claimable again)", rows[2].done and not rows[2].claimed and rows[0].current == 1)
	ctx.check("the new day's boss daily can be claimed again", _cmd(f, d, {"type": "daily_claim", "quest": "daily_boss"}, boundary + 40).get("ok", false))
	# --- the run end records on the authority (journey.pay_card_xp)
	ctx.check("a won journey records fight, waves and boss once", _journey_records(f))


func _orc_steps_ok() -> bool:
	var q := Quests.quest("orc_camp")
	var steps: Array = q.get("steps", [])
	if steps.size() != 3:
		return false
	return steps[0].type == "boss_beaten" and steps[0].zone == "pyramid" and steps[1].type == "card_level_all" and int(steps[1].min) == 10 and steps[2].type == "card_level" and int(steps[2].min) == 20 and int(steps[2].get("count", 1)) == 1


func _journey_records(f) -> bool:
	var Journey = load("res://logic/journey.gd")
	var JourneyData = load("res://logic/journey_data.gd")
	var p = F.past_tutorial(Profile.new_player(f.rules, f.camp, F.rng(31)))
	var data = JourneyData.load_by_id("goblin_waves", f.combat.enemies.keys())
	var trip = F.Run.start(p, f.camp)
	var j = Journey.start(data, load("res://logic/squad_member.gd").make_squad(trip, ["longbow"])[0], f.rules, f.loot, f.combat.weapon_ids, 7)
	j.daily_now = T0
	j.state = Journey.WON
	j.pay_card_xp()
	j.pay_card_xp()  # paid once
	var rows: Array = Daily.progress(p, T0 + 5)
	return rows[0].current == 1 and rows[2].current == 1 and rows[1].current == int(data.stage_count)
