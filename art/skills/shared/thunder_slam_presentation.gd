extends Node3D
## Materials and impact light over the authored ThunderSlamVFX. Zero new tri.

const ENERGY := preload("res://art/skills/shared/shaders/thunder_energy.gdshader")
const FIELD := preload("res://art/skills/shared/shaders/thunder_field.gdshader")
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
	_light.position = Vector3(0, 0.7, float(config.get("attack", {}).get("range_m", 3.01346655)))
	_light.light_color = Color(0.08, 0.32, 1.0)
	_light.omni_range = 8.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
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
			if not original or not original.resource_name.begins_with("Thunder"):
				continue
			var tag := original.resource_name
			var mat := ShaderMaterial.new()
			mat.resource_name = tag + "_Godot"
			mat.shader = ENERGY
			if original is BaseMaterial3D:
				mat.set_shader_parameter("tint", original.albedo_color)
			var kind := 0.0
			var energy := 1.25
			if tag.begins_with("ThunderGround"):
				if tag.begins_with("ThunderGroundSpark"):
					kind = 7.0
					energy = 3.1
					mat.render_priority = 8
				else:
					mat.shader = FIELD
					kind = 4.0
					energy = 0.04
					mat.render_priority = -20
			elif tag.begins_with("ThunderCore"):
				kind = 1.0
				energy = 1.9
			elif tag.begins_with("ThunderRing"):
				kind = 2.0
				energy = 1.05
			elif tag.begins_with("ThunderSpark") or tag.begins_with("ThunderOrb"):
				kind = 3.0
				energy = 1.6
			elif tag.begins_with("ThunderFlash"):
				kind = 4.0
				energy = 3.0
			elif tag.begins_with("ThunderHaze"):
				kind = 5.0
				energy = 0.50
			elif tag.begins_with("ThunderShockwave"):
				kind = 6.0
				energy = 1.15
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
		var start := 2.80
		var end := 3.4
		if tag.begins_with("ThunderFlash"):
			start = 1.24
			end = 1.40
		elif tag.begins_with("ThunderHaze"):
			start = 2.20
			end = 3.15
		elif tag.begins_with("ThunderSpark"):
			start = 2.35
			end = 3.20
		elif tag.begins_with("ThunderGround"):
			start = 3.12
		var mat: ShaderMaterial = row["material"]
		mat.set_shader_parameter("cast_time", time_s)
		mat.set_shader_parameter("opacity", 1.0 - smoothstep(start + _impact - 1.12, end + _impact - 1.12, time_s))
	if _light:
		_light.light_energy = 0.0 if time_s < _impact else 3.3 * exp(-(time_s-_impact)*4.2)
	if is_instance_valid(_camera):
		var shake := 0.0
		if time_s >= _impact and time_s < _impact + 0.24:
			shake = 0.049 * (1.0-(time_s-_impact)/0.24)
		_camera.h_offset = _base_h + sin(time_s*141.0)*shake
		_camera.v_offset = _base_v + cos(time_s*127.0)*shake

func _exit_tree() -> void:
	if is_instance_valid(_camera):
		_camera.h_offset = _base_h
		_camera.v_offset = _base_v
