extends SceneTree
## Correctness only; native timing is not evidence for browser performance.
func _initialize() -> void:
	var source = preload("res://data/perf/scenario.gd").new()
	var original: Dictionary = source.profile.to_dict().duplicate(true)
	var copied = preload("res://logic/profile.gd").from_dict(original.duplicate(true), source.rules, source.camp)
	assert(copied != null and copied != source.profile)
	var loot = preload("res://logic/loot_data_loader.gd").load_default(source.camp.materials.keys(), source.rules.tiers.size())
	var session = preload("res://client/session/local_session.gd").new(copied, source.rules, source.camp, loot)
	var combat = preload("res://logic/combat_data_loader.gd").load_default()
	session.begin_stage(source.map, combat)
	for i in range(120): session.step(source.input_at(i))
	copied.name = "LOCAL COPY ONLY"
	copied.appearance["diagnostic"] = true
	assert(source.profile.to_dict() == original)
	assert(session.tick_count == 120)
	assert(not session.fighters.is_empty())
	print("LOCAL PERF ISOLATION PASS: clone independent; local simulation 120 ticks; no account transport")
	quit()
