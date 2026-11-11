extends RefCounted
## Character lighting (Boss chose "B", 2026-10-08): the characters get their own soft key light and a rim
## light from behind that touch only render LAYER (the stage keeps its mood), gear is made less shiny so
## armor stops showing white hot spots, and the scene's tone mapping rolls off bright whites so white
## hair and light plates keep their shading. Comparison pictures: tools/shots/lighting_compare.gd.

const LAYER := 2  ## the render layer (1-based, as in the editor) that character meshes join
const MAX_SPECULAR := 0.25
const MIN_ROUGHNESS := 0.55
const AMBIENT_SCALE := 0.85  ## the key light replaces some of the flat ambient
const TONEMAP_WHITE := 3.0


## Adds the key and rim lights under `parent` and tunes `environment` for them.
static func light_scene(parent: Node, environment: Environment, key_energy: float, rim_energy: float) -> void:
	environment.ambient_light_energy *= AMBIENT_SCALE
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = TONEMAP_WHITE
	var key := DirectionalLight3D.new()  # soft light from the camera side: shapes faces and armor
	key.name = "CharacterKeyLight"
	key.rotation_degrees = Vector3(-38.0, 20.0, 0.0)
	key.light_color = Color(1.0, 0.92, 0.82)
	key.light_energy = key_energy
	key.light_cull_mask = 1 << (LAYER - 1)
	key.light_specular = 0.2
	parent.add_child(key)
	var rim := DirectionalLight3D.new()  # from behind and above: a bright edge that lifts them off the ground
	rim.name = "CharacterRimLight"
	rim.rotation_degrees = Vector3(-30.0, 180.0, 0.0)
	rim.light_color = Color(0.85, 0.92, 1.0)
	rim.light_energy = rim_energy
	rim.light_cull_mask = 1 << (LAYER - 1)
	rim.light_specular = 0.6
	parent.add_child(rim)


## Puts every mesh under `root` on the character layer and gives it less shiny copies of its materials.
## Safe to call again after new pieces are added: meshes already done are skipped.
static func prepare(root: Node) -> void:
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		if mesh.has_meta("character_lit"):
			continue
		mesh.set_meta("character_lit", true)
		mesh.layers |= 1 << (LAYER - 1)
		if DisplayServer.get_name() == "headless":
			continue  # (the headless test renderer cannot take copied materials: it only logs errors)
		for surface in mesh.get_surface_override_material_count():
			var material = mesh.get_active_material(surface)
			if material is BaseMaterial3D and material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
				var softer: BaseMaterial3D = material.duplicate()
				softer.metallic_specular = minf(softer.metallic_specular, MAX_SPECULAR)
				softer.roughness = maxf(softer.roughness, MIN_ROUGHNESS)
				mesh.set_surface_override_material(surface, softer)
