extends RefCounted
## Ink-style metal glints for the level-15 race armour (Boss 2026-11-16): stepped (toon) specular highlight, a thin
## lit-side rim and a per-cell sparkle on the metal parts only. The shader is studio05_toon.gdshader (group "metal");
## this file owns the numbers it is fed with, the mask path and the pure maths the tests check against.
const MATERIAL_PREFIX := "Level 15 | Original Armor"  ## the atlas material of art/armor/race_shared/<race>_<slot>_lv15.glb
const MASK_PATH := "res://art/armor/race_shared/race_wardrobe_atlas_lv15_metal.png"
const OPTION := "metal_glint"  ## client/graphics_options.gd boolean (device quality switch)
## Shader uniforms (name -> value), set on every lv15 material.
const PARAMS := {
	"metal_core": 0.93,  ## half-vector . normal above this = the bright glint (stepped, 1 band)
	"metal_halo": 0.82,  ## above this = the dim second band
	"metal_soft": 0.012,  ## step softness (anti-aliasing only; the look stays hard-edged)
	"metal_halo_strength": 0.34,
	"metal_jitter": 0.10,  ## per atlas cell shift of both thresholds: each stud/buckle sparkles at its own angle
	"metal_cells": 80.0,  ## atlas cells per UV unit for that shift
	"metal_rim_edge": 0.30,  ## facing (n . view) below this = rim
	"metal_rim_soft": 0.07,
	"metal_rim_strength": 0.50,
	"metal_lift": 0.68,  ## metal base is a touch brighter than cloth in the same band
	"metal_strength": 1.0,
}


static func is_metal_material(material_name: String) -> bool:
	return material_name.begins_with(MATERIAL_PREFIX)


static func _smooth(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / maxf(edge1 - edge0, 0.000001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Mirror of the shader: glint strength 0..1 for the half-vector dot `spec` and a per-cell `hash` 0..1.
static func glint(spec: float, hash: float) -> float:
	var s: float = spec + (hash - 0.5) * float(PARAMS["metal_jitter"])
	var soft: float = PARAMS["metal_soft"]
	var core := _smooth(float(PARAMS["metal_core"]), float(PARAMS["metal_core"]) + soft, s)
	var halo := _smooth(float(PARAMS["metal_halo"]), float(PARAMS["metal_halo"]) + soft, s) * float(PARAMS["metal_halo_strength"])
	return maxf(core, halo * (1.0 - core))


## Mirror of the shader: rim 0..1 for facing = n . view and cel_facing = n . key light (lit side only).
static func rim(facing: float, cel_facing: float) -> float:
	var edge: float = PARAMS["metal_rim_edge"]
	return (1.0 - _smooth(edge, edge + float(PARAMS["metal_rim_soft"]), facing)) * _smooth(-0.10, 0.35, cel_facing)


## Puts the mask and the numbers on a toon ShaderMaterial. Returns false (and changes nothing) for any other material.
static func apply(material: ShaderMaterial, mask: Texture2D) -> bool:
	if material == null or mask == null or not is_metal_material(material.resource_name):
		return false
	material.set_shader_parameter("use_metal", true)
	material.set_shader_parameter("metal_mask", mask)
	for key in PARAMS:
		material.set_shader_parameter(key, PARAMS[key])
	return true
