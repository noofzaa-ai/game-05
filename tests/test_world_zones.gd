extends RefCounted
## World map zones (logic/world_zones.gd, data/world/zones.json; Boss 2026-11-16): the data is sound, the first
## zone is open, a zone opens after the boss of the zone before it, a zone without a journey is "coming soon",
## and only a run that clears the last wave (the boss) marks the boss beaten.
const Zones := preload("res://logic/world_zones.gd")
const Profile := preload("res://logic/profile.gd")
const F := preload("res://tests/online_fixture.gd")
const Journey := preload("res://logic/journey.gd")
const JourneyData := preload("res://logic/journey_data.gd")
const SquadMember := preload("res://logic/squad_member.gd")


class FakeSim:
	var _waves_released := 0


func run(ctx) -> void:
	ctx.check("zones.json has no problems %s" % [Zones.problems()], Zones.problems().is_empty())
	var list := Zones.zones()
	ctx.check("there are 11 zones, goblin base first", list.size() == 11 and str(list[0].id) == "goblin_base")
	var f := F.make()
	var p = Profile.new_player(f.rules, f.camp, F.rng(5))
	ctx.check("a new player: zone 1 open", Zones.state(p, "goblin_base") == Zones.OPEN)
	ctx.check("a zone without a journey is coming soon", Zones.state(p, "orc_camp") == Zones.SOON)
	ctx.check("the current zone of a new player is zone 1", str(Zones.current_zone(p).get("id", "")) == "goblin_base")
	ctx.check("another journey marks nothing", not Zones.on_battle_result(p, "ink_road", 12, 12))
	ctx.check("wave 8 of 9 does not beat the boss", not Zones.on_battle_result(p, "goblin_waves", 8, 9) and not Zones.boss_beaten(p, "goblin_base"))
	# A real goblin run: died after 8 waves = no boss; a win = boss beaten (through Journey.pay_card_xp, the server path).
	var j = _wave_journey(f, p)
	var sim := FakeSim.new()
	sim._waves_released = 8
	j.note_waves(sim)
	j.died()
	j.pay_card_xp()
	ctx.check("a lost run (8 waves) does not beat the goblin boss", not Zones.boss_beaten(p, "goblin_base"))
	var j2 = _wave_journey(f, p)
	j2.state = Journey.WON
	j2.pay_card_xp()
	ctx.check("a won goblin run beats the goblin boss", Zones.boss_beaten(p, "goblin_base"))
	ctx.check("a second win changes nothing", not Zones.on_battle_result(p, "goblin_waves", 9, 9))
	ctx.check("the boss flag survives a save/load", Zones.boss_beaten(Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())), f.rules, f.camp), "goblin_base"))


func _wave_journey(f: Dictionary, p):
	var data = JourneyData.load_by_id("goblin_waves", f.combat.enemies.keys())
	var trip = preload("res://logic/run.gd").start(p, f.camp)
	return Journey.start(data, SquadMember.make_squad(trip, ["longbow"])[0], f.rules, f.loot, f.combat.weapon_ids, 77)
