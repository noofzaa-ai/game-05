extends Node3D
## Warm, hazy forest mood: low sun, depth fog, bloom, fake light shafts and placeholder trees.
## Only features that work in the Compatibility renderer (web/mobile) are used.
## Lighting is tuned through the constants below; the characters' own lights are in character_light.gd.

const CharacterLight := preload("res://client/character_light.gd")

const SUN_COLOR := Color(1.0, 0.82, 0.55)
const SUN_ENERGY := 0.9
const SUN_ROTATION_DEG := Vector3(-32.0, -55.0, 0.0)
const FOG_COLOR := Color(0.85, 0.78, 0.55)
const FOG_DENSITY := 0.012
const SHAFT_COLOR := Color(1.0, 0.85, 0.5, 0.09)
const SHAFT_COUNT := 7
const TREE_COUNT := 26
const FAR_X := 40.0

## "golden": the warm low-sun valley. "ink": a soft, misty, painterly garden (cool light, grey-green fog,
## muted colors, no god rays), set by the map's `atmosphere`.
var style := "golden"


func _ready() -> void:
	_build_environment()
	_build_sun()
	_build_ground()
	if style == "golden":  # the ink garden's scenery comes from the map's props
		_build_trees()
		_build_light_shafts()


func _build_environment() -> void:
	var ink := style == "ink"
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.62, 0.70, 0.74) if ink else Color(0.45, 0.6, 0.72)
	sky_material.sky_horizon_color = Color(0.82, 0.85, 0.82) if ink else Color(0.95, 0.85, 0.6)
	sky_material.ground_horizon_color = Color(0.82, 0.85, 0.82) if ink else Color(0.95, 0.85, 0.6)
	sky_material.ground_bottom_color = Color(0.35, 0.38, 0.36) if ink else Color(0.3, 0.3, 0.2)
	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.76, 0.78) if ink else Color(0.55, 0.55, 0.5)
	env.ambient_light_energy = 0.5 if ink else 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.79, 0.77) if ink else FOG_COLOR
	env.fog_density = 0.0025 if ink else FOG_DENSITY
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0 if ink else 1.1  # muted, like ink and wash
	env.adjustment_contrast = 1.18 if ink else 1.05

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	CharacterLight.light_scene(self, env, 0.7, 1.1)


func _build_sun() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = SUN_ROTATION_DEG
	sun.light_color = Color(0.92, 0.95, 1.0) if style == "ink" else SUN_COLOR
	sun.light_energy = 0.8 if style == "ink" else SUN_ENERGY
	sun.shadow_blur = 2.5 if style == "ink" else 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	# (Boss 2026-10-15: the floor showed fine dark stripes that stopped at a hard line following the camera =
	# the floor shadowing itself (shadow acne; the line is where the next shadow cascade starts). Bias alone
	# did not cure it. Back faces cast instead: the floor is one open surface (no back side), so it never
	# shadows itself; closed props, the kit's two-sided pieces and the characters still cast.)
	sun.shadow_reverse_cull_face = true
	sun.shadow_bias = 0.1
	sun.shadow_normal_bias = 1.5
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.7
	add_child(sun)


func _build_ground() -> void:
	# Big grass plane just under the lane floor so the lane reads as a dirt path.
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(160.0, 80.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.28, 0.32, 0.28) if style == "ink" else Color(0.22, 0.34, 0.14)
	plane.material = material
	mesh.mesh = plane
	mesh.position = Vector3(0.0, -0.25, 0.0 if style == "ink" else -20.0)
	if style == "ink":
		plane.size = Vector2(240.0, 240.0)
	add_child(mesh)


func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7  # fixed seed so the test scene looks the same every run
	var trunk_material := StandardMaterial3D.new()
	trunk_material.albedo_color = Color(0.25, 0.17, 0.1)
	var leaf_material := StandardMaterial3D.new()
	leaf_material.albedo_color = Color(0.2, 0.36, 0.14)

	for i in TREE_COUNT:
		var tree := Node3D.new()
		tree.position = Vector3(rng.randf_range(-FAR_X, FAR_X), -0.25, rng.randf_range(-30.0, -5.0))
		var height := rng.randf_range(7.0, 12.0)

		var trunk := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.25
		cylinder.bottom_radius = 0.4
		cylinder.height = height
		cylinder.radial_segments = 6
		cylinder.material = trunk_material
		trunk.mesh = cylinder
		trunk.position.y = height / 2.0
		tree.add_child(trunk)

		var leaves := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = rng.randf_range(2.0, 3.2)
		cone.height = height * 0.7
		cone.radial_segments = 7
		cone.material = leaf_material
		leaves.mesh = cone
		leaves.position.y = height * 0.8
		tree.add_child(leaves)

		add_child(tree)


func _build_light_shafts() -> void:
	# Soft ellipse texture stretched into tall, tilted, additive quads = cheap god rays.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = SHAFT_COLOR
	material.albedo_texture = texture

	for i in SHAFT_COUNT:
		var shaft := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(3.5, 16.0)
		quad.material = material
		shaft.mesh = quad
		var t := float(i) / float(SHAFT_COUNT - 1)
		shaft.position = Vector3(lerpf(-16.0, 16.0, t), 6.0, -3.0 - 2.0 * float(i % 3))
		shaft.rotation_degrees = Vector3(0.0, 0.0, 28.0)
		add_child(shaft)
