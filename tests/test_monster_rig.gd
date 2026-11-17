extends RefCounted
## Monster rigging pilot (mummy archer): the shared bow clip library carries exactly the clips a bow monster needs, its marks are
## valid for the sim, the run clip does not drift, the monster keeps every joint a clip animates, and the files stay in budget.
## Tools: tools/monsters/build_clip_library.gd, build_mummy_archer.gd (docs/art/monster_requests/mummy_archer.md).

const AnimationSet := preload("res://client/animation_set.gd")

const LIBRARY := "res://art/animations/monster_clips_bow.glb"
const LIBRARY_SHORT := "res://art/animations/monster_clips_bow_short.glb"
const MARKS := "res://art/animations/monster_clips_bow.json"
const MONSTER := "res://art/monsters/mummy_archer/mummy_archer.glb"
const MONSTER_SHORT := "res://art/monsters/mummy_archer/mummy_archer_short.glb"
const DONOR := "res://art/characters/studio05/split/body_longbow.glb"
const GOBLIN_ARCHER := "res://art/monsters/goblin_archer/goblin_archer.glb"
const CLIPS := ["death", "hit", "idle", "run", "shoot", "volley"]
const EXTRA_JOINTS := ["bandage_upper_L", "bandage_upper_R", "bandage_lower_L", "bandage_lower_R"]
const LIBRARY_BUDGET := 260 * 1024
const MONSTER_BUDGET := 450 * 1024  ## goblin_archer.glb is 560904 bytes
const TRIANGLE_BUDGET := 6000


func run(ctx) -> void:
	var library := AnimationSet.load_file(LIBRARY)
	ctx.check("the shared bow clip library loads", library != null)
	if library == null:
		return
	var names: Array = library.clip_names()
	names.sort()
	ctx.check("the library holds exactly the clips a bow monster needs %s" % [names], names == CLIPS)
	var marks: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MARKS))
	var marks_ok := marks.keys().size() == CLIPS.size()
	for clip in CLIPS:
		var entry: Dictionary = marks.get(clip, {})
		marks_ok = marks_ok and float(entry.get("length", 0.0)) > 0.0 and absf(float(entry.get("length", 0.0)) - library.length(clip)) < 0.03
		if clip in ["shoot", "volley"]:
			var windup := float(entry.get("windup_end", -1.0))
			var strike := float(entry.get("strike_end", -1.0))
			marks_ok = marks_ok and windup > 0.0 and windup < strike and strike < float(entry["length"])
	ctx.check("every clip has a length equal to its animation, and the shots a wind-up end before the strike end before the clip end", marks_ok)
	ctx.check("idle and run loop, the rest play once", library.is_looping("idle") and library.is_looping("run") and not library.is_looping("shoot") and not library.is_looping("death"))
	ctx.check("the run clip states its travel speed (rig units/s) for combat.json run_clip_speed", float(marks["run"].get("travel_per_second", 0.0)) > 0.5)

	var donor_joints := _joint_names(DONOR)
	var monster_joints := _joint_names(MONSTER)
	ctx.check("the monster keeps all 102 donor joints of the shared rig (%d)" % donor_joints.size(), donor_joints.size() == 102 and _missing(donor_joints, monster_joints).is_empty())
	ctx.check("and adds only its declared extra joints %s" % [_missing(monster_joints, donor_joints)], _sorted(_missing(monster_joints, donor_joints)) == _sorted(EXTRA_JOINTS))
	var animated := _animated_bones(LIBRARY)
	ctx.check("the monster has every joint a library clip animates %s" % [_missing(animated, monster_joints)], not animated.is_empty() and _missing(animated, monster_joints).is_empty())
	var unknown := _missing(animated, donor_joints)
	ctx.check("the library animates only donor joints %s" % [unknown], unknown.is_empty())
	var hair := animated.filter(func(bone): return str(bone).begins_with("hair_"))
	ctx.check("the player's hair tracks are not shipped to monsters (%d)" % hair.size(), hair.is_empty())
	ctx.check("the short-legs monster has the same joints", _joint_names(MONSTER_SHORT) == monster_joints)

	# The donor's run clip drifts forward through the Hips; the monster library's must stay in place.
	var donor_drift := _hips_drift(DONOR, "lb_run_forward")
	var run_drift := _hips_drift(LIBRARY, "run")
	ctx.check("the check can fail: the player's own run clip drifts %.2f rig units" % donor_drift, donor_drift > 0.5)
	ctx.check("the library's run clip stays in place (drift %.3f)" % run_drift, absf(run_drift) < 0.02)
	var hips_normal := _hips_y(LIBRARY, "idle")
	var hips_short := _hips_y(LIBRARY_SHORT, "idle")
	ctx.check("the short-legs library rescales the Hips height (%.3f -> %.3f = x0.75)" % [hips_normal, hips_short], absf(hips_short / hips_normal - 0.75) < 0.02)

	var library_size := FileAccess.get_file_as_bytes(LIBRARY).size()
	var monster_size := FileAccess.get_file_as_bytes(MONSTER).size()
	ctx.check("the library file is within budget (%d bytes)" % library_size, library_size <= LIBRARY_BUDGET)
	ctx.check("the monster file is within budget and lighter than the goblin archer (%d bytes)" % monster_size, monster_size <= MONSTER_BUDGET and monster_size < FileAccess.get_file_as_bytes(GOBLIN_ARCHER).size())
	var scene := (load(MONSTER) as PackedScene).instantiate()
	var triangles := 0
	var meshes := scene.find_children("*", "MeshInstance3D", true, false)
	var mesh_names := meshes.map(func(m): return str(m.name))
	for mesh in meshes:
		triangles += (mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	ctx.check("the monster is within the triangle budget (%d)" % triangles, triangles <= TRIANGLE_BUDGET)
	ctx.check("it carries a body, a bow, a string and the nocked 'arrow' the view shows during the draw %s" % [mesh_names], "Monster_MummyArcher_Body" in mesh_names and "Monster_MummyArcher_Bow" in mesh_names and "Monster_MummyArcher_BowString" in mesh_names and "arrow" in mesh_names)
	var influences_ok := true
	for mesh in meshes:
		var weights: PackedFloat32Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_WEIGHTS]
		influences_ok = influences_ok and weights.size() % 4 == 0
		for i in range(0, weights.size(), 4):
			influences_ok = influences_ok and absf(weights[i] + weights[i + 1] + weights[i + 2] + weights[i + 3] - 1.0) < 0.01
	ctx.check("every vertex has at most 4 influences, normalised", influences_ok)
	scene.free()


func _joint_names(path: String) -> Array:
	var scene := (load(path) as PackedScene).instantiate()
	var skeleton := scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var out := []
	for i in skeleton.get_bone_count():
		out.append(skeleton.get_bone_name(i))
	scene.free()
	return out


static func _sorted(values: Array) -> Array:
	var copy := values.duplicate()
	copy.sort()
	return copy


static func _missing(wanted: Array, have: Array) -> Array:
	return wanted.filter(func(name): return not have.has(name))


func _animated_bones(path: String) -> Array:
	var scene := (load(path) as PackedScene).instantiate()
	var player := scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var bones := {}
	for clip in player.get_animation_list():
		var animation := player.get_animation(clip)
		for t in animation.get_track_count():
			bones[String(animation.track_get_path(t).get_concatenated_subnames())] = true
	scene.free()
	return bones.keys().filter(func(bone): return bone != "" and not EXTRA_JOINTS.has(bone))


func _hips_track(animation: Animation) -> int:
	for t in animation.get_track_count():
		if animation.track_get_type(t) == Animation.TYPE_POSITION_3D:
			return t
	return -1


func _hips_drift(path: String, clip: String) -> float:
	var scene := (load(path) as PackedScene).instantiate()
	var animation := (scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer).get_animation(clip)
	var track := _hips_track(animation)
	var drift := 0.0
	if track >= 0:
		drift = (animation.track_get_key_value(track, animation.track_get_key_count(track) - 1) as Vector3).z - (animation.track_get_key_value(track, 0) as Vector3).z
	scene.free()
	return drift


func _hips_y(path: String, clip: String) -> float:
	var scene := (load(path) as PackedScene).instantiate()
	var animation := (scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer).get_animation(clip)
	var y: float = (animation.track_get_key_value(_hips_track(animation), 0) as Vector3).y
	scene.free()
	return y
