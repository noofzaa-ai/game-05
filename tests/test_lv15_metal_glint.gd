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
	ctx.check("a dimmer second band between halo and core", halo > 0.3 and halo < 0.7)
	ctx.check("glint is monotonic in the half-vector dot", MetalGlint.glint(0.80, 0.5) <= MetalGlint.glint(0.90, 0.5) and MetalGlint.glint(0.90, 0.5) <= MetalGlint.glint(0.97, 0.5))
	var edge := float(MetalGlint.PARAMS["metal_core"])
	ctx.check("the core is stepped (hard edge within 0.03)", MetalGlint.glint(edge + 0.03, 0.5) >= 0.99 and MetalGlint.glint(edge + 0.03, 0.5) - MetalGlint.glint(edge - 0.015, 0.5) > 0.4)
	ctx.check("each cell sparkles at its own angle", MetalGlint.glint(edge - 0.01, 0.95) > MetalGlint.glint(edge - 0.01, 0.05))
	ctx.check("dark ink line sits just below the halo edge only", MetalGlint.dark_line(float(MetalGlint.PARAMS["metal_halo"]) - 0.01, 0.5) > 0.9 and MetalGlint.dark_line(0.2, 0.5) == 0.0 and MetalGlint.dark_line(1.0, 0.5) == 0.0)
	ctx.check("studs always show a dot, and a bright one over a wider angle than plates", MetalGlint.stud(0.0, 0.5) >= float(MetalGlint.PARAMS["metal_stud_base"]) and MetalGlint.stud(0.80, 0.5) == 1.0 and MetalGlint.glint(0.80, 0.5) < 1.0)
	ctx.check("rim: thin, only at grazing angles on the lit side", MetalGlint.rim(0.05, 0.8) > 0.9 and MetalGlint.rim(0.6, 0.8) == 0.0 and MetalGlint.rim(0.05, -0.8) == 0.0)

	# shader and switch
	var shader_text := FileAccess.get_file_as_string(SHADER)
	var missing: Array = []
	for key in MetalGlint.PARAMS:
		if not shader_text.contains("uniform float %s" % key):
			missing.append(key)
	ctx.check("the toon shader declares every metal uniform %s" % [missing], missing.is_empty() and shader_text.contains("uniform bool use_metal") and shader_text.contains("uniform sampler2D metal_mask"))
	ctx.check("graphics switch metal_glint exists, on by default", Options._values.has(MetalGlint.OPTION) and Options._valid(MetalGlint.OPTION, false))

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
