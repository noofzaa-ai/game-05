extends RefCounted
## The named game states of tools/localstack/fixtures/ (Boss 2026-11-16: jump to a state instead of playing to it)
## stay valid: each one, merged into a new player's saved profile the way tools/localstack/fixture.py merges it,
## loads back through Profile.from_dict and lands the state its name promises.
const Profile := preload("res://logic/profile.gd")
const Tutorial := preload("res://logic/tutorial.gd")
const Unlocks := preload("res://logic/unlocks.gd")
const Zones := preload("res://logic/world_zones.gd")
const F := preload("res://tests/online_fixture.gd")
const DIR := "res://tools/localstack/fixtures/"


static func merge(base: Dictionary, patch: Dictionary) -> Dictionary:
	for k in patch:
		if str(k).begins_with("_"):
			continue
		if patch[k] is Dictionary and base.get(k) is Dictionary:
			merge(base[k], patch[k])
		else:
			base[k] = patch[k]
	return base


func run(ctx) -> void:
	var f := F.make()
	var loaded := {}
	for file in DirAccess.get_files_at(DIR):
		if not file.ends_with(".json"):
			continue
		var patch = JSON.parse_string(FileAccess.get_file_as_string(DIR + file))
		ctx.check("fixture %s parses" % file, patch is Dictionary)
		if not patch is Dictionary:
			continue
		var saved: Dictionary = JSON.parse_string(JSON.stringify(Profile.new_player(f.rules, f.camp, F.rng(9)).to_dict()))
		for key in patch.get("_remove", []):
			saved.erase(str(key))
		merge(saved, patch)
		var p = Profile.from_dict(saved, f.rules, f.camp)
		ctx.check("fixture %s loads as a profile" % file, p != null)
		loaded[file.get_basename()] = p
	ctx.check("the six named states exist", loaded.has_all(["new_player", "tutorial_alliance", "tutorial_tour", "unlock_ceremony", "veteran", "old_account"]))
	if loaded.size() < 6 or loaded.values().has(null):
		return
	ctx.check("new_player starts the tutorial", Tutorial.current(loaded.new_player) == "welcome")
	ctx.check("tutorial_alliance waits on alliance with a 3-card squad", Tutorial.current(loaded.tutorial_alliance) == "alliance" and loaded.tutorial_alliance.card_deck.squad.size() == 3)
	ctx.check("tutorial_tour is on the Equipment tour step", Tutorial.current(loaded.tutorial_tour) == "tour_equip")
	ctx.check("unlock_ceremony shows the ceremony", Tutorial.current(loaded.unlock_ceremony) == "unlock_ceremony")
	ctx.check("veteran: tutorial done, Magic unlocked, Chief beaten", Tutorial.current(loaded.veteran) == Tutorial.DONE and Unlocks.unlocked(loaded.veteran) and Zones.boss_beaten(loaded.veteran, "goblin_base"))
	ctx.check("old_account migrates to done and unlocked", Tutorial.current(loaded.old_account) == Tutorial.DONE and Unlocks.unlocked(loaded.old_account))
