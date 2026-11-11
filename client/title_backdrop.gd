extends Node3D
## The title screen's animated 3D backdrop (Boss 2026-10-13: "an animated picture that fits our theme,
## fantasy survival"). Night at the edge of a forest: a lone campfire with flickering light and rising
## embers, the player's chibi standing by it with its back to us, a big soft moon behind a ruined
## tower and a faintly glowing warp gate on a far hill, thin clouds drifting across the moon, stars,
## fireflies, rolling mist and a slow camera drift. The RIGHT ~40% of the frame is kept calm and dark
## for the logo and the menu (the title screen's UI sits on top of this node).
## Use: add TitleBackdrop.new() to the scene tree (as a Node3D in the 3D world, behind a CanvasLayer UI).
## It builds itself in _ready() and brings its own Camera3D (current) and WorldEnvironment.
## Cheap for web/phones (Compatibility renderer): one fire light + a weak moon light, no shadows,
## props drawn as MultiMeshes, CPU particles. set_quality(true) trims particles, clouds and mist.
## Scenery is built from the model team's verdant_reach props (art/maps/verdant_reach/props) and
## primitive shapes; nothing comes from outside the project.

const CharacterModel := preload("res://client/characters/studio05_character_model.gd")

const PROPS := "res://art/maps/verdant_reach/props/%s.glb"
const DESIGN_ASPECT := 16.0 / 9.0  ## the sky things are placed in screen terms for this shape
const FOV := 50.0
const CAMERA_POS := Vector3(0.0, 1.4, 9.0)
const CAMERA_LOOK := Vector3(-0.6, 3.6, -20.0)
const DRIFT := Vector3(0.7, 0.18, 0.35)  ## how far the camera sways (m)
const FIRE_POS := Vector3(-3.0, 0.0, 2.6)
const FIRE_COLOR := Color(1.0, 0.52, 0.2)
const FIRE_ENERGY := 2.6
const CHARACTER_POS := Vector3(-1.95, 0.0, 2.15)
const MOON_SCREEN := Vector2(-0.22, 0.44)  ## normalized device coords (x right, y up, -1..1)
const MOON_DEPTH := 140.0
const MOON_DISC := 24.0  ## diameter in m at MOON_DEPTH
const SKY_DEPTH := 160.0
const HORIZON := Color(0.11, 0.14, 0.24)
const NIGHT_INK := Color(0.025, 0.035, 0.07)  ## the darkest silhouettes

var low_quality := false
var menu_shade := true  ## a soft darkening over the right of the frame, under the menu
var show_character := false  ## Boss 2026-10-13: off until the real player model arrives (the bare chibi looked odd)

var _camera: Camera3D
var _environment: Environment
var _fire_light: OmniLight3D
var _fire_pool: MeshInstance3D
var _character  ## CharacterModel (null if the model is missing)
var _clouds: Array[Node3D] = []
var _cloud_speed: Array[float] = []
var _scalable: Array[Dictionary] = []  ## particles: {"node", "high", "low"}
var _extras: Array[Node3D] = []  ## hidden on low quality
var _gate_glow: MeshInstance3D
var _time := 0.0
var _soft_dot: GradientTexture2D
var _noise: NoiseTexture2D


func _ready() -> void:
	_soft_dot = _radial_texture()
	_noise = _noise_texture()
	_build_environment()
	_build_camera()
	_build_sky()
	_build_moon()
	_build_clouds()
	_build_far_hill()
	_build_ground()
	_build_forest()
	_build_campfire()
	if show_character:
		_build_character()
	_build_fireflies()
	_build_mist()
	if menu_shade:
		_build_menu_shade()
	set_quality(low_quality)


## Low quality (phones that struggle): fewer embers/fireflies/motes, one cloud and one mist layer, no glow.
func set_quality(low: bool) -> void:
	low_quality = low
	for entry in _scalable:
		var particles: CPUParticles3D = entry["node"]
		particles.amount = entry["low"] if low else entry["high"]
	for node in _extras:
		node.visible = not low
	if _environment != null:
		_environment.glow_enabled = not low


func camera() -> Camera3D:
	return _camera


func _process(delta: float) -> void:
	_time += delta
	var t := _time
	var flicker := 0.35 * sin(t * 11.0) + 0.25 * sin(t * 17.3 + 1.3) + 0.15 * sin(t * 29.0)
	_fire_light.light_energy = FIRE_ENERGY + flicker
	_fire_pool.scale = Vector3.ONE * (1.0 + 0.05 * flicker)
	var sway := Vector3(sin(t * 0.11) * DRIFT.x, sin(t * 0.083 + 0.7) * DRIFT.y, sin(t * 0.067 + 2.0) * DRIFT.z)
	_camera.look_at_from_position(CAMERA_POS + sway, CAMERA_LOOK + Vector3(sway.x * 0.3, sway.y * 2.0, 0.0))
	for i in _clouds.size():
		var cloud := _clouds[i]
		cloud.position += _camera_right() * _cloud_speed[i] * delta
		if cloud.position.x > 120.0:  # wraps around to the left, out of sight
			cloud.position -= _camera_right() * 230.0
	if _gate_glow != null:
		_gate_glow.transparency = 0.25 + 0.2 * sin(t * 1.3)
	if _character != null:
		_character.apply_pose(delta)


func _camera_right() -> Vector3:
	return Vector3(1.0, 0.0, 0.0)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = HORIZON
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.24, 0.4)
	env.ambient_light_energy = 0.38
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 3.0
	env.fog_enabled = true
	env.fog_light_color = HORIZON
	env.fog_density = 0.012
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.95
	_environment = env
	var holder := WorldEnvironment.new()
	holder.environment = env
	add_child(holder)

	var moon := DirectionalLight3D.new()  # weak cool moonlight from behind-left: rims the trees
	moon.rotation_degrees = Vector3(-28.0, 160.0, 0.0)
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.light_energy = 0.45
	moon.shadow_enabled = false
	add_child(moon)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.fov = FOV
	_camera.far = 400.0
	_camera.current = true
	add_child(_camera)
	_camera.look_at_from_position(CAMERA_POS, CAMERA_LOOK)


## A point `depth` m in front of the resting camera at normalized screen coords (x right, y up).
func _screen_point(ndc: Vector2, depth: float) -> Vector3:
	var basis := Basis.looking_at(CAMERA_LOOK - CAMERA_POS)
	var half_v := tan(deg_to_rad(FOV) * 0.5)
	return CAMERA_POS - basis.z * depth + basis.x * (ndc.x * half_v * DESIGN_ASPECT * depth) + basis.y * (ndc.y * half_v * depth)


## A quad facing the resting camera.
func _facing_quad(size: Vector2, material: Material, at: Vector3) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	var node := MeshInstance3D.new()
	node.mesh = quad
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.transform = Transform3D(Basis.looking_at(CAMERA_LOOK - CAMERA_POS), at)
	add_child(node)
	return node


# --- sky ---------------------------------------------------------------------------------------

const SKY_SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, shadows_disabled;
uniform vec3 top_color : source_color;
uniform vec3 horizon_color : source_color;
uniform vec2 moon_uv;
uniform float aspect;
uniform float horizon_v;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	float h = clamp((horizon_v - uv.y) / horizon_v, 0.0, 1.0);  // 0 at the horizon, 1 at the top
	vec3 col = mix(horizon_color, top_color, pow(h, 0.7));
	col *= mix(1.0, 0.55, smoothstep(0.45, 1.0, uv.x));  // calmer, darker right side for the menu
	vec2 d = (uv - moon_uv) * vec2(aspect, 1.0);
	float r = length(d);
	col += vec3(0.30, 0.38, 0.62) * exp(-r * 7.0) * 0.55 + vec3(0.5, 0.58, 0.8) * exp(-r * 22.0) * 0.35;
	vec2 grid = uv * vec2(aspect, 1.0) * 140.0;
	vec2 cell = floor(grid);
	float n = hash(cell);
	if (n > 0.982) {
		vec2 spot = vec2(hash(cell + 3.1), hash(cell + 7.7)) * 0.6 + 0.2;
		float s = smoothstep(0.16, 0.0, length(fract(grid) - spot));
		float twinkle = 0.55 + 0.45 * sin(TIME * (1.0 + n * 3.0) + n * 80.0);
		float keep = smoothstep(0.05, 0.35, h) * smoothstep(0.08, 0.25, r);
		col += vec3(0.75, 0.82, 1.0) * s * twinkle * keep * (0.4 + 0.6 * hash(cell + 1.7));
	}
	ALBEDO = col;
}
"""


func _build_sky() -> void:
	var material := ShaderMaterial.new()
	material.shader = _shader(SKY_SHADER)
	var height := 2.0 * SKY_DEPTH * tan(deg_to_rad(FOV) * 0.5) * 1.35
	var size := Vector2(height * 2.6, height)
	var center := _screen_point(Vector2(0.0, 0.2), SKY_DEPTH)
	material.set_shader_parameter("top_color", Color(0.02, 0.03, 0.08))
	material.set_shader_parameter("horizon_color", HORIZON * 1.25)
	material.set_shader_parameter("aspect", size.x / size.y)
	# Where the moon and the horizon fall on the quad (its UV runs top-left to bottom-right).
	var moon_world := _screen_point(MOON_SCREEN, SKY_DEPTH)
	var basis := Basis.looking_at(CAMERA_LOOK - CAMERA_POS)
	var offset := moon_world - center
	material.set_shader_parameter("moon_uv", Vector2(0.5 + offset.dot(basis.x) / size.x, 0.5 - offset.dot(basis.y) / size.y))
	var horizon_world := Vector3(center.x, CAMERA_POS.y, center.z)
	material.set_shader_parameter("horizon_v", clampf(0.5 - (horizon_world - center).dot(basis.y) / size.y, 0.3, 0.95))
	_facing_quad(size, material, center)


const MOON_SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, shadows_disabled, blend_add, depth_draw_never;
uniform float disc = 0.28;  // disc radius in UV

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 d = UV - 0.5;
	float r = length(d);
	float body = smoothstep(disc, disc - 0.006, r);
	float maria = noise(d * 9.0 + 3.0) * 0.6 + noise(d * 23.0) * 0.4;
	vec3 surface = mix(vec3(1.25, 1.28, 1.35), vec3(0.85, 0.9, 1.05), smoothstep(0.45, 0.75, maria));
	surface *= 1.0 - 0.25 * smoothstep(disc * 0.4, disc, r);  // soft limb darkening
	float pulse = 1.0 + 0.04 * sin(TIME * 0.5);
	float e = max(r - disc, 0.0);
	float glow = (exp(-e * 14.0) * 0.45 + exp(-e * 40.0) * 0.4) * (1.0 - body) * pulse;
	ALBEDO = surface * body + vec3(0.55, 0.65, 1.0) * glow;
}
"""


func _build_moon() -> void:
	var material := ShaderMaterial.new()
	material.shader = _shader(MOON_SHADER)
	var quad_size := MOON_DISC / (2.0 * 0.28)
	material.set_shader_parameter("disc", 0.28)
	var moon := _facing_quad(Vector2.ONE * quad_size, material, _screen_point(MOON_SCREEN, MOON_DEPTH))
	moon.sorting_offset = -10.0


const CLOUD_SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, shadows_disabled, depth_draw_never;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec3 tint : source_color;
uniform float density = 0.6;
uniform float seed = 0.0;

void fragment() {
	vec2 uv = UV;
	float n = texture(noise_tex, vec2(uv.x * 0.9 + seed + TIME * 0.004, uv.y * 0.35 + seed * 0.37)).r;
	float n2 = texture(noise_tex, vec2(uv.x * 2.3 - seed - TIME * 0.006, uv.y * 0.9)).r;
	float shape = smoothstep(0.0, 0.35, uv.x) * smoothstep(1.0, 0.65, uv.x) * smoothstep(0.0, 0.45, uv.y) * smoothstep(1.0, 0.5, uv.y);
	float a = smoothstep(0.42, 0.78, n * 0.7 + n2 * 0.3) * shape * density;
	ALBEDO = tint * (0.8 + 0.4 * n2);
	ALPHA = a;
}
"""


func _build_clouds() -> void:
	var shader := _shader(CLOUD_SHADER)
	# [screen x, screen y, width m, height m, speed m/s, brightness]
	var specs := [
		[-0.55, 0.50, 95.0, 13.0, 0.9, 1.4],  # crosses the moon: lit
		[0.05, 0.62, 120.0, 11.0, 0.6, 0.55],
		[-0.15, 0.30, 80.0, 8.0, 1.3, 0.8],
		[0.55, 0.78, 130.0, 14.0, 0.45, 0.35],  # high on the right, very faint
	]
	for i in specs.size():
		var spec: Array = specs[i]
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("noise_tex", _noise)
		material.set_shader_parameter("tint", Color(0.36, 0.42, 0.6) * float(spec[5]))
		material.set_shader_parameter("density", 0.75)
		material.set_shader_parameter("seed", float(i) * 0.31)
		var cloud := _facing_quad(Vector2(spec[2], spec[3]), material, _screen_point(Vector2(spec[0], spec[1]), 125.0 - float(i) * 3.0))
		_clouds.append(cloud)
		_cloud_speed.append(float(spec[4]))
		if i >= 2:
			_extras.append(cloud)


# --- distant hill: ruined tower and the warp gate --------------------------------------------------

func _flat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material


func _shape(mesh: Mesh, material: Material, at: Vector3, scale_by: Vector3 = Vector3.ONE, rotation_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position = at
	node.scale = scale_by
	node.rotation_degrees = rotation_deg
	add_child(node)
	return node


func _build_far_hill() -> void:
	var dark := _flat(NIGHT_INK)
	var hill_top := _screen_point(Vector2(-0.12, -0.02), 75.0)
	var base := Vector3(hill_top.x, 0.0, hill_top.z)
	var sphere := SphereMesh.new()
	sphere.radial_segments = 24
	sphere.rings = 10
	# The hill: a long rise with a steeper cliff on the left, like a ridge the tower guards.
	_shape(sphere, dark, base + Vector3(-4.0, -6.0, 0.0), Vector3(30.0, 15.0, 14.0))
	_shape(sphere, dark, base + Vector3(18.0, -4.0, 6.0), Vector3(34.0, 8.5, 12.0))
	_shape(sphere, dark, base + Vector3(-30.0, -3.0, 8.0), Vector3(24.0, 7.0, 10.0))
	var top := base + Vector3(-2.0, 8.4, 0.0)
	# The ruined tower: a tapering trunk, a broken crown with two jagged teeth, a fallen block.
	var trunk := CylinderMesh.new()
	trunk.top_radius = 1.5
	trunk.bottom_radius = 2.1
	trunk.height = 11.0
	trunk.radial_segments = 8
	_shape(trunk, dark, top + Vector3(0.0, 5.5, 0.0))
	var crown := CylinderMesh.new()
	crown.top_radius = 2.0
	crown.bottom_radius = 1.6
	crown.height = 1.2
	crown.radial_segments = 8
	_shape(crown, dark, top + Vector3(0.0, 11.4, 0.0))
	var box := BoxMesh.new()
	_shape(box, dark, top + Vector3(-1.1, 13.0, 0.0), Vector3(0.8, 2.4, 0.8), Vector3(0.0, 0.0, 6.0))
	_shape(box, dark, top + Vector3(1.2, 12.5, 0.3), Vector3(0.7, 1.4, 0.7), Vector3(0.0, 0.0, -10.0))
	_shape(box, dark, top + Vector3(3.2, 0.5, 0.0), Vector3(1.6, 1.0, 1.2), Vector3(0.0, 20.0, 25.0))
	var window := _flat(Color(1.6, 0.75, 0.3))  # one faint warm window: someone still holds out
	_shape(box, window, top + Vector3(0.0, 8.0, 1.7), Vector3(0.35, 0.6, 0.1))
	# The warp gate: a standing stone ring a little down the slope, with a slow cyan shimmer inside.
	var ring := TorusMesh.new()
	ring.inner_radius = 2.1
	ring.outer_radius = 2.6
	ring.rings = 20
	ring.ring_segments = 6
	var gate_at := base + Vector3(9.0, 6.6, 1.5)
	_shape(ring, dark, gate_at + Vector3(0.0, 2.6, 0.0), Vector3.ONE, Vector3(90.0, 0.0, 0.0))
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.albedo_texture = _soft_dot
	glow.albedo_color = Color(0.35, 1.0, 1.0)
	glow.disable_fog = true
	var quad := QuadMesh.new()
	quad.size = Vector2(5.4, 5.4)
	_gate_glow = _shape(quad, glow, gate_at + Vector3(0.0, 2.6, 0.3))
	_gate_glow.rotation = Basis.looking_at(CAMERA_LOOK - CAMERA_POS).get_euler()


# --- ground, forest and the near scenery ------------------------------------------------------------

func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(260.0, 260.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.07, 0.09, 0.08)
	material.roughness = 1.0
	var ground := _shape(plane, material, Vector3(0.0, 0.0, -60.0))
	ground.material_override = material
	# Low dark ridges between the camp and the far hill hide the ground's end and give depth layers.
	var sphere := SphereMesh.new()
	sphere.radial_segments = 20
	sphere.rings = 8
	var ridge := _flat(NIGHT_INK.lerp(HORIZON, 0.15))
	_shape(sphere, ridge, Vector3(-45.0, -2.0, -48.0), Vector3(40.0, 5.0, 10.0))
	_shape(sphere, ridge, Vector3(40.0, -2.5, -52.0), Vector3(50.0, 6.0, 10.0))


## Puts `rows` ([x, y, z, yaw, scale]) of a verdant_reach prop into one MultiMesh (one draw call).
## `material`: null = the prop's own vertex colors, darkened by `tint`; else drawn with it.
func _scatter(prop: String, rows: Array, material: Material = null, tint: Color = Color.WHITE) -> MultiMeshInstance3D:
	var path := PROPS % prop
	if rows.is_empty() or not ResourceLoader.exists(path):
		return null
	var scene: Node = load(path).instantiate()
	var meshes := scene.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		scene.free()
		return null
	var source: MeshInstance3D = meshes[0]
	var mesh: Mesh = source.mesh
	var local := source.transform
	if material == null:
		var own := mesh.surface_get_material(0) as StandardMaterial3D
		var copy: StandardMaterial3D = own.duplicate() if own != null else StandardMaterial3D.new()
		copy.vertex_color_use_as_albedo = true  # (the props are painted with vertex colors; the import leaves this off)
		copy.vertex_color_is_srgb = true
		copy.albedo_color = tint
		copy.metallic_specular = 0.1
		copy.roughness = 1.0
		material = copy
	scene.free()
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = rows.size()
	for i in rows.size():
		var row: Array = rows[i]
		var basis := Basis(Vector3.UP, float(row[3])).scaled(Vector3.ONE * float(row[4]))
		multi.set_instance_transform(i, Transform3D(basis, Vector3(row[0], row[1], row[2])) * local)
	var holder := MultiMeshInstance3D.new()
	holder.multimesh = multi
	holder.material_override = material
	holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(holder)
	return holder


func _build_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261013
	var gap := _screen_point(Vector2(-0.12, 0.0), 1.0)  # the valley toward the tower stays open
	var gap_dir := Vector2(gap.x - CAMERA_POS.x, gap.z - CAMERA_POS.z).normalized()

	# Far treeline (25-45 m): flat silhouettes, lowest in the valley under the tower.
	var far_pines: Array = []
	var far_oaks: Array = []
	var x := -60.0
	while x < 60.0:
		var z := rng.randf_range(-36.0, -22.0)
		var to := Vector2(x - CAMERA_POS.x, z - CAMERA_POS.z).normalized()
		var valley := smoothstep(0.03, 0.16, absf(to.angle_to(gap_dir)))
		var scale_by := lerpf(0.45, 1.25, valley) * rng.randf_range(0.8, 1.15)
		if rng.randf() < 0.75:
			far_pines.append([x, -0.3, z, rng.randf() * TAU, scale_by])
		else:
			far_oaks.append([x, -0.3, z, rng.randf() * TAU, scale_by * 0.85])
		x += rng.randf_range(1.6, 3.2)
	var far_ink := _flat(NIGHT_INK.lerp(HORIZON, 0.3))
	_scatter("pine", far_pines, far_ink)
	_scatter("oak", far_oaks, far_ink)

	# The forest edge on the left, around and behind the fire (lit by it and the moon).
	var pines: Array = []
	var oaks: Array = []
	var spots := [
		[-9.5, -6.0, 1.25], [-13.0, -3.0, 1.4], [-7.0, -11.0, 1.15], [-16.0, -9.0, 1.3],
		[-11.0, -16.0, 1.2], [-6.0, -17.0, 1.0], [-19.0, -2.0, 1.5], [-6.5, -3.5, 0.95],
		[-24.0, -19.0, 1.2], [-21.0, -14.0, 1.3], [-12.5, 3.5, 1.5],
	]
	for spot in spots:
		pines.append([spot[0], 0.0, spot[1], rng.randf() * TAU, spot[2]])
	oaks.append([-8.5, 0.0, -9.0, 0.7, 0.85])
	oaks.append([-15.0, 0.0, -20.0, 2.1, 1.1])
	_scatter("pine", pines, null, Color(0.55, 0.6, 0.65))
	_scatter("oak", oaks, null, Color(0.5, 0.55, 0.6))

	# Framing: a huge dark pine cut by the left edge, and two on the far right (deep shadow: menu side).
	var frame := _flat(Color(0.012, 0.016, 0.03))
	_scatter("pine", [[-8.2, -0.5, 6.0, 0.4, 1.7], [9.5, -0.5, 3.0, 1.9, 1.9], [13.0, -0.5, -2.0, 0.9, 1.6]], frame)

	# Undergrowth near the fire.
	var bushes: Array = [[-6.2, 0.0, -1.0, 0.3, 0.9], [-8.0, 0.0, 2.2, 1.7, 0.8], [-1.5, 0.0, -2.5, 2.4, 0.7], [-5.0, 0.0, -5.0, 0.9, 1.0]]
	_scatter("bush", bushes, null, Color(0.55, 0.6, 0.62))
	var rocks: Array = [[-5.4, 0.0, 3.6, 0.6, 0.55], [0.6, 0.0, 0.8, 2.0, 0.45], [-7.0, 0.0, -2.0, 1.1, 0.8], [2.8, 0.0, -4.0, 0.2, 0.6]]
	_scatter("rock", rocks, null, Color(0.6, 0.62, 0.68))
	var grass: Array = []
	var ferns: Array = []
	for i in 70:
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(1.2, 7.5)
		var spot := FIRE_POS + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist * 0.8)
		if spot.z > 4.0 or spot.x > 0.5:
			continue
		grass.append([spot.x, 0.0, spot.z, rng.randf() * TAU, rng.randf_range(1.0, 2.0)])
	for i in 16:
		var spot := Vector3(rng.randf_range(-12.0, 3.0), 0.0, rng.randf_range(-6.0, 3.5))
		if spot.distance_to(FIRE_POS) > 1.6:
			ferns.append([spot.x, 0.0, spot.z, rng.randf() * TAU, rng.randf_range(0.8, 1.4)])
	_scatter("grass", grass, null, Color(0.6, 0.65, 0.6))
	_scatter("fern", ferns, null, Color(0.55, 0.6, 0.6))


# --- the campfire ------------------------------------------------------------------------------------

func _billboard_material(color: Color, additive: bool = true) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _soft_dot
	material.albedo_color = color
	material.disable_fog = true
	return material


func _particles(amount_high: int, amount_low: int, lifetime: float, size: float, material: Material, ramp: Gradient) -> CPUParticles3D:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	quad.material = material
	var particles := CPUParticles3D.new()
	particles.mesh = quad
	particles.amount = amount_high
	particles.lifetime = lifetime
	particles.color_ramp = ramp
	particles.gravity = Vector3.ZERO
	particles.emitting = true
	particles.preprocess = lifetime  # already burning on the first frame
	add_child(particles)
	_scalable.append({"node": particles, "high": amount_high, "low": amount_low})
	return particles


func _ramp(points: Array) -> Gradient:
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for point in points:
		offsets.append(float(point[0]))
		colors.append(point[1])
	var gradient := Gradient.new()
	gradient.offsets = offsets
	gradient.colors = colors
	return gradient


func _build_campfire() -> void:
	# Stones and logs.
	var stones: Array = []
	for i in 9:
		var angle := TAU * float(i) / 9.0
		stones.append([FIRE_POS.x + cos(angle) * 0.62, 0.0, FIRE_POS.z + sin(angle) * 0.62, angle * 2.0, 0.17])
	_scatter("rock", stones, null, Color(0.7, 0.7, 0.72))
	var log_material := StandardMaterial3D.new()
	log_material.albedo_color = Color(0.22, 0.14, 0.09)
	var log_mesh := CylinderMesh.new()
	log_mesh.top_radius = 0.07
	log_mesh.bottom_radius = 0.08
	log_mesh.height = 0.95
	log_mesh.radial_segments = 6
	var logs := MultiMesh.new()
	logs.transform_format = MultiMesh.TRANSFORM_3D
	logs.mesh = log_mesh
	logs.instance_count = 4
	for i in 4:
		var basis := Basis(Vector3.UP, deg_to_rad(45.0 * float(i) + 10.0)) * Basis(Vector3.RIGHT, deg_to_rad(68.0))
		logs.set_instance_transform(i, Transform3D(basis, FIRE_POS + Vector3(0.0, 0.18, 0.0)))
	var log_holder := MultiMeshInstance3D.new()
	log_holder.multimesh = logs
	log_holder.material_override = log_material
	add_child(log_holder)
	# Warm pool of light on the ground (cheap fake bounce) and a soft halo in the air.
	var pool := StandardMaterial3D.new()
	pool.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pool.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pool.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pool.albedo_texture = _soft_dot
	pool.albedo_color = Color(0.55, 0.24, 0.08, 0.7)
	pool.disable_fog = true
	var pool_mesh := PlaneMesh.new()
	pool_mesh.size = Vector2(7.0, 7.0)
	_fire_pool = _shape(pool_mesh, pool, FIRE_POS + Vector3(0.0, 0.02, 0.0))
	var halo_material := _billboard_material(Color(1.0, 0.5, 0.18, 0.35))
	halo_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo_material.vertex_color_use_as_albedo = false
	var halo_mesh := QuadMesh.new()
	halo_mesh.size = Vector2(3.2, 3.2)
	_shape(halo_mesh, halo_material, FIRE_POS + Vector3(0.0, 0.7, 0.0))

	# Flames: soft additive blobs rising and shrinking.
	var flames := _particles(30, 30, 0.8, 0.42, _billboard_material(Color(1.0, 1.0, 1.0)), _ramp([
		[0.0, Color(1.0, 0.85, 0.45, 0.0)], [0.12, Color(1.0, 0.78, 0.35, 1.0)],
		[0.55, Color(1.0, 0.4, 0.08, 0.8)], [1.0, Color(0.6, 0.1, 0.02, 0.0)]]))
	flames.position = FIRE_POS + Vector3(0.0, 0.2, 0.0)
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = 0.2
	flames.direction = Vector3.UP
	flames.spread = 10.0
	flames.initial_velocity_min = 0.7
	flames.initial_velocity_max = 1.3
	flames.scale_amount_min = 0.6
	flames.scale_amount_max = 1.2
	flames.scale_amount_curve = _curve([[0.0, 0.7], [0.3, 1.0], [1.0, 0.25]])

	# Embers: tiny sparks that float up high and wander.
	var embers := _particles(40, 14, 3.2, 0.07, _billboard_material(Color(1.0, 1.0, 1.0)), _ramp([
		[0.0, Color(1.0, 0.85, 0.4, 0.0)], [0.08, Color(1.0, 0.75, 0.3, 1.0)],
		[0.7, Color(1.0, 0.4, 0.1, 0.8)], [1.0, Color(0.8, 0.2, 0.05, 0.0)]]))
	embers.position = FIRE_POS + Vector3(0.0, 0.5, 0.0)
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = 0.3
	embers.direction = Vector3(0.25, 1.0, 0.0)
	embers.spread = 28.0
	embers.initial_velocity_min = 0.8
	embers.initial_velocity_max = 2.0
	embers.gravity = Vector3(0.35, 0.25, 0.0)  # a light breeze toward the right
	embers.damping_min = 0.2
	embers.damping_max = 0.5
	embers.scale_amount_min = 0.6
	embers.scale_amount_max = 1.4

	# Thin smoke, barely there, lit from below.
	var smoke_material := _billboard_material(Color(0.5, 0.5, 0.6), false)
	var smoke := _particles(10, 1, 4.5, 1.4, smoke_material, _ramp([
		[0.0, Color(0.35, 0.25, 0.2, 0.0)], [0.2, Color(0.3, 0.27, 0.3, 0.16)], [1.0, Color(0.2, 0.22, 0.3, 0.0)]]))
	smoke.position = FIRE_POS + Vector3(0.0, 1.0, 0.0)
	smoke.direction = Vector3(0.2, 1.0, 0.0)
	smoke.spread = 10.0
	smoke.initial_velocity_min = 0.5
	smoke.initial_velocity_max = 0.8
	smoke.scale_amount_curve = _curve([[0.0, 0.4], [1.0, 1.6]])
	_extras.append(smoke)

	_fire_light = OmniLight3D.new()
	_fire_light.light_color = FIRE_COLOR
	_fire_light.omni_range = 8.0
	_fire_light.omni_attenuation = 1.4
	_fire_light.shadow_enabled = false
	_fire_light.light_energy = FIRE_ENERGY
	_fire_light.position = FIRE_POS + Vector3(0.0, 0.8, 0.0)
	add_child(_fire_light)


func _curve(points: Array) -> Curve:
	var curve := Curve.new()
	for point in points:
		curve.add_point(Vector2(point[0], point[1]))
	return curve


## The traveller: the player's chibi standing by the fire, its back to us (lit from the front by the fire).
func _build_character() -> void:
	var model := CharacterModel.new()
	model.ink_outline = false
	model.position = CHARACTER_POS
	add_child(model)
	if not model.load_model():
		model.queue_free()
		return
	_character = model
	var to_fire := Vector2(FIRE_POS.x - CHARACTER_POS.x, FIRE_POS.z - CHARACTER_POS.z).normalized()
	_character.set_pose("idle", 0.0, 0.0, true, to_fire, false)
	_extras.append(model)


# --- fireflies, motes, mist, menu shade --------------------------------------------------------------

func _build_fireflies() -> void:
	var fireflies := _particles(28, 10, 7.0, 0.09, _billboard_material(Color(1.0, 1.0, 1.0)), _ramp([
		[0.0, Color(0.75, 1.0, 0.45, 0.0)], [0.15, Color(0.8, 1.0, 0.45, 1.0)], [0.3, Color(0.7, 1.0, 0.4, 0.15)],
		[0.5, Color(0.8, 1.0, 0.5, 1.0)], [0.7, Color(0.7, 1.0, 0.4, 0.2)], [0.85, Color(0.8, 1.0, 0.45, 0.9)],
		[1.0, Color(0.7, 1.0, 0.4, 0.0)]]))
	fireflies.position = Vector3(-6.0, 1.3, -2.0)
	fireflies.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fireflies.emission_box_extents = Vector3(7.0, 1.1, 6.0)
	fireflies.direction = Vector3(1.0, 0.2, 0.0)
	fireflies.spread = 180.0
	fireflies.initial_velocity_min = 0.08
	fireflies.initial_velocity_max = 0.3
	fireflies.gravity = Vector3(0.0, 0.03, 0.0)
	fireflies.scale_amount_min = 0.7
	fireflies.scale_amount_max = 1.3
	fireflies.randomness = 0.6

	# Pale motes drifting high in the cold air, near the moon: the "drifting particles" layer.
	var motes := _particles(22, 8, 12.0, 0.25, _billboard_material(Color(1.0, 1.0, 1.0)), _ramp([
		[0.0, Color(0.6, 0.75, 1.0, 0.0)], [0.3, Color(0.6, 0.75, 1.0, 0.5)], [0.7, Color(0.6, 0.75, 1.0, 0.4)], [1.0, Color(0.6, 0.75, 1.0, 0.0)]]))
	motes.position = Vector3(-6.0, 7.0, -14.0)
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(14.0, 5.0, 6.0)
	motes.direction = Vector3(1.0, 0.15, 0.0)
	motes.spread = 25.0
	motes.initial_velocity_min = 0.2
	motes.initial_velocity_max = 0.5
	motes.scale_amount_min = 0.4
	motes.scale_amount_max = 1.0


const MIST_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec3 tint : source_color;
uniform float strength = 0.3;
uniform float speed = 0.01;

void fragment() {
	vec2 uv = UV;
	float n = texture(noise_tex, vec2(uv.x * 1.6 + TIME * speed, uv.y * 0.5 + 0.2)).r;
	float n2 = texture(noise_tex, vec2(uv.x * 3.1 - TIME * speed * 0.7, uv.y * 0.8 + 0.6)).r;
	float rise = smoothstep(0.0, 0.55, 1.0 - uv.y) * smoothstep(1.0, 0.8, 1.0 - uv.y);  // thick low, fades at both edges
	float sides = smoothstep(0.0, 0.15, uv.x) * smoothstep(1.0, 0.85, uv.x);
	ALBEDO = tint;
	ALPHA = clamp(n * 0.65 + n2 * 0.35 - 0.25, 0.0, 1.0) * rise * sides * strength;
}
"""


func _build_mist() -> void:
	var shader := _shader(MIST_SHADER)
	# [depth m from the camera, width, height, strength, speed]
	var layers := [[34.0, 120.0, 7.0, 0.55, 0.006], [18.0, 70.0, 3.6, 0.4, 0.01], [9.0, 40.0, 1.8, 0.28, 0.016]]
	for i in layers.size():
		var spec: Array = layers[i]
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("noise_tex", _noise)
		material.set_shader_parameter("tint", Color(0.42, 0.5, 0.7))
		material.set_shader_parameter("strength", float(spec[3]))
		material.set_shader_parameter("speed", float(spec[4]))
		var quad := QuadMesh.new()
		quad.size = Vector2(spec[1], spec[2])
		var mist := MeshInstance3D.new()
		mist.mesh = quad
		mist.material_override = material
		mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var depth: float = spec[0]
		mist.position = Vector3(CAMERA_POS.x - 4.0, float(spec[2]) * 0.38 - 0.2, CAMERA_POS.z - depth)
		add_child(mist)
		if i != 1:
			_extras.append(mist)


const SHADE_SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, shadows_disabled, depth_draw_never, depth_test_disabled;
uniform vec3 shade : source_color;

void fragment() {
	float a = smoothstep(0.5, 1.0, SCREEN_UV.x) * 0.5 + smoothstep(0.75, 1.0, SCREEN_UV.y) * 0.25;
	ALBEDO = shade;
	ALPHA = clamp(a, 0.0, 0.7);
}
"""


## A soft darkening over the right half and the bottom (under the menu), attached to the camera.
func _build_menu_shade() -> void:
	var material := ShaderMaterial.new()
	material.shader = _shader(SHADE_SHADER)
	material.set_shader_parameter("shade", Color(0.01, 0.012, 0.03))
	material.render_priority = 10
	var quad := QuadMesh.new()
	quad.size = Vector2(8.0, 8.0) * tan(deg_to_rad(FOV) * 0.5) * 2.0  # (wider than any screen at 1 m)
	var shade := MeshInstance3D.new()
	shade.mesh = quad
	shade.material_override = material
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shade.position = Vector3(0.0, 0.0, -1.0)
	shade.extra_cull_margin = 16384.0
	_camera.add_child(shade)


# --- helpers ------------------------------------------------------------------------------------------

func _shader(code: String) -> Shader:
	var shader := Shader.new()
	shader.code = code
	return shader


func _radial_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.35, Color(1.0, 1.0, 1.0, 0.45))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture


func _noise_texture() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = 13
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 128
	texture.seamless = true
	texture.noise = noise
	return texture
