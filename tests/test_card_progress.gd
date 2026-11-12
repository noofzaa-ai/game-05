extends RefCounted
## Card levels and XP (design/gdd/skill-tree.md 3.2, 3.7, formulas 4.1-4.3, acceptance 2): the level curve, points
## with milestone bonuses, run XP paid once at run end to every squad card, progress stored on the card and old
## saves (no progress) staying valid.
const Progress := preload("res://logic/card_progress.gd")
const Deck := preload("res://logic/card_deck.gd")
const F := preload("res://tests/online_fixture.gd")
const Party := preload("res://logic/coop_journey.gd")
const Journey := preload("res://logic/journey.gd")
const JourneyData := preload("res://logic/journey_data.gd")
const SquadMember := preload("res://logic/squad_member.gd")
const Profile := preload("res://logic/profile.gd")
const CARDS := ["sword_shield", "greatsword", "longbow"]


class FakeSim:
	var _waves_released := 0


func run(ctx) -> void:
	_formulas(ctx)
	_grant(ctx)
	_card_storage(ctx)
	_run_end(ctx)


func _formulas(ctx) -> void:
	var pts := [1, 2, 9, 10, 12, 16, 17, 20, 25].map(func(l): return Progress.points(l))
	ctx.check("card points follow formula 4.1 %s" % [pts], pts == [0, 1, 8, 10, 12, 16, 17, 21, 26])
	ctx.check("points stop at max level 25", Progress.max_level() == 25 and Progress.points(30) == 26)
	var reqs := [1, 2, 3, 4, 5, 10, 15, 20, 24].map(func(l): return Progress.xp_req(l))
	ctx.check("xp_req follows round(100 * L^1.2) %s" % [reqs], reqs == [100, 230, 374, 528, 690, 1585, 2578, 3641, 4532])  # GDD 4.2 table rounds 15 -> 2580, 24 -> 4530 by hand; the formula is the rule
	ctx.check("no XP needed past max level", Progress.xp_req(25) == 0)
	ctx.check("run XP: full win = 700", Progress.run_xp(11, true, true) == 700)
	ctx.check("run XP: a loss after 5 waves = 175", Progress.run_xp(5, false, false) == 175)
	ctx.check("run XP: nothing cleared = 0, waves past 11 do not count", Progress.run_xp(0, false, false) == 0 and Progress.run_xp(40, false, false) == Progress.run_xp(11, false, false))


func _grant(ctx) -> void:
	var deck := Deck.initial()
	ctx.check("a new card is level 1 with 0 XP", Progress.summary(deck, "longbow") == {"level": 1, "xp": 0, "xp_next": 100, "max": false, "points": 0})
	var got := Progress.grant(deck, "longbow", 175)
	ctx.check("175 XP takes a level-1 card to level 2 with 75 left %s" % [got], got["level"] == 2 and got["xp"] == 75 and got["levels_gained"] == 1)
	got = Progress.grant(deck, "longbow", 700)
	ctx.check("a full win then reaches level 4 (75+700-230-374 = 171) %s" % [got], got["level"] == 4 and got["xp"] == 171)
	ctx.check("other cards are untouched", Progress.level_of(deck, "magic") == 1)
	Progress.grant(deck, "magic", 10000000)
	ctx.check("XP past max level is discarded (MAX)", Progress.summary(deck, "magic") == {"level": 25, "xp": 0, "xp_next": 0, "max": true, "points": 26})
	ctx.check("an unknown card gets nothing", Progress.grant(deck, "nope", 100).is_empty())
	ctx.check("a deck with progress stays valid", Deck.validate(deck) == "")


func _card_storage(ctx) -> void:
	var deck := Deck.initial()
	ctx.check("an old card without progress is valid", not deck["cards"]["sword_shield"].has("progress") and Deck.validate(deck) == "")
	deck["cards"]["sword_shield"]["progress"] = {"level": 3, "xp": 9999}
	ctx.check("XP past the level's need is a bad card", Deck.validate(deck) == "bad_card")
	deck["cards"]["sword_shield"]["progress"] = {"level": 3.0, "xp": 20.0}  # JSON numbers
	ctx.check("integral JSON floats are accepted", Deck.validate(deck) == "")
	deck["cards"]["sword_shield"]["progress"] = {"level": 99, "xp": 9999}
	var fixed := Deck.repaired(deck)
	ctx.check("repair keeps the card and clamps its progress", fixed["cards"]["sword_shield"]["progress"] == {"level": 25, "xp": 0} and fixed["cards"]["sword_shield"]["hair"] == deck["cards"]["sword_shield"]["hair"])
	var f := F.make()
	Progress.grant(f.profile.card_deck, "greatsword", 500)
	var loaded = Profile.from_dict(JSON.parse_string(JSON.stringify(f.profile.to_dict())), f.rules, f.camp)
	ctx.check("card progress survives a profile save/load", loaded != null and Progress.progress_of(loaded.card_deck, "greatsword") == Progress.progress_of(f.profile.card_deck, "greatsword") and Progress.level_of(loaded.card_deck, "greatsword") == 3)


func _squad_journey(f: Dictionary, cards: Array):
	var data = JourneyData.load_by_id("goblin_waves", f.combat.enemies.keys())
	if cards.size() == 1:
		return Journey.start(data, SquadMember.make_squad(f.run, cards)[0], f.rules, f.loot, f.combat.weapon_ids, 77)
	var members: Array = SquadMember.make_squad(f.run, cards)
	var trips := {}
	for i in members.size():
		trips[i + 1] = members[i]
	return Party.start_party(data, trips, f.rules, f.loot, f.combat.weapon_ids, 77)


func _run_end(ctx) -> void:
	# A full win: 11 waves cleared, then the boss.
	var f := F.make()
	var j = _squad_journey(f, CARDS)
	j.choose(0)
	var sim := FakeSim.new()
	sim._waves_released = 11
	j.note_waves(sim)
	j.stage_cleared(1.0)
	ctx.check("a won squad run is over", j.state == Journey.WON)
	var levels: Array = CARDS.map(func(c): return Progress.progress_of(f.profile.card_deck, c))
	ctx.check("every squad card gets 700 XP for a full win %s" % [levels], levels.all(func(p): return p == {"level": 3, "xp": 370}))  # 700 - 100 - 230
	ctx.check("the card outside the squad gets none", Progress.level_of(f.profile.card_deck, "magic") == 1)
	ctx.check("the journey reports what each card got", j.card_xp.size() == 3 and int(j.card_xp["longbow"]["xp_gained"]) == 700)
	j.pay_card_xp()
	j.died()
	ctx.check("a repeated run end never pays twice", Progress.progress_of(f.profile.card_deck, "longbow") == levels[2])
	var restored = Party.from_dict(JSON.parse_string(JSON.stringify(j.to_dict())), j.data, f.rules, f.camp, f.loot, f.combat.weapon_ids)
	ctx.check("the paid flag survives a checkpoint", restored != null and restored.card_xp_paid and restored.card_xp.size() == 3)

	# A loss at wave 6: waves 1-5 cleared -> 175, downed or not.
	f = F.make()
	j = _squad_journey(f, CARDS)
	j.choose(0)
	sim = FakeSim.new()
	sim._waves_released = 5
	j.note_waves(sim)
	j.died()
	ctx.check("a loss after 5 waves pays 175 to every squad card", CARDS.all(func(c): return Progress.progress_of(f.profile.card_deck, c) == {"level": 2, "xp": 75}))
	sim._waves_released = 9
	j.note_waves(sim)
	ctx.check("waves noted after the run ended do not count", j.waves_cleared == 5)

	# A solo card run (one squad member through Journey.start).
	f = F.make()
	j = _squad_journey(f, ["magic"])
	j.choose(0)
	sim = FakeSim.new()
	sim._waves_released = 2
	j.note_waves(sim)
	j.died()
	ctx.check("a solo run levels only its card (25+30 = 55 XP)", Progress.progress_of(f.profile.card_deck, "magic") == {"level": 1, "xp": 55} and Progress.level_of(f.profile.card_deck, "sword_shield") == 1)
	var solo = Journey.from_dict(JSON.parse_string(JSON.stringify(j.to_dict())), j.data, f.rules, f.camp, f.loot, f.combat.weapon_ids)
	ctx.check("a solo checkpoint keeps waves cleared and the paid flag", solo != null and solo.waves_cleared == 2 and solo.card_xp_paid)
