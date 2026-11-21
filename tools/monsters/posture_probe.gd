extends SceneTree
## Read-only posture survey of donor locomotion clips (animator 2026-11-21, Boss: "the orc run looks like crawling"): per clip whose
## name matches a filter, the trunk lean (Hips -> Neck from vertical, + = forward, mean / max), the head lean, the foot lift (how high
## the swinging foot rises, rig units), the hand swing along z (left / right, rig units) and the Hips forward travel per second.
##   godot --headless --path . --script res://tools/monsters/posture_probe.gd -- <donor.glb> [filter...]

const Rig := preload("res://tools/monsters/rig_common.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	# a library built into build/ is not imported yet: read the file straight (no import step needed while iterating)
	var root: Node = Rig.load_gltf(args[0]) if args[0].begins_with("res://build/") else (load(args[0]) as PackedScene).instantiate()
	var sk := Rig.donor_skeleton(root)
	var player := Rig.donor_player(root)
	var filters: Array = args.slice(1) if args.size() > 1 else ["run", "walk"]
	var verbose := filters.has("--frames")
	filters.erase("--frames")
	var ids := {}
	for b in ["mixamorig_Hips", "mixamorig_Neck", "mixamorig_Head", "mixamorig_LeftFoot", "mixamorig_RightFoot", "mixamorig_LeftHand", "mixamorig_RightHand"]:
		ids[b] = sk.find_bone(b)
	for clip in player.get_animation_list():
		var hit := false
		for f in filters:
			hit = hit or (String(clip) == f if verbose else String(clip).contains(f))
		if not hit:
			continue
		var anim := player.get_animation(clip)
		var tracks := Rig.clip_tracks(anim)
		var t := 0.0
		var leans := []
		var foot_min := 9.0
		var foot_max := -9.0
		var lh := [9.0, -9.0]
		var rh := [9.0, -9.0]
		var first := Vector3.ZERO
		var last := Vector3.ZERO
		var shrug := 0.0
		while t <= anim.length + 0.0001:
			Rig.pose_at(sk, anim, tracks, t)
			for s in ["mixamorig_LeftShoulder", "mixamorig_RightShoulder"]:
				var si := sk.find_bone(s)
				var d := sk.get_bone_rest(si).basis.get_rotation_quaternion().inverse() * sk.get_bone_pose_rotation(si)
				shrug = maxf(shrug, rad_to_deg(absf(d.normalized().get_angle())) if d.w >= 0 else rad_to_deg((-d).normalized().get_angle()))
			var h := _g(sk, ids["mixamorig_Hips"]).origin
			var n := _g(sk, ids["mixamorig_Neck"]).origin
			var d := n - h
			leans.append(rad_to_deg(atan2(d.z, d.y)))
			var l := _g(sk, ids["mixamorig_LeftFoot"]).origin
			var r := _g(sk, ids["mixamorig_RightFoot"]).origin
			foot_min = minf(foot_min, minf(l.y, r.y))
			foot_max = maxf(foot_max, maxf(l.y, r.y))
			var a := _g(sk, ids["mixamorig_LeftHand"]).origin.z - h.z
			var b := _g(sk, ids["mixamorig_RightHand"]).origin.z - h.z
			lh = [minf(lh[0], a), maxf(lh[1], a)]
			rh = [minf(rh[0], b), maxf(rh[1], b)]
			if verbose:
				var up := _g(sk, ids["mixamorig_Hips"]).basis.y
				print("  t=%.2f lean=%.1f hips_pitch=%.1f L=(%.2f,%.3f) R=(%.2f,%.3f) handL=%.2f handR=%.2f" % [t, leans[-1], rad_to_deg(atan2(up.z, up.y)), l.z - h.z, l.y, r.z - h.z, r.y, a, b])
			if t == 0.0:
				first = h
			last = h
			t += 1.0 / 30.0
		var mean := 0.0
		for v in leans:
			mean += v
		mean /= leans.size()
		print("%s len=%.2f lean mean=%.1f max=%.1f foot_lift=%.3f handL=%.2f..%.2f handR=%.2f..%.2f per_s=%.3f shoulder_max=%.0f" % [clip,anim.length, mean, leans.max(), foot_max - foot_min, lh[0], lh[1], rh[0], rh[1], (last.z - first.z) / anim.length, shrug])
	root.free()
	quit()


static func _g(sk: Skeleton3D, i: int) -> Transform3D:
	var t := sk.get_bone_pose(i)
	var p := sk.get_bone_parent(i)
	while p >= 0:
		t = sk.get_bone_pose(p) * t
		p = sk.get_bone_parent(p)
	return t
