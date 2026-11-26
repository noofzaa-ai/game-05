extends RefCounted
## Fight readability light (tech-artist 2026-11-25, Boss approved): brighter exposure / ambient per zone and stronger
## character-only key + rim lights so the small fighters pop from the floor. Optional look keys (the orc camp at DUSK,
## Boss 2026-11-25): a gradient sky, the sun's colour / energy / low angle, the ambient (shadow) tint and the fighters'
## key / rim colours. Values: data/render/fight_light.json (by map id prefix). No new lights or passes: it re-tunes the
## stage's environment, its sun and the two character lights (client/character_light.gd), so the cost stays flat.

const DATA_PATH := "res://data/render/fight_light.json"
const KEEP_SKY_META := "fight_light_sky"  ## the drawn style leaves a sky with this meta alone (no painted day sky)


## The settings for `map_id` (longest matching prefix, else "default").
static func zone(map_id: String, path: String = DATA_PATH) -> Dictionary:
	var root = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	var zones: Dictionary = root.get("zones", {}) if root is Dictionary else {}
	var best := "default"
	for prefix in zones:
		if prefix != "default" and map_id.begins_with(str(prefix)) and (best == "default" or str(prefix).length() > best.length()):
			best = str(prefix)
	return zones.get(best, {})


## Applies the zone's light to every WorldEnvironment, the sun and the character lights under `root`. Call once,
## after the stage set its sky.
static func apply(root: Node, map_id: String) -> Dictionary:
	var z := zone(map_id)
	if z.is_empty():
		return z
	for node in root.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (node as WorldEnvironment).environment
		if env == null:
			continue
		env.tonemap_exposure = float(z.get("exposure", 1.0))
		if z.has("ambient_color"):
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color.html(str(z["ambient_color"]))
		env.ambient_light_energy *= float(z.get("ambient", 1.0))
		if z.get("sky") is Array and z["sky"].size() == 3:
			var c: Array = z["sky"].map(func(h): return Color.html(str(h)))
			var mat := ProceduralSkyMaterial.new()
			mat.sky_top_color = c[0]
			mat.sky_horizon_color = c[2]
			mat.sky_curve = 0.25
			mat.ground_horizon_color = c[2]
			mat.ground_bottom_color = c[0]  # (the steep camera sees mostly below the horizon: orange -> pink -> violet down there too)
			mat.ground_curve = 0.08
			mat.sun_angle_max = 0.0
			var sky := Sky.new()
			sky.sky_material = mat
			env.background_mode = Environment.BG_SKY
			env.sky = sky
			env.set_meta(KEEP_SKY_META, true)
	for node in root.find_children("*", "DirectionalLight3D", true, false):
		var light := node as DirectionalLight3D
		var name := str(light.name)
		if name == "CharacterKeyLight":
			light.light_energy *= float(z.get("key", 1.0))
			if z.has("key_color"): light.light_color = Color.html(str(z["key_color"]))
		elif name == "CharacterRimLight":
			light.light_energy *= float(z.get("rim", 1.0))
			if z.has("rim_color"): light.light_color = Color.html(str(z["rim_color"]))
		elif not name.begins_with("Character"):  # the stage's sun / moon
			if z.has("sun_color"): light.light_color = Color.html(str(z["sun_color"]))
			if z.has("sun_energy"): light.light_energy = float(z["sun_energy"])
			if z.get("sun_rotation") is Array: light.rotation_degrees = Vector3(float(z["sun_rotation"][0]), float(z["sun_rotation"][1]), float(z["sun_rotation"][2]))
	return z
