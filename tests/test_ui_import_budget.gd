extends RefCounted
## Download budget guard for UI images (tech-artist 2026-11-14, docs/tech/performance_budget.md "Download").
## Every exported image under art/ui/ must be imported so it cannot blow up the web download again:
##   - not lossless (compress/mode=0) when its longest side is over 512 px (lossy WebP, quality ~0.8);
##   - a process/size_limit (1..2048) when its longest side is over 1024 px;
##   - no mipmaps (2D UI is drawn with the linear filter, mipmaps only add a third to the file).
## Files the Web preset's exclude_filter drops are not checked. ALLOW lists deliberate exceptions.

const ROOT := "res://art/ui/"
const EXTENSIONS := ["png", "jpg", "jpeg", "webp"]
const ALLOW := {
	"res://art/ui/combat_numbers/digits.png": "glyph atlas, kept lossless for clean digit edges (0.18 MB)",
}


func run(ctx) -> void:
	var excludes := _exclude_patterns()
	ctx.check("Web preset exclude filter reads", not excludes.is_empty())
	var files: Array = []
	_collect(ROOT, files)
	ctx.check("UI images found", files.size() > 50)
	var problems: Array = []
	for path in files:
		if ALLOW.has(path) or _excluded(path, excludes):
			continue
		var cfg := ConfigFile.new()
		if cfg.load(path + ".import") != OK or str(cfg.get_value("remap", "importer", "")) != "texture":
			continue
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		if image == null or image.is_empty():
			problems.append(path + ": source does not load")
			continue
		var longest := maxi(image.get_width(), image.get_height())
		var mode := int(cfg.get_value("params", "compress/mode", 0))
		var limit := int(cfg.get_value("params", "process/size_limit", 0))
		if mode == 0 and longest > 512:
			problems.append("%s: lossless at %d px (set compress/mode=1, lossy_quality 0.8)" % [path, longest])
		if longest > 1024 and (limit <= 0 or limit > 2048):
			problems.append("%s: %d px with no size_limit (set process/size_limit to the drawn size, <= 2048)" % [path, longest])
		if bool(cfg.get_value("params", "mipmaps/generate", false)):
			problems.append(path + ": mipmaps on a UI image (set mipmaps/generate=false)")
	for p in problems:
		printerr("UI import budget: ", p)
	ctx.check("UI images are lossy, size-limited and without mipmaps (%d problems)" % problems.size(), problems.is_empty())


func _collect(dir_path: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for f in dir.get_files():
		if EXTENSIONS.has(f.get_extension().to_lower()):
			out.append(dir_path.path_join(f))


func _exclude_patterns() -> Array:
	var cfg := ConfigFile.new()
	if cfg.load("res://export_presets.cfg") != OK:
		return []
	var out: Array = []
	for part in str(cfg.get_value("preset.0", "exclude_filter", "")).split(","):
		var p := part.strip_edges()
		if not p.is_empty():
			out.append("res://" + p)
	return out


func _excluded(path: String, patterns: Array) -> bool:
	for p in patterns:
		if path.match(p):
			return true
	return false
