extends RefCounted
## Deterministic placement using collision bounds, not art. The solo spawn is unchanged.
const Body := preload("res://logic/sim_body.gd")

static func points(map, count: int, spacing: float) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for i in count:
		var found := false
		var candidates: Array[Vector3] = []
		if i < map.player_spawns.size(): candidates.append(map.player_spawns[i])
		if i == 0: candidates.append(map.spawn)
		for ring in range(1, 12):
			for index in 8:
				var angle := float(index) * TAU / 8.0
				candidates.append(map.spawn + Vector3(cos(angle), 0, sin(angle)) * spacing * ring)
		for at in candidates:
			if not at.is_finite(): continue
			if absf(at.x) > map.half_width - Body.HALF_WIDTH or absf(at.z) > map.half_depth - Body.HALF_DEPTH: continue
			var box := AABB(at + Vector3(-Body.HALF_WIDTH, .03, -Body.HALF_DEPTH), Vector3(Body.HALF_WIDTH * 2, Body.HEIGHT - .03, Body.HALF_DEPTH * 2))
			if map.solids.any(func(solid): return solid["box"].intersects(box)): continue
			if result.any(func(other): return Vector2(at.x - other.x, at.z - other.z).length() < spacing * .8 or (absf(at.x-other.x) < Body.HALF_WIDTH*2 and absf(at.z-other.z) < Body.HALF_DEPTH*2 and absf(at.y-other.y) < Body.HEIGHT)): continue
			result.append(at)
			found = true
			break
		if not found: return []  # fail setup; never silently put players inside geometry
	return result
