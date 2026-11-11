extends RefCounted
## The painted "ink and wash" look: dark outlines on characters and scenery, and a soft cloudy wash
## texture for the ground. Used by stages whose map says `atmosphere: "ink"`.
## EXTENDING: more of the look (paper grain, brush-stroke edges) is added here and used where needed.

const OUTLINE_SHADER := preload("res://client/ink_outline.gdshader")
const INK := Color(0.07, 0.07, 0.09)

static var _outline_cache: Dictionary = {}


## The outline material: draw it as a mesh's overlay or as a material's next pass. `width` is in the
## mesh's own units (about the line thickness in meters); the shader keeps it a couple of pixels thick.
static func outline_material(width: float = 0.005) -> ShaderMaterial:
	var key := snappedf(width, 0.0001)
	if not _outline_cache.has(key):
		var material := ShaderMaterial.new()
		material.shader = OUTLINE_SHADER
		material.set_shader_parameter("width", width)
		material.set_shader_parameter("min_pixels", 0.0)
		material.set_shader_parameter("ink_color", INK)
		_outline_cache[key] = material
	return _outline_cache[key]


## The shape the outline of `mesh` is drawn with: the same mesh, but every corner's normal is the
## average of all corners at that position, so the line is pushed out evenly and stays whole across
## the hard edges and seams of low-poly models (with the mesh's own normals it tears apart there).
## No materials: it is drawn only with the outline. Made once per mesh and kept on it.
static func outline_mesh(mesh: Mesh) -> Mesh:
	if not mesh is ArrayMesh or mesh.get_blend_shape_count() > 0:
		return mesh
	if mesh.has_meta("outline_mesh"):
		return mesh.get_meta("outline_mesh")
	var result := ArrayMesh.new()
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals = arrays[Mesh.ARRAY_NORMAL]
		if normals is PackedVector3Array and normals.size() == positions.size():
			var sums := {}
			for index in positions.size():
				var key := positions[index].snapped(Vector3.ONE * 0.0001)
				sums[key] = sums.get(key, Vector3.ZERO) + normals[index]
			var smooth := PackedVector3Array()
			smooth.resize(positions.size())
			for index in positions.size():
				var averaged: Vector3 = sums[positions[index].snapped(Vector3.ONE * 0.0001)]
				smooth[index] = averaged.normalized() if averaged.length_squared() > 0.000001 else normals[index]
			arrays[Mesh.ARRAY_NORMAL] = smooth
		arrays[Mesh.ARRAY_TANGENT] = null
		var flags: int = mesh.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		result.add_surface_from_arrays(mesh.surface_get_primitive_type(surface), arrays, [], {}, flags)
	mesh.set_meta("outline_mesh", result)
	return result


## The ground: soft blotches of grey-green, like washes of diluted ink.
static func ground_material(dark: Color = Color(0.22, 0.27, 0.24), light: Color = Color(0.40, 0.45, 0.39)) -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.018
	noise.fractal_octaves = 3
	noise.fractal_gain = 0.55
	var ramp := Gradient.new()
	ramp.set_color(0, dark)
	ramp.set_color(1, light)
	var texture := NoiseTexture2D.new()
	texture.noise = noise
	texture.color_ramp = ramp
	texture.width = 512
	texture.height = 512
	texture.seamless = true
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.uv1_triplanar = true  # the texture follows the world, not the box's stretched faces
	material.uv1_scale = Vector3(0.09, 0.09, 0.09)
	material.roughness = 1.0
	return material
