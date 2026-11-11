extends RefCounted
## Tests the combat effect data (data/combat/vfx.json) and its player (client/effects.gd): every
## action the rules can produce has a look, the data is valid, and the load-time prewarm draws
## every entry so the web build never compiles an effect shader mid-fight.

const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const Effects := preload("res://client/effects.gd")
const VfxLibrary := preload("res://client/vfx/vfx_library.gd")


func run(ctx) -> void:
	var lib = VfxLibrary.load_default()
	ctx.check("vfx.json loads without errors %s" % [lib.errors], lib.is_valid())
	var data := CombatDataLoader.load_default()
	ctx.check("combat data loads", data.is_valid())

	_check_coverage(ctx, lib, data)
	_check_rules(ctx, lib)
	_check_bad_data(ctx)
	await _check_player(ctx, lib)


## Every move, skill, telegraph, dive, status and event maps to a real entry.
func _check_coverage(ctx, lib, data) -> void:
	var defaulted: Array[String] = []
	for move_id in data.moves:
		var key: String = lib.swing_key(move_id)
		if key == "swing/default" or not lib.has(key):
			defaulted.append(move_id)
	ctx.check("every move has its own swing effect (by id or kind) %s" % [defaulted], defaulted.is_empty())

	var no_skill: Array[String] = []
	for weapon_id in data.weapon_ids:
		for kind in ["special", "ultimate"]:
			if not lib.has("swing/%s_%s" % [weapon_id, kind]):
				no_skill.append("%s_%s" % [weapon_id, kind])
	ctx.check("every weapon's skill and ultimate has its own look %s" % [no_skill], no_skill.is_empty())

	var no_windup: Array[String] = []
	var no_land: Array[String] = []
	for move_id in data.moves:
		var move: Dictionary = data.moves[move_id]
		if bool(move["telegraph"]) and lib.windup_key(move_id).is_empty():
			no_windup.append(move_id)
		if float(move["dive"]) > 0.0 and lib.land_key(move_id).is_empty():
			no_land.append(move_id)
		if move_id.ends_with("_special") or move_id.ends_with("_ultimate"):
			if lib.windup_key(move_id).is_empty():
				no_windup.append(move_id)
	ctx.check("every telegraphed monster move and every skill has a wind-up effect %s" % [no_windup], no_windup.is_empty())
	ctx.check("every diving move has a landing effect %s" % [no_land], no_land.is_empty())

	var no_status: Array[String] = []
	for effect_id in data.effects:
		var effect: Dictionary = data.effects[effect_id]
		if lib.status_key(str(effect.get("control", "")), str(effect["kind"])).is_empty():
			no_status.append(effect_id)
	ctx.check("every buff/debuff has a status effect %s" % [no_status], no_status.is_empty())
	ctx.check("stun, shock and sleep have their own looks", lib.status_key("stun", "debuff") == "status/stun" and lib.status_key("sleep", "debuff") == "status/sleep" and lib.status_key("shock", "debuff") == "status/shock")

	var missing: Array[String] = []
	for key in VfxLibrary.EVENT_KEYS:
		if not lib.has(key) or lib.layers(key).is_empty():
			missing.append(key)
	ctx.check("every event the stage plays has an effect %s" % [missing], missing.is_empty())


func _check_rules(ctx, lib) -> void:
	ctx.check("move kind: the longest kind wins", VfxLibrary.move_kind("hammer_run_heavy") == "run_heavy" and VfxLibrary.move_kind("blade_air_heavy") == "air_heavy" and VfxLibrary.move_kind("fists_heavy") == "heavy")
	ctx.check("move kind: monster moves have none", VfxLibrary.move_kind("brute_slam") == "")
	ctx.check("swing key prefers the move's own entry", lib.swing_key("hammer_special") == "swing/hammer_special")
	ctx.check("swing key falls back to the kind", lib.swing_key("hammer_light_2") == "swing/light_2")
	ctx.check("swing key falls back to the default", lib.swing_key("nobody_knows") == "swing/default")
	var light: Array[String] = lib.hit_keys("fists_light_1", 0.8, false, false, false, 3.0)
	ctx.check("a light hit plays only the base hit %s" % [light], light.size() == 1 and light[0] == "hit")
	var heavy: Array[String] = lib.hit_keys("hammer_heavy", 2.2, true, true, false, 12.0)
	ctx.check("a heavy launching crit adds heavy, crit and launch %s" % [heavy], "hit/heavy" in heavy and "hit/crit" in heavy and "hit/launch" in heavy and not "hit/knockback" in heavy)
	var armored: Array[String] = lib.hit_keys("blade_special", 1.0, false, false, true, 12.0)
	ctx.check("an armored hit shows the armor, not a knockback, plus the move's own %s" % [armored], "hit/armored" in armored and not "hit/knockback" in armored and "hit/blade_special" in armored)
	var heavy_kind: Array[String] = lib.hit_keys("dagger_heavy", 1.0, false, false, false, 1.0)
	ctx.check("a heavy attack shows the heavy hit once, even when weak %s" % [heavy_kind], heavy_kind.count("hit/heavy") == 1)
	ctx.check("a hard push without a launch shows knockback", "hit/knockback" in lib.hit_keys("fists_heavy", 1.0, false, false, false, 20.0))
	var rules: Dictionary = lib.hit_rules
	ctx.check("hit scale is clamped and 1 at the reference damage", is_equal_approx(lib.hit_scale(0.0), rules["scale_min"]) and is_equal_approx(lib.hit_scale(100000.0), rules["scale_max"]) and is_equal_approx(lib.hit_scale(rules["damage_reference"]), 1.0))
	ctx.check("light hits still read: the smallest hit is at least 0.7 of the reference look", float(rules["scale_min"]) >= 0.7)
	ctx.check("colors: palette, weapon, hex and list", lib.color_of("weapon", Color.RED) == Color.RED and lib.color_of("ink", Color.RED) == lib.palette["ink"] and lib.color_of("#00ff00", Color.RED).is_equal_approx(Color(0, 1, 0)) and lib.color_of([0.0, 0.0, 1.0, 0.5], Color.RED) == Color(0, 0, 1, 0.5))


func _check_bad_data(ctx) -> void:
	var broken = VfxLibrary.parse('{"version": 1, "palette": {}, "actions": {"hit": {"layers": [{"type": "laser", "seconds": 1}]}, "block": {"layers": [{"type": "sprite", "mode": "glow", "seconds": 0.2, "color": "nope"}]}}}')
	var text := " ".join(broken.errors)
	ctx.check("bad data: unknown layer type is reported", "unknown type" in text)
	ctx.check("bad data: unknown color is reported", "unknown color" in text)
	ctx.check("bad data: missing event keys are reported", "'dodge' is missing" in text)
	var loop = VfxLibrary.parse('{"version": 1, "actions": {"a": {"base": "b", "layers": []}, "b": {"base": "a", "layers": []}}}')
	ctx.check("bad data: a base loop is reported, not hung on", " ".join(loop.errors).contains("bad base"))
	var based = VfxLibrary.parse('{"version": 1, "actions": {"a": {"layers": [{"type": "shake", "strength": 0.1}]}, "b": {"base": "a", "layers": [{"type": "punch", "degrees": 2}]}}}')
	ctx.check("base: an entry plays its base's layers first", based.layers("b").size() == 2 and based.layers("b")[0]["type"] == "shake")
	ctx.check("bad JSON is an error, not a crash", not VfxLibrary.parse("{oops").is_valid())


## The node that draws effects: prewarm covers every entry, effects play and end, nodes are reused.
func _check_player(ctx, lib) -> void:
	var effects := Effects.new()
	effects.library = lib
	ctx.root.add_child(effects)
	effects.prewarm(Vector3(0.0, -4.0, 0.0))
	var all_keys: Array = lib.actions.keys()
	var missed: Array = all_keys.filter(func(key) -> bool: return not key in effects.prewarmed_keys)
	ctx.check("prewarm plays every vfx entry (%d entries) %s" % [all_keys.size(), missed], missed.is_empty() and effects.prewarmed_keys.size() == all_keys.size())
	var drawn := effects.live_count()
	ctx.check("prewarm puts every drawn layer on screen at once (%d nodes)" % drawn, drawn >= _drawn_layers(lib))
	var hidden := 0
	for child in effects.get_children():
		if child is MeshInstance3D and not (child as MeshInstance3D).visible:
			hidden += 1
	ctx.check("prewarm ignores delays so every shader is drawn in the first frame (%d hidden)" % hidden, hidden == 0)
	var shaders := {}
	for child in effects.get_children():
		if child is MeshInstance3D:
			shaders[((child as MeshInstance3D).material_override as ShaderMaterial).shader.resource_path] = true
	ctx.check("prewarm uses all four effect shaders %s" % [shaders.keys()], shaders.size() == 4)
	ctx.check("unknown keys play nothing", not effects.play("swing/not_a_move", Effects.context(Vector3.ZERO, Vector3.ZERO, Vector2.RIGHT, Color.WHITE)))
	await ctx.process_frame  # (one real frame: the renderer draws them)
	var waited := 0.0  # then step the clock by hand past the longest effect
	while effects.live_count() > 0 and waited < 4.0:
		effects._process(0.1)
		waited += 0.1
	ctx.check("every effect ends and goes back to the pool", effects.live_count() == 0)
	var nodes_before := effects.get_child_count()
	var hit_ctx := Effects.context(Vector3(0.0, 1.1, 0.0), Vector3.ZERO, Vector2.RIGHT, Color.ORANGE, {"scale": 1.5})
	ctx.check("a hit plays", effects.play("hit", hit_ctx) and effects.live_count() == lib.layers("hit").filter(func(l) -> bool: return l["type"] in ["trail", "sprite", "ground", "burst"]).size())
	ctx.check("playing again reuses pooled nodes", effects.get_child_count() == nodes_before)
	effects.queue_free()


## How many nodes playing every entry once makes (ghosts make one per afterimage).
func _drawn_layers(lib) -> int:
	var count := 0
	for key in lib.actions:
		for layer in lib.layers(key):
			match str(layer["type"]):
				"trail", "sprite", "ground", "burst":
					count += 1
				"ghosts":
					count += int(layer.get("count", 4))
	return count
