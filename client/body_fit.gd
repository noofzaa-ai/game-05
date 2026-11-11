extends RefCounted
## Keeps skin from poking through clothes. The model team's clothes sit very close to the body, so in
## motion the skin under them shows through in patches. fitted() returns a copy of a body mesh where
## every corner that a garment covers (a short line through it along its normal meets the garment) is
## pulled in under the garment by PUSH; uncovered skin stays exactly as it was. Body and clothes are
## skinned to the same skeleton in the same rest pose, so their vertices can be compared directly.
## The result is kept per body mesh and set of garments (computed once, a few tens of ms).

const PUSH := 0.015  ## how far below the garment covered skin goes (meters)
const REACH_OUT := 0.10  ## a garment this far outside the skin still covers it
const REACH_IN := 0.03  ## ... and this far inside it (where the skin already pokes through)
const CELL := 0.04  ## the size of the grid the garment triangles are sorted into

static var _cache: Dictionary = {}


## `body`: the body part's mesh; `garments`: the meshes of every worn piece. Returns `body` itself when
## nothing covers it.
static func fitted(body: Mesh, garments: Array) -> Mesh:
	if not body is ArrayMesh or body.get_blend_shape_count() > 0 or garments.is_empty():
		return body
	var key := str(body.get_instance_id())
	var ids: Array = garments.map(func(mesh: Mesh) -> int: return mesh.get_instance_id())
	ids.sort()
	key += ":" + ",".join(ids.map(func(id: int) -> String: return str(id)))
	if _cache.has(key):
		return _cache[key]
	var grid := _triangle_grid(garments)
	var result := ArrayMesh.new()
	var moved := 0
	for surface in body.get_surface_count():
		var arrays: Array = body.surface_get_arrays(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals = arrays[Mesh.ARRAY_NORMAL]
		if normals is PackedVector3Array and normals.size() == positions.size():
			var smooth := _averaged_normals(positions, normals)
			var shift := {}  # position -> how far along its normal (corners at one position move together)
			for index in positions.size():
				var spot := positions[index].snapped(Vector3.ONE * 0.0001)
				if shift.has(spot):
					continue
				var depth = _cover_depth(positions[index], smooth[spot], grid)
				shift[spot] = 0.0 if depth == null else minf(float(depth), 0.0) - PUSH
			for index in positions.size():
				var spot := positions[index].snapped(Vector3.ONE * 0.0001)
				if shift[spot] < 0.0:
					positions[index] += smooth[spot] * shift[spot]
					moved += 1
			arrays[Mesh.ARRAY_VERTEX] = positions
		var flags: int = body.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		result.add_surface_from_arrays(body.surface_get_primitive_type(surface), arrays, [], {}, flags)
		result.surface_set_material(surface, body.surface_get_material(surface))
		result.surface_set_name(surface, body.surface_get_name(surface))
	var answer: Mesh = result if moved > 0 else body
	_cache[key] = answer
	return answer


## Where the nearest garment is along the normal from `point` (negative = inside the skin), or null.
static func _cover_depth(point: Vector3, normal: Vector3, grid: Dictionary):
	var start := point - normal * REACH_IN
	var end := point + normal * REACH_OUT
	var tested := {}
	var best = null
	var low := _cell(start.min(end))
	var high := _cell(start.max(end))
	for x in range(low.x, high.x + 1):
		for y in range(low.y, high.y + 1):
			for z in range(low.z, high.z + 1):
				for triangle in grid.get(Vector3i(x, y, z), []):
					if tested.has(triangle):
						continue
					tested[triangle] = true
					var hit = Geometry3D.segment_intersects_triangle(start, end, triangle[0], triangle[1], triangle[2])
					if hit != null:
						var depth: float = (hit - point).dot(normal)
						if best == null or depth < best:
							best = depth
	return best


static func _triangle_grid(garments: Array) -> Dictionary:
	var grid := {}
	for mesh in garments:
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays: Array = mesh.surface_get_arrays(surface)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices = arrays[Mesh.ARRAY_INDEX]
			var count: int = indices.size() if indices is PackedInt32Array and not indices.is_empty() else positions.size()
			for corner in range(0, count - 2, 3):
				var a := positions[indices[corner] if indices is PackedInt32Array and not indices.is_empty() else corner]
				var b := positions[indices[corner + 1] if indices is PackedInt32Array and not indices.is_empty() else corner + 1]
				var c := positions[indices[corner + 2] if indices is PackedInt32Array and not indices.is_empty() else corner + 2]
				var triangle := [a, b, c]
				var low := _cell(a.min(b).min(c))
				var high := _cell(a.max(b).max(c))
				for x in range(low.x, high.x + 1):
					for y in range(low.y, high.y + 1):
						for z in range(low.z, high.z + 1):
							var key := Vector3i(x, y, z)
							if not grid.has(key):
								grid[key] = []
							grid[key].append(triangle)
	return grid


static func _cell(point: Vector3) -> Vector3i:
	return Vector3i(floori(point.x / CELL), floori(point.y / CELL), floori(point.z / CELL))


## position (snapped) -> the average normal of every corner there.
static func _averaged_normals(positions: PackedVector3Array, normals: PackedVector3Array) -> Dictionary:
	var sums := {}
	for index in positions.size():
		var spot := positions[index].snapped(Vector3.ONE * 0.0001)
		sums[spot] = sums.get(spot, Vector3.ZERO) + normals[index]
	for spot in sums:
		sums[spot] = sums[spot].normalized() if sums[spot].length_squared() > 0.000001 else Vector3.UP
	return sums
