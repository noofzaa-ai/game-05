extends RefCounted
## Download-size guard (docs/tech/unused_assets_2026-11-17.md): loose textures that sit next to a GLB which already embeds the
## same image are shipped but never loaded (11 MB of VFX frames and 4 MB of outfit textures were found that way). Fails when
## one appears again. Full report: python tools/assets/unused_assets.py --shipped <pack_files.tsv>.
const ROOTS := ["res://art/vfx/class_skills", "res://art/vfx/status", "res://art/characters/studio05/v1111"]


func run(ctx) -> void:
	var loose: Array = []
	for root in ROOTS:
		_scan(root, loose)
	ctx.check("unused assets: no loose VFX frame / outfit texture beside an embedding GLB (%s)" % [loose.slice(0, 5)], loose.is_empty())


func _scan(dir_path: String, loose: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_scan(dir_path + "/" + sub, loose)
	for file in dir.get_files():
		if file.ends_with(".import") or not (file.ends_with(".png") or file.ends_with(".jpg")):
			continue
		var frame := file.begins_with("effect_") and " phase " in file
		var duplicate := "_texture_pbr_20250901" in file or file.begins_with("race_heads_")
		if frame or duplicate:
			loose.append(dir_path + "/" + file)
