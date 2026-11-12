extends SceneTree
## Splits the exported web .pck into a core pack plus content packs (see tools/web/pack_layout.json).
## Run by tools/web/build_web.ps1:
##   godot --headless --path . --script res://tools/web/pck_split.gd -- <in.pck> <layout.json> <out_dir>
##   godot --headless --path . --script res://tools/web/pck_split.gd -- --list <in.pck>   (size per group)
##
## Why split after export: the exporter already converts everything (imports, remaps, binary scenes),
## so we only regroup its entries. Each imported file under .godot/imported|exported is kept with the
## .import/.remap entry that names it, so a pack never refers to data in another content pack.
## Scripts (.gd/.gdc/.gdshader...), scenes, data/ and project files always stay in the core pack.

const PackLayout := preload("res://client/pack_layout.gd")

const PRIVATE_ROOTS := ["build/", "server/", "pipeline/", "tools/", "tests/", "docs/", "ex/"]


static func safe_export_path(path: String) -> bool:
	var relative := path.trim_prefix("res://")
	if relative.contains(".."):
		return false
	for prefix in PRIVATE_ROOTS:
		if relative.begins_with(prefix):
			return false
	return true


var _entries: Array = []  # [{path, offset, size}]
var _file: FileAccess
var _format_order: Array = []  # texture formats in .import order = Godot's importer preference


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var code := 1
	if args.size() == 2 and args[0] == "--list":
		code = _list(args[1])
	elif args.size() == 3:
		code = _split(args[0], args[1], args[2])
	else:
		printerr("usage: -- <in.pck> <layout.json> <out_dir>  |  -- --list <in.pck>")
	quit(code)


func _read_dir(pck_path: String) -> bool:
	_file = FileAccess.open(pck_path, FileAccess.READ)
	if _file == null:
		printerr("cannot open " + pck_path)
		return false
	if _file.get_32() != 0x43504447:  # "GDPC"
		printerr("not a pck: " + pck_path)
		return false
	var version := _file.get_32()
	if version < 3:
		printerr("unsupported pck version %d" % version)
		return false
	_file.get_32(); _file.get_32(); _file.get_32()  # engine version
	var flags := _file.get_32()
	if flags & 1:
		printerr("encrypted pck directories are not supported")
		return false
	var file_base := _file.get_64()
	var dir_offset := _file.get_64()
	_file.seek(dir_offset)
	var count := _file.get_32()
	for i in count:
		var name_len := _file.get_32()
		var path := _file.get_buffer(name_len).get_string_from_utf8()
		var offset := _file.get_64()
		var size := _file.get_64()
		_file.get_buffer(16)  # md5
		var entry_flags := _file.get_32()
		if entry_flags & 1:
			printerr("encrypted files are not supported: " + path)
			return false
		if not path.begins_with("res://"):
			path = "res://" + path
		if not safe_export_path(path):
			printerr("Refusing development/private entry in Web export; check exclude_filter")
			return false
		_entries.append({"path": path, "offset": offset + (file_base if flags & 2 else 0), "size": size})
	return true


func _read_entry(entry: Dictionary) -> PackedByteArray:
	_file.seek(int(entry.offset))
	return _file.get_buffer(int(entry.size))


## pack name for every entry path, using the layout and the .import/.remap links. A content pack's
## GPU textures (path.s3tc=..., path.etc2=... in its .import files) go to "<pack>.<format>" packs so
## a device downloads only the format it can use. Core keeps every format (the page loads it whole).
func _assign(layout: Dictionary) -> Dictionary:
	var owner := {}
	for e in _entries:
		owner[e.path] = PackLayout.pack_for_path(layout, e.path)
	for e in _entries:
		var p: String = e.path
		if not (p.ends_with(".import") or p.ends_with(".remap")):
			continue
		var text := _read_entry(e).get_string_from_utf8()
		for target in PackLayout.linked_paths(text):
			if owner.has(target):
				owner[target] = owner[p]
		if owner[p] == PackLayout.CORE:
			continue
		var by_format := PackLayout.format_paths(text)
		if by_format.size() > 1:  # (one format only: nothing to choose between)
			var last := -1
			for fmt in by_format:
				if not _format_order.has(fmt):
					_format_order.append(fmt)
				if _format_order.find(fmt) < last:  # the loader's single format order would be wrong
					printerr("ERROR: %s lists texture formats in another order than %s" % [p, _format_order])
				last = _format_order.find(fmt)
				if owner.has(by_format[fmt]):
					owner[by_format[fmt]] = "%s.%s" % [owner[p], fmt]
	return owner


## base pack first, then its format variants in the importer's preference order
func _variant_rank(pack: String) -> int:
	var dot := pack.find(".")
	return -1 if dot < 0 else _format_order.find(pack.substr(dot + 1))


func _list(pck_path: String) -> int:
	if not _read_dir(pck_path):
		return 1
	var layout := {"packs": [{"name": "?", "include": [""]}]}
	var sizes := {}
	var owner_dir := {}
	for e in _entries:  # group by the source folder (2 levels), imported data counted with its source
		var p: String = e.path
		if p.ends_with(".import") or p.ends_with(".remap"):
			for target in PackLayout.linked_paths(_read_entry(e).get_string_from_utf8()):
				owner_dir[target] = _group(p)
	for e in _entries:
		var g: String = owner_dir.get(e.path, _group(e.path))
		sizes[g] = int(sizes.get(g, 0)) + int(e.size)
	var keys := sizes.keys()
	keys.sort_custom(func(a, b): return sizes[a] > sizes[b])
	for k in keys:
		print("%10.2f MB  %s" % [sizes[k] / 1048576.0, k])
	return 0


func _group(p: String) -> String:
	var parts := p.trim_prefix("res://").split("/")
	return "/".join(parts.slice(0, mini(3, parts.size() - 1))) if parts.size() > 1 else "(root)"


func _split(pck_path: String, layout_path: String, out_dir: String) -> int:
	if not _read_dir(pck_path):
		return 1
	var layout := PackLayout.read_layout(layout_path)
	if layout.is_empty() or not PackLayout.layout_errors(layout).is_empty():
		printerr("bad layout file %s %s" % [layout_path, PackLayout.layout_errors(layout)])
		return 1
	var owner := _assign(layout)
	var names := []  # layout order, each pack followed by its format variants
	for base in PackLayout.pack_names(layout):
		var variants := []
		for e in _entries:
			var n: String = owner[e.path]
			if (n == base or n.begins_with(base + ".")) and not names.has(n) and not variants.has(n):
				variants.append(n)
		variants.sort_custom(func(a, b): return _variant_rank(a) < _variant_rank(b))
		names.append_array(variants)
	var tmp := out_dir.path_join("_split_tmp")
	DirAccess.make_dir_recursive_absolute(tmp)
	var report := []
	for pack in names:
		var packer := PCKPacker.new()
		if packer.pck_start(out_dir.path_join(pack + ".pck"), 32) != OK:
			printerr("cannot write " + pack)
			return 1
		var count := 0
		var raw := 0
		for i in _entries.size():
			var e: Dictionary = _entries[i]
			if owner[e.path] != pack:
				continue
			var src := tmp.path_join("%d.bin" % i)
			var f := FileAccess.open(src, FileAccess.WRITE)
			f.store_buffer(_read_entry(e))
			f.close()
			if packer.add_file(e.path, src) != OK:
				printerr("cannot add %s to %s" % [e.path, pack])
				return 1
			count += 1
			raw += int(e.size)
		packer.flush()
		for i in _entries.size():
			if owner[_entries[i].path] == pack:
				DirAccess.remove_absolute(tmp.path_join("%d.bin" % i))
		var parts: PackedStringArray = str(pack).split(".")
		var stage := PackLayout.stage_of(layout, pack)
		report.append({"name": pack, "stage": stage, "format": parts[1] if parts.size() > 1 else "", "files": count, "content_bytes": raw})
		print("pack %-20s %-6s %5d files %8.2f MB" % [pack, stage, count, raw / 1048576.0])
	DirAccess.remove_absolute(tmp)
	var out := FileAccess.open(out_dir.path_join("split.json"), FileAccess.WRITE)
	out.store_string(JSON.stringify(report, "  "))
	return 0
