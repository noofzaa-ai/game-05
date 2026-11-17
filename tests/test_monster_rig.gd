extends RefCounted
## Monster rigging pilot (mummy archer): the shared bow clip library carries exactly the clips a bow monster needs, its marks are
## valid for the sim, the run clip does not drift, the monster keeps every joint a clip animates, and the files stay in budget.
## Tools: tools/monsters/build_clip_library.gd, build_mummy_archer.gd (docs/art/monster_requests/mummy_archer.md).

const AnimationSet := preload("res://client/animation_set.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")

const LIBRARY := "res://art/animations/monster_clips_bow.glb"
const MARKS := "res://art/animations/monster_clips_bow.json"
const MONSTER := "res://art/monsters/mummy_archer/mummy_archer.glb"
const MONSTER_IMPORT := "res://art/monsters/mummy_archer/mummy_archer.glb.import"
const TEXTURE_IMPORT := "res://art/monsters/mummy_archer/mummy_archer_mummy_bandage_albedo.jpg.import"
const GOBLIN_DATA := ["res://data/journeys/goblin_waves.json", "res://data/maps/goblin_arena_a.json", "res://data/maps/goblin_arena_b.json", "res://data/maps/goblin_arena_c.json", "res://data/maps/goblin_base_chief.json", "res://data/maps/goblin_base_courtyard.json", "res://data/maps/goblin_base_gate.json", "res://data/maps/goblin_base_quarry.json", "res://data/maps/goblin_base_rest.json", "res://data/maps/goblin_rest_camp.json"]
const DONOR := "res://art/characters/studio05/split/body_longbow.glb"
const GOBLIN_ARCHER := "res://art/monsters/goblin_archer/goblin_archer.glb"
const CLIPS := ["death", "hit", "idle", "run", "shoot", "volley"]
const EXTRA_JOINTS := ["bandage_upper_L", "bandage_upper_R", "bandage_lower_L", "bandage_lower_R"]
const LIBRARY_BUDGET := 200 * 1024  ## 6 clips on the 102-joint rig (pilot 195 KB, key tolerance 1.0 degree: 172 KB)
const MONSTER_BUDGET := 450 * 1024  ## goblin_archer.glb is 560904 bytes
const TRIANGLE_BUDGET := 4500  ## the request sheet's target for a NEW monster; the shipped archer is about 2,100 (simplified)
const MONSTER_TRIANGLE_LIMIT := 5000  ## Boss 2026-11-17: HARD limit for every monster model (goblins and mummies alike)
const MONSTER_FILE_LIMIT := 450 * 1024  ## the model (without its embedded textures) and each texture
const MONSTER_JOINT_LIMIT := 110
const MONSTER_TEXTURE_LIMIT := 1024
const MONSTER_ROOT := "res://art/monsters"
## The old melee mummy stand-in (3 PBR maps, 1.8 MB) is the only exemption, for its texture bytes only; it goes when the mummy_base model of
## docs/art/monster_requests/mummy_base.md arrives. Nothing else may be added here.
const LEGACY_TEXTURE_BYTES := ["mummy/mummy.glb"]


func run(ctx) -> void:
	var library := AnimationSet.load_file(LIBRARY)
	ctx.check("the shared bow clip library loads", library != null)
	if library == null:
		return
	var names: Array = library.clip_names()
	names.sort()
	ctx.check("the library holds exactly the clips a bow monster needs %s" % [names], names == CLIPS)
	var marks: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MARKS))
	var marks_ok := marks.keys().size() == CLIPS.size()
	for clip in CLIPS:
		var entry: Dictionary = marks.get(clip, {})
		marks_ok = marks_ok and float(entry.get("length", 0.0)) > 0.0 and absf(float(entry.get("length", 0.0)) - library.length(clip)) < 0.03
		if clip in ["shoot", "volley"]:
			var windup := float(entry.get("windup_end", -1.0))
			var strike := float(entry.get("strike_end", -1.0))
			marks_ok = marks_ok and windup > 0.0 and windup < strike and strike < float(entry["length"])
	ctx.check("every clip has a length equal to its animation, and the shots a wind-up end before the strike end before the clip end", marks_ok)
	ctx.check("idle and run loop, the rest play once", library.is_looping("idle") and library.is_looping("run") and not library.is_looping("shoot") and not library.is_looping("death"))
	ctx.check("the run clip states its travel speed (rig units/s) for combat.json run_clip_speed", float(marks["run"].get("travel_per_second", 0.0)) > 0.5)

	var donor_joints := _joint_names(DONOR)
	var monster_joints := _joint_names(MONSTER)
	ctx.check("the monster keeps all 102 donor joints of the shared rig (%d)" % donor_joints.size(), donor_joints.size() == 102 and _missing(donor_joints, monster_joints).is_empty())
	ctx.check("and adds only its declared extra joints %s" % [_missing(monster_joints, donor_joints)], _sorted(_missing(monster_joints, donor_joints)) == _sorted(EXTRA_JOINTS))
	var animated := _animated_bones(LIBRARY)
	ctx.check("the monster has every joint a library clip animates %s" % [_missing(animated, monster_joints)], not animated.is_empty() and _missing(animated, monster_joints).is_empty())
	var unknown := _missing(animated, donor_joints)
	ctx.check("the library animates only donor joints %s" % [unknown], unknown.is_empty())
	var hair := animated.filter(func(bone): return str(bone).begins_with("hair_"))
	ctx.check("the player's hair tracks are not shipped to monsters (%d)" % hair.size(), hair.is_empty())

	# The donor's run clip drifts forward through the Hips; the monster library's must stay in place.
	var donor_drift := _hips_drift(DONOR, "lb_run_forward")
	var run_drift := _hips_drift(LIBRARY, "run")
	ctx.check("the check can fail: the player's own run clip drifts %.2f rig units" % donor_drift, donor_drift > 0.5)
	ctx.check("the library's run clip stays in place (drift %.3f)" % run_drift, absf(run_drift) < 0.02)
	# hips_scale: the same shared library serves legs of other lengths (monster data field, read by client/animation_set.gd)
	var hips_full: Vector3 = library.sample("idle", 0.0)["mixamorig_Hips"]["position"]
	var hips_short: Vector3 = library.sample("idle", 0.0, "", 0.75)["mixamorig_Hips"]["position"]
	ctx.check("hips_scale 0.75 lowers the Hips height of the shared library (%.3f -> %.3f)" % [hips_full.y, hips_short.y], hips_full.y > 0.1 and absf(hips_short.y / hips_full.y - 0.75) < 0.001)
	ctx.check("the default hips_scale leaves the clip untouched", library.sample("idle", 0.0, "", 1.0)["mixamorig_Hips"]["position"] == hips_full)
	ctx.check("hips_scale touches only the Hips translation, not rotations", library.sample("run", 0.3, "", 0.75)["mixamorig_Spine"]["rotation"] == library.sample("run", 0.3)["mixamorig_Spine"]["rotation"])
	var view_script = load("res://client/fighter_view.gd")
	ctx.check("a fighter view takes the monster's hips_scale (default 1.0)", "monster_hips_scale" in view_script.new() and view_script.new().monster_hips_scale == 1.0)
	var combat_text := FileAccess.get_file_as_string("res://data/combat/combat.json")
	var parsed = CombatDataLoader.parse(combat_text)
	ctx.check("combat data gives every monster a hips_scale of 1.0 unless it sets one", parsed.enemies["goblin_archer"].get("hips_scale", 0.0) == 1.0)
	var root: Dictionary = JSON.parse_string(combat_text)
	root["enemies"]["goblin_archer"]["hips_scale"] = 0.75
	ctx.check("a monster's hips_scale is read from its data", absf(float(CombatDataLoader.parse(JSON.stringify(root)).enemies["goblin_archer"]["hips_scale"]) - 0.75) < 0.0001)
	root["enemies"]["goblin_archer"]["hips_scale"] = 0.1
	ctx.check("an absurd hips_scale is reported", CombatDataLoader.parse(JSON.stringify(root)).errors.size() == 1)
	ctx.check("no short-legs variant files are shipped any more (hips_scale replaces them)", not FileAccess.file_exists("res://art/animations/monster_clips_bow_short.glb") and not FileAccess.file_exists("res://art/monsters/mummy_archer/mummy_archer_short.glb"))

	# the web pack: the texture ships as lossy WebP (not lossless 300 KB) and the model keeps no tangents/LODs/shadow meshes
	var texture_import := FileAccess.get_file_as_string(TEXTURE_IMPORT)
	ctx.check("the mummy archer texture is imported lossy (compress/mode=1) and is never switched to VRAM by the editor (detect_3d off)", texture_import.contains("compress/mode=1") and texture_import.contains("detect_3d/compress_to=0"))
	var model_import := FileAccess.get_file_as_string(MONSTER_IMPORT)
	ctx.check("the model import keeps no tangents, LODs or shadow meshes (they only add bytes to the pack)", model_import.contains("meshes/ensure_tangents=false") and model_import.contains("meshes/generate_lods=false") and model_import.contains("meshes/create_shadow_meshes=false"))

	# the mummies live in the mummy zone only: nothing of the goblin waves or goblin maps names a mummy
	var leaked := GOBLIN_DATA.filter(func(path): return FileAccess.get_file_as_string(path).to_lower().contains("mummy"))
	ctx.check("goblin waves and goblin maps never reference a mummy %s" % [leaked], leaked.is_empty())

	var library_size := FileAccess.get_file_as_bytes(LIBRARY).size()
	var monster_size := FileAccess.get_file_as_bytes(MONSTER).size()
	ctx.check("the library file is within budget (%d bytes)" % library_size, library_size <= LIBRARY_BUDGET)
	ctx.check("the monster file is within budget and lighter than the goblin archer (%d bytes)" % monster_size, monster_size <= MONSTER_BUDGET and monster_size < FileAccess.get_file_as_bytes(GOBLIN_ARCHER).size())
	var scene := (load(MONSTER) as PackedScene).instantiate()
	var triangles := 0
	var meshes := scene.find_children("*", "MeshInstance3D", true, false)
	var mesh_names := meshes.map(func(m): return str(m.name))
	for mesh in meshes:
		triangles += (mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	ctx.check("the monster is within the triangle budget (%d)" % triangles, triangles <= TRIANGLE_BUDGET)
	ctx.check("it carries a body, a bow, a string and the nocked 'arrow' the view shows during the draw %s" % [mesh_names], "Monster_MummyArcher_Body" in mesh_names and "Monster_MummyArcher_Bow" in mesh_names and "Monster_MummyArcher_BowString" in mesh_names and "arrow" in mesh_names)
	var influences_ok := true
	for mesh in meshes:
		var weights: PackedFloat32Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_WEIGHTS]
		influences_ok = influences_ok and weights.size() % 4 == 0
		for i in range(0, weights.size(), 4):
			influences_ok = influences_ok and absf(weights[i] + weights[i + 1] + weights[i + 2] + weights[i + 3] - 1.0) < 0.01
	ctx.check("every vertex has at most 4 influences, normalised", influences_ok)
	var texture_size := 0
	for mesh in meshes:
		if mesh.name == "Monster_MummyArcher_Body":
			var material := mesh.mesh.surface_get_material(0) as BaseMaterial3D
			texture_size = material.albedo_texture.get_width() if material != null and material.albedo_texture != null else 0
			ctx.check("the body is one surface with one material", mesh.mesh.get_surface_count() == 1)
	ctx.check("the albedo atlas is at most 1024 (%d)" % texture_size, texture_size > 0 and texture_size <= 1024)
	scene.free()
	_check_every_monster(ctx)


## Every monster model under art/monsters/** (found by walking the folder: a new monster is covered without editing this test),
## read from the source .glb: triangles <= 5,000, joints <= 110, ONE material on the skinned body, every texture <= 1024 px,
## the model without its embedded textures <= 450 KB and each texture <= 450 KB.
func _check_every_monster(ctx) -> void:
	var files := _glb_files(MONSTER_ROOT)
	files.sort()
	ctx.check("the monster folder holds models to check (%d)" % files.size(), files.size() >= 6)
	for path: String in files:
		var info := _glb_info(path)
		var label := path.trim_prefix(MONSTER_ROOT + "/")
		ctx.check("%s: %d triangles (hard limit %d)" % [label, info.triangles, MONSTER_TRIANGLE_LIMIT], info.triangles <= MONSTER_TRIANGLE_LIMIT)
		ctx.check("%s: %d joints (limit %d)" % [label, info.joints, MONSTER_JOINT_LIMIT], info.joints <= MONSTER_JOINT_LIMIT)
		ctx.check("%s: the skinned body has one material (%d)" % [label, info.body_materials], info.body_materials <= 1)
		ctx.check("%s: textures at most %d px (largest %d)" % [label, MONSTER_TEXTURE_LIMIT, info.max_texture], info.max_texture <= MONSTER_TEXTURE_LIMIT)
		ctx.check("%s: model without textures %d bytes (limit %d)" % [label, info.model_bytes, MONSTER_FILE_LIMIT], info.model_bytes <= MONSTER_FILE_LIMIT)
		ctx.check("%s: biggest texture %d bytes (limit %d)" % [label, info.max_texture_bytes, MONSTER_FILE_LIMIT], info.max_texture_bytes <= MONSTER_FILE_LIMIT or label in LEGACY_TEXTURE_BYTES)


static func _glb_files(dir_path: String) -> Array:
	var out := []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_glb_files(dir_path.path_join(sub)))
	for file in dir.get_files():
		if file.ends_with(".glb"):
			out.append(dir_path.path_join(file))
	return out


## Facts of a source .glb, from its JSON chunk (no import needed): triangles, joints of the biggest skin, materials of the skinned meshes,
## texture sizes (embedded images and the loose image files next to it) and the model's own bytes without the embedded images.
static func _glb_info(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	var json_length := bytes.decode_u32(12)
	var gltf: Dictionary = JSON.parse_string(bytes.slice(20, 20 + json_length).get_string_from_utf8())
	var info := {"triangles": 0, "joints": 0, "body_materials": 0, "max_texture": 0, "max_texture_bytes": 0, "model_bytes": bytes.size()}
	var accessors: Array = gltf.get("accessors", [])
	var body_triangles := 0  # the skinned mesh with the most triangles is the body; its primitives must share one material
	for mesh in gltf.get("meshes", []):
		var materials := {}
		var mesh_triangles := 0
		var skinned := false
		for primitive in mesh["primitives"]:
			var count := int(accessors[int(primitive["indices"])]["count"]) / 3 if primitive.has("indices") else int(accessors[int(primitive["attributes"]["POSITION"])]["count"]) / 3
			info.triangles += count
			mesh_triangles += count
			skinned = skinned or primitive["attributes"].has("JOINTS_0")
			materials[int(primitive.get("material", -1))] = true
		if skinned and mesh_triangles > body_triangles:
			body_triangles = mesh_triangles
			info.body_materials = materials.size()
	for skin in gltf.get("skins", []):
		info.joints = maxi(info.joints, (skin["joints"] as Array).size())
	var views: Array = gltf.get("bufferViews", [])
	for image in gltf.get("images", []):
		if image.has("bufferView"):
			var size := int(views[int(image["bufferView"])]["byteLength"])
			info.model_bytes -= size
			info.max_texture_bytes = maxi(info.max_texture_bytes, size)
			var picture := Image.new()
			var start := int(views[int(image["bufferView"])].get("byteOffset", 0))
			var data := bytes.slice(20 + json_length + 8 + start, 20 + json_length + 8 + start + size)
			var loaded := picture.load_jpg_from_buffer(data) if str(image.get("mimeType", "")) == "image/jpeg" else picture.load_png_from_buffer(data)
			if loaded == OK:
				info.max_texture = maxi(info.max_texture, maxi(picture.get_width(), picture.get_height()))
	var folder := path.get_base_dir()
	for file in DirAccess.get_files_at(folder):
		if file.get_extension() in ["jpg", "jpeg", "png", "webp"] and file.begins_with(path.get_file().get_basename()):
			var loose := Image.load_from_file(folder.path_join(file))
			if loose != null:
				info.max_texture = maxi(info.max_texture, maxi(loose.get_width(), loose.get_height()))
			info.max_texture_bytes = maxi(info.max_texture_bytes, FileAccess.get_file_as_bytes(folder.path_join(file)).size())
	return info


func _joint_names(path: String) -> Array:
	var scene := (load(path) as PackedScene).instantiate()
	var skeleton := scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var out := []
	for i in skeleton.get_bone_count():
		out.append(skeleton.get_bone_name(i))
	scene.free()
	return out


static func _sorted(values: Array) -> Array:
	var copy := values.duplicate()
	copy.sort()
	return copy


static func _missing(wanted: Array, have: Array) -> Array:
	return wanted.filter(func(name): return not have.has(name))


func _animated_bones(path: String) -> Array:
	var scene := (load(path) as PackedScene).instantiate()
	var player := scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var bones := {}
	for clip in player.get_animation_list():
		var animation := player.get_animation(clip)
		for t in animation.get_track_count():
			bones[String(animation.track_get_path(t).get_concatenated_subnames())] = true
	scene.free()
	return bones.keys().filter(func(bone): return bone != "" and not EXTRA_JOINTS.has(bone))


func _hips_track(animation: Animation) -> int:
	for t in animation.get_track_count():
		if animation.track_get_type(t) == Animation.TYPE_POSITION_3D:
			return t
	return -1


func _hips_drift(path: String, clip: String) -> float:
	var scene := (load(path) as PackedScene).instantiate()
	var animation := (scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer).get_animation(clip)
	var track := _hips_track(animation)
	var drift := 0.0
	if track >= 0:
		drift = (animation.track_get_key_value(track, animation.track_get_key_count(track) - 1) as Vector3).z - (animation.track_get_key_value(track, 0) as Vector3).z
	scene.free()
	return drift


func _hips_y(path: String, clip: String) -> float:
	var scene := (load(path) as PackedScene).instantiate()
	var animation := (scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer).get_animation(clip)
	var y: float = (animation.track_get_key_value(_hips_track(animation), 0) as Vector3).y
	scene.free()
	return y
