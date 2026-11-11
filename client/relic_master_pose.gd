extends RefCounted
## Neutral standing correction for this donor only. Preserve rest, skin, feet and all other bones.
static func apply(visual:Node3D,skeleton:Skeleton3D)->bool:
	if skeleton==null:return false
	if skeleton.has_meta("relic_neutral_head"):return true
	var head=skeleton.find_bone("Head");var tip=skeleton.find_bone("Head_end")
	if head<0 or tip<0:return false
	var pose=skeleton.get_bone_global_pose(head)
	var up=(skeleton.get_bone_global_pose(tip).origin-pose.origin).normalized()
	var target=(skeleton.global_basis.inverse()*visual.global_basis.y).normalized()
	if up.is_zero_approx() or target.is_zero_approx():return false
	var rotation=pose.basis.orthonormalized().get_rotation_quaternion()
	var local_delta=rotation.inverse()*Quaternion(up,target)*rotation
	skeleton.set_bone_pose_rotation(head,(skeleton.get_bone_pose_rotation(head)*local_delta).normalized())
	skeleton.set_meta("relic_neutral_head",true)
	return true
