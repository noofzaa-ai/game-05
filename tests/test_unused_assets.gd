extends RefCounted
## Download-size guard (docs/tech/unused_assets_2026-11-17.md): loose outfit/hair textures next to a GLB that already embeds the
## same image are shipped but never loaded (3.9 MB found that way). NOTE: the loose VFX frames beside art/vfx effect.glb ARE loaded (the imported scn references them), do not add them here. Fails when
## one appears again. Full report: python tools/assets/unused_assets.py --shipped <pack_files.tsv>.
const ROOTS := ["res://art/characters/studio05/v1111"]


func run(ctx) -> void:
	var loose: Array = []
	for root in ROOTS:
		_scan(root, loose)
	ctx.check("unused assets: no loose outfit/hair texture beside an embedding GLB (%s)" % [loose.slice(0, 5)], loose.is_empty())


func _scan(dir_path: String, loose: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_scan(dir_path + "/" + sub, loose)
	for file in dir.get_files():
		if file.ends_with(".import") or not (file.ends_with(".png") or file.ends_with(".jpg")):
			continue
		if "_texture_pbr_20250901" in file:
			loose.append(dir_path + "/" + file)
