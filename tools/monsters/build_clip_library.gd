extends SceneTree
## Builds a monster clip library (skeleton-only .glb + .json of marks) out of the player's longbow clips.
## Only the clips a bow monster needs are copied, each baked at 30 fps and key-reduced; the player's files are only read.
##   godot --headless --path . --script res://tools/monsters/build_clip_library.gd
##   godot --headless --path . --script res://tools/monsters/build_clip_library.gd -- bow [sword_shield greatsword magic] [--out=res://dir/] [--tol=0.35]
## Output: art/animations/monster_clips_<stance>.glb + .json (the player's proportions). Leg proportions of a monster are NOT baked in:
## the monster's data field hips_scale rescales the Hips translation at runtime (client/animation_set.gd).
## Then re-import (godot --headless --path . --import).

const Rig := preload("res://tools/monsters/rig_common.gd")

## Libraries, one per weapon stance (a monster loads ONE: its own idle/run/hit/death + the attacks of its stance).
## Each is a skeleton-only glb named monster_clips_<stance>.glb with a .json of marks next to it.
## Clip entries: clip name -> {"segs": [[donor clip, from, to, speed]...] played one after the other (speed 2 = twice as fast)}.
## Only "bow" is shipped today (art/animations). The others are measured (sizes in docs/art/monster_requests/mummy_archer.md) and are
## built when the first monster of that stance exists: check the clip choices with the animator before shipping.
## bow shoot  = the player's own two-part shot (class_skills.json heartseeker: lb_draw_arrow then lb_aim_recoil, released at 0.18 s of the recoil).
## bow volley = the same with a slow draw, so it reads as the telegraphed move.
const LIBRARIES := {
	"bow": {"donor": "res://art/characters/studio05/split/body_longbow.glb", "clips": {
		"idle": {"segs": [["lb_idle_01", 0.0, 5.1, 1.0]], "loop": true},
		"run": {"segs": [["lb_run_forward", 0.0, 0.8833333, 1.0]], "loop": true, "strip_travel": true},  ## the donor's run drifts 0.947 rig units forward through the Hips: stripped, the speed goes to the marks
		"shoot": {"segs": [["lb_draw_arrow", 0.0, 1.017, 1.35], ["lb_aim_recoil", 0.17, 0.70, 1.0]], "loop": false, "release_in_seg": 1, "release_src": 0.18, "strike_src": 0.25},
		"volley": {"segs": [["lb_draw_arrow", 0.0, 1.017, 1.0], ["lb_aim_recoil", 0.17, 0.70, 1.0]], "loop": false, "release_in_seg": 1, "release_src": 0.18, "strike_src": 0.25},
		"hit": {"segs": [["lb_react_small_from_front", 0.0, 0.62, 1.0]], "loop": false},
		"death": {"segs": [["lb_death_forward_01", 0.0, 3.1833, 1.0]], "loop": false},
	}},
	## sword_shield (v1 shipped 2026-11-17: mummy + mummy_knight). Picked from contact sheets of the donor clips
	## (tools/monsters/donor_clip_sheet.gd): only clips whose Hips stay in place (attack, attack_2, attack_3 lunge 0.8-1.1 rig units).
	## attack_1 = slash: sword drawn back over the shoulder by 1.26 s, diagonal cut 1.40-1.70 s (hand speed peak 1.53 s).
	## attack_2 = attack_4: sword raised overhead by 1.27 s, held, chopped down 1.52-1.76 s (the telegraphed overhead).
	## death = the stagger, the sword raised, the fall lands at 4.38 s (the first 3.0 s never reached the floor): 0.4-4.6 s at 1.4x.
	"sword_shield": {"donor": "res://art/characters/studio05/split/body_sword_shield.glb", "clips": {
		"idle": {"segs": [["idle_4", 0.0, 6.375, 1.0]], "loop": true},
		"run": {"segs": [["run", 0.0, 1.7916, 1.0]], "loop": true, "strip_travel": true},  ## not run_2: that one runs BACKWARD (-0.74 rig units)
		"attack_1": {"segs": [["slash", 0.35, 2.3, 1.0]], "loop": false, "release_in_seg": 0, "release_src": 1.4, "strike_src": 1.7},
		"attack_2": {"segs": [["attack_4", 0.15, 2.4, 1.0]], "loop": false, "release_in_seg": 0, "release_src": 1.52, "strike_src": 1.76},
		"hit": {"segs": [["impact", 0.0, 0.62, 1.0]], "loop": false},
		"death": {"segs": [["death", 0.4, 4.6, 1.4]], "loop": false},
	}},
	## greatsword (v1 shipped 2026-11-17: mummy_boss, the Pharaoh; mirrors goblin_chief's quick chop + telegraphed leaping lunge).
	## attack_1 = gs_slash: raised 0.29-0.57 s, diagonal cut 0.60-0.86 s. attack_2 = gs_jump_attack: the leap, slam at about 1.07 s;
	## the donor travels 0.97 rig units forward (about 5 m on a 2.6 m boss): `pin_travel` keeps 15% of it (a short lunge) so the
	## boss lands near its hit box. attack_3 = gs_high_spin_attack (the whirl, travel pinned to 0). death = gs_death (lands by 1.6 s).
	"greatsword": {"donor": "res://art/characters/studio05/split/body_greatsword.glb", "clips": {
		"idle": {"segs": [["gs_idle", 0.0, 2.0166, 1.0]], "loop": true},
		"run": {"segs": [["gs_run_2", 0.0, 0.6166, 1.0]], "loop": true, "strip_travel": true},  ## not gs_run: that one runs BACKWARD
		"attack_1": {"segs": [["gs_slash", 0.0, 1.28, 1.0]], "loop": false, "release_in_seg": 0, "release_src": 0.6, "strike_src": 0.86},
		"attack_2": {"segs": [["gs_jump_attack", 0.0, 2.18, 1.0]], "loop": false, "pin_travel": 0.15, "release_in_seg": 0, "release_src": 0.97, "strike_src": 1.17},
		"attack_3": {"segs": [["gs_high_spin_attack", 0.0, 1.88, 1.0]], "loop": false, "pin_travel": 0.0, "release_in_seg": 0, "release_src": 0.84, "strike_src": 1.26},
		"hit": {"segs": [["gs_impact", 0.0, 0.62, 1.0]], "loop": false},
		"death": {"segs": [["gs_death", 0.0, 2.4166, 1.0]], "loop": false},
	}},
	## magic (v1 shipped 2026-11-17: mummy_mage; mirrors goblin_mage cast / cast_aoe / blink).
	## cast = mg_lite_1h_magic_attack_01: staff swept back, thrust forward at 1.0 s (hand speed peak 0.80 s).
	## cast_aoe = mg_lite_2h_magic_area_attack_02: gathers, arms flung wide at 1.8-2.2 s. blink = mg_spell_1h_cast_spell_01 at 2x:
	## the staff raised overhead (0.76-1.01 s) then lowered, short like the goblin mage's blink (0.47 s).
	"magic": {"donor": "res://art/characters/studio05/split/body_magic.glb", "clips": {
		"idle": {"segs": [["mg_lite_idle", 0.0, 1.8833, 1.0]], "loop": true},
		"run": {"segs": [["mg_lite_run_forward", 0.0, 0.75, 1.0]], "loop": true, "strip_travel": true},
		"cast": {"segs": [["mg_lite_1h_magic_attack_01", 0.0, 2.1, 1.0]], "loop": false, "release_in_seg": 0, "release_src": 0.95, "strike_src": 1.15},
		"cast_aoe": {"segs": [["mg_lite_2h_magic_area_attack_02", 0.0, 3.0, 1.0]], "loop": false, "release_in_seg": 0, "release_src": 1.75, "strike_src": 2.1},
		"blink": {"segs": [["mg_spell_1h_cast_spell_01", 0.2, 1.4, 2.0]], "loop": false, "release_in_seg": 0, "release_src": 0.76, "strike_src": 0.9},
		"hit": {"segs": [["mg_lite_react_small_from_front", 0.0, 0.62, 1.0]], "loop": false},
		"death": {"segs": [["mg_lite_react_death_backward", 0.0, 3.6333, 1.0]], "loop": false},
	}},
	## wizard_boss (2026-11-18: mummy_high_wizard, the Boss's own model). Base = the magic donor; the first five clips are copied, the
	## last three are NEW keyframed clips: a donor cast with an ADDITIVE keyed layer ("add": bone -> [[time s, rx, ry, rz degrees]...], eased,
	## multiplied onto the donor rotation in the parent's space; "hover": Hips height keys, rig units) so the boss rises, flings its arms and spins.
	## cast = mg_lite_1h_magic_attack_01 (the bolt). cast_aoe = mg_lite_2h_magic_area_attack_02 (the big ground cast).
	"wizard_boss": {"donor": "res://art/characters/studio05/split/body_magic.glb", "clips": {
		"idle": {"segs": [["mg_lite_idle", 0.0, 1.8833, 1.0]], "loop": true},
		"run": {"segs": [["mg_lite_run_forward", 0.0, 0.75, 1.0]], "loop": true, "strip_travel": true},
		"cast": {"segs": [["mg_lite_1h_magic_attack_01", 0.0, 2.1, 1.0]], "loop": false, "release_in_seg": 0, "release_src": 0.95, "strike_src": 1.15},
		"cast_aoe": {"segs": [["mg_lite_2h_magic_area_attack_02", 0.0, 3.0, 1.0]], "loop": false, "release_in_seg": 0, "release_src": 1.75, "strike_src": 2.1},
		"summon": {"segs": [["mg_spell_2h_cast_spell_01", 0.0, 2.18, 0.8]], "loop": false, "release_in_seg": 0, "release_src": 1.0, "strike_src": 1.4,
			"add": {"mixamorig_Spine": [[0.0, 0, 0, 0], [0.9, -14, 0, 0], [1.6, -14, 0, 0], [2.7, 0, 0, 0]],
				"mixamorig_Spine2": [[0.0, 0, 0, 0], [0.9, -12, 0, 0], [1.6, -12, 0, 0], [2.7, 0, 0, 0]],
				"mixamorig_Head": [[0.0, 0, 0, 0], [0.9, -16, 0, 0], [1.6, -16, 0, 0], [2.7, 0, 0, 0]]},
			"hover": [[0.0, 0.0], [1.0, 0.0], [1.5, 0.09], [2.2, 0.09], [2.7, 0.0]]},
		"starfall": {"segs": [["mg_spell_2h_magic_attack_03", 0.0, 4.32, 1.0]], "loop": false, "release_in_seg": 0, "release_src": 2.3, "strike_src": 3.0,
			"add": {"mixamorig_Spine": [[0.0, 0, 0, 0], [1.5, -12, 0, 0], [2.6, -12, 0, 0], [3.4, 6, 0, 0], [4.32, 0, 0, 0]],
				"mixamorig_Head": [[0.0, 0, 0, 0], [1.5, -22, 0, 0], [2.6, -22, 0, 0], [3.4, 8, 0, 0], [4.32, 0, 0, 0]]},
			"hover": [[0.0, 0.0], [1.2, 0.0], [1.9, 0.16], [3.0, 0.16], [3.7, 0.0], [4.32, 0.0]]},
		"sandstorm": {"segs": [["mg_spell_2h_magic_attack_02", 0.0, 2.65, 0.8]], "loop": false, "release_in_seg": 0, "release_src": 1.5, "strike_src": 2.2,
			"add": {"mixamorig_Hips": [[0.0, 0, 0, 0], [0.9, 0, 0, 0], [1.4, 0, 120, 0], [2.4, 0, 560, 0], [3.0, 0, 720, 0], [3.3, 0, 720, 0]]},
			"hover": [[0.0, 0.0], [1.0, 0.0], [1.5, 0.06], [2.6, 0.06], [3.3, 0.0]]},
		"hit": {"segs": [["mg_lite_react_small_from_front", 0.0, 0.62, 1.0]], "loop": false},
		"death": {"segs": [["mg_lite_react_death_backward", 0.0, 3.6333, 1.0]], "loop": false},
	}},
}
## Optional sway tracks for the loose-bandage bones of a mummy (name -> parent donor bone). A monster without them ignores the tracks.
const EXTRA_BONES := {"bandage_upper_L": "mixamorig_LeftArm", "bandage_upper_R": "mixamorig_RightArm", "bandage_lower_L": "mixamorig_LeftForeArm", "bandage_lower_R": "mixamorig_RightForeArm"}


func _init() -> void:
	var args := OS.get_cmdline_user_args()  ## [stance...] [--out=res://dir/] [--tol=<degrees>]
	var out_dir := "res://art/animations/"
	var stances := []
	for arg in args:
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
		elif arg.begins_with("--tol="):
			Rig.rot_tol = deg_to_rad(float(arg.substr(6)))
		else:
			stances.append(arg)
	if stances.is_empty():
		stances = ["bow"]
	var donor := Rig.load_donor()
	var src_skeleton := Rig.donor_skeleton(donor)
	DirAccess.make_dir_recursive_absolute(out_dir)
	for stance in stances:
		var spec: Dictionary = LIBRARIES[stance]
		var stance_donor := (load(spec["donor"]) as PackedScene).instantiate()
		_build("monster_clips_" + stance, out_dir, spec["clips"], src_skeleton, Rig.donor_player(stance_donor))
		stance_donor.free()
	quit()


func _build(file_name: String, out_dir: String, clips: Dictionary, src_skeleton: Skeleton3D, player: AnimationPlayer) -> void:
	var root := Node3D.new()
	root.name = "monster_clips"
	var rig := Node3D.new()
	rig.name = "rig"
	root.add_child(rig)
	var skeleton := Rig.copy_skeleton(src_skeleton)
	# The optional loose-bandage bones (a mummy's extra bones) hang from the arms.
	for extra in EXTRA_BONES:
		var index := skeleton.get_bone_count()
		skeleton.add_bone(extra)
		skeleton.set_bone_parent(index, skeleton.find_bone(EXTRA_BONES[extra]))
		skeleton.set_bone_rest(index, Transform3D(Basis(), Vector3(0, -0.02, -0.03)))
	skeleton.reset_bone_poses()
	rig.add_child(skeleton)
	# A skeleton with no skin is imported as plain nodes (tracks without bone names): one tiny skinned triangle, weighted to the
	# Root joint and binding every joint, makes the importer build a real Skeleton3D (as the goblin libraries have).
	var skin := Skin.new()
	for i in skeleton.get_bone_count():
		skin.add_named_bind(skeleton.get_bone_name(i), skeleton.get_bone_global_rest(i).affine_inverse())
	var tri_arrays := []
	tri_arrays.resize(Mesh.ARRAY_MAX)
	tri_arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(0.001, 0, 0), Vector3(0, 0.001, 0)])
	tri_arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	tri_arrays[Mesh.ARRAY_BONES] = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	tri_arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0])
	tri_arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	var tri_mesh := ArrayMesh.new()
	tri_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tri_arrays)
	var anchor := MeshInstance3D.new()
	anchor.name = "skin_anchor"
	anchor.mesh = tri_mesh
	anchor.skin = skin
	skeleton.add_child(anchor)
	anchor.skeleton = NodePath("..")
	anchor.owner = root
	var anim_player := AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	root.add_child(anim_player)
	var library := AnimationLibrary.new()
	var marks := {}
	var bones_used := {}
	for clip in clips:
		var built := _compose(clip, clips[clip], player)
		var animation: Animation = built["animation"]
		library.add_animation(clip, animation)
		marks[clip] = built["marks"]
		for t in animation.get_track_count():
			bones_used[String(animation.track_get_path(t).get_concatenated_subnames())] = true
	anim_player.add_animation_library("", library)
	for node in [rig, skeleton, anim_player]:
		node.owner = root
	var state := GLTFState.new()
	var document := GLTFDocument.new()
	var err := document.append_from_scene(root, state)
	if err == OK:
		err = document.write_to_filesystem(state, out_dir + file_name + ".glb")
	if err == OK:
		Rig.minify_glb(out_dir + file_name + ".glb")
	print(file_name, ": export err=", err, " bones animated=", bones_used.size())
	var json_text := JSON.stringify(marks, "  ")
	var file := FileAccess.open(out_dir + file_name + ".json", FileAccess.WRITE)
	file.store_string(json_text + "\n")
	file.close()
	root.free()


## A monster gets the body, not the player's hair (secondary motion baked into the clips) or finger tracks
## (monster hands deform as one piece, so 40 finger tracks per clip would only cost file size).
static func _wanted(bone: String) -> bool:
	return not bone.begins_with("hair_") and not (bone.contains("Hand") and bone.length() > 17 and bone[-1].is_valid_int())


## One clip: the segments baked at 30 fps in order; Hips travel scaled; the optional tail sway added to idle/run.
func _compose(clip: String, spec: Dictionary, player: AnimationPlayer) -> Dictionary:
	var segs: Array = spec["segs"]
	var starts := []
	var total := 0.0
	for seg in segs:
		starts.append(total)
		total += (float(seg[2]) - float(seg[1])) / float(seg[3])
	var frames := int(round(total * Rig.FPS))
	var times := []
	for f in frames + 1:
		times.append(minf(f / Rig.FPS, total))
	if absf(float(times[-1]) - total) > 0.0001:
		times.append(total)
	var out := Animation.new()
	out.length = total
	out.loop_mode = Animation.LOOP_LINEAR if spec["loop"] else Animation.LOOP_NONE
	# The tracks of the first segment's clip are the same bones for every donor clip.
	var first: Animation = player.get_animation(segs[0][0])
	var path_of := {}
	for t in first.get_track_count():
		path_of[String(first.track_get_path(t).get_concatenated_subnames()) + "|" + str(first.track_get_type(t))] = first.track_get_path(t)
	var tracks_per_seg := []
	for seg in segs:
		tracks_per_seg.append(Rig.clip_tracks(player.get_animation(seg[0])))
	var bones: Array = tracks_per_seg[0].keys()
	var travel := 0.0
	for bone in bones:
		if not _wanted(bone):
			continue
		var has_pos: bool = tracks_per_seg[0][bone]["pos"] >= 0
		var rot_t := []
		var rot_v := []
		var pos_v := []
		for time in times:
			var s := segs.size() - 1
			for k in segs.size():
				if time < float(starts[k]) + (float(segs[k][2]) - float(segs[k][1])) / float(segs[k][3]) - 0.00001:
					s = k
					break
			var src_time: float = float(segs[s][1]) + (time - float(starts[s])) * float(segs[s][3])
			src_time = clampf(src_time, 0.0, player.get_animation(segs[s][0]).length)
			var anim: Animation = player.get_animation(segs[s][0])
			var tr: Dictionary = tracks_per_seg[s][bone]
			rot_t.append(time)
			var q: Quaternion = anim.rotation_track_interpolate(tr["rot"], src_time)
			if spec.has("add") and (spec["add"] as Dictionary).has(bone):
				q = _layer(spec["add"][bone], time) * q
			rot_v.append(q)
			if has_pos:
				var pv: Vector3 = anim.position_track_interpolate(tr["pos"], src_time)
				if spec.has("hover") and bone == "mixamorig_Hips":
					pv.y += _ease_keys(spec["hover"], time)
				pos_v.append(pv)
		if has_pos and spec.get("strip_travel", false):
			var drift: float = (pos_v[-1] as Vector3).z - (pos_v[0] as Vector3).z
			travel = drift
			for i in pos_v.size():
				var v: Vector3 = pos_v[i]
				v.z -= drift * float(rot_t[i]) / total
				pos_v[i] = v
		if has_pos and spec.has("pin_travel"):
			# an attack that lunges far: the Hips' ground travel (x, z) is cut to the kept fraction, height untouched
			var keep := float(spec["pin_travel"])
			var start: Vector3 = pos_v[0]
			for i in pos_v.size():
				var v: Vector3 = pos_v[i]
				pos_v[i] = Vector3(start.x + (v.x - start.x) * keep, v.y, start.z + (v.z - start.z) * keep)
		var rot_reduced := Rig.reduce_keys(rot_t, rot_v, true)
		var path := NodePath("rig/Skeleton3D:" + bone)
		var rt := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(rt, path)
		for i in rot_reduced[0].size():
			out.rotation_track_insert_key(rt, rot_reduced[0][i], rot_reduced[1][i])
		if has_pos:
			var pos_reduced := Rig.reduce_keys(rot_t, pos_v, false)
			var pt := out.add_track(Animation.TYPE_POSITION_3D)
			out.track_set_path(pt, path)
			for i in pos_reduced[0].size():
				out.position_track_insert_key(pt, pos_reduced[0][i], pos_reduced[1][i])
	if clip == "idle" or clip == "run":
		_add_tail_sway(out, total, 0.07 if clip == "idle" else 0.16, 3.0 if clip == "idle" else 1.0)
	var meta := {"length": snappedf(total, 0.0001), "loop": bool(spec["loop"])}
	if travel != 0.0:
		meta["travel_per_second"] = snappedf(travel / total, 0.001)  ## rig units per second at the donor's size
	var key_count := 0
	for t in out.get_track_count():
		key_count += out.track_get_key_count(t)
	print("  clip ", clip, " length=", snappedf(total, 0.001), " tracks=", out.get_track_count(), " keys=", key_count)
	if spec.has("release_in_seg"):
		var k: int = spec["release_in_seg"]
		var seg_start: float = float(starts[k])
		var from: float = float(segs[k][1])
		var speed: float = float(segs[k][3])
		meta["windup_end"] = snappedf(seg_start + (float(spec["release_src"]) - from) / speed, 0.0001)
		meta["strike_end"] = snappedf(seg_start + (float(spec["strike_src"]) - from) / speed, 0.0001)
	return {"animation": out, "marks": meta}


## Eased value of keys [[t, v]...] at time t (smoothstep between keys, held outside).
static func _ease_keys(keys: Array, t: float) -> float:
	if t <= float(keys[0][0]):
		return float(keys[0][1])
	for i in range(1, keys.size()):
		if t <= float(keys[i][0]):
			var a: float = keys[i - 1][0]
			var b: float = keys[i][0]
			var w := smoothstep(0.0, 1.0, (t - a) / maxf(b - a, 0.0001))
			return lerpf(float(keys[i - 1][1]), float(keys[i][1]), w)
	return float(keys[-1][1])


## The additive rotation of a layer at time t: keys [[t, rx, ry, rz degrees]...], each component eased.
static func _layer(keys: Array, t: float) -> Quaternion:
	var c := []
	for k in 3:
		c.append(_ease_keys(keys.map(func(key): return [key[0], key[k + 1]]), t))
	return Quaternion.from_euler(Vector3(deg_to_rad(c[0]), deg_to_rad(c[1]), deg_to_rad(c[2])))


## The tail sways with a wave running down its three bones (a new, monster-only track set).
func _add_tail_sway(out: Animation, total: float, amplitude: float, cycles_per_clip: float) -> void:
	var steps := 24
	var names := EXTRA_BONES.keys()
	for i in names.size():
		var track := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(track, NodePath("rig/Skeleton3D:" + names[i]))
		for s in steps + 1:
			var phase := float(s) / steps * TAU * cycles_per_clip - i * 0.9
			out.rotation_track_insert_key(track, total * s / steps, Quaternion(Vector3.RIGHT, amplitude * sin(phase)) * Quaternion(Vector3.FORWARD, amplitude * 0.5 * sin(phase * 0.5)))


