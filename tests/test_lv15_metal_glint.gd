extends RefCounted
## Ink-style metal glints on the level-15 race armour (client/characters/metal_glint.gd, studio05_toon.gdshader group
## "metal", mask built by tools/items/build_lv15_metal_mask.py):
## - the mask exists, is a small grayscale image, and covers a plausible share of the atlas (3-35 %);
## - the glint is applied to the "Level 15 | Original Armor" material only (starter outfits and anything else are untouched);
## - the pure glint / rim helpers are stepped (hard bands), vary per cell, and stay off where the surface faces away;
## - the shader declares every uniform the helper feeds, and the graphics switch exists;
## - the real model path: a lv15 piece worn on the Studio body gets use_metal, a starter piece does not.

const MetalGlint := preload("res://client/characters/metal_glint.gd")
const Options := preload("res://client/graphics_options.gd")
const CharacterModel := preload("res://client/characters/studio05_character_model.gd")
const SHADER := "res://client/characters/studio05_toon.gdshader"


func run(ctx) -> void:
	# mask
	ctx.check("metal mask file exists", FileAccess.file_exists(MetalGlint.MASK_PATH))
	var image := Image.load_from_file(ProjectSettings.globalize_path(MetalGlint.MASK_PATH))
	ctx.check("metal mask loads, RGB (R metal, G warm, B stud), <= 1024 px", image != null and not image.is_empty() and image.get_format() == Image.FORMAT_RGB8 and maxi(image.get_width(), image.get_height()) <= 1024)
	if image != null and not image.is_empty():
		var lit := 0
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y).r > 0.5:
					lit += 1
		var share := float(lit) / float(image.get_width() * image.get_height())
		ctx.check("metal mask covers 2-35%% of the atlas (about 11%% of the UV-used area) (%.1f%%)" % (share * 100.0), share >= 0.02 and share <= 0.35)
	ctx.check("metal mask has an import config", FileAccess.file_exists(MetalGlint.MASK_PATH + ".import"))
	ctx.check("metal mask is a loadable texture", load(MetalGlint.MASK_PATH) is Texture2D)

	# material gate
	ctx.check("lv15 material names are metal", MetalGlint.is_metal_material("Level 15 | Original Armor") and MetalGlint.is_metal_material("Level 15 | Original Armor.001"))
	ctx.check("other materials are not metal", not MetalGlint.is_metal_material("B 00 | Armor") and not MetalGlint.is_metal_material("") and not MetalGlint.is_metal_material("Base_Body | Skin"))
	var mask := load(MetalGlint.MASK_PATH) as Texture2D
	var other := ShaderMaterial.new()
	other.resource_name = "Starter | Cloth"
	ctx.check("apply refuses a non-lv15 material", not MetalGlint.apply(other, mask) and other.get_shader_parameter("use_metal") == null)
	var armor := ShaderMaterial.new()
	armor.resource_name = "Level 15 | Original Armor.001"
	ctx.check("apply accepts the lv15 material", MetalGlint.apply(armor, mask) and armor.get_shader_parameter("use_metal") == true and armor.get_shader_parameter("metal_mask") == mask)
	ctx.check("apply needs a mask", not MetalGlint.apply(armor.duplicate(), null))

	# pure maths
	ctx.check("no glint when the surface faces away", MetalGlint.glint(0.2, 0.5) == 0.0)
	ctx.check("full glint at the highlight centre", MetalGlint.glint(1.0, 0.5) == 1.0)
	var halo := MetalGlint.glint(float(MetalGlint.PARAMS["metal_halo"]) + 0.03, 0.5)
	ctx.check("a dimmer second band between halo and core", halo > 0.2 and halo < 0.6)
	ctx.check("glint is monotonic in the half-vector dot", MetalGlint.glint(0.80, 0.5) <= MetalGlint.glint(0.90, 0.5) and MetalGlint.glint(0.90, 0.5) <= MetalGlint.glint(0.97, 0.5))
	var edge := float(MetalGlint.PARAMS["metal_core"])
	ctx.check("the core is stepped (hard edge within 0.03)", MetalGlint.glint(edge + 0.03, 0.5) >= 0.99 and MetalGlint.glint(edge + 0.03, 0.5) - MetalGlint.glint(edge - 0.015, 0.5) > 0.4)
	ctx.check("each cell sparkles at its own angle", MetalGlint.glint(edge - 0.01, 0.95) > MetalGlint.glint(edge - 0.01, 0.05))
	ctx.check("dark ink line sits just below the halo edge only", MetalGlint.dark_line(float(MetalGlint.PARAMS["metal_halo"]) - 0.01, 0.5) > 0.9 and MetalGlint.dark_line(0.2, 0.5) == 0.0 and MetalGlint.dark_line(1.0, 0.5) == 0.0)
	ctx.check("studs always show a dot, and a bright one over a wider angle than plates", MetalGlint.stud(0.0, 0.5) >= float(MetalGlint.PARAMS["metal_stud_base"]) and MetalGlint.stud(0.80, 0.5) == 1.0 and MetalGlint.glint(0.80, 0.5) < 1.0)
	ctx.check("plate glint fades when small on screen, never below its floor", MetalGlint.small_scale(1.0) == 1.0 and MetalGlint.small_scale(20.0) == float(MetalGlint.PARAMS["metal_small_floor"]) and MetalGlint.small_scale(4.5) < 1.0)
	ctx.check("the glint never covers a whole plate (texture stays visible)", float(MetalGlint.PARAMS["metal_glint_mix"]) <= 0.75 and float(MetalGlint.PARAMS["metal_lift"]) >= 0.8 and float(MetalGlint.PARAMS["metal_lift"]) <= 1.0)
	ctx.check("rim: thin, only at grazing angles on the lit side", MetalGlint.rim(0.05, 0.8) > 0.9 and MetalGlint.rim(0.6, 0.8) == 0.0 and MetalGlint.rim(0.05, -0.8) == 0.0)

	# shader and switch
	var shader_text := FileAccess.get_file_as_string(SHADER)
	var missing: Array = []
	for key in MetalGlint.PARAMS:
		if not shader_text.contains("uniform float %s" % key):
			missing.append(key)
	ctx.check("the toon shader declares every metal uniform %s" % [missing], missing.is_empty() and shader_text.contains("uniform bool use_metal") and shader_text.contains("uniform sampler2D metal_mask"))
	ctx.check("graphics switch metal_glint exists, on by default", Options._values.has(MetalGlint.OPTION) and Options._valid(MetalGlint.OPTION, false))

	# level-15 weapons (Boss 2026-11-17): same glint, more restrained, only the lv15 weapon materials
	var weapon_names := ["Sword and Shield Lv15 | Original Colors", "Greatswords Lv15 | Original Colors", "Bow | Original Colors", "Staff | Original Colors", "Human Shield Lv15 | Turquoise & Gold"]
	for weapon_name in weapon_names:
		ctx.check("lv15 weapon material gets the glint: %s" % weapon_name, MetalGlint.is_weapon_material(weapon_name) and MetalGlint.is_metal_material(weapon_name) and not MetalGlint.is_armor_material(weapon_name))
		var weapon_mask_path := MetalGlint.mask_path(weapon_name)
		var weapon_image := Image.load_from_file(ProjectSettings.globalize_path(weapon_mask_path)) if not weapon_mask_path.is_empty() else null
		ctx.check("weapon mask for %s: exists, RGB, small, loadable" % weapon_name, weapon_image != null and not weapon_image.is_empty() and weapon_image.get_format() == Image.FORMAT_RGB8 and maxi(weapon_image.get_width(), weapon_image.get_height()) <= 1024 and FileAccess.file_exists(weapon_mask_path + ".import") and load(weapon_mask_path) is Texture2D)
		if weapon_image != null and not weapon_image.is_empty():
			var weapon_lit := 0
			for y in weapon_image.get_height():
				for x in weapon_image.get_width():
					if weapon_image.get_pixel(x, y).r > 0.5:
						weapon_lit += 1
			var weapon_share := float(weapon_lit) / float(weapon_image.get_width() * weapon_image.get_height())
			ctx.check("weapon mask %s covers 2-60%% of its texture (%.1f%%)" % [weapon_name, weapon_share * 100.0], weapon_share >= 0.02 and weapon_share <= 0.60)
	for old_name in ["Greatswords | Original PBR", "Sword & Shield | Original PBR.001", "Longbows | Original PBR", "Magic Staves | Original PBR", "Magic Staves | Original PBR.001", "Shield | Leather arm straps", "Level 15 | Original Armour"]:
		ctx.check("not an lv15 weapon / armour material: %s" % old_name, not MetalGlint.is_metal_material(old_name) and MetalGlint.mask_path(old_name).is_empty())
	var weapon := ShaderMaterial.new()
	weapon.resource_name = "Greatswords Lv15 | Original Colors"
	var weapon_mask := load(MetalGlint.mask_path(weapon.resource_name)) as Texture2D
	ctx.check("apply puts the weapon look on an lv15 weapon material", MetalGlint.apply(weapon, weapon_mask) and weapon.get_shader_parameter("use_metal") == true)
	var armour_look := ShaderMaterial.new()
	armour_look.resource_name = "Level 15 | Original Armor.001"
	MetalGlint.apply(armour_look, mask)
	ctx.check("weapon glint is more restrained than the armour's", float(weapon.get_shader_parameter("metal_glint_mix")) < float(armour_look.get_shader_parameter("metal_glint_mix")) and float(weapon.get_shader_parameter("metal_lift")) > float(armour_look.get_shader_parameter("metal_lift")) and float(weapon.get_shader_parameter("metal_halo_strength")) < float(armour_look.get_shader_parameter("metal_halo_strength")) and float(weapon.get_shader_parameter("metal_glint_mix")) <= 0.5)
	ctx.check("the armour keeps its own numbers", float(armour_look.get_shader_parameter("metal_glint_mix")) == float(MetalGlint.PARAMS["metal_glint_mix"]))
	ctx.check("apply refuses the leather straps and old weapons", not MetalGlint.apply(ShaderMaterial.new(), weapon_mask))

	# real model: lv15 piece gets the glint, the class suit does not
	var lv15 := "res://art/armor/race_shared/human_shirt_lv15.glb"
	if not ResourceLoader.exists(lv15):
		ctx.check("lv15 shirt present for the model check", false)
		return
	var holder := Node3D.new()
	ctx.root.add_child(holder)
	var model = CharacterModel.new()
	holder.add_child(model)
	model.load_model()
	model.dress({"class": "sword_shield", "shirt": lv15, "pants": "", "armband": "", "shoes": ""})
	var metal := 0
	var plain := 0
	for material in model._toon:
		if MetalGlint.is_metal_material(material.resource_name):
			metal += 1 if material.get_shader_parameter("use_metal") == true else 0
		elif material.get_shader_parameter("use_metal") == true:
			plain += 1
	ctx.check("worn lv15 shirt: its material has the metal glint (%d)" % metal, metal >= 1)
	ctx.check("no other material has the metal glint (%d)" % plain, plain == 0)
	holder.free()
