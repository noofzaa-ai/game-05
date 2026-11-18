extends SceneTree
## Prints horizontal slices of one mesh of a glb (read straight from the file): per height band, the x clusters (with their z range),
## to find shoulders, elbows, hips, knees, ankles of an unrigged model. Also each mesh's centroid and bounds.
##   godot --headless --path . --script res://tools/monsters/slice_probe.gd -- <abs glb> <mesh name> [band]
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var state := GLTFState.new()
	var doc := GLTFDocument.new()
	doc.append_from_file(args[0], state)
	var root := doc.generate_scene(state)
	var band := float(args[2]) if args.size() > 2 else 0.02
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var xf := mi.global_transform if mi.is_inside_tree() else _to_root(mi, root)
		var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var c := Vector3.ZERO
		var box := AABB(xf * verts[0], Vector3.ZERO)
		for v in verts:
			c += xf * v
			box = box.expand(xf * v)
		print("MESH ", mi.name, " centroid=", (c / verts.size()).snappedf(0.001), " min=", box.position.snappedf(0.001), " max=", box.end.snappedf(0.001))
		if str(mi.name) != args[1]:
			continue
		var by_band := {}
		for v in verts:
			var p := xf * v
			var k := int(floor(p.y / band))
			if not by_band.has(k):
				by_band[k] = []
			by_band[k].append(p)
		var keys := by_band.keys()
		keys.sort()
		for k in keys:
			var pts: Array = by_band[k]
			pts.sort_custom(func(a, b): return a.x < b.x)
			var clusters := []
			var cur := [pts[0]]
			for i in range(1, pts.size()):
				if pts[i].x - pts[i - 1].x > 0.015:
					clusters.append(cur)
					cur = []
				cur.append(pts[i])
			clusters.append(cur)
			var line := "y=%.2f:" % (k * band)
			for cl in clusters:
				var zmin := 1e9
				var zmax := -1e9
				for p in cl:
					zmin = minf(zmin, p.z)
					zmax = maxf(zmax, p.z)
				line += "  x[%.3f,%.3f] z[%.3f,%.3f] n%d" % [cl[0].x, cl[-1].x, zmin, zmax, cl.size()]
			print(line)
	root.free()
	quit()


static func _to_root(n: Node3D, root: Node) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p != null and p != root:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t
