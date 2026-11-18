extends SceneTree
## Measures donor clips to pick monster attack segments: per clip, the right/left hand speed (rig units/s) every 1/15 s and the
## moments of peak speed (the strike), plus hips travel. Read only.
##   godot --headless --path . --script res://tools/monsters/clip_probe.gd -- res://art/characters/studio05/split/body_sword_shield.glb attack_2 slash ...

const Rig := preload("res://tools/monsters/rig_common.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var root := (load(args[0]) as PackedScene).instantiate()
	var sk := Rig.donor_skeleton(root)
	var player := Rig.donor_player(root)
	var rh := sk.find_bone("mixamorig_RightHand")
	var lh := sk.find_bone("mixamorig_LeftHand")
	var hips := sk.find_bone("mixamorig_Hips")
	for i in range(1, args.size()):
		var anim := player.get_animation(args[i])
		if anim == null:
			print(args[i], " MISSING")
			continue
		var tracks := Rig.clip_tracks(anim)
		var step := 1.0 / 15.0
		var t := 0.0
		var prev_r := Vector3.ZERO
		var prev_l := Vector3.ZERO
		var line := ""
		var best := [0.0, 0.0]
		var first_hips := Vector3.ZERO
		while t <= anim.length + 0.0001:
			Rig.pose_at(sk, anim, tracks, t)
			var r := _g(sk, rh).origin
			var l := _g(sk, lh).origin
			var hp := _g(sk, hips).origin
			if t == 0.0:
				first_hips = hp
			else:
				var vr := (r - prev_r).length() / step
				var vl := (l - prev_l).length() / step
				line += "%.2f:%d/%d(%.2f) " % [t, int(vr * 100), int(vl * 100), r.y]
				if vr > best[1]:
					best = [t, vr]
			prev_r = r
			prev_l = l
			t += step
		Rig.pose_at(sk, anim, tracks, anim.length)
		print("== ", args[i], " len=%.2f peakR at %.2f (%.2f) hips travel=%s" % [anim.length, best[0], best[1], _g(sk, hips).origin - first_hips])
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
