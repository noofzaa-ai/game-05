extends SceneTree
## Builds a monster clip library (skeleton-only .glb + .json of marks) out of the player's longbow clips.
## Only the clips a bow monster needs are copied, each baked at 30 fps and key-reduced; the player's files are only read.
##   godot --headless --path . --script res://tools/monsters/build_clip_library.gd
## Outputs:
##   art/animations/monster_clips_bow.glb/.json        shared library, the player's proportions (any bow monster)
##   art/animations/monster_clips_bow_short.glb/.json  pilot: the same clips with the Hips travel rescaled for legs at LEG_SCALE
## Then re-import (godot --headless --path . --import).

const Rig := preload("res://tools/monsters/rig_common.gd")

const LEG_SCALE := 0.75  ## the short-legs pilot variant (must match build_mummy_archer.gd)
## clip name -> segments [donor clip, from, to, speed] played one after the other (speed 2 = twice as fast).
## shoot  = the player's own two-part shot (class_skills.json heartseeker: lb_draw_arrow then lb_aim_recoil, released at 0.18 s of the recoil).
## volley = the same with a slow draw, so it reads as the telegraphed move.
const CLIPS := {
	"idle": {"segs": [["lb_idle_01", 0.0, 5.1, 1.0]], "loop": true},
	"run": {"segs": [["lb_run_forward", 0.0, 0.8833333, 1.0]], "loop": true, "strip_travel": true},  ## the donor's run drifts 0.947 rig units forward through the Hips: stripped, the speed goes to the marks
	"shoot": {"segs": [["lb_draw_arrow", 0.0, 1.017, 1.35], ["lb_aim_recoil", 0.17, 0.70, 1.0]], "loop": false, "release_in_seg": 1, "release_src": 0.18, "strike_src": 0.25},
	"volley": {"segs": [["lb_draw_arrow", 0.0, 1.017, 1.0], ["lb_aim_recoil", 0.17, 0.70, 1.0]], "loop": false, "release_in_seg": 1, "release_src": 0.18, "strike_src": 0.25},
	"hit": {"segs": [["lb_react_small_from_front", 0.0, 0.62, 1.0]], "loop": false},
	"death": {"segs": [["lb_death_forward_01", 0.0, 3.1833, 1.0]], "loop": false},
}
## Optional sway tracks for the loose-bandage bones of a mummy (name -> parent donor bone). A monster without them ignores the tracks.
const EXTRA_BONES := {"bandage_upper_L": "mixamorig_LeftArm", "bandage_upper_R": "mixamorig_RightArm", "bandage_lower_L": "mixamorig_LeftForeArm", "bandage_lower_R": "mixamorig_RightForeArm"}


func _init() -> void:
	var donor := Rig.load_donor()
	var src_skeleton := Rig.donor_skeleton(donor)
	var player := Rig.donor_player(donor)
	_build("monster_clips_bow", donor, src_skeleton, player, 1.0)
	_build("monster_clips_bow_short", donor, src_skeleton, player, LEG_SCALE)
	quit()


func _build(file_name: String, donor: Node, src_skeleton: Skeleton3D, player: AnimationPlayer, hips_scale: float) -> void:
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
	for clip in CLIPS:
		var built := _compose(clip, CLIPS[clip], player, hips_scale)
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
		err = document.write_to_filesystem(state, "res://art/animations/%s.glb" % file_name)
	if err == OK:
		Rig.minify_glb("res://art/animations/%s.glb" % file_name)
	print(file_name, ": export err=", err, " bones animated=", bones_used.size())
	var json_text := JSON.stringify(marks, "  ")
	var file := FileAccess.open("res://art/animations/%s.json" % file_name, FileAccess.WRITE)
	file.store_string(json_text + "\n")
	file.close()
	root.free()


## A monster gets the body, not the player's hair (secondary motion baked into the clips) or finger tracks
## (monster hands deform as one piece, so 40 finger tracks per clip would only cost file size).
static func _wanted(bone: String) -> bool:
	return not bone.begins_with("hair_") and not (bone.contains("Hand") and bone.length() > 17 and bone[-1].is_valid_int())


## One clip: the segments baked at 30 fps in order; Hips travel scaled; the optional tail sway added to idle/run.
func _compose(clip: String, spec: Dictionary, player: AnimationPlayer, hips_scale: float) -> Dictionary:
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
			rot_v.append(anim.rotation_track_interpolate(tr["rot"], src_time))
			if has_pos:
				pos_v.append((anim.position_track_interpolate(tr["pos"], src_time) as Vector3) * hips_scale)
		if has_pos and spec.get("strip_travel", false):
			var drift: float = (pos_v[-1] as Vector3).z - (pos_v[0] as Vector3).z
			travel = drift / hips_scale
			for i in pos_v.size():
				var v: Vector3 = pos_v[i]
				v.z -= drift * float(rot_t[i]) / total
				pos_v[i] = v
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


