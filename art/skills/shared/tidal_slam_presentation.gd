extends Node3D
## Water materials over Blender-authored TidalSlamVFX. Adds zero triangles.

const SURFACE_SHADER := preload("res://art/skills/shared/shaders/tidal_surface.gdshader")
const SPRAY_SHADER := preload("res://art/skills/shared/shaders/tidal_spray.gdshader")
var config: Dictionary = {}
var _materials: Array[Dictionary] = []
var _light: OmniLight3D
var _camera: Camera3D
var _base_h := 0.0
var _base_v := 0.0
var _impact := 1.12

func _ready() -> void:
	_impact = float(config.get("flight", {}).get("arrival_time_s", 1.12))
	_adapt(get_parent())
	_light = OmniLight3D.new()
	_light.position = Vector3(0, 0.65, float(config.get("attack", {}).get("range_m", 3.01346655)))
	_light.light_color = Color(0.14, 0.72, 1.0)
	_light.omni_range = 8.0
	_light.shadow_enabled = false
	_light.light_energy = 0.0
	add_child(_light)
	_camera = get_viewport().get_camera_3d()
	if _camera and config.get("camera_effects_enabled",true):
		_base_h = _camera.h_offset
		_base_v = _camera.v_offset
	if not config.get("camera_effects_enabled",true):_camera = null
	advance(0.0)

func _adapt(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		for surface in node.mesh.get_surface_count():
			var original: Material = node.mesh.surface_get_material(surface)
			if not original or not original.resource_name.begins_with("Tidal"):
				continue
			var tag := original.resource_name
			var mat := ShaderMaterial.new()
			mat.resource_name = tag + "_Godot"
			mat.shader = SPRAY_SHADER if tag.begins_with("TidalMist") else SURFACE_SHADER
			if original is BaseMaterial3D:
				mat.set_shader_parameter("tint", original.albedo_color)
				if tag.begins_with("TidalMist") and original.albedo_texture:
					mat.set_shader_parameter("spray_texture", original.albedo_texture)
			if not tag.begins_with("TidalMist"):
				var kind := 0.0
				var energy := 0.35
				if tag.begins_with("TidalFoam") or tag.begins_with("TidalRipple"):
					kind = 1.0
					energy = 0.65
				elif tag.begins_with("TidalFlash"):
					kind = 2.0
					energy = 2.0
				elif tag.begins_with("TidalDrop"):
					kind = 3.0
					energy = 0.40
				elif tag.begins_with("TidalPool"):
					kind = 4.0
					energy = 0.04
					mat.render_priority = -20
				elif tag.begins_with("TidalFlight"):
					kind = 5.0
					energy = 1.5
				mat.set_shader_parameter("surface_kind", kind)
				mat.set_shader_parameter("energy", energy)
			mat.set_shader_parameter("impact_time", _impact)
			node.set_surface_override_material(surface, mat)
			_materials.append({"tag": tag, "material": mat})
	for child in node.get_children():
		if child != self:
			_adapt(child)

func advance(time_s: float) -> void:
	for row in _materials:
		var tag: String = row["tag"]
		var mat: ShaderMaterial = row["material"]
		var start := 3.12
		var end := 3.4
		if tag.begins_with("TidalJet"):
			start = 1.50
			end = 1.90
		elif tag.begins_with("TidalWater"):
			start = 1.90
			end = 2.25
		elif tag.begins_with("TidalMist"):
			start = 2.40
			end = 3.18
		elif tag.begins_with("TidalFlash"):
			start = 1.28
			end = 1.40
		elif tag.begins_with("TidalFoam") or tag.begins_with("TidalRipple"):
			start = 2.75
			end = 3.35
		mat.set_shader_parameter("cast_time", time_s)
		mat.set_shader_parameter("opacity", 1.0 - smoothstep(start + _impact - 1.12, end + _impact - 1.12, time_s))
	if _light:
		_light.light_energy = 0.0 if time_s < _impact else 2.3 * exp(-(time_s-_impact)*4.5)
	if is_instance_valid(_camera):
		var shake := 0.0
		if time_s >= _impact and time_s < _impact + 0.23:
			shake = 0.042 * (1.0-(time_s-_impact)/0.23)
		_camera.h_offset = _base_h + sin(time_s*141.0)*shake
		_camera.v_offset = _base_v + cos(time_s*127.0)*shake

func _exit_tree() -> void:
	if is_instance_valid(_camera):
		_camera.h_offset = _base_h
		_camera.v_offset = _base_v
