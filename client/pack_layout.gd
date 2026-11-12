extends RefCounted
## Pure helpers for the split web build: which pack a file goes in (build time, tools/web/pck_split.gd)
## and reading the pack manifest (run time, client/pack_loader.gd). No nodes, no network: tested by
## tests/test_pack_loader.gd.
##
## Layout file (tools/web/pack_layout.json): {"packs": [{"name": "items", "include": ["res://art/items/"]}, ...]}
## Anything not matched, and every script/scene/data file whatever its folder, goes in "core".

const CORE := "core"
## Two-stage loading (Boss 2026-11-13): "boot" packs load before the card screen, "battle" packs in the
## background while the player is on it (FIGHT waits for them). A layout pack without "stage" is "boot".
const BOOT := "boot"
const BATTLE := "battle"
const STAGES := [BOOT, BATTLE]
## Kept in core whatever folder they sit in: code, scenes and project data (one place for class_name & co).
const CORE_EXTENSIONS := ["gd", "gdc", "gde", "gdshader", "gdshaderinc", "shader", "tscn", "scn", "uid", "json", "cfg", "binary"]
const CORE_PREFIXES := ["res://data/", "res://.godot/global_script_class_cache", "res://.godot/uid_cache", "res://project.binary"]


static func read_layout(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary) or not (parsed.get("packs") is Array):
		return {}
	return parsed


## "core" first, then the content packs in layout order (also the load order).
static func pack_names(layout: Dictionary) -> Array:
	var names := [CORE]
	for p in layout.get("packs", []):
		var n := str(p.get("name", ""))
		if n != "" and n != CORE and not names.has(n):
			names.append(n)
	return names


static func pack_for_path(layout: Dictionary, path: String) -> String:
	var source := path.trim_suffix(".remap").trim_suffix(".import")
	if CORE_EXTENSIONS.has(source.get_extension().to_lower()):
		return CORE
	for prefix in CORE_PREFIXES:
		if path.begins_with(prefix):
			return CORE
	var best := CORE
	var best_len := 0
	for p in layout.get("packs", []):  # the longest matching prefix wins
		for prefix in p.get("include", []):
			var s := str(prefix)
			if s.length() > best_len and path.begins_with(s):
				best = str(p.get("name", CORE))
				best_len = s.length()
	return best


## The loading stage of the layout pack called `name` ("core" and unknown names are BOOT; a format
## variant "<pack>.<format>" has its base pack's stage).
static func stage_of(layout: Dictionary, name: String) -> String:
	var base := name.get_slice(".", 0)
	for p in layout.get("packs", []):
		if str(p.get("name", "")) == base:
			var stage := str(p.get("stage", BOOT))
			return stage if STAGES.has(stage) else BOOT
	return BOOT


## Layout check: every stage value is "boot" or "battle". Returns the problems ([] = fine).
static func layout_errors(layout: Dictionary) -> Array:
	var errors := []
	for p in layout.get("packs", []):
		if p.has("stage") and not STAGES.has(str(p["stage"])):
			errors.append("pack %s: stage must be boot or battle, not %s" % [p.get("name", "?"), p["stage"]])
	return errors


## The manifest packs of one loading stage, in manifest order. Old manifests have no "stage": all boot.
static func packs_for_stage(packs: Array, stage: String) -> Array:
	return packs.filter(func(p): return str(p.get("stage", BOOT)) == stage)


## "path.s3tc=..." style lines of an exported .import file: {format: res://.godot/... path}.
static func format_paths(import_text: String) -> Dictionary:
	var out := {}
	var re := RegEx.create_from_string("(?m)^path\\.([a-z0-9_]+)=\"(res://\\.godot/[^\"]+)\"")
	for m in re.search_all(import_text):
		out[m.get_string(1)] = m.get_string(2)
	return out


## res://.godot/... files that an exported .import or .remap entry points at.
static func linked_paths(text: String) -> Array:
	var out := []
	var re := RegEx.create_from_string("\"(res://\\.godot/[^\"]+)\"")
	for m in re.search_all(text):
		if not out.has(m.get_string(1)):
			out.append(m.get_string(1))
	return out


## Manifest written by build_web.ps1 (packs.json) and handed to the game by play.html:
## {"build": "<id>", "engine": "...", "core": "...", "packs": [{"name", "stage", "format", "file", "bytes", "raw_bytes"}]}
## Returns the content packs to load, in order, or [] with errors filled when it is malformed.
static func content_packs(manifest, errors: Array) -> Array:
	if not (manifest is Dictionary):
		errors.append("manifest is not an object")
		return []
	if str(manifest.get("build", "")) == "":
		errors.append("manifest has no build id")
	var packs = manifest.get("packs", [])
	if not (packs is Array):
		errors.append("manifest packs is not a list")
		return []
	var out := []
	for p in packs:
		if not (p is Dictionary) or str(p.get("file", "")) == "" or str(p.get("name", "")) == "":
			errors.append("bad pack entry: " + str(p))
			continue
		if not is_versioned(str(p.file)):
			errors.append("pack file name has no content hash: " + str(p.file))
		if p.has("stage") and not STAGES.has(str(p["stage"])):
			errors.append("pack %s has an unknown stage: %s" % [p.name, p["stage"]])
		out.append(p)
	return out if errors.is_empty() else []


## Every shipped file is named <name>.<content hash>.<ext>, so a cache or CDN can never serve a
## stale copy under a current name (a changed file always gets a new name).
static func is_versioned(file: String) -> bool:
	return RegEx.create_from_string("\\.[0-9a-f]{10,}\\.").search(file.get_file()) != null


static func pack_url(base: String, file: String) -> String:
	if file.begins_with("http://") or file.begins_with("https://"):
		return file
	if base == "":
		return file
	return base + ("" if base.ends_with("/") else "/") + file


## gzip-wrapped packs (what the artifact host needs) are unpacked; plain bytes pass through
## (a server that sends Content-Encoding: gzip/br has the browser unpack them already).
static func unwrap(bytes: PackedByteArray) -> PackedByteArray:
	if bytes.size() > 2 and bytes[0] == 0x1f and bytes[1] == 0x8b:
		return bytes.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	return bytes
