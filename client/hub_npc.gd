extends Node3D
## Camp NPC visuals, interaction labels and lightweight idle motion.
## Use: var npc := HubNpc.new(); npc.role = "blacksmith"; npc.display_name = "Blacksmith";
##      npc.icon_name = "repair"; npc.position = spot; add_child(npc); npc.face(direction)

const CharacterModel := preload("res://client/characters/studio05_character_model.gd")
const InkUi := preload("res://client/ink_ui.gd")
const ItemAssets := preload("res://client/item_assets.gd")

const ROLE_MODELS := {
	"relic_master": "res://art/npcs/relic_master/relic_master.glb",
	"tailor": "res://art/npcs/tailor.glb",
	"merchant": "res://art/npcs/merchant.glb",
	"quest": "res://art/npcs/quest_board.glb",
	"storage": "res://art/npcs/storage.glb",
	"blacksmith": "res://art/npcs/blacksmith.glb",
}

const ROLE_VISUAL_SCALE := {"blacksmith": 1.2, "quest": 2.0, "merchant": 0.825, "tailor": 0.825}
const HEAD_HEIGHT := 1.8  ## the anchor of the name, the icon bubble and spoken lines (the chibi is ~1.6 m)
const SAY_SECONDS := 3.2
const STANCE := "fists"  ## the bare-handed idle (the chibi's own clips; "" would fall back to the old rig's set)
## Screen spacing above the name (metres at the base pixel size; the labels have fixed_size, so these
## grow with set_screen_scale too and the icon never sits on the name - Boss 2026-10-16).
const BUBBLE_LIFT := 0.05
const SAY_LIFT := 0.095
## Each role's clothes (catalog asset ids by slot) and looks (Boss 2026-10-16: no more grey ghosts).
const ROLE_LOOKS := {
	"blacksmith": {"appearance": {"face": "annoyed", "hair_style": "buzz", "hair_color": "black", "skin": "tan"}},
	"merchant": {"appearance": {"face": "playful", "hair_style": "short_fringe", "hair_color": "auburn", "skin": "honey"}},
	"tailor": {"appearance": {"face": "soft_smile", "hair_style": "low_ponytail", "hair_color": "silver", "skin": "porcelain"}},
	"storage": {"appearance": {"face": "bored", "hair_style": "tousled", "hair_color": "brown", "skin": "beige"}},
	"quest": {"appearance": {"face": "smile", "hair_style": "topknot", "hair_color": "jade_green", "skin": "fair"}},
}

var role := ""
var display_name := ""
var icon_name := ""
var model  ## CharacterModel (null if the model is missing)

var _custom_visual: Node3D
var _skeleton: Skeleton3D
var _idle_bones: Dictionary = {}
var _facing := Vector2(0.0, 1.0)
var _overlays: Array[Node3D] = []  ## name, line, bubble plate and icon: {node, base pixel_size}
var _base_pixel := {}
var _bubble: Node3D
var _bubble_base := 0.0
var _say: Label3D
var _say_left := 0.0
var _time := 0.0


func _ready() -> void:
	_time = randf() * 10.0
	if not _load_role_visual():
		var body := CharacterModel.new()
		add_child(body)
		if body.load_model():
			model = body
			model.dress(looks_for(role))
			model.set_pose("idle", 0.0, 0.0, true, _facing, false, "", "", STANCE)
		else:
			body.queue_free()
	_build_label()
	_build_bubble()


func _head_height() -> float:
	var factor := float(ROLE_VISUAL_SCALE.get(role, 1.0)) if _custom_visual != null else 1.0
	return HEAD_HEIGHT + 1.6 * (factor - 1.0) + (0.12 if role=="relic_master" else 0.0)


func _load_role_visual() -> bool:
	var path: String = ROLE_MODELS.get(role, "")
	if path.is_empty():
		return false
	var scene := load(path) as PackedScene
	if scene == null:
		return false
	_custom_visual = scene.instantiate() as Node3D
	add_child(_custom_visual)
	_custom_visual.scale *= float(ROLE_VISUAL_SCALE.get(role, 1.0))
	_custom_visual.rotation.y = atan2(_facing.x, _facing.y)
	_skeleton = _find_skeleton(_custom_visual)
	if role=="relic_master":preload("res://client/relic_master_pose.gd").apply(_custom_visual,_skeleton)
	if _skeleton != null:
		for bone_name in ["Spine2", "Head", "LeftArm", "RightArm", "LeftForeArm", "RightForeArm"]:
			var index := _skeleton.find_bone(bone_name)
			if index >= 0:
				_idle_bones[index] = _skeleton.get_bone_pose_rotation(index)
	return true


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _animate_role_idle() -> void:
	if _skeleton == null:
		return
	# Small local rotations retain imported bind transforms, weights and planted feet.
	for index in _idle_bones:
		var bone_name := _skeleton.get_bone_name(index)
		var amplitude := 0.018
		var phase := 0.0
		if "Arm" in bone_name:
			amplitude = 0.055 if "Fore" in bone_name else 0.035
			phase = 1.4 if bone_name.begins_with("Left") else 3.0
		var angle := amplitude * sin(_time * 1.3 + phase)
		_skeleton.set_bone_pose_rotation(index, _idle_bones[index] * Quaternion(Vector3.RIGHT, angle))


## What a role's NPC wears and looks like, in CharacterModel.dress() form (no weapon: bare hands).
static func looks_for(npc_role: String) -> Dictionary:
	var spec: Dictionary = ROLE_LOOKS.get(npc_role, {})
	var looks := {"weapon": {"path": "", "family": STANCE, "style": STANCE}, "hide_hair": false}
	# Fallback NPCs use native clothing; legacy wardrobe skins cannot bind to this rig.
	for slot_id in ItemAssets.BODY_SLOTS:
		looks[slot_id] = ""
	var choices: Dictionary = spec.get("appearance", {}).duplicate(true)
	choices["fashion"] = "red"
	looks["appearance"] = ItemAssets.appearance(choices)
	return looks


func _process(delta: float) -> void:
	_time += delta
	_animate_role_idle()
	if model != null:
		model.apply_pose(delta)
	if _bubble != null:
		_bubble.position.y = _bubble_base + 0.02 * sin(_time * 2.0)
	if _say_left > 0.0:
		_say_left -= delta
		_say.modulate.a = clampf(_say_left / 0.4, 0.0, 1.0)
		_say.outline_modulate.a = _say.modulate.a
		if _say_left <= 0.0:
			_say.visible = false
			_bubble.visible = true


## Turns the NPC to look along `direction` (x, z).
func face(direction: Vector2) -> void:
	_facing = direction.normalized() if direction.length() > 0.01 else Vector2(0.0, 1.0)
	if _custom_visual != null:
		_custom_visual.rotation.y = atan2(_facing.x, _facing.y)
	if model != null:
		model.set_pose("idle", 0.0, 0.0, true, _facing, false, "", "", STANCE)


## A short spoken line over the head for a few seconds (the icon bubble hides meanwhile).
func say(text: String) -> void:
	_say.text = text
	_say.visible = true
	_say_left = SAY_SECONDS
	_bubble.visible = false


func is_saying() -> bool:
	return _say_left > 0.0


func _build_label() -> void:
	var label := _text_3d(display_name, InkUi.TEXT_STRONG, 0.00042)
	label.name = "Name"
	label.position = Vector3(0.0, _head_height(), 0.0)
	add_child(label)
	_say = _text_3d("", InkUi.GOLD, 0.00036)
	_say.name = "Say"
	_say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_say.width = 900.0
	_say.position = Vector3(0.0, _head_height(), 0.0)
	_say.offset = Vector2(0.0, SAY_LIFT / _say.pixel_size)
	_say.visible = false
	add_child(_say)


func _text_3d(text: String, color: Color, pixel: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = InkUi.display_font()
	label.font_size = InkUi.FONT_DISPLAY * 2
	label.outline_size = 14
	label.outline_modulate = InkUi.INK
	label.modulate = color
	label.pixel_size = pixel
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true  # (the same size on screen near and far: the camera looks down steeply)
	label.no_depth_test = true
	label.render_priority = 2
	label.outline_render_priority = 1
	_remember(label)
	return label


## The labels and the bubble keep one size on screen (fixed_size); `factor` scales them for the
## screen (the hub passes the window's height relative to 900 px, more on small phones).
func set_screen_scale(factor: float) -> void:
	for node in _overlays:
		node.set("pixel_size", float(_base_pixel[node]) * factor)


func _remember(node: Node3D) -> void:
	_overlays.append(node)
	_base_pixel[node] = node.get("pixel_size")


## A round dark plate with a brass rim and the role's line icon, above the name. It sits at the name's
## anchor, lifted in screen pixels (offset), so it keeps clear of the name at every screen scale.
func _build_bubble() -> void:
	_bubble = Node3D.new()
	_bubble_base = _head_height()
	_bubble.position.y = _bubble_base
	add_child(_bubble)
	var plate := Sprite3D.new()
	plate.texture = _plate_texture()
	plate.pixel_size = 0.0006
	plate.offset = Vector2(0.0, BUBBLE_LIFT / plate.pixel_size)
	plate.fixed_size = true
	plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	plate.no_depth_test = true
	plate.render_priority = 1
	_bubble.add_child(plate)
	_remember(plate)
	if icon_name != "" and InkUi.icon(icon_name, 64) != null:
		var icon := Sprite3D.new()
		icon.texture = InkUi.icon(icon_name, 64, InkUi.ICON_TINT)
		icon.pixel_size = 0.00046
		icon.offset = Vector2(0.0, BUBBLE_LIFT / icon.pixel_size)
		icon.fixed_size = true
		icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		icon.no_depth_test = true
		icon.render_priority = 3
		_bubble.add_child(icon)
		_remember(icon)


static var _plate: ImageTexture


static func _plate_texture() -> ImageTexture:
	if _plate != null:
		return _plate
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var centre := Vector2(size, size) * 0.5 - Vector2(0.5, 0.5)
	var fill := InkUi.PANEL
	var rim := InkUi.ORNAMENT
	for y in size:
		for x in size:
			var r := Vector2(x, y).distance_to(centre) / (size * 0.5)
			var color := InkUi.CLEAR
			if r < 0.8:
				color = fill
				color.a = 0.92
			elif r < 0.92:
				color = rim
			elif r < 1.0:
				color = rim
				color.a = (1.0 - r) / 0.08
			image.set_pixel(x, y, color)
	_plate = ImageTexture.create_from_image(image)
	return _plate
