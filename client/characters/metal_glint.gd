extends RefCounted
## Ink-style metal glints for the level-15 race armour (Boss 2026-11-16): stepped (toon) specular highlight with a dark
## ink line beside it, a thin lit-side rim and a star-like sparkle dot on studs and buckles, on the metal parts only. The shader is studio05_toon.gdshader (group "metal");
## this file owns the numbers it is fed with, the mask path and the pure maths the tests check against.
const MATERIAL_PREFIX := "Level 15 | Original Armor"  ## the atlas material of art/armor/race_shared/<race>_<slot>_lv15.glb
const MASK_PATH := "res://art/armor/race_shared/race_wardrobe_atlas_lv15_metal.png"
const OPTION := "metal_glint"  ## client/graphics_options.gd boolean (device quality switch)
## Shader uniforms (name -> value), set on every lv15 material.
const PARAMS := {
	"metal_core": 0.80,  ## half-vector . normal above this = the bright glint (stepped, 1 band)
	"metal_halo": 0.62,  ## above this = the dimmer second band
	"metal_soft": 0.012,  ## step softness (anti-aliasing only; the look stays hard-edged)
	"metal_halo_strength": 0.55,
	"metal_jitter": 0.10,  ## per atlas cell shift of the thresholds: each plate patch / stud sparkles at its own angle
	"metal_cells": 80.0,  ## atlas cells per UV unit for that shift
	"metal_line_w": 0.05,  ## width (in the same dot) of the thin dark ink line just outside the halo
	"metal_line_strength": 0.70,
	"metal_rim_edge": 0.50,  ## facing (n . view) below this = rim
	"metal_rim_soft": 0.06,
	"metal_rim_strength": 1.0,
	"metal_stud_edge": 0.70,  ## studs / buckles: the star dot is on above this (much wider than the plate glint)
	"metal_stud_base": 0.50,  ## ... and never fully off, so a stud always reads as a small bright dot
	"metal_lift": 0.60,  ## metal base is darker than cloth in the same band, so the glints stand out
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


## Mirror of the shader: the thin dark line just outside the halo, 0..1.
static func dark_line(spec: float, hash: float) -> float:
	var s: float = spec + (hash - 0.5) * float(PARAMS["metal_jitter"])
	var soft: float = PARAMS["metal_soft"]
	var halo: float = PARAMS["metal_halo"]
	var width: float = PARAMS["metal_line_w"]
	return _smooth(halo - width, halo - width + soft, s) * (1.0 - _smooth(halo, halo + soft, s))


## Mirror of the shader: strength of the stud / buckle star dot (never below metal_stud_base).
static func stud(spec: float, hash: float) -> float:
	var s: float = spec + (hash - 0.5) * float(PARAMS["metal_jitter"]) + (hash - 0.5) * 0.2
	var edge: float = PARAMS["metal_stud_edge"]
	return maxf(_smooth(edge, edge + float(PARAMS["metal_soft"]), s), float(PARAMS["metal_stud_base"]))


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
