extends RefCounted
## Tests the player's own looks: the choices in data/cosmetics (logic/cosmetic_options.gd), how the
## model shows them (face and hair items, replacement heads, skin and hair colors), the camp's Look tab,
## the character creator and the character by the campfire.

const CampDataLoader := preload("res://logic/camp_data_loader.gd")
const CharacterCreator := preload("res://client/character_creator.gd")
const CharacterModel := preload("res://client/character_model.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const CosmeticOptions := preload("res://logic/cosmetic_options.gd")
const InkStyle := preload("res://client/ink_style.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const LookPanel := preload("res://client/look_panel.gd")
const Profile := preload("res://logic/profile.gd")


func _frames(ctx, count: int = 2) -> void:
	for i in count:
		await ctx.process_frame


func _body_part(model, part_name: String) -> MeshInstance3D:
	for mesh in model._body_meshes:
		if str(mesh.name) == part_name:
			return mesh
	return null


func _color_of(mesh: MeshInstance3D) -> Color:
	return (mesh.get_active_material(0) as BaseMaterial3D).albedo_color


func run(ctx) -> void:
	# The data.
	var options = CosmeticOptions.load_default()
	ctx.check("the cosmetics data loads without errors %s" % [options.errors], options.is_valid())
	for part in CosmeticOptions.PARTS:
		ctx.check("%s offers choices and a default (%d)" % [part, options.choices[part].size()], options.choices[part].size() >= 2 and not options.entry(part, options.defaults[part]).is_empty())
	for part in CosmeticOptions.MODEL_PARTS:
		var missing: Array = options.choices[part].filter(func(choice): return not choice["asset_id"].is_empty() and ItemAssets.path(choice["asset_id"], choice.get("archived", false)).is_empty())
		ctx.check("every %s is a model of the model team (missing: %s)" % [part, missing], missing.is_empty())
		var no_picture: Array = options.choices[part].filter(func(choice): return LookPanel.icon_file(part, choice).is_empty())
		ctx.check("every %s has a picture for its button (missing: %s)" % [part, no_picture], no_picture.is_empty())

	# The rules.
	var broken = CosmeticOptions.parse({"skin": "{\"default\": \"x\", \"colors\": [{\"id\": \"a\", \"color\": \"#zz\"}, {\"id\": \"b\", \"color\": \"#ffffff\"}, {\"id\": \"b\", \"color\": \"#000000\"}]}", "face": "not json"})
	ctx.check("mistakes are reported, not crashed on (bad color, twice-used id, bad default, broken and two missing files: %d)" % broken.errors.size(), broken.errors.size() == 4 + CosmeticOptions.PARTS.size() - 2 and broken.choices["skin"].size() == 1 and broken.defaults["skin"] == "b")
	var chosen := {}
	ctx.check("nothing picked = the defaults", options.resolve(chosen)["skin"]["id"] == options.defaults["skin"])
	ctx.check("an unknown choice is refused and changes nothing", not options.choose(chosen, "skin", "green_goblin") and chosen.is_empty())
	ctx.check("a known choice is kept", options.choose(chosen, "skin", "deep") and options.resolve(chosen)["skin"]["id"] == "deep")
	chosen["skin"] = "no_longer_offered"
	ctx.check("a choice the data dropped falls back to the default", options.resolve(chosen)["skin"]["id"] == options.defaults["skin"])
	ctx.check("the old face / hair-style / fashion lists are gone (Boss 2026-11-13)", not CosmeticOptions.PARTS.has("face") and not CosmeticOptions.PARTS.has("hair_style") and not CosmeticOptions.PARTS.has("fashion"))

	# The model.
	var model := CharacterModel.new()
	ctx.root.add_child(model)
	ctx.check("the model loads for the looks test", model.load_model("res://art/characters/chibi-studio/chibi_base_animated.glb"))
	var other := CharacterModel.new()
	ctx.root.add_child(other)
	other.load_model("res://art/characters/chibi-studio/chibi_base_animated.glb")
	model.set_appearance({"skin": Color("#4a2e20")})
	ctx.check("the skin takes its color", _color_of(_body_part(model, "Hands articulated")).is_equal_approx(Color("#4a2e20")))
	ctx.check("another character keeps its own colors (materials are not shared)", not _color_of(_body_part(other, "Hands articulated")).is_equal_approx(Color("#4a2e20")))

	# Clothes over skin.
	var body := _body_part(model, "Body continuous")
	var bare_body: Mesh = body.mesh
	var clothed := {"shirt": ItemAssets.path("clothing_oathkeeper_cuirass_01"), "pants": ItemAssets.path("clothing_oathkeeper_breeches_01"), "shoes": "", "hat": "", "armband": ""}
	ctx.check("the clothes for the fit test exist", not clothed["shirt"].is_empty() and not clothed["pants"].is_empty())
	model.dress(clothed)
	var fitted: Mesh = body.mesh
	var before: PackedVector3Array = bare_body.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var after: PackedVector3Array = fitted.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var pulled := 0
	var kept_high := true  # nothing above the collar moves
	for index in before.size():
		if not before[index].is_equal_approx(after[index]):
			pulled += 1
			kept_high = kept_high and before[index].y < 1.25
	ctx.check("skin under the clothes is pulled in so it cannot poke through (%d corners)" % pulled, fitted != bare_body and pulled > 500 and kept_high)
	ctx.check("its outline follows the fitted shape", model.outline_of(body) == null or model.outline_of(body).mesh == InkStyle.outline_mesh(fitted))
	model.dress({"shirt": clothed["shirt"], "pants": clothed["pants"]})
	ctx.check("the same clothes give the same (kept) shape", body.mesh == fitted)
	model.dress({"shirt": "", "pants": "", "shoes": "", "hat": "", "armband": ""})
	ctx.check("taking them off gives the bare body back", body.mesh == bare_body)
	model.set_appearance({"skin": Color("#6e4630")})
	model.dress({"pants": ItemAssets.path("clothing_shorts_basic_01")})
	ctx.check("clothes made of the clay material keep their own color (it is cloth there, not skin)", model._worn.has("pants") and model._worn["pants"]["meshes"].all(func(mesh): return not mesh.get_active_material(0).albedo_color.is_equal_approx(Color("#6e4630"))))
	model.queue_free()
	other.queue_free()

	# (The camp Look tab was cut with the campfire; the creator below still uses the look panel.)
	var rules := ItemRulesLoader.load_default()
	var camp := CampDataLoader.load_default(rules.tiers.size())
	var combat := CombatDataLoader.load_default()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var profile = Profile.new_player(rules, camp, rng)

	# Names and the dice.
	for case in [["Ink", ""], ["นักดาบ", ""], ["  Mo  ", ""], ["A", "too_short"], ["Abcdefghijklmnopq", "too_long"], ["<script>", "bad_characters"], ["two  spaces", "bad_characters"]]:
		ctx.check("the name '%s' -> '%s'" % case, Profile.name_problem(case[0]) == case[1])
	var dice := RandomNumberGenerator.new()
	dice.seed = 11
	var rolled: Dictionary = options.random(dice)
	ctx.check("a random look picks a valid choice for every part", rolled.size() == CosmeticOptions.PARTS.size() and rolled.keys().all(func(part): return not options.entry(part, rolled[part]).is_empty()))

	# The creator.
	var fresh = Profile.new_player(rules, camp, rng)
	ctx.check("a new player has no character yet", not fresh.created and fresh.name == "")
	var creator: CanvasLayer = CharacterCreator.new()
	ctx.root.add_child(creator)
	creator.setup(fresh, rules, combat)
	await _frames(ctx)
	ctx.check("Start waits for a name", creator.start_button.disabled)
	ctx.check("name allows the platform virtual keyboard", creator.name_field.virtual_keyboard_enabled)
	var saved_size: Vector2i = ctx.root.size
	for phone_size in [Vector2i(844, 390), Vector2i(667, 375), Vector2i(932, 430)]:
		ctx.root.size = phone_size
		creator._apply_layout()
		await _frames(ctx)
		var bounds: Rect2 = ctx.root.get_visible_rect()
		ctx.check("creator footer fits landscape %s" % phone_size, bounds.encloses(creator.start_button.get_global_rect()) and bounds.encloses(creator.name_field.get_global_rect()))
		ctx.check("creator preview fits above footer %s" % phone_size, creator.look.get_global_rect().end.y <= creator.name_field.get_global_rect().position.y)
	ctx.root.size = saved_size
	creator._apply_layout()
	await _frames(ctx)
	creator.name_field.text = "<x>"
	creator.name_field.text_changed.emit(creator.name_field.text)
	ctx.check("a bad name keeps Start off and says why", creator.start_button.disabled and creator._problem.text != "")
	creator.randomize_look()
	ctx.check("the dice gives the character a whole look", fresh.appearance.size() == CosmeticOptions.PARTS.size())
	var made := [false]
	creator.created.connect(func() -> void: made[0] = true)
	creator.name_field.text = " Mira "
	creator.name_field.text_changed.emit(creator.name_field.text)
	ctx.check("a good name turns Start on", not creator.start_button.disabled)
	creator.start_button.pressed.emit()
	await _frames(ctx)
	ctx.check("Start makes the character (name trimmed) and closes the creator", fresh.created and fresh.name == "Mira" and made[0] and not is_instance_valid(creator))
