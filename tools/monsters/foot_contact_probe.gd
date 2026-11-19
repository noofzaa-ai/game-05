extends SceneTree
## Foot heights (rig units) of one clip, every 1/30 s: which foot is planted when, to sync a stomp/bob layer to the steps.
##   godot --headless --path . --script res://tools/monsters/foot_contact_probe.gd -- <glb> <clip>

const Rig := preload("res://tools/monsters/rig_common.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var root := (load(args[0]) as PackedScene).instantiate()
	var sk := Rig.donor_skeleton(root)
	var player := Rig.donor_player(root)
	var anim := player.get_animation(args[1])
	var tracks := Rig.clip_tracks(anim)
	var lf := sk.find_bone("mixamorig_LeftFoot")
	var rf := sk.find_bone("mixamorig_RightFoot")
	var hips := sk.find_bone("mixamorig_Hips")
	var t := 0.0
	var line := ""
	while t <= anim.length + 0.0001:
		Rig.pose_at(sk, anim, tracks, t)
		line += "%.2f L%.3f R%.3f H%.3f | " % [t, _g(sk, lf).origin.y, _g(sk, rf).origin.y, _g(sk, hips).origin.y]
		t += 1.0 / 30.0
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
