extends SceneTree
## Cuts a monster model's triangles (Boss 2026-11-17: at most 5,000 per monster) WITHOUT touching its rig: the glTF is read as data,
## only the mesh surfaces are replaced, nodes / skeleton / skin joints / materials / names stay exactly as they were.
## The importer's quadric simplifier (the one that makes mesh LODs, aware of normals, UV seams and skin weights) is run per
## connected piece of the mesh, so pieces never crack against each other; each piece takes LOD `base` (the fused body, over
## 2,000 triangles), LOD `acc` (pieces of 100-1,999 triangles: armour, weapons) or stays as it is (smaller bits: eyes, teeth, studs).
## LOD 0 = half the triangles, 1 = a quarter, -1 = untouched.
##   godot --headless --path . --script res://tools/monsters/simplify_monster.gd -- goblin_chief --base=0 --acc=1 [--small=100] [--in=res://original.glb] [--out=res://dir/x.glb]
## then: python tools/monsters/prune_glb.py x.glb  (drops the replaced mesh data Godot keeps in the file)
## Embedded textures are re-written as JPEG (quality 0.9) and shrunk to 1024 px if larger.

const Rig := preload("res://tools/monsters/rig_common.gd")


func _init() -> void:
	var monster := ""
	var base_lod := 0
	var acc_lod := 0
	var small := 100
	var big := 2000
	var out_path := ""
	var in_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--base="):
			base_lod = int(arg.substr(7))
		elif arg.begins_with("--acc="):
			acc_lod = int(arg.substr(6))
		elif arg.begins_with("--small="):
			small = int(arg.substr(8))
		elif arg.begins_with("--in="):
			in_path = arg.substr(5)
		elif arg.begins_with("--out="):
			out_path = arg.substr(6)
		else:
			monster = arg
	var source := "res://art/monsters/%s/%s.glb" % [monster, monster]
	if in_path != "":
		source = in_path
	if out_path == "":
		out_path = source
	var state := GLTFState.new()
	var document := GLTFDocument.new()
	if document.append_from_file(ProjectSettings.globalize_path(source), state) != OK:
		printerr("cannot read ", source)
		quit(1)
		return
	var rests := []
	var scene := (load(source) as PackedScene).instantiate()
	var skeletons := scene.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		var skeleton := skeletons[0] as Skeleton3D
		for i in skeleton.get_bone_count():
			rests.append(skeleton.get_bone_global_rest(i))
	scene.free()
	var before := 0
	var after := 0
	for gltf_mesh in state.get_meshes():
		var original: ImporterMesh = gltf_mesh.mesh
		var rebuilt := ImporterMesh.new()
		for s in original.get_surface_count():
			var arrays := original.get_surface_arrays(s)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			before += indices.size() / 3
			var kept := _simplify(arrays, rests, base_lod, acc_lod, small, big)
			after += kept.size() / 3
			rebuilt.add_surface(Mesh.PRIMITIVE_TRIANGLES, _compact(arrays, kept), [], {}, original.get_surface_material(s), original.get_surface_name(s))
			print("  ", gltf_mesh.resource_name, ": ", indices.size() / 3, " -> ", kept.size() / 3)
		gltf_mesh.mesh = rebuilt
	print(monster, ": ", before, " -> ", after, " triangles")
	for texture in state.get_images():
		var image: Image = (texture as Texture2D).get_image()
		if maxi(image.get_width(), image.get_height()) > 1024:
			image.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
	document.image_format = "JPEG"
	document.lossy_quality = 0.9
	var err := document.write_to_filesystem(state, out_path)
	if err == OK:
		Rig.minify_glb(out_path)
	print("write ", out_path, " err=", err, " bytes=", FileAccess.get_file_as_bytes(out_path).size())
	quit()


## The triangle indices (into the original vertices) kept after simplifying each connected piece on its own.
static func _simplify(arrays: Array, rests: Array, base_lod: int, acc_lod: int, small: int, big: int) -> PackedInt32Array:
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var parent := {}
	var key := func(p: Vector3) -> Vector3i: return Vector3i(roundi(p.x * 10000.0), roundi(p.y * 10000.0), roundi(p.z * 10000.0))
	var find := func(k: Vector3i) -> Vector3i:
		while parent[k] != k:
			parent[k] = parent[parent[k]]
			k = parent[k]
		return k
	for p in positions:
		var k: Vector3i = key.call(p)
		if not parent.has(k):
			parent[k] = k
	for t in indices.size() / 3:
		var a: Vector3i = find.call(key.call(positions[indices[t * 3]]))
		for c in [1, 2]:
			var b: Vector3i = find.call(key.call(positions[indices[t * 3 + c]]))
			if b != a:
				parent[b] = a
	var pieces := {}  # root -> triangle indices
	for t in indices.size() / 3:
		var root: Vector3i = find.call(key.call(positions[indices[t * 3]]))
		var list: PackedInt32Array = pieces.get(root, PackedInt32Array())
		list.append_array(PackedInt32Array([indices[t * 3], indices[t * 3 + 1], indices[t * 3 + 2]]))
		pieces[root] = list
	var order := pieces.keys()
	var importer := ImporterMesh.new()
	for root in order:
		var part := arrays.duplicate()
		part[Mesh.ARRAY_INDEX] = pieces[root]
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, part, [], {}, null, "piece")
	importer.generate_lods(25.0, 25.0, rests)
	var kept := PackedInt32Array()
	for s in order.size():
		var piece: PackedInt32Array = pieces[order[s]]
		var triangles := piece.size() / 3
		var want := -1
		if triangles >= big:
			want = base_lod
		elif triangles >= small:
			want = acc_lod
		var lods := importer.get_surface_lod_count(s)
		if want < 0 or lods == 0:
			kept.append_array(piece)
		else:
			kept.append_array(importer.get_surface_lod_indices(s, mini(want, lods - 1)))
	return kept


## Surface arrays holding only the vertices `kept` uses (every per-vertex array is carried along).
static func _compact(arrays: Array, kept: PackedInt32Array) -> Array:
	var count := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var remap := {}
	var order := []
	for index in kept:
		if not remap.has(index):
			remap[index] = order.size()
			order.append(index)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for slot in Mesh.ARRAY_MAX:
		if slot == Mesh.ARRAY_INDEX or arrays[slot] == null:
			continue
		var source = arrays[slot]
		if source.size() == 0 or source.size() % count != 0:
			continue
		var stride: int = source.size() / count
		var packed = source.duplicate()
		packed.resize(order.size() * stride)
		for i in order.size():
			for k in stride:
				packed[i * stride + k] = source[order[i] * stride + k]
		out[slot] = packed
	var new_indices := PackedInt32Array()
	for index in kept:
		new_indices.append(remap[index])
	out[Mesh.ARRAY_INDEX] = new_indices
	return out
