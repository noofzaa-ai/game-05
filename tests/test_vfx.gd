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
	_check_skill_looks(ctx, lib)
	await _check_player(ctx, lib)
	await _check_class_skill_vfx(ctx)
	await _check_ultimate_hud(ctx)


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


## Every class skill reads on screen (QA 2026-11-12: several skills showed nothing), HUD helpers.
func _check_skill_looks(ctx, lib) -> void:
	# (the old skill-build skills' per-skill looks went with that system; class skills have no VFX yet, class-skills.md 6)
	var dark: Array[String] = []
	for key in ["skill_hit/1", "skill_hit/2", "skill_hit/3", "hit", "death"]:
		for layer in lib.layers(key):
			if str(layer.get("type")) in ["sprite", "burst", "ground"] and float(layer.get("ink", 0.0)) > 0.5 and str(layer.get("mode", layer.get("style", ""))) in ["splat", "puff", "stain"]:
				dark.append(key)
	ctx.check("hit and death looks have no dark ink blobs %s" % [dark], dark.is_empty())
	var link = VfxLibrary.parse('{"version": 1, "actions": {"a": {"layers": [{"type": "sprite", "mode": "bolt", "link": true, "billboard": "y", "seconds": 0.2}]}}}')
	ctx.check("bad data: a link sprite must turn round its own axis", " ".join(link.errors).contains("link sprite"))
	var SquadPanel = load("res://client/squad_panel.gd")
	ctx.check("squad HP text never shows more than the maximum", SquadPanel.hp_text(1079.6, 1079.4) == "1079 / 1079" and SquadPanel.hp_text(0.2, 100.0) == "1 / 100" and SquadPanel.hp_text(-5.0, 100.0) == "0 / 100")
	var Numbers = load("res://client/combat_numbers.gd")
	var keep: Array[Rect2] = [Rect2(900, 10, 360, 34)]
	var shift: Vector2 = Numbers.avoid(Rect2(950, 20, 80, 40), keep, Vector2(1280, 720))
	ctx.check("a pop-up under the HUD's trip line moves out of it %s" % shift, not Rect2(Vector2(950, 20) + shift, Vector2(80, 40)).intersects(keep[0]))
	ctx.check("a pop-up clear of the HUD stays put", Numbers.avoid(Rect2(400, 300, 80, 40), keep, Vector2(1280, 720)) == Vector2.ZERO)
	var edge: Vector2 = Numbers.avoid(Rect2(1250, 300, 80, 40), [] as Array[Rect2], Vector2(1280, 720))
	ctx.check("a pop-up at the screen edge stays on screen", 1250.0 + edge.x + 80.0 <= 1280.0)


## Class skills v2 (client/skills/class_skill_vfx.gd): every skill's vfx key resolves to its effect scene, the
## prewarm builds and draws one of each, a release event plays the effect and it goes back to its pool at the end.
func _check_class_skill_vfx(ctx) -> void:
	const ClassVfx := preload("res://client/skills/class_skill_vfx.gd")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/class_skills/class_skills.json"))
	var missing: Array = []
	for id in data["skills"]:
		if ClassVfx.scene_path(str(data["skills"][id].get("vfx", ""))) == "" or not ClassVfx.SPEC.has(id):
			missing.append(id)
	ctx.check("every class skill vfx key resolves to an effect scene %s" % [missing], missing.is_empty())
	ctx.check("a non class-skill key resolves to nothing", ClassVfx.scene_path("skill_cast/fireball") == "")
	var vfx = ClassVfx.new()
	vfx.session = _FakeSession.new()
	ctx.root.add_child(vfx)
	vfx.prewarm(["reaping_arc", "arcane_orb"], Vector3(0.0, -4.0, 0.0))
	ctx.check("prewarm builds every listed skill (+1 for an orb's burst)", vfx.prewarmed == ["reaping_arc", "arcane_orb"] and vfx.live_count() == 3)
	await ctx.process_frame
	for i in 5:
		vfx._process(0.1)
	ctx.check("prewarmed effects go back to the pool", vfx.live_count() == 0)
	var nodes := vfx.get_child_count()
	vfx.handle_events([{"type": "class_skill_release", "player": 1, "skill": "reaping_arc", "index": 0, "pos": Vector3.ZERO, "aim": Vector3(4, 0, 0)}])
	ctx.check("a release plays the skill's effect from the pool", vfx.live_count() == 1 and vfx.get_child_count() == nodes)
	vfx.handle_events([{"type": "class_skill_release", "player": 1, "skill": "arcane_orb", "index": 0, "pos": Vector3.ZERO, "aim": Vector3(4, 0, 0)}])
	vfx.handle_events([{"type": "class_skill_impact", "player": 1, "skill": "", "pos": Vector3(3, 0, 0), "radius": 2.0}])
	ctx.check("an orb's impact swaps the flying orb for its burst", vfx.live_count() == 2)
	for i in 30:
		vfx._process(0.1)
	ctx.check("every class skill effect ends and returns to its pool", vfx.live_count() == 0)
	# Draw-call fix: a daiyooo flipbook hides off phases by scale 0.0001 (still drawn); _slim turns those into
	# visible keys, so only live phases draw. After the all-visible prewarm frame a play must restore them.
	var leap: Node3D = vfx._take("crater_leap")
	var meshes: Array = leap.find_children("*", "MeshInstance3D", true, false)
	vfx._start(leap, 0.9, Vector3.ZERO, Vector3.FORWARD, false)
	var shown := meshes.filter(func(m) -> bool: return m.is_visible_in_tree()).size()
	var fresh: Node3D = load("res://art/vfx/class_skills/crater_leap/effect.tscn").instantiate()
	ctx.root.add_child(fresh)
	var fap: AnimationPlayer = vfx._player_of(fresh)
	fap.play(vfx._clip_of(fap))
	fap.seek(0.9, true)
	var live := fresh.find_children("*", "MeshInstance3D", true, false).filter(func(m) -> bool: return m.scale.x > 0.001).size()
	ctx.check("crater_leap draws only its live phases (%d of %d meshes shown, %d live in the raw clip)" % [shown, meshes.size(), live], shown > 0 and absi(shown - live) <= 2 and shown * 4 < meshes.size())
	fresh.queue_free()
	vfx.queue_free()


class _FakeBody:
	var position := Vector3.ZERO
	func _init(p: Vector3) -> void:
		position = p


class _FakeSession:
	var bodies := {1: _FakeBody.new(Vector3.ZERO), 2: _FakeBody.new(Vector3(4, 0, 0))}
	var fighters := {}


## Race ultimates on the squad cards (client/squad_panel.gd): the gauge strip follows Fighter.gauge in the race colour,
## a full gauge lights the ring, and ultimate_callout shows the race banner with the localized name, kept on screen.
func _check_ultimate_hud(ctx) -> void:
	var Fighter = load("res://logic/fighter.gd")
	var CardTokens = load("res://client/card_tokens.gd")
	var panel = load("res://client/squad_panel.gd").new()
	ctx.root.add_child(panel)
	var fighters := {}
	for id in [0, 1]:
		var f = Fighter.new()
		f.team = "player"
		f.stats = {"HP": 100.0}
		f.hp = 100.0
		f.race_state = {"race": "elf" if id == 0 else "viking", "class": "magic", "ultimate": {"name": "X", "vfx": "race_ult/elf_magic"}}
		fighters[id] = f
	fighters[0].gauge = 50.0
	fighters[1].gauge = 100.0
	var data := {"rules": {"ultimate_gauge_max": 100.0}}
	panel.update_from(fighters, 0, data)
	ctx.check("ultimate gauge strip shows half a gauge (%.2f)" % panel.gauge_shown(0), absf(panel.gauge_shown(0) - 0.5) < 0.01)
	ctx.check("a full gauge lights the race ring, a half one does not", panel._cards[1]["ult_ring"].visible and not panel._cards[0]["ult_ring"].visible)
	fighters[1].race_state.erase("ultimate")
	panel.update_from(fighters, 0, data)
	ctx.check("a card without a race ultimate has no gauge strip", panel.gauge_shown(1) < 0.0 and not panel._cards[1]["ult_ring"].visible)
	var name: String = CardTokens.ultimate_name("race_ult/elf_magic", "fallback")
	ctx.check("ultimate names come from the string table (%s)" % name, name == "Rebirth Bloom" and CardTokens.ultimate_name("race_ult/nope", "Data Name") == "Data Name")
	panel.ultimate_callout(0, name, "elf")
	ctx.check("ultimate_callout shows the race banner with the name", panel.ultimate_banner_shown(0) and panel._cards[0]["ult_name"].text == name and panel._cards[0]["ult_badge"].race == "elf")
	var rect: Rect2 = panel._cards[0]["ult_banner"].get_global_rect()
	var area: Vector2 = panel.get_viewport().get_visible_rect().size
	ctx.check("the ultimate banner stays on screen %s" % rect, rect.position.x >= 0.0 and rect.end.x <= area.x + 0.5)
	panel.queue_free()
	await ctx.process_frame
