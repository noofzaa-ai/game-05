extends RefCounted
## Equipped meshes only: shared static materials, no particles/lights or per-frame CPU updates.
const Palette := preload("res://client/refine_visual.gd")
const InkStyle := preload("res://client/ink_style.gd")
const SURFACE := preload("res://client/refine_equipment_surface.gdshader")
const SHELL := preload("res://client/refine_equipment_shell.gdshader")
static var _materials := {}
static func materials(level: int) -> Dictionary:
	var index := clampi(level, 4, 12) - 4
	if not _materials.has(index):
		var surface := ShaderMaterial.new()
		surface.shader = SURFACE
		surface.set_shader_parameter("aura", Palette.COLORS[index])
		surface.set_shader_parameter("intensity", 0.15 + Palette.POWER[index] * 0.12)
		var shell := ShaderMaterial.new()
		shell.shader = SHELL
		shell.set_shader_parameter("aura", Palette.COLORS[index])
		shell.set_shader_parameter("pixels", 1.5 + Palette.SPREAD[index] * 1.2)
		shell.set_shader_parameter("intensity", 0.40 + Palette.POWER[index] * 0.25)
		var soft := ShaderMaterial.new()
		soft.shader = SHELL
		soft.set_shader_parameter("aura", Palette.COLORS[index])
		soft.set_shader_parameter("pixels", 3.0 + Palette.SPREAD[index] * 2.5)
		soft.set_shader_parameter("intensity", 0.12 + Palette.POWER[index] * 0.10)
		shell.next_pass = soft
		_materials[index] = {"surface": surface, "shell": shell}
	return _materials[index]

static func apply(mesh: MeshInstance3D, level: int, skeleton: Skeleton3D) -> void:
	if mesh.get_meta("refine_visual_level", -1) == level: return
	mesh.set_meta("refine_visual_level", level)
	var old = mesh.get_meta("refine_shell") if mesh.has_meta("refine_shell") else null
	if is_instance_valid(old):
		mesh.remove_child(old)
		old.queue_free()
	if mesh.has_meta("refine_shell"): mesh.remove_meta("refine_shell")
	mesh.set_meta("refine_surface", null)
	mesh.material_overlay = null
	if level < 4: return
	var materials_for_level := materials(level)
	mesh.set_meta("refine_surface", materials_for_level.surface)
	mesh.material_overlay = materials_for_level.surface
	var shell := MeshInstance3D.new()
	shell.name = "RefineAura"
	shell.mesh = InkStyle.outline_mesh(mesh.mesh)
	shell.skin = mesh.skin
	mesh.add_child(shell)
	shell.skeleton = shell.get_path_to(skeleton) if mesh.skin != null else NodePath()
	shell.material_override = materials_for_level.shell
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.set_meta("refine_shell", shell)
