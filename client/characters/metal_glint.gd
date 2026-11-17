extends RefCounted
## Ink-style metal glints for the level-15 race armour (Boss 2026-11-16): stepped (toon) specular highlight with a dark
## ink line beside it, a thin lit-side rim and a star-like sparkle dot on studs and buckles, on the metal parts only. The shader is studio05_toon.gdshader (group "metal");
## this file owns the numbers it is fed with, the mask path and the pure maths the tests check against.
const MATERIAL_PREFIX := "Level 15 | Original Armor"  ## the atlas material of art/armor/race_shared/<race>_<slot>_lv15.glb
const MASK_PATH := "res://art/armor/race_shared/race_wardrobe_atlas_lv15_metal.png"
## The level-15 weapon materials (delivery sword_shield / greatsword / longbow / magic _weapons_lv15.glb) -> their metal mask
## (tools/items/build_lv15_weapon_metal_masks.py). Matched by name prefix; the old mid / starter weapons ("... | Original PBR")
## and the shield's leather straps are not listed, so they never get it.
const WEAPON_MASKS := {
	"Sword and Shield Lv15 | Original Colors": "res://art/weapons/race_shared/weapon_metal_lv15_sword_shield.png",
	"Human Shield Lv15 | Turquoise & Gold": "res://art/weapons/race_shared/weapon_metal_lv15_shield_front.png",
	"Greatswords Lv15 | Original Colors": "res://art/weapons/race_shared/weapon_metal_lv15_greatsword.png",
	"Bow | Original Colors": "res://art/weapons/race_shared/weapon_metal_lv15_longbow.png",
	"Staff | Original Colors": "res://art/weapons/race_shared/weapon_metal_lv15_magic.png",
}
## Weapons get a MORE restrained version of the armour look (Boss 2026-11-17: "a little metal reflection"): small accents on
## blades, guards, edges, gems and gold trim; no whitening.
const WEAPON_PARAMS := {
	"metal_core": 0.90,
	"metal_halo": 0.82,
	"metal_halo_strength": 0.15,
	"metal_lift": 0.93,
	"metal_line_strength": 0.25,
	"metal_rim_strength": 0.35,
	"metal_stud_base": 0.22,
	"metal_glint_mix": 0.45,
}
const OPTION := "metal_glint"  ## client/graphics_options.gd boolean (device quality switch)
## Shader uniforms (name -> value), set on every lv15 material.
const PARAMS := {
	"metal_core": 0.88,  ## half-vector . normal above this = the bright glint (stepped, 1 band)
	"metal_halo": 0.78,  ## above this = the dimmer second band
	"metal_soft": 0.012,  ## step softness (anti-aliasing only; the look stays hard-edged)
	"metal_halo_strength": 0.30,
	"metal_jitter": 0.10,  ## per atlas cell shift of the thresholds: each plate patch / stud sparkles at its own angle
	"metal_cells": 80.0,  ## atlas cells per UV unit for that shift
	"metal_line_w": 0.05,  ## width (in the same dot) of the thin dark ink line just outside the halo
	"metal_line_strength": 0.45,
	"metal_rim_edge": 0.42,  ## facing (n . view) below this = rim
	"metal_rim_soft": 0.06,
	"metal_rim_strength": 0.55,
	"metal_stud_edge": 0.70,  ## studs / buckles: the star dot is on above this (much wider than the plate glint)
	"metal_stud_base": 0.40,  ## ... and never fully off, so a stud always reads as a small bright dot
	"metal_lift": 0.84,  ## metal base is darker than cloth in the same band, so the glints stand out
	"metal_glint_mix": 0.70,  ## plates: the glint covers at most this much of the plate (its texture stays visible)
	"metal_small_lo": 2.5,  ## atlas texels per screen pixel where the plate glint starts to fade (card portrait, far fighter)
	"metal_small_hi": 7.0,
	"metal_small_floor": 0.35,  ## ... to this share of its strength (studs keep their dots)
	"metal_strength": 1.0,
}


static func is_armor_material(material_name: String) -> bool:
	return material_name.begins_with(MATERIAL_PREFIX)


static func weapon_key(material_name: String) -> String:
	for key in WEAPON_MASKS:
		if material_name.begins_with(key):
			return key
	return ""


static func is_weapon_material(material_name: String) -> bool:
	return not weapon_key(material_name).is_empty()


## Armour or lv15 weapon: the materials that get the glint.
static func is_metal_material(material_name: String) -> bool:
	return is_armor_material(material_name) or is_weapon_material(material_name)


## The mask file for a material name, "" for any other material.
static func mask_path(material_name: String) -> String:
	if is_armor_material(material_name):
		return MASK_PATH
	var key := weapon_key(material_name)
	return str(WEAPON_MASKS[key]) if not key.is_empty() else ""


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


## Mirror of the shader: how much of the plate glint is left when a screen pixel covers `texels` atlas texels.
static func small_scale(texels: float) -> float:
	return lerpf(1.0, float(PARAMS["metal_small_floor"]), _smooth(float(PARAMS["metal_small_lo"]), float(PARAMS["metal_small_hi"]), texels))


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
	if is_weapon_material(material.resource_name):
		for key in WEAPON_PARAMS:
			material.set_shader_parameter(key, WEAPON_PARAMS[key])
	return true
