extends Node3D
## Draws one fighter (player or enemy): the character model (or a placeholder capsule), a floating
## health bar for enemies, hit reactions (flash, squash, shudder during hit-stop). The capsule's
## color shows what the fighter is doing, which keeps combat timing readable without animations.
## It only displays what the simulation says.
## EXTENDING: the modular Blender character replaces the capsule; animations replace the stand-in poses.

const AnimationSet := preload("res://client/animation_set.gd")
const CharacterLight := preload("res://client/character_light.gd")
const CharacterModel := preload("res://client/characters/studio05_character_model.gd")
const Combat := preload("res://logic/combat.gd")
const CombatData := preload("res://logic/combat_data.gd")
const InkStyle := preload("res://client/ink_style.gd")
const Fighter := preload("res://logic/fighter.gd")
const Movement := preload("res://logic/movement.gd")
const SimBody := preload("res://logic/sim_body.gd")
const ClassSkillMotion := preload("res://client/skills/class_skill_motion.gd")

## Which stand-in pose each kind of move uses until real animations exist (client-side look only).
## A move id is "<weapon>_<kind>", so every weapon shares these.
const KIND_POSES := {
	"light_1": "punch_r", "light_2": "punch_l", "light_3": "punch_r", "heavy": "heavy",
	"air": "kick", "special": "punch_r", "ultimate": "heavy",
	"run_light": "dash_punch", "run_heavy": "flying_kick", "air_heavy": "dive",
}
## A hit lands: a short, faint white flash that always clears (Boss 2026-11-14: statuses and states never
## recolour the whole character; the old status / immune / hit-stun tints made the hero a pale ghost on phones).
const FLASH_SECONDS := 0.08
const FLASH_TINT := Color(1.0, 1.0, 1.0, 0.18)  ## the toon shader mixes in linear light, so 0.18 reads as a light flash
const FLASH_GAP := 0.3  ## at most one flash per this many seconds: a mobbed hero is not kept white by back-to-back hits
const BAR_WIDTH := 1.2
const LOW_HP_RATIO := 0.3  ## below this the enemy bar crosses to its low-HP colour and pulses (matches InkUi.LOW_HP)
const ATTACK_COLOR := Color(1.0, 0.7, 0.2)
const HITSTUN_COLOR := Color(1.0, 0.45, 0.45)
const DOWN_COLOR := Color(0.45, 0.45, 0.5)
const DEAD_COLOR := Color(0.2, 0.2, 0.22)
const STATUS_LINE := 0.27  ## height of one status-effect tag above the head
const StatusVfx := preload("res://client/status_vfx.gd")
const MONSTER_RUN_SPEED := 2.44  ## m/s a monster run clip is authored for at the goblin rig's own size; played 0.6-1.4x (x the model's scale)

var base_color := Color(0.85, 0.85, 0.9)
## Set before adding to the scene to show a character model instead of the capsule.
var model_path := ""
## What the character wears (ItemAssets.looks()); empty = only the stand-in weapon of its style.
var looks: Dictionary = {}
## Set before adding to the scene to show a monster's own model (a .glb facing +Z) instead of the
## capsule, scaled to `monster_model_height`. An untextured model takes the capsule's flat state colors;
## a textured one keeps its own materials and the state tints multiply them (per-instance copies).
var monster_model_path := ""
var monster_model_height := 1.8
## Measured once at model fit; used only for body-attached status presentation.
var status_visual_size:=Vector3(.8,1.35,.8)
var monster_run_clip_speed := 0.0  ## the speed (m/s) its run clip was made for; 0 = MONSTER_RUN_SPEED (combat.json run_clip_speed)
## The monster's animation set (a .glb with idle/run/attack_1/attack_2/hit/death clips and a .json of
## marks next to it). When that file is missing, the model's own clips are used (marks from the set's
## .json if only that exists); with no clips at all the model stays static (hop and lean).
var monster_animations_path := ""
## Which clip each of the monster's moves plays (move id -> clip); a move not listed plays attack_1.
var monster_clips: Dictionary = {}
## Multiplies a textured monster model's own colors (a darker chief made from the same model).
var monster_tint := Color.WHITE
## What a move plays while the set has no clip of the name in monster_clips yet (a variant still on
## the goblin's clips): move id -> clip.
var monster_standin_clips: Dictionary = {}
## A mesh of the model (by name) shown only while a firing move winds up: the archer's nocked arrow.
var monster_nock_mesh := ""
## Show a floating health bar above the head (enemies; the player has the HUD).
var show_health_bar := false
## The bar's look, resolved from data by client/enemy_bars.gd (frame shape, colours, the notch mark).
## Empty = the old plain red bar (so a view built without a style still works). Set before _ready.
var bar_style: Dictionary = {}
## Dark ink outlines (the ink stages): on the character model and the capsule.
var ink_outline := false

var _material: StandardMaterial3D
var _nose: MeshInstance3D
var _turn: Node3D  ## the monster model's turning root (faces the fighter's direction)
var _model: Node3D
var _body: Node3D  ## everything that is squashed and shuddered
var _bar_fill: MeshInstance3D
var _bar_root: Node3D
var _bar_frame: MeshInstance3D  ## the crude/studded frame drawn behind the bar (data-driven look)
var _bar_fill_material: StandardMaterial3D  ## the fill's material (recoloured on low HP)
var _bar_colors: Dictionary = {}  ## the resolved fill/fill_low/flash colours, cached from bar_style
var _warning: Label3D
var _status_tags: Dictionary = {}  ## effect id -> Label3D shown above the head
var _status_vfx: Node3D  ## client/status_vfx.gd: small looping status effects at the feet / over the head
var _flash_rest := 0.0  ## seconds until the next hit may flash again (FLASH_GAP)
var _model_flash_on := false  ## the model's hit flash is on now (cleared the frame the timer runs out)
var _flash := 0.0
var _clock := 0.0
var _center_skeleton: Skeleton3D  ## found once for body_center()
var _center_bone := -1
var _class_skill_shown := false  ## a class skill v2 clip window drives the model now
var _class_skill_id := ""
var _class_skill_start := -1
var _class_skill_clock := 0.0
var _weapon_hidden := false  ## the weapon is out of the hand (a thrown spear)
var _own_materials: Array = []  ## textured monster: [{"material": copy, "albedo": its own color}]
var _anim: RefCounted  ## the monster's AnimationSet (null = static model)
var _skeleton: Skeleton3D
var _bones: Dictionary = {}  ## bone name -> index in _skeleton
var _anim_clip := ""  ## the clip shown now and how far into it
var _anim_time := 0.0
var _anim_rate := 0.0  ## how fast a looping clip runs (seconds per second)
## Cross-fade into idle / run: the clip faded out, where it was, its speed, and how far the fade is (1 = done).
const MONSTER_BLEND_TIME := 0.15
var _from_clip := ""
var _from_time := 0.0
var _from_rate := 0.0
var _blend := 1.0
var _seen_state := -1  ## the fighter state and state_ticks last shown, to restart hit and death clips
var _seen_ticks := 0
var _fit := 1.0  ## how much the monster model is scaled (its rig's size; the run clip's speed grows with it)
var _nock: Node3D  ## the nocked arrow (monster_nock_mesh), or null
var _height := SimBody.HEIGHT  ## the body's height in the rules: the health bar, "!" and tags sit above it


## The kind of move a move id such as "hammer_run_heavy" is ("run_heavy"), or "" (monsters' own moves).
## The longest matching kind wins, so "_run_heavy" and "_air_heavy" are not taken for "_heavy".
static func clip_for(move_id: String) -> String:
	var found := ""
	for kind in KIND_POSES:
		if move_id.ends_with("_" + kind) and kind.length() > found.length():
			found = kind
	return found


## The stand-in pose for a move id (monsters' own moves fall back to a punch).
static func pose_for(move_id: String) -> String:
	var kind := clip_for(move_id)
	return KIND_POSES[kind] if kind != "" else "punch_r"


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)
	StatusVfx.prewarm(self)  # status loop materials compile once while the stage loads (no web shader cache)
	if not model_path.is_empty():
		var model := CharacterModel.new()
		model.ink_outline = ink_outline
		_body.add_child(model)
		if model.load_model(model_path):
			_model = model
			if not looks.is_empty():
				model.dress(looks)
		else:
			model.queue_free()  # model missing: fall back to the capsule below
	if _model == null and (monster_model_path.is_empty() or not _build_monster_model()):
		_build_capsule()
	if show_health_bar:
		_build_health_bar()
		_build_warning_sign()


func _process(delta: float) -> void:
	_clock += delta
	_flash = maxf(0.0, _flash - delta)
	_flash_rest = maxf(0.0, _flash_rest - delta)
	if _model_flash_on and _flash <= 0.0 and _model != null:
		_model.tint(Color(0, 0, 0, 0))
		_model_flash_on = false
	_body.scale = _body.scale.lerp(Vector3.ONE, minf(1.0, 14.0 * delta))
	if _model != null:
		_model.apply_pose(delta)
	if _anim != null and _anim_clip != "":
		_anim_time += delta * _anim_rate
		if _blend < 1.0:
			_from_time += delta * _from_rate
			_blend = minf(1.0, _blend + delta / MONSTER_BLEND_TIME)
		_apply_clip()
	if _turn != null:
		_turn.rotation.y = lerp_angle(_turn.rotation.y, _turn.get_meta("target_yaw", 0.0), minf(1.0, 12.0 * delta))


## Changes what the character wears (after a gear change).
func set_looks(new_looks: Dictionary) -> void:
	looks = new_looks
	if _model != null and _model.has_method("dress"):
		_model.dress(looks)


func show_state(body: SimBody, fighter: Fighter, data: CombatData = null) -> void:
	if _model!=null:_model.set_relics(fighter.relic_state.get("ids",[]))
	position = body.position
	_show_race_ring(fighter)
	if not is_equal_approx(_height, body.height):
		_height = body.height
		if _bar_root != null:
			_bar_root.position.y = _height + 0.4
		if _warning != null:
			_warning.position.y = _height + 1.0
	_show_effects(fighter, data)
	# During hit-stop the fighter shudders a little: it sells the impact.
	_body.position = Vector3(randf_range(-0.03, 0.03), 0.0, 0.0) if fighter.hitstop > 0 else Vector3.ZERO
	if _bar_fill != null:
		_bar_root.visible = fighter.is_alive()
		var ratio := clampf(fighter.hp / fighter.max_hp(), 0.0, 1.0)
		_bar_fill.scale.x = ratio
		_update_bar_color(ratio)
	# A big "!" and a pulsing color warn the player while a dangerous move is winding up.
	var warning := data != null and Combat.is_telegraphing(fighter, data)
	if _warning != null:
		_warning.visible = warning
		_warning.scale = Vector3.ONE * (1.0 + 0.25 * sin(_clock * 24.0))
	if _model != null:
		_show_model_state(body, fighter, data)
		return
	var facing := Vector2(fighter.direction).normalized()
	if _turn != null:
		_turn.set_meta("target_yaw", atan2(facing.x, facing.y))
		if _anim == null or not _show_monster_clip(body, fighter, data):
			# A small hop while walking and a forward lean while attacking keep the static model alive.
			var moving := Vector2(body.velocity.x, body.velocity.z).length() > 0.1 and body.grounded
			_turn.position.y = absf(sin(_clock * 14.0)) * 0.08 if moving else 0.0
			_turn.rotation.x = 0.3 if fighter.state == Fighter.State.ATTACK else (-0.25 if fighter.state == Fighter.State.HITSTUN else 0.0)
		if _nock != null:
			_show_nock(fighter, data)
		if not _own_materials.is_empty():
			_tint_own_materials(fighter, data, warning)
			return
	else:
		if _nose == null:  # _ready stopped early (the character model script failed to load): nothing to draw
			return
		_nose.position = Vector3(0.45 * facing.x, 1.4, 0.45 * facing.y)

	var color := base_color
	match fighter.state:
		Fighter.State.ATTACK:
			color = ATTACK_COLOR
		Fighter.State.HITSTUN:
			color = HITSTUN_COLOR
		Fighter.State.GUARD:
			color = Color(0.4, 0.6, 1.0)
		Fighter.State.DODGE:
			color = Color(0.4, 0.95, 1.0)
		Fighter.State.DOWN, Fighter.State.DOWNED:
			color = DOWN_COLOR
		Fighter.State.DEAD:
			color = DEAD_COLOR
	if warning:
		color = base_color.lerp(Color(1.0, 0.95, 0.2), 0.5 + 0.5 * sin(_clock * 24.0))
	if _flash > 0.0:
		color = Color.WHITE
	_material.albedo_color = color


## A hit lands: bright flash and a quick squash that springs back.
func flash() -> void:
	if _flash_rest <= 0.0:
		_flash = FLASH_SECONDS
		_flash_rest = FLASH_GAP
	_body.scale = Vector3(1.14, 0.88, 1.14)


## Loads the monster's model under a turning root, scaled to its height with its feet on the ground.
## An untextured model uses the shared state-color material on every mesh; a textured one keeps its
## own look (see _use_own_materials). Monster models always get the ink outline, on every stage, so
## they stand out from the ground (Boss 2026-10-10). False when the file is missing.
func _build_monster_model() -> bool:
	var scene := load(monster_model_path) as PackedScene
	if scene == null:
		return false
	var model := scene.instantiate() as Node3D
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	var textured := _is_textured(meshes)
	if not textured:
		_material = StandardMaterial3D.new()
		_material.albedo_color = base_color
		_material.next_pass = InkStyle.outline_material(0.005)
	var bounds := AABB()
	var first := true
	for mesh in meshes:
		if not textured:
			mesh.material_override = _material
		var to_model: Transform3D = mesh.transform
		var parent := mesh.get_parent()
		while parent != model:
			to_model = parent.transform * to_model
			parent = parent.get_parent()
		var box: AABB = to_model * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if first or bounds.size.y <= 0.0:
		model.free()
		return false
	var fit := monster_model_height / bounds.size.y
	status_visual_size=bounds.size*fit
	_fit = fit
	model.scale = Vector3.ONE * fit
	model.position = Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z) * fit
	_turn = Node3D.new()
	_turn.add_child(model)
	_body.add_child(_turn)
	if textured:
		_use_own_materials(model, meshes)
	_find_monster_clips(model)
	if monster_nock_mesh != "":
		_nock = model.find_child(monster_nock_mesh, true, false) as Node3D
		if _nock != null:
			_nock.visible = false
	return true


## The nocked arrow shows from the start of a firing move until its release, and not otherwise.
func _show_nock(fighter: Fighter, data: CombatData) -> void:
	var shown := false
	if fighter.state == Fighter.State.ATTACK and data != null and data.moves.has(fighter.move_id):
		var spawns: Array = data.moves[fighter.move_id]["spawns"]
		shown = not spawns.is_empty() and spawns[0].has("projectile") and fighter.move_frame < float(spawns[0]["frame"])
	_nock.visible = shown


## True when any mesh of the model has a texture: then it keeps its own materials (the goblin);
## flat-colored models (monster_01) keep taking the capsule's state colors.
static func _is_textured(meshes: Array) -> bool:
	for mesh in meshes:
		for surface in mesh.mesh.get_surface_count():
			var material = mesh.get_active_material(surface)
			if material is BaseMaterial3D and material.albedo_texture != null:
				return true
	return false


## A textured monster joins the character lighting and gets its own copy of each material, so a tint
## (hit, stun, death) multiplies that copy's color and the texture stays. Each mesh gets an ink
## outline child, moved by the same bones when the mesh is skinned (as on the player).
func _use_own_materials(model: Node3D, meshes: Array) -> void:
	CharacterLight.prepare(model)
	for mesh in meshes:
		for surface in mesh.mesh.get_surface_count():
			var material = mesh.get_surface_override_material(surface)  # CharacterLight's copy, if it made one
			if material == null:
				material = mesh.get_active_material(surface)
				if not material is BaseMaterial3D:
					continue
				material = material.duplicate()
				mesh.set_surface_override_material(surface, material)
			if not material is BaseMaterial3D:
				continue
			if str(material.resource_name).ends_with("_glow"):
				# A glowing part (the mage's crystal) keeps its own light and only pulses gently.
				_own_materials.append({"material": material, "albedo": material.albedo_color, "glow": material.emission_energy_multiplier})
				continue
			material.emission_enabled = true  # (set once, so a flash does not compile a new shader mid-fight)
			material.emission = Color.BLACK
			_own_materials.append({"material": material, "albedo": material.albedo_color * monster_tint})
		var outline := MeshInstance3D.new()
		outline.name = "InkOutline"
		outline.mesh = InkStyle.outline_mesh(mesh.mesh)
		outline.skin = mesh.skin
		mesh.add_child(outline)
		if mesh.skin != null:
			outline.skeleton = outline.get_path_to(mesh.get_node(mesh.skeleton))
		outline.material_override = InkStyle.outline_material(0.005)
		outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The state tint on a textured monster: hit reddens, down and death darken (statuses do not tint; they show
## as status_vfx loops); the flash and the wind-up warning glow (emission) since multiplying cannot brighten.
func _tint_own_materials(fighter: Fighter, data: CombatData, warning: bool) -> void:
	var multiply := Color.WHITE
	var glow := Color.BLACK
	match fighter.state:
		Fighter.State.HITSTUN:
			multiply = Color(1.0, 0.6, 0.6)
			glow = Color(0.3, 0.03, 0.03)
		Fighter.State.DOWN, Fighter.State.DOWNED:
			multiply = Color(0.75, 0.75, 0.8)
		Fighter.State.DEAD:
			multiply = Color(0.4, 0.4, 0.45)
	if warning:
		glow = Color(1.0, 0.85, 0.1) * (0.2 + 0.2 * sin(_clock * 24.0))
	if _flash > 0.0:
		glow = Color(0.6, 0.6, 0.6)
	for entry in _own_materials:
		var albedo: Color = entry["albedo"]
		entry["material"].albedo_color = Color(albedo.r * multiply.r, albedo.g * multiply.g, albedo.b * multiply.b, albedo.a)
		if entry.has("glow"):
			var dim := 0.25 if fighter.state == Fighter.State.DEAD else 1.0
			entry["material"].emission_energy_multiplier = float(entry["glow"]) * dim * (1.0 + 0.15 * sin(_clock * 2.4))
		else:
			entry["material"].emission = glow


## The monster's clips: its animation set file if it exists, else the model's own animations (marks
## from the set's .json if that exists, else from a .json next to the model). Null = static model.
func _find_monster_clips(model: Node3D) -> void:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	var found: RefCounted = null
	if monster_animations_path != "":
		found = AnimationSet.load_file(monster_animations_path)
	if not usable_clips(found):
		var marks := monster_animations_path.get_basename() + ".json"
		found = AnimationSet.load_file(monster_model_path, marks if monster_animations_path != "" and FileAccess.file_exists(marks) else "")
	if not usable_clips(found):
		return
	_anim = found
	_skeleton = skeletons[0]
	for index in _skeleton.get_bone_count():
		_bones[_skeleton.get_bone_name(index)] = index
	for player in model.find_children("*", "AnimationPlayer", true, false):
		player.active = false  # the view poses the bones itself (a test clip must not play on its own)


## A set the monster can animate with: it has an idle or an attack clip.
static func usable_clips(found: RefCounted) -> bool:
	return found != null and (found.has_clip("idle") or found.has_clip("attack_1"))


## The animation set this view plays (null = a static model or a capsule).
func monster_animation() -> RefCounted:
	return _anim


## Picks the clip for the fighter's state: idle/run by speed, the move's attack clip stretched over its
## wind-up / strike / recovery (like the player's), hit when struck, death when it dies (held at the
## end). False when the set has no clip for this state (the static hop and lean are used instead).
func _show_monster_clip(body: SimBody, fighter: Fighter, data: CombatData) -> bool:
	var restarted := fighter.state != _seen_state or fighter.state_ticks < _seen_ticks
	_seen_state = fighter.state
	_seen_ticks = fighter.state_ticks
	var clip := ""
	match fighter.state:
		Fighter.State.ATTACK:
			clip = str(monster_clips.get(fighter.move_id, "attack_1"))
			if not _anim.has_clip(clip):
				clip = str(monster_standin_clips.get(fighter.move_id, "attack_1"))
			if not _anim.has_clip(clip) or data == null or not data.moves.has(fighter.move_id):
				return false
			var move: Dictionary = data.moves[fighter.move_id]
			var startup := float(move["startup"])
			var active_end := startup + float(move["active"])
			var frame := fighter.move_frame
			var time := 0.0
			if frame < startup:
				time = _anim.attack_time(clip, "windup", frame / maxf(1.0, startup))
			elif frame < active_end:
				time = _anim.attack_time(clip, "strike", (frame - startup) / maxf(1.0, float(move["active"])))
			else:
				time = _anim.attack_time(clip, "recover", (frame - active_end) / maxf(1.0, float(move["recovery"])))
			_set_clip(clip, time, 0.0)
		Fighter.State.HITSTUN, Fighter.State.DOWN, Fighter.State.DOWNED:
			clip = "hit"
		Fighter.State.DEAD:
			clip = "death" if _anim.has_clip("death") else "hit"
		_:
			var speed := Vector2(body.velocity.x, body.velocity.z).length()
			clip = "run" if speed > 0.3 and body.grounded and _anim.has_clip("run") else "idle"
			if not _anim.has_clip(clip):
				return false
			var reference := monster_run_clip_speed if monster_run_clip_speed > 0.0 else MONSTER_RUN_SPEED
			var rate := clampf(speed / (reference * _fit), 0.6, 1.4) if clip == "run" else 1.0
			if _anim_clip != clip:
				_set_clip(clip, 0.0, rate)
			_anim_rate = rate
	if clip == "hit" or clip == "death":
		if not _anim.has_clip(clip):
			return false
		if restarted or _anim_clip != clip:
			_set_clip(clip, 0.0, 1.0)
	_turn.position.y = 0.0
	_turn.rotation.x = 0.0
	return true


## Attacks, hit and death start at once (their timing is the rules'); idle and run fade in from
## whatever was showing, so locomotion changes do not pop.
func _set_clip(clip: String, time: float, rate: float) -> void:
	if clip != _anim_clip and _anim_clip != "" and _anim.is_looping(clip):
		_from_clip = _anim_clip
		_from_time = _anim_time
		_from_rate = _anim_rate
		_blend = 0.0
	elif clip != _anim_clip or not _anim.is_looping(clip):
		_blend = 1.0
	_anim_clip = clip
	_anim_time = time
	_anim_rate = rate
	_apply_clip()


## Poses the skeleton at the current moment of the current clip (bones the clip does not move rest).
func _apply_clip() -> void:
	if _anim_clip == "" or _skeleton == null:
		return
	_skeleton.reset_bone_poses()
	var pose: Dictionary = _anim.sample(_anim_clip, _anim_time)
	if _blend < 1.0 and _from_clip != "" and _anim.has_clip(_from_clip):
		pose = _blend_poses(_anim.sample(_from_clip, _from_time), pose, _blend)
	for bone in pose:
		var index: int = _bones.get(bone, -1)
		if index < 0:
			continue
		if pose[bone].has("rotation"):
			_skeleton.set_bone_pose_rotation(index, pose[bone]["rotation"])
		if pose[bone].has("position"):
			_skeleton.set_bone_pose_position(index, pose[bone]["position"])


## `from` faded toward `to` by `weight` (0..1); a bone only one of them moves blends with its rest.
func _blend_poses(from: Dictionary, to: Dictionary, weight: float) -> Dictionary:
	var out := {}
	for bone in from.keys() + to.keys():
		if out.has(bone):
			continue
		var index: int = _bones.get(bone, -1)
		if index < 0:
			continue
		var rest := _skeleton.get_bone_rest(index)
		var a: Dictionary = from.get(bone, {})
		var b: Dictionary = to.get(bone, {})
		var rot_a: Quaternion = a.get("rotation", rest.basis.get_rotation_quaternion())
		var rot_b: Quaternion = b.get("rotation", rest.basis.get_rotation_quaternion())
		out[bone] = {"rotation": rot_a.slerp(rot_b, weight)}
		if a.has("position") or b.has("position"):
			out[bone]["position"] = (a.get("position", rest.origin) as Vector3).lerp(b.get("position", rest.origin), weight)
	return out


func _build_capsule() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = base_color
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.height = SimBody.HEIGHT
	capsule.radius = SimBody.HALF_WIDTH
	capsule.material = _material
	mesh.mesh = capsule
	mesh.position.y = SimBody.HEIGHT / 2.0
	_body.add_child(mesh)

	_nose = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.2, 0.2)
	box.material = _material
	_nose.mesh = box
	_nose.position = Vector3(0.45, 1.4, 0.0)
	_body.add_child(_nose)


func _build_warning_sign() -> void:
	_warning = Label3D.new()
	_warning.text = "!"
	_warning.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_warning.font_size = 96
	_warning.pixel_size = 0.012
	_warning.outline_size = 16
	_warning.modulate = Color(1.0, 0.9, 0.1)
	_warning.no_depth_test = true
	_warning.position = Vector3(0.0, SimBody.HEIGHT + 1.0, 0.0)
	_warning.visible = false
	add_child(_warning)


## A flat bar that always faces the camera. Its look is `bar_style` (from data via client/enemy_bars.gd):
## a dark back plate and outline so it reads on both the bright golden ground and the dark ink ground,
## a frame shape (crude lashed planks / studded elite / chief), a mossy-to-rust fill that is not the
## player's clean HUD red, and a notch mark on the left cap (so the goblin bar never reads by colour
## alone). Empty bar_style = the old plain red bar.
func _build_health_bar() -> void:
	var style := bar_style
	var fill_color: Color = style.get("fill", Color(0.95, 0.2, 0.25))
	var back_color: Color = style.get("back", Color(0.05, 0.05, 0.08, 0.85))
	var outline_color: Color = style.get("outline", Color(0.03, 0.04, 0.03, 1.0))
	var frame_color: Color = style.get("frame", Color(0, 0, 0, 0))
	var shape := str(style.get("frame_shape", "plain"))
	var mark := str(style.get("mark", "none"))
	_bar_colors = {
		"fill": fill_color,
		"fill_low": style.get("fill_low", fill_color),
		"flash": style.get("low_flash", fill_color),
	}
	_bar_root = Node3D.new()
	_bar_root.position = Vector3(0.0, SimBody.HEIGHT + 0.4, 0.0)
	add_child(_bar_root)
	# The frame / back plate: one quad a little larger than the fill, in the outline colour, with the
	# frame colour drawn as a border by a thin inner quad; both billboarded so the bar faces the camera.
	if shape != "plain":
		var frame_quad := QuadMesh.new()
		frame_quad.size = Vector2(BAR_WIDTH + 0.18, 0.30)
		_bar_frame = MeshInstance3D.new()
		_bar_frame.mesh = frame_quad
		_bar_frame.material_override = _bar_material(frame_color, 0)
		_bar_root.add_child(_bar_frame)
	for part in ["back", "fill"]:
		var quad := QuadMesh.new()
		quad.size = Vector2(BAR_WIDTH + 0.08, 0.2) if part == "back" else Vector2(BAR_WIDTH, 0.13)
		if part == "fill":
			quad.center_offset = Vector3(BAR_WIDTH * 0.5, 0.0, 0.0)
		var material := _bar_material(back_color if part == "back" else fill_color, 2 if part == "fill" else 1)
		if part == "back":
			material.albedo_color = back_color  # the dark plate (already alpha); keep its transparency
		var bar := MeshInstance3D.new()
		bar.mesh = quad
		bar.material_override = material
		if part == "fill":
			bar.position.x = -BAR_WIDTH * 0.5
			_bar_fill = bar
			_bar_fill_material = material
		_bar_root.add_child(bar)
	_build_bar_mark(mark, outline_color, frame_color)


## One unshaded, billboarded, depth-free material for a bar part. `priority` orders back/frame/fill.
func _bar_material(color: Color, priority: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.albedo_color = color
	material.render_priority = priority
	material.no_depth_test = true
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


## A small crude mark on the bar's left cap so meaning is not colour alone: a goblin "fang"
## (one or two tiny triangles), or a "skull" dot for the Chief. Drawn with tiny billboarded quads
## (0 KB). "none" draws nothing.
func _build_bar_mark(mark: String, ink: Color, tint: Color) -> void:
	if mark == "none" or mark == "":
		return
	var cap := Node3D.new()
	cap.position = Vector3(-BAR_WIDTH * 0.5 - 0.14, 0.0, 0.0)
	_bar_root.add_child(cap)
	var count := 2 if mark == "fang_double" else 1
	if mark == "skull":
		# a pale bone dot ringed in ink: the Chief's bar
		var dot := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.17, 0.17)
		dot.mesh = quad
		dot.material_override = _bar_material(Color(0.90, 0.86, 0.74, 1.0), 3)
		cap.add_child(dot)
		var rim := MeshInstance3D.new()
		var rim_quad := QuadMesh.new()
		rim_quad.size = Vector2(0.21, 0.21)
		rim.mesh = rim_quad
		rim.material_override = _bar_material(ink, 2)
		cap.add_child(rim)
		return
	for i in count:
		var fang := MeshInstance3D.new()
		var tri := PrismMesh.new()  # a wedge reads as a little tooth from the camera
		tri.size = Vector3(0.13, 0.17, 0.02)
		fang.mesh = tri
		fang.rotation_degrees = Vector3(0.0, 0.0, 180.0)  # point down, like a fang
		fang.position = Vector3(float(i) * 0.13 - (count - 1) * 0.065, 0.0, 0.0)
		fang.material_override = _bar_material(Color(0.92, 0.88, 0.78, 1.0), 3)
		cap.add_child(fang)


## Recolours the fill for low HP: below the low threshold it crosses toward fill_low and pulses with
## low_flash, so a hurt enemy reads at a glance (the HUD boss bar does the same for the player).
func _update_bar_color(ratio: float) -> void:
	if _bar_fill_material == null or _bar_colors.is_empty():
		return
	var base: Color = _bar_colors["fill"]
	if ratio < LOW_HP_RATIO:
		var low: Color = _bar_colors["fill_low"]
		var flash: Color = _bar_colors["flash"]
		var pulse := 0.5 + 0.5 * sin(_clock * 7.0)
		_bar_fill_material.albedo_color = low.lerp(flash, 0.35 * pulse)
	else:
		_bar_fill_material.albedo_color = base


## Chooses the stand-in pose for the fighter's state; the model is tinted only by the brief hit flash.
func _show_model_state(body: SimBody, fighter: Fighter, data: CombatData) -> void:
	var kind := "idle"
	var phase := ""
	var amount := 0.0
	var speed := Vector2(body.velocity.x, body.velocity.z).length() / Movement.SPEED
	match fighter.state:
		Fighter.State.ATTACK:
			kind = pose_for(fighter.move_id)
			if data != null and data.moves.has(fighter.move_id):
				var move: Dictionary = data.moves[fighter.move_id]
				var startup: float = move["startup"]
				var active_end: float = startup + float(move["active"])
				var frame := fighter.move_frame
				if frame < startup:
					phase = "windup"
					amount = frame / startup
				elif frame < active_end:
					phase = "strike"
					amount = (frame - startup) / float(move["active"])
				else:
					phase = "recover"
					amount = clampf((frame - active_end) / maxf(1.0, float(move["recovery"])), 0.0, 1.0)
		Fighter.State.HITSTUN:
			kind = "launched" if fighter.launched else "hurt"
		Fighter.State.GUARD:
			kind = "guard"
			amount = fighter.state_ticks / 60.0
		Fighter.State.DODGE:
			kind = "slide"
			if data != null:
				amount = fighter.state_ticks / maxf(1.0, float(data.rules["dodge_ticks"]))
		Fighter.State.DOWN, Fighter.State.DOWNED, Fighter.State.DEAD:
			kind = "down"
		_:
			if fighter.running:
				kind = "run"
			elif speed > 0.1 and body.grounded:
				kind = "walk"
	var lying := fighter.state in [Fighter.State.DOWN, Fighter.State.DOWNED, Fighter.State.DEAD]
	var clip := clip_for(fighter.move_id) if fighter.state == Fighter.State.ATTACK else ""
	if not looks.has("weapon"):
		_model.set_weapon(fighter.style if fighter.team == "player" else "")
	if data != null and data.weapons.has(fighter.style) and _model.has_blade_trail():
		var tone: Color = data.weapons[fighter.style]["color"]
		var wanted := tone.lerp(Color.WHITE, 0.45)
		if not _model.trail_color.is_equal_approx(wanted):
			_model.trail_color = wanted
	var facing: Vector2 = fighter.skill_view.get("shot_aim",Vector2(fighter.direction)) if fighter.style=="bow" and fighter.state==Fighter.State.ATTACK else Vector2(fighter.direction)
	_model.set_pose(kind, amount, speed, body.grounded, facing, lying, phase, clip, fighter.style)
	_show_skill_pack(body, fighter)
	_show_model_flash()


## The only whole-body colour on a character model: the hit flash, on for FLASH_SECONDS, then cleared.
func _show_model_flash() -> void:
	var on := _flash > 0.0
	if on == _model_flash_on:
		return
	_model_flash_on = on
	_model.tint(FLASH_TINT if on else Color(0, 0, 0, 0))


## An ultimate with an imported skill pack (data/combat/ultimates.json): the pack's own character
## clip is played on our rig and its effect stands where the skill was cast, facing the way the
## fighter faced then. Both run on the move's frames (move_frame / 60 = seconds into the pack's
## clip), so hit-stop and attack speed keep picture and rules together. When the move ends the
## effect is left behind to finish its smoke and debris on its own clock.
func skill_weapon_point() -> Vector3:
	if _model != null:
		for blade in _model._blades:
			var tip = blade.get("tip")
			if is_instance_valid(tip):
				return tip.global_position
	return position + Vector3(0, 0.15, 0)


## The class skill clip window (old skill packs and Skill Lab casts were deleted with the old skill system).
func _show_skill_pack(_body: SimBody, fighter: Fighter) -> void:
	_show_class_skill(fighter)


## The middle of the shown body in world space: the hips bone of the model (it rises with a leaping
## skill clip), or a point a little above the feet when the model has no such bone. Used by the
## ultimate camera to keep the caster in frame.
func body_center() -> Vector3:
	if not is_instance_valid(_center_skeleton) and _model != null:
		var found := _model.find_children("*", "Skeleton3D", true, false)
		if not found.is_empty():
			_center_skeleton = found[0]
			_center_bone = _center_skeleton.find_bone("Hips")
	if is_instance_valid(_center_skeleton) and _center_bone >= 0:
		return _center_skeleton.global_transform * _center_skeleton.get_bone_global_pose(_center_bone).origin
	return global_position + Vector3(0.0, 0.85, 0.0)


## Hides or shows the weapon in the hand (a thrown spear is in the air, drawn by the pack's effect).
func _show_thrown_weapon(in_hand: bool) -> void:
	if _model == null or not _model.has_method("set_weapon_visible") or _weapon_hidden == (not in_hand):
		return
	_weapon_hidden = not in_hand
	_model.set_weapon_visible(in_hand)


## Small colored tags above the head for every buff and debuff, and a stagger or slump for the
## effects that stop the fighter (stun wobbles, sleep slumps).
func _show_effects(fighter: Fighter, data: CombatData) -> void:
	if data == null:
		return
	_show_status_vfx(fighter, data)
	for id in _status_tags.keys():
		if not fighter.effects.has(id) or not fighter.is_alive():
			_status_tags[id].queue_free()
			_status_tags.erase(id)
	var ids := fighter.effects.keys()
	ids.sort()
	var base_y := _height + (0.75 if show_health_bar else 0.35)
	var index := 0
	if fighter.is_alive() and show_health_bar:  # the player's own effects are in the HUD
		for id in ids:
			var definition: Dictionary = data.effects[id]
			var tag: Label3D = _status_tags.get(id)
			if tag == null:
				tag = Label3D.new()
				tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				tag.font_size = 40
				tag.pixel_size = 0.008
				tag.outline_size = 10
				tag.no_depth_test = true
				tag.modulate = definition["color"]
				add_child(tag)
				_status_tags[id] = tag
			var stacks := int(fighter.effects[id]["stacks"])
			tag.text = ("%s x%d" % [definition["name"], stacks]) if stacks > 1 else str(definition["name"])
			tag.position = Vector3(0.0, base_y + float(index) * STATUS_LINE, 0.0)
			index += 1
	var asleep := false
	var stunned := false
	for id in ids:
		asleep = asleep or data.effects[id]["control"] == "sleep"
		stunned = stunned or data.effects[id]["control"] == "stun"
	var target_tilt := 0.0
	if asleep:
		target_tilt = -0.35
	elif stunned:
		target_tilt = sin(_clock * 22.0) * 0.08
	_body.rotation.z = lerpf(_body.rotation.z, target_tilt, 0.3)

## Statuses (and the immune ring) as small looping effects (client/status_vfx.gd) instead of a body tint.
## Built on the first status or immune moment.
func _show_status_vfx(fighter: Fighter, data: CombatData) -> void:
	if _status_vfx == null:
		if fighter.effects.is_empty() and (fighter.state == Fighter.State.DOWN or not Combat.is_invulnerable(fighter, data)):
			return
		_status_vfx = StatusVfx.new()
		_status_vfx.name = "StatusVfx"
		add_child(_status_vfx)
	_status_vfx.head_height = _height + (0.95 if show_health_bar else 0.25)
	_status_vfx.size_scale = clampf(maxf(status_visual_size.x, status_visual_size.z) / 0.8, 0.8, 2.2)
	var immune := fighter.state != Fighter.State.DOWN and Combat.is_invulnerable(fighter, data)
	_status_vfx.show_effects(fighter.effects.keys(), data.effects, fighter.is_alive(), immune)


## The status loops shown now: {"head": look, "feet": look} ("" = none). Tests.
func status_looks() -> Dictionary:
	return _status_vfx.shown() if _status_vfx != null else {"head": "", "feet": "", "guard": ""}


## Class skills v2 (design/gdd/class-skills.md 3.1 rule 7): the Studio clip window of the skill being cast, timed from
## the sim's cast start (skill_view.class_cast). The sim moves the body only in the travel frames; the model keeps the
## hips in place. No VFX yet: each skill's `vfx` key (class_skill/<id>) resolves to nothing until the VFX tool fills it.
func _show_class_skill(fighter: Fighter) -> bool:
	var cast: Dictionary = fighter.skill_view.get("class_cast", {})
	if cast.is_empty() or not _model.has_method("show_class_skill_frame"):
		if _class_skill_shown:
			_class_skill_shown = false
			_model.clear_class_skill_frame()
		return false
	if str(cast.get("skill", "")) != _class_skill_id or int(cast.get("start", 0)) != _class_skill_start:
		_class_skill_id = str(cast.get("skill", ""))
		_class_skill_start = int(cast.get("start", 0))
		_class_skill_clock = float(cast.get("now", _class_skill_start))
	# the sim tick plus the time since it was published (render frames run between ticks)
	var now := float(cast.get("now", 0))
	if cast.has("view_tick"):
		_class_skill_clock = float(cast["view_tick"])  # online remote: the tick its body is drawn at (logic/net/skill_net.gd)
	elif now > _class_skill_clock:
		_class_skill_clock = now
	else:
		_class_skill_clock = minf(_class_skill_clock + get_process_delta_time() * 60.0, now + 1.0)
	var pose: Dictionary = ClassSkillMotion.frame(cast, _class_skill_clock)
	if pose.is_empty() or not _model.show_class_skill_frame(pose):
		return false
	_class_skill_shown = true
	return true



## The race ground marker (design/gdd/races-and-classes.md 3.8): a squad card's thin race-coloured ring at its feet
## (client/race_ground_ring.gd), hidden while the fighter is down.
var _race_ring = null  ## client/race_ground_ring.gd

func _show_race_ring(fighter: Fighter) -> void:
	var race := str(fighter.race_state.get("race", "")) if fighter.team == "player" else ""
	if race.is_empty():
		if _race_ring != null:
			_race_ring.visible = false
		return
	if _race_ring == null or _race_ring.race != race:
		if _race_ring != null:
			_race_ring.queue_free()
		_race_ring = preload("res://client/race_ground_ring.gd").new()
		_race_ring.name = "RaceRing"
		_race_ring.setup(race)
		add_child(_race_ring)
	_race_ring.visible = fighter.is_alive()
