class_name WeaponSkillController
extends Node

signal skill_event(skill_id: StringName, event_name: StringName)
signal attack_requested(skill_id: StringName, event_name: StringName, context: Dictionary)
signal locomotion_released(skill_id: StringName)
signal skill_finished(skill_id: StringName)
signal dash_blocked(skill_id: StringName, collision: KinematicCollision3D)

@export var character_root: Node3D
@export var facing_source: Node3D
@export var cast_origin_source: Node3D
@export var skeleton: Skeleton3D
@export var animator: AnimationPlayer
@export var equipped_weapon_type: StringName = &"blade"
@export var return_animation: StringName = &"StandBlade"
# Optional world-space height; zero uses reference height * visual root scale.
@export var body_height_override_m: float = 0.0
@export_flags_3d_physics var target_collision_mask: int = 0
@export var self_collision_root: Node
@export var movement_body: CharacterBody3D
@export var held_weapon: Node3D
var equipped_pack: WeaponSkillPack
const INFERNO_PRESENTATION := preload("res://art/skills/shared/inferno_spectacle.gd")
const SOLAR_PRESENTATION := preload("res://art/skills/shared/solar_slam_presentation.gd")
const TIDAL_SLAM_PRESENTATION := preload("res://art/skills/shared/tidal_slam_presentation.gd")
const THUNDER_SLAM_PRESENTATION := preload("res://art/skills/shared/thunder_slam_presentation.gd")
const EARTH_SLAM_PRESENTATION := preload("res://art/skills/shared/earth_slam_presentation.gd")
const SPEAR_DELIVERY := preload("res://art/skills/shared/spear_throw_recall.gd")
const SHADOW_PRESENTATION := preload("res://art/skills/shared/shadow_extraction_presentation.gd")
var _presentation: Node3D
var _weapon_presentation: Node3D
var _effect: Node3D
var _active := false
var _actor_locked := false
var _elapsed := 0.0
var _dash_finished := false
var _next_event := 0
var _animation_key: StringName
var _cast_origin := Vector3.ZERO
var _cast_forward := Vector3(0, 0, 1)
var _cast_basis := Basis.IDENTITY
var _body_height_m := 0.0
var _events: Array = []
var _hit_ids: Dictionary = {}
var _dash_start_position := Vector3.ZERO
var _dash_actual_distance := 0.0
var _dash_blocked := false
var _effect_scale := 1.0

func _ready() -> void:
	if animator:
		animator.animation_finished.connect(_on_finished)

func equip_skill(pack: WeaponSkillPack) -> bool:
	if pack and (pack.required_weapon_type != equipped_weapon_type or not pack.has_forward_ultimate_contract()):
		push_error("Invalid skill contract or weapon type: " + String(pack.skill_id))
		return false
	cancel_skill()
	if animator and animator.has_animation_library(&"weapon_skill"):
		animator.remove_animation_library(&"weapon_skill")
	equipped_pack = null
	if not pack:
		return true
	if not animator or not skeleton or not character_root or not pack.animation_carrier:
		return false
	var carrier := pack.animation_carrier.instantiate()
	var source := _find_player(carrier)
	if not source or not source.has_animation(pack.animation_name):
		push_error("Missing carrier clip: " + String(pack.animation_name))
		carrier.free()
		return false
	var clip: Animation = source.get_animation(pack.animation_name).duplicate(true)
	clip.loop_mode = Animation.LOOP_NONE
	var animation_root := animator.get_node(animator.root_node)
	var mapped_bones: Dictionary = {}
	var missing_bones: Dictionary = {}
	for track in range(clip.get_track_count() - 1, -1, -1):
		var path := clip.track_get_path(track)
		if path.get_subname_count() == 0:
			clip.remove_track(track)
			continue
		var bone := String(path.get_subname(0))
		if skeleton.find_bone(bone) < 0:
			missing_bones[bone] = true
			clip.remove_track(track)
			continue
		mapped_bones[bone] = true
		clip.track_set_path(track, NodePath(String(animation_root.get_path_to(skeleton)) + ":" + bone))
	# Do not silently equip an empty or partly mapped animation on another rig.
	if mapped_bones.is_empty() or not missing_bones.is_empty():
		push_error("Skill rig mapping failed; missing bones: " + str(missing_bones.keys()))
		carrier.free()
		return false
	var library := AnimationLibrary.new()
	library.add_animation(pack.animation_name, clip)
	animator.add_animation_library(&"weapon_skill", library)
	_animation_key = StringName("weapon_skill/" + String(pack.animation_name))
	equipped_pack = pack
	carrier.free()
	return true

func set_weapon_type(value: StringName) -> void:
	equipped_weapon_type = value
	if equipped_pack and equipped_pack.required_weapon_type != value:
		equip_skill(null)

func cast_ultimate(forward_world: Vector3 = Vector3.ZERO) -> bool:
	if _active or not equipped_pack or equipped_pack.required_weapon_type != equipped_weapon_type:
		return false
	if not equipped_pack.has_forward_ultimate_contract():
		return false
	if equipped_pack.manifest().get("weapon_delivery",{}).get("kind","")=="throw_recall" and not is_instance_valid(held_weapon):
		push_error("Assign the equipped right-hand weapon before casting a throw/recall skill")
		return false
	var config := equipped_pack.attack_config()
	if config["caster_motion"] == "forward_dash" and not is_instance_valid(movement_body):
		return false
	var source := facing_source if facing_source else character_root
	var forward := forward_world if not forward_world.is_zero_approx() else source.global_basis * Vector3(0, 0, 1)
	forward.y = 0.0
	if forward.is_zero_approx() or not forward.is_finite():
		return false
	_cast_forward = forward.normalized()
	_cast_origin = cast_origin_source.global_position if cast_origin_source else character_root.global_position
	# The asset is authored model-forward +Z; never substitute camera -Z.
	_cast_basis = Basis(Vector3.UP.cross(_cast_forward).normalized(), Vector3.UP, _cast_forward)
	var reference_height := float(config["reference_body_height_m"])
	_body_height_m = body_height_override_m if body_height_override_m > 0.0 else reference_height * absf(character_root.global_basis.get_scale().y)
	if not is_finite(_body_height_m) or _body_height_m <= 0.0:
		return false
	_active = true
	_actor_locked = true
	_elapsed = 0.0
	_dash_finished = false
	_next_event = 0
	_events = equipped_pack.gameplay_events().duplicate(true)
	_hit_ids.clear()
	_dash_actual_distance = 0.0
	_dash_blocked = false
	if is_instance_valid(movement_body):
		_dash_start_position = movement_body.global_position
	if equipped_pack.vfx_scene:
		_effect = Node3D.new() if equipped_pack.skill_id == &"blade_inferno_ultimate" else equipped_pack.vfx_scene.instantiate() as Node3D
		_disable_effect_shadows(_effect)
		character_root.get_parent().add_child(_effect)
		# A visual character root may live under the moving physics body.
		# Keep this effect in world space even when that parent walks away.
		_effect.set_as_top_level(true)
		_effect_scale = _body_height_m / reference_height
		_effect.global_transform = Transform3D(_cast_basis.scaled(Vector3.ONE * _effect_scale), _cast_origin)
		if equipped_pack.is_shadow_extraction():
			_presentation = SHADOW_PRESENTATION.new()
			_presentation.config = equipped_pack.manifest()
			_presentation.receiver_skeleton = skeleton
			_presentation.hero_root = character_root
			_effect.add_child(_presentation)
		elif equipped_pack.skill_id == &"blade_inferno_ultimate":
			_presentation = INFERNO_PRESENTATION.new()
			_presentation.config = equipped_pack.manifest()
			_effect.add_child(_presentation)
		elif equipped_pack.skill_id in [&"blade_solar_slam_ultimate",&"spear_fire_sky_throw_ultimate"]:
			_presentation = SOLAR_PRESENTATION.new()
			var visual_config := equipped_pack.manifest().duplicate(true)
			if equipped_pack.skill_id == &"spear_fire_sky_throw_ultimate":
				visual_config["camera_effects_enabled"] = not multiplayer.has_multiplayer_peer() or source.is_multiplayer_authority()
				_presentation.receiver_skeleton = skeleton
			_presentation.config = visual_config
			_effect.add_child(_presentation)
		elif equipped_pack.skill_id in [&"blade_tidal_slam_ultimate", &"spear_water_sky_throw_ultimate"]:
			_presentation = TIDAL_SLAM_PRESENTATION.new()
			var elemental_config := equipped_pack.manifest().duplicate(true)
			if equipped_pack.is_spear_sky_throw():
				elemental_config["camera_effects_enabled"] = not multiplayer.has_multiplayer_peer() or source.is_multiplayer_authority()
			_presentation.config = elemental_config
			_effect.add_child(_presentation)
		elif equipped_pack.skill_id in [&"blade_thunder_slam_ultimate", &"spear_thunder_sky_throw_ultimate"]:
			_presentation = THUNDER_SLAM_PRESENTATION.new()
			var elemental_config := equipped_pack.manifest().duplicate(true)
			if equipped_pack.is_spear_sky_throw():
				elemental_config["camera_effects_enabled"] = not multiplayer.has_multiplayer_peer() or source.is_multiplayer_authority()
			_presentation.config = elemental_config
			_effect.add_child(_presentation)
		elif equipped_pack.skill_id in [&"blade_earth_slam_ultimate", &"spear_earth_sky_throw_ultimate"]:
			_presentation = EARTH_SLAM_PRESENTATION.new()
			var elemental_config := equipped_pack.manifest().duplicate(true)
			if equipped_pack.is_spear_sky_throw():
				elemental_config["camera_effects_enabled"] = not multiplayer.has_multiplayer_peer() or source.is_multiplayer_authority()
			_presentation.config = elemental_config
			_effect.add_child(_presentation)
		var player := _find_player(_effect)
		if player:
			for name in player.get_animation_list():
				if name != &"RESET":
					player.get_animation(name).loop_mode = Animation.LOOP_NONE
					player.play(name)
					break
	if equipped_pack.manifest().get("weapon_delivery",{}).get("kind","")=="throw_recall":
		_weapon_presentation = SPEAR_DELIVERY.new()
		_weapon_presentation.config = equipped_pack.manifest()
		_weapon_presentation.skeleton = skeleton
		_weapon_presentation.animator = animator
		_weapon_presentation.held_weapon = held_weapon
		_weapon_presentation.cast_basis = _cast_basis
		_weapon_presentation.cast_origin = _cast_origin
		_weapon_presentation.visual_scale = _effect_scale
		character_root.get_parent().add_child(_weapon_presentation)
		_weapon_presentation.weapon_event.connect(func(event: StringName): skill_event.emit(equipped_pack.skill_id,event))
	animator.play(_animation_key, 0.08)
	skill_event.emit(equipped_pack.skill_id, &"charge")
	return true

func attack_context(range_factor: float = 1.0) -> Dictionary:
	if not equipped_pack or _body_height_m <= 0.0:
		return {}
	var config := equipped_pack.attack_config()
	var reach := float(config["range_body_lengths"]) * _body_height_m * clampf(range_factor, 0.05, 1.0)
	var near := float(config["near_body_lengths"]) * _body_height_m
	if config["caster_motion"] == "forward_dash":
		reach = minf(reach, _dash_actual_distance)
		if reach <= near:
			return {}
	var width := float(config["width_body_lengths"]) * _body_height_m
	var height := float(config["height_body_lengths"]) * _body_height_m
	var center := _cast_origin + _cast_forward * ((near + reach) * 0.5) + Vector3.UP * (height * 0.5)
	return {"origin": _cast_origin, "forward": _cast_forward, "body_height_m": _body_height_m,
		"range_m": reach, "full_range_m": _body_height_m * float(config["range_body_lengths"]),
		"box_size_m": Vector3(width, height, maxf(0.01, reach - near)),
		"query_transform": Transform3D(_cast_basis, center),
		"max_hits_per_target_per_cast": int(config["max_hits_per_target_per_cast"]),
		"caster_motion": config["caster_motion"], "vfx_motion": "authored_in_glb",
		"actual_dash_distance_m": _dash_actual_distance, "dash_blocked": _dash_blocked}

func suppresses_locomotion() -> bool:
	return _actor_locked

func _apply_dash_motion(time: float) -> void:
	if _dash_finished or equipped_pack.attack_config()["caster_motion"] != "forward_dash":
		return
	if not is_instance_valid(movement_body):
		cancel_skill()
		return
	var movement: Dictionary = equipped_pack.manifest()["movement"]
	_dash_finished = time >= float(movement["end_time_s"])
	var u := clampf((time - float(movement["start_time_s"])) / (float(movement["end_time_s"]) - float(movement["start_time_s"])), 0.0, 1.0)
	var goal := _body_height_m * 2.0 * (u * u * (3.0 - 2.0 * u))
	var traveled := maxf(0.0, (movement_body.global_position - _dash_start_position).dot(_cast_forward))
	var remaining := maxf(0.0, goal - traveled)
	if not _dash_blocked and remaining > 0.00001:
		var collision := movement_body.move_and_collide(_cast_forward * remaining)
		if collision:
			_dash_blocked = true
			dash_blocked.emit(equipped_pack.skill_id, collision)
			if not _active:
				return
	_dash_actual_distance = clampf((movement_body.global_position - _dash_start_position).dot(_cast_forward), 0.0, _body_height_m * 2.0)
	# VFX is frozen at cast origin; shorten its authored wake if a wall stops
	# the body. Never translate the effect root along the dash a second time.
	if is_instance_valid(_effect) and _dash_blocked and goal > 0.00001:
		var ratio := clampf(_dash_actual_distance / goal, 0.0, 1.0)
		_effect.global_transform = Transform3D(_cast_basis * Basis.from_scale(Vector3(_effect_scale, _effect_scale, _effect_scale * ratio)), _cast_origin)

# Call in a physics tick (attack_requested is emitted from _physics_process).
# Collision candidates are not damage: the game still resolves teams, walls,
# health and hit receivers, then calls mark_target_hit after an accepted hit.
func query_forward_targets(context: Dictionary, max_results: int = 64) -> Array[Dictionary]:
	if target_collision_mask == 0 or context.is_empty():
		return []
	var shape := BoxShape3D.new()
	shape.size = context["box_size_m"]
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = context["query_transform"]
	query.collision_mask = target_collision_mask
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var excluded: Array[RID] = []
	_collect_self_rids(self_collision_root if self_collision_root else character_root, excluded)
	var parent := character_root.get_parent()
	while parent:
		if parent is CollisionObject3D:
			var rid: RID = parent.get_rid()
			if not excluded.has(rid):
				excluded.append(rid)
		parent = parent.get_parent()
	query.exclude = excluded
	return character_root.get_world_3d().direct_space_state.intersect_shape(query, max_results)

func can_hit_target(receiver: Object) -> bool:
	return is_instance_valid(receiver) and not _hit_ids.has(receiver.get_instance_id())

func mark_target_hit(receiver: Object) -> void:
	if is_instance_valid(receiver):
		_hit_ids[receiver.get_instance_id()] = true

func cancel_skill() -> void:
	if is_instance_valid(_presentation) and _presentation.has_method("restore_eyes"):
		_presentation.restore_eyes()
	if is_instance_valid(_weapon_presentation):
		if is_instance_valid(held_weapon):held_weapon.visible = true
		_weapon_presentation.queue_free()
	_weapon_presentation = null
	if is_instance_valid(_effect):
		_effect.queue_free()
	_effect = null
	_presentation = null
	if _actor_locked and animator and animator.current_animation == _animation_key:
		if animator.has_animation(return_animation):
			animator.play(return_animation, 0.1)
		else:
			animator.stop()
	_active = false
	_actor_locked = false
	_events.clear()
	_body_height_m = 0.0
	_hit_ids.clear()

func _physics_process(delta: float) -> void:
	if not _active or not equipped_pack:
		return
	if _actor_locked and animator.current_animation != _animation_key:
		cancel_skill()
		return
	_elapsed += delta
	if is_instance_valid(_weapon_presentation):
		_weapon_presentation.advance(_elapsed)
	if is_instance_valid(_presentation):
		_presentation.advance(_elapsed)
	_apply_dash_motion(_elapsed)
	if not _active:
		return
	while _next_event < _events.size() and _elapsed >= float(_events[_next_event]["time_s"]):
		var event: Dictionary = _events[_next_event]
		_next_event += 1
		var name := StringName(event["name"])
		var context := attack_context(float(event.get("range_factor", 1.0)))
		skill_event.emit(equipped_pack.skill_id, name)
		if not _active:
			return
		attack_requested.emit(equipped_pack.skill_id, name, context)
		if not _active:
			return

	if _actor_locked and _elapsed >= float(equipped_pack.control_config()["locomotion_resume_time_s"]):
		_release_locomotion()
	if _active and _elapsed >= float(equipped_pack.manifest()["duration_s"]):
		var finished_id := equipped_pack.skill_id
		cancel_skill()
		skill_finished.emit(finished_id)

func _release_locomotion() -> void:
	if not _actor_locked:
		return
	_actor_locked = false
	# Release before emitting so a game listener can play Run/Walk immediately.
	# The independent cast clock still owns VFX, hit events and frozen query data.
	if animator and animator.current_animation == _animation_key:
		if animator.has_animation(return_animation):
			animator.play(return_animation, float(equipped_pack.control_config()["blend_out_s"]))
		else:
			animator.stop()
	locomotion_released.emit(equipped_pack.skill_id)

func _on_finished(name: StringName) -> void:
	if _active and name == _animation_key:
		_release_locomotion()

func _collect_self_rids(root: Node, result: Array[RID]) -> void:
	if root is CollisionObject3D:
		result.append(root.get_rid())
	for child in root.get_children():
		_collect_self_rids(child, result)

func _find_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var found := _find_player(child)
		if found:
			return found
	return null

func _disable_effect_shadows(root: Node) -> void:
	if root is GeometryInstance3D:
		root.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in root.get_children():
		_disable_effect_shadows(child)
