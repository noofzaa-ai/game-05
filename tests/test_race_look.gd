extends RefCounted
## Race look (Boss 2026-11-14): a card's race shows on the Studio character. data/races/<id>.json "look" names the
## Studio race head (art/characters/studio05/v1111/race/race_heads.glb, same 102-joint rig as the bodies) that
## replaces Head_Anime; Human keeps the default head. (Run `godot --headless --path . --import` after a .glb change.)

const StudioModel := preload("res://client/characters/studio05_character_model.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const CardDeck := preload("res://logic/card_deck.gd")
const HEADS := {"human": "", "elf": "Head_Anime_Elf", "viking": "Head_Anime_Viking", "runeborn": "Head_Anime_Runeborn"}


func run(ctx) -> void:
	for race in HEADS:
		var look := StudioModel.race_look(race)
		ctx.check("race %s look names its head (%s)" % [race, look], str(look.get("head", "")) == HEADS[race])
		if not str(look.get("head_file", "")).is_empty():
			ctx.check("race %s head file exists" % race, ResourceLoader.exists(str(look["head_file"])))
	ctx.check("runeborn has the rune overlay", StudioModel.race_look("runeborn").get("overlay", "") == "Runeborn_Face_Runes_Studio")
	ctx.check("an unknown or odd race id gives no look", StudioModel.race_look("goblin").is_empty() and StudioModel.race_look("../x").is_empty())

	var model := StudioModel.new()
	ctx.root.add_child(model)
	ctx.check("the studio model loads for the race look test", model.load_model())
	var default_head: MeshInstance3D = model.shown_head()
	ctx.check("no race: the default Studio head shows", default_head != null and str(default_head.name) == "Head_Anime")

	model.set_race_look("elf")
	var head: MeshInstance3D = model.shown_head()
	ctx.check("elf: the long-eared head shows", head != null and str(head.name) == "Head_Anime_Elf" and head.is_visible_in_tree())
	ctx.check("elf: the default head is hidden", not default_head.visible)
	ctx.check("elf: the race head is skinned to the body's skeleton", head != null and head.skin != null and head.get_node_or_null(head.skeleton) == model._skeleton)
	ctx.check("elf: the race head uses the toon face material", head != null and head.get_surface_override_material(0) is ShaderMaterial
		and int(head.get_surface_override_material(0).get_shader_parameter("part")) == 1)

	model.set_race_look("viking")
	var names: Array = model.race_meshes().map(func(m): return str(m.name))
	ctx.check("switching race removes the previous head (%s)" % [names], names == ["Head_Anime_Viking"])
	var viking: MeshInstance3D = model.shown_head()
	var paint: ShaderMaterial = viking.get_surface_override_material(0) if viking != null else null
	ctx.check("viking: the war paint texture is kept and the skin follows the card", paint != null and bool(paint.get_shader_parameter("use_albedo_tex"))
		and bool(paint.get_shader_parameter("albedo_is_paint")) and bool(paint.get_shader_parameter("rest_in_custom")))

	model.set_race_look("runeborn")
	names = model.race_meshes().map(func(m): return str(m.name))
	ctx.check("runeborn: head + rune overlay (%s)" % [names], names.has("Head_Anime_Runeborn") and names.has("Runeborn_Face_Runes_Studio") and names.size() == 2)

	model.set_race_look("human")
	ctx.check("human: the default head shows again, no race pieces", model.shown_head() == default_head and default_head.visible and model.race_meshes().is_empty())

	# The card path: CardDeck.look_of carries the race, card_appearance passes it on, the model shows it.
	var deck := CardDeck.initial()
	var card := "sword_shield"  # tutorial.md 2: a new deck has an empty squad
	deck["cards"][card]["race"] = "elf"
	var look := CardDeck.look_of(deck, card)
	model.dress({"class": card, "appearance": ItemAssets.card_appearance(look, ItemAssets.appearance({}))})
	ctx.check("a card's race reaches the model through its look", model.race_look_id() == "elf" and str(model.shown_head().name) == "Head_Anime_Elf")
	ctx.check("the race head takes the card's skin colour", _skin_of(model.shown_head()).is_equal_approx(_skin_of_default(model, default_head)))
	model.queue_free()


static func _skin_of(mesh: MeshInstance3D) -> Vector3:
	return mesh.get_surface_override_material(0).get_shader_parameter("base_color_linear") if mesh != null else Vector3.ZERO


static func _skin_of_default(_model, default_head: MeshInstance3D) -> Vector3:
	return _skin_of(default_head) if is_instance_valid(default_head) else Vector3(-1, -1, -1)
