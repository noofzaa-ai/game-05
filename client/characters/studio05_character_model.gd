extends "res://client/character_model.gd"
## Production player (Boss goal 2026-11-10): the studio05 toon character on its own Mixamo rig (102 joints,
## 6x3 hair chain). Source of truth: the Studio drop of 2026-11-11 (docs/tech/studio_v20261111_inventory.md).
## Per class one base body file is loaded once (split/body_<class>.glb: body, face, rig, the class clips, no hair)
## and the chosen hair (split/hair_<x>.glb, or the Studio's hair/hair_g.glb) is merged onto its skeleton like
## class-gear.js replaceCharacterHair() (Boss 2026-11-13; files made by tools/characters/split_studio05_hair.py
## from the Studio's whole-character files, bytes unchanged). The class gear
## (outfits/armor_<class>.glb, same 102 joints and rest) is merged onto that skeleton like class-gear.js:
## "outfit" = every gear mesh and the base body hidden, "weapons" = only "| Sword/Shield/Bow/Quiver/Staff/
## Spellbook" pieces (Silver Silk = split/outfit_silver_silk.glb over the body plus the class weapons). The source rig, weights,
## blend shapes and clips are used as they are; the game only adds two weapon socket bones under the hands.
## Looks follow STUDIO_SPEC.md: fixed-key cel bands, procedural anime eyes (iris presets, makeup, blink),
## face/hair ink and the ink hulls.
## Combat poses are mapped onto the source clips (data/classes/<id>.json); clips are sampled at times driven by
## the simulation, the hips stay in place (the game moves the body).

const ItemAssets := preload("res://client/item_assets.gd")
const ToonShader := preload("res://client/characters/studio05_toon.gdshader")
const InkShader := preload("res://client/characters/studio05_ink.gdshader")
const RefineEffect := preload("res://client/refine_equipment.gd")
const FOLDER := "res://art/characters/studio05/"
const V1111 := "res://art/characters/studio05/v1111/"
## Written by tools/characters/split_studio05_hair.py: class -> body file, class -> hair letter -> hair file, silver.
const SPLIT_MANIFEST := "res://art/characters/studio05/split/manifest.json"
const HAIR_STYLES: Array[String] = ["a", "b", "c", "e", "f", "g"]  ## Studio hair buttons (hair D was retired; G is new)
const HEIGHT := 1.35  ## Boss: characters at most 135cm
const HIPS := "mixamorig_Hips"
const DEFAULT_HAIR := Color("6f657f")  ## index.html #hair-color default (hairs A, B)
const LIGHT_HAIR := Color("ffffff")  ## index.html: hairs C-G default to white (their colour is in the file)
const DEFAULT_IRIS := Color("c98634")
const SKIN_LINEAR := Color(0.72, 0.56, 0.48)
const CLASS_FOLDER := "res://data/classes/"
const DEFAULT_CLASS := "sword_shield"
## index.html characterClasses: the class's body file prefix and gear file.
const CLASS_FILES := {
	"sword_shield": {"model": "lowpoly_toon", "gear": "armor_sword_shield"},
	"greatsword": {"model": "greatsword", "gear": "armor_greatsword"},
	"longbow": {"model": "longbow", "gear": "armor_longbow"},
	"magic": {"model": "magic", "gear": "armor_magic"},
}
## class-gear.js 'weapons' mode: the gear pieces kept over the Silver Silk outfit.
const WEAPON_PIECE := "\\| (?:Sword|Shield|Bow|Quiver|Staff|Spellbook)\\b"
## index.html iris menu: value -> default colour (data-color); 0 Classic uses the eye colour input.
const IRIS_STYLES := {0: "", 1: "a352df", 3: "ff562c", 6: "a577db", 7: "f75c3e", 9: "b960db", 10: "9b69e7"}
## eyes/blink.js timings (seconds).
const BLINK_CLOSE := 0.080
const BLINK_HOLD := 0.035
const BLINK_OPEN := 0.145
const BLINK_FIRST := 1.6
const BLINK_GAP_MIN := 2.8
const BLINK_GAP_SPAN := 2.8
const BLINK_DOUBLE_CHANCE := 0.16
const BLINK_DOUBLE_GAP := 0.18
## Cape morph targets of armor_sword_shield (B 00 | Armor suit). The source drives them from a gear clip
## that class-gear.js only keeps when the body has a clip of the same name (index.html: the sword & shield
## run/idle). Its weight tracks are copied from the gear file by clip name.
const CAPE_SHAPES: Array[String] = ["Cape Trail", "Cape Ripple Sine", "Cape Ripple Cosine"]
static var _classes: Dictionary = {}
static var _cape_tracks: Dictionary = {}  ## gear path -> {clip: {shape: Animation track}} (+ "_animation" refs)
static var _weapon_regex: RegEx
static var _split: Dictionary = {}


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
var _custom_hair := false
var _iris := DEFAULT_IRIS
var _iris_style := 0
var _skin := SKIN_LINEAR
var _makeup := 0
var _toon: Array[ShaderMaterial] = []
var _flash := Color(0, 0, 0, 0)
var _relic_orbit: Node3D
var _weapon_args := ["", ""]
var _shield: Node3D
var _hair_letter := "a"
var _silver := false
var _gear_meshes: Array[MeshInstance3D] = []  ## merged class gear (armor_<class>.glb)
var _gear_weapons: Array[MeshInstance3D] = []  ## ... its weapon pieces (shown in both modes)
var _gear_shield: Array[MeshInstance3D] = []  ## ... its shield piece (sword & shield)
var _offhand := {}  ## ItemAssets.looks()["offhand"]: the equipped shield, {} = class default
var _cape_mesh: MeshInstance3D
var _blink := 0.0
var _blink_clock := 0.0
var _blink_start := BLINK_FIRST
var _blink_rng := RandomNumberGenerator.new()
var blink_enabled := true  ## eyes/blink.js: off = eyes held open
var class_id := DEFAULT_CLASS  ## which data/classes/<id>.json drives the animations
## Simple stand-in shield on the left hand (GLB units, in the left hand bone): radius, thickness.
const SHIELD_RADIUS := 0.11
const SHIELD_THICKNESS := 0.012
const SHIELD_OFFSET := Vector3(0.0, 0.0, 0.0)
var shield_turn_degrees := Vector3(0.0, 0.0, 90.0)
var _offhand_node: Node3D  ## an equipped shield that has its own model file (left hand socket)
var _offhand_path := ""
var _weapon_shown := true
## Idle variant (card portraits): the clip shown in place of the class idle while the pose is a plain idle,
## "" = the class idle. The previous one fades out over the blend (play_idle_clip).
var _idle_clip := ""
var _idle_start := 0.0  ## _clock when _idle_clip started
var _idle_from := ""  ## clip faded out ("" = nothing to fade)
var _idle_from_start := 0.0
var _idle_blend := 0.0  ## seconds of the crossfade
var _retired: Array = []  ## the previous look's meshes and materials, kept one switch longer (_load_variant)
## Equipped armour on the Studio rig (race gear, docs/art/race_gear_handoff.md): slot -> file wanted by dress().
## Worn like class-gear.js 'weapons' mode: the base body shows, the class suit hides, its weapons stay.
var _armor_wanted: Dictionary = {}
var _race_weapon_wanted := ""  ## a race weapon file on the Studio rig ("" = the class gear's weapon)
var _race_weapon_meshes: Array[MeshInstance3D] = []
var _class_weapons: Array[MeshInstance3D] = []  ## the class gear's own weapon / shield pieces (hidden under a race weapon)
var _class_shield: Array[MeshInstance3D] = []
var _race_shield_wanted := ""  ## an equipped race shield on the Studio rig (off-hand item file), "" = none
var _race_shield_meshes: Array[MeshInstance3D] = []
var _weapon_file_shield: Array[MeshInstance3D] = []  ## "| Shield" pieces inside a race weapon file
var _body_full: Mesh  ## Base_Body as loaded (the masked copies below are made from it)
## The body skin a worn race piece covers, by the bone that moves a triangle most (all three corners): those
## triangles are left out, so skin cannot poke through the cloth (the Studio hides the whole Base_Body under an
## outfit; the race shirts carry their own skin forearms). A forearm needs shirt and armband (a short sleeve with
## no glove shows the arm). Neck and head always stay. Engine-side fitting: OPEN until accepted (parity doc).
const BODY_COVER := {
	"shirt": ["Spine", "Spine1", "Spine2", "LeftShoulder", "RightShoulder", "LeftArm", "RightArm"],
	"shirt+armband": ["LeftForeArm", "RightForeArm"],
	"armband": ["LeftHand", "RightHand", "HandIndex", "HandMiddle", "HandPinky", "HandRing", "HandThumb"],
	"pants": ["Hips", "LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg"],
	"shoes": ["LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase", "LeftToe_End", "RightToe_End"],
}
static var _masked_bodies: Dictionary = {}  ## covered-slot key -> ArrayMesh


static func _split_files() -> Dictionary:
	if _split.is_empty() and FileAccess.file_exists(SPLIT_MANIFEST):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SPLIT_MANIFEST))
		_split = parsed if parsed is Dictionary else {}
	return _split


static func _known_class(class_name_id: String) -> String:
	return class_name_id if CLASS_FILES.has(class_name_id) else DEFAULT_CLASS


## The class's base body (body, face, rig and the class clips; no hair), loaded once per class. The Studio's
## per-hair body files carry the same body, rig and clips (byte-identical, except hair F's export-rate slip:
## see tools/characters/split_studio05_hair.py).
static func body_path(class_name_id: String, _hair: String = "") -> String:
	return str(_split_files().get("bodies", {}).get(_known_class(class_name_id), ""))


## The hair-only file merged onto the body (index.html hair buttons A, B, C, E, F, G; G = hair/hair_g.glb).
static func hair_path(class_name_id: String, hair: String) -> String:
	var table: Dictionary = _split_files().get("hair", {}).get(_known_class(class_name_id), {})
	return str(table.get(hair, table.get("a", "")))


static func gear_path(class_name_id: String) -> String:
	return V1111 + "outfits/" + str(CLASS_FILES.get(class_name_id, CLASS_FILES[DEFAULT_CLASS])["gear"]) + ".glb"


## The Silver Silk outfit (Outfit_SilverSilk only; the same mesh as in every Studio *_silver file).
static func silver_path() -> String:
	return str(_split_files().get("silver", ""))


## The hair letter for a cosmetic hair id: stable per id so remote players see the same.
static func hair_for(hair_id: String) -> String:
	if hair_id.length() == 1 and hair_id in HAIR_STYLES:
		return hair_id
	if hair_id.is_empty() or hair_id == "mens_short":
		return "a"
	return HAIR_STYLES[absi(hash(hair_id)) % HAIR_STYLES.size()]


static func is_weapon_piece(mesh_name: String) -> bool:
	if _weapon_regex == null:
		_weapon_regex = RegEx.create_from_string(WEAPON_PIECE)
	return _weapon_regex.search(mesh_name) != null


## `path` is ignored: every caller asks for "the player" (class, hair and outfit come from dress()).
func load_model(_path: String = "") -> bool:
	return _load_variant(class_id, _hair_letter, _silver)


func _load_variant(cls: String, hair: String, silver: bool) -> bool:
	var key := "%s|%s|%s" % [cls, hair, silver]
	if key == _variant and _model_root != null:
		return true
	var path := body_path(cls, hair)
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
		# The renderer may still hold an update for the old meshes this frame: keep their materials and meshes
		# referenced until the next switch, else it reads a freed material ("Parameter material is null").
		_retired.clear()
		for node in _model_root.find_children("*", "MeshInstance3D", true, false):
			var instance := node as MeshInstance3D
			_retired.append(instance.mesh)
			_retired.append(instance.material_override)
			for surface in instance.get_surface_override_material_count():
				_retired.append(instance.get_surface_override_material(surface))
		_lie.remove_child(_model_root)
		_model_root.queue_free()
	_meshes.clear()
	_body_meshes.clear()
	_hair_meshes.clear()
	_gear_meshes.clear()
	_gear_weapons.clear()
	_gear_shield.clear()
	_worn.clear()
	_race_weapon_meshes.clear()
	_race_shield_meshes.clear()
	_weapon_file_shield.clear()
	_class_weapons.clear()
	_class_shield.clear()
	_cape_mesh = null
	_bone_index.clear()
	_rest.clear()
	_global_rest.clear()
	_rest_position.clear()
	_toon.clear()
	_offhand_node = null
	_offhand_path = ""
	_variant = key
	class_id = cls
	_hair_letter = hair
	_silver = silver
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
	# replaceCharacterHair(): the chosen hair's mesh joins the body's skeleton (before sizing, as in the old
	# whole-character files whose bounds included the hair).
	_meshes.append_array(_merge(hair_path(cls, hair), func(n: String) -> bool: return n.begins_with("Hair_")))
	for mesh in _meshes:
		if str(mesh.name).begins_with("Hair_"):
			_hair_meshes.append(mesh)
	# The body's size is set before the gear goes on (a hood or a staff must not change the character's size).
	var bounds := _union_bounds()
	var factor := HEIGHT / bounds.size.y
	_model_root.scale = Vector3.ONE * factor
	_model_root.position.y = -bounds.position.y * factor
	_body_meshes = _meshes.duplicate()
	_body_full = null
	for mesh in _body_meshes:
		if str(mesh.name) == "Base_Body":
			_body_full = mesh.mesh
	_dress_class_gear(cls, silver)
	_class_weapons = _gear_weapons.duplicate()
	_class_shield = _gear_shield.duplicate()
	_wear_studio_armor()
	_wear_race_weapon()
	_wear_race_shield()
	var spec := class_data(cls)
	# The class clips live in the body file: they are the same for every hair (the hair chains' secondary
	# motion included), so one library per class.
	_library = AnimationSet.load_file(path, str(spec.get("clip_marks", "")))
	if _library == null:
		_library = AnimationSet.load_file(str(spec.get("animations", "")), str(spec.get("clip_marks", "")))
	if _library == null:
		return false
	_skill_clip = {}
	_prepare_meshes()
	_apply_colors()
	_shield = null
	_build_shield()
	if not str(weapon[0]).is_empty():
		_show_weapon(weapon[0], weapon[1])
	_update_shield()
	_fit_weapon()
	return true


## class-gear.js equipClassGear(): "outfit" = all gear meshes and no base body; "weapons" (Silver Silk) =
## the silk over the base body plus only the weapon pieces.
func _dress_class_gear(cls: String, silver: bool) -> void:
	var gear := gear_path(cls)
	if not ResourceLoader.exists(gear):
		return
	if silver:
		var silk := _merge(silver_path(), func(n: String) -> bool: return n.begins_with("Outfit_SilverSilk"))
		_meshes.append_array(silk)
		_gear_meshes.append_array(silk)
	else:
		for mesh in _meshes:
			if str(mesh.name) == "Base_Body":
				mesh.visible = false  # (kept hidden, not freed: worn Studio armour shows it again)
	var pieces := _merge(gear, func(n: String) -> bool: return not silver or is_weapon_piece(n))
	for mesh in pieces:
		var label := str(mesh.name)
		if is_weapon_piece(label):
			if label.contains("| Shield"):
				_gear_shield.append(mesh)
			else:
				_gear_weapons.append(mesh)
		if mesh.mesh.get_blend_shape_count() > 0 and mesh.find_blend_shape_by_name(CAPE_SHAPES[0]) >= 0:
			_cape_mesh = mesh
			_load_cape_tracks(gear)
	_meshes.append_array(pieces)
	_gear_meshes.append_array(pieces)


## Moves the skinned meshes of another file with the same 102-joint rig and rest pose onto our skeleton
## (their skins bind by bone name). `keep` gets the mesh name.
func _merge(path: String, keep: Callable) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	var packed := load(path) as PackedScene if ResourceLoader.exists(path) else null
	if packed == null:
		return found
	var piece := packed.instantiate()
	var meshes: Array[MeshInstance3D] = []
	_find_meshes(piece, meshes)
	for mesh in meshes:
		if mesh.skin == null or not keep.call(str(mesh.name)):
			continue
		mesh.owner = null
		mesh.get_parent().remove_child(mesh)
		_skeleton.add_child(mesh)
		mesh.transform = Transform3D.IDENTITY
		mesh.skeleton = mesh.get_path_to(_skeleton)
		found.append(mesh)
	piece.free()
	return found


## The cape's morph-target tracks in the gear file, by clip name (class-gear.js keeps a gear clip only when
## the body has a clip of the same name).
func _load_cape_tracks(gear: String) -> void:
	if _cape_tracks.has(gear):
		return
	var tracks := {}
	var packed := load(gear) as PackedScene
	var scene := packed.instantiate()
	for player in scene.find_children("*", "AnimationPlayer", true, false):
		for clip in player.get_animation_list():
			var animation: Animation = player.get_animation(clip)
			var shapes := {}
			for track in animation.get_track_count():
				if animation.track_get_type(track) == Animation.TYPE_BLEND_SHAPE:
					shapes[str(animation.track_get_path(track).get_concatenated_subnames())] = track
			if not shapes.is_empty():
				tracks[str(clip)] = {"animation": animation, "shapes": shapes}
	scene.free()
	_cape_tracks[gear] = tracks


func _apply_cape(clip: String, time: float) -> void:
	if _cape_mesh == null or _library == null:
		return
	var entry: Dictionary = _cape_tracks.get(gear_path(class_id), {}).get(clip, {})
	for shape in CAPE_SHAPES:
		var index := _cape_mesh.find_blend_shape_by_name(shape)
		if index < 0:
			continue
		var value := 0.0
		if not entry.is_empty() and entry["shapes"].has(shape):
			var animation: Animation = entry["animation"]
			var looping: bool = _library.has_clip(clip) and _library.is_looping(clip)
			var t := fposmod(time, animation.length) if looping else clampf(time, 0.0, animation.length)
			value = animation.blend_shape_track_interpolate(entry["shapes"][shape], t)
		_cape_mesh.set_blend_shape_value(index, value)


## A plain round shield (steel face, gold rim, boss in the middle) on the left hand's socket: the look of
## the procedural catalog shield (data/items/catalog.json round_shield).
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


## Which shield shows (Boss 2026-11-11: the off-hand slot is Sword & Shield only):
## "file" = an equipped shield with its own model; "procedural" = the equipped procedural round_shield
## (or the class file's round_shield fallback); "class" = the Studio's "| Shield" gear piece when the
## slot is empty; "" = none (classes with off_hand "none").
func shield_kind() -> String:
	var spec_off := str(class_data(class_id).get("off_hand", "none"))
	if spec_off == "none":
		return ""
	if not _offhand.is_empty():
		var file := str(_offhand.get("path", ""))
		if not file.is_empty() and not is_studio_rig_file(file):
			return "file"
		# Boss 2026-11-12: the class armor's own Studio shield beats the flat procedural round_shield
		# (the starter shield has no model file); the refine aura still follows the off-hand item.
		if bool(_offhand.get("procedural", false)) and _gear_shield.is_empty():
			return "procedural"
	if not _gear_shield.is_empty():
		return "class"
	return "procedural" if spec_off == "round_shield" else ""


func _update_shield() -> void:
	var kind := shield_kind()
	var shown := _weapon_shown
	if _shield != null:
		_shield.visible = kind == "procedural" and shown
	for mesh in _gear_shield:
		mesh.visible = kind == "class" and shown
	var wanted := str(_offhand.get("path", "")) if kind == "file" else ""
	if wanted != _offhand_path and _skeleton != null:
		if _offhand_node != null:
			_offhand_node.get_parent().queue_free()
			_offhand_node = null
		_offhand_path = wanted
		var packed := load(wanted) as PackedScene if not wanted.is_empty() and ResourceLoader.exists(wanted) else null
		if packed != null:
			_offhand_node = _attach(packed, WEAPON_BONE_LEFT)
			_offhand_node.quaternion = Quaternion.from_euler(shield_turn_degrees * PI / 180.0)
			_offhand_node.scale = Vector3.ONE / maxf(model_scale(), 0.0001)
			_prepare_meshes()
	if _offhand_node != null:
		_offhand_node.visible = shown


## The meshes that show the shield now (refine aura, tests).
func shield_meshes() -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	match shield_kind():
		"class":
			found.append_array(_gear_shield)
		"procedural":
			if _shield != null:
				_find_meshes(_shield, found)
		"file":
			if _offhand_node != null:
				_find_meshes(_offhand_node, found)
	return found.filter(func(m): return m.name != "RefineAura")


func _union_bounds() -> AABB:
	var bounds := AABB()
	var first := true
	for mesh in _meshes:
		if not is_instance_valid(mesh) or not mesh.visible or str(mesh.name).ends_with("_StudioInk"):
			continue
		if mesh in _gear_weapons or mesh in _gear_shield:
			continue  # framing follows the body, not the reach of a bow or staff
		var current: AABB = mesh.transform * mesh.mesh.get_aabb()
		bounds = current if first else bounds.merge(current)
		first = false
	return bounds


## Bind-pose position copied into UV/UV2: the face artwork and hair strokes stay on the skin while it moves.
## (Only for the UV-less head and hair A-F; textured pieces keep their UV.)
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
	for mesh in _meshes.duplicate():
		if not is_instance_valid(mesh) or mesh.has_meta("studio05"):
			continue
		mesh.set_meta("studio05", true)
		var label: String = str(mesh.name)
		var part: int = 1 if label.begins_with("Head_Anime") else (2 if label.begins_with("Hair_") else 0)
		var has_uv: bool = (mesh.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_TEX_UV) != 0
		var rest: bool = part != 0 and not has_uv
		if rest:
			mesh.mesh = _with_rest_coordinates(mesh.mesh)
		var first_texture: Texture2D = null
		var has_color := false
		for surface in mesh.mesh.get_surface_count():
			var original := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			var material := ShaderMaterial.new()
			material.shader = ToonShader
			material.resource_name = original.resource_name if original != null else label
			material.set_shader_parameter("part", part)
			material.set_shader_parameter("has_rest", rest)
			# The importer gives albedo_color in sRGB; the Studio multiplies in linear (three.js material.color).
			var color := (original.albedo_color if original != null else Color.WHITE).srgb_to_linear()
			material.set_meta("file_color", color)
			material.set_shader_parameter("base_color_linear", Vector3(color.r, color.g, color.b))
			if original != null and original.albedo_texture != null:
				material.set_shader_parameter("use_albedo_tex", true)
				material.set_shader_parameter("albedo_tex", original.albedo_texture)
				first_texture = original.albedo_texture
			var format: int = mesh.mesh.surface_get_format(surface)
			if original != null and original.normal_enabled and original.normal_texture != null and (format & Mesh.ARRAY_FORMAT_TANGENT):
				material.set_shader_parameter("use_normal_tex", true)
				material.set_shader_parameter("normal_tex", original.normal_texture)
			if format & Mesh.ARRAY_FORMAT_COLOR:
				material.set_shader_parameter("use_vertex_color", true)
				has_color = true
			if part == 2:
				material.set_shader_parameter("hair_part", 0.009 if label.begins_with("Hair_A") else -0.003)
				material.set_shader_parameter("painted_bangs", 0.0 if label.substr(5, 1) in ["C", "D", "E", "F", "G"] else 1.0)
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
			ink.set_shader_parameter("has_rest", rest)
			ink.set_shader_parameter("use_vertex_color", has_color)
			if first_texture != null:
				ink.set_shader_parameter("use_albedo_tex", true)
				ink.set_shader_parameter("albedo_tex", first_texture)
			hull.material_override = ink
			hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			hull.set_meta("studio05_ink", part)
	CharacterLight.prepare(_model_root)


## Hair colour (index.html updateColors: material.color.set(#hair-color) on Hair_* meshes, multiplied in the
## shader by the hair's vertex colours / Hair G texture, as three.js does): the chosen colour (a card's
## hair_color via ItemAssets.card_appearance), else #6F657F for hairs A/B and white for
## C-G (their colour lives in the file: vertex colours, or Hair G's texture).
func _hair_linear() -> Color:
	var chosen := _hair_color if _custom_hair else (LIGHT_HAIR if _hair_letter in ["c", "e", "f", "g"] else DEFAULT_HAIR)
	return chosen.srgb_to_linear()


func _apply_colors() -> void:
	var hair := _hair_linear()
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
			material.set_shader_parameter("iris_style", _iris_style)
			material.set_shader_parameter("makeup_style", _makeup)
			material.set_shader_parameter("blink", _blink)
		material.set_shader_parameter("flash", Vector4(_flash.r, _flash.g, _flash.b, _flash.a))
	for mesh in _hair_meshes:
		for hull in mesh.get_children():
			if hull is MeshInstance3D and hull.material_override is ShaderMaterial:
				hull.material_override.set_shader_parameter("base_color_linear", Vector3(hair.r, hair.g, hair.b))


## Switches the class (data/classes/<id>.json): its body file, gear, animation library and shield.
func set_class(id: String) -> void:
	if id == class_id and _library != null:
		return
	if class_data(id).is_empty():
		return
	_load_variant(id, _hair_letter, _silver)


func _fit_weapon() -> void:
	var spec := class_data(class_id)
	# The class gear carries the class weapon (class-gear.js): the item weapon stays in the socket
	# (swing trails, skills) but is not drawn over it.
	var shown := bool(spec.get("weapon_visible", true)) and _gear_weapons.is_empty() and _weapon_shown
	var scale_by := float(spec.get("weapon_scale", 1.0)) / maxf(model_scale(), 0.0001)
	for node in [_weapon_node, _weapon_left]:
		if node != null:
			node.visible = shown
			node.scale = Vector3.ONE * scale_by
	for mesh in _gear_weapons:
		mesh.visible = _weapon_shown
	_update_shield()


## Hides the weapons in the hands without unequipping them (a spear pack throws it and catches it again).
func set_weapon_visible(shown: bool) -> void:
	_weapon_shown = shown
	_fit_weapon()


## True when the class gear draws the class weapon (the item weapon is then kept hidden in the socket).
func has_class_weapon() -> bool:
	return not _gear_weapons.is_empty()


func set_appearance(appearance: Dictionary) -> void:
	var choices: Dictionary = appearance.get("choices", {})
	var silver := false  # the old account-wide fashion is gone (Boss 2026-11-13); the card's outfit sets it below
	var hair := hair_for(str(choices.get("hair_style", "")))
	if appearance.has("studio_hair"):  # the card's own look (CardDeck.look_of) wins
		hair = hair_for(str(appearance["studio_hair"]))
		silver = bool(appearance.get("studio_silver", silver))
	_custom_hair = appearance.has("hair") and not bool(appearance.get("hair_natural", true))
	_hair_color = appearance["hair"] if _custom_hair else DEFAULT_HAIR
	_iris_style = int(appearance.get("iris_style", 0))
	if not IRIS_STYLES.has(_iris_style):
		_iris_style = 0
	if appearance.has("eye_color") and str(appearance.get("eye_color_id", "")) not in ["", "original", "default"]:
		_iris = appearance["eye_color"]
	elif _iris_style != 0:
		_iris = Color(str(IRIS_STYLES[_iris_style]))  # index.html: a preset brings its own data-color
	else:
		_iris = DEFAULT_IRIS
	if appearance.has("skin") and str(choices.get("skin", "default")) not in ["default", ""]:
		_skin = (appearance["skin"] as Color).srgb_to_linear()
	else:
		_skin = SKIN_LINEAR
	_makeup = makeup_style(str(choices.get("makeup", "")))
	if appearance.has("blink_mode"):
		set_blink_mode(str(appearance["blink_mode"]))
	_load_variant(class_id, hair, silver)
	_apply_colors()


## eye-makeup.js makeupStyle for a makeup id. The Studio menu: 0 Anime Soft, 1 Sharp Wing, 2 natural (no makeup).
## The card's "none" is the Studio's natural / no-makeup set (PO default 2026-11-12, docs/po_defaults.md);
## any other id (the account look's "" / old ids) keeps Anime Soft.
static func makeup_style(id: String) -> int:
	match id:
		"sharp_wing":
			return 1
		"natural", "none":
			return 2
	return 0


## Files skinned to this 102-joint Studio rig (same joints, order and bind pose: tools/items/split_race_outfits.py
## checks the delivery): the race gear folders. Other armour files are on the old 93-joint rig.
static func is_studio_rig_file(file: String) -> bool:
	return file.begins_with("res://art/armor/race_") or file.begins_with("res://art/weapons/race_")


## The worn Studio armour pieces: slot -> file ({} = the class suit).
func worn_studio_armor() -> Dictionary:
	var result := {}
	for slot_id in _worn:
		result[slot_id] = _worn[slot_id]["path"]
	return result


## Puts _armor_wanted on the skeleton. Any worn piece switches the look to the base body + worn pieces + the
## class weapons (class-gear.js 'weapons' mode, like Silver Silk); none = the class suit as the Studio shows it.
func _wear_studio_armor() -> void:
	if _skeleton == null:
		return
	for slot_id in _worn.keys():
		if _armor_wanted.get(slot_id, "") == _worn[slot_id]["path"]:
			continue
		for mesh in _worn[slot_id]["meshes"]:
			_meshes.erase(mesh)
			_retired.append(mesh.mesh)
			mesh.queue_free()
		_worn.erase(slot_id)
	var added := false
	for slot_id in _armor_wanted:
		if _worn.has(slot_id):
			continue
		var pieces := _merge(str(_armor_wanted[slot_id]), func(_n: String) -> bool: return true)
		if pieces.is_empty():
			continue
		_meshes.append_array(pieces)
		_worn[slot_id] = {"path": str(_armor_wanted[slot_id]), "meshes": pieces}
		added = true
	var dressed := not _worn.is_empty()
	_mask_body()
	for mesh in _gear_meshes:
		if not (mesh in _class_weapons or mesh in _class_shield or mesh in _race_weapon_meshes):
			mesh.visible = not dressed  # the class suit (and its cape / neck fitting) steps aside
	for mesh in _body_meshes:
		if str(mesh.name) == "Base_Body":
			mesh.visible = dressed or _silver
	if added and not _toon.is_empty():
		_prepare_meshes()
		_apply_colors()


## Base_Body without the triangles the worn pieces cover (BODY_COVER); the whole body when nothing is worn.
func _mask_body() -> void:
	var body: MeshInstance3D = null
	for mesh in _body_meshes:
		if is_instance_valid(mesh) and str(mesh.name) == "Base_Body":
			body = mesh
	if body == null or _body_full == null:
		return
	var covered: Array[String] = []
	for slot_id in ["shirt", "armband", "pants", "shoes"]:
		if _worn.has(slot_id):
			covered.append(slot_id)
	if _worn.has("shirt") and _worn.has("armband"):
		covered.append("shirt+armband")
	var key := ",".join(covered)
	var wanted: Mesh = _body_full
	if not covered.is_empty():
		if not _masked_bodies.has(key):
			_masked_bodies[key] = masked_body(_body_full, body.skin, covered)
		wanted = _masked_bodies[key]
	if body.mesh == wanted:
		return
	var materials := []
	for surface in body.get_surface_override_material_count():
		materials.append(body.get_surface_override_material(surface))
	body.mesh = wanted
	for surface in mini(materials.size(), body.get_surface_override_material_count()):
		body.set_surface_override_material(surface, materials[surface])


## A copy of `source` (skinned by `skin`) without the triangles whose three corners are each moved most by a bone
## of the `covered` BODY_COVER groups. Vertex data is copied as it is (only the index list shrinks).
static func masked_body(source: Mesh, skin: Skin, covered: Array) -> ArrayMesh:
	var hidden_bind := {}
	for bind in skin.get_bind_count():
		var bone := str(skin.get_bind_name(bind)).replace("mixamorig_", "").replace("mixamorig:", "")
		for group in covered:
			for name in BODY_COVER.get(group, []):
				if bone == name or (name.begins_with("Hand") and bone.contains(name)):
					hidden_bind[bind] = true
	var mesh := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		var count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var per := 8 if bones != null and bones.size() == count * 8 else 4
		var hide := PackedByteArray()
		hide.resize(count)
		for v in count:
			var best := 0
			for k in range(1, per):
				if weights[v * per + k] > weights[v * per + best]:
					best = k
			hide[v] = 1 if hidden_bind.has(int(bones[v * per + best])) else 0
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var kept := PackedInt32Array()
		for t in range(0, indices.size(), 3):
			if hide[indices[t]] == 1 and hide[indices[t + 1]] == 1 and hide[indices[t + 2]] == 1:
				continue
			kept.append(indices[t])
			kept.append(indices[t + 1])
			kept.append(indices[t + 2])
		arrays[Mesh.ARRAY_INDEX] = kept
		mesh.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0)
		mesh.surface_set_material(surface, source.surface_get_material(surface))
	return mesh


## Puts the equipped race shield (an off-hand item whose file is on the Studio rig, skinned to LeftForeArm like the
## class gear's "| Shield") on the body. It then counts as the shown gear shield (shield_kind() "class").
func _wear_race_shield() -> void:
	if _skeleton == null:
		return
	var current := str(_race_shield_meshes[0].get_meta("race_shield_file", "")) if not _race_shield_meshes.is_empty() else ""
	if current != _race_shield_wanted:
		for mesh in _race_shield_meshes:
			_meshes.erase(mesh)
			_gear_meshes.erase(mesh)
			_retired.append(mesh.mesh)
			mesh.queue_free()
		_race_shield_meshes.clear()
		if not _race_shield_wanted.is_empty():
			_race_shield_meshes = _merge(_race_shield_wanted, func(_n: String) -> bool: return true)
		for mesh in _race_shield_meshes:
			mesh.set_meta("race_shield_file", _race_shield_wanted)
		_meshes.append_array(_race_shield_meshes)
		_gear_meshes.append_array(_race_shield_meshes)
		if not _race_shield_meshes.is_empty() and not _toon.is_empty():
			_prepare_meshes()
			_apply_colors()
	_pick_gear_shield()


## The gear shield on show: an equipped race shield, else a "| Shield" in the race weapon file, else the class
## gear's own. The others are hidden.
func _pick_gear_shield() -> void:
	var chosen: Array[MeshInstance3D] = _class_shield
	if not _race_shield_meshes.is_empty():
		chosen = _race_shield_meshes
	elif not _weapon_file_shield.is_empty():
		chosen = _weapon_file_shield
	for list in [_class_shield, _weapon_file_shield, _race_shield_meshes]:
		if list != chosen:
			for mesh in list:
				if is_instance_valid(mesh):
					mesh.visible = false
	_gear_shield = chosen.duplicate()
	_update_shield()


## Puts _race_weapon_wanted in the hands: its skinned "| Sword/Shield/Bow/Quiver/Staff/Spellbook" pieces take the
## class gear weapon's place (a "| Shield" piece also replaces the class shield); "" = the class gear's own.
func _wear_race_weapon() -> void:
	if _skeleton == null:
		return
	var current := str(_race_weapon_meshes[0].get_meta("race_weapon_file", "")) if not _race_weapon_meshes.is_empty() else ""
	if current == _race_weapon_wanted:
		return
	for mesh in _race_weapon_meshes:
		_meshes.erase(mesh)
		_gear_meshes.erase(mesh)
		_retired.append(mesh.mesh)
		mesh.queue_free()
	_race_weapon_meshes.clear()
	var pieces: Array[MeshInstance3D] = []
	if not _race_weapon_wanted.is_empty():
		pieces = _merge(_race_weapon_wanted, func(_n: String) -> bool: return true)
	var weapons: Array[MeshInstance3D] = []
	var shields: Array[MeshInstance3D] = []
	for mesh in pieces:
		mesh.set_meta("race_weapon_file", _race_weapon_wanted)
		if str(mesh.name).contains("| Shield"):
			shields.append(mesh)
		else:
			weapons.append(mesh)
	_race_weapon_meshes = pieces
	_meshes.append_array(pieces)
	_gear_meshes.append_array(pieces)
	# A file without skinned meshes is a hand-held prop: it goes in the right-hand socket (attach_weapon.R) like the
	# model team's weapons, and the class gear weapon steps aside.
	var socket_prop := pieces.is_empty() and not _race_weapon_wanted.is_empty() and ResourceLoader.exists(_race_weapon_wanted)
	if socket_prop:
		_show_weapon(_race_weapon_wanted, "race")
	for mesh in _class_weapons:
		mesh.visible = weapons.is_empty() and not socket_prop and _weapon_shown
	for mesh in _class_shield:
		mesh.visible = false
	_gear_weapons = weapons if not weapons.is_empty() else ([] as Array[MeshInstance3D] if socket_prop else _class_weapons.duplicate())
	_weapon_file_shield = shields
	_pick_gear_shield()
	if not pieces.is_empty() and not _toon.is_empty():
		_prepare_meshes()
		_apply_colors()
	_fit_weapon()


func dress(looks: Dictionary) -> void:
	if looks.has("relics"):
		set_relics(looks.relics)
	if _skeleton == null:
		return
	if looks.has("class"):
		set_class(str(looks["class"]))
	if looks.has("appearance"):
		set_appearance(looks["appearance"])
	if looks.has("offhand"):
		_offhand = looks["offhand"] if looks["offhand"] is Dictionary else {}
		var shield_file := str(_offhand.get("path", ""))
		_race_shield_wanted = shield_file if is_studio_rig_file(shield_file) else ""
		_wear_race_shield()
	if looks.has("weapon"):
		var weapon: Dictionary = looks["weapon"]
		var file := str(weapon.get("path", ""))
		if is_studio_rig_file(file):  # a race weapon on the Studio rig replaces the class gear's weapon pieces
			_race_weapon_wanted = file
			set_weapon(str(weapon.get("style", "")))
		else:
			_race_weapon_wanted = ""
			if not file.is_empty():
				_show_weapon(file, str(weapon.get("family", "")))
			else:
				set_weapon(str(weapon.get("style", "")))
		_wear_race_weapon()
	var armor_given := false
	for slot_id in BODY_SLOTS:
		armor_given = armor_given or looks.has(slot_id)
	if armor_given:  # ItemAssets.looks() always lists every body slot; a look without them leaves the armour alone
		var wanted := {}
		for slot_id in BODY_SLOTS:
			var file := str(looks.get(slot_id, ""))
			if is_studio_rig_file(file):  # older armour files (the 93-joint rig) cannot go on this body
				wanted[slot_id] = file
		if wanted != _armor_wanted:
			_armor_wanted = wanted
			_wear_studio_armor()
	_update_shield()
	_apply_equipment_refine(looks.get("refine", {}))


## The base aura on the item weapon, plus the class weapon pieces (weapon level) and the shield on show
## (off-hand level).
func _apply_equipment_refine(levels: Dictionary) -> void:
	super._apply_equipment_refine(levels)
	var kind := shield_kind()
	var offhand_level := int(levels.get("offhand", 0))
	for mesh in _gear_weapons:
		RefineEffect.apply(mesh, int(levels.get("weapon", 0)), _skeleton)
	for mesh in _gear_shield:
		RefineEffect.apply(mesh, offhand_level if kind == "class" else 0, _skeleton)
	for holder in [_shield, _offhand_node]:
		if holder == null:
			continue
		var meshes: Array[MeshInstance3D] = []
		_find_meshes(holder, meshes)
		var shown: bool = (holder == _shield and kind == "procedural") or (holder == _offhand_node and kind == "file")
		for mesh in meshes:
			if mesh.name != "RefineAura":
				RefineEffect.apply(mesh, offhand_level if shown else 0, _skeleton)


func set_relics(ids: Array) -> void:
	if _relic_orbit == null:
		if ids.is_empty():
			return
		_relic_orbit = preload("res://client/relic_orbit.gd").new()
		add_child(_relic_orbit)
	_relic_orbit.configure(ids)


## eyes/blink.js: "auto" blinks (the Studio's only behaviour), "open" / "closed" hold the lids.
func set_blink_mode(mode: String) -> void:
	blink_enabled = mode != "open" and mode != "closed"
	_blink = 1.0 if mode == "closed" else 0.0
	_blink_clock = 0.0
	_blink_start = BLINK_FIRST
	_set_blink_uniform()


## blink.js blinkAmount(): fast close, brief contact, slower opening (smoothstep easing).
static func blink_amount(elapsed: float) -> float:
	if elapsed < 0.0:
		return 0.0
	if elapsed < BLINK_CLOSE:
		return smoothstep(0.0, 1.0, elapsed / BLINK_CLOSE)
	if elapsed < BLINK_CLOSE + BLINK_HOLD:
		return 1.0
	return 1.0 - smoothstep(0.0, 1.0, (elapsed - BLINK_CLOSE - BLINK_HOLD) / BLINK_OPEN)


func _update_blink(delta: float) -> void:
	if not blink_enabled:
		return
	if delta > 0.5:  # blink.js: a long gap (hidden tab, throttled portrait) restarts the wait
		_blink_clock = 0.0
		_blink_start = BLINK_FIRST
	_blink_clock += minf(delta, 0.5)
	var elapsed := _blink_clock - _blink_start
	var value := blink_amount(elapsed)
	if elapsed >= BLINK_CLOSE + BLINK_HOLD + BLINK_OPEN:
		_blink_clock = 0.0
		_blink_start = BLINK_DOUBLE_GAP if _blink_rng.randf() < BLINK_DOUBLE_CHANCE else BLINK_GAP_MIN + _blink_rng.randf() * BLINK_GAP_SPAN
		value = 0.0
	if value != _blink:
		_blink = value
		_set_blink_uniform()


func _set_blink_uniform() -> void:
	for material in _toon:
		if int(material.get_shader_parameter("part")) == 1:
			material.set_shader_parameter("blink", _blink)


func blink_value() -> float:
	return _blink


func apply_pose(delta: float) -> void:
	super.apply_pose(delta)
	_update_blink(delta)


func is_hair_shown() -> bool:
	return not _hair_meshes.is_empty()


func tint(color: Color) -> void:
	_flash = color if color.a > 0.0 else Color(0, 0, 0, 0)
	for material in _toon:
		material.set_shader_parameter("flash", Vector4(_flash.r, _flash.g, _flash.b, _flash.a))


func _show_weapon(path: String, family: String) -> void:
	_weapon_args = [path, family]
	super._show_weapon(path, family)
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


## Plays `clip` (a clip of this class's animation file, e.g. an idle variant from data/classes/<id>.json
## "idle_variants") whenever the pose is a plain idle, cross-fading from what was shown over `blend_seconds`.
## "" or the class idle goes back to the class idle. Display only: other poses (run, attacks, hurt) are unchanged.
## Returns false when the clip is not in the file.
func play_idle_clip(clip: String, blend_seconds: float = 0.5) -> bool:
	if _library == null:
		return false
	var main := str(class_data(class_id).get("states", {}).get("idle", "idle"))
	var wanted := "" if clip == main else clip
	if not wanted.is_empty() and not _library.has_clip(wanted):
		return false
	if wanted == _idle_clip:
		return true
	_idle_from = _idle_clip if not _idle_clip.is_empty() else main
	_idle_from_start = _idle_start if not _idle_clip.is_empty() else 0.0
	_idle_clip = wanted
	_idle_start = _clock
	_idle_blend = maxf(blend_seconds, 0.0)
	return true


## Seconds of a clip of this class's file (0 when it is not there).
func clip_length(clip: String) -> float:
	return _library.length(clip) if _library != null and _library.has_clip(clip) else 0.0


## Class skills v2 (client/skills/class_skill_motion.gd frame()): one frame of this class's own clips, with an optional
## cross-fade from the previous segment's last pose. Wins over the pose until clear_class_skill_frame().
func show_class_skill_frame(pose: Dictionary) -> bool:
	if _library == null or not _library.has_clip(str(pose.get("clip", ""))):
		return false
	var active := {"set": _library, "clip": str(pose["clip"]), "time": float(pose["time"])}
	if pose.has("from") and _library.has_clip(str(pose["from"])):
		active["from"] = str(pose["from"])
		active["from_time"] = float(pose["from_time"])
		active["weight"] = float(pose["weight"])
	_skill_clip = active
	return true


func clear_class_skill_frame() -> void:
	_skill_clip = {}


## The idle clip on show ("" = the class idle).
func idle_clip() -> String:
	return _idle_clip


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
	else:
		return _idle_active(clip)
	return {"set": _library, "clip": clip, "time": time}


## The plain idle: the class idle (on the model clock, as before) or the chosen variant (from its start,
## play_idle_clip), with the fade from the previous one.
func _idle_active(main: String) -> Dictionary:
	var clip := _idle_clip if not _idle_clip.is_empty() and _library.has_clip(_idle_clip) else main
	var active := {"set": _library, "clip": clip, "time": _clock if clip == main else _clock - _idle_start}
	var since := _clock - _idle_start
	if not _idle_from.is_empty() and _idle_from != clip and _library.has_clip(_idle_from) and since < _idle_blend:
		active["from"] = _idle_from
		active["from_time"] = _clock if _idle_from == main else _clock - _idle_from_start
		active["weight"] = since / maxf(_idle_blend, 0.001)
	return active


func _apply_clip(active: Dictionary) -> void:
	var sample: Dictionary = active["set"].sample(active["clip"], active["time"])
	if active.has("from"):  # idle variant crossfade (play_idle_clip)
		sample = _blend_samples(active["set"].sample(active["from"], active["from_time"]), sample, float(active["weight"]))
	_apply_cape(str(active["clip"]), float(active["time"]))
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


## `a` toward `b` by `weight` (0 = a, 1 = b), bone by bone; a bone missing from one side uses its rest pose.
func _blend_samples(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	var w := smoothstep(0.0, 1.0, clampf(weight, 0.0, 1.0))
	var out := {}
	for bone_name in _bone_index:
		if not a.has(bone_name) and not b.has(bone_name):
			continue
		var from: Dictionary = a.get(bone_name, {})
		var to: Dictionary = b.get(bone_name, {})
		var values := {}
		var rest: Quaternion = _rest.get(bone_name, Quaternion.IDENTITY)
		values["rotation"] = (from.get("rotation", rest) as Quaternion).slerp(to.get("rotation", rest), w)
		if from.has("position") or to.has("position"):
			var rest_position: Vector3 = _rest_position.get(bone_name, Vector3.ZERO)
			values["position"] = (from.get("position", rest_position) as Vector3).lerp(to.get("position", rest_position), w)
		out[bone_name] = values
	return out
