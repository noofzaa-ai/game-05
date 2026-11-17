extends "res://tools/web/pck_split.gd"
## Lists every file of an exported web .pck with its size, the content pack it lands in and the source file
## that owns it (imported textures/meshes are counted with their .import/.remap):
##   godot --headless --path . --script res://tools/web/pack_files.gd -- <in.pck> <layout.json> <out.tsv>
## Columns: entry path, bytes, pack, owner source path. Used by docs/tech/unused_assets_*.md to rank the shipped files.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		printerr("usage: -- <in.pck> <layout.json> <out.tsv>")
		quit(1)
		return
	if not _read_dir(args[0]):
		quit(1)
		return
	var layout := PackLayout.read_layout(args[1])
	var owner := _assign(layout)
	var source_of := {}
	for e in _entries:
		var p: String = e.path
		if p.ends_with(".import") or p.ends_with(".remap"):
			for target in PackLayout.linked_paths(_read_entry(e).get_string_from_utf8()):
				source_of[target] = p.trim_suffix(".import").trim_suffix(".remap")
	var out := FileAccess.open(args[2], FileAccess.WRITE)
	for e in _entries:
		var p: String = e.path
		out.store_line("%s\t%d\t%s\t%s" % [p, int(e.size), owner.get(p, "?"), source_of.get(p, p)])
	out.close()
	quit(0)
