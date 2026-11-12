extends Node3D
## Plays an imported skill pack's effect (art/skills/<weapon>/<skill>/vfx.glb) for one cast: frozen
## where the skill was cast, facing the way the caster faced then (the pack's +Z), scaled to the
## game's body size. While the move runs the effect is not on its own clock - show_at() sets its time
## from the move's own frames, so it stays on the swing through hit-stop and attack speed; when the
## move ends and the fighter walks away, play_out() lets the rest of the effect finish on its own
## (the packs keep smoke and debris playing for seconds after the hit). Display only: whether
## anything is hit is decided in logic/ (the move's forward box, timed to this pack's hit events).
## Which pack a weapon's ultimate shows is data: "defaults" in data/combat/ultimates.json
## (weapon type -> skill id), the same file the rules read, so picture and damage cannot disagree.
## EXTENDING: import a pack with tools/skills/shrink_skills.py, run tools/skills/sync_ultimates.py,
## then point a weapon type at it in that file; nothing in code changes.

const AnimationSet := preload("res://client/animation_set.gd")

const ULTIMATES := "res://data/combat/ultimates.json"
const WARM_FRAMES := 2  ## frames a new pack is drawn at a pinhead size, so its shaders compile before the first cast
const WARM_SCALE := 0.001

static var _data: Dictionary = {}  ## the parsed ultimates.json ({} until first use)
static var _packs: Dictionary = {}  ## move id -> the pack's facts (or {} when the weapon has none)
static var _scenes: Dictionary = {}  ## skill id -> PackedScene of vfx.glb (loaded when the weapon is equipped)
static var _motions: Dictionary = {}  ## skill id -> {"set": AnimationSet, "clip": String} of motion.glb
static var _warmed: Dictionary = {}  ## skill id -> true once its shaders have been drawn once

var _player: AnimationPlayer
var _clip := &""
var _time := 0.0
var _presentation: Node
var _free_running := false  ## playing itself out after the move ended
var _end_time := 0.0
var _warm_left := 0


## The pack a move id such as "blade_ultimate" shows: {"id", "folder", "height", "animation",
## "duration_s", "vfx_end_s", "events", "throw", "camera", "body_m"} or {} when that weapon has no pack.
static func pack_for(move_id: String) -> Dictionary:
	# Retired player packs are excluded from Web; current skills use the Lab presenter.
	if preload("res://logic/skill_build.gd").enabled(): return {}
	if _packs.has(move_id):
		return _packs[move_id]
	var found := {}
	var parts := move_id.rsplit("_", true, 1)
	if parts.size() == 2 and parts[1] == "ultimate":
		var skill_id := str(_ultimates().get("defaults", {}).get(parts[0], ""))
		var skill: Dictionary = _ultimates().get("skills", {}).get(skill_id, {})
		if not skill.is_empty() and ResourceLoader.exists(str(skill["folder"]) + "vfx.glb"):
			found = {
				"id": skill_id,
				"folder": str(skill["folder"]),
				"height": float(skill.get("reference_body_height_m", 1.0)),
				"animation": str(skill.get("animation", "")),
				"duration_s": float(skill.get("duration_s", 0.0)),
				"vfx_end_s": float(skill.get("vfx_end_s", skill.get("duration_s", 0.0))),
				"events": skill.get("events", []),
				"throw": skill.get("throw", {}),
				"impact_anchor": skill.get("impact_anchor", {}),
				"presentation": str(skill.get("presentation", "")),
				"camera": skill.get("camera", {}),  # played by client/ultimate_camera.gd
				"body_m": float(_ultimates().get("body_length_m", 1.7)),
			}
	_packs[move_id] = found
	return found


static func _ultimates() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ULTIMATES)) if FileAccess.file_exists(ULTIMATES) else null
		_data = parsed if typeof(parsed) == TYPE_DICTIONARY else {"skills": {}, "defaults": {}}
	return _data


## Called when a fighter equips a weapon: loads that weapon's pack (effect and character clip) and
## draws it once at a pinhead size under `parent`, so the first cast does not stutter while the web
## build compiles its shaders. Cheap to call again: everything is kept per skill id.
static func prepare(weapon_type: String, parent: Node) -> void:
	if preload("res://logic/skill_build.gd").enabled(): return
	if not preload("res://client/graphics_options.gd").enabled("ultimate_vfx"): return
	var pack := pack_for(weapon_type + "_ultimate")
	if pack.is_empty():
		return
	_load(pack)
	if _warmed.get(pack["id"], false) or parent == null or not parent.is_inside_tree():
		return
	_warmed[pack["id"]] = true
	var warm := new()
	warm.set_meta("warm", true)
	parent.add_child(warm)
	warm._warm(pack)


## The character animation of a pack: {"set": AnimationSet, "clip": String}, or {} when it has none.
static func motion_for(pack: Dictionary) -> Dictionary:
	if pack.is_empty():
		return {}
	_load(pack)
	return _motions.get(pack["id"], {})


static func _load(pack: Dictionary) -> void:
	var id: String = pack["id"]
	if not _scenes.has(id):
		_scenes[id] = load(str(pack["folder"]) + "vfx.glb") as PackedScene
	if not _motions.has(id):
		var found := {}
		var path: String = "res://art/characters/studio05/split/body_sword_shield.glb"
		var library: RefCounted = AnimationSet.load_file(path) if ResourceLoader.exists(path) else null
		if library != null:
			var clip := str(pack.get("animation", ""))
			if not library.has_clip(clip):
				clip = str(library.clip_names()[0]) if not library.clip_names().is_empty() else ""
			if clip != "":
				found = {"set": library, "clip": clip}
		_motions[id] = found


static func clear_cache() -> void:
	_data = {}
	_packs = {}
	_scenes = {}
	_motions = {}
	_warmed = {}


## Starts a cast at `origin` (feet, world), facing `forward` (world, on the ground), for a caster whose
## model is shown `model_scale` times its authored size.
func setup(pack: Dictionary, origin: Vector3, forward: Vector2, model_scale: float, hero: Node3D = null) -> void:
	_load(pack)
	_end_time = float(pack.get("vfx_end_s", 0.0))
	var scene: PackedScene = _scenes.get(pack["id"])
	if scene == null:
		return
	var effect: Node3D = scene.instantiate()
	add_child(effect)
	if pack.get("id", "") == "dagger_shadow_extraction_ultimate":
		# The GLB contains billboard geometry. It requires its presentation shaders,
		# otherwise smoke/flame cards render as opaque purple rectangles.
		var script_path := str(pack.get("presentation", ""))
		if not script_path.is_empty():
			_presentation = load(script_path).new()
			_presentation.config = JSON.parse_string(FileAccess.get_file_as_string(str(pack["folder"]) + "skill.json"))
			_presentation.hero_root = hero
			_presentation.receiver_skeleton = hero.get("_skeleton") if hero != null else null
			effect.add_child(_presentation)
	elif not pack.get("impact_anchor", {}).is_empty():
		_presentation = load(str(pack["folder"]) + "presentation.gd").new()
		effect.add_child(_presentation)
	var players := effect.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_player = players[0]
		for clip in _player.get_animation_list():
			if clip != &"RESET":
				_clip = clip
				break
	var ahead := Vector3(forward.x, 0.0, forward.y).normalized()
	if ahead.is_zero_approx():
		ahead = Vector3(0.0, 0.0, 1.0)
	global_transform = Transform3D(Basis(Vector3.UP.cross(ahead).normalized(), Vector3.UP, ahead).scaled(Vector3.ONE * model_scale), origin)
	show_at(0.0)


## Shows the effect at `time` seconds into its clip.
func show_at(time: float) -> void:
	_time = time
	if _player == null or _clip == &"":
		return
	if _player.current_animation != String(_clip):
		_player.play(_clip)
		_player.pause()
	_player.seek(time, true)
	if is_instance_valid(_presentation):
		_presentation.advance(time)


## The move is over but the effect is not (smoke, debris): it finishes on its own clock and then goes.
func play_out() -> void:
	_free_running = true


func _process(delta: float) -> void:
	if not preload("res://client/graphics_options.gd").enabled("ultimate_vfx") and (_free_running or has_meta("warm")):
		queue_free()
		return
	if _warm_left > 0:
		_warm_left -= 1
		if _warm_left == 0:
			queue_free()
		return
	if not _free_running:
		return
	show_at(_time + delta)
	if _time >= _end_time:
		queue_free()


func _warm(pack: Dictionary) -> void:
	# Drawn at the moment of the blast: that is when the pack shows every one of its materials, so
	# all of their shaders are compiled now instead of on the first cast.
	var events: Array = pack.get("events", [])
	var busiest := float(events[events.size() - 1].get("time_s", 0.0)) if not events.is_empty() else float(pack.get("duration_s", 0.0)) * 0.5
	setup(pack, global_position, Vector2(0.0, 1.0), WARM_SCALE)
	show_at(busiest)
	_warm_left = WARM_FRAMES
