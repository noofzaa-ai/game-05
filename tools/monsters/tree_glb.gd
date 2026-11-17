extends SceneTree
func _p(n: Node, d: int) -> void:
	var extra := ""
	if n is MeshInstance3D:
		var m := n as MeshInstance3D
		extra = " MESH surf=" + str(m.mesh.get_surface_count()) + " aabb=" + str(m.get_aabb()) + " skin=" + str(m.skin != null)
	elif n is BoneAttachment3D:
		extra = " BONEATT " + (n as BoneAttachment3D).bone_name
	if d < 6 and not (n is Skeleton3D and false):
		print("  ".repeat(d), n.name, " [", n.get_class(), "]", extra)
	for c in n.get_children():
		_p(c, d + 1)
func _init() -> void:
	var root := (load(OS.get_cmdline_user_args()[0]) as PackedScene).instantiate()
	_p(root, 0)
	quit()
