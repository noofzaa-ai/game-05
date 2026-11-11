extends Node3D
## Material adapter for the authored SolarSlamVFX GLB. Adds no geometry.
## Its transform tracks and mesh silhouettes are supplied by Blender.

const ENERGY_SHADER := preload("res://art/skills/shared/shaders/solar_energy.gdshader")
const SMOKE_SHADER := preload("res://art/skills/shared/shaders/solar_smoke.gdshader")
const GROUND_SHADER := preload("res://art/skills/shared/shaders/solar_ground.gdshader")

var config: Dictionary = {}
var receiver_skeleton: Skeleton3D
var _materials: Array[Dictionary] = []
var _light: OmniLight3D
var _camera: Camera3D
var _base_h_offset := 0.0
var _base_v_offset := 0.0
var _impact := 1.12
var _fade_end := 3.4
var _time_offset := 0.0

func _ready() -> void:
	_impact = float(config.get("flight", {}).get("arrival_time_s", 1.12))
	_time_offset = _impact-1.12
	_fade_end = float(config.get("visual", {}).get("vfx_fade_end_time_s", 3.4))
	_adapt(get_parent())
	_light = OmniLight3D.new()
	_light.position = Vector3(0.0, 0.65, float(config.get("attack", {}).get("range_m", 3.01346655)))
	_light.light_color = Color(1.0, 0.37, 0.055)
	_light.omni_range = 8.0
	_light.omni_attenuation = 1.2
	_light.shadow_enabled = false
	_light.light_energy = 0.0
	add_child(_light)
	_camera = get_viewport().get_camera_3d()
	if not bool(config.get("camera_effects_enabled",true)):_camera = null
	if _camera:
		_base_h_offset = _camera.h_offset
		_base_v_offset = _camera.v_offset
	advance(0.0)

func _adapt(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		for surface in node.mesh.get_surface_count():
			var original: Material = node.mesh.surface_get_material(surface)
			if not original:
				continue
			var tag := original.resource_name
			if not tag.begins_with("Solar"):
				continue
			var replacement := _make_material(tag, original)
			if replacement:
				node.set_surface_override_material(surface, replacement)
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		if child != self:
			_adapt(child)

func _make_material(tag: String, original: Material) -> Material:
	if tag.begins_with("SolarDebris"):
		var debris: Material = original.duplicate()
		return debris
	var material := ShaderMaterial.new()
	material.resource_name = tag + "_Godot"
	if tag.begins_with("SolarGround"):
		material.shader = GROUND_SHADER
		# All decorative surfaces share a skinned batch's sort depth. Draw
		# the mixed charred plane before additive stars/cracks, so it cannot
		# paint over the center flash despite being below it geometrically.
		material.render_priority = -20
		material.set_shader_parameter("ground_kind", 1.0 if tag.begins_with("SolarGroundPlate") else 0.0)
	elif tag.begins_with("SolarSmoke"):
		material.shader = SMOKE_SHADER
		if original is BaseMaterial3D and original.albedo_texture:
			material.set_shader_parameter("smoke_texture", original.albedo_texture)
			material.set_shader_parameter("use_texture", true)
		var smoke_kind := 0.0 if tag.begins_with("SolarSmokeVolume") else 2.0 if tag.begins_with("SolarSmokeBillow") else 1.0
		material.set_shader_parameter("smoke_kind", smoke_kind)
		# Dense hero masses carry the silhouette. Only torn fringe is thin;
		# multiplying every overlapping layer by low alpha made a glassy cloud.
		material.set_shader_parameter("tint", Color(0.72, 0.30, 0.055, 0.94 if smoke_kind == 0.0 else 0.24 if smoke_kind == 2.0 else 0.40))
	else:
		material.shader = ENERGY_SHADER
		var kind := 5.0
		var energy := 1.65
		if tag.begins_with("SolarFlash"):
			kind = 0.0
			energy = 4.4
		elif tag.begins_with("SolarStar"):
			kind = 6.0
			energy = 1.55
		elif tag.begins_with("SolarCore"):
			kind = 1.0
			energy = 2.10
		elif tag.begins_with("SolarRing"):
			kind = 2.0
			energy = 1.15
		elif tag.begins_with("SolarFlame"):
			kind = 3.0
			energy = 1.65
		elif tag.begins_with("SolarCrack"):
			kind = 4.0
			energy = 0.78
		elif tag.begins_with("SolarSpark"):
			kind = 5.0
			energy = 3.2
			# Mixed smoke in the same skin must not paint over tiny hot embers.
			material.render_priority = 12
		material.set_shader_parameter("surface_kind", kind)
		material.set_shader_parameter("energy", energy)
		if original is BaseMaterial3D:
			material.set_shader_parameter("tint", original.albedo_color)
	material.set_shader_parameter("impact_time", _impact)
	_materials.append({"material": material, "tag": tag})
	return material

func advance(time_s: float) -> void:
	for row in _materials:
		var tag: String = row["tag"]
		var end := _fade_end
		var start := 3.0+_time_offset
		if tag.begins_with("SolarCore") or tag.begins_with("SolarFlame"):
			start = 1.65+_time_offset
			end = 2.18+_time_offset
		elif tag.begins_with("SolarSmoke"):
			# Keep the outward peak dense, then expose the ground before the
			# final ember phase. Erosion still leaves unequal detached pieces.
			if tag.begins_with("SolarSmokeVolume"):
				start = _impact + 0.93
				end = minf(_fade_end, _impact + 2.18)
			elif tag.begins_with("SolarSmokeBillow"):
				start = _impact + 0.83
				end = minf(_fade_end, _impact + 1.98)
			else:
				start = _impact + 1.43
		elif tag.begins_with("SolarGround"):
			start = 3.16+_time_offset
		elif tag.begins_with("SolarRing"):
			# Radius is authored independently. Fade light after the peak, then
			# remove the existing rim late without collapsing its footprint.
			start = 3.05+_time_offset
		elif tag.begins_with("SolarStar"):
			start = 3.12+_time_offset
		elif tag.begins_with("SolarFlash"):
			start = 1.31+_time_offset
			end = 1.55+_time_offset
		var opacity := 1.0 - smoothstep(start, end, time_s)
		var material: ShaderMaterial = row["material"]
		material.set_shader_parameter("cast_time", time_s)
		material.set_shader_parameter("opacity", opacity)
		if tag.begins_with("SolarSmoke") and is_instance_valid(receiver_skeleton):
			var bone := _receiver_bone("Hips")
			var center := receiver_skeleton.global_transform * receiver_skeleton.get_bone_global_pose(bone).origin
			center += Vector3.UP * 0.30 * absf(receiver_skeleton.global_basis.get_scale().y)
			material.set_shader_parameter("receiver_world",center)
			material.set_shader_parameter("receiver_radius",1.15 * absf(receiver_skeleton.global_basis.get_scale().y))
			material.set_shader_parameter("receiver_visibility",smoothstep(_impact+.16,_impact+.28,time_s))
	if _light:
		var t := maxf(0.0, time_s - _impact)
		_light.light_energy = 0.0 if time_s < _impact else 4.0 * exp(-t * 3.8)
	if is_instance_valid(_camera):
		var shake := 0.0
		if time_s >= _impact and time_s < _impact + 0.26:
			shake = 0.052 * (1.0 - (time_s - _impact) / 0.26)
		_camera.h_offset = _base_h_offset + sin(time_s * 141.0) * shake
		_camera.v_offset = _base_v_offset + cos(time_s * 127.0) * shake

func _exit_tree() -> void:
	if is_instance_valid(_camera):
		_camera.h_offset = _base_h_offset
		_camera.v_offset = _base_v_offset

func _receiver_bone(short_name: String) -> int:
	for candidate in [short_name, "mixamorig:" + short_name, "mixamorig_" + short_name, "mixamorig" + short_name]:
		var index := receiver_skeleton.find_bone(candidate)
		if index >= 0: return index
	return -1
