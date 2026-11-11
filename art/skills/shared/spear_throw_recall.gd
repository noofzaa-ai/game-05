extends Node3D
## World-space weapon delivery on the independent cast clock. Catching restores
## the equipped instance; the animated carrier supplies the hand and fingers.
signal weapon_event(event: StringName)
var config: Dictionary = {}
var skeleton: Skeleton3D
var animator: AnimationPlayer
var held_weapon: Node3D
var cast_basis := Basis.IDENTITY
var cast_origin := Vector3.ZERO
var visual_scale := 1.0
var _base := Transform3D.IDENTITY
var _main := Vector3.ZERO
var _tip := Vector3.ZERO
var _center := Vector3.ZERO
var _socket := -1
var _projectile: Node3D
var _flight_start := Transform3D.IDENTITY
var _landing := Transform3D.IDENTITY
var _released := false
var _impacted := false
var _recalling := false
var _caught := false
var _light: OmniLight3D
var _trail: MeshInstance3D
var _sparks: Array[MeshInstance3D] = []
var _camera: Camera3D
var _events: Array[Dictionary] = []
var _time := 0.0
var _catch_error_m := -1.0

func _marker(node: Node, tag: String) -> Node3D:
	if node is Node3D and (String(node.name)==tag or String(node.get_meta("zorx_point_type",""))==tag):return node
	for child in node.get_children():
		var found := _marker(child,tag)
		if found:return found
	return null

func _ready() -> void:
	set_as_top_level(true)
	global_transform = Transform3D.IDENTITY
	if not is_instance_valid(held_weapon) or not skeleton or not animator:
		push_error("Spear recall needs the equipped weapon, skeleton and animator")
		return
	_socket = skeleton.find_bone("attach_weapon.R")
	var main := _marker(held_weapon,"grip_main")
	var tip := _marker(held_weapon,"trail_end")
	if _socket<0 or not main or not tip:
		push_error("Spear recall needs the actual attach_weapon.R/grip_main/trail_end")
		return
	_main = held_weapon.global_transform.affine_inverse()*main.global_position
	_tip = held_weapon.global_transform.affine_inverse()*tip.global_position
	_center = (_main+_tip)*0.5
	_base = held_weapon.transform
	_projectile = held_weapon.duplicate() as Node3D
	add_child(_projectile)
	_projectile.visible = false
	_camera = get_viewport().get_camera_3d()
	_build_accents()

func _hand_transform() -> Transform3D:
	return skeleton.global_transform*skeleton.get_bone_global_pose(_socket)*_base

func _event(name: StringName) -> void:
	_events.append({"event":String(name),"time_s":_time})
	weapon_event.emit(name)

func advance(time_s: float) -> void:
	_time = time_s
	if not is_instance_valid(_projectile) or not is_instance_valid(held_weapon):return
	var delivery: Dictionary = config["weapon_delivery"]
	var release := float(delivery["release_time_s"])
	var impact := float(delivery["impact_time_s"])
	var recall := float(delivery["recall_time_s"])
	var catch_time := float(delivery["catch_time_s"])
	if not _released and time_s>=release:
		var current := animator.current_animation_position
		animator.seek(release,true)
		_flight_start = _hand_transform()
		animator.seek(current,true)
		var endpoint := cast_origin+cast_basis*Vector3(0,-float(delivery["tip_burial_depth_m"])*visual_scale,float(config["attack"]["range_m"])*visual_scale)
		var direction := (endpoint-(_flight_start*_main)).normalized()
		var axis := (_flight_start.basis*(_tip-_main)).normalized()
		var basis := Basis(Quaternion(axis,direction))*_flight_start.basis
		_landing = Transform3D(basis,endpoint-basis*_tip)
		_projectile.global_transform = _flight_start
		_projectile.visible = true
		held_weapon.visible = false
		_released = true
		_event(&"spear_release")
	if _released and not _recalling and not _caught:
		var u := clampf((time_s-release)/(impact-release),0.0,1.0)
		_projectile.global_transform = _flight_start.interpolate_with(_landing,u)
		if time_s>=impact and not _impacted:
			_projectile.global_transform = _landing
			_impacted = true
			_event(&"spear_ground_contact")
	if not _recalling and not _caught and time_s>=recall:
		_recalling = true
		_event(&"spear_recall")
	if _recalling and not _caught:
		var u := clampf((time_s-recall)/(catch_time-recall),0.0,1.0)
		var eased := u*u*(3.0-2.0*u)
		var destination := _hand_transform()
		var center := (_landing*_center).lerp(destination*_center,eased)
		center += Vector3.UP*sin(PI*u)*float(delivery["recall_arc_height_m"])*visual_scale
		center += cast_basis.x*sin(PI*u)*float(delivery["recall_side_arc_m"])*visual_scale
		var align := smoothstep(0.58,1.0,u)
		var spin := Basis(Quaternion(cast_basis.x,TAU*float(delivery["spin_revolutions"])*eased))
		var basis := spin*_landing.basis.slerp(destination.basis,align)
		_projectile.global_transform = Transform3D(basis,center-basis*_center)
		if time_s>=catch_time:
			_projectile.global_transform = destination
			_catch_error_m = (_projectile.global_transform*_main-(skeleton.global_transform*skeleton.get_bone_global_pose(_socket)).origin).length()
			_projectile.visible = false
			held_weapon.visible = true
			_caught = true
			_recalling = false
			_event(&"spear_catch")
	_update_accents(time_s)

func _build_accents() -> void:
	var hot := StandardMaterial3D.new()
	hot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var accent := Color(String(config.get("weapon_delivery",{}).get("accent_color","#ff6b09")))
	hot.albedo_color = accent
	hot.emission_enabled = true
	hot.emission = accent if config.get("element","fire") != "fire" else Color(1,.26,.015)
	hot.emission_energy_multiplier = 2.0
	hot.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in range(48):
		var quad := QuadMesh.new()
		quad.size = Vector2(.018,.045)*visual_scale
		quad.material = hot
		var spark := MeshInstance3D.new()
		spark.mesh = quad
		spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(spark)
		_sparks.append(spark)
	_trail = MeshInstance3D.new()
	_trail.mesh = ImmediateMesh.new()
	_trail.material_override = hot
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trail)
	_light = OmniLight3D.new()
	_light.light_color = accent if config.get("element","fire") != "fire" else Color(1,.29,.045)
	_light.omni_range = 1.2*visual_scale
	add_child(_light)

func _update_accents(time_s: float) -> void:
	var transform := _projectile.global_transform if _released and not _caught else _hand_transform()
	var tip := transform*_tip
	_light.global_position = tip
	_light.light_energy = .7 if time_s<float(config["weapon_delivery"]["grip_closed_time_s"]) else 0.0
	var mesh := _trail.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if (_released and not _impacted) or _recalling:
		var destination := _hand_transform().origin if _recalling else _landing.origin
		var heading := (destination-transform.origin).normalized()
		var tail := tip-heading*.8*visual_scale
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for axis in [cast_basis.x,Vector3.UP]:
			var w: Vector3 = axis*.025*visual_scale
			for point in [tip-w,tip+w,tail+w,tip-w,tail+w,tail-w]:mesh.surface_add_vertex(point)
		mesh.surface_end()
	for i in _sparks.size():
		var spark := _sparks[i]
		var born := .38+float(i%12)*.018
		var age := fmod(maxf(0.,time_s-born),.32)
		spark.visible = time_s>=born and time_s<float(config["weapon_delivery"]["grip_closed_time_s"]) and (not _impacted or _recalling or _caught)
		if spark.visible:
			var a := float(i)*2.399963
			spark.global_position = tip+Vector3(cos(a),.6+float(i%5)*.15,sin(a))*age*.6*visual_scale
			if is_instance_valid(_camera):spark.look_at(_camera.global_position,Vector3.UP)
			spark.scale = Vector3.ONE*(1.-age/.32)

func snapshot() -> Dictionary:
	var tip_world := _projectile.global_transform*_tip if is_instance_valid(_projectile) else Vector3.ZERO
	return {"released":_released,"impacted":_impacted,"recalling":_recalling,"caught":_caught,"held_visible":held_weapon.visible if is_instance_valid(held_weapon) else false,"projectile_visible":_projectile.visible if is_instance_valid(_projectile) else false,"projectile_position_m":[_projectile.global_position.x,_projectile.global_position.y,_projectile.global_position.z] if is_instance_valid(_projectile) else [],"projectile_tip_world_m":[tip_world.x,tip_world.y,tip_world.z],"catch_marker_error_m":_catch_error_m,"events":_events.duplicate(true)}

func _exit_tree() -> void:
	if is_instance_valid(held_weapon):held_weapon.visible = true
