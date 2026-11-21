extends SceneTree
## Hips height and both hands' height + speed of donor clips every 1/15 s (to find the take-off, apex and landing of a leap clip and
## the moment of a slam). Read only.
##   godot --headless --path . --script res://tools/monsters/hips_height_probe.gd -- <body.glb> clip ...

const Rig := preload("res://tools/monsters/rig_common.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var root := (load(args[0]) as PackedScene).instantiate()
	var sk := Rig.donor_skeleton(root)
	var player := Rig.donor_player(root)
	var hips := sk.find_bone("mixamorig_Hips")
	var rh := sk.find_bone("mixamorig_RightHand")
	var lh := sk.find_bone("mixamorig_LeftHand")
	for i in range(1, args.size()):
		var anim := player.get_animation(args[i])
		var tracks := Rig.clip_tracks(anim)
		var t := 0.0
		var line := ""
		var prev_r := Vector3.ZERO
		while t <= anim.length + 0.0001:
			Rig.pose_at(sk, anim, tracks, t)
			var r := _g(sk, rh).origin
			line += "%.2f:h%.2f r%.2f l%.2f v%d  " % [t, _g(sk, hips).origin.y, r.y, _g(sk, lh).origin.y, int((r - prev_r).length() * 15.0 * 100.0)]
			prev_r = r
			t += 1.0 / 15.0
		print("== ", args[i], " len=%.2f" % anim.length)
		print(line)
	root.free()
	quit()


static func _g(sk: Skeleton3D, i: int) -> Transform3D:
	var t := sk.get_bone_pose(i)
	var p := sk.get_bone_parent(i)
	while p >= 0:
		t = sk.get_bone_pose(p) * t
		p = sk.get_bone_parent(p)
	return t
