extends RefCounted
## Skill tree data (design/gdd/skill-tree.md 3.1, 3.4, 3.5, 3.8-3.10; acceptance 1, 8, 9): every class and race tree loads,
## node ids match the art manifest (112), bad data is a load error, a new class/race works with zero code changes, and no
## max-level budget holds both branch capstones.
const TreeData := preload("res://logic/skill_tree_data.gd")
const RaceData := preload("res://logic/race_data.gd")
const Progress := preload("res://logic/card_progress.gd")
const MANIFEST := "res://art/ui/skill_tree/manifest.json"
const FIXTURE := "user://test_skill_tree_fixture/"


func run(ctx) -> void:
	_game_data(ctx)
	_bad_data(ctx)
	_new_class_and_race(ctx)
	_budget(ctx)


func _game_data(ctx) -> void:
	var data = TreeData.load_default()
	ctx.check("skill tree data loads without errors %s" % [data.errors], data.errors.is_empty())
	ctx.check("every race has a combo for every class (no warnings) %s" % [data.warnings], data.warnings.is_empty())
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))["nodes"]
	var ids: Array = data.by_id.keys()
	ids.sort()
	var art: Array = manifest.keys()
	art.sort()
	ctx.check("the 112 node ids are the art manifest's ids", ids.size() == 112 and ids == art)
	var names_match := true
	var icons_exist := true
	for id in ids:
		# names: class-skills.md 3.6 renamed the class nodes; the art manifest keeps the old names until new icons come
		names_match = names_match and (str(data.node(id)["name"]) == str(manifest[id]["name"]) or str(manifest[id].get("branch", "")) == "class") and str(data.node(id)["icon"]) == str(manifest[id]["icon"])
		icons_exist = icons_exist and ResourceLoader.exists(str(data.node(id)["icon"]))
	ctx.check("node names and icons match the manifest", names_match)
	ctx.check("every node icon exists", icons_exist)
	for class_id in ["sword_shield", "greatsword", "longbow", "magic"]:
		for race_id in ["human", "viking", "elf", "runeborn"]:
			var tree_size: int = data.class_nodes(class_id).size() + data.race_nodes(race_id).size() + (1 if not data.combo_node(race_id, class_id).is_empty() else 0)
			if tree_size != 25:
				ctx.check("%s x %s tree has 25 nodes (%d)" % [class_id, race_id, tree_size], false)
	ctx.check("each card's tree is 16 class + 8 race + 1 combo", data.class_nodes("magic").size() == 16 and data.race_nodes("elf").size() == 8 and data.combo_node("elf", "magic")["id"] == "combo_el_mg")
	ctx.check("branches resolve by id", data.branch_of("ss_t4_b") == "class" and data.branch_of("rb_7") == "race" and data.branch_of("combo_hu_lb") == "combo" and data.branch_of("nope") == "")
	ctx.check("gates are class 0/3/8/13 and race 0/2/6/8, combo class 8 + race 6", data.tiers("class").map(func(r): return int(r["gate"])) == [0, 3, 8, 13] and data.tiers("race").map(func(r): return int(r["gate"])) == [0, 2, 6, 8] and int(data.combo_rule()["class_gate"]) == 8 and int(data.combo_rule()["race_gate"]) == 6)
	ctx.check("class reset is 50 gold per point (PO default)", data.class_reset_gold_per_point() == 50)
	ctx.check("every class lists 4 different skills of its own", data.classes.keys().all(func(c): return data.class_skills(c).size() == 4))


## Copies the game's class and race files into the fixture, applying `edit` (Callable(files: Dictionary)) first.
func _fixture(edit: Callable):
	var files := {}
	for folder in ["res://data/classes/", "res://data/races/"]:
		for file in DirAccess.get_files_at(folder):
			if file.ends_with(".json"):
				files[folder.get_slice("/", 3) + "/" + file] = JSON.parse_string(FileAccess.get_file_as_string(folder + file))
	files["rules"] = JSON.parse_string(FileAccess.get_file_as_string(TreeData.RULES_FILE))
	edit.call(files)
	for sub in ["classes", "races"]:
		DirAccess.make_dir_recursive_absolute(FIXTURE + sub)
		for old in DirAccess.get_files_at(FIXTURE + sub):
			DirAccess.remove_absolute(FIXTURE + sub + "/" + old)
	for key in files:
		var path: String = FIXTURE + ("rules.json" if key == "rules" else key)
		var out := FileAccess.open(path, FileAccess.WRITE)
		out.store_string(JSON.stringify(files[key]))
		out.close()
	var class_ids: Array = files.keys().filter(func(k): return str(k).begins_with("classes/")).map(func(k): return str(k).get_file().get_basename())
	var races = RaceData.load_from(FIXTURE + "races/", [], class_ids)
	return TreeData.load_from(FIXTURE + "classes/", FIXTURE + "races/", FIXTURE + "rules.json", races)


func _class_node(files: Dictionary, class_id: String, node_id: String) -> Dictionary:
	for n in files["classes/%s.json" % class_id]["skill_tree"]["nodes"]:
		if n["id"] == node_id:
			return n
	return {}


func _bad_data(ctx) -> void:
	var sound = _fixture(func(_f): pass)
	ctx.check("an unchanged fixture loads %s" % [sound.errors], sound.errors.is_empty())
	var cases := {
		"a node with an unknown effect type": func(f): _class_node(f, "magic", "mg_t1_ring")["effects"] = [{"type": "teleport"}],
		"a node with an unknown event": func(f): _class_node(f, "magic", "mg_t3_b")["effects"][0]["on"] = "sneeze",
		"a node with an unknown action": func(f): _class_node(f, "greatsword", "gs_t3_b")["effects"][0]["actions"][0]["action"] = "yeet",
		"a node with an unknown status": func(f): _class_node(f, "greatsword", "gs_t3_b")["effects"][0]["actions"][0]["status"] = "giggles",
		"a node with an unknown stat": func(f): _class_node(f, "sword_shield", "ss_t4_b")["effects"][0]["stat"] = "LUCK",
		"a skill_upgrade of another class's skill": func(f): _class_node(f, "magic", "mg_t1_fireball")["effects"][0]["skill"] = f["classes/greatsword.json"]["skill_tree"]["skills"][0],
		"an unknown mechanic": func(f): _class_node(f, "magic", "mg_t3_a")["effects"][0]["id"] = "win_game",
		"an unknown cell_mod field": func(f): f["races/human.json"]["skill_tree"]["nodes"][0]["effects"][0]["power"] = 9.0,
		"a wrong cost for the tier": func(f): _class_node(f, "longbow", "lb_t1_trap")["cost"] = 2,
		"a tier with one node too many": func(f): _class_node(f, "longbow", "lb_t3_a")["tier"] = 1,
		"an OR pair of 1 node": func(f): _class_node(f, "longbow", "lb_t2_chain_b")["excl"] = "lb_lonely",
		"an OR pair of 3 nodes": func(f): _class_node(f, "longbow", "lb_t2_chain_b")["excl"] = "lb_pierce",
		"a free node in an exclusive tier": func(f): _class_node(f, "longbow", "lb_t4_a")["excl"] = "",
		"a node id used twice": func(f): _class_node(f, "longbow", "lb_t1_lance")["id"] = "lb_t1_chain",
		"a combo with the wrong cost": func(f): f["races/elf.json"]["skill_tree"]["combo"]["magic"]["cost"] = 1,
		"a class without a skill_tree": func(f): f["classes/magic.json"].erase("skill_tree"),
		"gates that go down": func(f): f["rules"]["branches"]["race"][2]["gate"] = 1,
	}
	for what in cases:
		var data = _fixture(cases[what])
		ctx.check("%s is a load error" % what, not data.errors.is_empty())


## Acceptance 8: a new race (8 nodes + combos) and a new class (16 nodes) need data only.
func _new_class_and_race(ctx) -> void:
	var data = _fixture(func(f):
		var cls: Dictionary = f["classes/sword_shield.json"].duplicate(true)
		cls["id"] = "testclass"
		for n in cls["skill_tree"]["nodes"]:
			n["id"] = "tc_" + str(n["id"])
		f["classes/testclass.json"] = cls
		var race: Dictionary = f["races/human.json"].duplicate(true)
		race["id"] = "testrace"
		for n in race["skill_tree"]["nodes"]:
			n["id"] = "tr_" + str(n["id"])
		for class_id in race["skill_tree"]["combo"]:
			race["skill_tree"]["combo"][class_id]["id"] = "tr_" + str(race["skill_tree"]["combo"][class_id]["id"])
		race["skill_tree"]["combo"]["testclass"] = race["skill_tree"]["combo"]["sword_shield"].duplicate(true)
		race["skill_tree"]["combo"]["testclass"]["id"] = "tr_combo_testclass"
		f["races/testrace.json"] = race)
	ctx.check("a new class and race load with zero code changes %s" % [data.errors], data.errors.is_empty() and data.class_nodes("testclass").size() == 16 and data.race_nodes("testrace").size() == 8 and data.combo_node("testrace", "testclass")["id"] == "tr_combo_testclass")
	ctx.check("other races without a combo for the new class only warn", data.warnings.any(func(w): return "no combo for class testclass" in w))


## Every sum of points a branch can have spent, honouring tier gates (points in earlier tiers) and OR pairs.
func _reachable(data, branch: String, nodes: Array, up_to_tier: int) -> Array:
	var sums := {0: true}
	for rule in data.tiers(branch):
		var tier := int(rule["tier"])
		if tier > up_to_tier:
			break
		var options := {0: true}  # point totals one tier can add
		var groups := {}
		for n in nodes.filter(func(x): return int(x["tier"]) == tier):
			var key: String = str(n["excl"]) if not str(n["excl"]).is_empty() else str(n["id"])
			groups[key] = int(n["cost"])
		for key in groups:
			var grown := options.duplicate()
			for have in options:
				grown[int(have) + int(groups[key])] = true
			options = grown
		var next := {}
		for have in sums:
			next[have] = true
			if int(have) >= int(rule["gate"]):
				for add in options:
					next[int(have) + int(add)] = true
		sums = next
	return sums.keys()


## The fewest points that reach a branch's capstone tier (gate met with earlier tiers) plus the capstone.
func _capstone_cost(data, branch: String, nodes: Array) -> int:
	var last: Dictionary = data.tiers(branch)[-1]
	var spent: Array = _reachable(data, branch, nodes, int(last["tier"]) - 1).filter(func(s): return int(s) >= int(last["gate"]))
	return int(spent.min()) + int(last["cost"])


func _budget(ctx) -> void:
	var data = TreeData.load_default()
	var budget := Progress.points(Progress.max_level())
	var combo: Dictionary = data.combo_rule()
	var ok := true
	var detail := []
	for class_id in data.classes:
		var class_cap := _capstone_cost(data, "class", data.class_nodes(class_id))
		var class_for_combo: int = _reachable(data, "class", data.class_nodes(class_id), 4).filter(func(s): return int(s) >= int(combo["class_gate"])).min()
		for race_id in data.races:
			var race_cap := _capstone_cost(data, "race", data.race_nodes(race_id))
			var race_for_combo: int = _reachable(data, "race", data.race_nodes(race_id), 4).filter(func(s): return int(s) >= int(combo["race_gate"])).min()
			var both_caps := class_cap + race_cap
			var class_route := class_cap + maxi(race_for_combo, 0) + int(combo["cost"])  # the class cap already has class >= 8
			var race_route := race_cap + class_for_combo + int(combo["cost"])
			detail.append([class_id, race_id, class_cap, race_cap, class_route, race_route])
			ok = ok and both_caps > budget and class_route <= budget and race_route <= budget
	ctx.check("4.4: the class capstone costs 16 and the race capstone 11", _capstone_cost(data, "class", data.class_nodes("sword_shield")) == 16 and _capstone_cost(data, "race", data.race_nodes("human")) == 11)
	ctx.check("4.4: no %d-point build holds both branch capstones, and each capstone + combo fits %s" % [budget, detail.slice(0, 2)], ok)
