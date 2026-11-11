extends RefCounted
## Reads the player-facing development log (data/ui/version_info.json) for the title screen's Version
## Info screen: the versions newest first, each with its notes in sections. Also gives the newest
## version's number for the corner of the title screen. Pure presentation data, so it lives in client/.
## EXTENDING: a new version is one more entry in the file (no code); a new section kind is one more
## key in SECTIONS (and its heading in title_screen.gd TEXT).

const PATH := "res://data/ui/version_info.json"
## The note sections, in the order they are shown.
const SECTIONS := ["new", "changes", "fixes", "in_progress"]

var errors: Array[String] = []
## [{id, name, date, th, sections: {key: [String]}}], newest first.
var versions: Array = []


## Loads `path` (the default file if empty) and returns self: `VersionInfo.new().load_file()`.
## A broken file fills `errors`; `versions` then holds whatever entries were valid.
func load_file(path: String = PATH) -> RefCounted:
	versions.clear()
	errors.clear()
	if not FileAccess.file_exists(path):
		errors.append("version info file not found: %s" % path)
		return self
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		errors.append("version info: invalid JSON: %s (line %d)" % [json.get_error_message(), json.get_error_line()])
		return self
	var root = json.data
	if not (root is Dictionary) or not (root.get("versions") is Array):
		errors.append("version info: needs a 'versions' list")
		return self
	for raw in root["versions"]:
		var entry := _entry(raw)
		if not entry.is_empty():
			versions.append(entry)
	versions.sort_custom(func(a, b): return compare_ids(str(a.id), str(b.id)) > 0)
	return self


func _entry(raw) -> Dictionary:
	if not (raw is Dictionary) or str(raw.get("id", "")) == "":
		errors.append("version info: an entry without an id")
		return {}
	var sections := {}
	var lines := 0
	var raw_sections = raw.get("sections", {})
	if raw_sections is Dictionary:
		for key in raw_sections:
			if not key in SECTIONS:
				errors.append("version %s: unknown section '%s'" % [raw.id, key])
				continue
			var list: Array = []
			if raw_sections[key] is Array:
				for line in raw_sections[key]:
					if str(line).strip_edges() != "":
						list.append(str(line))
			sections[key] = list
			lines += list.size()
	if lines == 0:
		errors.append("version %s has no notes" % raw.id)
	return {"id": str(raw.id), "name": str(raw.get("name", "")), "date": str(raw.get("date", "")),
		"th": str(raw.get("th", "")), "sections": sections}


## The newest version (or an empty dictionary when the file had none).
func newest() -> Dictionary:
	return versions[0] if not versions.is_empty() else {}


## Compares dotted version numbers ("0.10" is newer than "0.9"): 1 if a is newer, -1 if older, 0 same.
static func compare_ids(a: String, b: String) -> int:
	var pa := a.trim_prefix("v").split(".")
	var pb := b.trim_prefix("v").split(".")
	for i in maxi(pa.size(), pb.size()):
		var na := int(pa[i]) if i < pa.size() else 0
		var nb := int(pb[i]) if i < pb.size() else 0
		if na != nb:
			return 1 if na > nb else -1
	return 0
