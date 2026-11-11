extends Node3D
## Pose study only: Blender-authored armor, soft dark flames, no gameplay events.
const SILHOUETTE := preload("res://art/skills/shared/shaders/shadow_silhouette.gdshader")
const AURA := preload("res://art/skills/shared/shaders/shadow_torn_aura.gdshader")
const GROUND := preload("res://art/skills/shared/shaders/shadow_ink_ground.gdshader")
var _materials: Array[ShaderMaterial] = []
var _light: OmniLight3D

func _ready() -> void:
	_adapt(get_parent(),true)
	_light = OmniLight3D.new()
	_light.position = Vector3(0,1.05,-.6)
	_light.light_color = Color(.37,.08,.85)
	_light.omni_range = 3.5
	_light.light_energy = 0.0
	add_child(_light)

func _adapt(node: Node, shadow: bool) -> void:
	if node is MeshInstance3D and node.mesh:
		for index in node.mesh.get_surface_count():
			var original: Material = node.mesh.surface_get_material(index)
			var tag := original.resource_name if original else ""
			var mat := ShaderMaterial.new()
			mat.shader = SILHOUETTE
			if shadow and (tag.begins_with("ShadowFlame") or tag.begins_with("ShadowSmoke") or tag.begins_with("ShadowChip")):
				mat.shader = AURA
				mat.set_shader_parameter("kind",2.0 if tag.begins_with("ShadowChip") else 1.0 if tag.begins_with("ShadowSmoke") else 0.0)
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			elif shadow and tag.begins_with("ShadowGround"):
				mat.shader = GROUND
				mat.render_priority = -10
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			else:
				mat.set_shader_parameter("is_double",shadow)
				mat.set_shader_parameter("is_seam",tag.begins_with("ShadowArmorEdge"))
				mat.set_shader_parameter("is_eye",tag.begins_with("ShadowEye") or String(node.name).begins_with("Eye_inset") or String(node.name).begins_with("Eye inset"))
			node.set_surface_override_material(index,mat)
			_materials.append(mat)
	for child in node.get_children():
		if child != self:_adapt(child,shadow)

func advance(time_s: float) -> void:
	for mat in _materials:mat.set_shader_parameter("cast_time",time_s)
	if _light:_light.light_energy = smoothstep(.16,.78,time_s)*(1.1+.08*sin(time_s*4.5))
