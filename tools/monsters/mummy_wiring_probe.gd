extends SceneTree
## Prints, per mummy type, what the fight view really uses: the resolved model / animation set / clip map from combat.json
## (logic/combat_data_loader.gd picks the first `looks` entry whose model exists), and whether the set it loads has clips.
##   godot --headless --path . --script res://tools/monsters/mummy_wiring_probe.gd [-- orc_grunt orc_archer orc_mage]  (other ids)

const AnimationSet := preload("res://client/animation_set.gd")
const IDS := ["mummy", "mummy_archer", "mummy_knight", "mummy_mage", "mummy_boss", "mummy_high_wizard"]


func _init() -> void:
	var data = preload("res://logic/combat_data_loader.gd").load_default()
	var ids: Array = OS.get_cmdline_user_args() if not OS.get_cmdline_user_args().is_empty() else IDS
	for id in ids:
		var e: Dictionary = data.enemies[id]
		var found: RefCounted = null
		var path: String = e["animations"]
		if path != "":
			found = AnimationSet.load_file(path)
		var source := path
		if found == null or not (found.has_clip("idle") or found.has_clip("attack_1")):
			found = AnimationSet.load_file(e["model"])
			source = e["model"] + " (embedded)"
		var clips: Array = found.clip_names() if found != null else []
		var mult: float = maxf(0.1, 1.0 + float(e["stats"]["MOVESPD"]) / 100.0)
		var fit := float(e["model_height"]) / _bounds_height(e["model"])
		var walk := 3.8 * mult
		var reference := float(e["run_clip_speed"]) if float(e["run_clip_speed"]) > 0.0 else 2.44
		var rate := walk / (reference * fit)
		var travel := 0.0
		if found != null and found.has_clip("run"):
			var marks = JSON.parse_string(FileAccess.get_file_as_string(source.get_basename() + ".json")) if FileAccess.file_exists(source.get_basename() + ".json") else {}
			if typeof(marks) == TYPE_DICTIONARY:
				travel = float(marks.get("run", {}).get("travel_per_second", 0.0))
		var shown := clampf(rate, 0.6, 1.4)
		var slide := (walk - travel * shown * fit) / walk if travel > 0.0 else 1.0
		print("%s look=%s model=%s animations='%s' -> set=%s clips=%s map=%s run_clip_speed=%s hips=%s walk=%.2f m/s run=%.2f m/s fit=%.3f rate=%.3f shown=%.3f clip_travel=%.3f foot_slide=%.0f%%" % [
			id, e["look"], e["model"], path, source, clips, e["clips"], e["run_clip_speed"], e["hips_scale"], walk, walk * 1.75, fit, rate, shown, travel, slide * 100.0])
	quit()


## The model's height in its own units, as client/fighter_view.gd _build_monster_model measures it (all meshes, rest pose).
static func _bounds_height(path: String) -> float:
	var model := (load(path) as PackedScene).instantiate() as Node3D
	var bounds := AABB()
	var first := true
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var to_model: Transform3D = mesh.transform
		var parent: Node = mesh.get_parent()
		while parent != model:
			to_model = (parent as Node3D).transform * to_model
			parent = parent.get_parent()
		var box: AABB = to_model * (mesh as MeshInstance3D).get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	model.free()
	return bounds.size.y
