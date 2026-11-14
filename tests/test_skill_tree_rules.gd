extends RefCounted
## Card skill tree rules (design/gdd/skill-tree.md 3.3, 3.11, 5; acceptance 3, 4): learn, confirm a draft, branch resets,
## race change refund, every rejection reason, repair on load, server commands (camp only, ALLOWED list). Node ids are read
## from the tree data (never named here), so a redesign of the class skills does not break these tests.
const SkillTree := preload("res://logic/skill_tree.gd")
const TreeData := preload("res://logic/skill_tree_data.gd")
const Deck := preload("res://logic/card_deck.gd")
const Progress := preload("res://logic/card_progress.gd")
const Commands := preload("res://logic/commands.gd")
const Runner := preload("res://server/profile/runner.gd")
const F := preload("res://tests/online_fixture.gd")
const CARD := "sword_shield"


func run(ctx) -> void:
	_learn_and_gates(ctx)
	_drafts(ctx)
	_resets(ctx)
	_race_change(ctx)
	_repair(ctx)
	_commands(ctx)


## The class / race / combo nodes of a card, by tier, in data order.
func _class_tier(data, tier: int) -> Array:
	return data.class_nodes(CARD).filter(func(n): return int(n["tier"]) == tier)


func _race_tier(data, race: String, tier: int) -> Array:
	return data.race_nodes(race).filter(func(n): return int(n["tier"]) == tier)


## One node per OR pair of a class tier (the first of each pair), so the pick is always legal.
func _one_per_pair(nodes: Array) -> Array:
	var seen := {}
	var out := []
	for n in nodes:
		var key: String = str(n["excl"]) if not str(n["excl"]).is_empty() else str(n["id"])
		if not seen.has(key):
			seen[key] = true
			out.append(n)
	return out


func _deck_at(level: int) -> Dictionary:
	var deck := Deck.initial()
	for c in Deck.classes(): Deck.set_race(deck, c, Deck.starter_race(c))  # tutorial.md 2: new cards are raceless
	var need := 0
	for l in range(1, level):
		need += Progress.xp_req(l)
	Progress.grant(deck, CARD, need)
	return deck


func _learn_all(deck: Dictionary, nodes: Array) -> bool:
	var ok := true
	for n in nodes:
		ok = ok and SkillTree.learn(deck, CARD, str(n["id"]))["ok"]
	return ok


func _learn_and_gates(ctx) -> void:
	var data = TreeData.load_default()
	var t1 := _class_tier(data, 1)
	var t2 := _one_per_pair(_class_tier(data, 2))
	var deck := _deck_at(1)
	ctx.check("a level-1 card has 0 points: learning fails not_enough_points", SkillTree.learn(deck, CARD, str(t1[0]["id"])) == {"ok": false, "reason": "not_enough_points"})
	deck = _deck_at(10)  # 10 points
	ctx.check("a T2 node before 3 class points: gate_not_met", SkillTree.learn(deck, CARD, str(t2[0]["id"]))["reason"] == "gate_not_met")
	ctx.check("T1 nodes learn one by one", _learn_all(deck, t1.slice(0, 3)))
	ctx.check("learning twice is refused", SkillTree.learn(deck, CARD, str(t1[0]["id"]))["reason"] == "already_learned")
	ctx.check("3 class points open T2", SkillTree.learn(deck, CARD, str(t2[0]["id"]))["ok"])
	var partner: Dictionary = _class_tier(data, 2).filter(func(n): return str(n["excl"]) == str(t2[0]["excl"]) and n["id"] != t2[0]["id"])[0]
	ctx.check("the other node of an OR pair: exclusive_conflict", SkillTree.learn(deck, CARD, str(partner["id"]))["reason"] == "exclusive_conflict")
	ctx.check("a node of another class: unknown_node", SkillTree.learn(deck, CARD, str(data.class_nodes("magic")[0]["id"]))["reason"] == "unknown_node")
	var other_race: String = data.races.keys().filter(func(r): return r != Deck.race_of(deck, CARD))[0]
	ctx.check("a node of another race: unknown_node", SkillTree.learn(deck, CARD, str(data.race_nodes(other_race)[0]["id"]))["reason"] == "unknown_node")
	ctx.check("an id that does not exist: unknown_node", SkillTree.learn(deck, CARD, "no_such_node")["reason"] == "unknown_node")
	var race := Deck.race_of(deck, CARD)
	var combo: Dictionary = data.combo_node(race, CARD)
	ctx.check("the combo before class 8 + race 6: gate_not_met", SkillTree.learn(deck, CARD, str(combo["id"]))["reason"] == "gate_not_met")
	ctx.check("another class's combo of the same race: combo_mismatch", SkillTree.learn(deck, CARD, str(data.combo_node(race, "magic")["id"]))["reason"] == "combo_mismatch")
	var state := SkillTree.state(deck, CARD)
	ctx.check("state counts points %s" % [state], state["earned"] == 10 and state["spent"]["class"] == 5 and state["free"] == 5 and state["reset_class_gold"] == 250)
	ctx.check("a deck with a learned tree is still valid", Deck.validate(deck) == "")

	# Combo: class 8 and race 6 at level 17 (17 points).
	deck = _deck_at(17)
	var class_eight: Array = t1 + t2.slice(0, 2)  # 4 + 4 = 8
	var race_six: Array = _race_tier(data, race, 1) + _race_tier(data, race, 2)  # 2 + 4 = 6
	ctx.check("class 8 + race 6 learn", _learn_all(deck, class_eight) and _learn_all(deck, race_six))
	ctx.check("then the combo learns (3 points, 17 spent)", SkillTree.learn(deck, CARD, str(combo["id"]))["ok"] and SkillTree.state(deck, CARD)["free"] == 0)
	var t3: Array = _class_tier(data, 3)
	ctx.check("with no points left: not_enough_points", SkillTree.learn(deck, CARD, str(t3[0]["id"]))["reason"] == "not_enough_points")


func _drafts(ctx) -> void:
	var data = TreeData.load_default()
	var t1 := _class_tier(data, 1)
	var deck := _deck_at(10)
	SkillTree.learn(deck, CARD, str(t1[0]["id"]))
	var draft := SkillTree.owned(deck, CARD)
	for n in t1.slice(1):
		draft = SkillTree.draft_learn(draft, str(n["id"]))
	ctx.check("a draft previews valid", SkillTree.check_draft(deck, CARD, draft) == "")
	ctx.check("a draft node can come off for free", not SkillTree.draft_unlearn(deck, CARD, draft, str(t1[1]["id"])).is_empty())
	ctx.check("a confirmed node cannot come off a draft", SkillTree.draft_unlearn(deck, CARD, draft, str(t1[0]["id"])).is_empty())
	var dropped := draft.duplicate(true)
	dropped["class"].erase(str(t1[0]["id"]))
	ctx.check("a draft dropping a confirmed node is rejected", SkillTree.save(deck, CARD, dropped)["reason"] == "confirmed_removed")
	var before := SkillTree.owned(deck, CARD)
	var bad := draft.duplicate(true)
	bad["class"].append(str(_class_tier(data, 4)[0]["id"]))
	ctx.check("a bad draft is rejected as a whole, nothing saved", SkillTree.save(deck, CARD, bad)["reason"] == "gate_not_met" and SkillTree.owned(deck, CARD) == before)
	ctx.check("a valid draft confirms in one go", SkillTree.save(deck, CARD, draft)["ok"] and SkillTree.owned(deck, CARD)["class"].size() == 4)
	var round_trip := Deck.repaired(JSON.parse_string(JSON.stringify(deck)))
	ctx.check("a confirmed tree round-trips save -> load", SkillTree.owned(round_trip, CARD) == SkillTree.owned(deck, CARD))


class Purse:
	var gold := 0


func _resets(ctx) -> void:
	var data = TreeData.load_default()
	var race := "human"
	var deck := _deck_at(17)
	Deck.set_race(deck, CARD, race)
	_learn_all(deck, _class_tier(data, 1) + _one_per_pair(_class_tier(data, 2)).slice(0, 2))
	_learn_all(deck, _race_tier(data, race, 1) + _race_tier(data, race, 2))
	SkillTree.learn(deck, CARD, str(data.combo_node(race, CARD)["id"]))
	var purse := Purse.new()
	purse.gold = 399
	ctx.check("class reset with too little gold: cannot_afford (8 points x 50)", SkillTree.reset_class(deck, CARD, purse)["reason"] == "cannot_afford" and purse.gold == 399)
	purse.gold = 1000
	var reset := SkillTree.reset_class(deck, CARD, purse)
	ctx.check("class reset charges 50 per class point, refunds class + combo %s" % [reset], reset["ok"] and reset["gold"] == 400 and purse.gold == 600 and reset["refunded"] == 11)
	ctx.check("class reset keeps the race branch", SkillTree.owned(deck, CARD)["class"].is_empty() and SkillTree.owned(deck, CARD)["combo"].is_empty() and SkillTree.owned(deck, CARD)["race"].size() == 4)
	ctx.check("nothing to reset is refused", SkillTree.reset_class(deck, CARD, purse)["reason"] == "nothing_to_reset")
	var race_reset := SkillTree.reset_race(deck, CARD)
	ctx.check("race reset is free and refunds the race points", race_reset["ok"] and race_reset["gold"] == 0 and race_reset["refunded"] == 6 and SkillTree.owned(deck, CARD)["race"].is_empty())


func _race_change(ctx) -> void:
	var data = TreeData.load_default()
	var f := F.make()
	var deck: Dictionary = f.profile.card_deck
	var need := 0
	for l in range(1, 17):
		need += Progress.xp_req(l)
	Progress.grant(deck, CARD, need)
	var race := Deck.race_of(deck, CARD)
	_learn_all(deck, _class_tier(data, 1) + _one_per_pair(_class_tier(data, 2)).slice(0, 2))
	_learn_all(deck, _race_tier(data, race, 1) + _race_tier(data, race, 2))
	SkillTree.learn(deck, CARD, str(data.combo_node(race, CARD)["id"]))
	var class_before: Array = SkillTree.owned(deck, CARD)["class"]
	var gold_before: int = f.profile.stash.gold
	var other: String = data.races.keys().filter(func(r): return r != race)[0]
	var result := Commands.apply(f, {"type": "card_race", "class": CARD, "race": other}, F.rng())
	var after := SkillTree.owned(f.profile.card_deck, CARD)
	ctx.check("card_race clears race + combo, keeps class, gold unchanged %s" % [result.get("result")], result["ok"] and after["race"].is_empty() and after["combo"].is_empty() and after["class"] == class_before and f.profile.stash.gold == gold_before)
	ctx.check("card_race reports the refunded points (6 race + 3 combo)", int(result["result"].get("tree_refunded", -1)) == 9)
	ctx.check("the new race's nodes can be learned at once", SkillTree.learn(f.profile.card_deck, CARD, str(_race_tier(data, other, 1)[0]["id"]))["ok"])


func _repair(ctx) -> void:
	var data = TreeData.load_default()
	var t1 := _class_tier(data, 1)
	var t2 := _one_per_pair(_class_tier(data, 2))
	var tree := {"class": [str(t2[0]["id"]), "gone_node", str(t1[0]["id"]), str(t1[1]["id"]), str(t1[2]["id"])], "race": [], "combo": []}
	var fixed := SkillTree.repaired(tree, CARD, "human", 26)
	ctx.check("repair drops unknown ids and keeps the valid rest", fixed["class"].size() == 4 and not fixed["class"].has("gone_node"))
	fixed = SkillTree.repaired(tree, CARD, "human", 4)
	ctx.check("with fewer points the deepest tier is refunded first", fixed["class"].size() == 3 and not fixed["class"].has(str(t2[0]["id"])))
	fixed = SkillTree.repaired({"class": [str(t2[0]["id"])], "race": [], "combo": []}, CARD, "human", 26)
	ctx.check("a node whose gate is no longer met is refunded", fixed["class"].is_empty())
	var deck := _deck_at(5)
	deck["cards"][CARD]["skill_tree"] = {"class": [str(t1[0]["id"]), "gone_node"], "race": [], "combo": []}
	var loaded := Deck.repaired(deck)
	ctx.check("deck repair on load cleans the tree and keeps the card", loaded["cards"][CARD]["skill_tree"]["class"] == [str(t1[0]["id"])] and loaded["cards"][CARD]["hair"] == deck["cards"][CARD]["hair"])
	deck["cards"][CARD]["skill_tree"] = "junk"
	ctx.check("a tree with a bad shape makes the card invalid", Deck.validate(deck) == "bad_card")


func _commands(ctx) -> void:
	var data = TreeData.load_default()
	var f := F.make()
	Progress.grant(f.profile.card_deck, CARD, 100 + 230)  # level 3: 2 points
	var node := str(_class_tier(data, 1)[0]["id"])
	var learned := Commands.apply(f, {"type": "tree_learn", "card": CARD, "node": node}, F.rng())
	ctx.check("tree_learn works at camp and reports the change", learned["ok"] and learned["changes"].has("card_deck"))
	ctx.check("tree_learn refuses a stranger's card", Commands.apply(f, {"type": "tree_learn", "card": "nope", "node": node}, F.rng())["error"] == "invalid_card")
	ctx.check("tree_learn needs its fields", Commands.apply(f, {"type": "tree_learn", "card": CARD}, F.rng())["error"] == "invalid_command")
	var in_run := f.duplicate()
	in_run["location"] = "stage"
	in_run["run"] = f.run
	ctx.check("the tree never changes during a run: in_run", Commands.apply(in_run, {"type": "tree_learn", "card": CARD, "node": str(_class_tier(data, 1)[1]["id"])}, F.rng())["error"] == "in_run")
	var draft := SkillTree.owned(f.profile.card_deck, CARD)
	draft["class"].append(str(_class_tier(data, 1)[1]["id"]))
	ctx.check("tree_save confirms a draft", Commands.apply(f, {"type": "tree_save", "card": CARD, "draft": draft}, F.rng())["ok"])
	f.profile.stash.gold = 30
	ctx.check("tree_reset_class without gold: cannot_afford", Commands.apply(f, {"type": "tree_reset_class", "card": CARD}, F.rng())["error"] == "cannot_afford")
	f.profile.stash.gold = 500
	ctx.check("tree_reset_class takes 100 gold for 2 points", Commands.apply(f, {"type": "tree_reset_class", "card": CARD}, F.rng())["ok"] and f.profile.stash.gold == 400)
	ctx.check("tree_reset_race with nothing learned: nothing_to_reset", Commands.apply(f, {"type": "tree_reset_race", "card": CARD}, F.rng())["error"] == "nothing_to_reset")
	ctx.check("the server allows the tree commands", ["tree_learn", "tree_save", "tree_reset_class", "tree_reset_race"].all(func(k): return Runner.ALLOWED.has(k)))
