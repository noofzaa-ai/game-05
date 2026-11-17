extends SceneTree
## Global rest positions of a skeleton (model space): godot --headless --path . --script res://tools/monsters/dump_rest.gd -- res://x.glb [filter]
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var root := (load(args[0]) as PackedScene).instantiate()
	var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	var g := {}
	for i in sk.get_bone_count():
		var p := sk.get_bone_parent(i)
		g[i] = (g[p] if p >= 0 else Transform3D.IDENTITY) * sk.get_bone_rest(i)
		var n := sk.get_bone_name(i)
		if args.size() < 2 or args[1] in n or "Hips" in n:
			var dir: Vector3 = (g[i].basis * Vector3.UP).normalized()
			print(i, " ", n, " p=", p, " pos=", (g[i].origin * 1000).round() / 1000, " Y->", (dir * 100).round() / 100, " scale=", g[i].basis.get_scale())
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var t := 0
		for s in mi.mesh.get_surface_count():
			t += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		print("MESH ", mi.name, " tris=", t, " aabb=", mi.get_aabb(), " xform=", mi.transform, " mat=", mi.get_active_material(0), " skin_binds=", mi.skin.get_bind_count() if mi.skin else -1)
	print("ROOT xform children: ", root.get_children().map(func(c): return str(c.name) + str(c.transform.basis.get_scale())))
	quit()
