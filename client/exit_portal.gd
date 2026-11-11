extends Node3D
## An EXIT PORTAL of a journey stage (Boss 2026-10-13, after Lost Castle 2's end-of-room beams): a tall
## beam of light, a ring on the ground and a floating icon, colored by what the next stage is. The
## player picks it by standing in the ring until it fills (HOLD_SECONDS), so walking past cannot pick
## by accident and it works the same with keys and touch. Only drawing and the hold timer live here;
## stage_view.gd asks the journey (logic/journey.gd) to take the choice.
## Cheap for the web / GL Compatibility: unshaded additive meshes, one CPU particle system, no lights.

const InkUi := preload("res://client/ink_ui.gd")

## Beam color by stage kind: blue = fight, green = rest camp, red-orange = challenge, gold = treasure,
## purple = boss.
const COLORS := {
	"combat": Color(0.30, 0.62, 1.00),
	"camp": Color(0.35, 1.00, 0.50),
	"challenge": Color(1.00, 0.40, 0.18),
	"treasure": Color(1.00, 0.80, 0.28),
	"boss": Color(0.72, 0.36, 1.00),
}
const NAMES := {"combat": "Combat", "camp": "Rest camp", "challenge": "Challenge", "treasure": "Treasure", "boss": "BOSS"}
const RADIUS := 1.1  ## standing within this (on the ground plane) fills the ring
const HOLD_SECONDS := 0.6  ## how long to stand in it before it takes you
const BEAM_HEIGHT := 9.0

var kind := "combat"
var index := 0  ## which upcoming choice this portal is
var stage := 0  ## the stage number it leads to
var hold := 0.0  ## seconds the player has stood in the ring
var color := Color.WHITE
var armed := false  ## a portal that rose under the player's feet waits until they have stepped out once

var _fill: MeshInstance3D  ## grows with `hold`
var _icon: Node3D
var _beam_core: MeshInstance3D
var _clock := 0.0


## Builds the portal for upcoming choice `choice_index` leading to node {"stage", "kind"}.
func setup(node: Dictionary, choice_index: int) -> void:
	kind = str(node.get("kind", "combat"))
	stage = int(node.get("stage", 0))
	index = choice_index
	color = COLORS.get(kind, COLORS["combat"])
	name = "ExitPortal%d" % choice_index
	_build()


## True while a point (feet position) is inside the ring.
func contains(at: Vector3) -> bool:
	return Vector2(at.x - position.x, at.z - position.z).length() <= RADIUS


## Advances the hold while the player stands in the ring (it empties quickly when they step out).
## Returns true once the ring is full: the player is taking this portal.
func update_hold(inside: bool, delta: float) -> bool:
	armed = armed or not inside
	if not armed:
		return false
	hold = clampf(hold + (delta if inside else -2.0 * delta), 0.0, HOLD_SECONDS)
	if _fill != null:
		var amount := hold / HOLD_SECONDS
		_fill.scale = Vector3(maxf(amount, 0.001), 1.0, maxf(amount, 0.001))
		_fill.visible = amount > 0.0
	return hold >= HOLD_SECONDS


func _process(delta: float) -> void:
	_clock += delta
	if _icon != null:
		_icon.position.y = 2.9 + 0.18 * sin(_clock * 2.2)
	if _beam_core != null:
		var pulse := 0.75 + 0.25 * sin(_clock * 3.1) + 0.6 * hold / HOLD_SECONDS
		(_beam_core.material_override as StandardMaterial3D).albedo_color = Color(color.r, color.g, color.b, clampf(pulse, 0.0, 1.0))


func _build() -> void:
	# The beam: a wide soft column and a thin bright core, both fading upward.
	add_child(_column(0.62, 0.78, Color(color.r, color.g, color.b, 0.55)))
	_beam_core = _column(0.22, 0.30, Color(color.r, color.g, color.b, 0.9))
	add_child(_beam_core)
	# The ground: a glowing disc, a bright rim, and the fill disc that grows while the player stands in it.
	add_child(_disc(RADIUS * 1.25, _radial_texture(0.85), Color(color.r, color.g, color.b, 0.55), 0.03))
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.outer_radius = RADIUS
	torus.inner_radius = RADIUS - 0.09
	torus.rings = 32
	torus.ring_segments = 6
	rim.mesh = torus
	rim.material_override = _additive(Color(color.r, color.g, color.b, 1.0))
	rim.scale.y = 0.2
	rim.position.y = 0.06
	add_child(rim)
	_fill = _disc(RADIUS, null, Color(color.r * 0.6 + 0.4, color.g * 0.6 + 0.4, color.b * 0.6 + 0.4, 0.7), 0.05)
	_fill.visible = false
	add_child(_fill)
	# The icon floats in the beam with the stage kind written under it.
	_icon = Node3D.new()
	add_child(_icon)
	var sprite := Sprite3D.new()
	sprite.texture = InkUi.icon(_icon_name(), 64, Color(1.0, 1.0, 1.0))
	sprite.modulate = color.lerp(Color.WHITE, 0.45)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.pixel_size = 0.009
	sprite.no_depth_test = true
	sprite.shaded = false
	sprite.render_priority = 2
	_icon.add_child(sprite)
	var label := Label3D.new()
	label.text = "%s\nStage %d" % [NAMES.get(kind, kind.capitalize()), stage] if stage > 0 else str(NAMES.get(kind, kind))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.009
	label.font_size = 52
	label.outline_size = 12
	label.font = InkUi.display_font()
	label.modulate = color.lerp(Color.WHITE, 0.55)
	label.outline_modulate = Color(0.04, 0.05, 0.10, 0.9)
	label.no_depth_test = true
	label.position = Vector3(0.0, 1.35, 0.0)  # (under the floating icon, above the ring; it does not bob)
	add_child(label)
	add_child(_sparks())


func _icon_name() -> String:
	return {"camp": "camp", "boss": "boss", "treasure": "treasure", "challenge": "challenge"}.get(kind, "combat")


## An open cylinder of light fading toward its top.
func _column(top: float, bottom: float, tint: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = BEAM_HEIGHT
	mesh.radial_segments = 16
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	var column := MeshInstance3D.new()
	column.mesh = mesh
	var material := _additive(tint)
	material.albedo_texture = _height_texture()
	column.material_override = material
	column.position.y = BEAM_HEIGHT * 0.5
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return column


func _disc(radius: float, texture: Texture2D, tint: Color, height: float) -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE * radius * 2.0
	var disc := MeshInstance3D.new()
	disc.mesh = mesh
	var material := _additive(tint)
	material.albedo_texture = texture if texture != null else _radial_texture(0.98)
	disc.material_override = material
	disc.position.y = height
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return disc


## A few motes of light rising through the beam.
func _sparks() -> CPUParticles3D:
	var sparks := CPUParticles3D.new()
	sparks.amount = 14
	sparks.lifetime = 2.2
	sparks.preprocess = 2.2
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	sparks.emission_ring_axis = Vector3.UP
	sparks.emission_ring_radius = RADIUS * 0.8
	sparks.emission_ring_inner_radius = 0.2
	sparks.emission_ring_height = 0.1
	sparks.direction = Vector3.UP
	sparks.spread = 8.0
	sparks.gravity = Vector3.ZERO
	sparks.initial_velocity_min = 1.0
	sparks.initial_velocity_max = 2.2
	sparks.scale_amount_min = 0.6
	sparks.scale_amount_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	sparks.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	var material := _additive(color.lerp(Color.WHITE, 0.4))
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _radial_texture(1.0)
	quad.material = material
	sparks.mesh = quad
	return sparks


static func _additive(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.albedo_color = tint
	return material


static var _height_tex: Texture2D
static var _radial_cache: Dictionary = {}


## Bright at the bottom of the beam, gone at the top (the cylinder's v runs top to bottom).
static func _height_texture() -> Texture2D:
	if _height_tex == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.55, 0.9, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.9), Color(1, 1, 1, 1.0)])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.width = 4
		texture.height = 64
		texture.fill_from = Vector2(0.5, 0.0)
		texture.fill_to = Vector2(0.5, 1.0)
		_height_tex = texture
	return _height_tex


## A soft round spot: opaque in the middle, fading out by `edge` of the radius.
static func _radial_texture(edge: float) -> Texture2D:
	var key := snappedf(edge, 0.01)
	if not _radial_cache.has(key):
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, edge * 0.7, edge])
		gradient.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0.0)])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.width = 64
		texture.height = 64
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		_radial_cache[key] = texture
	return _radial_cache[key]
