extends Node3D
## Stone, dust and impact over Blender-authored EarthSlamVFX. Adds zero tri.

const STONE := preload("res://art/skills/shared/shaders/earth_stone.gdshader")
const DUST := preload("res://art/skills/shared/shaders/earth_dust.gdshader")
const IMPACT_SHADER := preload("res://art/skills/shared/shaders/earth_impact.gdshader")
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
	_light.position = Vector3(0, 0.75, float(config.get("attack", {}).get("range_m", 3.01346655)))
	_light.light_color = Color(1.0, 0.80, 0.52)
	_light.omni_range = 7.0
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
			if not original or not original.resource_name.begins_with("Earth"):
				continue
			var tag := original.resource_name
			var mat := ShaderMaterial.new()
			mat.resource_name = tag + "_Godot"
			mat.shader = IMPACT_SHADER
			if original is BaseMaterial3D:
				mat.set_shader_parameter("tint", original.albedo_color)
			if tag.begins_with("EarthRock"):
				mat.shader = STONE
			elif tag.begins_with("EarthDust"):
				mat.shader = DUST
				var textured := not tag.begins_with("EarthDustVolume")
				mat.set_shader_parameter("use_texture", textured)
				if textured and original is BaseMaterial3D and original.albedo_texture:
					mat.set_shader_parameter("dust_texture", original.albedo_texture)
			else:
				var kind := 0.0
				if tag.begins_with("EarthFlight"):
					kind = 1.0
				elif tag.begins_with("EarthCrack"):
					kind = 2.0
				elif tag.begins_with("EarthRim") or tag.begins_with("EarthRipple"):
					kind = 3.0
				elif tag.begins_with("EarthGround"):
					kind = 4.0
					mat.render_priority = -20
				mat.set_shader_parameter("surface_kind", kind)
			mat.set_shader_parameter("impact_time", _impact)
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
		if tag.begins_with("EarthFlash"):
			start = 1.19
			end = 1.32
		elif tag.begins_with("EarthDust"):
			start = 2.30
			end = 3.4
		elif tag.begins_with("EarthRock"):
			start = 2.85
		elif tag.begins_with("EarthGround"):
			start = 3.12
		var mat: ShaderMaterial = row["material"]
		mat.set_shader_parameter("cast_time", time_s)
		mat.set_shader_parameter("opacity", 1.0 - smoothstep(start + _impact - 1.12, end + _impact - 1.12, time_s))
	if _light:
		_light.light_energy = 0.0 if time_s < _impact else 1.5 * exp(-(time_s-_impact)*10.0)
	if is_instance_valid(_camera):
		var shake := 0.0
		if time_s >= _impact and time_s < _impact + 0.28:
			shake = 0.064 * (1.0-(time_s-_impact)/0.28)
		_camera.h_offset = _base_h + sin(time_s*137.0)*shake
		_camera.v_offset = _base_v + cos(time_s*121.0)*shake

func _exit_tree() -> void:
	if is_instance_valid(_camera):
		_camera.h_offset = _base_h
		_camera.v_offset = _base_v
