extends MeshInstance3D
## A ribbon behind a swinging weapon, drawn between the weapon's own trail_start and trail_end
## points (markers in the model team's weapon .glb), so a long blade leaves a long trail and a dagger
## a short one. A bright glint flashes at effect_point when the strike begins. Display only.
## CharacterModel feeds it every frame: sample() while the blow is live, nothing otherwise.

const LIFE := 0.13  ## seconds a sample of the ribbon lasts
const MAX_SAMPLES := 24
const GLINT_SECONDS := 0.09
const GLINT_SIZE := 0.22

var color := Color(1.0, 0.95, 0.85)
var _samples: Array[Dictionary] = []  ## {"a": Vector3, "b": Vector3, "age": float}, oldest first
var _glint := 0.0
var _glint_at := Vector3.ZERO
var _mesh := ImmediateMesh.new()


func _ready() -> void:
	top_level = true  # the ribbon lives in the world, not in the swinging hand
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Additive light, or mix-blended paint under the drawn style (client/vfx/ink_vfx.gd, graphics setting drawn_style).
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX if preload("res://client/vfx/ink_vfx.gd").enabled() else BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = false
	material_override = material


## Adds this frame's blade line (world positions of the weapon's trail points).
func sample(start: Vector3, end: Vector3) -> void:
	if not preload("res://client/graphics_options.gd").enabled("combat_vfx"): return
	_samples.append({"a": start, "b": end, "age": 0.0})
	if _samples.size() > MAX_SAMPLES:
		_samples.pop_front()


## A glint at the weapon's effect point (the strike begins).
func glint(at: Vector3) -> void:
	if not preload("res://client/graphics_options.gd").enabled("combat_vfx"): return
	_glint = GLINT_SECONDS
	_glint_at = at


func is_drawing() -> bool:
	return _samples.size() >= 2 or _glint > 0.0


func _process(delta: float) -> void:
	if not preload("res://client/graphics_options.gd").enabled("combat_vfx"):
		_samples.clear()
		_glint = 0.0
		_mesh.clear_surfaces()
		return
	global_transform = Transform3D.IDENTITY
	for entry in _samples:
		entry["age"] += delta
	while not _samples.is_empty() and _samples[0]["age"] > LIFE:
		_samples.pop_front()
	_glint = maxf(0.0, _glint - delta)
	_mesh.clear_surfaces()
	if _samples.size() < 2 and _glint <= 0.0:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(1, _samples.size()):
		var old: Dictionary = _samples[index - 1]
		var new: Dictionary = _samples[index]
		var fade_old: float = 1.0 - float(old["age"]) / LIFE
		var fade_new: float = 1.0 - float(new["age"]) / LIFE
		# Brightest along the edge near the tip; the inner edge fades so the ribbon reads as a sweep.
		var tip_old := Color(color, 0.85 * fade_old)
		var tip_new := Color(color, 0.85 * fade_new)
		var root_old := Color(color, 0.12 * fade_old)
		var root_new := Color(color, 0.12 * fade_new)
		_quad(old["a"], old["b"], new["b"], new["a"], root_old, tip_old, tip_new, root_new)
	if _glint > 0.0:
		var strength := _glint / GLINT_SECONDS
		var camera := get_viewport().get_camera_3d()
		var right := camera.global_basis.x if camera != null else Vector3.RIGHT
		var up := camera.global_basis.y if camera != null else Vector3.UP
		var size := GLINT_SIZE * (0.6 + 0.4 * strength)
		var white := Color(1.0, 1.0, 1.0, strength)
		var clear := Color(color, 0.0)
		# A four-pointed star: two thin crossed diamonds.
		for axis in [[right * size, up * size * 0.18], [up * size, right * size * 0.18]]:
			var long_axis: Vector3 = axis[0]
			var short_axis: Vector3 = axis[1]
			_triangle(_glint_at - long_axis, _glint_at + short_axis, _glint_at, clear, clear, white)
			_triangle(_glint_at + short_axis, _glint_at + long_axis, _glint_at, clear, clear, white)
			_triangle(_glint_at + long_axis, _glint_at - short_axis, _glint_at, clear, clear, white)
			_triangle(_glint_at - short_axis, _glint_at - long_axis, _glint_at, clear, clear, white)
	_mesh.surface_end()


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_triangle(a, b, c, ca, cb, cc)
	_triangle(a, c, d, ca, cc, cd)


func _triangle(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	_mesh.surface_set_color(ca)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(cb)
	_mesh.surface_add_vertex(b)
	_mesh.surface_set_color(cc)
	_mesh.surface_add_vertex(c)
