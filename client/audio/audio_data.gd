extends RefCounted
## Loads and checks data/audio/audio.json (which sound plays for what; see its _comment).
## load_default() always returns a Dictionary; problems are listed in its "errors" array and the
## game keeps running with whatever is valid (a missing sound is silence, never a crash).

const PATH := "res://data/audio/audio.json"
const BUSES := ["Master", "Music", "SFX", "UI", "Ambience"]
## Move sets "{weapon}" in a cue name can become (the weapons of data/combat/weapons.json and the
## monster styles of data/combat/combat.json). Used only to check that every expanded cue exists.
const DEFAULT_WEAPONS := ["fists", "blade", "dagger", "spear", "hammer", "bow"]


static func load_default() -> Dictionary:
	return load_file(PATH)


static func load_file(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {"errors": ["%s is missing or empty" % path], "cues": {}, "events": {}}
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return {"errors": ["%s: invalid JSON: %s (line %d)" % [path, json.get_error_message(), json.get_error_line()]], "cues": {}, "events": {}}
	var data: Dictionary = json.data
	data["errors"] = validate(data)
	return data


## Every problem with the data as readable lines (empty = valid).
static func validate(data: Dictionary, weapons: Array = DEFAULT_WEAPONS) -> Array[String]:
	var errors: Array[String] = []
	var cues = data.get("cues", {})
	if not (cues is Dictionary) or cues.is_empty():
		errors.append("cues must be a non-empty object")
		cues = {}
	var defaults: Dictionary = data.get("defaults", {})
	for name in cues:
		var cue = cues[name]
		if not (cue is Dictionary):
			errors.append("cues.%s must be an object" % name)
			continue
		var files = cue.get("files", [])
		if not (files is Array) or files.is_empty():
			errors.append("cues.%s.files must list at least one file" % name)
		else:
			for file in files:
				if not ResourceLoader.exists(str(file)):
					errors.append("cues.%s: file %s does not exist" % [name, file])
		var bus := str(cue.get("bus", defaults.get("bus", "SFX")))
		if not bus in BUSES:
			errors.append("cues.%s.bus '%s' is not one of %s" % [name, bus, BUSES])
		var pitch = cue.get("pitch", defaults.get("pitch", [1.0, 1.0]))
		if not (pitch is Array) or pitch.size() != 2 or float(pitch[0]) <= 0.0 or float(pitch[0]) > float(pitch[1]):
			errors.append("cues.%s.pitch must be [min, max] with 0 < min <= max" % name)
		if int(cue.get("max_voices", defaults.get("max_voices", 1))) < 1:
			errors.append("cues.%s.max_voices must be at least 1" % name)

	var events = data.get("events", {})
	if not (events is Dictionary):
		errors.append("events must be an object")
		events = {}
	for type in events:
		var rules = events[type]
		if not (rules is Array):
			errors.append("events.%s must be a list of rules" % type)
			continue
		for i in rules.size():
			var rule = rules[i]
			if not (rule is Dictionary) or not (rule.get("play", null) is Array):
				errors.append("events.%s[%d] must be {when?, play: [cues]}" % [type, i])
				continue
			for cue_name in rule["play"]:
				for name in expansions(str(cue_name), weapons):
					if not cues.has(name):
						errors.append("events.%s[%d] plays unknown cue '%s'" % [type, i, name])

	for section in ["ui", "auto_ui"]:
		var table = data.get(section, {})
		if not (table is Dictionary):
			errors.append("%s must be an object" % section)
			continue
		for action in table:
			var target := str(table[action])
			if section == "ui" and not cues.has(target):
				errors.append("ui.%s plays unknown cue '%s'" % [action, target])
			if section == "auto_ui" and not data.get("ui", {}).has(target):
				errors.append("auto_ui.%s names unknown ui action '%s'" % [action, target])

	for section in ["music", "ambience"]:
		var table = data.get(section, {})
		if not (table is Dictionary):
			errors.append("%s must be an object" % section)
			continue
		for id in table:
			var file := str(table[id].get("file", "")) if table[id] is Dictionary else ""
			if not ResourceLoader.exists(file):
				errors.append("%s.%s: file '%s' does not exist" % [section, id, file])

	var scenes = data.get("scenes", {})
	for scene in scenes:
		var entry: Dictionary = scenes[scene]
		if entry.has("music") and not data.get("music", {}).has(str(entry["music"])):
			errors.append("scenes.%s: unknown music '%s'" % [scene, entry["music"]])
		var ambiences: Array = [entry.get("ambience", "")]
		ambiences.append_array(entry.get("ambience_by_map", {}).values())
		for id in ambiences:
			if not str(id).is_empty() and not data.get("ambience", {}).has(str(id)):
				errors.append("scenes.%s: unknown ambience '%s'" % [scene, id])
	return errors


## The cue names a rule entry can turn into ("swing_{weapon}_light" -> one per weapon).
static func expansions(cue_name: String, weapons: Array = DEFAULT_WEAPONS) -> Array[String]:
	var out: Array[String] = []
	if "{weapon}" in cue_name:
		for weapon in weapons:
			out.append(cue_name.replace("{weapon}", str(weapon)))
	else:
		out.append(cue_name)
	return out


## A cue's settings with the defaults filled in.
static func cue_settings(data: Dictionary, name: String) -> Dictionary:
	var out: Dictionary = data.get("defaults", {}).duplicate()
	var cue = data.get("cues", {}).get(name, null)
	if cue is Dictionary:
		out.merge(cue, true)
	return out
