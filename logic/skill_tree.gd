extends RefCounted
## A card's learned skill tree (design/gdd/skill-tree.md 3.2, 3.3, 3.11, 5): what it owns, its points, and the rules that
## learn / confirm a draft / reset / repair it. Pure rules on plain data; the server runs them through logic/commands.gd
## (tree_learn, tree_save, tree_reset_class, tree_reset_race) and card_race resets the race + combo branches for free.
## Stored on the card (logic/card_deck.gd): card["skill_tree"] = {"class": [ids], "race": [ids], "combo": [ids]}. A card
## without it owns nothing (older saves stay valid). Node data comes from logic/skill_tree_data.gd; no node or skill id is
## named in code.
## Drafts (3.3) live on the client: check_draft() previews them with the same rules the server uses in save().

const TreeData := preload("res://logic/skill_tree_data.gd")
const CardProgress := preload("res://logic/card_progress.gd")
const TREE := "skill_tree"
const BRANCHES: Array[String] = ["class", "race", "combo"]

## Rejection reasons (GDD 5): unknown_node, not_enough_points, gate_not_met, exclusive_conflict, combo_mismatch,
## in_run (commands.gd), already_learned, confirmed_removed, nothing_to_reset, cannot_afford, invalid_card, bad_tree.


static func empty() -> Dictionary:
	return {"class": [], "race": [], "combo": []}


## The card's owned nodes {"class", "race", "combo"} (a copy; empty for a card that never learned any).
static func owned(deck: Dictionary, class_id: String) -> Dictionary:
	var card = deck.get("cards", {}).get(class_id)
	var saved = card.get(TREE) if card is Dictionary else null
	var out := empty()
	if saved is Dictionary:
		for branch in BRANCHES:
			if saved.get(branch) is Array:
				out[branch] = (saved[branch] as Array).map(func(id): return str(id))
	return out


static func race_of(deck: Dictionary, class_id: String) -> String:
	return preload("res://logic/card_deck.gd").race_of(deck, class_id)


## Points spent per branch {"class", "race", "combo", "total"}.
static func spent(tree: Dictionary, data = null) -> Dictionary:
	data = data if data != null else TreeData.load_default()
	var out := {"class": 0, "race": 0, "combo": 0, "total": 0}
	for branch in BRANCHES:
		for id in tree.get(branch, []):
			out[branch] += int(data.node(str(id)).get("cost", 0))
	out["total"] = out["class"] + out["race"] + out["combo"]
	return out


## What the Skills tab shows for a card: {"class", "race", "combo" (owned ids), "spent": {...}, "earned", "free",
## "level", "race_id", "reset_class_gold"}.
static func state(deck: Dictionary, class_id: String, data = null) -> Dictionary:
	data = data if data != null else TreeData.load_default()
	var tree := owned(deck, class_id)
	var used := spent(tree, data)
	var earned := CardProgress.points_of(deck, class_id)
	var out := tree.duplicate(true)
	out["spent"] = used
	out["earned"] = earned
	out["free"] = earned - int(used["total"])
	out["level"] = CardProgress.level_of(deck, class_id)
	out["race_id"] = race_of(deck, class_id)
	out["reset_class_gold"] = int(used["class"]) * data.class_reset_gold_per_point()
	return out


## "" when `tree` is a valid tree for this class x race with `points` to spend, else the first reason (GDD 3.3):
## every id is a node of this card's class / race / combo, cost <= points, each tier's gate is met by points in EARLIER
## tiers of its branch, at most one node per OR pair, the combo only with its pair and its class + race gates.
static func check(tree: Variant, class_id: String, race_id: String, points: int, data = null) -> String:
	data = data if data != null else TreeData.load_default()
	if not tree is Dictionary:
		return "bad_tree"
	for branch in BRANCHES:
		if not tree.get(branch, []) is Array:
			return "bad_tree"
	var seen := {}
	var per_tier := {"class": {}, "race": {}}
	var pairs := {}
	for branch in BRANCHES:
		for id in tree.get(branch, []):
			if not id is String or seen.has(id):
				return "bad_tree" if not id is String else "already_learned"
			seen[id] = true
			var problem := _belongs(data, id, branch, class_id, race_id)
			if not problem.is_empty():
				return problem
			var n: Dictionary = data.node(id)
			if branch != "combo":
				per_tier[branch][int(n["tier"])] = int(per_tier[branch].get(int(n["tier"]), 0)) + int(n["cost"])
			var excl := str(n["excl"])
			if not excl.is_empty():
				if pairs.has(excl):
					return "exclusive_conflict"
				pairs[excl] = id
	for branch in ["class", "race"]:
		for id in tree.get(branch, []):
			var tier := int(data.node(id)["tier"])
			var before := 0
			for t in per_tier[branch]:
				if int(t) < tier:
					before += int(per_tier[branch][t])
			if before < int(data.tier_rule(branch, tier).get("gate", 0)):
				return "gate_not_met"
	var used := spent(tree, data)
	if not (tree.get("combo", []) as Array).is_empty():
		if (tree["combo"] as Array).size() > 1:
			return "combo_mismatch"
		var combo: Dictionary = data.combo_rule()
		if int(used["class"]) < int(combo["class_gate"]) or int(used["race"]) < int(combo["race_gate"]):
			return "gate_not_met"
	if int(used["total"]) > points:
		return "not_enough_points"
	return ""


static func _belongs(data, id: String, branch: String, class_id: String, race_id: String) -> String:
	var entry: Dictionary = data.by_id.get(id, {})
	if entry.is_empty():
		return "unknown_node"
	if str(entry["branch"]) != branch:
		return "unknown_node"
	match branch:
		"class":
			return "" if str(entry["owner"]) == class_id else "unknown_node"
		"race":
			return "" if str(entry["owner"]) == race_id else "unknown_node"
		_:
			return "" if str(entry["owner"]) == race_id and str(entry["class"]) == class_id else "combo_mismatch"
	return ""


## Client preview of a draft (3.3): the same check the server runs in save(), plus "confirmed nodes stay".
static func check_draft(deck: Dictionary, class_id: String, draft: Variant, data = null) -> String:
	if not draft is Dictionary:
		return "bad_tree"
	var current := owned(deck, class_id)
	for branch in BRANCHES:
		for id in current[branch]:
			if not draft.get(branch, []) is Array or not (draft.get(branch, []) as Array).has(id):
				return "confirmed_removed"
	return check(draft, class_id, race_of(deck, class_id), CardProgress.points_of(deck, class_id), data)


## Draft helpers for the client (free, nothing saved): a draft with one more / one less node. {} when not allowed.
static func draft_learn(draft: Dictionary, node_id: String, data = null) -> Dictionary:
	data = data if data != null else TreeData.load_default()
	var branch: String = data.branch_of(node_id)
	if branch.is_empty() or (draft.get(branch, []) as Array).has(node_id):
		return {}
	var next := draft.duplicate(true)
	next[branch].append(node_id)
	return next


static func draft_unlearn(deck: Dictionary, class_id: String, draft: Dictionary, node_id: String, data = null) -> Dictionary:
	data = data if data != null else TreeData.load_default()
	var branch: String = data.branch_of(node_id)
	if branch.is_empty() or not (draft.get(branch, []) as Array).has(node_id) or owned(deck, class_id)[branch].has(node_id):
		return {}  # only draft nodes come off; a confirmed node needs a branch reset
	var next := draft.duplicate(true)
	next[branch].erase(node_id)
	return next


## Server: learns one node now. {"ok", "reason"?}.
static func learn(deck: Dictionary, class_id: String, node_id: String, data = null) -> Dictionary:
	data = data if data != null else TreeData.load_default()
	if not deck.get("cards", {}).has(class_id):
		return {"ok": false, "reason": "invalid_card"}
	var branch: String = data.branch_of(node_id)
	if branch.is_empty():
		return {"ok": false, "reason": "unknown_node"}
	var tree := owned(deck, class_id)
	if (tree[branch] as Array).has(node_id):
		return {"ok": false, "reason": "already_learned"}
	tree[branch].append(node_id)
	var problem := check(tree, class_id, race_of(deck, class_id), CardProgress.points_of(deck, class_id), data)
	if not problem.is_empty():
		return {"ok": false, "reason": problem}
	deck["cards"][class_id][TREE] = tree
	return {"ok": true, "node": node_id}


## Server: confirms a whole draft (3.3, one command): saved as a whole or rejected as a whole. Confirmed nodes stay.
static func save(deck: Dictionary, class_id: String, draft: Variant, data = null) -> Dictionary:
	data = data if data != null else TreeData.load_default()
	if not deck.get("cards", {}).has(class_id):
		return {"ok": false, "reason": "invalid_card"}
	var problem := check_draft(deck, class_id, draft, data)
	if not problem.is_empty():
		return {"ok": false, "reason": problem}
	var clean := empty()
	for branch in BRANCHES:
		clean[branch] = (draft.get(branch, []) as Array).duplicate()
	deck["cards"][class_id][TREE] = clean
	return {"ok": true}


## Server: class branch reset (3.3). Costs class_reset_gold_per_point x refunded class points, taken from `gold_holder`
## (an object with a `gold` property: the profile stash). The combo goes too (its gate needs class points), not charged.
static func reset_class(deck: Dictionary, class_id: String, gold_holder, data = null) -> Dictionary:
	data = data if data != null else TreeData.load_default()
	if not deck.get("cards", {}).has(class_id):
		return {"ok": false, "reason": "invalid_card"}
	var tree := owned(deck, class_id)
	if (tree["class"] as Array).is_empty():
		return {"ok": false, "reason": "nothing_to_reset"}
	var cost: int = int(spent(tree, data)["class"]) * int(data.class_reset_gold_per_point())
	if int(gold_holder.gold) < cost:
		return {"ok": false, "reason": "cannot_afford"}
	gold_holder.gold -= cost
	var refunded := int(spent(tree, data)["class"]) + int(spent(tree, data)["combo"])
	tree["class"] = []
	tree["combo"] = []
	deck["cards"][class_id][TREE] = tree
	return {"ok": true, "gold": cost, "refunded": refunded}


## Server: race branch reset (3.3): free, takes the combo with it.
static func reset_race(deck: Dictionary, class_id: String, data = null) -> Dictionary:
	data = data if data != null else TreeData.load_default()
	if not deck.get("cards", {}).has(class_id):
		return {"ok": false, "reason": "invalid_card"}
	var tree := owned(deck, class_id)
	if (tree["race"] as Array).is_empty() and (tree["combo"] as Array).is_empty():
		return {"ok": false, "reason": "nothing_to_reset"}
	var refunded := int(spent(tree, data)["race"]) + int(spent(tree, data)["combo"])
	tree["race"] = []
	tree["combo"] = []
	deck["cards"][class_id][TREE] = tree
	return {"ok": true, "gold": 0, "refunded": refunded}


## Race change side effect (3.11): race + combo branches cleared and refunded, class kept. Returns points refunded.
static func on_race_change(deck: Dictionary, class_id: String, data = null) -> int:
	var card = deck.get("cards", {}).get(class_id)
	if not card is Dictionary or not card.has(TREE):
		return 0
	var result := reset_race(deck, class_id, data)
	return int(result.get("refunded", 0))


## Repair on load (GDD 5): unknown ids dropped; a tree no longer valid (data changed, race file removed, fewer points)
## keeps the nodes it can, in order lowest tier first then id, so the deepest invalid tiers are refunded first.
static func repaired(tree: Variant, class_id: String, race_id: String, points: int, data = null) -> Dictionary:
	data = data if data != null else TreeData.load_default()
	var wanted: Array = []
	if tree is Dictionary:
		for branch in BRANCHES:
			if tree.get(branch) is Array:
				for id in tree[branch]:
					if id is String and data.branch_of(id) == branch:
						wanted.append(id)
	wanted.sort_custom(func(a, b): return _order(data, a) < _order(data, b))
	var kept := empty()
	for id in wanted:
		var branch: String = data.branch_of(id)
		if (kept[branch] as Array).has(id):
			continue
		kept[branch].append(id)
		if not check(kept, class_id, race_id, points, data).is_empty():
			kept[branch].erase(id)
	var out := empty()  # the saved order stays (a clean tree loads back identical)
	for branch in BRANCHES:
		for id in (tree[branch] if tree is Dictionary and tree.get(branch) is Array else []):
			if (kept[branch] as Array).has(id) and not (out[branch] as Array).has(id):
				out[branch].append(id)
	return out


static func _order(data, id: String) -> Array:
	var branch: String = data.branch_of(id)
	return [1 if branch == "combo" else 0, int(data.node(id).get("tier", 0)), id]


## The server command entry (logic/commands.gd, camp only): tree_learn {card, node}, tree_save {card, draft},
## tree_reset_class {card} (gold from the stash), tree_reset_race {card}. Ownership: the card must be one of the profile's.
static func apply_command(profile, command: Dictionary, data = null) -> Dictionary:
	var card := str(command.get("card", ""))
	if card.is_empty() or not profile.card_deck.get("cards", {}).has(card):
		return {"ok": false, "reason": "invalid_card"}
	match str(command.get("type", "")):
		"tree_learn":
			return learn(profile.card_deck, card, str(command.get("node", "")), data)
		"tree_save":
			return save(profile.card_deck, card, command.get("draft"), data)
		"tree_reset_class":
			return reset_class(profile.card_deck, card, profile.stash, data)
		"tree_reset_race":
			return reset_race(profile.card_deck, card, data)
	return {"ok": false, "reason": "invalid_command"}


## The old per-run tree (v1 skill_build {v, start, allocated, skills[{skill, shape, effect}]}) becomes card levels
## (design/gdd/skill-tree.md 5, PO default 2026-11-13 / OPEN Q3 A). For each card with an old build: n = old allocated
## nodes not counting the free start node (0..max_points), card level = max(level, 1 + n) with xp 0, an empty v2 tree,
## and the old build keeps only its start node and its skills with no gems (the old passives and gems are dropped, so
## the effort is not counted twice). No gold comes back: the old system never charged gold for gems (only reskill_gold
## for a reset, which bought nothing that still exists). The caller runs this once (Profile.tree_migration_version).
## Returns {card: {"old_nodes": n, "level": new level}} for the cards that had an old build.
const OLD_MAX_POINTS := 12  ## the deleted skill-build system's max_points (was data/skill_system/integration.json)


static func migrate_old_builds(old_builds: Dictionary, deck: Dictionary) -> Dictionary:
	var report := {}
	var max_points := OLD_MAX_POINTS
	for card in old_builds:
		var build = old_builds[card]
		var entry = deck.get("cards", {}).get(card)
		if not build is Dictionary or not entry is Dictionary:
			continue
		var start := "start_" + str(build.get("start", ""))
		var allocated: Array = build.get("allocated", []) if build.get("allocated") is Array else []
		var n := clampi(allocated.filter(func(id): return str(id) != start).size(), 0, max_points)
		var level := maxi(CardProgress.level_of(deck, str(card)), mini(1 + n, CardProgress.max_level()))
		if level > CardProgress.level_of(deck, str(card)):
			entry[CardProgress.PROGRESS] = {"level": level, "xp": 0}
		if not entry.has(TREE):
			entry[TREE] = empty()
		if not str(build.get("start", "")).is_empty():
			build["allocated"] = [start]
		if build.get("skills") is Array:
			for row in build["skills"]:
				if row is Dictionary:
					row["shape"] = ""
					row["effect"] = ""
		report[str(card)] = {"old_nodes": n, "level": level}
	return report
