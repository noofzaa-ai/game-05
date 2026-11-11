extends RefCounted
## Explicit ID references keep the simulation checkpoint free of executable Objects.
const Codec := preload("res://logic/state_codec.gd")

static func pack_value(value):
	if value is ZorxSkillTarget: return {"$target": value.entity_id}
	if value is ZorxSkillData: return {"$skill": value.id}
	if value is Basis: return {"$basis": [value.x, value.y, value.z]}
	if value is Array: return value.map(func(entry): return pack_value(entry))
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = pack_value(value[key])
		return result
	return value

static func unpack_value(value, targets: Dictionary):
	if value is Array: return value.map(func(entry): return unpack_value(entry, targets))
	if value is Dictionary:
		if value.has("$target"): return targets.get(int(value["$target"]))
		if value.has("$skill"): return load("res://data/skill_system/skills/" + str(value["$skill"]) + ".tres")
		if value.has("$basis"): return Basis(value["$basis"][0], value["$basis"][1], value["$basis"][2])
		var result := {}
		for key in value: result[key] = unpack_value(value[key], targets)
		return result
	return value

static func capture(runtime: ZorxSkillRuntime) -> Dictionary:
	return {"runtime": pack_value(Codec.fields(runtime, ["actor", "targets", "crit_rng"])),
		"actor": pack_value(Codec.fields(runtime.actor)),
		"rng_seed": runtime.crit_rng.seed, "rng_state": runtime.crit_rng.state}

static func restore(runtime: ZorxSkillRuntime, saved: Dictionary, targets: Dictionary) -> void:
	Codec.apply_fields(runtime, unpack_value(saved.runtime, targets))
	Codec.apply_fields(runtime.actor, unpack_value(saved.actor, targets))
	runtime.crit_rng.seed = saved.rng_seed
	runtime.crit_rng.state = saved.rng_state
