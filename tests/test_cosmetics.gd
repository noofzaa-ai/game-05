extends RefCounted
## Tests the player's own looks: the choices in data/cosmetics (logic/cosmetic_options.gd), how the
## model shows them (face and hair items, replacement heads, skin and hair colors), the camp's Look tab,
## the character creator and the character by the campfire.

const CampDataLoader := preload("res://logic/camp_data_loader.gd")
const CampScreen := preload("res://client/camp_screen.gd")
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
	ctx.check("the body's own hair is offered", options.entry("hair_style", "original").get("asset_id", "?") == "")
	ctx.check("every face choice is a real face (Boss 2026-10-08: no plain clay face, no faceless heads)", options.choices["face"].all(func(face): return not face["asset_id"].is_empty() and not ItemAssets.entry(face["asset_id"]).get("replaces_head", false)))
	ctx.check("there are 31 hair styles from the model team (+ the body's own)", options.choices["hair_style"].size() == 32)
	ctx.check("hair can keep each style's own colors", options.entry("hair_color", "natural").get("natural", false))

	# The rules.
	var broken = CosmeticOptions.parse({"skin": "{\"default\": \"x\", \"colors\": [{\"id\": \"a\", \"color\": \"#zz\"}, {\"id\": \"b\", \"color\": \"#ffffff\"}, {\"id\": \"b\", \"color\": \"#000000\"}]}", "face": "not json"})
	ctx.check("mistakes are reported, not crashed on (bad color, twice-used id, bad default, broken and two missing files: %d)" % broken.errors.size(), broken.errors.size() == 6 and broken.choices["skin"].size() == 1 and broken.defaults["skin"] == "b")
	var chosen := {}
	ctx.check("nothing picked = the defaults", options.resolve(chosen)["skin"]["id"] == options.defaults["skin"] and options.resolve(chosen)["face"]["id"] == options.defaults["face"])
	ctx.check("an unknown choice is refused and changes nothing", not options.choose(chosen, "skin", "green_goblin") and chosen.is_empty())
	ctx.check("a known choice is kept", options.choose(chosen, "skin", "deep") and options.resolve(chosen)["skin"]["id"] == "deep")
	chosen["face"] = "no_longer_offered"
	ctx.check("a choice the data dropped falls back to the default", options.resolve(chosen)["face"]["id"] == options.defaults["face"])
	var looks := ItemAssets.appearance({"skin": "deep", "hair_color": "blonde", "face": "devious"})
	ctx.check("the choices become colors and a face model for the character", looks["skin"].is_equal_approx(Color("#4a2e20")) and looks["hair"].is_equal_approx(Color("#d9b56a")) and looks["face"].ends_with("face_devious_01.glb"))

	# The model.
	var model := CharacterModel.new()
	ctx.root.add_child(model)
	ctx.check("the model loads for the looks test", model.load_model("res://art/characters/chibi-studio/chibi_base_animated.glb"))
	var other := CharacterModel.new()
	ctx.root.add_child(other)
	other.load_model("res://art/characters/chibi-studio/chibi_base_animated.glb")
	var mouth := _body_part(model, "Mouth")
	model.set_appearance(looks)
	ctx.check("a face item is worn on the head and the body's own face features are hidden", model.face_path() == looks["face"] and model._face_node != null and mouth != null and not mouth.visible)
	ctx.check("the skin takes its color", _color_of(_body_part(model, "Face")).is_equal_approx(looks["skin"]) and _color_of(_body_part(model, "Hands articulated")).is_equal_approx(looks["skin"]))
	ctx.check("the hair and brows take the hair color", model._hair_meshes.size() > 0 and model._hair_meshes.all(func(mesh): return _color_of(mesh).is_equal_approx(looks["hair"])) and _color_of(_body_part(model, "Brow_L")).is_equal_approx(looks["hair"]))
	ctx.check("another character keeps its own colors (materials are not shared)", not _color_of(_body_part(other, "Face")).is_equal_approx(looks["skin"]))
	model.dress({"appearance": {"face": ""}})
	ctx.check("the plain face takes the face item off and shows the body's own again", model.face_path() == "" and model._face_node == null and mouth.visible)

	# Whole replacement heads.
	# (none is offered now, but the model still supports them for when the model team makes heads with faces)
	var head_skin := Color("#4a2e20")
	model.set_appearance({"face": ItemAssets.path("head_smooth_brain_01", true), "face_replaces_head": true, "face_hides_hair": true, "skin": head_skin})
	ctx.check("a replacement head hides the body's own head, face and hair", model.face_path().ends_with("head_smooth_brain_01.glb") and not _body_part(model, "Face").visible and not _body_part(model, "Nose").visible and not mouth.visible and not model.is_hair_shown())
	ctx.check("and takes the skin color", model._face_meshes.size() > 0 and _color_of(model._face_meshes[0]).is_equal_approx(head_skin))
	model.set_appearance(ItemAssets.appearance({"face": "smile"}))
	ctx.check("a normal face brings the head and hair back", _body_part(model, "Face").visible and model.is_hair_shown() and not mouth.visible)

	# Hair styles.
	var styled := ItemAssets.appearance({"hair_style": "cat_ears", "hair_color": "natural"})
	model.ink_outline = true
	model.set_appearance(styled)
	var strands: Array = model._hair_item_meshes
	ctx.check("a hair style is worn on the head and the body's own hair is hidden", model.hair_style_path().ends_with("hair_row4_cat_ears_01.glb") and strands.size() > 0 and model._hair_meshes.all(func(mesh): return not mesh.visible) and model.is_hair_shown())
	ctx.check("its pieces get the ink outline like the body", strands.all(func(mesh): return mesh in model._meshes and model.outline_of(mesh) != null))
	var designed: Array = strands.map(func(mesh): return _color_of(mesh))
	ctx.check("natural = the style's own designed colors", strands.all(func(mesh): return _color_of(mesh).is_equal_approx(mesh.get_active_material(0).get_meta("style_color"))))
	model.set_appearance(ItemAssets.appearance({"hair_style": "cat_ears", "hair_color": "jade_green"}))
	var green := Color("#2f7d62")
	ctx.check("a hair color dyes the style, keeping darker and lighter parts", strands.all(func(mesh): var c := _color_of(mesh); return c.g > c.r and c.g <= green.g + 0.001) and strands.any(func(mesh): return _color_of(mesh).is_equal_approx(green)))
	model.set_appearance(ItemAssets.appearance({"hair_style": "cat_ears", "hair_color": "natural"}))
	ctx.check("and natural brings the designed colors back", strands.map(func(mesh): return _color_of(mesh)) == designed)
	model.dress({"hide_hair": true})
	ctx.check("a hat that hides hair hides the hair style", not model.is_hair_shown() and not model._hair_node.visible)
	model.dress({"hide_hair": false})
	ctx.check("and it comes back without the hat", model.is_hair_shown())
	model.set_appearance({"hair_style": ""})
	ctx.check("the body's own hair comes back when no style is worn", model._hair_node == null and model._hair_meshes.all(func(mesh): return mesh.visible) and strands.all(func(mesh): return not mesh in model._meshes))

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

	# The Look tab.
	var rules := ItemRulesLoader.load_default()
	var camp := CampDataLoader.load_default(rules.tiers.size())
	var combat := CombatDataLoader.load_default()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var profile = Profile.new_player(rules, camp, rng)
	var screen: CanvasLayer = CampScreen.new()
	ctx.root.add_child(screen)
	screen.setup(profile, camp, rules, combat)
	await _frames(ctx)
	var look = screen.look
	ctx.check("the camp has a Look tab with the face, hair, hair color and skin choices", look != null and look._buttons.has("face") and look._buttons["hair_style"].size() == 32 and look._buttons["skin"].size() == options.choices["skin"].size() and look._buttons.has("hair_color"))
	ctx.check("Look has three category tabs", look._tabs.size() == 3 and look.selected_tab == "face")
	look.show_tab("hair")
	ctx.check("hair page hides other choices", look._pages["hair"].get_parent().visible and not look._pages["face"].get_parent().visible)
	look.show_tab("colors")
	ctx.check("color page shows independently", look._pages["colors"].get_parent().visible and not look._pages["hair"].get_parent().visible)
	look.show_tab("face")
	ctx.check("cosmetic icons use enlarged width", look._buttons["face"]["vampire"].get_theme_constant("icon_max_width") == 88)
	var camp_size: Vector2i = ctx.root.size
	screen.show_tab(1)
	for phone in [Vector2i(844, 390), Vector2i(667, 375)]:
		ctx.root.size = phone
		screen._apply_layout()
		await _frames(ctx)
		ctx.check("Look preview fits %s" % phone, ctx.root.get_visible_rect().encloses(look._doll_holder.get_global_rect()))
		ctx.check("Look tabs fit %s" % phone, ctx.root.get_visible_rect().encloses(look._tabs["colors"].get_global_rect()))
	ctx.root.size = camp_size
	screen._apply_layout()
	await _frames(ctx)
	ctx.check("the defaults are shown picked", look.picked_id("skin") == options.defaults["skin"] and look._buttons["skin"][options.defaults["skin"]].button_pressed)
	# Legacy cosmetic fixtures use the body those items were fitted to.
	look.doll.model.load_model("res://art/characters/chibi-studio/chibi_base_animated.glb")
	screen.gear.doll.model.load_model("res://art/characters/chibi-studio/chibi_base_animated.glb")
	look._buttons["skin"]["tan"].pressed.emit()
	look._buttons["face"]["vampire"].pressed.emit()
	await _frames(ctx)
	look._buttons["hair_style"]["topknot"].pressed.emit()
	await _frames(ctx)
	ctx.check("pressing a choice puts it in the profile", profile.appearance.get("skin") == "tan" and profile.appearance.get("face") == "vampire" and profile.appearance.get("hair_style") == "topknot")
	ctx.check("the doll wears the hair style", look.doll.model.hair_style_path().ends_with("hair_row2_topknot_01.glb"))
	ctx.check("the button shows as picked and the old one not", look._buttons["skin"]["tan"].button_pressed and not look._buttons["skin"][options.defaults["skin"]].button_pressed)
	ctx.check("the Look doll wears it", look.doll.model != null and look.doll.model.face_path().ends_with("face_vampire_01.glb"))
	ctx.check("the inventory's doll wears it too", screen.gear.doll.model.face_path().ends_with("face_vampire_01.glb"))
	screen.queue_free()
	await _frames(ctx)

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
