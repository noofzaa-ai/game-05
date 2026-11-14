extends RefCounted
## New-player tutorial rules (design/gdd/tutorial.md 7, acceptance 1-6, 7 (data part) and 9): raceless starter cards,
## the Magic/Runeborn gate, old-save migration, server guards, the wave-12 unlock hook, step order and room refusal.
const Deck := preload("res://logic/card_deck.gd")
const Profile := preload("res://logic/profile.gd")
const Commands := preload("res://logic/commands.gd")
const Unlocks := preload("res://logic/unlocks.gd")
const Tutorial := preload("res://logic/tutorial.gd")
const F := preload("res://tests/online_fixture.gd")
const Journey := preload("res://logic/journey.gd")
const JourneyData := preload("res://logic/journey_data.gd")
const SquadMember := preload("res://logic/squad_member.gd")
const Manager := preload("res://server/rooms/manager.gd")
const Runner := preload("res://server/profile/runner.gd")


class FakeSim:
	var _waves_released := 0


func run(ctx) -> void:
	var f := F.make()
	var p = Profile.new_player(f.rules, f.camp, F.rng(3))  # a raw new player (F.make() is past the tutorial)
	# 1. initial(): raceless starter cards, a locked magic card, new-profile flags.
	var deck := Deck.initial()
	ctx.check("AC1 every new card has race ''", deck["cards"].values().all(func(c): return str(c.get("race", "x")) == ""))
	ctx.check("AC1 the starter classes and magic exist", deck["cards"].has_all(["sword_shield", "greatsword", "longbow", "magic"]))
	ctx.check("AC1 the new squad is empty", deck["squad"].is_empty())
	ctx.check("AC1 a new deck validates", Deck.validate(deck) == "")
	ctx.check("AC1 magic is locked for a new profile", not Unlocks.is_class_unlocked(p, "magic") and Unlocks.is_class_unlocked(p, "longbow"))
	ctx.check("AC1 new profile: unlock false, step ''", p.unlocks.get("magic_runeborn") == false and p.tutorial["step"] == "")
	ctx.check("AC1 raceless new cards still wear their class kit", p.loadout_of("greatsword") != null and p.loadout_of("greatsword").item_at("weapon", 0) != null)
	var saved = Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())), f.rules, f.camp)
	ctx.check("AC1 a new profile survives save/load", saved != null and saved.tutorial == p.tutorial and saved.unlocks == p.unlocks and saved.card_deck["squad"].is_empty() and saved.card_deck["cards"]["longbow"]["race"] == "")

	# 2. Migration of an old save (no tutorial block, cards without race field).
	var old: Dictionary = JSON.parse_string(JSON.stringify(p.to_dict()))
	old.erase("tutorial")
	old.erase("unlocks")
	for c in old["card_deck"]["cards"]:
		old["card_deck"]["cards"][c].erase("race")
	old["card_deck"]["squad"] = ["sword_shield", "greatsword", "longbow"]
	var cards_before: Dictionary = old["card_deck"]["cards"].duplicate(true)
	var m = Profile.from_dict(old.duplicate(true), f.rules, f.camp)
	ctx.check("AC2 old save: step done, tour done, unlocked", m != null and m.tutorial["step"] == "done" and m.tutorial["tour_done"] and m.tutorial["unlock_seen"] and Unlocks.unlocked(m))
	ctx.check("AC2 old save: cards unchanged, squad kept", m.card_deck["cards"] == cards_before and m.card_deck["squad"] == ["sword_shield", "greatsword", "longbow"])
	ctx.check("AC2 old raceless cards use their starter race", Deck.race_of(m.card_deck, "greatsword") == "viking")
	var m2 = Profile.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())), f.rules, f.camp)
	ctx.check("AC2 migration is idempotent", m2.to_dict() == m.to_dict())

	# 3. card_race lock.
	ctx.check("AC3 card_race(magic, human) locked", _cmd(f, p, {"type": "card_race", "class": "magic", "race": "human"}) == "locked")
	ctx.check("AC3 card_race(longbow, runeborn) locked", _cmd(f, p, {"type": "card_race", "class": "longbow", "race": "runeborn"}) == "locked")
	ctx.check("AC3 card_race(longbow, elf) ok", _cmd(f, p, {"type": "card_race", "class": "longbow", "race": "elf"}) == "ok")
	var u = Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())), f.rules, f.camp)
	u.unlocks["magic_runeborn"] = true
	ctx.check("AC3 after unlock magic/runeborn ok", _cmd(f, u, {"type": "card_race", "class": "magic", "race": "runeborn"}) == "ok")

	# 4. Empty race; squad/fight with raceless or locked cards.
	ctx.check("AC4 card_race(x, '') invalid_race", _cmd(f, p, {"type": "card_race", "class": "longbow", "race": ""}) == "invalid_race")
	ctx.check("AC4 squad with a raceless card refused", _cmd(f, p, {"type": "card_squad", "squad": ["longbow", "greatsword"]}) == "no_race")
	ctx.check("AC4 squad with a locked card refused", _cmd(f, p, {"type": "card_squad", "squad": ["longbow", "magic"]}) == "locked")
	ctx.check("AC4 squad of raced cards ok", _cmd(f, p, {"type": "card_squad", "squad": ["longbow"]}) == "ok")
	var g = Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())), f.rules, f.camp)
	g.card_deck["squad"] = []
	ctx.check("AC4 fight guard: empty squad refused", Commands.fight_problem(g) == "no_squad")
	g.card_deck["squad"] = ["longbow", "greatsword"]  # a tampered save: greatsword has no race
	ctx.check("AC4 fight guard: raceless card refused", Commands.fight_problem(g) == "no_race")
	g.card_deck["squad"] = ["longbow", "magic"]
	ctx.check("AC4 fight guard: locked card refused", Commands.fight_problem(g) == "locked")
	g.card_deck["squad"] = ["longbow"]
	ctx.check("AC4 fight guard: a raced squad may fight", Commands.fight_problem(g) == "")
	var mgr = Manager.new()
	mgr.squad_rooms = true  # the card-squad (auto-battler) rooms carry the guards
	var raceless: Dictionary = g.to_dict()
	raceless["card_deck"]["squad"] = ["longbow", "greatsword"]  # tampered: greatsword has no race
	var made: Dictionary = mgr.create("tutorialfightguard", 5, [{"id": 1, "profile": raceless}], false, 1)
	ctx.check("AC4 room fight start refused for a raceless squad %s" % [made], not made.get("ok", true))

	# 5. Battle-result unlock hook.
	ctx.check("AC5 cleared 11 does not unlock", not Unlocks.on_battle_result(p, "goblin_waves", 11) and not Unlocks.unlocked(p))
	ctx.check("AC5 another journey does not unlock", not Unlocks.on_battle_result(p, "ink_road", 12) and not Unlocks.unlocked(p))
	var j = _wave_journey(f, p)
	var sim := FakeSim.new()
	sim._waves_released = 11
	j.note_waves(sim)
	j.died()
	ctx.check("AC5 a goblin_waves run ending at 11 cleared does not unlock", not Unlocks.unlocked(p))
	var p2 = Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())), f.rules, f.camp)
	var j2 = _wave_journey(f, p2)
	var sim2 := FakeSim.new()
	sim2._waves_released = 12
	j2.note_waves(sim2)
	j2.died()
	ctx.check("AC5 a goblin_waves run with 12 cleared unlocks", Unlocks.unlocked(p2) and j2.cleared_wave() == 12)

	# 6. tutorial_step order, skip, replay.
	var t = Profile.new_player(f.rules, f.camp, F.rng(9))
	ctx.check("AC6 out-of-order step refused, step unchanged", _cmd(f, t, {"type": "tutorial_step", "step": "alliance"}) == "invalid_step" and t.tutorial["step"] == "")
	ctx.check("AC6 the next step is accepted", _cmd(f, t, {"type": "tutorial_step", "step": "welcome"}) == "ok" and t.tutorial["step"] == "race_ss_card")
	_cmd(f, t, {"type": "card_race", "class": "sword_shield", "race": "human"})
	ctx.check("AC6 steps of a card that has a race are passed", _cmd(f, t, {"type": "tutorial_step", "step": "race_ss_card"}) == "ok" and t.tutorial["step"] == "race_gs_card")
	ctx.check("AC6 skip_tour refused outside the tour", _cmd(f, t, {"type": "tutorial_step", "step": "skip_tour"}) == "invalid_step")
	ctx.check("AC6 replay refused before the tour", _cmd(f, t, {"type": "tutorial_replay"}) != "ok")
	_cmd(f, t, {"type": "card_race", "class": "greatsword", "race": "viking"})
	_cmd(f, t, {"type": "card_race", "class": "longbow", "race": "elf"})
	for id in ["race_gs_card", "alliance", "fight", "battle_tip"]:
		_cmd(f, t, {"type": "tutorial_step", "step": id})
	ctx.check("AC6 walked to the tour %s" % [t.tutorial], t.tutorial["step"] == "tour_equip")
	ctx.check("AC6 skip_tour sets tour_done", _cmd(f, t, {"type": "tutorial_step", "step": "skip_tour"}) == "ok" and t.tutorial["tour_done"] and t.tutorial["step"] == "done")
	var deck_before: Dictionary = t.card_deck.duplicate(true)
	ctx.check("AC6 replay resets the tour fields only", _cmd(f, t, {"type": "tutorial_replay"}) == "ok" and t.tutorial["step"] == "tour_equip" and not t.tutorial["tour_done"] and t.card_deck == deck_before)
	t.unlocks["magic_runeborn"] = true
	t.tutorial["step"] = "done"
	ctx.check("AC6 the unlock steps open once unlocked", Tutorial.current(t) == "unlock_ceremony")
	ctx.check("AC6 the profile runner allows the tutorial commands", Runner.ALLOWED.has("tutorial_step") and Runner.ALLOWED.has("tutorial_replay"))

	# 7 (data part). steps.json loads and is sound.
	ctx.check("AC7 steps.json version 1", Tutorial.version() == 1)
	ctx.check("AC7 steps.json has no problems %s" % [Tutorial.problems(Tutorial.data())], Tutorial.problems(Tutorial.data()).is_empty())
	ctx.check("AC7 each race card has 3 steps", ["ss", "gs", "lb"].all(func(k): return Tutorial.index_of("race_%s_card" % k) >= 0 and Tutorial.index_of("race_%s_button" % k) >= 0 and Tutorial.index_of("race_%s_pick" % k) >= 0))
	ctx.check("AC7 the unlock journey is a real journey file", JourneyData.load_by_id(Unlocks.unlock_journey(), f.combat.enemies.keys()).id == Unlocks.unlock_journey())

	# 9. Online rooms refused before battle_tip.
	var fresh = Profile.new_player(f.rules, f.camp, F.rng(11))
	_cmd(f, fresh, {"type": "card_race", "class": "sword_shield", "race": "human"})
	_cmd(f, fresh, {"type": "card_race", "class": "greatsword", "race": "viking"})
	_cmd(f, fresh, {"type": "card_race", "class": "longbow", "race": "elf"})
	_cmd(f, fresh, {"type": "card_squad", "squad": ["sword_shield", "greatsword", "longbow"]})
	var lobby: Dictionary = mgr.create("tutorialroomguard1", 6, [{"id": 1, "profile": fresh.to_dict()}], true, 2)
	ctx.check("AC9 a shared room is refused with tutorial", lobby.get("error") == "tutorial")
	ctx.check("AC9 not past battle_tip", not Tutorial.past(fresh, "battle_tip"))
	fresh.tutorial["step"] = "tour_equip"
	ctx.check("AC9 past battle_tip after the fight steps", Tutorial.past(fresh, "battle_tip"))
	var lobby2: Dictionary = mgr.create("tutorialroomguard2", 6, [{"id": 1, "profile": fresh.to_dict()}], true, 2)
	ctx.check("AC9 the room is not refused after battle_tip %s" % [lobby2], lobby2.get("error", "") != "tutorial")


func _cmd(f: Dictionary, p, command: Dictionary) -> String:
	var result: Dictionary = Commands.apply({"profile": p, "rules": f.rules, "camp": f.camp, "location": "camp", "cosmetics": f.cosmetics}, command, F.rng(1))
	return "ok" if result.get("ok", false) else str(result.get("error", ""))


func _wave_journey(f: Dictionary, p):
	var data = JourneyData.load_by_id("goblin_waves", f.combat.enemies.keys())
	var trip = preload("res://logic/run.gd").start(p, f.camp)
	return Journey.start(data, SquadMember.make_squad(trip, ["longbow"])[0], f.rules, f.loot, f.combat.weapon_ids, 77)
