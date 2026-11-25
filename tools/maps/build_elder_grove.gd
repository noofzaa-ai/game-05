extends SceneTree
## Builds the Elder Grove boards (level-designer 2026-11-24, zone elder_tree, order 4): data/maps/elder_grove_*.json +
## art/maps/elder_grove/<id>.tscn + art/maps/elder_grove/meshes/<id>_{floor,dressing,kit}.res.
##   godot --headless --path . --script res://tools/maps/build_elder_grove.gd [-- map_id ...]
## Same contract as the orc / mummy islands (tools/maps/build_orc_camp.gd, build_mummy_pyramid.gd): the goblin courtyard
## board (16 x 9 m, same spawns, no cover: logic/auto_pilot.gd walks straight at its target) on a floating island whose
## whole top is this scene in three merged meshes, marked meta floating_island (client/arena_props.gd is_pyramid_island)
## and meta elder_grove (client/arena_props.gd is_grove_island: the warm leaf-light, the mossy underside, the motes).
##   Floor     3 surfaces: the board (goblin painted dirt tinted mossy loam), the margin + fascia (goblin painted grass
##             tinted deep moss), and the unshaded additive glow (shrine runes, lantern halos, canopy motes: on the floor
##             mesh because the floor is toon_no_outline, so the drawn style's ink hull never rings them dark). Sunlight
##             through the leaves is baked into the vertex colours (gold dapples); flat roots and the map's inlay (root
##             ring / flagstone path / stepping stones) lie on the board under 0.1 m.
##   Dressing  1 surface: the root-and-rotting-log walls north/east/west, hanging roots on the cliff, mossy stones, ferns,
##             grass and flowers (the verdant_reach painted props merged), low mushrooms on the open front.
##   Kit       1 surface: the giant elder tree, corner trees, the vine arch gate, the mossy stone shrine, glow caps; flat
##             vertex colours, no texture.
## Day light: 2-3 warm lantern lights at the shrine (light_lantern markers), no shadows; the rest is baked.
## Monster ids are a placeholder fixture (the elder family does not exist yet): the zone's journey will bring the real
## waves onto the spots in list order (melee x4, knight, melee, archer, mage), like the orc board.

const DIRT_TEX := "res://art/maps/goblin_base/painted/dirt.png"
const GRASS_TEX := "res://art/maps/goblin_base/painted/grass.png"
const PROP_DIR := "res://art/maps/verdant_reach/props/"
const SCENE_DIR := "res://art/maps/elder_grove/"
const MESH_DIR := "res://art/maps/elder_grove/meshes/"
const MAP_DIR := "res://data/maps/"
const W := 8.0
const D := 4.5
const BOARD_Y := 0.02
const EDGE_Y := 0.14
const ISLAND_W := W + 3.6  ## = arena_props.MARGIN_X
const ISLAND_D := D + 3.4  ## = arena_props.MARGIN_Z
const WALL_N := -ISLAND_D + 0.6
const WALL_X := ISLAND_W - 0.6
const WALL_END := ISLAND_D - 1.5

## sRGB palette (written linear; stage_props turns vertex_color_is_srgb off)
const LOAM := Color(0.60, 0.74, 0.46)  ## x the painted dirt: a mossy brown-green loam
const LOAM_DARK := Color(0.48, 0.60, 0.38)
const MOSS := Color(0.60, 0.78, 0.46)  ## x the painted grass: deep cushion moss
const MOSS_DARK := Color(0.44, 0.60, 0.36)
const SUN := Color(1.0, 0.90, 0.52)  ## the light through the leaves, baked
const BARK := Color(0.46, 0.34, 0.24)
const BARK_DARK := Color(0.32, 0.23, 0.17)
const ROTWOOD := Color(0.52, 0.42, 0.30)
const ROOT := Color(0.40, 0.29, 0.20)
const LEAF := Color(0.36, 0.58, 0.26)
const LEAF_DARK := Color(0.22, 0.42, 0.20)
const LEAF_GOLD := Color(0.78, 0.80, 0.34)
const MOSS_CAP := Color(0.42, 0.64, 0.28)
const VINE := Color(0.30, 0.52, 0.22)
const STONE := Color(0.62, 0.64, 0.58)
const STONE_DARK := Color(0.46, 0.48, 0.44)
const CAP_RED := Color(0.80, 0.34, 0.24)
const CAP_CREAM := Color(0.94, 0.88, 0.72)
const RUNE := Color(0.62, 1.0, 0.70)
const FLAG := Color(0.66, 0.78, 0.92)  ## inlaid stone (x the painted dirt texture: a pale weathered stone)
const FLAG_MOSS := Color(0.50, 0.80, 0.52)

const SPOTS := [
	["melee", 2.6, -3.4], ["melee", 2.6, -1.13], ["melee", 2.6, 1.13], ["melee", 2.6, 3.4],
	["knight", 3.9, -3.4], ["melee", 3.9, 3.4], ["archer", 6.8, -3.4], ["mage", 6.8, 3.4]]
## Placeholder fixture (no elder family yet): family-neutral old monsters, never a goblin / mummy / orc.
const FIXTURE := {"melee": "dummy_grunt", "knight": "brute", "archer": "dummy_grunt", "mage": "dummy_grunt"}


## The three boards. elder = [x, z, scale] of the giant tree; trees = corner/side trees [x, z, scale];
## arch = [x, z, yaw] of the vine gate (or []); shrine = [x, z, yaw, scale]; inlay = the board's flat feature.
static func layouts() -> Dictionary:
	return {
		"elder_grove_heart": {
			"name": "Elder Grove · Heart Tree", "seed": 11,
			"design": "The giant elder tree stands in the middle of the north wall, its roots spilling over the back margin and running flat across the board into a ring of roots round a moss heart in the middle of the fight (the memorable feature, nothing to trip on). Sunlight falls through its canopy in gold dapples. A small mossy shrine with two stone lanterns sits on the east margin, smaller trees in the back corners, ferns and glow-capped mushrooms on the open front cliff.",
			"elder": [0.0, -6.7, 1.0], "trees": [[-10.2, -6.4, 0.8], [10.2, -6.4, 0.75], [-10.6, 2.6, 0.6]],
			"arch": [], "shrine": [10.15, 1.2, -90.0, 0.8], "inlay": "root_ring",
		},
		"elder_grove_gate": {
			"name": "Elder Grove · Vine Gate", "seed": 23,
			"design": "A great arch of twisted vines and old wood breaks the north root wall: the way into the grove. A mossy flagstone path runs from the gate south across the board, the elder tree leans in from the north-west corner, a ring of mossy standing stones and lanterns (the shrine) guards the west margin, corner tree north-east, ferns and mushrooms on the open front.",
			"elder": [-9.6, -6.5, 0.72], "trees": [[10.2, -6.4, 0.85], [10.6, 3.0, 0.6]],
			"arch": [0.0, -7.0, 0.0], "shrine": [-10.15, 1.0, 90.0, 0.8], "inlay": "flag_path",
		},
		"elder_grove_shrine": {
			"name": "Elder Grove · Moss Shrine", "seed": 37,
			"design": "The old moss shrine of the Grove Warden sits on a stepped stone dais in the middle of the north wall, lit by two stone lanterns and green runes; the elder tree rises from the north-east corner and a small vine arch opens the west wall. Stepping stones circle the middle of the board, flat roots cross it, ferns and mushrooms on the open front cliff.",
			"elder": [9.6, -6.4, 0.78], "trees": [[-10.2, -6.4, 0.8], [10.6, 3.4, 0.55]],
			"arch": [-10.9, -1.4, 90.0], "shrine": [0.0, -6.4, 0.0, 1.15], "inlay": "stepping",
		},
	}


class Acc:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()

	func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, color: Color, uvs: Array) -> void:
		var base := v.size()
		var normal := (b - a).cross(d - a)
		if normal.length() < 0.000001:
			normal = (cc - a).cross(d - a)
		normal = normal.normalized()
		for k in 4:
			v.append([a, b, cc, d][k])
			n.append(normal)
			uv.append(uvs[k])
			c.append(color)
		i.append_array([base, base + 3, base + 2, base, base + 2, base + 1])

	func fan(centre: Vector3, radius: float, inner: Color, outer: Color, segments: int, axis: Basis = Basis.IDENTITY) -> void:
		var base := v.size()
		v.append(centre)
		n.append(axis.y)
		uv.append(Vector2.ZERO)
		c.append(inner)
		for k in segments:
			var a := TAU * float(k) / segments
			v.append(centre + axis * (Vector3(cos(a), 0.0, sin(a)) * radius))
			n.append(axis.y)
			uv.append(Vector2.ZERO)
			c.append(outer)
		for k in segments:
			i.append_array([base, base + 1 + (k + 1) % segments, base + 1 + k])

	## Appends the arrays moved by `xf`; vertex colour from `paint(world_pos, world_normal, source_colour)`.
	func add(arrays: Array, xf: Transform3D, paint: Callable) -> void:
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs = arrays[Mesh.ARRAY_TEX_UV]
		var cols = arrays[Mesh.ARRAY_COLOR]
		var indices = arrays[Mesh.ARRAY_INDEX]
		var nb := xf.basis.inverse().transposed()
		var base := v.size()
		for k in verts.size():
			var p := xf * verts[k]
			var nn := (nb * norms[k]).normalized()
			v.append(p)
			n.append(nn)
			uv.append(uvs[k] if uvs != null and (uvs as PackedVector2Array).size() > k else Vector2.ZERO)
			c.append(paint.call(p, nn, cols[k] if cols != null and (cols as PackedColorArray).size() > k else Color.WHITE))
		if indices == null or (indices as PackedInt32Array).is_empty():
			for k in verts.size():
				i.append(base + k)
		else:
			for k in indices:
				i.append(base + k)

	func tris() -> int:
		return i.size() / 3

	func arrays() -> Array:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = n
		a[Mesh.ARRAY_TEX_UV] = uv
		a[Mesh.ARRAY_COLOR] = c
		a[Mesh.ARRAY_INDEX] = i
		return a


static func lin(color: Color) -> Color:
	var out := color.srgb_to_linear()
	out.a = color.a
	return out


static func _hash2(a: int, b: int, s: int = 0) -> float:
	var h := (a * 73856093) ^ (b * 19349663) ^ (s * 83492791) ^ 4271
	h = (h ^ (h >> 13)) * 1274126177
	return float(absi(h) % 1000) / 1000.0


## Sun through the leaves (0..1): soft gold dapples, strongest under the open sky over the board, broken by the canopy.
static func dapple(x: float, z: float) -> float:
	var a := sin(x * 1.3 + sin(z * 0.9) * 1.6) * sin(z * 1.55 - x * 0.35) + sin((x + z) * 0.8) * 0.45
	return clampf(smoothstep(0.15, 0.85, a), 0.0, 1.0)


static func sunlit(color: Color, x: float, z: float, amount: float = 0.35) -> Color:
	return color.lerp(SUN, dapple(x, z) * amount) * (1.0 + dapple(x, z) * amount * 0.4)


## ---- builder state -----------------------------------------------------------------------------------------------

var _dress: Acc
var _kit: Acc
var _glow: Acc
var _rng: RandomNumberGenerator
var _props: Dictionary = {}  ## verdant prop name -> surface arrays
var _lights: Array = []  ## [x, y, z] light_lantern markers


func _load_props() -> bool:
	for name in ["fern", "grass", "flower"]:
		var path: String = PROP_DIR + name + ".glb"
		if not ResourceLoader.exists(path):
			printerr("missing prop ", path)
			return false
		var scene := (load(path) as PackedScene).instantiate()
		var meshes := scene.find_children("*", "MeshInstance3D", true, false)
		if meshes.is_empty():
			scene.free()
			return false
		_props[name] = (meshes[0] as MeshInstance3D).mesh.surface_get_arrays(0)
		scene.free()
	return true


## ---- floor -------------------------------------------------------------------------------------------------------

static func _lines(a0: float, b0: float, b1: float, a1: float) -> Array:
	var out: Array = [a0]
	for end in [b0, b1, a1]:
		var start: float = out[-1]
		var count := maxi(1, int(round((end - start) / 0.5)))
		for k in count:
			out.append(lerpf(start, end, float(k + 1) / count))
	return out


func _floor_colour(x: float, z: float, s: int) -> Color:
	var inside: bool = absf(x) < W and absf(z) < D
	var noise := sin(x * 0.7 + sin(z * 0.5) * 1.7) * 0.5 + sin(z * 1.1 - x * 0.4) * 0.5
	var speck := _hash2(int(floor(x * 2.0)), int(floor(z * 2.0)), s) - 0.5
	if inside:
		var edge: float = minf(W - absf(x), D - absf(z))
		if edge < 0.3:
			return MOSS_DARK.lerp(LOAM_DARK, 0.5)  # the mossy kerb
		var base := LOAM.lerp(LOAM_DARK, 0.4 + noise * 0.3 + speck * 0.2)
		return sunlit(base, x, z, 0.2)
	var out: float = maxf(absf(x) - W, absf(z) - D)
	var base := MOSS.lerp(MOSS_DARK, clampf(0.35 + out * 0.08 + noise * 0.25 + speck * 0.2, 0.0, 1.0))
	return sunlit(base, x, z, 0.22)


func _floor_mesh(id: String, layout: Dictionary) -> ArrayMesh:
	var board := Acc.new()
	var moss := Acc.new()
	var s: int = layout.seed
	var xs := _lines(-ISLAND_W, -W, W, ISLAND_W)
	var zs := _lines(-ISLAND_D, -D, D, ISLAND_D)
	for j in zs.size() - 1:
		for k in xs.size() - 1:
			var x0: float = xs[k]
			var z0: float = zs[j]
			var sx: float = xs[k + 1] - x0
			var sz: float = zs[j + 1] - z0
			var cx := x0 + sx * 0.5
			var cz := z0 + sz * 0.5
			var inside: bool = absf(cx) < W and absf(cz) < D
			var corners := [Vector2(x0, z0), Vector2(x0 + sx, z0), Vector2(x0 + sx, z0 + sz), Vector2(x0, z0 + sz)]
			var p := []
			var cols := []
			for q in corners:
				p.append(Vector3(q.x, BOARD_Y if inside else EDGE_Y, q.y))
				cols.append(lin(_floor_colour(q.x if not inside else clampf(q.x, -W + 0.01, W - 0.01), q.y if not inside else clampf(q.y, -D + 0.01, D - 0.01), s)))
			var uvs := corners.map(func(q): return Vector2(q.x, q.y) / 4.0)
			var acc: Acc = board if inside else moss
			var base := acc.v.size()
			acc.quad(p[0], p[3], p[2], p[1], cols[0], [uvs[0], uvs[3], uvs[2], uvs[1]])
			# per-corner colours: smooth sun dapples
			acc.c[base + 1] = cols[3]
			acc.c[base + 2] = cols[2]
			acc.c[base + 3] = cols[1]
	# The board's step up to the margin (faces into the board): a dark mossy lip.
	var trim := lin(MOSS_DARK.darkened(0.25))
	for f in [[Vector3(W, 0, -D), Vector3(-W, 0, -D)], [Vector3(-W, 0, D), Vector3(W, 0, D)], [Vector3(-W, 0, -D), Vector3(-W, 0, D)], [Vector3(W, 0, D), Vector3(W, 0, -D)]]:
		var a: Vector3 = f[0]
		var b: Vector3 = f[1]
		moss.quad(a + Vector3(0, EDGE_Y, 0), b + Vector3(0, EDGE_Y, 0), b + Vector3(0, BOARD_Y, 0), a + Vector3(0, BOARD_Y, 0), trim,
			[Vector2(0, 0), Vector2(4, 0), Vector2(4, 0.03), Vector2(0, 0.03)])
	var grid_end := board.i.size()
	_inlay(board, layout)
	_face_up(board, grid_end)
	# The island's fascia: root-laced earth bands down to the client's rock underside.
	var bands := [[EDGE_Y, -0.25, Color(0.34, 0.46, 0.24)], [-0.25, -0.45, Color(0.30, 0.22, 0.16)], [-0.45, -1.0, Color(0.38, 0.29, 0.21)]]
	for f in [[Vector3(-ISLAND_W, 0, ISLAND_D), Vector3(ISLAND_W, 0, ISLAND_D)], [Vector3(ISLAND_W, 0, ISLAND_D), Vector3(ISLAND_W, 0, -ISLAND_D)], [Vector3(ISLAND_W, 0, -ISLAND_D), Vector3(-ISLAND_W, 0, -ISLAND_D)], [Vector3(-ISLAND_W, 0, -ISLAND_D), Vector3(-ISLAND_W, 0, ISLAND_D)]]:
		var a: Vector3 = f[0]
		var b: Vector3 = f[1]
		var segments := int(ceil(a.distance_to(b) / 1.0))
		for sg in segments:
			var p0: Vector3 = a.lerp(b, float(sg) / segments)
			var p1: Vector3 = a.lerp(b, float(sg + 1) / segments)
			for band in bands:
				moss.quad(Vector3(p0.x, band[0], p0.z), Vector3(p0.x, band[1], p0.z), Vector3(p1.x, band[1], p1.z), Vector3(p1.x, band[0], p1.z), lin(band[2]),
					[Vector2(sg * 0.25, band[0] * 0.25), Vector2(sg * 0.25, band[1] * 0.25), Vector2((sg + 1) * 0.25, band[1] * 0.25), Vector2((sg + 1) * 0.25, band[0] * 0.25)])
	var mesh := ArrayMesh.new()
	for pair in [[board, DIRT_TEX, "grove_floor"], [moss, GRASS_TEX, "grove_moss"]]:
		var acc: Acc = pair[0]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, acc.arrays())
		var material := StandardMaterial3D.new()
		material.resource_name = pair[2]
		material.albedo_texture = load(pair[1])
		material.vertex_color_use_as_albedo = true
		material.vertex_color_is_srgb = false
		material.roughness = 1.0
		material.metallic_specular = 0.05
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	# The glow (lantern halos, shrine runes, canopy motes) rides on the floor mesh: the floor is toon_no_outline, so the
	# drawn style's ink hull (which wraps a whole mesh) never rings the additive discs dark.
	if not _glow.v.is_empty():
		for k in _glow.v.size():  # (kept inside the island footprint: the floor's bounds are the island's)
			_glow.v[k] = Vector3(clampf(_glow.v[k].x, -ISLAND_W, ISLAND_W), _glow.v[k].y, clampf(_glow.v[k].z, -ISLAND_D, ISLAND_D))
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _glow.arrays())
		mesh.surface_set_material(mesh.get_surface_count() - 1, _glow_material())
	return mesh


## The inlays are drawn with mixed windings: turn every triangle after `from` to the winding of the floor grid's first
## triangle (which faces up and is drawn), so none is back-face culled.
static func _face_up(acc: Acc, from: int) -> void:
	var up_sign := signf(((acc.v[acc.i[1]] - acc.v[acc.i[0]]).cross(acc.v[acc.i[2]] - acc.v[acc.i[0]])).y)
	for t in range(from, acc.i.size(), 3):
		var a := acc.v[acc.i[t]]
		var y := ((acc.v[acc.i[t + 1]] - a).cross(acc.v[acc.i[t + 2]] - a)).y
		if signf(y) != up_sign and absf(y) > 0.0:
			var keep := acc.i[t + 1]
			acc.i[t + 1] = acc.i[t + 2]
			acc.i[t + 2] = keep
	for k in range(0, acc.n.size()):
		if acc.n[k].y < 0.0:
			acc.n[k] = -acc.n[k]


## A flat root ribbon on the board (y under 0.1): a polyline of points, width tapering from w0 to w1.
func _flat_root(acc: Acc, pts: Array, w0: float, w1: float, color: Color, y: float) -> void:
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x)
		var wa := lerpf(w0, w1, float(k) / (pts.size() - 1)) * 0.5
		var wb := lerpf(w0, w1, float(k + 1) / (pts.size() - 1)) * 0.5
		var col := lin(sunlit(color, a.x, a.y, 0.2))
		var hump := y + 0.015
		acc.quad(Vector3(a.x + side.x * wa, y, a.y + side.y * wa), Vector3(a.x, hump, a.y), Vector3(b.x, hump, b.y), Vector3(b.x + side.x * wb, y, b.y + side.y * wb), col,
			[Vector2(0, 0), Vector2(0, 0), Vector2(0, 0), Vector2(0, 0)])
		acc.quad(Vector3(a.x, hump, a.y), Vector3(a.x - side.x * wa, y, a.y - side.y * wa), Vector3(b.x - side.x * wb, y, b.y - side.y * wb), Vector3(b.x, hump, b.y), col.darkened(0.12),
			[Vector2(0, 0), Vector2(0, 0), Vector2(0, 0), Vector2(0, 0)])


## A winding root path from `from` towards `to` (xz) in `steps` steps.
func _wind(from: Vector2, to: Vector2, steps: int, wiggle: float) -> Array:
	var out: Array = []
	var dir := (to - from)
	var side := Vector2(-dir.y, dir.x).normalized()
	var phase := _rng.randf() * TAU
	for k in steps + 1:
		var t := float(k) / steps
		out.append(from.lerp(to, t) + side * sin(t * 5.0 + phase) * wiggle * (1.0 - t * 0.4))
	return out


func _disc(acc: Acc, x: float, z: float, y: float, r: float, color: Color, segments: int, squash: float = 1.0) -> void:
	var col := lin(color)
	var base := acc.v.size()
	acc.fan(Vector3(x, y, z), r, col, col.darkened(0.08), segments, Basis.from_scale(Vector3(1.0, 1.0, squash)))
	for k in range(base, acc.v.size()):
		acc.uv[k] = Vector2(acc.v[k].x, acc.v[k].z) / 4.0  # (world uvs on the painted dirt, like the floor grid)


func _inlay(acc: Acc, layout: Dictionary) -> void:
	var y := BOARD_Y + 0.02
	var elder: Array = layout.elder
	match str(layout.inlay):
		"root_ring":
			# Roots from the elder tree run south over the board into a ring round a moss heart.
			for k in 5:
				var x0 := -1.6 + k * 0.8
				var end := Vector2(cos(-PI * 0.5 + (k - 2) * 0.5), sin(-PI * 0.5 + (k - 2) * 0.5)) * 3.3
				_flat_root(acc, _wind(Vector2(x0, -D + 0.05), end, 8, 0.25), 0.34, 0.16, ROOT, y)
			for k in 12:
				var a0 := TAU * float(k) / 12.0
				var a1 := TAU * float(k + 1) / 12.0 + 0.08
				var pts: Array = []
				for t in 4:
					var a := lerpf(a0, a1, t / 3.0)
					pts.append(Vector2(cos(a), sin(a)) * (3.3 + sin(a * 5.0) * 0.08))
				_flat_root(acc, pts, 0.3, 0.26, ROOT.lightened(0.05), y + 0.004)
			_disc(acc, 0.0, 0.0, y, 1.0, FLAG_MOSS, 22)
			_disc(acc, 0.0, 0.0, y + 0.004, 0.55, Color(0.95, 1.0, 0.55), 18)
		"flag_path":
			# Mossy flagstones from the gate (north) south across the board, then splitting east and west.
			var z := -D + 0.35
			var k := 0
			while z < D - 0.3:
				var x := sin(z * 0.6) * 0.35 + (_rng.randf() - 0.5) * 0.3
				_disc(acc, x - 0.38, z, y, 0.42 + _rng.randf() * 0.1, FLAG.lerp(FLAG_MOSS, 0.15 + _rng.randf() * 0.3), 7, 0.8)
				_disc(acc, x + 0.42, z + 0.25, y, 0.38 + _rng.randf() * 0.1, FLAG.lerp(FLAG_MOSS, 0.1 + _rng.randf() * 0.3), 7, 0.85)
				z += 0.95
				k += 1
			for k2 in 2:
				var px := _wind(Vector2(-0.6, -D + 0.1), Vector2(-6.5, -1.2), 6, 0.2) if k2 == 0 else _wind(Vector2(0.6, -D + 0.1), Vector2(6.5, -1.6), 6, 0.2)
				_flat_root(acc, px, 0.3, 0.12, ROOT, y)
		"stepping":
			for k in 14:
				var a := TAU * (float(k) + 0.5) / 14.0
				var at := Vector2(cos(a) * 3.4, sin(a) * 2.9)
				_disc(acc, at.x, at.y, y, 0.36, FLAG.lerp(FLAG_MOSS, 0.25), 8)
			_disc(acc, 0.0, 0.0, y, 0.85, FLAG.lerp(FLAG_MOSS, 0.15), 16)
			_disc(acc, 0.0, 0.0, y + 0.004, 0.5, FLAG_MOSS, 14)
			for k in 4:
				var from := Vector2(-3.5 + k * 2.3, -D + 0.05)
				_flat_root(acc, _wind(from, from + Vector2(_rng.randf_range(-1.5, 1.5), 3.0 + _rng.randf() * 1.5), 7, 0.3), 0.28, 0.1, ROOT, y)


## ---- dressing ----------------------------------------------------------------------------------------------------

func _shade(color: Color) -> Callable:
	return func(p: Vector3, nn: Vector3, _c: Color) -> Color:
		var top := clampf(nn.y, 0.0, 1.0)
		return lin(sunlit(color, p.x, p.z, 0.18 + top * 0.2) * (0.88 + top * 0.14))


func _prim(acc: Acc, m: PrimitiveMesh, at: Vector3, color: Color, basis: Basis = Basis.IDENTITY) -> void:
	acc.add(m.surface_get_arrays(0), Transform3D(basis, at), _shade(color))


func _cyl(acc: Acc, at: Vector3, r_bottom: float, r_top: float, h: float, segments: int, color: Color, basis: Basis = Basis.IDENTITY, caps: bool = false) -> void:
	var m := CylinderMesh.new()
	m.bottom_radius = r_bottom
	m.top_radius = r_top
	m.height = h
	m.radial_segments = segments
	m.rings = 1
	m.cap_top = caps
	m.cap_bottom = false
	_prim(acc, m, at, color, basis)


func _blob(acc: Acc, at: Vector3, r: float, scale: Vector3, color: Color, segments: int = 8, rings: int = 4) -> void:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = segments
	m.rings = rings
	_prim(acc, m, at, color, Basis.from_scale(scale))


func _box(acc: Acc, x: float, y0: float, z: float, sx: float, sy: float, sz: float, color: Color, yaw_deg: float = 0.0) -> void:
	var m := BoxMesh.new()
	m.size = Vector3(sx, sy, sz)
	_prim(acc, m, Vector3(x, y0 + sy * 0.5, z), color, Basis(Vector3.UP, deg_to_rad(yaw_deg)))


## A cylinder from a to b (a log, a branch, a root).
func _limb(acc: Acc, a: Vector3, b: Vector3, r0: float, r1: float, segments: int, color: Color) -> void:
	var dir := b - a
	var up := dir.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var basis := Basis(side, up, side.cross(up).normalized())  # right-handed: keeps the cylinder's winding
	_cyl(acc, (a + b) * 0.5, r0, r1, dir.length(), segments, color, basis)


func _verdant(name: String, x: float, z: float, yaw: float, scale: float, tint: Color) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), Vector3(x, EDGE_Y - 0.02, z))
	_dress.add(_props[name], xf, func(p: Vector3, _nn: Vector3, c: Color) -> Color: return lin(sunlit(c.linear_to_srgb() * tint, p.x, p.z, 0.2)))


## One rotting-wood stump of the wall, moss on its jagged top.
func _stump(x: float, z: float, h: float, r: float) -> void:
	var tone := ROTWOOD.lerp(BARK_DARK, _rng.randf() * 0.7)
	_cyl(_dress, Vector3(x, EDGE_Y - 0.3 + (h + 0.3) * 0.5, z), r * 1.15, r, h + 0.3, 6, tone)
	_cyl(_dress, Vector3(x, EDGE_Y + h + 0.12, z), r, r * 0.35, 0.24, 6, tone.darkened(0.15))
	if _rng.randf() < 0.6:
		_blob(_dress, Vector3(x, EDGE_Y + h + 0.06, z), r * 1.2, Vector3(1.0, 0.5, 1.0), MOSS_CAP.lerp(LEAF, _rng.randf() * 0.5), 6, 2)


## A root wall run from a to b (xz): stumps, two gnarled lying roots on the inner face, hanging vines, moss clumps.
var _gap := Vector2(INF, INF)  ## the vine arch's foot centre: the root wall leaves a gap there


func _in_gap(p: Vector2, pad: float = 0.0) -> bool:
	return p.distance_to(_gap) < 1.35 + pad


func _root_wall(a: Vector2, b: Vector2, h: float, inner: Vector2) -> void:
	var length := a.distance_to(b)
	var count := int(round(length / 0.66))
	for k in count + 1:
		var p := a.lerp(b, float(k) / count)
		if _in_gap(p):
			continue
		var hk := h * (0.6 + _rng.randf() * 0.55)
		_stump(p.x, p.y, hk, 0.3 + _rng.randf() * 0.1)
	var along := (b - a).normalized()
	for row in [[0.45, 0.3, 0.32], [1.15, 0.42, 0.24]]:
		var pieces := int(ceil(length / 3.2))
		for k in pieces:
			var p0 := a.lerp(b, float(k) / pieces) + inner * float(row[1])
			var p1 := a.lerp(b, float(k + 1) / pieces) + inner * float(row[1]) + along * 0.3
			if _in_gap(p0, 0.6) or _in_gap(p1, 0.6) or _in_gap((p0 + p1) * 0.5, 0.6):
				continue
			var y0: float = EDGE_Y + float(row[0]) + _rng.randf() * 0.2
			var mid := (p0 + p1) * 0.5 + inner * 0.12
			_limb(_dress, Vector3(p0.x, y0, p0.y), Vector3(mid.x, y0 + 0.15, mid.y), float(row[2]), float(row[2]) * 0.85, 6, ROOT.lerp(BARK, _rng.randf()))
			_limb(_dress, Vector3(mid.x, y0 + 0.15, mid.y), Vector3(p1.x, y0 - 0.05, p1.y), float(row[2]) * 0.85, float(row[2]) * 0.75, 6, ROOT.lerp(BARK, _rng.randf()))
	# vines hanging off the top, on the inner face
	var vines := int(length / 1.1)
	for k in vines:
		var p := a.lerp(b, (float(k) + 0.5) / vines) + inner * 0.38
		if _in_gap(p - inner * 0.38):
			continue
		var top := EDGE_Y + h * (0.8 + _rng.randf() * 0.3)
		var hang := 0.6 + _rng.randf() * 1.0
		_box(_dress, p.x, top - hang, p.y, 0.06 if absf(along.x) < 0.5 else 0.09, hang, 0.09 if absf(along.x) < 0.5 else 0.06, VINE.lerp(LEAF_DARK, _rng.randf()))
		_blob(_dress, Vector3(p.x, top - hang, p.y), 0.13, Vector3.ONE, LEAF, 5, 2)


## Low clutter on a margin spot (ferns, grass, flowers, rocks): stays under 1.3 m.
func _clutter(x: float, z: float, kind: String) -> void:
	match kind:
		"fern":
			_verdant("fern", x, z, _rng.randf() * TAU, 0.7 + _rng.randf() * 0.4, Color(0.85, 1.0, 0.8))
		"grass":
			_verdant("grass", x, z, _rng.randf() * TAU, 0.8 + _rng.randf() * 0.5, Color(0.9, 1.0, 0.85))
		"flower":
			_verdant("flower", x, z, _rng.randf() * TAU, 0.8 + _rng.randf() * 0.4, Color.WHITE)
		"rock":
			var rr := 0.16 + _rng.randf() * 0.14
			_blob(_dress, Vector3(x, EDGE_Y + rr * 0.3, z), rr, Vector3(1.3, 0.7, 1.0), STONE.lerp(STONE_DARK, _rng.randf()), 6, 3)
			_blob(_dress, Vector3(x, EDGE_Y + rr * 0.65, z), rr * 0.85, Vector3(1.3, 0.3, 1.0), MOSS_CAP, 6, 2)
		"mushroom":
			var h := 0.18 + _rng.randf() * 0.22
			_cyl(_dress, Vector3(x, EDGE_Y + h * 0.5, z), 0.05, 0.04, h, 5, CAP_CREAM)
			_blob(_dress, Vector3(x, EDGE_Y + h, z), 0.14 + h * 0.3, Vector3(1.0, 0.55, 1.0), CAP_RED if _rng.randf() < 0.6 else Color(0.86, 0.62, 0.30), 6, 2)


func _dressing(id: String, layout: Dictionary) -> void:
	var arch: Array = layout.arch
	_gap = Vector2(INF, INF) if arch.is_empty() else Vector2(float(arch[0]), float(arch[1]))
	_root_wall(Vector2(-WALL_X - 0.3, WALL_N), Vector2(WALL_X + 0.3, WALL_N), 2.6, Vector2(0, 1))
	for side in [-1.0, 1.0]:
		_root_wall(Vector2(side * WALL_X, WALL_N + 0.6), Vector2(side * WALL_X, WALL_END), 2.2, Vector2(-side, 0))
		# The wall's end at the open front: a big hollow stump with a moss crown (x beyond the board: allowed tall).
		_cyl(_dress, Vector3(side * WALL_X, EDGE_Y + 1.0, WALL_END + 0.6), 0.62, 0.5, 2.2, 9, BARK)
		_blob(_dress, Vector3(side * WALL_X, EDGE_Y + 2.1, WALL_END + 0.6), 0.62, Vector3(1.0, 0.5, 1.0), MOSS_CAP, 9, 4)
	# Hanging roots under the island's front and side lips (below the floor: never block the view).
	for k in 30:
		var t := float(k) / 29.0
		var x := lerpf(-ISLAND_W + 0.3, ISLAND_W - 0.3, t)
		var hang := 0.6 + _rng.randf() * 1.4
		_limb(_dress, Vector3(x, -0.3, ISLAND_D + 0.02), Vector3(x + _rng.randf_range(-0.3, 0.3), -0.3 - hang, ISLAND_D + 0.12), 0.06, 0.015, 4, ROOT)
	# Front margin: only low things (the camera side): ferns, mushrooms, grass, rocks, flowers.
	var front_kinds := ["fern", "fern", "grass", "grass", "mushroom", "flower", "rock", "grass"]
	for k in 34:
		var x := _rng.randf_range(-ISLAND_W + 0.4, ISLAND_W - 0.4)
		var z := _rng.randf_range(D + 0.85, ISLAND_D - 0.3)
		_clutter(x, z, front_kinds[k % front_kinds.size()])
	# Side and back margins: denser ferns and grass between the wall and the board.
	for k in 40:
		var side := -1.0 if k % 2 == 0 else 1.0
		var x: float
		var z: float
		if k % 3 == 0:
			x = _rng.randf_range(-ISLAND_W + 1.0, ISLAND_W - 1.0)
			z = _rng.randf_range(WALL_N + 0.8, -D - 0.85)
		else:
			x = side * _rng.randf_range(W + 0.8, WALL_X - 0.7)
			z = _rng.randf_range(-D, D + 1.5)
		_clutter(x, z, ["fern", "grass", "fern", "flower", "mushroom", "grass", "rock"][k % 7])
	# Mossy boulders on the side margins.
	for k in 6:
		var side := -1.0 if k % 2 == 0 else 1.0
		var at := Vector3(side * _rng.randf_range(W + 0.8, W + 2.2), EDGE_Y + 0.05, _rng.randf_range(-3.5, 4.5))
		var r := 0.35 + _rng.randf() * 0.25
		_blob(_dress, at, r, Vector3(1.2, 0.8, 1.0), STONE.lerp(STONE_DARK, _rng.randf()), 8, 4)
		_blob(_dress, at + Vector3(0, r * 0.55, 0), r * 0.9, Vector3(1.2, 0.35, 1.0), MOSS_CAP, 8, 3)


## ---- kit: trees, arch, shrine ------------------------------------------------------------------------------------

func _leaf_paint(base: Color) -> Callable:
	return func(p: Vector3, nn: Vector3, _c: Color) -> Color:
		var top := clampf(nn.y * 0.5 + 0.5, 0.0, 1.0)
		var col := LEAF_DARK.lerp(base, top).lerp(LEAF_GOLD, pow(top, 3.0) * 0.55)
		return lin(col)


func _canopy(at: Vector3, r: float, scale: Vector3, base: Color = LEAF) -> void:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 12
	m.rings = 6
	_kit.add(m.surface_get_arrays(0), Transform3D(Basis.from_scale(scale), at), _leaf_paint(base))


## The giant elder tree: a flared trunk, buttress roots over the margin, big limbs into layered canopy clouds.
## Its canopy stays north of the board's back edge (nothing over the board), extending out over the island's edge.
func _elder(x: float, z: float, s: float) -> void:
	var base := Vector3(x, EDGE_Y - 0.1, z)
	var trunk_h := 3.3 * s
	var segs := 5
	for k in segs:
		var t0 := float(k) / segs
		var t1 := float(k + 1) / segs
		var r0 := lerpf(1.25, 0.72, pow(t0, 0.6)) * s
		var r1 := lerpf(1.25, 0.72, pow(t1, 0.6)) * s
		var lean := Vector3(sin(t0 * 2.0) * 0.15, 0, -t0 * 0.25) * s
		var lean1 := Vector3(sin(t1 * 2.0) * 0.15, 0, -t1 * 0.25) * s
		_limb(_kit, base + lean + Vector3(0, trunk_h * t0, 0), base + lean1 + Vector3(0, trunk_h * t1, 0), r0, r1, 12, BARK.lerp(BARK_DARK, t0 * 0.4))
	# bark ridges (dark vertical strips) and a hollow at the foot
	for k in 7:
		var a := TAU * float(k) / 7.0 + 0.3
		var off := Vector3(cos(a), 0, sin(a)) * 1.05 * s
		_limb(_kit, base + off + Vector3(0, 0.1, 0), base + off * 0.72 + Vector3(0, trunk_h * 0.75, -0.15 * s), 0.16 * s, 0.07 * s, 5, BARK_DARK)
	_blob(_kit, base + Vector3(0, 0.6 * s, 1.0 * s), 0.45 * s, Vector3(1.0, 1.4, 0.4), Color(0.14, 0.10, 0.08), 8, 4)
	# buttress roots arching out over the margin (they stay north of the board's back edge)
	for k in 8:
		var a := PI * 0.5 + (float(k) - 3.5) * 0.42 + PI
		var dir := Vector3(cos(a), 0, -sin(a))
		if dir.z > 0.0:
			dir.z *= 0.35  # (roots towards the board stay short)
		var reach := (1.9 + _rng.randf() * 0.9) * s
		var p0 := base + dir * 0.7 * s + Vector3(0, 0.9 * s, 0)
		var p1 := base + dir * (reach * 0.6) + Vector3(0, 0.45 * s, 0)
		var p2 := base + dir * reach + Vector3(0, 0.0, 0)
		if (p2.z > -D - 0.25) and absf(p2.x) < W:
			p2.z = -D - 0.3
			p1.z = minf(p1.z, -D - 0.35)
		_limb(_kit, p0, p1, 0.32 * s, 0.22 * s, 7, ROOT.lerp(BARK, 0.4))
		_limb(_kit, p1, p2, 0.22 * s, 0.07 * s, 6, ROOT.lerp(BARK, 0.4))
		if k % 2 == 0:
			_blob(_kit, p1 + Vector3(0, 0.15 * s, 0), 0.28 * s, Vector3(1.3, 0.45, 1.0), MOSS_CAP, 8, 3)
	# limbs and canopy clouds
	var top := base + Vector3(0.15 * s, trunk_h, -0.25 * s)
	var limbs := [[-2.6, 1.0, -0.4], [2.7, 0.9, -0.5], [-1.2, 1.6, -1.2], [1.3, 1.7, -1.1], [0.0, 1.3, -2.0], [-3.6, 0.4, -1.4], [3.6, 0.5, -1.5]]
	for l in limbs:
		var tip: Vector3 = top + Vector3(l[0], l[1], l[2]) * s
		_limb(_kit, top - Vector3(0, 0.8 * s, 0), tip, 0.42 * s, 0.16 * s, 7, BARK)
		var c := tip + Vector3(0, 0.5 * s, 0)
		c.z = minf(c.z, -D - 1.9)  # (the crown never overhangs the board)
		_canopy(c, 1.5 * s, Vector3(1.35, 0.62, 1.0), LEAF.lerp(LEAF_GOLD, _rng.randf() * 0.3))
	_canopy(top + Vector3(0, 2.0 * s, -1.3 * s), 2.0 * s, Vector3(1.5, 0.62, 1.0), LEAF.lerp(LEAF_GOLD, 0.25))
	# glowing motes hanging under the canopy (fake light: unshaded discs)
	for k in 8:
		var p := top + Vector3(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-0.5, 0.8), _rng.randf_range(-2.5, -1.0)) * s
		_glow.fan(p, 0.18, lin(Color(1.0, 0.92, 0.55, 0.85)), lin(Color(1.0, 0.85, 0.4, 0.0)), 8, Basis(Vector3.RIGHT, PI * 0.5))


## A smaller grove tree (corner / side): trunk + 3-4 canopy clouds.
func _tree(x: float, z: float, s: float) -> void:
	var base := Vector3(x, EDGE_Y - 0.1, z)
	var h := 3.6 * s
	_limb(_kit, base, base + Vector3(0.1, h, -0.15) * Vector3(s, 1, s), 0.42 * s, 0.26 * s, 9, BARK)
	for k in 4:
		var a := TAU * float(k) / 4.0 + _rng.randf()
		var dir := Vector3(cos(a), 0, sin(a))
		_limb(_kit, base + dir * 0.2 * s + Vector3(0, 0.35 * s, 0), base + dir * 0.9 * s, 0.18 * s, 0.05 * s, 5, ROOT)
	var top := base + Vector3(0.1 * s, h, -0.15 * s)
	for c in [[0, 1.0, 0, 1.5], [-1.1, 0.4, 0.2, 1.1], [1.1, 0.5, -0.2, 1.1], [0.2, 0.3, -0.9, 1.1]]:
		_canopy(top + Vector3(c[0], c[1], c[2]) * s, float(c[3]) * s, Vector3(1.2, 0.8, 1.1), LEAF.lerp(LEAF_DARK, _rng.randf() * 0.4))


## The vine arch gate: two mossy stone-and-wood posts and an arch of twisted vines with leaf clusters hanging.
func _arch(x: float, z: float, yaw_deg: float) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var o := Vector3(x, EDGE_Y, z)
	var half := 1.6
	var rise := 3.1
	for side in [-1.0, 1.0]:
		var foot := o + b * Vector3(side * half, 0, 0)
		_box(_kit, foot.x, EDGE_Y - 0.1, foot.z, 0.75, 0.5, 0.75, STONE_DARK, yaw_deg)
		_cyl(_kit, foot + Vector3(0, 0.55, 0), 0.42, 0.42, 0.25, 8, STONE.lerp(MOSS_CAP, 0.3))
	# two twisted vine strands along the arch
	for strand in 2:
		var prev := Vector3.ZERO
		var steps := 12
		for k in steps + 1:
			var t := float(k) / steps
			var a := PI * t
			var twist := sin(t * TAU * 2.0 + strand * PI) * 0.12
			var local := Vector3(-cos(a) * half, 0.5 + sin(a) * (rise - 0.5), twist)
			var p := o + b * local
			if k > 0:
				_limb(_kit, prev, p, 0.16, 0.16, 6, VINE.lerp(ROOT, 0.45 + strand * 0.25))
			prev = p
	# leaf clusters and hanging tendrils along the arch
	for k in 9:
		var t := (float(k) + 0.5) / 9.0
		var a := PI * t
		var p := o + b * Vector3(-cos(a) * half, 0.5 + sin(a) * (rise - 0.5) + 0.1, 0)
		_canopy(p, 0.34 + _rng.randf() * 0.12, Vector3(1.2, 0.8, 1.0), LEAF.lerp(LEAF_GOLD, _rng.randf() * 0.35))
		if k % 2 == 1:
			var hang := 0.5 + _rng.randf() * 0.6
			_box(_kit, p.x, p.y - hang, p.z, 0.05, hang, 0.05, VINE, yaw_deg)
		if k == 4:
			_glow.fan(p + b * Vector3(0, -0.45, 0.2), 0.35, lin(Color(0.75, 1.0, 0.6, 0.6)), lin(Color(0.6, 1.0, 0.5, 0.0)), 10, b * Basis(Vector3.RIGHT, PI * 0.5))


## The mossy stone shrine: a stepped dais, a mossy stone idol with a green rune, two stone lanterns (real warm lights).
func _shrine(x: float, z: float, yaw_deg: float, s: float) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var o := Vector3(x, EDGE_Y, z)
	var at := func(lx: float, lz: float) -> Vector3: return o + b * (Vector3(lx, 0, lz) * s)
	var p0: Vector3 = at.call(0.0, 0.0)
	_box(_kit, p0.x, EDGE_Y - 0.08, p0.z, 2.6 * s, 0.26, 1.7 * s, STONE_DARK, yaw_deg)
	_box(_kit, p0.x, EDGE_Y + 0.18, p0.z, 2.0 * s, 0.22, 1.25 * s, STONE, yaw_deg)
	_blob(_kit, p0 + Vector3(0, 0.42, 0), 0.9 * s, Vector3(1.1, 0.18, 0.7), MOSS_CAP, 10, 3)
	# the idol: stacked weathered stones, a moss crown
	var idol: Vector3 = at.call(0.0, -0.25)
	_box(_kit, idol.x, EDGE_Y + 0.4, idol.z, 0.7 * s, 0.9 * s, 0.5 * s, STONE, yaw_deg)
	_box(_kit, idol.x, EDGE_Y + 0.4 + 0.9 * s, idol.z, 0.55 * s, 0.55 * s, 0.42 * s, STONE.lightened(0.06), yaw_deg)
	_blob(_kit, idol + Vector3(0, 0.4 + 1.48 * s, 0), 0.4 * s, Vector3(1.1, 0.5, 0.9), MOSS_CAP, 8, 4)
	var face := idol + b * Vector3(0, 0.4 + 0.95 * s, 0.26 * s)
	_glow.fan(face, 0.16 * s, lin(Color(0.7, 1.0, 0.75, 0.95)), lin(Color(0.5, 1.0, 0.6, 0.0)), 8, b * Basis(Vector3.RIGHT, PI * 0.5))
	_glow.fan(face + b * Vector3(0, -0.4 * s, 0), 0.12 * s, lin(Color(0.7, 1.0, 0.75, 0.85)), lin(Color(0.5, 1.0, 0.6, 0.0)), 8, b * Basis(Vector3.RIGHT, PI * 0.5))
	# standing stones round the back
	for k in 4:
		var a := PI * (0.15 + 0.7 * float(k) / 3.0)
		var sp: Vector3 = at.call(cos(a) * 1.55, -sin(a) * 1.0 - 0.2)
		var h := (0.9 + _rng.randf() * 0.5) * s
		_box(_kit, sp.x, EDGE_Y - 0.05, sp.z, 0.32 * s, h, 0.26 * s, STONE.lerp(STONE_DARK, _rng.randf()), yaw_deg + _rng.randf_range(-10, 10))
		_blob(_kit, sp + Vector3(0, h - 0.05, 0), 0.2 * s, Vector3(1.0, 0.4, 0.8), MOSS_CAP, 6, 3)
	# two stone lanterns in front, lit
	for side in [-1.0, 1.0]:
		var lp: Vector3 = at.call(side * 1.25, 0.95)
		_cyl(_kit, lp + Vector3(0, 0.35, 0), 0.12, 0.1, 0.7, 6, STONE)
		_box(_kit, lp.x, EDGE_Y + 0.68, lp.z, 0.34, 0.26, 0.34, STONE.lightened(0.05), yaw_deg)
		_cyl(_kit, lp + Vector3(0, 1.02, 0), 0.3, 0.02, 0.22, 6, STONE_DARK, Basis.IDENTITY, true)
		_glow.fan(lp + Vector3(0, 0.82, 0), 0.5, lin(Color(1.0, 0.85, 0.45, 0.6)), lin(Color(1.0, 0.75, 0.3, 0.0)), 12)
		_glow.fan(lp + Vector3(0, 0.82, 0), 0.14, lin(Color(1.0, 0.95, 0.7, 1.0)), lin(Color(1.0, 0.9, 0.6, 0.6)), 8, Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.FORWARD, 0.0))
		_lights.append(lp + Vector3(0, 1.2, 0))


## Glow caps: small bright teal mushrooms on the side margins.
func _glow_caps() -> void:
	for k in 10:
		var side := -1.0 if k % 2 == 0 else 1.0
		var at := Vector3(side * _rng.randf_range(W + 0.5, W + 2.4), EDGE_Y, _rng.randf_range(-D, D))
		_cyl(_kit, at + Vector3(0, 0.1, 0), 0.03, 0.025, 0.2, 4, CAP_CREAM)
		_blob(_kit, at + Vector3(0, 0.22, 0), 0.12, Vector3(1.0, 0.55, 1.0), Color(0.45, 0.92, 0.80), 6, 2)  # (no halo disc: the ink hull would ring it dark)


func _kit_and_glow(layout: Dictionary) -> void:
	var e: Array = layout.elder
	_elder(float(e[0]), float(e[1]), float(e[2]))
	for t in layout.trees:
		_tree(float(t[0]), float(t[1]), float(t[2]))
	if not (layout.arch as Array).is_empty():
		_arch(float(layout.arch[0]), float(layout.arch[1]), float(layout.arch[2]))
	var sh: Array = layout.shrine
	_shrine(float(sh[0]), float(sh[1]), float(sh[2]), float(sh[3]))
	_glow_caps()


func _kit_mesh() -> ArrayMesh:
	var out := ArrayMesh.new()
	var kit_material := StandardMaterial3D.new()
	kit_material.resource_name = "grove_kit"
	kit_material.vertex_color_use_as_albedo = true
	kit_material.vertex_color_is_srgb = false
	kit_material.roughness = 1.0
	kit_material.metallic_specular = 0.08
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _kit.arrays())
	out.surface_set_material(0, kit_material)
	return out


static func _glow_material() -> StandardMaterial3D:
	var glow_material := StandardMaterial3D.new()
	glow_material.resource_name = "grove_glow"  # *_glow: unshaded, additive, never inked
	glow_material.vertex_color_use_as_albedo = true
	glow_material.vertex_color_is_srgb = false
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return glow_material


## ---- scene + map -------------------------------------------------------------------------------------------------

func _save_mesh(mesh: Mesh, path: String) -> Mesh:
	if ResourceSaver.save(mesh, path, ResourceSaver.FLAG_COMPRESS) != OK:
		printerr("cannot save ", path)
		return null
	return load(path)


func _instance(root: Node3D, node_name: String, mesh: Mesh) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	root.add_child(node)
	node.owner = root
	return node


func _marker(root: Node3D, node_name: String, at: Vector3) -> void:
	var marker := Node3D.new()
	marker.name = node_name
	marker.position = at
	root.add_child(marker)
	marker.owner = root


## Mote emitters (client/arena_props.gd add_grove_island): over the margins and under the canopies, never in front.
func _motes(layout: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	var e: Array = layout.elder
	out.append(Vector3(float(e[0]), 3.5, float(e[1]) + 1.2))
	for t in layout.trees:
		out.append(Vector3(float(t[0]), 2.2, float(t[1]) + 0.8))
	out.append(Vector3(-W - 1.5, 1.0, 0.0))
	out.append(Vector3(W + 1.5, 1.0, 0.0))
	return out


func _map_json(id: String, layout: Dictionary) -> Dictionary:
	var spawns: Array = []
	for s in SPOTS:
		spawns.append({"type": FIXTURE[s[0]], "level": 1, "position": [s[1], 0.05, s[2]]})
	return {
		"version": 1, "id": id, "name": layout.name,
		"_design": "Elder Grove zone (level-designer 2026-11-24; zone elder_tree, order 4). Generated by tools/maps/build_elder_grove.gd (edit the script, not this file): the goblin courtyard board (same bounds, spawns, no cover) on a floating island deep in an ancient giant-tree forest: mossy loam board, cushion-moss margins, walls of rotting stumps and gnarled roots north/east/west, an open cliff in front with ferns and mushrooms only, soft green-gold sunlight baked as dapples through the leaves. " + str(layout.design) + " Monster ids here are a PLACEHOLDER fixture (family-neutral old monsters: the elder family does not exist yet); the zone's journey will bring the real waves onto the spots in list order.",
		"modes": ["pve"], "kind": "fight", "camera_style": "arena", "atmosphere": "ink",
		"art_scene": SCENE_DIR + id + ".tscn", "art_mood": "",
		"bounds": {"half_width": W, "half_depth": D},
		"spawn": [-5.6, 0.05, 0.0],
		"solids": [{"center": [0, -0.2, 0], "size": [16.0, 0.4, 9.0], "material": "ink"}],
		"enemy_spawns": spawns,
		"rest_points": [],
		"player_spawns": [[-5.6, 0.05, 0.0], [-4.6, 0.05, -2.2], [-4.6, 0.05, 2.2]],
		"_arena": "Board 16 x 9 m, the goblin courtyard's (same spawns, no cover: logic/auto_pilot.gd walks straight at its target). Nothing stands on the board (roots and stones on it are flat inlays under 0.1 m); trees, walls and the shrine are on the island margins, the front (camera side) is an open cliff.",
		"_spots": "Spot roles in order: " + ", ".join(SPOTS.map(func(s): return str(s[0]))),
		"world_region": "elder_tree",
	}


func _build(id: String, layout: Dictionary) -> Dictionary:
	_rng = RandomNumberGenerator.new()
	_rng.seed = int(layout.seed)
	_dress = Acc.new()
	_kit = Acc.new()
	_glow = Acc.new()
	_lights = []
	_dressing(id, layout)
	_kit_and_glow(layout)
	var floor_mesh := _save_mesh(_floor_mesh(id, layout), MESH_DIR + id + "_floor.res")
	var dress_mesh := ArrayMesh.new()
	dress_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _dress.arrays())
	var dress_material := StandardMaterial3D.new()
	dress_material.resource_name = "grove_dressing"
	dress_material.vertex_color_use_as_albedo = true
	dress_material.vertex_color_is_srgb = false
	dress_material.roughness = 1.0
	dress_material.metallic_specular = 0.08
	dress_mesh.surface_set_material(0, dress_material)
	dress_mesh = _save_mesh(dress_mesh, MESH_DIR + id + "_dressing.res")
	var kit_mesh := _save_mesh(_kit_mesh(), MESH_DIR + id + "_kit.res")
	if floor_mesh == null or dress_mesh == null or kit_mesh == null:
		return {}
	var map := _map_json(id, layout)
	var root_node := Node3D.new()
	root_node.name = id
	root_node.set_meta("floating_island", true)  # client/arena_props.gd is_pyramid_island: the scene is the island top
	root_node.set_meta("elder_grove", true)  # client/arena_props.gd is_grove_island: leaf light, mossy underside, motes
	root_node.set_meta("motes", _motes(layout))
	var ground := _instance(root_node, "PyramidFloor", floor_mesh)  # (the island-floor node name the client and tests share)
	ground.set_meta("toon_no_outline", true)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_instance(root_node, "Dressing", dress_mesh)
	_instance(root_node, "Kit", kit_mesh)
	for k in _lights.size():
		_marker(root_node, "light_lantern%d" % k, _lights[k])
	_marker(root_node, "spawn", Vector3(-5.6, 0.05, 0.0))
	for k in map.enemy_spawns.size():
		var p: Array = map.enemy_spawns[k].position
		_marker(root_node, "enemy_%d" % k, Vector3(p[0], p[1], p[2]))
	var packed := PackedScene.new()
	packed.pack(root_node)
	var scene_path: String = SCENE_DIR + id + ".tscn"
	if ResourceSaver.save(packed, scene_path) != OK:
		printerr("cannot save ", scene_path)
		return {}
	root_node.free()
	var f := FileAccess.open(MAP_DIR + id + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(map, "\t", false))
	f.close()
	var per_mesh := {}
	var tris := 0
	var surfaces := 0
	for pair in [["floor", floor_mesh], ["dressing", dress_mesh], ["kit", kit_mesh]]:
		var t := 0
		for s in pair[1].get_surface_count():
			t += pair[1].surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
			surfaces += 1
		per_mesh[pair[0]] = t
		tris += t
	var bytes := 0
	for suffix in ["_floor.res", "_dressing.res", "_kit.res"]:
		bytes += FileAccess.get_file_as_bytes(MESH_DIR + id + suffix).size()
	return {"triangles": tris, "triangles_by_mesh": per_mesh, "draw_surfaces": surfaces, "mesh_bytes": bytes,
		"scene_bytes": FileAccess.get_file_as_bytes(scene_path).size(), "lights": _lights.size(), "cover": 0}


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if not _load_props():
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MESH_DIR))
	var only := OS.get_cmdline_user_args()
	var all := layouts()
	var manifest_path := SCENE_DIR + "manifest.json"
	var manifest: Dictionary = {}
	if FileAccess.file_exists(manifest_path):
		var old = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if old is Dictionary:
			manifest = old
	for id in all:
		if not only.is_empty() and not only.has(id):
			continue
		var row := _build(id, all[id])
		if row.is_empty():
			quit(1)
			return
		manifest[id] = row
		print("built ", id, " ", row)
	for old_id in manifest.keys():
		if not all.has(old_id):
			manifest.erase(old_id)
	var m := FileAccess.open(manifest_path, FileAccess.WRITE)
	m.store_string(JSON.stringify(manifest, "  "))
	m.close()
	print("ELDER GROVE BUILT")
	quit()
