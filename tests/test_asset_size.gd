extends RefCounted
## Asset-size guard (rule file .claude/rules/asset-size.md, Boss order 2026-11-17).
## Scans every .import of a shipped directory (derived from the folder, never hand-listed) and fails
## when a COLOUR texture is imported lossless (compress/mode=0). Shipped = not matched by the
## exclude_filter of export_presets.cfg.
## A colour texture = source over 64 KB, or longer side over 512 px. Data masks are allowlisted below.

const SCAN_DIRS := ["res://art", "res://assets"]
const BIG_BYTES := 64 * 1024
const BIG_SIDE := 512
## Packed lossless WebP estimate for a photo-like source: about 1.05 byte per pixel (measured 2026-11-17: 2048 px atlas -> 4.4 MB).
const LOSSLESS_BYTES_PER_PX := 1.05

## Lossless data masks (a shader thresholds them exactly). path pattern (String.match) -> reason
const LOSSLESS_ALLOW := {
	"res://art/armor/race_shared/race_wardrobe_atlas_lv15_metal.png": "lv15 metal mask, read exactly by the metal shader",
	"res://art/weapons/race_shared/weapon_metal_lv15_*.png": "lv15 weapon metal masks (4), read exactly by the metal shader",
	"res://art/ui/combat_numbers/digits.png": "damage-number glyph sheet, small UI piece (~0.11 MB packed), crisp edges",
}
## Lossy atlases of this set must not be flipped to VRAM compression by the editor.
const LV15_LOSSY_ATLASES := ["res://art/armor/race_shared/*lv15*.png", "res://art/weapons/race_shared/*lv15*.png"]

var _exclude: PackedStringArray = []


func run(ctx) -> void:
	_exclude = _load_exclude_filter()
	ctx.check("export_presets exclude_filter was read", _exclude.size() > 10)
	var imports: Array = []
	for d in SCAN_DIRS:
		_collect(d, imports)
	ctx.check("asset scan found .import files", imports.size() > 100)
	var violations: Array = []
	var allowed: Array = []
	var allowed_bytes := 0.0
	var lv15_bad: Array = []
	for imp in imports:
		var src: String = imp.trim_suffix(".import")
		if not (src.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]):
			continue
		if _is_excluded(src):
			continue
		var params := _read_params(imp)
		if params.is_empty():
			continue
		var mode := int(params.get("compress/mode", "0"))
		var is_lv15 := false
		for pat in LV15_LOSSY_ATLASES:
			if src.match(pat):
				is_lv15 = true
		if mode != 0:
			if is_lv15 and int(params.get("detect_3d/compress_to", "1")) != 0:
				lv15_bad.append(src)
			continue
		var bytes := _file_len(src)
		var dims := _dims(src)
		var side := maxi(dims.x, dims.y)
		if bytes <= BIG_BYTES and side <= BIG_SIDE:
			continue
		var est := _estimate_packed(src, bytes, dims)
		var reason := ""
		for pat in LOSSLESS_ALLOW:
			if src.match(pat):
				reason = LOSSLESS_ALLOW[pat]
		if reason != "":
			allowed.append("%s  %dx%d  ~%.2f MB  (%s)" % [src, dims.x, dims.y, est / 1048576.0, reason])
			allowed_bytes += est
		else:
			violations.append("%s  mode=0  src=%.0f KB  %dx%d  packed~%.2f MB" % [src, bytes / 1024.0, dims.x, dims.y, est / 1048576.0])
	violations.sort()
	for v in violations:
		print("  VIOLATION lossless colour texture: ", v)
	# Visible growth of the lossless exceptions (rule 1: each below 0.5 MB packed, or listed with a reason).
	for a in allowed:
		print("  LOSSLESS-ALLOWED ", a)
	print("  lossless exceptions: %d files, ~%.2f MB packed estimate" % [allowed.size(), allowed_bytes / 1048576.0])
	ctx.check("no colour texture over 64 KB / 512 px is imported lossless (%d violations, see VIOLATION lines)" % violations.size(), violations.is_empty())
	ctx.check("lv15 lossy atlases have detect_3d/compress_to=0 (%d bad)" % lv15_bad.size(), lv15_bad.is_empty())
	ctx.check("lossless allowlist stays small (under 2 MB packed estimate)", allowed_bytes < 2.0 * 1048576.0)
	ctx.check("the 5 lv15 metal masks (1 armour + 4 weapon) and the digit sheet are allowlisted lossless", allowed.size() == 6)


func _estimate_packed(src: String, bytes: int, dims: Vector2i) -> float:
	var px := float(dims.x * dims.y)
	if src.get_extension().to_lower() == "png":
		return minf(float(bytes), px * LOSSLESS_BYTES_PER_PX)  # a PNG is already lossless: about its own size
	return maxf(float(bytes), px * LOSSLESS_BYTES_PER_PX)


func _load_exclude_filter() -> PackedStringArray:
	var out := PackedStringArray()
	var f := FileAccess.open("res://export_presets.cfg", FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("exclude_filter="):
			var raw := line.substr(line.find("=") + 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
			for p in raw.split(","):
				var t := p.strip_edges()
				if t != "":
					out.append(t)
			break
	return out


func _is_excluded(src: String) -> bool:
	var rel := src.trim_prefix("res://")
	for pat in _exclude:
		if rel.match(pat):
			return true
	return false


func _collect(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for sub in d.get_directories():
		_collect(dir_path + "/" + sub, out)
	for f in d.get_files():
		if f.ends_with(".import"):
			out.append(dir_path + "/" + f)


func _read_params(imp: String) -> Dictionary:
	var out := {}
	var f := FileAccess.open(imp, FileAccess.READ)
	if f == null:
		return out
	var in_params := false
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with("["):
			in_params = line == "[params]"
		elif in_params and line.contains("="):
			var i := line.find("=")
			out[line.substr(0, i)] = line.substr(i + 1)
	return out


func _file_len(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return 0 if f == null else f.get_length()


## Image size from the file header only (png / jpg); (0,0) when unknown.
func _dims(path: String) -> Vector2i:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return Vector2i.ZERO
	var ext := path.get_extension().to_lower()
	if ext == "png":
		var h := f.get_buffer(24)
		if h.size() < 24:
			return Vector2i.ZERO
		f.big_endian = true
		return Vector2i(_be32(h, 16), _be32(h, 20))
	if ext == "jpg" or ext == "jpeg":
		var data := f.get_buffer(mini(f.get_length(), 65536))
		var i := 2
		while i + 9 < data.size():
			if data[i] != 0xFF:
				i += 1
				continue
			var m: int = data[i + 1]
			if m >= 0xC0 and m <= 0xCF and m != 0xC4 and m != 0xC8 and m != 0xCC:
				return Vector2i((data[i + 7] << 8) | data[i + 8], (data[i + 5] << 8) | data[i + 6])
			i += 2 + ((data[i + 2] << 8) | data[i + 3])
		return Vector2i.ZERO
	return Vector2i.ZERO


func _be32(b: PackedByteArray, o: int) -> int:
	return (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]
