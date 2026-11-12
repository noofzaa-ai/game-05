extends RefCounted
## Old saves (design/gdd/skill-tree.md 5, acceptance 5; PO default 2026-11-13): each card's old per-run tree points become
## card levels (n old nodes -> level 1 + n), gems and old passives are dropped, the v2 tree starts empty, and the
## migration runs once only.
const Profile := preload("res://logic/profile.gd")
const SkillTree := preload("res://logic/skill_tree.gd")
const Progress := preload("res://logic/card_progress.gd")
const F := preload("res://tests/online_fixture.gd")


func run(ctx) -> void:
	_migrates_once(ctx)
	_edge_cases(ctx)


## An old save: this profile written without the migration marker, the card's build holding `nodes` passives + gems.
func _old_save(f: Dictionary, card: String, nodes: int) -> Dictionary:
	var saved: Dictionary = JSON.parse_string(JSON.stringify(f.profile.to_dict()))
	saved.erase("tree_migration_version")
	var build := {"v": 1, "start": "katana", "allocated": [], "skills": [{"skill": "old_a", "shape": "", "effect": ""}]}
	saved["card_gear"][card]["skill_build"] = build  # (the save of a player from before the class skills)
	var start := "start_" + str(build["start"])
	build["allocated"] = [start]
	for i in nodes:
		build["allocated"].append("old_node_%d" % i)  # ids of the old chart (never read by the new tree)
	for row in build["skills"]:
		row["shape"] = "wide"
		row["effect"] = "bleed"
	for class_id in saved["card_deck"]["cards"]:
		saved["card_deck"]["cards"][class_id].erase("progress")
		saved["card_deck"]["cards"][class_id].erase("skill_tree")
	return saved


func _migrates_once(ctx) -> void:
	var f := F.make()
	var card := "sword_shield"
	var saved := _old_save(f, card, 7)
	var gold_before := int(saved["stash"]["gold"])
	var loaded = Profile.from_dict(saved, f.rules, f.camp)
	ctx.check("an old save loads", loaded != null)
	var state := SkillTree.state(loaded.card_deck, card)
	ctx.check("7 old nodes (+ start) -> level 8, 7 points, 0 XP %s" % [state], state["level"] == 8 and state["earned"] == 7 and state["free"] == 7 and Progress.progress_of(loaded.card_deck, card)["xp"] == 0)
	ctx.check("the v2 tree starts empty", state["class"].is_empty() and state["race"].is_empty() and state["combo"].is_empty())
	ctx.check("the old skill build itself is dropped on load (class-skills.md)", not loaded.card_gear[card].has("skill_build") and not loaded.to_dict().has("skill_build"))
	ctx.check("no gold changes hands (the old gems never cost gold)", loaded.stash.gold == gold_before)
	ctx.check("the profile is marked migrated", loaded.tree_migration_version == 2)
	ctx.check("the other cards had no old points: still level 1", Progress.level_of(loaded.card_deck, "greatsword") == 1)
	var again = Profile.from_dict(JSON.parse_string(JSON.stringify(loaded.to_dict())), f.rules, f.camp)
	ctx.check("loading again does not migrate twice", again != null and Progress.level_of(again.card_deck, card) == 8 and again.tree_migration_version == 2)
	# The marker is what stops it: a migrated save whose build still lists old nodes is left alone.
	var marked: Dictionary = _old_save(f, card, 5)
	marked["tree_migration_version"] = 2
	var kept = Profile.from_dict(marked, f.rules, f.camp)
	ctx.check("a save already marked migrated is not converted", Progress.level_of(kept.card_deck, card) == 1)


func _edge_cases(ctx) -> void:
	var f := F.make()
	ctx.check("a new player needs no migration", f.profile.tree_migration_version == 2)
	var none = Profile.from_dict(_old_save(f, "sword_shield", 0), f.rules, f.camp)
	ctx.check("an old build with only the start node stays level 1", Progress.level_of(none.card_deck, "sword_shield") == 1)
	var saved := _old_save(f, "sword_shield", 40)
	var capped = Profile.from_dict(saved, f.rules, f.camp)
	var max_points := SkillTree.OLD_MAX_POINTS
	ctx.check("old points are capped at the old max (%d) -> level %d" % [max_points, 1 + max_points], Progress.level_of(capped.card_deck, "sword_shield") == 1 + max_points)
	var levelled := _old_save(f, "sword_shield", 3)
	levelled["card_deck"]["cards"]["sword_shield"]["progress"] = {"level": 10, "xp": 50}
	var higher = Profile.from_dict(levelled, f.rules, f.camp)
	ctx.check("a card already above 1 + n keeps its level and XP", Progress.progress_of(higher.card_deck, "sword_shield") == {"level": 10, "xp": 50})
	var pre_card: Dictionary = _old_save(f, "sword_shield", 4)
	pre_card["skill_build"] = pre_card["card_gear"]["sword_shield"]["skill_build"]
	pre_card["loadout"] = pre_card["card_gear"]["sword_shield"]["loadout"]
	pre_card.erase("card_gear")
	pre_card.erase("card_deck")
	var oldest = Profile.from_dict(pre_card, f.rules, f.camp)
	ctx.check("a pre-card save (one account build) levels the Sword & Shield card", oldest != null and Progress.level_of(oldest.card_deck, "sword_shield") == 5)
