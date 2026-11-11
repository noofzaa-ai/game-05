extends RefCounted
## A set of character animations kept in one file: art/animations/<name>.glb (a skeleton with one
## animation per clip, authored in Blender, see tools/blender/build_animations.py) and <name>.json
## (per clip: "length", "loop", and for attacks "windup_end" / "strike_end" in seconds).
## There is one "common" set that every weapon can fall back on, and an optional set per weapon
## (art/animations/blade.glb...). Clips are sampled at a time the game chooses, so the animation
## follows the simulation (hit-stop, attack speed) instead of running on its own clock.
## EXTENDING: a new weapon's animations are a new <weapon>.glb + .json pair; nothing in code changes.

const FOLDER := "res://art/animations/"

static var _cache: Dictionary = {}  ## set name -> AnimationSet (or null when the files do not exist)

var set_name := ""
var _clips: Dictionary = {}  ## clip name -> {"animation": Animation, "rotation": {bone: track}, "position": {bone: track}, "meta": Dictionary}


## The set called `name`, or null when its files do not exist. Sets are loaded once and kept.
static func load_set(name: String) -> RefCounted:
	if _cache.has(name):
		return _cache[name]
	var found: RefCounted = null
	var path := FOLDER + name + ".glb"
	if ResourceLoader.exists(path):
		var candidate := new()
		if candidate._load(name, path):
			found = candidate
	_cache[name] = found
	return found


## The clips inside any .glb (a monster's own model, or a monster set such as art/animations/goblin.glb),
## with their marks from `json_path` (default: the .json next to the file). Null when the file does not
## exist or has no animations. Kept like the named sets (a file that lands later needs a new session).
static func load_file(glb_path: String, json_path: String = "") -> RefCounted:
	var key := glb_path + "|" + json_path
	if _cache.has(key):
		return _cache[key]
	var found: RefCounted = null
	if ResourceLoader.exists(glb_path):
		var candidate := new()
		if candidate._load(glb_path.get_file().get_basename(), glb_path, json_path if json_path != "" else glb_path.get_basename() + ".json"):
			found = candidate
	_cache[key] = found
	return found


static func clear_cache() -> void:
	_cache.clear()


func has_clip(clip: String) -> bool:
	return _clips.has(clip)


func clip_names() -> Array:
	return _clips.keys()


func length(clip: String) -> float:
	return float(_clips[clip]["meta"].get("length", _clips[clip]["animation"].length))


func is_looping(clip: String) -> bool:
	return bool(_clips[clip]["meta"].get("loop", false))


## The moment inside the clip for a point in an attack: `phase` is "windup", "strike" or "recover" and
## `amount` (0..1) how far through that phase the move is. The three phases are stretched over the
## clip's own wind-up / strike / recovery, so the animation always lines up with the move's frames.
func attack_time(clip: String, phase: String, amount: float) -> float:
	var meta: Dictionary = _clips[clip]["meta"]
	var total := length(clip)
	var windup_end := float(meta.get("windup_end", total * 0.3))
	var strike_end := float(meta.get("strike_end", total * 0.5))
	amount = clampf(amount, 0.0, 1.0)
	match phase:
		"windup":
			return windup_end * amount
		"strike":
			return lerpf(windup_end, strike_end, amount)
		"recover":
			return lerpf(strike_end, total, amount)
	return 0.0


## The bones the clip moves, with their values at `time` (seconds; wrapped for looping clips):
## {bone name: {"rotation": Quaternion, "position": Vector3 (only for bones with a position track)}}.
func sample(clip: String, time: float, bone_prefix: String = "") -> Dictionary:
	var entry: Dictionary = _clips[clip]
	var animation: Animation = entry["animation"]
	var total := animation.length
	time = fposmod(time, total) if bool(entry["meta"].get("loop", false)) else clampf(time, 0.0, total)
	var pose := {}
	for bone in entry["rotation"]:
		if not bone_prefix.is_empty() and not str(bone).begins_with(bone_prefix): continue
		pose[bone] = {"rotation": animation.rotation_track_interpolate(entry["rotation"][bone], time)}
	for bone in entry["position"]:
		if not bone_prefix.is_empty() and not str(bone).begins_with(bone_prefix): continue
		if not pose.has(bone):
			pose[bone] = {}
		pose[bone]["position"] = animation.position_track_interpolate(entry["position"][bone], time)
	return pose


func _load(name: String, path: String, json_path: String = "") -> bool:
	var packed := load(path) as PackedScene
	if packed == null:
		return false
	var instance := packed.instantiate()
	var players := instance.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		instance.free()
		return false
	var metadata := _read_metadata(json_path if json_path != "" else FOLDER + name + ".json")
	var player: AnimationPlayer = players[0]
	for library_name in player.get_animation_library_list():
		var library := player.get_animation_library(library_name)
		for clip in library.get_animation_list():
			var animation: Animation = library.get_animation(clip)
			var rotation_tracks := {}
			var position_tracks := {}
			for track in animation.get_track_count():
				var bone := String(animation.track_get_path(track).get_concatenated_subnames())
				match animation.track_get_type(track):
					Animation.TYPE_ROTATION_3D:
						rotation_tracks[bone] = track
					Animation.TYPE_POSITION_3D:
						position_tracks[bone] = track
			_clips[String(clip)] = {"animation": animation, "rotation": rotation_tracks, "position": position_tracks, "meta": metadata.get(String(clip), {})}
	instance.free()
	set_name = name
	return not _clips.is_empty()


func _read_metadata(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
