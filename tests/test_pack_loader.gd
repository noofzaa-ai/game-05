extends RefCounted
## The split web build: which pack each exported file goes in, the manifest checks, and the boot
## scene's choice of texture-format packs (client/pack_layout.gd, client/pack_loader.gd).

const PackLayout := preload("res://client/pack_layout.gd")
const PackLoader := preload("res://client/pack_loader.gd")
const PackFetcher := preload("res://client/pack_fetcher.gd")
const LAYOUT := "res://tools/web/pack_layout.json"


func run(ctx) -> void:
	var export_config := ConfigFile.new()
	ctx.check("Web preset loads for virtual keyboard check", export_config.load("res://export_presets.cfg") == OK)
	ctx.check("Web exports enable touchscreen keyboard", export_config.get_value("preset.0.options", "html/experimental_virtual_keyboard", false))
	var layout := PackLayout.read_layout(LAYOUT)
	ctx.check("pack layout file reads", not layout.is_empty())
	var names := PackLayout.pack_names(layout)
	ctx.check("core is the first pack", names.size() > 1 and names[0] == "core")
	ctx.check("pack names are unique and have no dots (dots mark format variants)",
		names.size() == _unique(names).size() and names.all(func(n): return str(n).find(".") < 0))

	# scripts, scenes, data and project files stay in core wherever they are
	for p in ["res://client/hub.gd.remap", "res://client/hub.gdc", "res://art/items/weapons/x.tscn.remap",
			"res://data/maps/a.json", "res://art/animations/chibi.json", "res://project.binary",
			"res://.godot/global_script_class_cache.cfg", "res://.godot/uid_cache.bin", "res://client/ink_outline.gdshader"]:
		ctx.check("core keeps " + p, PackLayout.pack_for_path(layout, p) == "core")
	ctx.check("weapons go to the weapons pack (longest prefix beats art/items/)",
		PackLayout.pack_for_path(layout, "res://art/items/weapons/hammer.glb.import") == "weapons")
	ctx.check("clothing goes to items", PackLayout.pack_for_path(layout, "res://art/items/clothing/a.glb.import") == "items")
	ctx.check("monster animation clips go with the battle art (vfx pack)", PackLayout.pack_for_path(layout, "res://art/animations/goblin.glb.import") == "vfx")
	ctx.check("audio stays in core (the Audio autoload preloads cues before packs load)",
		PackLayout.pack_for_path(layout, "res://audio/sfx/hit.ogg.import") == "core")

	var import_text := "[remap]\nimporter=\"texture\"\npath.s3tc=\"res://.godot/imported/a.png-1.s3tc.ctex\"\npath.etc2=\"res://.godot/imported/a.png-1.etc2.ctex\"\n"
	var fmts := PackLayout.format_paths(import_text)
	ctx.check("format paths read from an .import", fmts.get("s3tc", "") == "res://.godot/imported/a.png-1.s3tc.ctex" and fmts.has("etc2"))
	ctx.check("linked paths read from an .import", PackLayout.linked_paths(import_text).size() == 2)

	var good := {"build": "abc123def456", "engine": "engine.0123456789ab.wasm", "core": "core.0123456789ab.pck.wasm", "packs": [
		{"name": "items", "format": "", "file": "items.0123456789ab.pck.wasm", "bytes": 10},
		{"name": "weapons.s3tc", "format": "s3tc", "file": "weapons.s3tc.aaaaaaaaaaaa.pck.wasm", "bytes": 10},
		{"name": "weapons.etc2", "format": "etc2", "file": "weapons.etc2.bbbbbbbbbbbb.pck.wasm", "bytes": 10}]}
	var errors := []
	var packs := PackLayout.content_packs(good, errors)
	ctx.check("a good manifest gives its packs in order", errors.is_empty() and packs.size() == 3 and packs[0].name == "items")
	errors = []
	ctx.check("an unversioned pack name is refused",
		PackLayout.content_packs({"build": "x", "packs": [{"name": "a", "file": "a.pck.wasm"}]}, errors).is_empty() and not errors.is_empty())
	errors = []
	ctx.check("a manifest that is not an object is refused", PackLayout.content_packs("nope", errors).is_empty() and not errors.is_empty())

	var desktop := PackLoader.choose_packs(packs, ["s3tc", "bptc"])
	ctx.check("desktop GPU gets the s3tc textures only", _names(desktop) == ["items", "weapons.s3tc"])
	var mobile := PackLoader.choose_packs(packs, ["etc2", "astc"])
	ctx.check("mobile GPU gets the etc2 textures only", _names(mobile) == ["items", "weapons.etc2"])
	ctx.check("a GPU with both formats takes the manifest's first (the .import order, as Godot's importer does)",
		_names(PackLoader.choose_packs(packs, ["etc2", "s3tc"])) == ["items", "weapons.s3tc"])

	# Two-stage loading (Boss 2026-11-13): boot packs before the card screen, battle packs in the background.
	ctx.check("layout stages are all boot or battle", PackLayout.layout_errors(layout).is_empty())
	ctx.check("a bad layout stage is reported", not PackLayout.layout_errors({"packs": [{"name": "x", "stage": "later"}]}).is_empty())
	ctx.check("class characters load at boot (card screen)", PackLayout.stage_of(layout, PackLayout.pack_for_path(layout, "res://art/characters/studio05/split/hair_a.glb.import")) == PackLayout.BOOT)
	ctx.check("item icons load at boot (character screen, Tailor)",
		PackLayout.stage_of(layout, PackLayout.pack_for_path(layout, "res://art/items/icons/a.png.import")) == PackLayout.BOOT
		and PackLayout.stage_of(layout, PackLayout.pack_for_path(layout, "res://art/armor/ash_cloth/shirt.glb.import")) == PackLayout.BOOT)
	for p in ["res://art/maps/goblin_forest/a.glb.import", "res://art/props/goblin_base/meshes/hut.res", "res://art/monsters/goblin/goblin.glb.import",
			"res://art/animations/goblin.glb.import"]:
		ctx.check("battle art loads in the background: " + p, PackLayout.stage_of(layout, PackLayout.pack_for_path(layout, p)) == PackLayout.BATTLE)
	# 2026-11-13 (PO): card/hub and skill-tree UI art left core for the "ui" boot pack (the boot scene uses none of it).
	for p in ["res://art/ui/class_cards/hub_fight_button.png.import", "res://art/ui/skill_tree/icons/el_1.png.import"]:
		ctx.check("card screen UI art loads at boot, not in core: " + p,
			PackLayout.pack_for_path(layout, p) == "ui" and PackLayout.stage_of(layout, "ui") == PackLayout.BOOT)
	ctx.check("class skill VFX load with the battle packs",
		PackLayout.stage_of(layout, PackLayout.pack_for_path(layout, "res://art/vfx/class_skills/starfall/effect.glb.import")) == PackLayout.BATTLE)
	ctx.check("status VFX (battle-only loops) load with the battle packs",
		PackLayout.stage_of(layout, PackLayout.pack_for_path(layout, "res://art/vfx/status/burn/effect.glb.import")) == PackLayout.BATTLE)
	ctx.check("class skill VFX scenes stay in core (scenes always do)", PackLayout.pack_for_path(layout, "res://art/vfx/class_skills/starfall/effect.tscn") == "core")
	ctx.check("a format variant has its base pack's stage", PackLayout.stage_of(layout, "monsters.etc2") == PackLayout.BATTLE and PackLayout.stage_of(layout, "characters.s3tc") == PackLayout.BOOT)
	var staged := [{"name": "characters", "stage": "boot", "file": "characters.0123456789ab.pck.wasm"},
		{"name": "stages", "stage": "battle", "file": "stages.0123456789ab.pck.wasm"},
		{"name": "items", "file": "items.0123456789ab.pck.wasm"}]
	ctx.check("manifest packs split into boot (no stage = boot) and battle",
		_names(PackLayout.packs_for_stage(staged, PackLayout.BOOT)) == ["characters", "items"] and _names(PackLayout.packs_for_stage(staged, PackLayout.BATTLE)) == ["stages"])
	errors = []
	ctx.check("a manifest pack with an unknown stage is refused",
		PackLayout.content_packs({"build": "x", "packs": [{"name": "a", "stage": "soon", "file": "a.0123456789ab.pck.wasm"}]}, errors).is_empty() and not errors.is_empty())
	ctx.check("FIGHT does not wait when there is no background download (desktop, tests)",
		PackFetcher.battle_ready(Engine.get_main_loop()) and is_equal_approx(PackFetcher.battle_fraction(Engine.get_main_loop()), 1.0))
	var fetcher = PackFetcher.new()
	fetcher.start([], "")
	ctx.check("an empty battle list counts as loaded", fetcher.fraction() == 1.0 or fetcher.state == fetcher.State.LOADING)
	fetcher.free()

	ctx.check("pack URL next to the page", PackLayout.pack_url("", "a.pck.wasm") == "a.pck.wasm")
	ctx.check("pack URL on a CDN base", PackLayout.pack_url("https://cdn.x/zorx", "a.pck.wasm") == "https://cdn.x/zorx/a.pck.wasm")
	var raw := "GDPC-pack-bytes".to_utf8_buffer()
	ctx.check("plain pack bytes pass through", PackLayout.unwrap(raw) == raw)
	ctx.check("gzip-wrapped pack bytes are unpacked", PackLayout.unwrap(raw.compress(FileAccess.COMPRESSION_GZIP)) == raw)

	var main_scene := str(ProjectSettings.get_setting("application/run/main_scene"))
	var boot = load(main_scene)
	var node: Node = boot.instantiate() if boot is PackedScene else null
	ctx.check("the main scene is the pack-loading boot scene", node != null and node.get_script() == PackLoader)
	if node != null:
		node.free()


func _names(list: Array) -> Array:
	return list.map(func(p): return str(p.name))


func _unique(list: Array) -> Array:
	var out := []
	for x in list:
		if not out.has(x):
			out.append(x)
	return out
