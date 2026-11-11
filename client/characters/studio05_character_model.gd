extends "res://client/character_model.gd"
## Production player (Boss goal 2026-11-10): the test05/studio "Sword & Shield" toon character,
## five hair styles (A-E) and the Silver Silk outfit, each its own GLB with the Mixamo rig (102 joints,
## 6x3 hair chain) and 47 authored clips. The source rig, weights and clips are used as they are; the
## game only adds two weapon socket bones under the hands. Looks follow test05/studio/STUDIO_SPEC.md:
## fixed-key cel bands, procedural anime eyes/makeup/face ink and the face/hair ink hulls.
## Combat poses are mapped onto the source clips (data/classes/<id>.json); clips are sampled at times driven by
## the simulation, the hips stay in place (the game moves the body).

const ItemAssets := preload("res://client/item_assets.gd")
const ToonShader := preload("res://client/characters/studio05_toon.gdshader")
const InkShader := preload("res://client/characters/studio05_ink.gdshader")
const FOLDER := "res://art/characters/studio05/"
const HAIR_STYLES: Array[String] = ["a", "b", "c", "e", "f"]  ## (hair D was retired in the Studio)
const HEIGHT := 1.35  ## Boss: characters at most 135cm
const HIPS := "mixamorig_Hips"
const DEFAULT_HAIR := Color("6f657f")
const DEFAULT_IRIS := Color("c98634")
const SKIN_LINEAR := Color(0.72, 0.56, 0.48)
const CLASS_FOLDER := "res://data/classes/"
const DEFAULT_CLASS := "sword_shield"
static var _classes: Dictionary = {}


## The class file (data/classes/<id>.json): its animation clips, how our moves and states map onto them.
static func class_data(id: String) -> Dictionary:
	if not _classes.has(id):
		var path := CLASS_FOLDER + id + ".json"
		_classes[id] = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
	return _classes[id]


## Travel: the game body surges forward by a move's "advance" (data/combat/weapons.json templates) while the
## model plays in place (hips x/z locked), so a clip that carries the hips must be paired with an advance of the
## same distance or the feet slide: advance = metres * 60 * (1 - Movement.KNOCKBACK_FRICTION) = metres * 7.2,
## metres = the hips' forward travel (z, times the 2.577 body scale) from the clip's windup_end to its "finish"
## in clips.json. Measured: slash 0.08, slash_3 -0.11, slash_5/slash_4 0.11, slash_2 0.77 (run_light, special),
## attack_3 0.90 (run_heavy, charge), attack_2 0.69 (ultimate: its dash comes from the skill pack). Re-measure
## after changing a class file (data/classes) or the clip windows. (The jump attack keeps a 4.0 advance: a rule of the game, see
## tests/test_combat.gd, even though its clip travels only 0.11 m.)
## Where the weapon sits in the fist (GLB units, in the hand bone: +Y runs along the fingers).
const SOCKET_OFFSET := Vector3(0.0, 0.032, 0.006)
## Turn of the game's weapons (blade along +Y in the model team's files) inside the hand socket.
var weapon_grip_degrees := Vector3(0.0, 0.0, -90.0)

var _library: RefCounted
var _variant := ""
var _hair_color := DEFAULT_HAIR
var _iris := DEFAULT_IRIS
var _skin := SKIN_LINEAR
var _makeup := 0
var _toon: Array[ShaderMaterial] = []
var _flash := Color(0, 0, 0, 0)
var _relic_orbit: Node3D
var _weapon_args := ["", ""]
var _shield: Node3D
var class_id := DEFAULT_CLASS  ## which data/classes/<id>.json drives the animations
## Simple stand-in shield on the left hand (GLB units, in the left hand bone): radius, thickness.
const SHIELD_RADIUS := 0.11
const SHIELD_THICKNESS := 0.012
const SHIELD_OFFSET := Vector3(0.0, 0.0, 0.0)
var shield_turn_degrees := Vector3(0.0, 0.0, 90.0)


static func variant_path(hair: String, silver: bool) -> String:
	return FOLDER + "our_character_lowpoly_toon_hair_" + hair + "_5k" + ("_silver" if silver else "") + ".glb"


## The A-E hair file for a cosmetic hair id: stable per id so remote players see the same.
static func hair_for(hair_id: String) -> String:
	if hair_id.length() == 1 and hair_id in HAIR_STYLES:
		return hair_id
	if hair_id.is_empty() or hair_id == "mens_short":
		return "a"
	return HAIR_STYLES[absi(hash(hair_id)) % HAIR_STYLES.size()]


## `path` is ignored unless it is one of the test05 files: every caller asks for "the player".
func load_model(path: String = "") -> bool:
	if not path.begins_with(FOLDER):
		path = variant_path("a", false)
	return _load_variant(path)


func _load_variant(path: String) -> bool:
	if path == _variant and _model_root != null:
		return true
	if not ResourceLoader.exists(path):
		return false
	var packed := load(path) as PackedScene
	if packed == null:
		return false
	if _turn == null:
		_turn = Node3D.new()
		_turn.rotation_degrees.y = 90.0
		add_child(_turn)
		_lie = Node3D.new()
		_turn.add_child(_lie)
	var weapon := _weapon_args.duplicate()
	if _model_root != null:
		_show_weapon("", "")
		_model_root.queue_free()
		_lie.remove_child(_model_root)
	_meshes.clear()
	_body_meshes.clear()
	_hair_meshes.clear()
	_bone_index.clear()
	_rest.clear()
	_global_rest.clear()
	_rest_position.clear()
	_toon.clear()
	_variant = path
	_anim_model = ""
	_model_root = packed.instantiate()
	_lie.add_child(_model_root)
	_skeleton = _find_skeleton(_model_root)
	_find_meshes(_model_root, _meshes)
	if _skeleton == null or _meshes.is_empty():
		push_warning("studio05 model has no skeleton or mesh")
		return false
	for player in _model_root.find_children("*", "AnimationPlayer", true, false):
		player.stop()  # the game samples the clips itself
	for side in ["Right", "Left"]:
		var bone := WEAPON_BONE if side == "Right" else WEAPON_BONE_LEFT
		if _skeleton.find_bone(bone) < 0:
			var index := _skeleton.add_bone(bone)
			_skeleton.set_bone_parent(index, _skeleton.find_bone("mixamorig_" + side + "Hand"))
			var offset := SOCKET_OFFSET * Vector3(-1.0 if side == "Left" else 1.0, 1.0, 1.0)
			_skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, offset))
			_skeleton.reset_bone_pose(index)
	for index in _skeleton.get_bone_count():
		var bone_name := _skeleton.get_bone_name(index)
		_bone_index[bone_name] = index
		_rest[bone_name] = _skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
		_global_rest[bone_name] = _skeleton.get_bone_global_rest(index).basis.get_rotation_quaternion()
		_rest_position[bone_name] = _skeleton.get_bone_rest(index).origin
	for mesh in _meshes:
		if str(mesh.name).begins_with("Hair_"):
			_hair_meshes.append(mesh)
	_body_meshes = _meshes.duplicate()
	var spec := class_data(class_id)
	_library = AnimationSet.load_file(str(spec.get("animations", "")), str(spec.get("clip_marks", "")))
	if _library == null:
		return false
	var bounds := _union_bounds()
	var factor := HEIGHT / bounds.size.y
	_model_root.scale = Vector3.ONE * factor
	_model_root.position.y = -bounds.position.y * factor
	_prepare_meshes()
	_apply_colors()
	_shield = null
	_build_shield()
	if not str(weapon[0]).is_empty():
		_show_weapon(weapon[0], weapon[1])
	return true


## A plain round shield (steel face, gold rim, boss in the middle) held on the left hand's socket.
func _build_shield() -> void:
	var attachment := BoneAttachment3D.new()
	attachment.name = "ShieldAttachment"
	attachment.bone_name = WEAPON_BONE_LEFT
	_skeleton.add_child(attachment)
	_shield = Node3D.new()
	_shield.quaternion = Quaternion.from_euler(shield_turn_degrees * PI / 180.0)
	_shield.position = SHIELD_OFFSET
	attachment.add_child(_shield)
	var parts := [
		[SHIELD_RADIUS, SHIELD_THICKNESS, 0.0, Color("5d6f8a")],
		[SHIELD_RADIUS * 1.08, SHIELD_THICKNESS * 0.7, 0.0, Color("c9a23a")],
		[SHIELD_RADIUS * 0.28, SHIELD_THICKNESS * 1.8, SHIELD_THICKNESS * 0.4, Color("c9a23a")],
	]
	for part in parts:
		var mesh := CylinderMesh.new()
		mesh.top_radius = part[0]
		mesh.bottom_radius = part[0]
		mesh.height = part[1]
		mesh.radial_segments = 20
		mesh.rings = 1
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.position = Vector3(0.0, part[2], 0.0)
		var material := ShaderMaterial.new()
		material.shader = ToonShader
		var c: Color = (part[3] as Color).srgb_to_linear()
		material.set_shader_parameter("base_color_linear", Vector3(c.r, c.g, c.b))
		instance.material_override = material
		instance.layers |= 1 << (CharacterLight.LAYER - 1)
		_shield.add_child(instance)
	_shield.visible = false
	_update_shield()


func _update_shield() -> void:
	if _shield != null:
		_shield.visible = not str(_weapon_args[0]).is_empty() and str(class_data(class_id).get("off_hand", "round_shield")) == "round_shield"


func _union_bounds() -> AABB:
	var bounds := AABB()
	var first := true
	for mesh in _meshes:
		if not is_instance_valid(mesh) or not mesh.visible or str(mesh.name).ends_with("_StudioInk"):
			continue
		var current: AABB = mesh.transform * mesh.mesh.get_aabb()
		bounds = current if first else bounds.merge(current)
		first = false
	return bounds


## Bind-pose position copied into UV/UV2: the face artwork and hair strokes stay on the skin while it moves.
static func _with_rest_coordinates(source: Mesh) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uv := PackedVector2Array()
		var uv2 := PackedVector2Array()
		uv.resize(positions.size())
		uv2.resize(positions.size())
		for i in positions.size():
			uv[i] = Vector2(positions[i].x, positions[i].y)
			uv2[i] = Vector2(positions[i].z, 0.0)
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		var flags := 0
		var bones = arrays[Mesh.ARRAY_BONES]
		if bones != null and positions.size() > 0 and bones.size() == positions.size() * 8:
			flags = Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		mesh.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays, [], {}, flags)
		mesh.surface_set_material(surface, source.surface_get_material(surface))
	return mesh


func _prepare_meshes() -> void:
	for mesh in _body_meshes.duplicate():
		if mesh.has_meta("studio05"):
			continue
		mesh.set_meta("studio05", true)
		var label := str(mesh.name)
		var part := 1 if label.begins_with("Head_Anime") else (2 if label.begins_with("Hair_") else 0)
		if part != 0:
			mesh.mesh = _with_rest_coordinates(mesh.mesh)
		for surface in mesh.mesh.get_surface_count():
			var original := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			var material := ShaderMaterial.new()
			material.shader = ToonShader
			material.resource_name = original.resource_name if original != null else label
			material.set_shader_parameter("part", part)
			material.set_shader_parameter("has_rest", part != 0)
			var color := original.albedo_color if original != null else Color.WHITE
			material.set_meta("file_color", color)
			material.set_shader_parameter("base_color_linear", Vector3(color.r, color.g, color.b))
			if part == 2:
				material.set_shader_parameter("hair_part", 0.009 if label.begins_with("Hair_A") else -0.003)
				material.set_shader_parameter("painted_bangs", 0.0 if label.substr(5, 1) in ["C", "D", "E"] else 1.0)
			mesh.set_surface_override_material(surface, material)
			_toon.append(material)
		if part != 0:
			var hull := MeshInstance3D.new()
			hull.name = label + "_StudioInk"
			hull.mesh = mesh.mesh
			hull.skin = mesh.skin
			mesh.add_child(hull)
			hull.skeleton = hull.get_path_to(_skeleton)
			var ink := ShaderMaterial.new()
			ink.shader = InkShader
			ink.set_shader_parameter("grow", 0.0019 if part == 2 else 0.0014)
			ink.set_shader_parameter("is_hair", part == 2)
			ink.set_shader_parameter("has_rest", true)
			hull.material_override = ink
			hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			hull.set_meta("studio05_ink", part)
	CharacterLight.prepare(_model_root)


func _apply_colors() -> void:
	var hair := _hair_color.srgb_to_linear()
	var iris := _iris.srgb_to_linear()
	for material in _toon:
		var label := material.resource_name.to_lower()
		var part := int(material.get_shader_parameter("part"))
		if part == 2:
			material.set_shader_parameter("base_color_linear", Vector3(hair.r, hair.g, hair.b))
		elif label.contains("skin"):
			material.set_shader_parameter("base_color_linear", Vector3(_skin.r, _skin.g, _skin.b))
		if part == 1:
			material.set_shader_parameter("iris_tint", Vector3(iris.r, iris.g, iris.b))
			material.set_shader_parameter("makeup_style", _makeup)
		material.set_shader_parameter("flash", Vector4(_flash.r, _flash.g, _flash.b, _flash.a))
	for mesh in _hair_meshes:
		for hull in mesh.get_children():
			if hull is MeshInstance3D and hull.material_override is ShaderMaterial:
				hull.material_override.set_shader_parameter("base_color_linear", Vector3(hair.r, hair.g, hair.b))


## Fashion: an active outfit shows the Silver Silk file; the hair choice picks the A-E file.
## Combat armor of the old rig cannot fit this body, so equipment stays stats-only (not shown).
## Switches the class (data/classes/<id>.json): its animation library, what the hands hold and the shield.
func set_class(id: String) -> void:
	if id == class_id and _library != null:
		return
	var spec := class_data(id)
	if spec.is_empty():
		return
	class_id = id
	_library = AnimationSet.load_file(str(spec.get("animations", "")), str(spec.get("clip_marks", "")))
	_skill_clip = {}
	_update_shield()
	_fit_weapon()


func _fit_weapon() -> void:
	var spec := class_data(class_id)
	var shown := bool(spec.get("weapon_visible", true))
	var scale_by := float(spec.get("weapon_scale", 1.0)) / maxf(model_scale(), 0.0001)
	for node in [_weapon_node, _weapon_left]:
		if node != null:
			node.visible = shown
			node.scale = Vector3.ONE * scale_by


func set_appearance(appearance: Dictionary) -> void:
	var choices: Dictionary = appearance.get("choices", {})
	var outfit := str(choices.get("fashion", "none"))
	var silver := outfit != "none" and str(choices.get("fashion_display", "on")) == "on"
	var hair := hair_for(str(choices.get("hair_style", "")))
	if appearance.has("studio_hair"):  # the squad's own look (GameState.squad_loadout) wins
		hair = str(appearance["studio_hair"])
		silver = bool(appearance.get("studio_silver", silver))
	if appearance.has("hair") and not bool(appearance.get("hair_natural", true)):
		_hair_color = appearance["hair"]
	else:
		_hair_color = DEFAULT_HAIR
	if appearance.has("eye_color") and str(appearance.get("eye_color_id", "")) not in ["", "original", "default"]:
		_iris = appearance["eye_color"]
	else:
		_iris = DEFAULT_IRIS
	if appearance.has("skin") and str(choices.get("skin", "default")) not in ["default", ""]:
		_skin = (appearance["skin"] as Color).srgb_to_linear()
	else:
		_skin = SKIN_LINEAR
	_makeup = 1 if str(choices.get("makeup", "")) == "sharp_wing" else 0
	_load_variant(variant_path(hair, silver))
	_apply_colors()


func dress(looks: Dictionary) -> void:
	if looks.has("relics"):
		set_relics(looks.relics)
	if _skeleton == null:
		return
	if looks.has("class"):
		set_class(str(looks["class"]))
	if looks.has("appearance"):
		set_appearance(looks["appearance"])
	if looks.has("weapon"):
		var weapon: Dictionary = looks["weapon"]
		if not str(weapon.get("path", "")).is_empty():
			_show_weapon(weapon["path"], str(weapon.get("family", "")))
		else:
			set_weapon(str(weapon.get("style", "")))
	_apply_equipment_refine(looks.get("refine", {}))


func set_relics(ids: Array) -> void:
	if _relic_orbit == null:
		if ids.is_empty():
			return
		_relic_orbit = preload("res://client/relic_orbit.gd").new()
		add_child(_relic_orbit)
	_relic_orbit.configure(ids)


func set_blink_mode(_mode: String) -> void:
	pass  # the source Studio has no blink


func is_hair_shown() -> bool:
	return not _hair_meshes.is_empty()


func tint(color: Color) -> void:
	_flash = color if color.a > 0.0 else Color(0, 0, 0, 0)
	for material in _toon:
		material.set_shader_parameter("flash", Vector4(_flash.r, _flash.g, _flash.b, _flash.a))


func _show_weapon(path: String, family: String) -> void:
	_weapon_args = [path, family]
	super._show_weapon(path, family)
	_update_shield()
	var grip := Quaternion.from_euler(weapon_grip_degrees * PI / 180.0)
	_grip_ours = grip
	_grip_own = grip
	for node in [_weapon_node, _weapon_left]:
		if node != null:
			node.quaternion = grip
	_fit_weapon()  # (the weapons are authored in meters for a 1.35m body: counter the model scale; class scale on top)


## Ultimates/skills authored for the old rig play the source's sweeping spin slash (attack_2) instead.
func show_skill_clip(_set: RefCounted, clip: String, time: float) -> void:
	if _library == null or clip.is_empty():
		return
	var wanted := str(class_data(class_id).get("moves", {}).get("ultimate", "attack_2"))
	_skill_clip = {"set": _library, "clip": wanted, "time": minf(time, _library.length(wanted))}


func _clip_time(clip: String, phase: String, amount: float) -> float:
	var meta: Dictionary = _library._clips[clip]["meta"]
	var begin := float(meta.get("begin", 0.0))
	var windup_end := float(meta.get("windup_end", _library.length(clip) * 0.3))
	var strike_end := float(meta.get("strike_end", _library.length(clip) * 0.5))
	var finish := float(meta.get("finish", _library.length(clip)))
	amount = clampf(amount, 0.0, 1.0)
	match phase:
		"windup":
			return lerpf(begin, windup_end, amount)
		"strike":
			return lerpf(windup_end, strike_end, amount)
	return lerpf(strike_end, finish, amount)


func _active_clip() -> Dictionary:
	if _library == null:
		return {}
	if not _skill_clip.is_empty():
		return _skill_clip
	var spec := class_data(class_id)
	var moves: Dictionary = spec.get("moves", {})
	var states: Dictionary = spec.get("states", {})
	var kind := str(_pose["kind"])
	var clip: String = str(states.get("idle", "idle"))
	var time := _clock
	var amount := float(_pose["amount"])
	if bool(_pose["lying"]):
		time = 0.0
	elif not str(_pose["clip"]).is_empty() and not str(_pose["phase"]).is_empty():
		clip = str(moves.get(str(_pose["clip"]), moves.get("kick", clip) if kind in ["kick", "flying_kick"] else moves.get("light_1", clip)))
		return {"set": _library, "clip": clip, "time": _clip_time(clip, str(_pose["phase"]), amount)}
	elif kind in ["run", "walk"] and bool(_pose["grounded"]):
		clip = str(states.get("run", "run"))
		time = _clock * clampf(float(_pose["speed"]), 0.6, 1.4) * 1.1
	elif kind == "guard":
		clip = str(states.get("guard", clip))
	elif kind == "slide":
		clip = str(states.get("slide", clip))
		time = clampf(amount, 0.0, 1.0) * _library.length(clip)
	elif kind in ["hurt", "launched"]:
		clip = str(states.get(kind, clip))
		time = clampf(amount, 0.0, 1.0) * _library.length(clip)
	elif not bool(_pose["grounded"]):
		clip = str(states.get("air", clip))
		time = clampf(amount, 0.0, 1.0) * _library.length(clip)
	return {"set": _library, "clip": clip, "time": time}


func _apply_clip(active: Dictionary) -> void:
	var sample: Dictionary = active["set"].sample(active["clip"], active["time"])
	for bone_name in _bone_index:
		var values: Dictionary = sample.get(bone_name, {})
		_move_bone_to(bone_name, values.get("rotation", _rest[bone_name]))
		if values.has("position"):
			var index: int = _bone_index[bone_name]
			var target: Vector3 = values["position"]
			if bone_name == HIPS:  # in place: the game moves the body, keep the bounce
				target.x = _rest_position[HIPS].x
				target.z = _rest_position[HIPS].z
			_skeleton.set_bone_pose_position(index, _skeleton.get_bone_pose_position(index).lerp(target, _follow))
