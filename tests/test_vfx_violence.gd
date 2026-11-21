extends RefCounted
## The violent light-and-scatter looks (Boss 2026-11-19, client/vfx/violence.gd + client/vfx/violent_vfx.gd): the data is
## valid; every preset has L1/L2/L3 each with a lighter phone twin; no ground decals and only short soft flashes; every race
## ultimate (16 + defaults), every class skill (16) and the listed mummy boss moves have a look; the shipped level is L3;
## one token switches it ("current" plays and prewarms nothing new); the right events trigger the right keys; per-map
## debris colours apply; flashes of overlapping blows are rate-limited; reduced motion drops the shake / punch and softens
## the flash; glowing (additive) layers are never inked; pooled; the per-frame code allocates nothing.

const Effects := preload("res://client/effects.gd")
const VfxLibrary := preload("res://client/vfx/vfx_library.gd")
const Violence := preload("res://client/vfx/violence.gd")
const ViolentVfx := preload("res://client/vfx/violent_vfx.gd")
const SkillData := preload("res://logic/class_skills/skill_data.gd")
const SUPPORT := ["ult_aura", "aura"]  ## heal / shield / rally ults, buff / stance skills: the soft floating look
const BOSS_MOVES := ["monster/hw_star", "monster/hw_curse", "monster/mummy_hw_sandstorm", "monster/hw_bolt", "monster/summon",
	"monster/mummy_boss_nova", "monster/pharaoh_sand_crescent", "monster/mummy_knight_bash", "monster/mummy_curse",
	"monster/orc_warlock_cleave", "monster/orc_warlock_skyfall", "monster/orc_warlock_cataclysm", "monster/orc_warlock_bulwark"]
const MonsterVfx := preload("res://client/monster_vfx.gd")
## The Orc Warlock's own daiyooo bundles (Boss 2026-11-21: spectacular, violent, ember / fire with a touch of purple).
const WARLOCK_KEYS := {"attack_active/orc_warlock_cleave": "orc_warlock/cleave", "attack_started/orc_warlock_skyfall": "orc_warlock/skyfall",
	"attack_active/orc_warlock_cataclysm": "orc_warlock/cataclysm", "attack_started/orc_warlock_bulwark": "orc_warlock/bulwark"}


func run(ctx) -> void:
	var lib = VfxLibrary.load_default()
	ctx.check("vfx.json with the violent looks loads without errors %s" % [lib.errors], lib.is_valid())
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Violence.DATA_PATH))["violence"]
	_check_data(ctx, lib, data)
	_check_coverage(ctx, lib, data)
	_check_bad_data(ctx)
	_check_switch(ctx, data)
	await _check_play(ctx, lib)
	_check_no_allocation(ctx)
	_check_orc_warlock(ctx, lib, data)
	Violence.override_level = ""
	Violence.override_phone = -1
	Violence.override_reduced = -1


func _check_data(ctx, lib, data) -> void:
	var presets: Array[String] = lib.violent_skills()
	ctx.check("every preset of the data has looks %s" % [presets], Array(data["presets"]).all(func(p): return str(p) in presets))
	for preset in presets:
		var counts := []
		for lvl in ["L1", "L2", "L3"]:
			var full: Array = lib.layers("violent/%s/%s" % [preset, lvl])
			var phone: Array = lib.layers("violent/%s/%s_phone" % [preset, lvl])
			ctx.check("%s %s has a lighter phone variant (%d < %d particles)" % [preset, lvl, VfxLibrary.violent_particles(phone), VfxLibrary.violent_particles(full)],
				not phone.is_empty() and VfxLibrary.violent_particles(phone) < VfxLibrary.violent_particles(full) and phone.size() <= full.size())
			ctx.check("%s %s: no ground decal (no rings / scorch)" % [preset, lvl], (full + phone).all(func(l): return str(l.get("type")) != "ground"))
			ctx.check("%s %s: dust and debris are matter, not light" % [preset, lvl],
				full.all(func(l): return not (str(l.get("style", "")) in ["chunk", "smoke"] and bool(l.get("glow", false)))))
			ctx.check("%s %s: any flash is soft and short" % [preset, lvl],
				full.filter(func(l): return str(l.get("type")) == "flash").all(func(l): return float(l["seconds"]) <= 0.12 and float(l["color"][3]) <= 0.16))
			if preset in SUPPORT:
				ctx.check("%s %s (support): soft glow and slow rising motes" % [preset, lvl],
					full.any(func(l): return str(l.get("mode", "")) == "glow" and bool(l.get("glow", false))) and full.any(func(l): return str(l.get("style", "")) == "mote" and float(l.get("gravity", 0.0)) < 0.0))
				ctx.check("%s %s (support): no rays, pillar, rocks, shake, punch or flash" % [preset, lvl], (full + phone).all(_soft_layer))
			else:
				ctx.check("%s %s: a white-hot additive core, glowing sparks and a shake" % [preset, lvl],
					full.any(func(l): return str(l.get("mode", "")) == "glow" and bool(l.get("glow", false))) and full.any(func(l): return str(l.get("style", "")) == "streak" and bool(l.get("glow", false)))
					and full.any(func(l): return str(l.get("type")) == "shake"))
			counts.append(VfxLibrary.violent_particles(full))
		ctx.check("%s: L1 < L2 < L3 in particles %s" % [preset, counts], counts[0] < counts[1] and counts[1] < counts[2])
		if not preset in SUPPORT:
			var l3: Array = lib.layers("violent/%s/L3" % preset)
			ctx.check("%s L3: radiating rays" % preset, l3.any(func(l): return str(l.get("mode", "")) == "star"))
			var pillar: Array = l3.filter(func(l): return str(l.get("mode", "")) == "beam")
			ctx.check("%s L3: the light pillar is short enough to stay in frame (<= 4.5 m)" % preset, pillar.all(func(l): return float(l.get("height", 0.0)) <= 4.5))
	for preset in ["ult", "skill", "boss"]:
		var l3: Array = lib.layers("violent/%s/L3" % preset)
		ctx.check("%s L3 has the pillar, debris and dust (the approved L3 set)" % preset, l3.any(func(l): return str(l.get("mode", "")) == "beam")
			and l3.any(func(l): return str(l.get("style", "")) == "chunk") and l3.any(func(l): return str(l.get("style", "")) == "smoke"))


## A support look's layer: no rays, rocks, shake, punch or flash; a beam only as a faint haze column, never a pillar.
static func _soft_layer(l: Dictionary) -> bool:
	if str(l.get("mode", "")) == "star" or str(l.get("style", "")) == "chunk" or str(l.get("type")) in ["shake", "punch", "flash"]:
		return false
	return str(l.get("mode", "")) != "beam" or float(l.get("opacity", 1.0)) <= 0.4


func _check_coverage(ctx, lib, data) -> void:
	var skills: Dictionary = data["skills"]
	var missing: Array = []
	for race in ["human", "elf", "runeborn", "viking"]:
		var race_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/races/%s.json" % race))
		for key in _ult_keys(race_data):
			if not skills.has(key):
				missing.append(key)
	ctx.check("every race ultimate has its own look %s" % [missing], missing.is_empty())
	var ult_colors := {}
	for key in skills:
		if str(key).begins_with("race_ult/"):
			ult_colors[str(skills[key]["color"])] = true
	ctx.check("race ultimates have their own colours (%d distinct)" % ult_colors.size(), ult_colors.size() >= 16)
	var class_missing: Array = []
	for skill in SkillData.load_default().skills:
		if not skills.has("class_skill/" + str(skill)):
			class_missing.append(skill)
	ctx.check("every class skill has a look %s" % [class_missing], class_missing.is_empty())
	ctx.check("the mummy bosses' big moves have looks", BOSS_MOVES.all(func(k): return skills.has(k)))
	for key in skills:
		ctx.check("%s uses a known preset" % key, lib.has("violent/%s/L3" % str(skills[key]["preset"])))
	ctx.check("the dark mummy island has lighter debris and dust", data["map_colors"].has("mummy")
		and Color.html(data["map_colors"]["mummy"]["rock"]).get_luminance() > Color.html(data["map_colors"]["goblin"]["rock"]).get_luminance() + 0.25)


func _ult_keys(node) -> Array:
	var out: Array = []
	if node is Dictionary:
		if node.get("ultimate") is Dictionary and node["ultimate"].has("vfx"):
			out.append(str(node["ultimate"]["vfx"]))
		for v in node.values():
			out.append_array(_ult_keys(v))
	elif node is Array:
		for v in node:
			out.append_array(_ult_keys(v))
	return out


func _check_bad_data(ctx) -> void:
	var missing = VfxLibrary.parse('{"version": 1, "actions": {"violent/x/L1": {"layers": [{"type": "shake", "strength": 0.1}]}}}')
	ctx.check("bad data: a violent look without its phone twin or other levels is reported", " ".join(missing.errors).contains("violent look 'x'"))
	var heavy = VfxLibrary.parse('{"version": 1, "actions": {"violent/x/L1": {"layers": [{"type": "burst", "style": "chunk", "count": 4, "seconds": 1}]}, "violent/x/L1_phone": {"layers": [{"type": "burst", "style": "chunk", "count": 9, "seconds": 1}]}}}')
	ctx.check("bad data: a phone variant with more particles is reported", " ".join(heavy.errors).contains("more particles"))
	var dropped = VfxLibrary.parse('{"version": 1, "actions": {"violent/x/L1": {"layers": [{"type": "shake", "strength": 0.1}, {"type": "burst", "style": "chunk", "count": 4, "seconds": 1}]}, "violent/x/L1_phone": {"layers": [{"type": "burst", "style": "chunk", "count": 2, "seconds": 1}]}}}')
	ctx.check("bad data: a phone variant that drops the shake is reported", " ".join(dropped.errors).contains("drops the shake"))
	var decal = VfxLibrary.parse('{"version": 1, "actions": {"violent/x/L1": {"layers": [{"type": "ground", "mode": "ring", "seconds": 1}]}, "violent/x/L1_phone": {"layers": [{"type": "ground", "mode": "ring", "seconds": 1}]}}}')
	ctx.check("bad data: a violent ground decal is reported", " ".join(decal.errors).contains("ground decal"))
	var flash = VfxLibrary.parse('{"version": 1, "actions": {"violent/x/L1": {"layers": [{"type": "flash", "color": [1, 1, 1, 0.5], "seconds": 0.3}]}, "violent/x/L1_phone": {"layers": [{"type": "flash", "color": [1, 1, 1, 0.5], "seconds": 0.3}]}}}')
	ctx.check("bad data: a long or strong violent flash is reported", " ".join(flash.errors).contains("too long or strong"))
	var glow_ground = VfxLibrary.parse('{"version": 1, "actions": {"a": {"layers": [{"type": "ground", "mode": "ring", "glow": true, "seconds": 1}]}}}')
	ctx.check("bad data: only sprites and bursts can glow", " ".join(glow_ground.errors).contains("can glow"))
	var styles = VfxLibrary.parse('{"version": 1, "actions": {"a": {"layers": [{"type": "burst", "style": "chunk", "dir": "ring", "count": 3, "seconds": 1}, {"type": "burst", "style": "smoke", "count": 3, "seconds": 1}]}}}')
	ctx.check("chunk / smoke bursts and the ring direction are known %s" % [styles.errors], not " ".join(styles.errors).contains("unknown"))


func _check_switch(ctx, data) -> void:
	Violence.override_level = ""
	Violence.reload()
	ctx.check("the shipped level is L3 (data %s)" % data["level"], str(data["level"]) == "L3")
	ctx.check("the current look plays no violent key", Violence.key_for("ult", "current", false) == "")
	ctx.check("one token picks the level and the device variant",
		Violence.key_for("ult", "L2", false) == "violent/ult/L2" and Violence.key_for("ult", "L2", true) == "violent/ult/L2_phone")
	Violence.override_level = "current"
	ctx.check("at the current look nothing violent is prewarmed", not Effects.prewarm_wanted("violent/ult/L1") and Effects.prewarm_wanted("hit"))
	Violence.override_level = "L3"
	Violence.override_phone = 1
	ctx.check("at L3 on a phone only the L3 phone looks are prewarmed",
		Effects.prewarm_wanted("violent/skill/L3_phone") and not Effects.prewarm_wanted("violent/skill/L3") and not Effects.prewarm_wanted("violent/skill/L2_phone"))
	Violence.override_phone = -1
	ctx.check("the lighting dim experiment is gone", not (Violence as Script).get_script_method_list().any(func(m): return m["name"] == "dim_mode") and not "dim" in data)


func _check_play(ctx, lib) -> void:
	var effects := Effects.new()
	effects.library = lib
	ctx.root.add_child(effects)
	var rig := _FakeRig.new()
	ctx.root.add_child(rig)
	effects.rig = rig
	var flashes: Array = []
	effects.screen_flash.connect(func(c: Color, _s: float) -> void: flashes.append(c.a))
	var violent := ViolentVfx.new()
	violent.effects = effects
	violent.map_id = "mummy_arena_a"
	violent.session = _FakeSession.new()
	ctx.root.add_child(violent)
	Violence.override_level = "current"
	ctx.check("at the current look a blow plays nothing new", violent.play("monster/hw_star", Vector3.ZERO, Vector2.RIGHT) == "" and effects.live_count() == 0)
	Violence.override_level = "L3"
	Violence.override_phone = 0
	Violence.override_reduced = 0
	violent.handle_events([{"type": "area_detonated", "kind": "hw_star", "pos": Vector3(1, 0, 1), "radius": 1.5}])
	ctx.check("a High Wizard star's blow plays its look %s" % [violent.played], violent.played == ["monster/hw_star"])
	var drawn: int = lib.layers("violent/boss/L3").filter(func(l) -> bool: return str(l["type"]) in ["sprite", "ground", "burst"]).size()
	ctx.check("every drawn layer is on screen (%d / %d)" % [effects.live_count(), drawn], effects.live_count() == drawn)
	var additive := 0
	var rock_ok := false
	var mummy_rock := Color.html(str(violent.map_colors.get("rock", Color.BLACK).to_html()))
	for child in effects.get_children():
		if child is MeshInstance3D and child.visible:
			var mat := child.material_override as ShaderMaterial
			if str(child.get_meta("vfx_type")).ends_with("_add"):
				additive += 1
				ctx.check("a glowing layer is never inked", float(mat.get_shader_parameter("drawn")) == 0.0)
			elif int(mat.get_shader_parameter("style")) == 3 and (mat.get_shader_parameter("color") as Color).is_equal_approx(mummy_rock):
				rock_ok = true
	ctx.check("the glowing core / rays / pillar / sparks use the additive shaders (%d)" % additive, additive >= 5)
	ctx.check("on the mummy island the debris uses its light sand colour", rock_ok)
	await ctx.process_frame
	ctx.check("the hit shakes the camera", rig.shakes > 0)
	ctx.check("the hit flashes the screen softly %s" % [flashes], flashes.size() == 1 and float(flashes[0]) <= 0.16)
	flashes.clear()
	violent.handle_events([
		{"type": "ultimate_cast", "player": 3, "vfx": "race_ult/runeborn_greatsword"},
		{"type": "race_burst", "player": 3, "pos": Vector3.ZERO, "radius": 3.0, "ultimate": true},
		{"type": "race_zone", "player": 3, "pos": Vector3.ZERO, "radius": 3.0, "ultimate": true},
		{"type": "ultimate_cast", "player": 4, "vfx": "race_ult/elf_magic"},
		{"type": "race_heal", "player": 4, "target": 4, "amount": 10.0, "ultimate": true},
		{"type": "class_skill_impact", "player": 1, "skill": "arcane_orb", "pos": Vector3(0, 1.1, 0), "radius": 2.0},
		{"type": "class_skill_release", "player": 1, "skill": "repulse_nova", "index": 0, "pos": Vector3.ZERO, "aim": Vector3.ZERO, "target": -1},
		{"type": "class_skill_release", "player": 1, "skill": "rapid_fire", "index": 2, "pos": Vector3.ZERO, "aim": Vector3.ZERO, "target": -1},
		{"type": "projectile_ended", "player": 9, "projectile": "hw_bolt", "reason": "hit", "pos": Vector3.ZERO},
		{"type": "projectile_ended", "player": 9, "projectile": "hw_bolt", "reason": "gone", "pos": Vector3.ZERO},
	])
	ctx.check("ultimates (once each, at their first action), the orb burst, the nova and the bolt play; a volley's later arrows and a vanished bolt do not %s" % [violent.played],
		violent.played == ["monster/hw_star", "race_ult/runeborn_greatsword", "race_ult/elf_magic", "class_skill/arcane_orb", "class_skill/repulse_nova", "monster/hw_bolt"])
	await ctx.process_frame
	ctx.check("overlapping blows flash at most once (no flicker) %s" % [flashes], flashes.size() <= 1)
	Violence.override_reduced = 1
	rig.shakes = 0
	rig.punches = 0
	flashes.clear()
	violent._flash_clock = 99.0
	violent.play("race_ult/viking_magic", Vector3.ZERO, Vector2.RIGHT)
	await ctx.process_frame
	ctx.check("reduced motion: no camera shake or zoom punch", rig.shakes == 0 and rig.punches == 0)
	ctx.check("reduced motion: the screen flash is a third as strong %s" % [flashes], flashes.size() == 1 and float(flashes[0]) < 0.06)
	Violence.override_reduced = 0
	rig.shakes = 0
	flashes.clear()
	violent._flash_clock = 99.0
	var soft := violent.play("race_ult/human_magic", Vector3.ZERO, Vector2.RIGHT)
	await ctx.process_frame
	ctx.check("a support ultimate (Rally) plays the soft floating look with no shake or flash (%s)" % soft, soft == "violent/ult_aura/L3" and rig.shakes == 0 and flashes.is_empty())
	Violence.override_reduced = 1
	Violence.override_phone = 1
	var before := effects.live_count()
	var action := violent.play("race_ult/viking_magic", Vector3.ZERO, Vector2.RIGHT)
	ctx.check("a phone plays the phone variant (%s)" % action, action == "violent/ult/L3_phone")
	ctx.check("the phone variant puts fewer nodes on screen", effects.live_count() - before < lib.layers("violent/ult/L3").filter(func(l) -> bool: return str(l["type"]) in ["sprite", "ground", "burst"]).size())
	var waited := 0.0
	while effects.live_count() > 0 and waited < 6.0:
		effects._process(0.1)
		waited += 0.1
	ctx.check("every violent layer ends and goes back to the pool (%.1f s)" % waited, effects.live_count() == 0)
	var nodes := effects.get_child_count()
	violent._phone_tokens = violent.PHONE_BLOWS_PER_SECOND
	violent.play("race_ult/viking_magic", Vector3.ZERO, Vector2.RIGHT)
	ctx.check("playing again reuses pooled nodes", effects.get_child_count() == nodes)
	var got := 0
	for i in 8:
		if violent.play("monster/hw_star", Vector3.ZERO, Vector2.RIGHT) != "":
			got += 1
	ctx.check("a phone plays at most %d violent blows a second in a burst (%d of 8 more)" % [int(violent.PHONE_BLOWS_PER_SECOND), got], got <= 2)
	Violence.override_phone = 0
	ctx.check("desktop has no such cap", violent.play("monster/hw_star", Vector3.ZERO, Vector2.RIGHT) != "")
	violent.queue_free()
	rig.queue_free()
	effects.queue_free()


## The Orc Warlock plays its own four bundles (not the player's Iron Guard, not purple player presets), warm ember colours
## with a purple accent, the skyfall falls from the sky, the cataclysm draws cracks and debris but no flat ground ring, and
## an attack_active bundle lands `ahead` along the boss's facing.
func _check_orc_warlock(ctx, lib, data) -> void:
	var spec := MonsterVfx.load_spec()
	for key in WARLOCK_KEYS:
		ctx.check("orc warlock %s plays its own bundle %s" % [key, WARLOCK_KEYS[key]], spec.has(key) and str(spec[key]["vfx"]) == WARLOCK_KEYS[key]
			and MonsterVfx.scene_path(WARLOCK_KEYS[key]) != "")
		var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art/vfx/monster/%s/recipe.json" % WARLOCK_KEYS[key]))
		var hues: Array = recipe["layers"].map(func(l): return Color.html(str(l["color"])))
		ctx.check("%s: ember / fire orange with a touch of purple" % WARLOCK_KEYS[key],
			hues.any(func(c: Color): return c.s > 0.5 and c.h > 0.03 and c.h < 0.12) and hues.any(func(c: Color): return c.s > 0.4 and c.h > 0.72 and c.h < 0.85))
		if key.ends_with("skyfall"):
			ctx.check("the skyfall's meteor falls from the sky", recipe["layers"].any(func(l): return str(l["motion"]) == "fall" and str(l["style"]) == "meteor"))
		if key.ends_with("cataclysm"):
			ctx.check("the cataclysm breaks the floor with cracks and debris, no flat ring", recipe["layers"].any(func(l): return str(l["style"]) == "combat_ground_crack")
				and recipe["layers"].any(func(l): return str(l["type"]) == "debris") and recipe["layers"].all(func(l): return str(l["type"]) != "wave"))
	ctx.check("no warlock effect borrows the player's Iron Guard any more", spec.values().all(func(e): return not str(e["vfx"]).contains("iron_guard")))
	ctx.check("the cataclysm's swing draws no ground ring", lib.layers("swing/orc_warlock_cataclysm").all(func(l): return str(l.get("type")) != "ground"))
	ctx.check("the bulwark's shield bash has its own hit burst", not lib.layers("hit/orc_warlock_bulwark").is_empty())
	for key in ["monster/orc_warlock_cleave", "monster/orc_warlock_skyfall", "monster/orc_warlock_cataclysm", "monster/orc_warlock_bulwark"]:
		var c := Color.html(str(data["skills"][key]["color"]))
		ctx.check("%s violent look is ember orange (%s)" % [key, c.to_html(false)], c.h > 0.03 and c.h < 0.12 and c.s > 0.6)
	var combat = load("res://logic/combat_data_loader.gd").load_default()
	Violence.override_level = "current"  # (no violent child: this checks the bundle only)
	var mv = MonsterVfx.new()
	var bundles: Array = mv.vfx_for_types(["orc_warlock"], combat)
	bundles.sort()
	ctx.check("the warlock's fight prewarms its four bundles %s" % [bundles], bundles == ["orc_warlock/bulwark", "orc_warlock/cataclysm", "orc_warlock/cleave", "orc_warlock/skyfall"])
	var session := _FakeSession.new()
	session.fighters = {1: _FakeFighter.new()}
	mv.session = session
	ctx.root.add_child(mv)
	mv.handle_events([{"type": "attack_active", "player": 1, "move": "orc_warlock_cleave"}])
	ctx.check("the cleave's blow plays its bundle", mv.live_count() == 1)
	if mv.live_count() == 1:
		var node: Node3D = mv._live[0]["node"]
		var want := Vector3(2.0, 0.0, 1.0) + Vector3(0.0, 0.0, 1.0) * float(spec["attack_active/orc_warlock_cleave"]["ahead"])
		ctx.check("it lands ahead along the boss's facing and turned with it (%s)" % [node.global_position], node.global_position.is_equal_approx(want)
			and (node.global_basis.z.normalized()).is_equal_approx(Vector3(0.0, 0.0, 1.0)))
	mv.handle_events([{"type": "attack_started", "player": 1, "move": "orc_warlock_cleave"}])
	ctx.check("the cleave's windup plays no bundle", mv.live_count() == 1)
	mv.queue_free()


## The per-frame path (the flash clock) and the event scan allocate no objects.
func _check_no_allocation(ctx) -> void:
	var violent := ViolentVfx.new()
	violent._process(0.016)
	var none: Array = [{"type": "hit"}, {"type": "attack_active", "player": 1, "move": "not_a_move"}]
	violent.handle_events(none)
	var objects := Performance.get_monitor(Performance.OBJECT_COUNT)
	for i in 120:
		violent._process(0.016)
		violent.handle_events(none)
	ctx.check("the per-frame code allocates no objects (%d -> %d)" % [objects, Performance.get_monitor(Performance.OBJECT_COUNT)],
		Performance.get_monitor(Performance.OBJECT_COUNT) == objects)
	violent.free()


class _FakeBody:
	extends RefCounted
	var position := Vector3(2.0, 0.0, 1.0)


class _FakeSession:
	extends RefCounted
	var bodies := {1: _FakeBody.new(), 3: _FakeBody.new(), 4: _FakeBody.new()}
	var fighters := {}


class _FakeFighter:
	extends RefCounted
	var direction := Vector2(0.0, 1.0)


class _FakeRig:
	extends Node
	var shakes := 0
	var punches := 0
	func shake(_strength: float, _seconds: float) -> void:
		shakes += 1
	func punch(_degrees: float) -> void:
		punches += 1
