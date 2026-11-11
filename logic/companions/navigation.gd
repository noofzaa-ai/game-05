extends RefCounted
## Cached static XZ walking graph. Full body clearance and floor support, no teleports.
const HALF := 0.43
var _world
var _grid: AStarGrid2D
var _height := INF
var _path := PackedVector2Array()
var _goal := Vector2.INF
var _refresh := 0

func direction(world, at: Vector3, goal: Vector3) -> Vector2:
	if _world != world or absf(_height - at.y) > 0.45:
		_build(world, at.y)
	if _grid == null: return Vector2.ZERO
	_refresh -= 1
	var target := Vector2(goal.x, goal.z)
	if _refresh <= 0 or target.distance_to(_goal) > 1.0 or _path.is_empty():
		_refresh = 24
		_goal = target
		var start := _nearest(Vector2(at.x, at.z))
		var end := _nearest(target)
		_path = _grid.get_point_path(start, end, true) if start != Vector2i(2147483647, 2147483647) and end != Vector2i(2147483647, 2147483647) else PackedVector2Array()
		if _path.size() > 1: _path.remove_at(0)
	var flat := Vector2(at.x, at.z)
	while _path.size() > 1 and flat.distance_to(_path[0]) < 0.3: _path.remove_at(0)
	if _path.is_empty(): return Vector2.ZERO
	return (_path[0] - flat).normalized() if flat.distance_to(_path[0]) > 0.12 else Vector2.ZERO

func _build(world, height: float) -> void:
	_world = world
	_height = height
	_path.clear()
	_grid = null
	var width := ceili(world.half_width)
	var depth := ceili(world.half_depth)
	if width > 128 or depth > 128: return # Authored worlds are bounded; no unbounded allocation.
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(-width, -depth, width * 2 + 1, depth * 2 + 1)
	_grid.cell_size = Vector2.ONE
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()
	for x in range(-width, width + 1):
		for z in range(-depth, depth + 1):
			var safe: bool = absf(x) + HALF < world.half_width and absf(z) + HALF < world.half_depth
			var floor_found := false
			var footprint := AABB(Vector3(x-HALF, height+0.15, z-HALF), Vector3(HALF*2, 1.45, HALF*2))
			for solid in world.solids:
				if footprint.intersects(solid): safe = false; break
				if absf(solid.end.y-height) <= 0.35 and solid.position.x <= x-HALF and solid.end.x >= x+HALF and solid.position.z <= z-HALF and solid.end.z >= z+HALF: floor_found = true
			_grid.set_point_solid(Vector2i(x,z), not safe or not floor_found)

func _nearest(at: Vector2) -> Vector2i:
	var center := Vector2i(roundi(at.x), roundi(at.y))
	var best := Vector2i(2147483647, 2147483647)
	var distance := INF
	for x in range(center.x-3, center.x+4):
		for z in range(center.y-3, center.y+4):
			var p := Vector2i(x,z)
			if not _grid.is_in_boundsv(p) or _grid.is_point_solid(p): continue
			var d := at.distance_squared_to(Vector2(p))
			if d < distance: distance = d; best = p
	return best

static func line_clear(world, a: Vector3, b: Vector3) -> bool:
	for solid in world.solids:
		if solid.intersects_segment(a + Vector3.UP * 0.8, b + Vector3.UP * 0.8) != null: return false
	return true

static func line_supported(world, a: Vector3, b: Vector3) -> bool:
	if not line_clear(world,a,b): return false
	var steps := maxi(1, ceili(a.distance_to(b)/0.3))
	for index in range(steps+1):
		var point := a.lerp(b,float(index)/steps)
		if absf(point.x)+HALF >= world.half_width or absf(point.z)+HALF >= world.half_depth: return false
		var supported := false
		for solid in world.solids:
			if absf(solid.end.y-point.y) <= 0.35 and solid.position.x <= point.x-HALF and solid.end.x >= point.x+HALF and solid.position.z <= point.z-HALF and solid.end.z >= point.z+HALF:
				supported = true; break
		if not supported: return false
	return true
