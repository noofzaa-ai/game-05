extends SceneTree
## Pilot: the existing mummy mesh (the stand-in, now tools/monsters/standin/mummy_standin.glb, its own 28-bone rig) re-bound to the shared 102-joint
## studio05 rig, plus the player's longbow, string and a nocked arrow (all skinned to the same rig).
##   godot --headless --path . --script res://tools/monsters/build_mummy_archer.gd
## Writes art/monsters/mummy_archer/mummy_archer.glb (shared clip library proportions: big head only). `-- --legs=0.75 --name=x --out=res://dir/`
## builds a short-legs TEST variant (play it with hips_scale 0.75 on the same library; not shipped).
## The player's files are only read. Re-import afterwards (godot --headless --path . --import).
##
## How the mummy mesh is put on the donor rig (no donor joint is removed):
##  1. each mummy bone is mapped to its donor joint (MAP); the mummy's four loose-bandage bones become extra joints under the arms;
##  2. the mummy's limbs are swung (rotation about their own joint) to point where the donor's limbs point in the donor rest pose,
##     so the donor's clip rotations (authored on the donor's bone axes) bend the mummy the way they bend the player;
##  3. everything is scaled so the hips sit at the donor's hip height (clips move the Hips to an absolute height);
##  4. joints are placed at the mummy's joint positions with the donor's rest ORIENTATION; bind = rest; weights are renamed donor joints;
##  5. the donor bow / string (weighted to the donor rig) are moved with the rig the same way (rest-to-rest linear blend skinning).

const Rig := preload("res://tools/monsters/rig_common.gd")
const ALBEDO := Rig.STANDIN_ALBEDO  ## the stand-in source lives in tools/monsters/standin (art/monsters/mummy/mummy.glb is now the rebuilt mummy)
var out_dir := "res://art/monsters/mummy_archer/"
const HEAD_SCALE := 1.3
const TEXTURE_SIZE := 512
const SIMPLIFY := true  ## body and bow take the first LOD of the importer's mesh simplifier (about half the triangles), vertices compacted

const MAP := {
	"root": "Root", "hips": "mixamorig_Hips", "spine": "mixamorig_Spine", "chest": "mixamorig_Spine2", "neck": "mixamorig_Neck", "head": "mixamorig_Head",
	"clavicle.L": "mixamorig_LeftShoulder", "upper_arm.L": "mixamorig_LeftArm", "forearm.L": "mixamorig_LeftForeArm", "hand.L": "mixamorig_LeftHand",
	"clavicle.R": "mixamorig_RightShoulder", "upper_arm.R": "mixamorig_RightArm", "forearm.R": "mixamorig_RightForeArm", "hand.R": "mixamorig_RightHand",
	"thigh.L": "mixamorig_LeftUpLeg", "shin.L": "mixamorig_LeftLeg", "foot.L": "mixamorig_LeftFoot", "toe.L": "mixamorig_LeftToeBase",
	"thigh.R": "mixamorig_RightUpLeg", "shin.R": "mixamorig_RightLeg", "foot.R": "mixamorig_RightFoot", "toe.R": "mixamorig_RightToeBase",
	"attach_weapon.L": "mixamorig_LeftHand", "attach_weapon.R": "mixamorig_RightHand",  # sockets: their weights (none) fold into the hand
}
## extra joints: mummy bone -> [new name, donor parent joint]
const EXTRA := {
	"bandage_upper.L": ["bandage_upper_L", "mixamorig_LeftArm"], "bandage_upper.R": ["bandage_upper_R", "mixamorig_RightArm"],
	"bandage_lower.L": ["bandage_lower_L", "mixamorig_LeftForeArm"], "bandage_lower.R": ["bandage_lower_R", "mixamorig_RightForeArm"],
}
## limbs swung to the donor's direction: mummy bone -> its mummy child that gives the direction
const SWING := {"clavicle.L": "upper_arm.L", "upper_arm.L": "forearm.L", "forearm.L": "hand.L", "thigh.L": "shin.L", "shin.L": "foot.L", "foot.L": "toe.L",
	"clavicle.R": "upper_arm.R", "upper_arm.R": "forearm.R", "forearm.R": "hand.R", "thigh.R": "shin.R", "shin.R": "foot.R", "foot.R": "toe.R"}


func _init() -> void:
	var legs := 1.0
	var file_name := "mummy_archer"
	for arg in OS.get_cmdline_user_args():  ## [--legs=0.75] [--name=mummy_archer_short] [--out=res://dir/]  (a short-legs TEST variant: not shipped)
		if arg.begins_with("--legs="):
			legs = float(arg.substr(7))
		elif arg.begins_with("--name="):
			file_name = arg.substr(7)
		elif arg.begins_with("--out="):
			out_dir = arg.substr(6)
	_build(file_name, legs)
	quit()


func _build(file_name: String, leg_scale: float) -> void:
	var donor := Rig.load_donor()
	var donor_sk := Rig.donor_skeleton(donor)
	var donor_global := _globals(donor_sk)  # bone index -> rest global Transform3D
	var donor_index := {}
	for i in donor_sk.get_bone_count():
		donor_index[donor_sk.get_bone_name(i)] = i

	# ---- the mummy
	var mummy_root := Rig.load_gltf(Rig.STANDIN)
	var m_sk := mummy_root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var m_mesh := mummy_root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var m_global := _globals(m_sk)
	var m_index := {}
	for i in m_sk.get_bone_count():
		m_index[m_sk.get_bone_name(i)] = i

	# 2. swing the mummy's limbs to the donor's directions: A[b] = the affine that moves everything bound to mummy bone b.
	var A := {}
	for i in m_sk.get_bone_count():
		var name := m_sk.get_bone_name(i)
		var a: Transform3D = A[m_sk.get_bone_parent(i)] if m_sk.get_bone_parent(i) >= 0 else Transform3D.IDENTITY
		if SWING.has(name):
			var child: String = SWING[name]
			var here: Vector3 = a * (m_global[i] as Transform3D).origin
			var there: Vector3 = a * (m_global[m_index[child]] as Transform3D).origin
			var want: Vector3 = ((donor_global[donor_index[MAP[child]]] as Transform3D).origin - (donor_global[donor_index[MAP[name]]] as Transform3D).origin).normalized()
			var turn := Transform3D(Basis(Quaternion((there - here).normalized(), want)), Vector3.ZERO)
			a = Transform3D(Basis(), here) * turn * Transform3D(Basis(), -here) * a
		A[i] = a

	# the mummy mesh, skinned to its own rest pose, then swung
	var arrays := m_mesh.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var per := (arrays[Mesh.ARRAY_BONES] as PackedInt32Array).size() / verts.size()
	var m_bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var m_weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var skin := m_mesh.skin
	var infl := []  # per vertex: [[final bone name, weight]...]
	var swung := PackedVector3Array()
	var swung_n := PackedVector3Array()
	swung.resize(verts.size())
	swung_n.resize(verts.size())
	for v in verts.size():
		var p := Vector3.ZERO
		var n := Vector3.ZERO
		var list := {}
		for k in per:
			var w := m_weights[v * per + k]
			if w <= 0.0:
				continue
			var bind_name := String(skin.get_bind_name(m_bones[v * per + k]))
			var bone: int = m_index[bind_name]
			var rest_pos: Vector3 = (m_global[bone] as Transform3D) * (skin.get_bind_pose(m_bones[v * per + k]) * verts[v])
			var af: Transform3D = A[bone]
			p += w * (af * rest_pos)
			n += w * (af.basis * ((m_global[bone] as Transform3D).basis * (skin.get_bind_pose(m_bones[v * per + k]).basis * normals[v])))
			var final_name: String = MAP[bind_name] if MAP.has(bind_name) else EXTRA[bind_name][0]
			list[final_name] = list.get(final_name, 0.0) + w
		swung[v] = p
		swung_n[v] = n.normalized()
		infl.append(list)
	# 3. scale and floor: hips at the donor's hip height, feet on y = 0
	var min_y := 1e9
	for p in swung:
		min_y = minf(min_y, p.y)
	var hips_y: float = (A[m_index["hips"]] as Transform3D * (m_global[m_index["hips"]] as Transform3D).origin).y - min_y
	var donor_hips: float = (donor_global[donor_index["mixamorig_Hips"]] as Transform3D).origin.y
	var f := donor_hips / hips_y
	var shift := Vector3(0, min_y, 0)
	print(file_name, ": scale f=", f, " mummy height after scale=", f * (_max_y(swung) - min_y))

	# 4. joint positions
	var new_pos := {}  # final bone name -> position
	for mname in m_index:
		var i: int = m_index[mname]
		var pos: Vector3 = f * ((A[i] as Transform3D) * (m_global[i] as Transform3D).origin - shift)
		if MAP.has(mname) and not mname.begins_with("attach"):
			new_pos[MAP[mname]] = pos
		elif EXTRA.has(mname):
			new_pos[EXTRA[mname][0]] = pos
	new_pos["Root"] = Vector3.ZERO
	new_pos["mixamorig_Spine1"] = ((new_pos["mixamorig_Spine"] as Vector3) + (new_pos["mixamorig_Spine2"] as Vector3)) * 0.5
	# the donor joints the mummy has no counterpart for (fingers, hair, head tips, toe ends): the donor's offset from its parent, scaled
	var ratio := {}
	for i in donor_sk.get_bone_count():
		var name := donor_sk.get_bone_name(i)
		var parent := donor_sk.get_bone_parent(i)
		if new_pos.has(name):
			var base: float = ((donor_global[i] as Transform3D).origin - (donor_global[parent] as Transform3D).origin).length() if parent >= 0 else 1.0
			ratio[name] = clampf(((new_pos[name] as Vector3) - (new_pos[donor_sk.get_bone_name(parent)] as Vector3)).length() / maxf(base, 0.0001), 0.5, 3.0) if parent >= 0 and base > 0.001 else 1.0
	for i in donor_sk.get_bone_count():
		var name := donor_sk.get_bone_name(i)
		if new_pos.has(name):
			continue
		var parent := donor_sk.get_bone_parent(i)
		var pname := donor_sk.get_bone_name(parent)
		var s: float = float(ratio.get(pname, 1.0))
		new_pos[name] = (new_pos[pname] as Vector3) + ((donor_global[i] as Transform3D).origin - (donor_global[parent] as Transform3D).origin) * s
		ratio[name] = s

	# proportion demo: a big head and (variant) shorter legs, applied to joints and vertices alike
	var head_pos: Vector3 = new_pos["mixamorig_Head"]
	var head_subtree := _subtree(donor_sk, "mixamorig_Head")
	for name in head_subtree:
		if name != "mixamorig_Head":
			new_pos[name] = head_pos + ((new_pos[name] as Vector3) - head_pos) * HEAD_SCALE
	var final_pos := PackedVector3Array()
	var final_n := PackedVector3Array()
	final_pos.resize(verts.size())
	final_n.resize(verts.size())
	for v in verts.size():
		var p: Vector3 = f * (swung[v] - shift)
		var wh := float((infl[v] as Dictionary).get("mixamorig_Head", 0.0))
		p += wh * (HEAD_SCALE - 1.0) * (p - head_pos)
		final_pos[v] = p
		final_n[v] = swung_n[v]
	if leg_scale != 1.0:
		for name in new_pos:
			new_pos[name] = _leg_warp(new_pos[name], donor_hips, leg_scale)
		for v in final_pos.size():
			final_pos[v] = _leg_warp(final_pos[v], donor_hips, leg_scale)

	# the new rest globals: donor orientation, new positions; extras take their parent's orientation
	var new_global := {}
	for i in donor_sk.get_bone_count():
		new_global[donor_sk.get_bone_name(i)] = Transform3D((donor_global[i] as Transform3D).basis, new_pos[donor_sk.get_bone_name(i)])
	# ---- the skeleton
	var skeleton := Rig.copy_skeleton(donor_sk)
	var names: Array = []
	for i in donor_sk.get_bone_count():
		names.append(donor_sk.get_bone_name(i))
	for mname in EXTRA:
		var info: Array = EXTRA[mname]
		var index := skeleton.get_bone_count()
		skeleton.add_bone(info[0])
		skeleton.set_bone_parent(index, skeleton.find_bone(info[1]))
		names.append(info[0])
		new_global[info[0]] = Transform3D((new_global[info[1]] as Transform3D).basis, new_pos[info[0]])
	for i in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(i)
		var g: Transform3D = new_global[names[i]]
		skeleton.set_bone_rest(i, (new_global[names[parent]] as Transform3D).affine_inverse() * g if parent >= 0 else g)
	skeleton.reset_bone_poses()
	var new_skin := Skin.new()
	var name_to_index := {}
	for i in skeleton.get_bone_count():
		name_to_index[names[i]] = i
		new_skin.add_named_bind(names[i], (new_global[names[i]] as Transform3D).affine_inverse())

	# ---- the meshes
	var bone_rests := []
	for i in skeleton.get_bone_count():
		bone_rests.append(new_global[names[i]])
	var mummy_surface := _surface(final_pos, final_n, arrays[Mesh.ARRAY_TEX_UV], infl, name_to_index, arrays[Mesh.ARRAY_INDEX])
	if SIMPLIFY:
		mummy_surface = _simplify(mummy_surface, bone_rests)
	var mummy_mesh := ArrayMesh.new()
	mummy_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mummy_surface)
	var texture_image := Image.load_from_file(ALBEDO)
	texture_image.resize(TEXTURE_SIZE, TEXTURE_SIZE, Image.INTERPOLATE_LANCZOS)
	var mummy_material := StandardMaterial3D.new()
	mummy_material.resource_name = "mummy_bandage"
	mummy_material.albedo_texture = ImageTexture.create_from_image(texture_image)
	mummy_material.roughness = 0.9
	mummy_material.metallic = 0.0
	mummy_mesh.surface_set_material(0, mummy_material)

	var root := Node3D.new()
	root.name = "Monster_MummyArcher"
	var rig := Node3D.new()
	rig.name = "rig"
	root.add_child(rig)
	rig.add_child(skeleton)
	_add_mesh(skeleton, "Monster_MummyArcher_Body", mummy_mesh, new_skin)

	# the player's longbow and string (weighted to the donor rig) moved to the new rest pose
	# read straight from the file: its textures are embedded (the importer's extracted copies are not kept in the repo)
	var armor_state := GLTFState.new()
	var armor_doc := GLTFDocument.new()
	armor_doc.append_from_file(ProjectSettings.globalize_path(Rig.DONOR_ARMOR), armor_state)
	var armor := armor_doc.generate_scene(armor_state)
	var armor_sk := Rig.donor_skeleton(armor)
	var armor_global := _globals(armor_sk)
	for piece in [["L 01 | Bow", "Monster_MummyArcher_Bow", Color(0.32, 0.2, 0.1)], ["L 17 | Bow string", "Monster_MummyArcher_BowString", Color(0.85, 0.8, 0.65)]]:
		var mi := armor.find_child(piece[0], true, false) as MeshInstance3D
		var a := mi.mesh.surface_get_arrays(0)
		var av: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var an: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var ab: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var aw: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		var aper := ab.size() / av.size()
		var out_v := PackedVector3Array()
		var out_n := PackedVector3Array()
		var out_infl := []
		for v in av.size():
			var p := Vector3.ZERO
			var n := Vector3.ZERO
			var list := {}
			for k in aper:
				var w := aw[v * aper + k]
				if w <= 0.0:
					continue
				var bname := String(mi.skin.get_bind_name(ab[v * aper + k]))
				if bname == "":  # a skin read straight from the file binds by bone index
					bname = armor_sk.get_bone_name(mi.skin.get_bind_bone(ab[v * aper + k]))
				var gd: Transform3D = armor_global[armor_sk.find_bone(bname)]
				var rest_pos: Vector3 = gd * (mi.skin.get_bind_pose(ab[v * aper + k]) * av[v])
				var move: Transform3D = (new_global[bname] as Transform3D) * (donor_global[donor_index[bname]] as Transform3D).affine_inverse()
				p += w * (move * rest_pos)
				n += w * (move.basis * (gd.basis * (mi.skin.get_bind_pose(ab[v * aper + k]).basis * an[v])))
				list[bname] = list.get(bname, 0.0) + w
			if leg_scale != 1.0:
				p = _leg_warp(p, donor_hips, leg_scale)
			out_v.append(p)
			out_n.append(n.normalized())
			out_infl.append(list)
		var piece_mesh := ArrayMesh.new()
		var piece_surface := _surface(out_v, out_n, a[Mesh.ARRAY_TEX_UV], out_infl, name_to_index, a[Mesh.ARRAY_INDEX])
		if SIMPLIFY and piece[1] == "Monster_MummyArcher_Bow":
			piece_surface = _simplify(piece_surface, bone_rests)
		piece_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, piece_surface)
		var flat := StandardMaterial3D.new()
		flat.albedo_color = piece[2]
		flat.roughness = 0.85
		piece_mesh.surface_set_material(0, flat)
		_add_mesh(skeleton, piece[1], piece_mesh, new_skin)
	armor.free()

	# the nocked arrow ("arrow", shown only while the draw winds up): placed on the full-draw pose, weighted to the right hand
	var draw := Rig.donor_player(donor).get_animation("lb_draw_arrow")
	Rig.pose_at(skeleton, draw, Rig.clip_tracks(draw), 1.017)
	var rh := skeleton.find_bone("mixamorig_RightHand")
	var lh := skeleton.find_bone("mixamorig_LeftHand")
	var rh_pose := skeleton.get_bone_global_pose(rh)
	var tail: Vector3 = rh_pose.origin
	var dir: Vector3 = (skeleton.get_bone_global_pose(lh).origin - tail).normalized()
	var arrow_length := 0.3
	var arrow_mesh := _arrow(tail, dir, arrow_length, rh_pose, new_global["mixamorig_RightHand"], name_to_index["mixamorig_RightHand"])
	_add_mesh(skeleton, "arrow", arrow_mesh, new_skin)
	print(file_name, ": nock arrow tail=", tail, " tip=", tail + dir * arrow_length)
	skeleton.reset_bone_poses()

	for node in [rig, skeleton]:
		node.owner = root
	for child in skeleton.get_children():
		child.owner = root
	var tris := 0
	for child in skeleton.get_children():
		var m := (child as MeshInstance3D).mesh
		tris += (m.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	DirAccess.make_dir_recursive_absolute(out_dir)
	var state := GLTFState.new()
	var document := GLTFDocument.new()
	document.image_format = "JPEG"
	document.lossy_quality = 0.8
	var err := document.append_from_scene(root, state)
	if err == OK:
		err = document.write_to_filesystem(state, out_dir + file_name + ".glb")
	if err == OK:
		Rig.minify_glb(out_dir + file_name + ".glb")
	print(file_name, ": export err=", err, " tris=", tris, " joints=", skeleton.get_bone_count(), " body bounds y=", _max_y(final_pos), " bytes=", FileAccess.get_file_as_bytes(out_dir + file_name + ".glb").size())
	root.free()
	donor.free()
	mummy_root.free()


static func _leg_warp(p: Vector3, hip_height: float, k: float) -> Vector3:
	return Vector3(p.x, p.y * k if p.y < hip_height else p.y - (1.0 - k) * hip_height, p.z * (1.0 if p.y >= hip_height else 1.0))


static func _max_y(points: PackedVector3Array) -> float:
	var m := -1e9
	for p in points:
		m = maxf(m, p.y)
	return m


static func _globals(sk: Skeleton3D) -> Dictionary:
	var out := {}
	for i in sk.get_bone_count():
		var parent := sk.get_bone_parent(i)
		out[i] = ((out[parent] as Transform3D) if parent >= 0 else Transform3D.IDENTITY) * sk.get_bone_rest(i)
	return out


static func _subtree(sk: Skeleton3D, root_name: String) -> Array:
	var out := [root_name]
	var root := sk.find_bone(root_name)
	for i in sk.get_bone_count():
		var p := sk.get_bone_parent(i)
		while p >= 0:
			if p == root:
				out.append(sk.get_bone_name(i))
				break
			p = sk.get_bone_parent(p)
	return out


## Surface arrays with the final joint indices (4 strongest influences, normalised).
static func _surface(pos: PackedVector3Array, nor: PackedVector3Array, uv: Variant, infl: Array, name_to_index: Dictionary, index: PackedInt32Array) -> Array:
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for list in infl:
		var pairs := []
		for name in list:
			pairs.append([float(list[name]), int(name_to_index[name])])
		pairs.sort_custom(func(a, b): return a[0] > b[0])
		var total := 0.0
		for k in mini(4, pairs.size()):
			total += pairs[k][0]
		for k in 4:
			if k < pairs.size():
				bones.append(pairs[k][1])
				weights.append(pairs[k][0] / total)
			else:
				bones.append(0)
				weights.append(0.0)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nor
	if uv != null:
		arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = index
	return arrays


## The importer's quadric simplifier (the one that makes mesh LODs, aware of normals, UV seams and skinning): the first LOD's
## triangles kept, the vertices nothing uses dropped. Keeps the skin weights of the surviving vertices.
static func _simplify(arrays: Array, bone_rests: Array) -> Array:
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, null, "s")
	importer.generate_lods(25.0, 25.0, bone_rests)
	if importer.get_surface_lod_count(0) == 0:
		return arrays
	var kept: PackedInt32Array = importer.get_surface_lod_indices(0, 0)
	var remap := {}
	var order := []
	for index in kept:
		if not remap.has(index):
			remap[index] = order.size()
			order.append(index)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV]:
		if arrays[slot] == null:
			continue
		var source = arrays[slot]
		var packed = source.duplicate()
		packed.resize(order.size())
		for i in order.size():
			packed[i] = source[order[i]]
		out[slot] = packed
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for index in order:
		for k in 4:
			bones.append((arrays[Mesh.ARRAY_BONES] as PackedInt32Array)[index * 4 + k])
			weights.append((arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array)[index * 4 + k])
	out[Mesh.ARRAY_BONES] = bones
	out[Mesh.ARRAY_WEIGHTS] = weights
	var indices := PackedInt32Array()
	for index in kept:
		indices.append(remap[index])
	out[Mesh.ARRAY_INDEX] = indices
	print("  simplified ", (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3, " -> ", indices.size() / 3, " triangles, vertices ", (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), " -> ", order.size())
	return out


static func _add_mesh(skeleton: Skeleton3D, name: String, mesh: ArrayMesh, skin: Skin) -> void:
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	instance.skin = skin
	skeleton.add_child(instance)
	instance.skeleton = NodePath("..")


## A thin six-sided arrow (shaft, head and fletching block) from `tail` along `dir`, given in the posed (full draw) model space and
## converted to the right hand's rest space, so it is weighted 100% to that hand and follows it through the shot.
static func _arrow(tail: Vector3, dir: Vector3, length: float, hand_pose: Transform3D, hand_rest: Transform3D, hand_index: int) -> ArrayMesh:
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var side := dir.cross(up).normalized()
	var top := side.cross(dir).normalized()
	var to_rest := hand_rest * hand_pose.affine_inverse()
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var radius := 0.004
	var rings := [[0.0, radius], [length - 0.04, radius], [length - 0.04, 0.011], [length, 0.0]]
	for ring in rings:
		for s in 6:
			var angle := TAU * s / 6.0
			verts.append(to_rest * (tail + dir * float(ring[0]) + (side * cos(angle) + top * sin(angle)) * float(ring[1])))
	for r in 3:
		for s in 6:
			var a := r * 6 + s
			var b := r * 6 + (s + 1) % 6
			idx.append_array(PackedInt32Array([a, b, a + 6, b, b + 6, a + 6]))
	var tail_center := verts.size()
	verts.append(to_rest * tail)
	for s in 6:
		idx.append_array(PackedInt32Array([tail_center, (s + 1) % 6, s]))
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for v in verts:
		normals.append(Vector3.UP)
		uvs.append(Vector2.ZERO)
		bones.append_array(PackedInt32Array([hand_index, 0, 0, 0]))
		weights.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.62, 0.5, 0.3)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	return mesh
