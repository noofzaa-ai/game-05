extends RefCounted
## Ink-wash look for the battle effects (Boss 2026-11-15: "the VFX must look ink-drawn too"). One shared treatment,
## a material swap only (no extra nodes, passes or draws):
##   - daiyooo flipbook effects (class skills, status loops): every imported StandardMaterial3D becomes
##     client/vfx/ink_flipbook.gdshader (same texture and colour), built once per source material and shared.
##   - the procedural effects (client/effects.gd, telegraphs): their shaders take `drawn` = 1 and run vfx_ink()
##     from client/vfx/vfx_common.gdshaderinc.
## On while the graphics setting `drawn_style` is "on" or "lite" (client/draw_style/draw_style.gd); "off" keeps the
## original glossy look. Read when an effect is built, so a change applies from the next battle.

const FLIPBOOK_SHADER := preload("res://client/vfx/ink_flipbook.gdshader")
const ATTACK_TELEGRAPH := preload("res://client/vfx/attack_telegraph.gdshader")
const INK := Color(0.10, 0.08, 0.07)  ## the stages' pen colour (ink_outline_brush.gdshader)

static var _cache: Dictionary = {}  ## source BaseMaterial3D -> ShaderMaterial


## True when the effects are drawn in ink this battle.
static func enabled() -> bool:
	return load("res://client/draw_style/draw_style.gd").mode() != "off"  # (load, not preload: draw_style preloads this file)


## 1.0 / 0.0 for the `drawn` uniform of the procedural effect shaders.
static func strength() -> float:
	return 1.0 if enabled() else 0.0


## Swaps every BaseMaterial3D surface under `root` (a daiyooo effect instance) for its ink version.
## Does nothing when the drawn style is off.
static func apply(root: Node) -> void:
	if not enabled():
		return
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.get_active_material(surface)
			if source is BaseMaterial3D:
				mesh_instance.set_surface_override_material(surface, material_for(source))


## The shared ink material for one imported effect material.
static func material_for(source: BaseMaterial3D) -> ShaderMaterial:
	if _cache.has(source):
		return _cache[source]
	var material := ShaderMaterial.new()
	material.shader = FLIPBOOK_SHADER
	material.render_priority = source.render_priority
	material.set_shader_parameter("albedo_tex", source.albedo_texture)
	material.set_shader_parameter("tint", source.albedo_color)
	material.set_shader_parameter("uv_scale", source.uv1_scale)
	material.set_shader_parameter("uv_offset", source.uv1_offset)
	material.set_shader_parameter("ink_color", INK)
	material.set_shader_parameter("grain_seed", float(_cache.size() % 17) * 3.7)
	material.set_shader_parameter("billboard", source.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED)
	_cache[source] = material
	return material


## A monster wind-up warning quad built by the stage (attack_telegraph.gdshader): drawn in ink. Called (deferred,
## after the stage set its material) for each node that enters the battle; client/effects.gd watches them.
static func mark(reference: WeakRef) -> void:
	var geometry := reference.get_ref() as GeometryInstance3D
	if geometry == null:
		return
	var material := geometry.material_override as ShaderMaterial
	if material != null and material.shader == ATTACK_TELEGRAPH:
		material.set_shader_parameter("drawn", 1.0)
