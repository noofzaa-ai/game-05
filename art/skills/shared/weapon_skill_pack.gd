class_name WeaponSkillPack
extends Resource

# Type-based ultimate; skill.json is the authoritative attack configuration.
@export var skill_id: StringName
@export var required_weapon_type: StringName
@export var animation_name: StringName
@export_file("*.json") var manifest_path: String
@export var animation_carrier: PackedScene
@export var vfx_scene: PackedScene
var _manifest: Dictionary = {}

func manifest() -> Dictionary:
	if _manifest.is_empty() and FileAccess.file_exists(manifest_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if parsed is Dictionary:
			_manifest = parsed
	return _manifest

func attack_config() -> Dictionary:
	return manifest().get("attack", {})

func gameplay_events() -> Array:
	return manifest().get("gameplay_events", [])

func control_config() -> Dictionary:
	var data := manifest()
	if data.has("control"):
		return data["control"] if data["control"] is Dictionary else {}
	var dash: bool = attack_config().get("caster_motion") == "forward_dash"
	var flight: Dictionary = data.get("flight", {})
	var resume := float(flight.get("arrival_time_s" if dash else "release_time_s", 0.0))
	if skill_id == &"blade_inferno_ultimate" and not gameplay_events().is_empty():
		resume = float(gameplay_events()[0]["time_s"])
	var feet: Dictionary = data.get("footwork", {})
	if dash:
		if feet.has("second_contact_time_s"):
			resume = maxf(resume, float(feet["second_contact_time_s"]))
		elif float(data.get("body_motion", {}).get("visual_jump_height_m", 0.0)) > 0.0:
			resume += float(feet.get("second_contact_delay_s", 0.16))
	return {"locomotion_resume_time_s": resume, "blend_out_s": 0.12,
		"vfx_clock": "independent_cast", "release_actor_heading": true}

func has_forward_ultimate_contract() -> bool:
	var data := manifest()
	var attack := attack_config()
	var defaults_path := "res://art/skills/ultimate_defaults.json"
	if not FileAccess.file_exists(defaults_path):
		return false
	var defaults: Variant = JSON.parse_string(FileAccess.get_file_as_string(defaults_path))
	if not (defaults is Dictionary):
		return false
	# Explicit user exception, limited to the four sky throw IDs. Defaults stay 2.
	var range_body_lengths := 2.0
	if is_spear_sky_throw() and attack.get("range_override") == "user_2026-10-11_spear_double_range":
		range_body_lengths = 4.0
	if is_shadow_extraction():
		range_body_lengths = 4.0
	for key in defaults:
		if key in ["caster_motion", "delivery"]:
			continue
		var expected: Variant = range_body_lengths if key == "range_body_lengths" else defaults[key]
		if attack.get(key) != expected:
			return false
	if String(data.get("id", "")) != String(skill_id) or String(data.get("weapon_type", "")) != String(required_weapon_type):
		return false
	if String(data.get("animation", "")) != String(animation_name):
		return false
	if data.get("slot") != "ultimate" or data.get("in_place") != true:
		return false
	if attack.get("direction") != "forward" or attack.get("lock_direction_on_cast") != true:
		return false
	# JSON numbers are floats in Godot; compare with numeric float literals.
	if attack.get("asset_forward_axis") != [0.0, 0.0, 1.0] or attack.get("range_body_lengths") != range_body_lengths:
		return false
	var mode := String(attack.get("caster_motion", ""))
	if is_shadow_extraction() and mode != "in_place":
		return false
	if mode not in ["in_place", "forward_dash"] or attack.get("vfx_motion") != "authored_in_glb":
		return false
	if attack.get("delivery") != ("dash_trail" if mode == "forward_dash" else "traveling_wave"):
		return false
	var flight: Dictionary = data.get("flight", {})
	var arrival := float(flight.get("arrival_time_s", -1.0))
	var release := float(flight.get("release_time_s", -1.0))
	if not is_finite(release) or not is_finite(arrival) or release < 0.0 or arrival <= release or arrival > float(data.get("duration_s", 0.0)):
		return false
	if not is_equal_approx(float(flight.get("center_end_body_lengths", 0.0)) + float(flight.get("front_extent_body_lengths", 0.0)), range_body_lengths):
		return false
	if mode == "forward_dash":
		var movement: Dictionary = data.get("movement", {})
		if movement.get("kind") != "forward_dash" or movement.get("distance_body_lengths") != 2.0 or movement.get("ease") != "smoothstep":
			return false
		if movement.get("motion_owner") != "godot_runtime" or movement.get("collision") != "stop" or movement.get("animation_root_motion") != false:
			return false
		if not is_equal_approx(float(movement.get("start_time_s", -1.0)), release) or not is_equal_approx(float(movement.get("end_time_s", -1.0)), arrival):
			return false
	var control := control_config()
	var resume := float(control.get("locomotion_resume_time_s", -1.0))
	var blend := float(control.get("blend_out_s", -1.0))
	var earliest := arrival if mode == "forward_dash" else release
	if not is_finite(resume) or resume < earliest or resume >= float(data["duration_s"]):
		return false
	if not is_finite(blend) or blend <= 0.0 or blend > 0.3:
		return false
	if control.get("vfx_clock") != "independent_cast" or control.get("release_actor_heading") != true:
		return false
	var has_arrival_hit := false
	var previous_time := -1.0
	for event in gameplay_events():
		if not (event is Dictionary):
			return false
		var time := float(event.get("time_s", -1.0))
		var factor := float(event.get("range_factor", 0.0))
		if not is_finite(time) or time < previous_time or time > float(data.get("duration_s", 0.0)) or factor <= 0.0 or factor > 1.0:
			return false
		previous_time = time
		if is_equal_approx(time, arrival) and is_equal_approx(factor, 1.0):
			has_arrival_hit = true
	if not has_arrival_hit:
		return false
	var height := float(attack.get("reference_body_height_m", 0.0))
	return is_finite(height) and height > 0.0 and is_equal_approx(float(attack.get("range_m", 0.0)), height * range_body_lengths)

func is_spear_sky_throw() -> bool:
	var elements := {"spear_fire_sky_throw_ultimate":"fire", "spear_water_sky_throw_ultimate":"water", "spear_earth_sky_throw_ultimate":"earth", "spear_thunder_sky_throw_ultimate":"lightning"}
	var data := manifest()
	return required_weapon_type == &"spear" and elements.has(String(skill_id)) and data.get("element") == elements[String(skill_id)] and data.get("weapon_delivery",{}).get("kind") == "throw_recall"

func is_shadow_extraction() -> bool:
	var token := "user_2026-10-11_shadow_guardians_spear_range_stationary_hero"
	return skill_id == &"dagger_shadow_extraction_ultimate" and required_weapon_type == &"dagger" and manifest().get("element") == "shadow" and attack_config().get("range_override") == token and attack_config().get("movement_override") == token
