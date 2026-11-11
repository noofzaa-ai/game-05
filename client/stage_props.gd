extends RefCounted
## Builds the scenery of a stage from the map's `props` list: trees, plum trees, rocks, bushes and
## drifting petals on the ground. They are only to look at (no collision: anything the player must
## not walk through is a solid in the map). Low-poly shapes with flat colors until real models exist.
## EXTENDING: a new kind of prop is a new entry in KINDS and a builder function here.
## "art_scene" is special: a map's `art_scene` (a ready-made .glb, e.g. art/maps/goblin_forest/) arrives as one
## prop entry {"kind": "art_scene", "path", "mood"} (logic/map_loader.gd); it is instanced whole, with the
## vertex-colour fix, lights on its light_* empties and the map's lighting mood.

const InkStyle := preload("res://client/ink_style.gd")

const KINDS: Array[String] = ["pine", "plum", "rock", "bush", "petals", "pond", "art_scene"]

const BARK := Color(0.30, 0.22, 0.18)
const PINE_GREEN := Color(0.20, 0.34, 0.26)
const PLUM_PINK := Color(0.93, 0.55, 0.65)
const PLUM_DEEP := Color(0.80, 0.30, 0.42)
const STONE := Color(0.40, 0.41, 0.40)
const BUSH_GREEN := Color(0.28, 0.42, 0.28)
const PETAL := Color(0.90, 0.40, 0.52)
const WATER := Color(0.55, 0.78, 0.82)


## Adds every prop to `parent`. A map naming a kind that does not exist simply gets nothing for it.
static func build(parent: Node3D, props: Array, outline: bool = false) -> void:
	_outline = InkStyle.outline_material(0.035) if outline else null
	var rng := RandomNumberGenerator.new()
	rng.seed = 7  # the scatter looks the same every time
	for prop in props:
		if not KINDS.has(prop["kind"]):
			continue
		if prop["kind"] == "art_scene":
			add_art_scene(parent, str(prop.get("path", "")), str(prop.get("mood", "")))
			continue
		for index in int(prop["count"]):
			var spot: Vector3 = prop["position"]
			if float(prop["radius"]) > 0.0:
				var angle := rng.randf() * TAU
				var distance := sqrt(rng.randf()) * float(prop["radius"])
				spot += Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
			var node: Node3D = _builder(prop["kind"]).call(rng)
			node.position = spot
			node.scale = Vector3.ONE * float(prop["scale"]) * rng.randf_range(0.9, 1.1)
			node.rotation_degrees.y = float(prop["yaw"]) + rng.randf_range(-20.0, 20.0)
			parent.add_child(node)


static func _builder(kind: String) -> Callable:
	match kind:
		"pine":
			return _pine
		"plum":
			return _plum
		"rock":
			return _rock
		"bush":
			return _bush
		"pond":
			return _pond
	return _petals


static var _outline: Material  ## the ink outline put on every piece (null = none)


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.next_pass = _outline
	return material


static func _piece(mesh: PrimitiveMesh, color: Color, position: Vector3, scale: Vector3 = Vector3.ONE, rotation_degrees: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	mesh.material = _material(color)
	instance.mesh = mesh
	instance.position = position
	instance.scale = scale
	instance.rotation_degrees = rotation_degrees
	return instance


static func _cylinder(top: float, bottom: float, height: float, sides: int = 6) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	return mesh


static func _blob(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 7
	mesh.rings = 4
	return mesh


static func _pine(rng: RandomNumberGenerator) -> Node3D:
	var node := Node3D.new()
	node.add_child(_piece(_cylinder(0.12, 0.18, 1.2), BARK, Vector3(0, 0.6, 0)))
	for layer in 3:
		var size := 1.1 - 0.28 * float(layer)
		node.add_child(_piece(_cylinder(0.0, size, 1.1), PINE_GREEN.lerp(Color(0.3, 0.5, 0.35), 0.15 * float(layer)), Vector3(0, 1.5 + 0.8 * float(layer), 0)))
	return node


static func _plum(rng: RandomNumberGenerator) -> Node3D:
	var node := Node3D.new()
	node.add_child(_piece(_cylinder(0.10, 0.20, 1.6), BARK, Vector3(0, 0.8, 0), Vector3.ONE, Vector3(0, 0, rng.randf_range(-8.0, 8.0))))
	node.add_child(_piece(_cylinder(0.05, 0.10, 1.2), BARK, Vector3(0.35, 1.7, 0), Vector3.ONE, Vector3(0, 0, -42)))
	node.add_child(_piece(_cylinder(0.05, 0.10, 1.0), BARK, Vector3(-0.3, 1.8, 0.1), Vector3.ONE, Vector3(0, 0, 38)))
	for blossom in [Vector3(0, 2.5, 0), Vector3(0.9, 2.3, 0.2), Vector3(-0.85, 2.4, -0.1), Vector3(0.2, 2.9, 0.5), Vector3(-0.2, 2.2, -0.7)]:
		node.add_child(_piece(_blob(0.85), PLUM_PINK.lerp(PLUM_DEEP, rng.randf() * 0.5), blossom, Vector3(1.0, 0.7, 1.0)))
	return node


static func _rock(rng: RandomNumberGenerator) -> Node3D:
	var node := Node3D.new()
	for part in 3:
		var size := rng.randf_range(0.55, 0.9)
		var tone := rng.randf_range(0.85, 1.1)
		node.add_child(_piece(_blob(size), STONE * tone, Vector3(rng.randf_range(-0.5, 0.5), size * 0.5, rng.randf_range(-0.5, 0.5)), Vector3(1.0, 0.8, 1.0)))
	return node


static func _bush(rng: RandomNumberGenerator) -> Node3D:
	var node := Node3D.new()
	for part in 2:
		node.add_child(_piece(_blob(rng.randf_range(0.35, 0.5)), BUSH_GREEN.lerp(Color(0.4, 0.55, 0.3), rng.randf() * 0.5), Vector3(rng.randf_range(-0.3, 0.3), 0.3, rng.randf_range(-0.3, 0.3)), Vector3(1.0, 0.75, 1.0)))
	return node


## One tiny flat petal on the ground.
static func _petals(rng: RandomNumberGenerator) -> Node3D:
	var node := Node3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.18, 0.1)
	var instance := _piece(quad, PETAL.lerp(PLUM_DEEP, rng.randf() * 0.6), Vector3(0, 0.03, 0), Vector3.ONE, Vector3(-90.0, rng.randf() * 360.0, 0.0))
	node.add_child(instance)
	return node


## A shallow pond: a flat disc of water just above the ground.
static func _pond(rng: RandomNumberGenerator) -> Node3D:
	var node := Node3D.new()
	var disc := _cylinder(1.0, 1.0, 0.04, 20)
	node.add_child(_piece(disc, WATER, Vector3(0, 0.02, 0), Vector3(1.0, 1.0, 0.7)))
	return node


## Light energies and colours for the art scene's light_* empties (OmniLight3D, no shadows: web-cheap).
const ART_LIGHTS := {
	"light_fire": {"color": Color(1.0, 0.58, 0.28), "energy": 2.2, "range": 9.0, "flicker": 0.35},
	"light_lantern": {"color": Color(1.0, 0.78, 0.45), "energy": 1.1, "range": 5.5, "flicker": 0.08},
	"light_glow": {"color": Color(0.5, 0.85, 1.0), "energy": 0.6, "range": 3.0, "flicker": 0.0},
}
## Lighting moods an art scene may ask for (map field `art_mood`), applied over the stage's atmosphere:
## the sun becomes a moon (or a low warm sun), the ambient and the fog turn to the mood's colours.
const ART_MOODS := {
	"night": {"sun_color": Color(0.70, 0.78, 1.0), "sun_energy": 1.15, "ambient": Color(0.52, 0.58, 0.80), "ambient_energy": 1.45,
		"fog": Color(0.16, 0.20, 0.28), "fog_density": 0.006, "background": Color(0.06, 0.07, 0.11), "saturation": 1.05},
	"camp": {"sun_color": Color(1.0, 0.82, 0.62), "sun_energy": 0.9, "ambient": Color(0.62, 0.64, 0.60), "ambient_energy": 1.05,
		"fog": Color(0.30, 0.30, 0.24), "fog_density": 0.006, "background": Color(0.16, 0.17, 0.14), "saturation": 1.08},
}


## Instances an art scene (a .glb) under `parent`. Returns the instance (null when the file is missing:
## the stage then simply has no art, the map's solids and props still work).
static func add_art_scene(parent: Node3D, path: String, mood: String = "") -> Node3D:
	if path.is_empty() or not ResourceLoader.exists(path):
		push_warning("art scene not found: %s" % path)
		return null
	var scene := (load(path) as PackedScene).instantiate() as Node3D
	scene.name = "ArtScene"
	use_vertex_colors(scene)
	parent.add_child(scene)
	for marker in scene.find_children("light_*", "", true, false):
		var key := str(marker.name).rstrip("0123456789").trim_suffix("_")
		if not ART_LIGHTS.has(key) or not marker is Node3D:
			continue
		var look: Dictionary = ART_LIGHTS[key]
		var light := OmniLight3D.new()
		light.light_color = look["color"]
		light.light_energy = look["energy"]
		light.omni_range = look["range"]
		light.omni_attenuation = 1.4
		light.shadow_enabled = false
		marker.add_child(light)
		if float(look["flicker"]) > 0.0 and light.is_inside_tree():
			var tween := light.create_tween().set_loops()
			var base := float(look["energy"])
			var amount := float(look["flicker"])
			tween.tween_property(light, "light_energy", base * (1.0 + amount), 0.13).set_trans(Tween.TRANS_SINE)
			tween.tween_property(light, "light_energy", base * (1.0 - amount * 0.6), 0.21).set_trans(Tween.TRANS_SINE)
			tween.tween_property(light, "light_energy", base * (1.0 + amount * 0.4), 0.17).set_trans(Tween.TRANS_SINE)
			tween.tween_property(light, "light_energy", base, 0.19).set_trans(Tween.TRANS_SINE)
	if ART_MOODS.has(mood):
		apply_mood(parent, ART_MOODS[mood])
	return scene


## Godot's glTF import leaves vertex_color_use_as_albedo off, so vertex-painted art renders white.
## (The materials are the imported resources, shared by every instance: setting the flags is idempotent.)
static func use_vertex_colors(scene: Node) -> void:
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var material := mesh.surface_get_material(i) as StandardMaterial3D
			if material != null:
				material.vertex_color_use_as_albedo = true
				material.vertex_color_is_srgb = false  # (glTF COLOR_0 is linear already; true would darken it twice)
				if material.resource_name.begins_with("gf_"):
					# Our generated stage art is closed solids on one open floor sheet: drawn one-sided, the
					# sun (shadow_reverse_cull_face, atmosphere.gd) casts from back faces only, so the floor
					# never shadows itself (Boss 2026-10-15: fine dark stripes on the floor). The bought kit
					# (orc_kit: single-sheet banners/hides) stays two-sided.
					material.cull_mode = BaseMaterial3D.CULL_BACK
				if _is_emissive(material):
					material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # flames/glows show their painted colours


## Materials named *_fire / *_glow (gf_fire, gf_glow, chest_glow) are light sources: shown unshaded, so the
## painted gradient (flame base -> tip, gold seam) reads instead of one flat emission colour.
static func _is_emissive(material: Material) -> bool:
	var name := material.resource_name
	return name.ends_with("_fire") or name.ends_with("_glow")


## Re-tints the stage's sun and environment (made by client/atmosphere.gd, a sibling under the same parent).
static func apply_mood(parent: Node, look: Dictionary) -> void:
	for node in parent.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (node as WorldEnvironment).environment
		if env == null:
			continue
		env.background_mode = Environment.BG_COLOR
		env.background_color = look["background"]
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = look["ambient"]
		env.ambient_light_energy = look["ambient_energy"]
		env.fog_light_color = look["fog"]
		env.fog_density = look["fog_density"]
		env.adjustment_saturation = look["saturation"]
	for node in parent.find_children("*", "DirectionalLight3D", true, false):
		var sun := node as DirectionalLight3D
		if str(sun.name).begins_with("Character"):
			continue  # (the characters' own key/rim lights keep them readable in any mood)
		sun.light_color = look["sun_color"]
		sun.light_energy = look["sun_energy"]
