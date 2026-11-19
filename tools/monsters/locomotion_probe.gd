extends SceneTree
## Read-only survey of the donor locomotion clips: per clip whose name matches a filter, length, Hips forward travel (rig units/s),
## stride (max foot-to-foot distance along z), hips bob and the feet's lowest point, so a monster's walk/run can be picked and its
## run_clip_speed derived.
##   godot --headless --path . --script res://tools/monsters/locomotion_probe.gd -- res://art/characters/studio05/split/body_greatsword.glb [filter...]

const Rig := preload("res://tools/monsters/rig_common.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var root := (load(args[0]) as PackedScene).instantiate()
	var sk := Rig.donor_skeleton(root)
	var player := Rig.donor_player(root)
	var filters: Array = args.slice(1) if args.size() > 1 else ["run", "walk"]
	var lf := sk.find_bone("mixamorig_LeftFoot")
	var rf := sk.find_bone("mixamorig_RightFoot")
	var hips := sk.find_bone("mixamorig_Hips")
	var names := player.get_animation_list()
	for clip in names:
		var hit := false
		for f in filters:
			hit = hit or String(clip).contains(f)
		if not hit:
			continue
		var anim := player.get_animation(clip)
		var tracks := Rig.clip_tracks(anim)
		var t := 0.0
		var max_stride := 0.0
		var max_width := 0.0
		var min_width := 9.0
		var hy_min := 9.0
		var hy_max := -9.0
		var first := Vector3.ZERO
		var last := Vector3.ZERO
		var min_foot := 9.0
		while t <= anim.length + 0.0001:
			Rig.pose_at(sk, anim, tracks, t)
			var l := _g(sk, lf).origin
			var r := _g(sk, rf).origin
			var h := _g(sk, hips).origin
			if t == 0.0:
				first = h
			last = h
			max_stride = maxf(max_stride, absf(l.z - r.z))
			max_width = maxf(max_width, absf(l.x - r.x))
			min_width = minf(min_width, absf(l.x - r.x))
			hy_min = minf(hy_min, h.y)
			hy_max = maxf(hy_max, h.y)
			min_foot = minf(min_foot, minf(l.y, r.y))
			t += 1.0 / 30.0
		var travel := last - first
		print("%s len=%.3f travel=(%.2f,%.2f) per_s=%.3f stride=%.3f feet_x=%.3f..%.3f hips_y=%.3f..%.3f foot_min=%.3f" % [clip, anim.length, travel.x, travel.z, travel.z / anim.length, max_stride, min_width, max_width, hy_min, hy_max, min_foot])
	root.free()
	quit()


static func _g(sk: Skeleton3D, i: int) -> Transform3D:
	var t := sk.get_bone_pose(i)
	var p := sk.get_bone_parent(i)
	while p >= 0:
		t = sk.get_bone_pose(p) * t
		p = sk.get_bone_parent(p)
	return t
