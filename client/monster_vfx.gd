extends Node3D
## Baked daiyooo-vfx effects for monster moves (combat-designer 2026-11-18: the Mummy High Wizard's curse circle,
## starfall, sandstorm, golden bolt and the summoning circles its escorts rise from). Data: res://data/combat/monster_vfx.json,
## assets: res://art/vfx/monster/<vfx>/effect.tscn. Plays from the sim's events (area_placed, attack_started, attack_active =
## the blow lands, projectile_fired, wave_arrived; ahead = metres along the attacker's facing, face = turned along it);
## display only, nothing here changes the fight. Instances are pooled per effect, built and drawn once
## under the floor while the stage loads (no shader cache on the web), and slimmed like the class skill effects
## (client/skills/class_skill_vfx.gd slim_animation: only the live flipbook phase of each particle is drawn).

const DATA_PATH := "res://data/combat/monster_vfx.json"
const ROOT := "res://art/vfx/monster/"
const ClassSkillVfx := preload("res://client/skills/class_skill_vfx.gd")
const GraphicsOptions := preload("res://client/graphics_options.gd")
const InkVfx := preload("res://client/vfx/ink_vfx.gd")

var session  ## the stage's session (bodies, fighters, events)
var views: Dictionary = {}  ## fighter id -> fighter_view (shared with stage_view)
var spec: Dictionary = {}  ## event key -> {vfx, seek, speed, scale, boss_scale, ref_radius, follow}

var _packed: Dictionary = {}  ## vfx -> PackedScene (or null when missing)
var _pool: Dictionary = {}  ## vfx -> idle instances
var _slim_clip: Dictionary = {}  ## vfx -> slimmed Animation
var _live: Array = []  ## {node, vfx, age, length, follow}
## The violent light-and-scatter looks of every race ultimate, class skill and big monster move (client/vfx/violent_vfx.gd,
## Boss 2026-11-19). It reads the same sim events as this node; made only when "violence".level is not "current".
var violent: Node


func _init() -> void:
	spec = load_spec()


func _ready() -> void:
	if preload("res://client/vfx/violence.gd").level() == "current":
		return
	violent = preload("res://client/vfx/violent_vfx.gd").new()
	violent.session = session
	var stage := get_parent()
	if stage != null:
		violent.map_id = str(stage.get("_map_id")) if stage.get("_map_id") != null else ""
		for sibling in stage.get_children():
			if sibling.get_script() == preload("res://client/effects.gd"):
				violent.effects = sibling
	add_child(violent)


static func load_spec() -> Dictionary:
	var root = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) if FileAccess.file_exists(DATA_PATH) else null
	return root.get("effects", {}) if root is Dictionary else {}


## The scene of a bundle, or "" when it is not installed.
static func scene_path(vfx: String) -> String:
	var path := ROOT + vfx + "/effect.tscn"
	return path if ResourceLoader.exists(path) else ""


## The bundles the given monster types can play (to prewarm only what this fight can show).
func vfx_for_types(types: Array, combat_data) -> Array:
	var keys := {}
	for type in types:
		var t := str(type)
		if spec.has("wave_arrived/" + t):
			keys[str(spec["wave_arrived/" + t]["vfx"])] = true
		var enemy: Dictionary = combat_data.enemies.get(t, {})
		var style: Dictionary = combat_data.styles.get(str(enemy.get("style", "")), {})
		var move_ids: Array = style.values().map(func(m): return str(m))
		for skill in enemy.get("ai", {}).get("skills", []):  # ai.skills moves are not style slots
			move_ids.append(str(skill["move"]))
		for move_id in move_ids:
			for event_name in ["attack_started/", "attack_active/"]:
				if spec.has(event_name + move_id):
					keys[str(spec[event_name + move_id]["vfx"])] = true
			for entry in combat_data.moves.get(move_id, {}).get("spawns", []):
				if entry.has("area") and spec.has("area_placed/" + str(entry["area"])):
					keys[str(spec["area_placed/" + str(entry["area"])]["vfx"])] = true
				if entry.has("projectile") and spec.has("projectile_fired/" + str(entry["projectile"])):
					keys[str(spec["projectile_fired/" + str(entry["projectile"])]["vfx"])] = true
	return keys.keys()


## Builds one instance of each bundle and draws it a moment at `hidden` (under the floor) so its materials compile now.
func prewarm(vfx_ids: Array, hidden: Vector3) -> void:
	for vfx in vfx_ids:
		var inst := _make(str(vfx))
		if inst == null:
			continue
		_start(inst, str(vfx), 0.5, hidden, 1.0, 1.0)
		for mi in inst.find_children("*", "GeometryInstance3D", true, false):
			(mi as Node3D).visible = true
		_live.append({"node": inst, "vfx": str(vfx), "age": 0.0, "length": 0.15, "follow": -1})


func handle_events(events: Array) -> void:
	if not GraphicsOptions.enabled("combat_vfx"):
		return
	if violent != null:
		violent.handle_events(events)
	for event in events:
		match str(event.get("type", "")):
			"area_placed":
				var entry: Dictionary = spec.get("area_placed/" + str(event.get("kind", "")), {})
				if not entry.is_empty():
					var size := float(event.get("radius", 1.0)) / maxf(0.01, float(entry.get("ref_radius", 1.0)))
					_play(entry, event["pos"], size, -1)
			"projectile_fired":
				var entry: Dictionary = spec.get("projectile_fired/" + str(event.get("projectile", "")), {})
				if not entry.is_empty():
					var flat: Vector2 = event.get("dir", Vector2.RIGHT)
					var dir := Vector3(flat.x, 0.0, flat.y).normalized() if flat.length() > 0.001 else Vector3.RIGHT
					var at: Vector3 = Vector3(event["pos"]) + dir * float(entry.get("forward", 0.0)) + Vector3.UP * float(entry.get("lift", 0.0))
					_play(entry, at, float(entry.get("scale", 1.0)), -1, dir if bool(entry.get("face", false)) else Vector3.ZERO)
			"attack_started", "attack_active":
				var entry: Dictionary = spec.get(str(event["type"]) + "/" + str(event.get("move", "")), {})
				var player := int(event.get("player", -1))
				if not entry.is_empty() and session != null and session.bodies.has(player):
					var facing := _facing(player)
					var at := _position_of(player) + facing * float(entry.get("ahead", 0.0))
					var follow := player if bool(entry.get("follow", false)) else -1
					_play(entry, at, float(entry.get("scale", 1.0)), follow, facing if bool(entry.get("face", false)) else Vector3.ZERO)
			"wave_arrived":
				_on_wave(event)


## A wave that brings a type with a wave_arrived effect: a summoning circle under every monster of that wave.
func _on_wave(event: Dictionary) -> void:
	if session == null:
		return
	var entry: Dictionary = {}
	for id in event.get("enemies", []):
		var fighter = session.fighters.get(int(id))
		if fighter != null and spec.has("wave_arrived/" + str(fighter.enemy_type)):
			entry = spec["wave_arrived/" + str(fighter.enemy_type)]
	if entry.is_empty():
		return
	var bosses: Array = Array(load("res://logic/race_data.gd").load_default().rules.get("boss_types", []))
	for id in event.get("enemies", []):
		if not session.bodies.has(int(id)):
			continue
		var is_boss: bool = session.fighters.has(int(id)) and bosses.has(str(session.fighters[int(id)].enemy_type))
		_play(entry, session.bodies[int(id)].position, float(entry.get("boss_scale" if is_boss else "scale", 1.0)), -1)


func _play(entry: Dictionary, at: Vector3, size: float, follow: int, dir: Vector3 = Vector3.ZERO) -> void:
	var vfx := str(entry.get("vfx", ""))
	var inst := _take(vfx)
	if inst == null:
		return
	var seek := float(entry.get("seek", 0.0))
	var speed := maxf(0.05, float(entry.get("speed", 1.0)))
	_start(inst, vfx, seek, at, size, speed, dir)
	_live.append({"node": inst, "vfx": vfx, "age": seek, "length": _clip_length(inst), "follow": follow, "speed": speed,
		"ahead": float(entry.get("ahead", 0.0))})


func _process(delta: float) -> void:
	for i in range(_live.size() - 1, -1, -1):
		var fx: Dictionary = _live[i]
		fx["age"] = float(fx["age"]) + delta * float(fx.get("speed", 1.0))
		var node: Node3D = fx["node"]
		var done := float(fx["age"]) >= float(fx["length"])
		var follow := int(fx["follow"])
		if follow >= 0:
			if session != null and session.bodies.has(follow):
				node.global_position = _position_of(follow) + _facing(follow) * float(fx.get("ahead", 0.0))
			else:
				done = true
		if done:
			_release(fx)
			_live.remove_at(i)


## How many monster effects are playing now (tests, the performance overlay).
func live_count() -> int:
	return _live.size()


## The fighter's facing on the floor (+X when it has none).
func _facing(id: int) -> Vector3:
	if session != null and session.fighters.has(id):
		var d = session.fighters[id].get("direction")
		if d is Vector2 and (d as Vector2).length() > 0.01:
			return Vector3(d.x, 0.0, d.y).normalized()
	return Vector3.RIGHT


func _position_of(id: int) -> Vector3:
	if views.has(id) and is_instance_valid(views[id]):
		return views[id].global_position
	return session.bodies[id].position


func _make(vfx: String) -> Node3D:
	if not _packed.has(vfx):
		var path := scene_path(vfx)
		if path == "":
			push_warning("monster VFX missing: " + vfx)
		_packed[vfx] = load(path) if path != "" else null
	var packed: PackedScene = _packed[vfx]
	if packed == null:
		return null
	var inst := packed.instantiate() as Node3D
	inst.set("autoplay", false)
	inst.set("free_on_finish", false)
	inst.visible = false
	add_child(inst)
	_slim(vfx, inst)
	InkVfx.apply(inst)
	return inst


## Particles kept per emitter group ("cat_rocks 1".."cat_rocks 40" is one group): a daiyooo bundle draws every particle
## as its own mesh, so a boss move is 150-230 draw calls (tech-artist 2026-11-27: the Orc Warlock's cataclysm/bulwark/
## skyfall and the High Wizard's sandstorm dropped a phone to 10-14 fps). The kept particles are spread over the group
## (every n-th), so the shape and timing stay; only the density drops. Groups at or under the cap are untouched.
const PARTICLES_PER_GROUP := 16
const PARTICLES_PER_GROUP_PHONE := 8


static func particle_cap() -> int:
	return PARTICLES_PER_GROUP_PHONE if GraphicsOptions.device_class() == "phone" else PARTICLES_PER_GROUP


## The particle nodes to hide in a bundle: per group (name without its trailing number) keep `cap` spread evenly.
static func thinned(root: Node, cap: int) -> Array:
	var groups := {}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var particle: Node = mi.get_parent()
		var name := str(particle.name)
		var cut := name.rfind(" ")
		if cut <= 0 or not name.substr(cut + 1).is_valid_int():
			continue
		var key := name.substr(0, cut)
		if not groups.has(key): groups[key] = []
		if not groups[key].has(particle): groups[key].append(particle)
	var hidden: Array = []
	for key in groups:
		var members: Array = groups[key]
		if members.size() <= cap:
			continue
		var keep := {}
		for k in cap:
			keep[int(floor(float(k) * members.size() / cap))] = true
		for i in members.size():
			if not keep.has(i): hidden.append(members[i])
	return hidden


func _slim(vfx: String, inst: Node3D) -> void:
	var hidden := thinned(inst, particle_cap())
	for node in hidden:
		(node as Node3D).visible = false  # (its phase meshes keep their own visible keys; the parent hides them all)
	for mi in inst.find_children("*", "GeometryInstance3D", true, false):
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var player := _player_of(inst)
	var clip := _clip_of(player)
	if clip == &"":
		return
	if not _slim_clip.has(vfx):
		var slim := ClassSkillVfx.slim_animation(player.get_animation(clip), player.get_node(player.root_node))
		var base := player.get_node(player.root_node)
		var dead := {}
		for node in hidden: dead[String(base.get_path_to(node))] = true
		for t in range(slim.get_track_count() - 1, -1, -1):  # no keys for hidden particles (less work per frame)
			var path := String(slim.track_get_path(t)).get_slice(":", 0)
			for d in dead:
				if path == d or path.begins_with(d + "/"):
					slim.remove_track(t)
					break
		_slim_clip[vfx] = slim
	var anim: Animation = _slim_clip[vfx]
	var lib_name := String(clip).get_slice("/", 0) if "/" in String(clip) else ""
	var anim_name := String(clip).get_slice("/", 1) if "/" in String(clip) else String(clip)
	var lib := player.get_animation_library(lib_name)
	lib.remove_animation(anim_name)
	lib.add_animation(anim_name, anim)
	for t in anim.get_track_count():
		if anim.track_get_type(t) == Animation.TYPE_VALUE and anim.track_get_key_count(t) > 0:
			var node := player.get_node(player.root_node).get_node_or_null(NodePath(String(anim.track_get_path(t)).get_slice(":", 0)))
			if node is Node3D:
				(node as Node3D).visible = bool(anim.track_get_key_value(t, 0))


func _take(vfx: String) -> Node3D:
	var idle: Array = _pool.get(vfx, [])
	if not idle.is_empty():
		return idle.pop_back()
	return _make(vfx)


func _start(inst: Node3D, _vfx: String, seek: float, at: Vector3, size: float, speed: float, dir: Vector3 = Vector3.ZERO) -> void:
	inst.global_position = at
	var turn := Basis.looking_at(-dir, Vector3.UP) if dir.length() > 0.01 else Basis.IDENTITY  # the asset's forward is +Z
	inst.global_basis = turn.scaled(Vector3.ONE * size)
	inst.visible = true
	var player := _player_of(inst)
	var clip := _clip_of(player)
	if clip == &"":
		return
	player.speed_scale = speed
	player.play(clip)
	player.seek(seek, true)


func _release(fx: Dictionary) -> void:
	var inst: Node3D = fx["node"]
	if not is_instance_valid(inst):
		return
	var player := _player_of(inst)
	if player != null:
		player.stop()
	inst.visible = false
	var vfx := str(fx["vfx"])
	if not _pool.has(vfx):
		_pool[vfx] = []
	_pool[vfx].append(inst)


func _player_of(inst: Node) -> AnimationPlayer:
	if inst.has_meta("vfx_player"):
		return inst.get_meta("vfx_player")
	var found := inst.find_children("*", "AnimationPlayer", true, false)
	var player: AnimationPlayer = found[0] if not found.is_empty() else null
	inst.set_meta("vfx_player", player)
	return player


func _clip_of(player: AnimationPlayer) -> StringName:
	if player == null:
		return &""
	for name in player.get_animation_list():
		if name != "RESET":
			return name
	return &""


func _clip_length(inst: Node3D) -> float:
	var player := _player_of(inst)
	var clip := _clip_of(player)
	return player.get_animation(clip).length if clip != &"" else 1.0
