extends SceneTree
## The mummy family on the shared 102-joint studio05 rig (the mummy archer's pipeline, tools/monsters/build_mummy_archer.gd):
## the stand-in mummy mesh (tools/monsters/standin) re-bound to the donor rig, given per-monster proportions, a tinted albedo
## and its own gear, every piece skinned to the same rig (no donor joint removed or merged; the four loose-bandage joints added).
##   godot --headless --path . --script res://tools/monsters/build_mummy_family.gd -- [mummy mummy_knight mummy_mage mummy_boss] [--out=res://dir/]
## Writes art/monsters/<id>/<id>.glb + <id>.json. Then re-import (godot --headless --path . --import).
##
## Gear is built here, procedurally, in the POSE of the player's own weapon of the same stance (the weapon whose clips the
## monster plays): the player's sword / shield / staff / greatsword mesh is read only to find its grip point, its blade direction
## and its flat side in the donor rest pose; the new piece (khopesh, Egyptian shield, scarab staff) is built along that frame and
## weighted 100% to the joint that holds the player's piece, so it sits in the fist through every copied clip.
## Head gear (nemes, death mask, helmet, hood) is fitted to the bounds of the head and weighted 100% to mixamorig_Head;
## the pharaoh's collar is weighted 100% to mixamorig_Spine2.

const Rig := preload("res://tools/monsters/rig_common.gd")
const TEXTURE_SIZE := 512
const NO_EXTRA_POS := Vector3(0, -0.02, -0.03)  ## a loose-bandage joint a source rig lacks is put just under its parent joint
const ARMOR_SWORD_SHIELD := "res://art/characters/studio05/v1111/outfits/armor_sword_shield.glb"
const ARMOR_GREATSWORD := "res://art/characters/studio05/v1111/outfits/armor_greatsword.glb"
const ARMOR_MAGIC := "res://art/characters/studio05/v1111/outfits/armor_magic.glb"

const GOLD := Color(0.78, 0.55, 0.16)
const BRONZE := Color(0.55, 0.37, 0.19)
const RUST := Color(0.36, 0.32, 0.28)
const TEAL := Color(0.05, 0.28, 0.29)
const DARK_TEAL := Color(0.04, 0.17, 0.19)
const WOOD := Color(0.3, 0.21, 0.13)
const GLOW := Color(0.2, 0.85, 0.72)
const SHIELD_TOP := -1.0  ## which way the round top of the shield points along the player's shield width axis (checked in the windowed shots)

## Per monster: model height in game (data model_height), its stance library, body proportions and gear.
## width: shoulders/chest widened about the centre line (arms moved out, not thickened); head: head scale (archer 1.3);
## tint: multiplies the stand-in albedo; gear: pieces built below.
const VARIANTS := {
	"mummy": {"node": "Monster_Mummy", "height": 1.8, "stance": "mummy", "width": 1.0, "head": 1.3,
		"tint": Color(1.0, 1.0, 1.0), "gear": ["blade"],
		"clips": {"attack_1": "the two-handed rake", "attack_2": "the grave grasp (lunge and clutch)"}},
	"mummy_knight": {"node": "Monster_MummyKnight", "height": 2.0, "stance": "sword_shield", "width": 1.16, "head": 1.22,
		"tint": Color(0.84, 0.8, 0.74), "gear": ["shield", "khopesh", "helmet"],
		"clips": {"attack_1": "the side cut", "attack_2": "the shield bash (keyed)"}},
	"mummy_mage": {"node": "Monster_MummyMage", "height": 1.9, "stance": "magic", "width": 0.94, "head": 1.3,
		"tint": Color(0.86, 0.88, 0.9), "gear": ["staff", "hood"],
		"clips": {"cast": "the bolt", "cast_aoe": "the ground mark", "blink": "the escape"}},
	## The Boss's own model (boss-mummy-higthwizard.fbx), squeezed + landmark-rigged by tools/monsters/squeeze_fbx.py and rig_boss_fbx.py
	## (build/mummy_high_wizard/rigged.glb, kept out of git: re-run those two to rebuild), ONE body mesh incl. crown, collar, staff and orb,
	## its own 1024 albedo (no tint, no gear built here). Own clip library (monster_clips_wizard_boss), see build_clip_library.gd.
	"mummy_high_wizard": {"node": "Monster_MummyHighWizard", "height": 3.4, "stance": "wizard_boss", "width": 1.0, "head": 1.0,
		"tint": Color(1.0, 1.0, 1.0), "gear": [], "source": "res://build/mummy_high_wizard/rigged.glb", "albedo": "res://build/mummy_high_wizard/albedo.png",
		"texture_size": 1024, "simplify": false,
		"clips": {"cast": "the bolt", "cast_aoe": "the big cast", "summon": "calls the mummies", "starfall": "the starfall", "sandstorm": "the sandstorm"}},
	"mummy_boss": {"node": "Monster_MummyBoss", "height": 2.6, "stance": "greatsword", "width": 1.24, "head": 1.18,
		"tint": Color(0.5, 0.62, 0.6), "gear": ["boss_khopesh", "nemes", "mask", "collar"],
		"clips": {"attack_1": "the two-cut combo", "attack_2": "the leaping nova slam (in place)"}},
	## ---- The orc family (Boss 2026-11-21: ONE supplied body, rigged once, every type made from it by tint, proportions, its own
	## tool-built weapon/headgear and its OWN animation set). Source: the Boss's orc FBX squeezed by tools/monsters/squeeze_fbx.py
	## (3,892 triangles) and landmark-rigged by tools/monsters/rig_orc_fbx.py into build/orc_base (kept out of git: re-run those two).
	"orc_grunt": {"node": "Monster_OrcGrunt", "height": 1.7, "stance": "orc_grunt", "width": 1.12, "head": 1.0,
		"tint": Color(1.0, 1.0, 1.0), "gear": ["cleaver"], "source": ORC_SOURCE, "albedo": ORC_ALBEDO, "texture_size": 1024, "simplify": false,
		"sheet": "orc_family", "clips": {"attack_1": "the cleaver chop", "attack_2": "the lunging cleave"}},
	"orc_archer": {"node": "Monster_OrcArcher", "height": 1.6, "stance": "orc_bow", "width": 0.94, "head": 1.0,
		"tint": Color(0.86, 0.94, 0.8), "gear": ["bow", "headband"], "source": ORC_SOURCE, "albedo": ORC_ALBEDO, "texture_size": 1024, "simplify": false,
		"sheet": "orc_family", "clips": {"shoot": "one arrow", "volley": "three arrows (slow draw)"}},
	"orc_mage": {"node": "Monster_OrcMage", "height": 1.6, "stance": "orc_magic", "width": 0.94, "head": 1.06,
		"tint": Color(0.84, 0.86, 1.0), "gear": ["totem_staff", "skull_mask"], "source": ORC_SOURCE, "albedo": ORC_ALBEDO, "texture_size": 1024, "simplify": false,
		"sheet": "orc_family", "clips": {"cast": "the bolt", "cast_aoe": "the ground slam", "blink": "the escape"}},
	## The Orc Warlock, the Orc Camp's BOSS (Boss 2026-11-21: its own supplied FBX, a hooded purple-robed horned orc; weapon = sword
	## and shield). Squeezed by squeeze_fbx.py and landmark-rigged by tools/monsters/rig_warlock_fbx.py into build/orc_warlock (kept out
	## of git). No tint (its own albedo). The sword and shield are PLAIN MOCKUPS (Boss: no real weapon models yet) so the copied
	## sword-and-shield clips can be judged; the real weapons replace _gear_mock_sword / _gear_mock_shield later.
	"orc_warlock": {"node": "Monster_OrcWarlock", "height": 3.2, "stance": "orc_warlock", "width": 1.0, "head": 1.0,
		"tint": Color(1.0, 1.0, 1.0), "gear": ["mock_shield", "mock_sword"], "source": "res://build/orc_warlock/rigged.glb",
		"albedo": "res://build/orc_warlock/albedo.png", "texture_size": 1024, "simplify": false, "sheet": "orc_warlock",
		"clips": {"attack_1": "the sweeping cleave", "skyfall": "the leaping skyfall smash", "cataclysm": "the airborne ground breaker", "block": "the bulwark (shield slam, then the held guard)"}},
}
const ORC_SOURCE := "res://build/orc_base/rigged.glb"
const ORC_ALBEDO := "res://build/orc_base/albedo.png"
const ARMOR_LONGBOW := "res://art/characters/studio05/v1111/outfits/armor_longbow.glb"
const Archer := preload("res://tools/monsters/build_mummy_archer.gd")
const IRON := Color(0.42, 0.43, 0.45)
const LEATHER := Color(0.33, 0.2, 0.11)
const BONE := Color(0.86, 0.82, 0.7)
const RED_CLOTH := Color(0.55, 0.12, 0.08)
const ORC_GLOW := Color(0.55, 0.95, 0.25)

const MAP := {
	"root": "Root", "hips": "mixamorig_Hips", "spine": "mixamorig_Spine", "chest": "mixamorig_Spine2", "neck": "mixamorig_Neck", "head": "mixamorig_Head",
	"clavicle.L": "mixamorig_LeftShoulder", "upper_arm.L": "mixamorig_LeftArm", "forearm.L": "mixamorig_LeftForeArm", "hand.L": "mixamorig_LeftHand",
	"clavicle.R": "mixamorig_RightShoulder", "upper_arm.R": "mixamorig_RightArm", "forearm.R": "mixamorig_RightForeArm", "hand.R": "mixamorig_RightHand",
	"thigh.L": "mixamorig_LeftUpLeg", "shin.L": "mixamorig_LeftLeg", "foot.L": "mixamorig_LeftFoot", "toe.L": "mixamorig_LeftToeBase",
	"thigh.R": "mixamorig_RightUpLeg", "shin.R": "mixamorig_RightLeg", "foot.R": "mixamorig_RightFoot", "toe.R": "mixamorig_RightToeBase",
	"attach_weapon.L": "mixamorig_LeftHand", "attach_weapon.R": "mixamorig_RightHand",
}
const EXTRA := {
	"bandage_upper.L": ["bandage_upper_L", "mixamorig_LeftArm"], "bandage_upper.R": ["bandage_upper_R", "mixamorig_RightArm"],
	"bandage_lower.L": ["bandage_lower_L", "mixamorig_LeftForeArm"], "bandage_lower.R": ["bandage_lower_R", "mixamorig_RightForeArm"],
}
const SWING := {"clavicle.L": "upper_arm.L", "upper_arm.L": "forearm.L", "forearm.L": "hand.L", "thigh.L": "shin.L", "shin.L": "foot.L", "foot.L": "toe.L",
	"clavicle.R": "upper_arm.R", "upper_arm.R": "forearm.R", "forearm.R": "hand.R", "thigh.R": "shin.R", "shin.R": "foot.R", "foot.R": "toe.R"}

var out_root := "res://art/monsters/"


func _init() -> void:
	var ids := []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_root = arg.substr(6)
		else:
			ids.append(arg)
	if ids.is_empty():
		ids = VARIANTS.keys()
	for id in ids:
		_build(id, VARIANTS[id])
	quit()


func _build(id: String, spec: Dictionary) -> void:
	var donor := Rig.load_donor()
	var donor_sk := Rig.donor_skeleton(donor)
	var donor_global := _globals(donor_sk)
	var donor_index := {}
	for i in donor_sk.get_bone_count():
		donor_index[donor_sk.get_bone_name(i)] = i
	var donor_by_name := {}
	for i in donor_sk.get_bone_count():
		donor_by_name[donor_sk.get_bone_name(i)] = donor_global[i]

	var mummy_root := Rig.load_gltf(str(spec.get("source", Rig.STANDIN)))
	var m_sk := mummy_root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var m_mesh := mummy_root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var m_global := _globals(m_sk)
	var m_index := {}
	for i in m_sk.get_bone_count():
		m_index[m_sk.get_bone_name(i)] = i

	# swing the stand-in's limbs to the donor's rest directions (see build_mummy_archer.gd)
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

	var arrays := m_mesh.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var per := (arrays[Mesh.ARRAY_BONES] as PackedInt32Array).size() / verts.size()
	var m_bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var m_weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var skin := m_mesh.skin
	var infl := []
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
	var min_y := 1e9
	for p in swung:
		min_y = minf(min_y, p.y)
	var hips_y: float = (A[m_index["hips"]] as Transform3D * (m_global[m_index["hips"]] as Transform3D).origin).y - min_y
	var donor_hips: float = (donor_global[donor_index["mixamorig_Hips"]] as Transform3D).origin.y
	var f := donor_hips / hips_y
	var shift := Vector3(0, min_y, 0)

	var new_pos := {}
	for mname in m_index:
		var i: int = m_index[mname]
		var pos: Vector3 = f * ((A[i] as Transform3D) * (m_global[i] as Transform3D).origin - shift)
		if MAP.has(mname) and not mname.begins_with("attach"):
			new_pos[MAP[mname]] = pos
		elif EXTRA.has(mname):
			new_pos[EXTRA[mname][0]] = pos
	new_pos["Root"] = Vector3.ZERO
	new_pos["mixamorig_Spine1"] = ((new_pos["mixamorig_Spine"] as Vector3) + (new_pos["mixamorig_Spine2"] as Vector3)) * 0.5
	for mname in EXTRA:
		if not new_pos.has(EXTRA[mname][0]):  # a source rig without loose-bandage joints: they hang just under their parent joint
			new_pos[EXTRA[mname][0]] = (new_pos[EXTRA[mname][1]] as Vector3) + NO_EXTRA_POS * 0.5
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

	# proportions: the head scale (joints and vertices alike), then the shoulder width
	var head_scale: float = spec["head"]
	var head_pos: Vector3 = new_pos["mixamorig_Head"]
	for name in _subtree(donor_sk, "mixamorig_Head"):
		if name != "mixamorig_Head":
			new_pos[name] = head_pos + ((new_pos[name] as Vector3) - head_pos) * head_scale
	var final_pos := PackedVector3Array()
	final_pos.resize(verts.size())
	for v in verts.size():
		var p: Vector3 = f * (swung[v] - shift)
		var wh := float((infl[v] as Dictionary).get("mixamorig_Head", 0.0))
		p += wh * (head_scale - 1.0) * (p - head_pos)
		final_pos[v] = p
	var warp := _width_warp(donor_sk, new_pos, float(spec["width"]))
	for name in new_pos:
		new_pos[name] = _warp_point(warp, name, new_pos[name])
	for v in final_pos.size():
		var p := Vector3.ZERO
		var total := 0.0
		for name in infl[v]:
			p += float(infl[v][name]) * _warp_point(warp, name, final_pos[v])
			total += float(infl[v][name])
		final_pos[v] = p / total

	var new_global := {}
	for i in donor_sk.get_bone_count():
		new_global[donor_sk.get_bone_name(i)] = Transform3D((donor_global[i] as Transform3D).basis, new_pos[donor_sk.get_bone_name(i)])
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

	# ---- the body
	var bone_rests := []
	for i in skeleton.get_bone_count():
		bone_rests.append(new_global[names[i]])
	var body_surface := _surface(final_pos, swung_n, arrays[Mesh.ARRAY_TEX_UV], infl, name_to_index, arrays[Mesh.ARRAY_INDEX])
	if spec.get("simplify", true):
		body_surface = _simplify(body_surface, bone_rests)
	var body_mesh := ArrayMesh.new()
	body_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, body_surface)
	var texture_image := Image.load_from_file(ProjectSettings.globalize_path(str(spec.get("albedo", Rig.STANDIN_ALBEDO))))
	var tex_size: int = int(spec.get("texture_size", TEXTURE_SIZE))
	texture_image.resize(tex_size, tex_size, Image.INTERPOLATE_LANCZOS)
	_tint(texture_image, spec["tint"])
	var body_material := StandardMaterial3D.new()
	body_material.resource_name = "bandage"
	body_material.albedo_texture = ImageTexture.create_from_image(texture_image)
	body_material.roughness = 0.9
	body_mesh.surface_set_material(0, body_material)

	var root := Node3D.new()
	root.name = spec["node"]
	var rig := Node3D.new()
	rig.name = "rig"
	root.add_child(rig)
	rig.add_child(skeleton)
	_add_mesh(skeleton, spec["node"] + "_Body", body_mesh, new_skin)

	# ---- the gear
	var ctx := {"donor_global": donor_by_name, "new_global": new_global, "name_to_index": name_to_index, "skeleton": skeleton,
		"skin": new_skin, "node": spec["node"], "head": _bounds(final_pos, infl, "mixamorig_Head", 0.9),
		"chest": _bounds(final_pos, infl, "mixamorig_Spine2", 0.5), "new_pos": new_pos}
	# the face/skull of the head (an orc's head bounds include the ears and the mohawk): the middle 62% across, the lower 64% up
	var hb: AABB = ctx["head"]
	# centred on the head joint across (the bounds are lopsided: one ear is a separate rigid part, the mohawk leans)
	var head_x: float = (new_pos["mixamorig_Head"] as Vector3).x
	ctx["face"] = AABB(Vector3(head_x - hb.size.x * 0.31, hb.position.y, hb.position.z), Vector3(hb.size.x * 0.62, hb.size.y * 0.64, hb.size.z))
	var sockets := {}
	for gear in spec["gear"]:
		var made: Dictionary = call("_gear_" + gear, ctx)
		for piece in made:
			sockets[piece] = made[piece]

	for node in [rig, skeleton]:
		node.owner = root
	for child in skeleton.get_children():
		child.owner = root
	var tris := 0
	var mesh_tris := {}
	var top := -1e9
	var bottom := 1e9
	for child in skeleton.get_children():
		var m := (child as MeshInstance3D).mesh
		var t := 0
		for s in m.get_surface_count():
			t += (m.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		tris += t
		mesh_tris[str(child.name)] = t
		var box := m.get_aabb()
		top = maxf(top, box.end.y)
		bottom = minf(bottom, box.position.y)
	var out_dir := out_root + id + "/"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var state := GLTFState.new()
	var document := GLTFDocument.new()
	document.image_format = "JPEG"
	document.lossy_quality = 0.8
	var err := document.append_from_scene(root, state)
	if err == OK:
		err = document.write_to_filesystem(state, out_dir + id + ".glb")
	if err == OK:
		Rig.minify_glb(out_dir + id + ".glb")
	if err == OK and spec.has("sheet"):
		# the orcs (a 3.4k-triangle body): drop the TANGENT streams Godot's writer adds (no normal map; ~100 KB) to stay in the budget
		var py := OS.execute("python", ["-I", ProjectSettings.globalize_path("res://tools/monsters/prune_glb.py"), ProjectSettings.globalize_path(out_dir + id + ".glb"), "--strip-tangents"])
		print("  prune_glb --strip-tangents exit=", py)
	var bytes := FileAccess.get_file_as_bytes(out_dir + id + ".glb").size()
	print(id, ": export err=", err, " tris=", tris, " ", mesh_tris, " joints=", skeleton.get_bone_count(), " bounds y=", bottom, "..", top, " bytes=", bytes)

	# the monster sheet next to the model (the game reads combat.json; this records what the model offers)
	var library := "res://art/animations/monster_clips_%s.glb" % spec["stance"]
	var marks: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(library.get_basename() + ".json"))
	var info := {
		"id": id,
		"model": out_dir + id + ".glb",
		"model_height": spec["height"],
		"animations": library,
		"stance": spec["stance"],
		"clips": marks.keys(),
		"move_clips": spec["clips"],
		"run_clip_speed": float(marks["run"]["travel_per_second"]),
		"hips_scale": 1.0,
		"sockets": sockets,
		"meshes": mesh_tris,
		"triangles": tris,
		"joints": skeleton.get_bone_count(),
		"extra_joints": ["bandage_upper_L", "bandage_upper_R", "bandage_lower_L", "bandage_lower_R"],  ## the shared monster rig's extras (an orc leaves them unweighted)
		"rig": "shared studio05 102-joint rig (donor art/characters/studio05/split/body_longbow.glb), no donor joint removed or merged",
		"texture": "one %dx%d albedo (%s), lossy" % [tex_size, tex_size, "the Boss model atlas" + (", tinted" if spec["tint"] != Color(1, 1, 1) else "") if spec.has("source") else "stand-in bandage atlas, tinted"],
		"built_by": "tools/monsters/build_mummy_family.gd",
		"request_sheet": "docs/art/monster_requests/%s.md" % spec.get("sheet", "mummy_base" if id == "mummy" else ("mummy_boss" if id == "mummy_high_wizard" else id)),
	}
	var file := FileAccess.open(out_dir + id + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(info, "  ", false) + "\n")
	file.close()
	root.free()
	donor.free()
	mummy_root.free()


# ------------------------------------------------------------------ gear

func _gear_blade(ctx: Dictionary) -> Dictionary:
	var frame := _weapon_frame(ARMOR_SWORD_SHIELD, ["B 02 | Sword"])
	var acc := _acc()
	var L: float = frame["reach"] * 0.62
	# a short leaf blade: grip, small guard, a leaf-shaped bronze blade gone rusty
	var outline := PackedVector2Array([Vector2(-0.16, -0.035), Vector2(0.18, -0.035), Vector2(0.18, -0.09), Vector2(0.24, -0.08), Vector2(0.5, -0.1),
		Vector2(0.85, -0.05), Vector2(1.0, 0.0), Vector2(0.85, 0.05), Vector2(0.5, 0.1), Vector2(0.24, 0.08), Vector2(0.18, 0.09), Vector2(0.18, 0.035), Vector2(-0.16, 0.035)])
	_add_extrude_frame(acc, outline, frame, L, 0.035 * L)
	var name: String = ctx["node"] + "_Blade"
	_add_piece(ctx, name, acc, frame["joint"], frame, _mat("blade", RUST, 0.25, 0.7))
	return {name: frame["joint"]}


func _gear_khopesh(ctx: Dictionary) -> Dictionary:
	var frame := _weapon_frame(ARMOR_SWORD_SHIELD, ["B 02 | Sword"])
	var name: String = ctx["node"] + "_Khopesh"
	_add_piece(ctx, name, _khopesh(frame, frame["reach"] * 1.0), frame["joint"], frame, _mat("khopesh", BRONZE, 0.35, 0.55))
	return {name: frame["joint"]}


func _gear_boss_khopesh(ctx: Dictionary) -> Dictionary:
	var frame := _weapon_frame(ARMOR_GREATSWORD, ["A 03 | Sword blade", "A 14 | Sword grip", "A 06 | Sword crossguard", "A 11 | Sword pommel"])
	var name: String = ctx["node"] + "_Khopesh"
	_add_piece(ctx, name, _khopesh(frame, frame["reach"] * 0.8), frame["joint"], frame, _mat("khopesh_gold", GOLD, 0.45, 0.45))
	return {name: frame["joint"]}


## A khopesh along the frame: grip, straight neck, then the sickle (centre line on an arc, wide at its start, a point at the tip).
func _khopesh(frame: Dictionary, L: float) -> Dictionary:
	var right := PackedVector2Array()
	var left := PackedVector2Array()
	right.append(Vector2(-0.12, -0.035))
	right.append(Vector2(0.22, -0.035))
	right.append(Vector2(0.22, -0.07))
	right.append(Vector2(0.26, -0.07))
	right.append(Vector2(0.26, -0.03))
	right.append(Vector2(0.45, -0.03))
	left.append(Vector2(-0.12, 0.035))
	left.append(Vector2(0.22, 0.035))
	left.append(Vector2(0.22, 0.07))
	left.append(Vector2(0.26, 0.07))
	left.append(Vector2(0.26, 0.03))
	left.append(Vector2(0.45, 0.03))
	# the sickle: centre line from (0.45, 0) curving to -side over 112 degrees on radius R; a crescent whose cutting edge bulges
	# on the outside of the curve, widest a third of the way, a point at the tip
	var R := 0.3
	var steps := 10
	var centre := Vector2(0.45, -R)
	for s in range(1, steps + 1):
		var t := float(s) / steps
		var ang := PI * 0.5 - t * deg_to_rad(112.0)
		var c := centre + Vector2(cos(ang), sin(ang)) * R
		var radial := Vector2(cos(ang), sin(ang))
		var outer := 0.03 * (1.0 - t) + 0.15 * pow(sin(PI * minf(t * 1.25, 1.0)), 0.7) * (1.0 - t * 0.5)
		var inner := 0.03 * (1.0 - t)
		if s == steps:
			outer = 0.0
			inner = 0.0
		left.append(c + radial * outer)
		right.append(c - radial * inner)
	var outline := PackedVector2Array()
	outline.append_array(right)
	for i in range(left.size() - 2, -1, -1):
		outline.append(left[i])
	var acc := _acc()
	_add_extrude_frame(acc, outline, frame, L, 0.03 * L)
	return acc


func _gear_shield(ctx: Dictionary) -> Dictionary:
	var frame := _weapon_frame(ARMOR_SWORD_SHIELD, ["B 01 | Shield"])
	# Egyptian shield: straight sides and bottom, round top; bronze rim + teal hide panel with a gold disc
	# the player's heater shield lies along the forearm; the Egyptian one stands across it (upright when the arm guards)
	var H: float = frame["width"] * 1.4
	var W: float = frame["width"] * 0.88
	var up: Vector3 = -(frame["side"] as Vector3) * SHIELD_TOP
	var across: Vector3 = frame["up"]
	var rim := _arch_outline(W, H, 10)
	var panel := _arch_outline(W * 0.78, H * 0.84, 10)
	var acc := _acc()
	var thick := 0.06 * W
	_add_extrude(acc, rim, frame["centre"], up, across, frame["normal"], thick, Vector3.ZERO)
	var panel_acc := _acc()
	_add_extrude(panel_acc, panel, frame["centre"] + frame["normal"] * (thick * 0.5 + 0.002) - up * H * 0.02, up, across, frame["normal"], thick * 0.4, Vector3.ZERO)
	var disc := PackedVector2Array()
	for i in 10:
		disc.append(Vector2(cos(TAU * i / 10.0), sin(TAU * i / 10.0)) * W * 0.16)
	_add_extrude(panel_acc, disc, frame["centre"] + frame["normal"] * (thick * 0.9 + 0.003) + up * H * 0.08, up, across, frame["normal"], thick * 0.4, Vector3.ZERO)
	var name: String = ctx["node"] + "_Shield"
	_add_piece(ctx, name, acc, frame["joint"], frame, _mat("shield_rim", BRONZE, 0.35, 0.55), panel_acc, _mat("shield_panel", TEAL, 0.0, 0.8))
	return {name: frame["joint"]}


func _gear_staff(ctx: Dictionary) -> Dictionary:
	var frame := _weapon_frame(ARMOR_MAGIC, ["M 01 | Staff"])
	# the player's staff is short; the mummy's is longer toward its head end, with a gold scarab cradling a teal crystal
	var head_dir: Vector3 = frame["head_dir"]
	var grip: Vector3 = frame["grip"]
	var fwd: float = frame["reach_head"] * 1.55
	var back: float = frame["reach_tail"] * 1.0
	var r: float = frame["length"] * 0.035
	var acc := _acc()
	_add_tube(acc, grip - head_dir * back, grip + head_dir * fwd, r, r * 1.15, 6, true)
	var tip := grip + head_dir * fwd
	var side: Vector3 = frame["side"]
	var horns := _acc()
	# the scarab: a gold beetle body ring and two curved horns rising around the crystal
	_add_tube(horns, tip - head_dir * r * 1.5, tip + head_dir * r * 2.5, r * 2.4, r * 2.0, 6, true)
	for sgn in [-1.0, 1.0]:
		var prev: Vector3 = tip + head_dir * r * 2.0 + side * sgn * r * 2.0
		for k in range(1, 5):
			var t := k / 4.0
			var p: Vector3 = tip + head_dir * (r * 2.0 + t * fwd * 0.16) + side * sgn * (r * 2.0 + sin(t * PI) * fwd * 0.07 - t * t * fwd * 0.03)
			_add_tube(horns, prev, p, r * (1.0 - t * 0.5), r * (1.0 - t * 0.6), 4, false)
			prev = p
	var crystal := _acc()
	_add_crystal(crystal, tip + head_dir * fwd * 0.14, head_dir, side, fwd * 0.13, fwd * 0.24)
	var name: String = ctx["node"] + "_Staff"
	_add_piece(ctx, name, acc, frame["joint"], frame, _mat("staff_wood", WOOD, 0.0, 0.85), horns, _mat("staff_scarab", GOLD, 0.45, 0.45))
	var crystal_name: String = ctx["node"] + "_StaffCrystal"
	_add_piece(ctx, crystal_name, crystal, frame["joint"], frame, _mat("crystal_glow", GLOW, 0.0, 0.3, true))
	return {name: frame["joint"], crystal_name: frame["joint"]}


func _gear_helmet(ctx: Dictionary) -> Dictionary:
	var head: AABB = ctx["head"]
	var c := head.get_center() + Vector3(0, head.size.y * 0.06, -head.size.z * 0.02)
	var r := head.size * 0.5 * Vector3(1.1, 1.06, 1.1)
	var acc := _acc()
	_add_shell(acc, c, r, func(theta: float) -> float: return deg_to_rad(62.0 + 30.0 * smoothstep(0.6, 2.2, absf(theta))), 14, 6, head.size.x * 0.035)
	# a crest ridge front to back
	var crest := _acc()
	_add_tube(crest, c + Vector3(0, r.y * 0.93, r.z * 0.55), c + Vector3(0, r.y * 0.98, -r.z * 0.2), head.size.x * 0.06, head.size.x * 0.05, 4, true)
	_add_tube(crest, c + Vector3(0, r.y * 0.98, -r.z * 0.2), c + Vector3(0, r.y * 0.75, -r.z * 0.9), head.size.x * 0.05, head.size.x * 0.035, 4, true)
	var name: String = ctx["node"] + "_Helmet"
	_add_piece(ctx, name, acc, "mixamorig_Head", {}, _mat("helmet", BRONZE, 0.35, 0.55), crest, _mat("helmet_crest", TEAL, 0.0, 0.7))
	return {name: "mixamorig_Head"}


func _gear_hood(ctx: Dictionary) -> Dictionary:
	var head: AABB = ctx["head"]
	var c := head.get_center() + Vector3(0, head.size.y * 0.04, -head.size.z * 0.05)
	var r := head.size * 0.5 * Vector3(1.14, 1.1, 1.16)
	var acc := _acc()
	# open in front of the face, falls to the nape at the back
	_add_shell(acc, c, r, func(theta: float) -> float: return deg_to_rad(55.0 + 75.0 * smoothstep(0.7, 2.0, absf(theta))), 14, 7, head.size.x * 0.04)
	var band := _acc()
	_add_shell(band, c + Vector3(0, -r.y * 0.02, 0), r * Vector3(1.03, 1.0, 1.03), func(theta: float) -> float: return deg_to_rad(58.0), 14, 1, head.size.x * 0.03, deg_to_rad(48.0))
	var name: String = ctx["node"] + "_Hood"
	_add_piece(ctx, name, acc, "mixamorig_Head", {}, _mat("hood", DARK_TEAL, 0.0, 0.85), band, _mat("hood_band", GOLD, 0.45, 0.45))
	return {name: "mixamorig_Head"}


func _gear_nemes(ctx: Dictionary) -> Dictionary:
	var head: AABB = ctx["head"]
	var c := head.get_center() + Vector3(0, head.size.y * 0.05, -head.size.z * 0.03)
	var r := head.size * 0.5 * Vector3(1.16, 1.08, 1.14)
	var acc := _acc()
	# the headcloth: a dome open over the face, reaching below the ears at the sides and the back
	_add_shell(acc, c, r, func(theta: float) -> float: return deg_to_rad(66.0 + 50.0 * smoothstep(0.5, 1.6, absf(theta))), 16, 7, head.size.x * 0.04)
	# the two lappets falling in front of the shoulders, flaring outward
	for sgn in [-1.0, 1.0]:
		var top := c + Vector3(sgn * r.x * 0.86, -r.y * 0.35, r.z * 0.12)
		var bottom := c + Vector3(sgn * r.x * 1.12, -r.y * 1.75, r.z * 0.28)
		_add_slab(acc, top, bottom, r.z * 0.85, r.z * 1.0, head.size.x * 0.06, Vector3(sgn, 0, 0))
	# the uraeus at the brow: a small gold cobra plate
	var uraeus := _acc()
	var brow := c + Vector3(0, r.y * 0.42, r.z * 0.93)
	_add_slab(uraeus, brow + Vector3(0, r.y * 0.28, 0.0), brow, r.x * 0.16, r.x * 0.1, head.size.x * 0.05, Vector3(0, 0, 1))
	var name: String = ctx["node"] + "_Nemes"
	var stripes := _mat("nemes", Color.WHITE, 0.3, 0.55)
	stripes.albedo_texture = ImageTexture.create_from_image(_stripes(8, 64, 7, GOLD, DARK_TEAL, 0.3))
	_add_piece(ctx, name, acc, "mixamorig_Head", {}, stripes, uraeus, _mat("uraeus", GOLD, 0.45, 0.45))
	return {name: "mixamorig_Head"}


func _gear_mask(ctx: Dictionary) -> Dictionary:
	var head: AABB = ctx["head"]
	var c := head.get_center() + Vector3(0, -head.size.y * 0.02, 0.0)
	var r := head.size * 0.5 * Vector3(1.02, 1.0, 1.08)
	var acc := _acc()
	# the gold face: the front of the head from the brow to the chin
	_add_patch(acc, c, r, deg_to_rad(-62.0), deg_to_rad(62.0), deg_to_rad(62.0), deg_to_rad(150.0), 8, 6)
	# the false beard under the chin
	var chin := c + Vector3(0, -r.y * 0.86, r.z * 0.5)
	_add_tube(acc, chin, chin + Vector3(0, -r.y * 0.5, r.z * 0.08), r.x * 0.16, r.x * 0.12, 6, true)
	var eyes := _acc()
	for sgn in [-1.0, 1.0]:
		var theta: float = sgn * deg_to_rad(23.0)
		var phi := deg_to_rad(92.0)
		var p: Vector3 = c + Vector3(r.x * sin(phi) * sin(theta), r.y * cos(phi), r.z * sin(phi) * cos(theta)) * 1.02
		_add_crystal(eyes, p, Vector3(sgn * 0.2, 0, 1).normalized(), Vector3(1, 0, 0), r.x * 0.19, r.x * 0.07)
	var name: String = ctx["node"] + "_Mask"
	_add_piece(ctx, name, acc, "mixamorig_Head", {}, _mat("mask", GOLD, 0.5, 0.4))
	var eyes_name: String = ctx["node"] + "_Eyes"
	_add_piece(ctx, eyes_name, eyes, "mixamorig_Head", {}, _mat("eyes_glow", GLOW, 0.0, 0.3, true))
	return {name: "mixamorig_Head", eyes_name: "mixamorig_Head"}


func _gear_collar(ctx: Dictionary) -> Dictionary:
	var new_pos: Dictionary = ctx["new_pos"]
	var neck: Vector3 = new_pos["mixamorig_Neck"]
	var shoulder := absf((new_pos["mixamorig_LeftArm"] as Vector3).x - (new_pos["mixamorig_RightArm"] as Vector3).x) * 0.5
	var chest: AABB = ctx["chest"]
	var depth := chest.size.z * 0.5
	var cz := chest.get_center().z
	var acc := _acc()
	# the usekh: a broad ring falling from the neck over the shoulders, banded gold and teal
	var seg := 18
	var rings := [[0.0, 0.5, 0.95, 0.06], [0.5, 1.0, 1.45, -0.04], [1.0, 1.42, 1.75, -0.24]]  # [v, x radius / shoulder, z radius / depth, y / shoulder]
	var thick := shoulder * 0.05
	var base: int = acc["v"].size()
	for layer in 2:
		for ring in rings:
			for s in seg:
				var a := TAU * s / seg
				var out := 1.0 + layer * 0.0
				var p := Vector3(sin(a) * shoulder * float(ring[1]), neck.y - shoulder * 0.12 + shoulder * float(ring[3]) - layer * thick, cz + cos(a) * depth * float(ring[2]) * out)
				acc["v"].append(p)
				acc["n"].append(Vector3(sin(a), 1.4, cos(a)).normalized() * (1.0 if layer == 0 else -1.0))
				acc["uv"].append(Vector2(float(s) / seg, float(ring[0])))
	var per_layer := rings.size() * seg
	for layer in 2:
		for k in rings.size() - 1:
			for s in seg:
				var a: int = base + layer * per_layer + k * seg + s
				var b: int = base + layer * per_layer + k * seg + (s + 1) % seg
				var c2 := a + seg
				var d := b + seg
				if layer == 0:
					acc["i"].append_array(([a, b, c2, b, d, c2]))
				else:
					acc["i"].append_array(([a, c2, b, b, c2, d]))
	# close the outer rim between the two layers
	for s in seg:
		var a: int = base + (rings.size() - 1) * seg + s
		var b: int = base + (rings.size() - 1) * seg + (s + 1) % seg
		acc["i"].append_array(([a, a + per_layer, b, b, a + per_layer, b + per_layer]))
	var name: String = ctx["node"] + "_Collar"
	var bands := _mat("collar", Color.WHITE, 0.35, 0.5)
	bands.albedo_texture = ImageTexture.create_from_image(_stripes(8, 64, 5, GOLD, TEAL))
	_add_piece(ctx, name, acc, "mixamorig_Spine2", {}, bands)
	print("  collar: neck y=", neck.y, " shoulder=", shoulder, " chest depth=", depth)
	return {name: "mixamorig_Spine2"}


# ------------------------------------------------------------------ orc gear (2026-11-21)

## The grunt's cleaver: a wide, square-ended butcher blade with a notch, on a leather-wrapped grip, in the pose of the player's sword.
func _gear_cleaver(ctx: Dictionary) -> Dictionary:
	var frame := _weapon_frame(ARMOR_SWORD_SHIELD, ["B 02 | Sword"])
	var L: float = frame["reach"] * 0.85
	var blade := PackedVector2Array([Vector2(0.2, -0.07), Vector2(0.62, -0.1), Vector2(0.98, -0.12), Vector2(1.0, -0.04), Vector2(0.98, 0.2),
		Vector2(0.78, 0.22), Vector2(0.72, 0.16), Vector2(0.64, 0.2), Vector2(0.2, 0.16)])
	var acc := _acc()
	_add_extrude_frame(acc, blade, frame, L, 0.04 * L)
	var grip := _acc()
	_add_extrude_frame(grip, PackedVector2Array([Vector2(-0.18, -0.045), Vector2(0.21, -0.045), Vector2(0.21, 0.045), Vector2(-0.18, 0.045)]), frame, L, 0.07 * L)
	var name: String = ctx["node"] + "_Cleaver"
	_add_piece(ctx, name, acc, frame["joint"], frame, _mat("cleaver", IRON, 0.4, 0.5), grip, _mat("cleaver_grip", LEATHER, 0.0, 0.85))
	return {name: frame["joint"]}


## The archer's bow: the player's own longbow and string (weighted to the donor rig) moved to the orc's rest pose like the mummy
## archer's, plus the nocked "arrow" the view shows while a shot winds up (placed on the full-draw pose, weighted to the right hand).
func _gear_bow(ctx: Dictionary) -> Dictionary:
	var donor_global: Dictionary = ctx["donor_global"]
	var new_global: Dictionary = ctx["new_global"]
	var name_to_index: Dictionary = ctx["name_to_index"]
	var armor_state := GLTFState.new()
	var armor_doc := GLTFDocument.new()
	armor_doc.append_from_file(ProjectSettings.globalize_path(ARMOR_LONGBOW), armor_state)
	var armor := armor_doc.generate_scene(armor_state)
	var armor_sk := Rig.donor_skeleton(armor)
	var armor_global := _globals(armor_sk)
	var made := {}
	for piece in [["L 01 | Bow", "_Bow", LEATHER.darkened(0.1)], ["L 17 | Bow string", "_BowString", BONE]]:
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
				if bname == "":
					bname = armor_sk.get_bone_name(mi.skin.get_bind_bone(ab[v * aper + k]))
				var gd: Transform3D = armor_global[armor_sk.find_bone(bname)]
				var rest_pos: Vector3 = gd * (mi.skin.get_bind_pose(ab[v * aper + k]) * av[v])
				var move: Transform3D = (new_global[bname] as Transform3D) * (donor_global[bname] as Transform3D).affine_inverse()
				p += w * (move * rest_pos)
				n += w * (move.basis * (gd.basis * (mi.skin.get_bind_pose(ab[v * aper + k]).basis * an[v])))
				list[bname] = list.get(bname, 0.0) + w
			out_v.append(p)
			out_n.append(n.normalized())
			out_infl.append(list)
		var surface := _surface(out_v, out_n, a[Mesh.ARRAY_TEX_UV], out_infl, name_to_index, a[Mesh.ARRAY_INDEX])
		if piece[1] == "_Bow":
			var rests := []
			for i in (ctx["skeleton"] as Skeleton3D).get_bone_count():
				rests.append(new_global[(ctx["skeleton"] as Skeleton3D).get_bone_name(i)])
			surface = _simplify(surface, rests)
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
		mesh.surface_set_material(0, _mat("bow" + piece[1].to_lower(), piece[2], 0.0, 0.85))
		_add_mesh(ctx["skeleton"], ctx["node"] + piece[1], mesh, ctx["skin"])
		made[ctx["node"] + piece[1]] = "mixamorig_LeftHand"
	armor.free()
	# the nocked arrow on the full-draw pose
	var skeleton: Skeleton3D = ctx["skeleton"]
	var donor := Rig.load_donor()
	var draw := Rig.donor_player(donor).get_animation("lb_draw_arrow")
	Rig.pose_at(skeleton, draw, Rig.clip_tracks(draw), 1.017)
	var rh := skeleton.find_bone("mixamorig_RightHand")
	var lh := skeleton.find_bone("mixamorig_LeftHand")
	var rh_pose := skeleton.get_bone_global_pose(rh)
	var tail: Vector3 = rh_pose.origin
	var dir: Vector3 = (skeleton.get_bone_global_pose(lh).origin - tail).normalized()
	_add_mesh(skeleton, "arrow", Archer._arrow(tail, dir, 0.3, rh_pose, new_global["mixamorig_RightHand"], name_to_index["mixamorig_RightHand"]), ctx["skin"])
	skeleton.reset_bone_poses()
	donor.free()
	made["arrow"] = "mixamorig_RightHand"
	return made


## The archer's red cloth headband round the brow (under the mohawk), its two tails hanging at the back of the head.
func _gear_headband(ctx: Dictionary) -> Dictionary:
	var head: AABB = ctx["face"]
	var c := head.get_center()
	var r := head.size * 0.5 * Vector3(1.06, 1.0, 1.06)
	var acc := _acc()
	_add_shell(acc, c + Vector3(0, r.y * 0.1, 0), r, func(_theta: float) -> float: return deg_to_rad(66.0), 14, 1, head.size.x * 0.03, deg_to_rad(48.0))
	for sgn in [-1.0, 1.0]:
		var top: Vector3 = c + Vector3(sgn * r.x * 0.18, r.y * 0.2, -r.z * 0.98)
		_add_slab(acc, top, top + Vector3(sgn * r.x * 0.25, -r.y * 0.9, -r.z * 0.25), r.x * 0.2, r.x * 0.14, head.size.x * 0.03, Vector3(0, 0, -1))
	var name: String = ctx["node"] + "_Headband"
	_add_piece(ctx, name, acc, "mixamorig_Head", {}, _mat("headband", RED_CLOTH, 0.0, 0.85))
	return {name: "mixamorig_Head"}


## The shaman's totem staff: a crooked wooden pole with bone rings, topped by a horned skull holding a green glowing stone.
func _gear_totem_staff(ctx: Dictionary) -> Dictionary:
	var frame := _weapon_frame(ARMOR_MAGIC, ["M 01 | Staff"])
	var head_dir: Vector3 = frame["head_dir"]
	var grip: Vector3 = frame["grip"]
	var side: Vector3 = frame["side"]
	var fwd: float = frame["reach_head"] * 1.5
	var back: float = frame["reach_tail"] * 1.0
	var r: float = frame["length"] * 0.04
	var wood := _acc()
	var bend := side * fwd * 0.05
	_add_tube(wood, grip - head_dir * back, grip + head_dir * fwd * 0.5 + bend, r, r * 1.1, 6, true)
	_add_tube(wood, grip + head_dir * fwd * 0.5 + bend, grip + head_dir * fwd, r * 1.1, r * 1.3, 6, true)
	var tip := grip + head_dir * fwd
	var bone := _acc()
	for t: float in [0.15, 0.55]:
		var p: Vector3 = grip + head_dir * fwd * t + bend * (t * 2.0)
		_add_tube(bone, p - head_dir * r, p + head_dir * r, r * 1.6, r * 1.6, 6, true)
	# the skull: a squat block-ish crystal, two horns curving up and out
	_add_crystal(bone, tip + head_dir * r * 3.0, head_dir, side, r * 3.2, r * 3.6)
	for sgn in [-1.0, 1.0]:
		var prev: Vector3 = tip + head_dir * r * 3.5 + side * sgn * r * 2.4
		for k in range(1, 5):
			var t := k / 4.0
			var p: Vector3 = tip + head_dir * (r * 3.5 + t * r * 6.0) + side * sgn * (r * 2.4 + t * r * 5.0 - t * t * r * 2.0)
			_add_tube(bone, prev, p, r * (1.0 - t * 0.55), r * (1.0 - t * 0.7), 4, false)
			prev = p
	var stone := _acc()
	_add_crystal(stone, tip + head_dir * r * 7.5, head_dir, side, r * 1.6, r * 2.4)
	var name: String = ctx["node"] + "_Staff"
	_add_piece(ctx, name, wood, frame["joint"], frame, _mat("staff_wood", WOOD, 0.0, 0.85), bone, _mat("staff_bone", BONE, 0.0, 0.7))
	var stone_name: String = ctx["node"] + "_StaffStone"
	_add_piece(ctx, stone_name, stone, frame["joint"], frame, _mat("stone_glow", ORC_GLOW, 0.0, 0.3, true))
	return {name: frame["joint"], stone_name: frame["joint"]}


## The shaman's skull mask: a bone face plate over the upper face (brow to the tusks), green glowing eye holes, two small horns.
func _gear_skull_mask(ctx: Dictionary) -> Dictionary:
	var head: AABB = ctx["face"]
	var c := head.get_center() + Vector3(0, -head.size.y * 0.14, 0)  # down over the eyes (the face box reaches up into the skull)
	var r := head.size * 0.5 * Vector3(1.04, 1.0, 1.1)
	var acc := _acc()
	_add_patch(acc, c, r, deg_to_rad(-58.0), deg_to_rad(58.0), deg_to_rad(40.0), deg_to_rad(104.0), 8, 5)
	for sgn in [-1.0, 1.0]:
		var base: Vector3 = c + Vector3(sgn * r.x * 0.55, r.y * 0.72, r.z * 0.45)
		var prev: Vector3 = base
		for k in range(1, 4):
			var t := k / 3.0
			var p: Vector3 = base + Vector3(sgn * r.x * (0.25 * t), r.y * (0.55 * t), -r.z * (0.25 * t * t))
			_add_tube(acc, prev, p, head.size.x * 0.07 * (1.0 - t * 0.6), head.size.x * 0.07 * (1.0 - t * 0.85), 5, true)
			prev = p
	var eyes := _acc()
	for sgn in [-1.0, 1.0]:
		var theta: float = sgn * deg_to_rad(24.0)
		var phi := deg_to_rad(78.0)
		var p: Vector3 = c + Vector3(r.x * sin(phi) * sin(theta), r.y * cos(phi), r.z * sin(phi) * cos(theta)) * 1.03
		_add_crystal(eyes, p, Vector3(sgn * 0.2, 0, 1).normalized(), Vector3(1, 0, 0), r.x * 0.17, r.x * 0.06)
	var name: String = ctx["node"] + "_SkullMask"
	_add_piece(ctx, name, acc, "mixamorig_Head", {}, _mat("skull_mask", BONE, 0.0, 0.7))
	var eyes_name: String = ctx["node"] + "_MaskEyes"
	_add_piece(ctx, eyes_name, eyes, "mixamorig_Head", {}, _mat("mask_eyes_glow", ORC_GLOW, 0.0, 0.3, true))
	return {name: "mixamorig_Head", eyes_name: "mixamorig_Head"}


# ------------------------------------------------------------------ orc warlock MOCKUP weapons (2026-11-21)
# Boss: the warlock fights with sword and shield, but no weapon model exists yet. These are deliberately PLAIN placeholder shapes
# (flat grey steel, plain brown board, every mesh and material named MOCKUP) in the exact pose of the player's own sword and
# shield, so the copied sword-and-shield clips can be judged. Replace them with the real weapon models when they arrive.
const MOCK_STEEL := Color(0.62, 0.63, 0.66)
const MOCK_BOARD := Color(0.42, 0.3, 0.2)


## A straight broadsword along the player's sword frame: grip, a plain cross-guard, a long straight blade with a point.
func _gear_mock_sword(ctx: Dictionary) -> Dictionary:
	var frame := _weapon_frame(ARMOR_SWORD_SHIELD, ["B 02 | Sword"])
	var L: float = frame["reach"] * 1.05
	var blade := _acc()
	_add_extrude_frame(blade, PackedVector2Array([Vector2(0.2, -0.055), Vector2(0.9, -0.05), Vector2(1.0, 0.0), Vector2(0.9, 0.05), Vector2(0.2, 0.055)]), frame, L, 0.025 * L)
	_add_extrude_frame(blade, PackedVector2Array([Vector2(0.16, -0.16), Vector2(0.2, -0.16), Vector2(0.2, 0.16), Vector2(0.16, 0.16)]), frame, L, 0.06 * L)
	var grip := _acc()
	_add_extrude_frame(grip, PackedVector2Array([Vector2(-0.14, -0.035), Vector2(0.16, -0.035), Vector2(0.16, 0.035), Vector2(-0.14, 0.035)]), frame, L, 0.06 * L)
	var name: String = ctx["node"] + "_MOCKUP_Sword"
	_add_piece(ctx, name, blade, frame["joint"], frame, _mat("MOCKUP_sword_steel", MOCK_STEEL, 0.3, 0.6), grip, _mat("MOCKUP_sword_grip", MOCK_BOARD, 0.0, 0.9))
	return {name: frame["joint"]}


## A plain kite shield on the player's shield frame (long axis along the forearm, as the player's heater shield), a little larger.
func _gear_mock_shield(ctx: Dictionary) -> Dictionary:
	var frame := _weapon_frame(ARMOR_SWORD_SHIELD, ["B 01 | Shield"])
	var H: float = frame["length"] * 1.15
	var W: float = frame["width"] * 1.15
	var outline := PackedVector2Array([Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(0.1, 0.5), Vector2(-0.25, 0.32), Vector2(-0.5, 0.0), Vector2(-0.25, -0.32), Vector2(0.1, -0.5)])
	var scaled := PackedVector2Array()
	for p in outline:
		scaled.append(Vector2(p.x * H, p.y * W))
	var up: Vector3 = frame["up"]
	var across: Vector3 = (frame["normal"] as Vector3).cross(up).normalized()
	var board := _acc()
	_add_extrude(board, scaled, frame["centre"], up, across, frame["normal"], 0.05 * W, Vector3.ZERO)
	var boss := _acc()
	var disc := PackedVector2Array()
	for i in 8:
		disc.append(Vector2(cos(TAU * i / 8.0), sin(TAU * i / 8.0)) * W * 0.14)
	_add_extrude(boss, disc, frame["centre"] + (frame["normal"] as Vector3) * W * 0.04 + up * H * 0.08, up, across, frame["normal"], 0.05 * W, Vector3.ZERO)
	var name: String = ctx["node"] + "_MOCKUP_Shield"
	_add_piece(ctx, name, board, frame["joint"], frame, _mat("MOCKUP_shield_board", MOCK_BOARD, 0.0, 0.9), boss, _mat("MOCKUP_shield_boss", MOCK_STEEL, 0.3, 0.6))
	return {name: frame["joint"]}


# ------------------------------------------------------------------ the player's weapon frames

## The pose of the player's weapon pieces in the donor rest pose: dominant joint, centre, long axis, flat side, the grip (the
## holding joint projected on the long axis) and the reach from the grip to either end.
func _weapon_frame(armor_path: String, pieces: Array) -> Dictionary:
	var armor := Rig.load_gltf(armor_path)
	var armor_sk := Rig.donor_skeleton(armor)
	var armor_global := _globals(armor_sk)
	var points := PackedVector3Array()
	var joint_weight := {}
	for piece in pieces:
		var mi := armor.find_child(piece, true, false) as MeshInstance3D
		var a := mi.mesh.surface_get_arrays(0)
		var av: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ab: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var aw: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		var aper := ab.size() / av.size()
		for v in av.size():
			var p := Vector3.ZERO
			for k in aper:
				var w := aw[v * aper + k]
				if w <= 0.0:
					continue
				var bname := String(mi.skin.get_bind_name(ab[v * aper + k]))
				var gd: Transform3D = armor_global[armor_sk.find_bone(bname)]
				p += w * (gd * (mi.skin.get_bind_pose(ab[v * aper + k]) * av[v]))
				joint_weight[bname] = float(joint_weight.get(bname, 0.0)) + w
			points.append(p)
	var joint := ""
	for name in joint_weight:
		if joint == "" or float(joint_weight[name]) > float(joint_weight[joint]):
			joint = name
	var centre := Vector3.ZERO
	for p in points:
		centre += p
	centre /= points.size()
	var axes := _pca(points, centre)
	var e1: Vector3 = axes[0]
	var e2: Vector3 = axes[1]
	var e3: Vector3 = axes[2]
	var lo := 1e9
	var hi := -1e9
	var wlo := 1e9
	var whi := -1e9
	for p in points:
		lo = minf(lo, (p - centre).dot(e1))
		hi = maxf(hi, (p - centre).dot(e1))
		wlo = minf(wlo, (p - centre).dot(e2))
		whi = maxf(whi, (p - centre).dot(e2))
	var joint_global: Transform3D = armor_global[armor_sk.find_bone(joint)]
	var hold: Vector3 = joint_global.origin
	var s := (hold - centre).dot(e1)
	s = clampf(s, lo, hi)
	var grip := centre + e1 * s
	var dir := e1 if hi - s >= s - lo else -e1
	var reach := maxf(hi - s, s - lo)
	var tail := minf(hi - s, s - lo)
	# the head end of a staff: the end with the wider cross-section
	var spread := [0.0, 0.0]
	var count := [0, 0]
	for p in points:
		var t := (p - centre).dot(e1)
		var radial := ((p - centre) - e1 * t).length()
		if t > hi - (hi - lo) * 0.15:
			spread[0] += radial
			count[0] += 1
		elif t < lo + (hi - lo) * 0.15:
			spread[1] += radial
			count[1] += 1
	var head_is_hi: bool = spread[0] / maxf(1, count[0]) >= spread[1] / maxf(1, count[1])
	var head_dir := e1 if head_is_hi else -e1
	var reach_head := (hi - s) if head_is_hi else (s - lo)
	var reach_tail := (s - lo) if head_is_hi else (hi - s)
	# the shield faces away from its arm; its top points up in the rest pose
	var normal := e3 if (centre - hold).dot(e3) >= 0.0 else -e3
	var up := e1 if e1.y >= 0.0 else -e1
	var flat_side := dir.cross(e3).normalized()
	armor.free()
	var frame := {"joint": joint, "joint_global": joint_global, "centre": centre, "grip": grip, "dir": dir, "side": flat_side, "flat": e3, "reach": reach, "tail": tail,
		"length": hi - lo, "width": whi - wlo, "normal": normal, "up": up, "head_dir": head_dir, "reach_head": reach_head, "reach_tail": reach_tail}
	print("  axes e1=", e1, " e2=", e2, " e3=", e3, " hold=", hold, " centre=", centre)
	print("  frame ", pieces, ": joint=", joint, " length=", snappedf(hi - lo, 0.001), " width=", snappedf(whi - wlo, 0.001), " reach=", snappedf(reach, 0.001), " tail=", snappedf(tail, 0.001), " head_reach=", snappedf(reach_head, 0.001))
	return frame


## Principal axes (largest spread first) of a point cloud, by power iteration on its covariance.
static func _pca(points: PackedVector3Array, centre: Vector3) -> Array:
	var m := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	for p in points:
		var d := p - centre
		var c := [d.x, d.y, d.z]
		for i in 3:
			for j in 3:
				m[i][j] += c[i] * c[j]
	var axes := []
	for n in 2:
		var v := Vector3(0.577, 0.577, 0.577) if n == 0 else Vector3(0.3, -0.8, 0.5)
		for it in 60:
			var w := Vector3(m[0][0] * v.x + m[0][1] * v.y + m[0][2] * v.z, m[1][0] * v.x + m[1][1] * v.y + m[1][2] * v.z, m[2][0] * v.x + m[2][1] * v.y + m[2][2] * v.z)
			for prev in axes:
				w -= (prev as Vector3) * w.dot(prev)
			v = w.normalized()
		axes.append(v)
	axes.append((axes[0] as Vector3).cross(axes[1]).normalized())
	return axes


# ------------------------------------------------------------------ geometry

static func _acc() -> Dictionary:
	return {"v": [], "n": [], "uv": [], "i": []}  ## plain Arrays (references): appended to in place


## A flat outline (x along the weapon, y across, in units of L) extruded `thick` along the weapon's flat normal, placed on the frame.
func _add_extrude_frame(acc: Dictionary, outline: PackedVector2Array, frame: Dictionary, L: float, thick: float) -> void:
	var scaled := PackedVector2Array()
	for p in outline:
		scaled.append(p * L)
	_add_extrude(acc, scaled, frame["grip"], frame["dir"], frame["side"], frame["flat"], thick, Vector3.ZERO)


## outline in (u, v) placed at origin + u * U + v * V, extruded +-thick/2 along N; flat normals; uv = the outline coordinates.
static func _add_extrude(acc: Dictionary, outline: PackedVector2Array, origin: Vector3, U: Vector3, V: Vector3, N: Vector3, thick: float, _unused: Vector3) -> void:
	var tris := Geometry2D.triangulate_polygon(outline)
	if tris.is_empty():
		var reversed := outline.duplicate()
		reversed.reverse()
		outline = reversed
		tris = Geometry2D.triangulate_polygon(outline)
	var n := outline.size()
	# orientation: front faces must face +N
	var area := 0.0
	for i in n:
		area += outline[i].x * outline[(i + 1) % n].y - outline[(i + 1) % n].x * outline[i].y
	var ccw := area > 0.0  # counter-clockwise in (U, V)
	var uv_ccw := U.cross(V).dot(N) > 0.0
	for side in [1.0, -1.0]:
		var base: int = acc["v"].size()
		for p in outline:
			acc["v"].append(origin + U * p.x + V * p.y + N * (thick * 0.5 * side))
			acc["n"].append(N * side)
			acc["uv"].append(p)
		for t in range(0, tris.size(), 3):
			var a := tris[t]
			var b := tris[t + 1]
			var c := tris[t + 2]
			var facing_front: bool = (ccw == uv_ccw) == (side > 0.0)
			if facing_front:
				acc["i"].append_array(([base + a, base + c, base + b]))
			else:
				acc["i"].append_array(([base + a, base + b, base + c]))
	# side walls
	for i in n:
		var p0 := outline[i]
		var p1 := outline[(i + 1) % n]
		var a0 := origin + U * p0.x + V * p0.y
		var a1 := origin + U * p1.x + V * p1.y
		var edge := a1 - a0
		var out := edge.cross(N).normalized()
		if not ((ccw == uv_ccw)):
			out = -out
		var base: int = acc["v"].size()
		for q in [a0 + N * thick * 0.5, a1 + N * thick * 0.5, a1 - N * thick * 0.5, a0 - N * thick * 0.5]:
			acc["v"].append(q)
			acc["n"].append(out)
			acc["uv"].append(p0)
		acc["i"].append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	_fix_winding(acc)


## Makes every triangle wind so its face normal agrees with its stored vertex normals (Godot: clockwise = front).
static func _fix_winding(acc: Dictionary) -> void:
	var v: Array = acc["v"]
	var nn: Array = acc["n"]
	var idx: Array = acc["i"]
	for t in range(0, idx.size(), 3):
		var a: Vector3 = v[idx[t]]
		var b: Vector3 = v[idx[t + 1]]
		var c: Vector3 = v[idx[t + 2]]
		var face := (b - a).cross(c - a)
		var want: Vector3 = nn[idx[t]] + nn[idx[t + 1]] + nn[idx[t + 2]]
		# Godot front faces are clockwise seen from the front: (b - a) x (c - a) points AWAY from the viewer
		if face.dot(want) > 0.0:
			var tmp: int = idx[t + 1]
			idx[t + 1] = idx[t + 2]
			idx[t + 2] = tmp
	acc["i"] = idx


## A Egyptian shield outline: straight sides and bottom, a half-round top (u up, v across), centred.
static func _arch_outline(W: float, H: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var r := W * 0.5
	var straight := H - r
	out.append(Vector2(-H * 0.5, -r))
	out.append(Vector2(-H * 0.5 + straight, -r))
	for s in range(1, steps):
		var a := -PI * 0.5 + PI * s / steps
		out.append(Vector2(-H * 0.5 + straight + cos(a) * r, sin(a) * r))
	out.append(Vector2(-H * 0.5 + straight, r))
	out.append(Vector2(-H * 0.5, r))
	return out


## A tube (n sides) from p0 to p1, radius r0 to r1, optional end caps; smooth sides.
static func _add_tube(acc: Dictionary, p0: Vector3, p1: Vector3, r0: float, r1: float, sides: int, caps: bool) -> void:
	var axis := (p1 - p0).normalized()
	var ref := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var x := axis.cross(ref).normalized()
	var y := axis.cross(x).normalized()
	var base: int = acc["v"].size()
	for ring in 2:
		var c := p0 if ring == 0 else p1
		var r := r0 if ring == 0 else r1
		for s in sides:
			var a := TAU * s / sides
			var d := x * cos(a) + y * sin(a)
			acc["v"].append(c + d * r)
			acc["n"].append(d)
			acc["uv"].append(Vector2(float(s) / sides, ring))
	for s in sides:
		var a := base + s
		var b := base + (s + 1) % sides
		acc["i"].append_array(([a, b, a + sides, b, b + sides, a + sides]))
	if caps:
		for ring in 2:
			var cb: int = acc["v"].size()
			var c := p0 if ring == 0 else p1
			var r := r0 if ring == 0 else r1
			var nrm := -axis if ring == 0 else axis
			acc["v"].append(c)
			acc["n"].append(nrm)
			acc["uv"].append(Vector2(0.5, ring))
			for s in sides:
				var a := TAU * s / sides
				acc["v"].append(c + (x * cos(a) + y * sin(a)) * r)
				acc["n"].append(nrm)
				acc["uv"].append(Vector2(float(s) / sides, ring))
			for s in sides:
				acc["i"].append_array(([cb, cb + 1 + s, cb + 1 + (s + 1) % sides]))
	_fix_winding(acc)


## A double pyramid (a cut crystal / a painted eye): centre, long axis, a side axis, radius and half length.
static func _add_crystal(acc: Dictionary, centre: Vector3, axis: Vector3, side: Vector3, radius: float, half: float) -> void:
	var x := (side - axis * side.dot(axis)).normalized()
	var y := axis.cross(x).normalized()
	var ring := []
	for s in 6:
		var a := TAU * s / 6.0
		ring.append(centre + (x * cos(a) + y * sin(a)) * radius)
	for tip in [centre + axis * half, centre - axis * half * 0.7]:
		for s in 6:
			var a: Vector3 = ring[s]
			var b: Vector3 = ring[(s + 1) % 6]
			var nrm: Vector3 = (a - centre + b - centre + ((tip as Vector3) - centre)).normalized()
			var base: int = acc["v"].size()
			for q in [a, b, tip]:
				acc["v"].append(q)
				acc["n"].append(nrm)
				acc["uv"].append(Vector2.ZERO)
			acc["i"].append_array(([base, base + 1, base + 2]))
	_fix_winding(acc)


## A thick tapered plate from `top` to `bottom` (widths across `face` x vertical), facing `face`; a lappet or a plate.
static func _add_slab(acc: Dictionary, top: Vector3, bottom: Vector3, w_top: float, w_bottom: float, thick: float, face: Vector3) -> void:
	var down := (bottom - top).normalized()
	var across := down.cross(face).normalized()
	var nrm := across.cross(down).normalized()
	if nrm.dot(face) < 0.0:
		nrm = -nrm
	var corners := [top - across * w_top * 0.5, top + across * w_top * 0.5, bottom + across * w_bottom * 0.5, bottom - across * w_bottom * 0.5]
	var faces := [[0, 1, 2, 3, nrm, 1.0], [0, 1, 2, 3, -nrm, -1.0]]
	for f in faces:
		var base: int = acc["v"].size()
		for k in 4:
			acc["v"].append((corners[k] as Vector3) + nrm * thick * 0.5 * float(f[5]))
			acc["n"].append(f[4])
			acc["uv"].append(Vector2(float(k == 1 or k == 2), float(k >= 2)))
		acc["i"].append_array(([base, base + 1, base + 2, base, base + 2, base + 3]))
	for k in 4:
		var a: Vector3 = corners[k]
		var b: Vector3 = corners[(k + 1) % 4]
		var out := ((a + b) * 0.5 - (top + bottom) * 0.5).normalized()
		var base: int = acc["v"].size()
		for q in [a + nrm * thick * 0.5, b + nrm * thick * 0.5, b - nrm * thick * 0.5, a - nrm * thick * 0.5]:
			acc["v"].append(q)
			acc["n"].append(out)
			acc["uv"].append(Vector2(0, float(k >= 2)))
		acc["i"].append_array(([base, base + 1, base + 2, base, base + 2, base + 3]))
	_fix_winding(acc)


## A part of an ellipsoid surface (theta around Y from +Z, phi from the top) as a shell with smooth normals (single sided, thin).
static func _add_patch(acc: Dictionary, c: Vector3, r: Vector3, t0: float, t1: float, p0: float, p1: float, nt: int, np: int) -> void:
	var base: int = acc["v"].size()
	for j in np + 1:
		var phi := lerpf(p0, p1, float(j) / np)
		for i in nt + 1:
			var theta := lerpf(t0, t1, float(i) / nt)
			var d := Vector3(sin(phi) * sin(theta), cos(phi), sin(phi) * cos(theta))
			acc["v"].append(c + d * r)
			acc["n"].append(Vector3(d.x / r.x, d.y / r.y, d.z / r.z).normalized())
			acc["uv"].append(Vector2(float(i) / nt, float(j) / np))
	for j in np:
		for i in nt:
			var a := base + j * (nt + 1) + i
			var b := a + 1
			var c2 := a + nt + 1
			var d2 := c2 + 1
			acc["i"].append_array(([a, b, c2, b, d2, c2]))
	_fix_winding(acc)


## A closed cap shell over the head: theta all round, from the top down to phi_max(theta), with a thickness (an inner layer and a rim).
## phi_min > 0 makes a band instead of a cap.
static func _add_shell(acc: Dictionary, c: Vector3, r: Vector3, phi_max: Callable, nt: int, np: int, thick: float, phi_min := 0.0) -> void:
	for layer in 2:
		var base: int = acc["v"].size()
		var rr := r if layer == 0 else r - Vector3.ONE * thick
		for j in np + 1:
			for i in nt:
				var theta := -PI + TAU * i / nt
				var phi := lerpf(maxf(phi_min, 0.001), float(phi_max.call(theta)), float(j) / np)
				var d := Vector3(sin(phi) * sin(theta), cos(phi), sin(phi) * cos(theta))
				acc["v"].append(c + d * rr)
				var nrm := Vector3(d.x / rr.x, d.y / rr.y, d.z / rr.z).normalized()
				acc["n"].append(nrm if layer == 0 else -nrm)
				acc["uv"].append(Vector2(float(i) / nt, float(j) / np))
		for j in np:
			for i in nt:
				var a := base + j * nt + i
				var b := base + j * nt + (i + 1) % nt
				acc["i"].append_array(([a, b, a + nt, b, b + nt, a + nt]))
	# the rim joining the layers at the lower edge (and the upper edge of a band)
	var outer_base: int = acc["v"].size() - 2 * (np + 1) * nt
	var inner_base: int = outer_base + (np + 1) * nt
	var edges := [np] if phi_min <= 0.0 else [0, np]
	for j in edges:
		for i in nt:
			var oa: int = outer_base + j * nt + i
			var ob: int = outer_base + j * nt + (i + 1) % nt
			var ia: int = inner_base + j * nt + i
			var ib: int = inner_base + j * nt + (i + 1) % nt
			var rim_base: int = acc["v"].size()
			var out := ((acc["v"][oa] as Vector3) - c).normalized() * Vector3(1, 0.2, 1)
			if j == 0 and phi_min > 0.0:
				out = Vector3.UP
			for q in [oa, ob, ib, ia]:
				acc["v"].append(acc["v"][q])
				acc["n"].append(out.normalized() if j == np else Vector3.UP)
				acc["uv"].append(Vector2(0, 1))
			acc["i"].append_array(([rim_base, rim_base + 1, rim_base + 2, rim_base, rim_base + 2, rim_base + 3]))
	_fix_winding(acc)


## Horizontal bands (v direction) of two colours, for the nemes and the collar (a flat painted pattern, no shading).
static func _stripes(w: int, h: int, bands: int, a: Color, b: Color, plain_top := 0.0) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		var band := 0 if float(y) / h < plain_top else int(floor((float(y) / h - plain_top) / (1.0 - plain_top) * bands * 2.0))
		for x in w:
			img.set_pixel(x, y, a if band % 2 == 0 else b)
	return img


static func _mat(name: String, color: Color, metallic: float, roughness: float, glow := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = name
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if glow:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 1.0
	return m


## Adds the gear piece as a skinned mesh: every vertex 100% on `joint` (the arrays are in the final model rest space, except a
## weapon frame's, which are in the DONOR rest space and are moved with the joint like the archer's bow).
func _add_piece(ctx: Dictionary, name: String, acc: Dictionary, joint: String, frame: Dictionary, material: Material, acc2: Variant = null, material2: Material = null) -> void:
	var mesh := ArrayMesh.new()
	var move := Transform3D.IDENTITY
	if not frame.is_empty():
		# the piece keeps its offset in the holding joint's own frame as the player's weapon has it in ITS file (whose rest pose may differ)
		move = (ctx["new_global"][joint] as Transform3D) * (frame["joint_global"] as Transform3D).affine_inverse()
		var donor_rest: Transform3D = ctx["donor_global"][joint]
		print("    ", name, ": joint rest angle player-file vs donor ", snappedf(rad_to_deg(Quaternion(donor_rest.basis.orthonormalized()).angle_to(Quaternion((frame["joint_global"] as Transform3D).basis.orthonormalized()))), 0.1), " deg")
	for pair in [[acc, material], [acc2, material2]]:
		if pair[0] == null:
			continue
		var a: Dictionary = pair[0]
		var verts := PackedVector3Array()
		var nrms := PackedVector3Array()
		for k in (a["v"] as Array).size():
			verts.append(move * (a["v"][k] as Vector3))
			nrms.append((move.basis * (a["n"][k] as Vector3)).normalized())
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		var index: int = ctx["name_to_index"][joint]
		for k in verts.size():
			bones.append_array(PackedInt32Array([index, 0, 0, 0]))
			weights.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = nrms
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(a["uv"])
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(a["i"])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, pair[1])
	_add_mesh(ctx["skeleton"], name, mesh, ctx["skin"])


# ------------------------------------------------------------------ body helpers

## Shoulder width: the spine joints and clavicles are scaled across (x) about the centre line, the arm chains moved out by the
## shoulder's offset (arms keep their thickness). bone -> [x scale, x offset].
func _width_warp(sk: Skeleton3D, new_pos: Dictionary, k: float) -> Dictionary:
	var warp := {}
	if absf(k - 1.0) < 0.001:
		return warp
	warp["mixamorig_Spine"] = [lerpf(1.0, k, 0.45), 0.0]
	warp["mixamorig_Spine1"] = [lerpf(1.0, k, 0.75), 0.0]
	warp["mixamorig_Spine2"] = [k, 0.0]
	warp["mixamorig_LeftShoulder"] = [k, 0.0]
	warp["mixamorig_RightShoulder"] = [k, 0.0]
	for side in ["Left", "Right"]:
		var arm := "mixamorig_%sArm" % side
		var dx := (k - 1.0) * (new_pos[arm] as Vector3).x
		var chain := _subtree(sk, arm)
		chain.append_array(["bandage_upper_" + side[0], "bandage_lower_" + side[0]])
		for name in chain:
			warp[name] = [1.0, dx]
	return warp


static func _warp_point(warp: Dictionary, bone: String, p: Vector3) -> Vector3:
	if not warp.has(bone):
		return p
	return Vector3(p.x * float(warp[bone][0]) + float(warp[bone][1]), p.y, p.z)


## Bounds of the vertices weighted at least `min_weight` to `bone`.
static func _bounds(pos: PackedVector3Array, infl: Array, bone: String, min_weight: float) -> AABB:
	var box := AABB()
	var first := true
	for v in pos.size():
		if float((infl[v] as Dictionary).get(bone, 0.0)) >= min_weight:
			if first:
				box = AABB(pos[v], Vector3.ZERO)
				first = false
			else:
				box = box.expand(pos[v])
	return box


static func _tint(img: Image, tint: Color) -> void:
	if tint == Color(1, 1, 1):
		return
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, c.a))


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
	print("  simplified ", (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3, " -> ", indices.size() / 3, " triangles")
	return out


static func _add_mesh(skeleton: Skeleton3D, name: String, mesh: ArrayMesh, skin: Skin) -> void:
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	instance.skin = skin
	skeleton.add_child(instance)
	instance.skeleton = NodePath("..")
