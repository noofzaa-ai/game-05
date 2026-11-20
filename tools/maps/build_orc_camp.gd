extends SceneTree
## Builds the Orc Camp night board (level-designer 2026-11-20): data/maps/orc_camp_night.json +
## art/maps/orc_camp/orc_camp_night.tscn + art/maps/orc_camp/meshes/orc_camp_night_{floor,dressing,kit}.res.
##   godot --path . --script res://tools/maps/build_orc_camp.gd        (needs a window: the kit's LOD index lists
##                                                                     are read from the rendering server)
## The board is the goblin courtyard board (16 x 9 m, camera_style arena, squad of 3 on the left, 8 monster spots on the
## right, no cover) on a floating island made like the mummy boards (tools/maps/build_mummy_pyramid.gd): the scene is the
## whole island top in three merged meshes, marked meta floating_island (client/arena_props.gd is_pyramid_island) and
## meta night_camp (client/arena_props.gd is_orc_island: the night sky, the dark rock underside, the drifting embers).
##   Floor     board + margin + earth fascia, one surface: goblin painted dirt tinted night blue by vertex colour, the
##             torches' warm pools baked into the vertex colours (fake light, free), a stone ring and an ash pit inlaid;
##   Dressing  log palisade north/east/west, the throne dais, torches (pole + iron basket), front clutter: one surface;
##   Kit       the orc kit (art/props/orc_camp/orc_kit.glb: throne, watchtowers, war banners, totems, bonfire, cage, bone
##             fence) merged into one atlas surface (big pieces from their first LOD), + the flames (unshaded) and the
##             flames' soft halo discs (unshaded, additive): 3 surfaces.
## Night: at most 4 real lights (light_fire markers -> stage_props unshadowed flickering omni lights); every other torch is
## fake: unshaded flame + additive halo + its warm pool baked into the floor/dressing/kit vertex colours.

const KIT_GLB := "res://art/props/orc_camp/orc_kit.glb"
const KIT_ATLAS := "res://art/props/orc_camp/orc_kit_atlas.png"
const DIRT_TEX := "res://art/maps/goblin_base/painted/dirt.png"
const SCENE_DIR := "res://art/maps/orc_camp/"
const MESH_DIR := "res://art/maps/orc_camp/meshes/"
const MAP_DIR := "res://data/maps/"
const ID := "orc_camp_night"
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
const EARTH := Color(0.50, 0.54, 0.74)  ## trodden night earth (x the painted dirt texture)
const EARTH_DARK := Color(0.40, 0.43, 0.62)
const MOSS := Color(0.40, 0.50, 0.58)  ## the margin's dark blue-green turf
const ASH := Color(0.30, 0.28, 0.32)
const EMBER := Color(0.62, 0.24, 0.10)
const RING_STONE := Color(0.74, 0.74, 0.82)
const WOOD := Color(0.46, 0.38, 0.32)
const WOOD_DARK := Color(0.33, 0.27, 0.23)
const IRON := Color(0.20, 0.20, 0.24)
const STONE := Color(0.50, 0.51, 0.60)
const BONE := Color(0.80, 0.76, 0.66)
const WARM := Color(0.95, 0.55, 0.24)  ## the torchlight baked into vertex colours
const WHITE := Color(1, 1, 1)

## torches: [x, z, height, lit] (lit = a real light_fire marker over it; at most 4 real lights in the map)
const TORCHES := [
	[-2.7, -5.55, 2.0, true], [2.7, -5.55, 2.0, true],
	[-6.2, -6.75, 1.8, false], [6.2, -6.75, 1.8, false],
	[-10.45, -3.4, 1.8, false], [10.45, -3.4, 1.8, false],
	[10.45, 0.6, 1.8, false],
	[-10.45, 4.3, 1.6, false], [10.45, 4.3, 1.6, false],
]
const BONFIRE := Vector3(-9.9, EDGE_Y, 0.6)
## kit: [piece, x, z, yaw_deg, scale, lod (0 = full), tint]
const KIT := [
	["throne", 0.0, -6.05, 0.0, 0.82, 1, Color(0.92, 0.90, 0.94)],
	["watchtower", -9.9, -6.2, 0.0, 0.82, 2, Color(0.86, 0.86, 0.92)],
	["watchtower", 9.9, -6.2, 180.0, 0.82, 2, Color(0.86, 0.86, 0.92)],
	["war_banner", -4.5, -6.55, 0.0, 0.85, 1, Color(0.95, 0.92, 0.95)],
	["war_banner", 4.5, -6.55, 0.0, 0.85, 1, Color(0.95, 0.92, 0.95)],
	["totem", -10.4, -1.3, 90.0, 0.7, 1, Color(0.9, 0.9, 0.95)],
	["totem", 10.4, 2.5, -90.0, 0.7, 1, Color(0.9, 0.9, 0.95)],
	["bonfire", BONFIRE.x, BONFIRE.z, 0.0, 0.75, 1, Color(0.95, 0.92, 0.92)],
	["cage", 10.0, -1.4, -90.0, 0.62, 1, Color(0.88, 0.88, 0.94)],
	["bone_fence", -9.6, 6.6, 15.0, 0.8, 1, Color(0.95, 0.95, 0.98)],
]
## lights: [x, y, z] (light_fire markers)
const SPOTS := [
	["melee", 2.6, -3.4], ["melee", 2.6, -1.13], ["melee", 2.6, 1.13], ["melee", 2.6, 3.4],
	["knight", 3.9, -3.4], ["melee", 3.9, 3.4], ["archer", 6.8, -3.4], ["mage", 6.8, 3.4]]


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

	## A flat ring (r0 ~ 0: a disc) at height y, world-xz uvs, facing up.
	func ring(cx: float, cz: float, y: float, r0: float, r1: float, color: Color, segments: int) -> void:
		for k in segments:
			var a0 := TAU * float(k) / segments
			var a1 := TAU * float(k + 1) / segments
			var p := [Vector3(cx + cos(a0) * r0, y, cz + sin(a0) * r0), Vector3(cx + cos(a1) * r0, y, cz + sin(a1) * r0),
				Vector3(cx + cos(a1) * r1, y, cz + sin(a1) * r1), Vector3(cx + cos(a0) * r1, y, cz + sin(a0) * r1)]
			quad(p[0], p[1], p[2], p[3], color, p.map(func(q): return Vector2(q.x, q.z) / 4.0))

	## A flat fan at `centre` (horizontal): centre colour `inner`, rim `outer` (the halo discs).
	func fan(centre: Vector3, radius: float, inner: Color, outer: Color, segments: int) -> void:
		var base := v.size()
		v.append(centre)
		n.append(Vector3.UP)
		uv.append(Vector2.ZERO)
		c.append(inner)
		for k in segments:
			var a := TAU * float(k) / segments
			v.append(centre + Vector3(cos(a), 0.0, sin(a)) * radius)
			n.append(Vector3.UP)
			uv.append(Vector2.ZERO)
			c.append(outer)
		for k in segments:
			i.append_array([base, base + 1 + (k + 1) % segments, base + 1 + k])

	## Appends `indices` of the surface arrays moved by `xf`; vertex colour from `paint(world_pos, source_colour)`.
	func add(arrays: Array, indices: PackedInt32Array, xf: Transform3D, paint: Callable) -> void:
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs = arrays[Mesh.ARRAY_TEX_UV]
		var cols = arrays[Mesh.ARRAY_COLOR]
		var nb := xf.basis.inverse().transposed()
		var remap := {}
		for k in indices:
			if not remap.has(k):
				remap[k] = v.size()
				var p := xf * verts[k]
				v.append(p)
				n.append((nb * norms[k]).normalized())
				uv.append(uvs[k] if uvs != null else Vector2.ZERO)
				c.append(paint.call(p, cols[k] if cols != null and (cols as PackedColorArray).size() > k else Color.WHITE))
			i.append(remap[k])

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


## The flame points (torch tips + the bonfire), the baked warm light comes from these.
static func flames() -> Array:
	var out: Array = []
	for t in TORCHES:
		out.append([Vector3(t[0], EDGE_Y + float(t[2]) + 0.15, t[1]), 0.45 if t[3] else 0.75])
	out.append([BONFIRE + Vector3(0, 0.9, 0), 0.5])
	return out


## Baked torchlight at world point p (0..1).
static func warmth(p: Vector3, radius: float = 3.2) -> float:
	var w := 0.0
	for f in flames():
		var d: float = (f[0] as Vector3).distance_to(p)
		w += float(f[1]) * pow(clampf(1.0 - d / radius, 0.0, 1.0), 2.0)
	return clampf(w, 0.0, 0.85)


static func lit(color: Color, p: Vector3, radius: float = 3.2) -> Color:
	var w := warmth(p, radius)
	return color.lerp(WARM, w * 0.45) * (1.0 + w * 0.35)


## ---- floor -----------------------------------------------------------------------------------------------------

static func _hash2(a: int, b: int) -> float:
	var h := (a * 73856093) ^ (b * 19349663) ^ 4271
	h = (h ^ (h >> 13)) * 1274126177
	return float(absi(h) % 1000) / 1000.0


static func _floor_colour(x: float, z: float) -> Color:
	var inside: bool = absf(x) < W and absf(z) < D
	var noise := sin(x * 0.8 + sin(z * 0.6) * 1.7) * 0.5 + sin(z * 1.2 - x * 0.45) * 0.5
	var speck := _hash2(int(floor(x * 2.0)), int(floor(z * 2.0))) - 0.5
	if inside:
		var edge: float = minf(W - absf(x), D - absf(z))
		if edge < 0.3:
			return STONE.lerp(EARTH_DARK, 0.4)  # the trodden kerb
		var base := EARTH.lerp(EARTH_DARK, 0.45 + noise * 0.3 + speck * 0.2)
		var r := Vector2(x, z).length()
		if r < 1.5:
			base = base.lerp(ASH, smoothstep(1.5, 0.9, r))  # the scorched heart of the pit
		return base
	var out: float = maxf(absf(x) - W, absf(z) - D)
	var base := MOSS.lerp(EARTH_DARK, clampf(0.55 - out * 0.15 + noise * 0.25 + speck * 0.2, 0.0, 1.0))
	if absf(x) < 3.6 and z < -D:
		base = EARTH_DARK.lerp(STONE, 0.15)  # the beaten path to the throne
	return base


static func _terrain_y(x: float, z: float) -> float:
	if absf(x) < W and absf(z) < D:
		return BOARD_Y
	return EDGE_Y


## Grid lines a0 -> b0 -> b1 -> a1, each run split into ~0.5 m steps that end exactly on its end.
static func _lines(a0: float, b0: float, b1: float, a1: float) -> Array:
	var out: Array = [a0]
	for end in [b0, b1, a1]:
		var start: float = out[-1]
		var count := maxi(1, int(round((end - start) / 0.5)))
		for k in count:
			out.append(lerpf(start, end, float(k + 1) / count))
	return out


func _floor_mesh() -> ArrayMesh:
	var acc := Acc.new()
	# ~0.5 m cells whose lines land on the island's and the board's edges (15.8 m deep: 0.5 m does not divide it).
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
			for q in corners:
				p.append(Vector3(q.x, BOARD_Y if inside else EDGE_Y, q.y))
			var col := lin(lit(_floor_colour(cx, cz), Vector3(cx, 0.0, cz), 3.4))
			var uvs := corners.map(func(q): return Vector2(q.x, q.y) / 4.0)
			acc.quad(p[0], p[3], p[2], p[1], col, [uvs[0], uvs[3], uvs[2], uvs[1]])
	# The board's step up to the margin (faces into the board).
	var trim := lin(STONE.lerp(EARTH_DARK, 0.5))
	for f in [[Vector3(W, 0, -D), Vector3(-W, 0, -D)], [Vector3(-W, 0, D), Vector3(W, 0, D)], [Vector3(-W, 0, -D), Vector3(-W, 0, D)], [Vector3(W, 0, D), Vector3(W, 0, -D)]]:
		var a: Vector3 = f[0]
		var b: Vector3 = f[1]
		acc.quad(a + Vector3(0, EDGE_Y, 0), b + Vector3(0, EDGE_Y, 0), b + Vector3(0, BOARD_Y, 0), a + Vector3(0, BOARD_Y, 0), trim,
			[Vector2(0, 0), Vector2(4, 0), Vector2(4, 0.03), Vector2(0, 0.03)])
	# The war ring: a ring of flat stones round the middle of the board, a glowing ember heart (memorable feature).
	acc.ring(0.0, 0.0, BOARD_Y + 0.012, 3.35, 3.6, lin(RING_STONE), 56)
	for k in 14:
		var a := TAU * (float(k) + 0.5) / 14.0
		var at := Vector2(cos(a), sin(a)) * 3.475
		acc.ring(at.x, at.y, BOARD_Y + 0.016, 0.0, 0.2, lin(RING_STONE.lightened(0.12)), 8)
	acc.ring(0.0, 0.0, BOARD_Y + 0.012, 0.0, 0.55, lin(EMBER), 20)
	acc.ring(0.0, 0.0, BOARD_Y + 0.014, 0.0, 0.28, lin(Color(0.85, 0.42, 0.16)), 14)
	# The island's fascia: dark earth bands down to the client's rock underside.
	var x0 := -ISLAND_W
	var x1 := ISLAND_W
	var z0 := -ISLAND_D
	var z1 := ISLAND_D
	var bands := [[EDGE_Y, -0.3, Color(0.25, 0.22, 0.24)], [-0.3, -0.4, Color(0.13, 0.12, 0.14)], [-0.4, -1.0, Color(0.19, 0.17, 0.19)]]
	for f in [[Vector3(x0, 0, z1), Vector3(x1, 0, z1)], [Vector3(x1, 0, z1), Vector3(x1, 0, z0)], [Vector3(x1, 0, z0), Vector3(x0, 0, z0)], [Vector3(x0, 0, z0), Vector3(x0, 0, z1)]]:
		var a: Vector3 = f[0]
		var b: Vector3 = f[1]
		var segments := int(ceil(a.distance_to(b) / 1.0))
		for s in segments:
			var p0: Vector3 = a.lerp(b, float(s) / segments)
			var p1: Vector3 = a.lerp(b, float(s + 1) / segments)
			for band in bands:
				acc.quad(Vector3(p0.x, band[0], p0.z), Vector3(p0.x, band[1], p0.z), Vector3(p1.x, band[1], p1.z), Vector3(p1.x, band[0], p1.z), lin(band[2]),
					[Vector2(s * 0.25, band[0] * 0.25), Vector2(s * 0.25, band[1] * 0.25), Vector2((s + 1) * 0.25, band[1] * 0.25), Vector2((s + 1) * 0.25, band[0] * 0.25)])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, acc.arrays())
	var material := StandardMaterial3D.new()
	material.resource_name = "orc_floor"
	material.albedo_texture = load(DIRT_TEX)
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = false
	material.roughness = 1.0
	material.metallic_specular = 0.05
	mesh.surface_set_material(0, material)
	return mesh


## ---- dressing (primitives, one vertex-coloured surface) ----------------------------------------------------------

var _dress: Acc
var _fire: Acc
var _glow: Acc


func _prim(m: PrimitiveMesh, at: Vector3, color: Color, basis: Basis = Basis.IDENTITY) -> void:
	var arrays := m.surface_get_arrays(0)
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	_dress.add(arrays, idx, Transform3D(basis, at), func(p: Vector3, _c: Color) -> Color: return lin(lit(color, p, 2.2)))


func _box(x: float, y0: float, z: float, sx: float, sy: float, sz: float, color: Color, yaw_deg: float = 0.0) -> void:
	var m := BoxMesh.new()
	m.size = Vector3(sx, sy, sz)
	_prim(m, Vector3(x, y0 + sy * 0.5, z), color, Basis(Vector3.UP, deg_to_rad(yaw_deg)))


func _cyl(at: Vector3, r_bottom: float, r_top: float, h: float, segments: int, color: Color, basis: Basis = Basis.IDENTITY, caps: bool = false) -> void:
	var m := CylinderMesh.new()
	m.bottom_radius = r_bottom
	m.top_radius = r_top
	m.height = h
	m.radial_segments = segments
	m.rings = 1
	m.cap_top = caps
	m.cap_bottom = false
	_prim(m, at, color, basis)


## One sharpened palisade log standing on the margin.
func _log(x: float, z: float, h: float, r: float, color: Color) -> void:
	_cyl(Vector3(x, EDGE_Y - 0.3 + (h + 0.3) * 0.5, z), r, r, h + 0.3, 5, color)
	_cyl(Vector3(x, EDGE_Y + h + 0.2, z), r, 0.0, 0.4, 5, color.darkened(0.1))


## A palisade run from a to b (xz), logs `r` thick, heights varied, two lashing beams on the inner face.
func _palisade(a: Vector2, b: Vector2, h: float, inner: Vector2) -> void:
	var length := a.distance_to(b)
	var count := int(round(length / 0.46))
	for k in count + 1:
		var p := a.lerp(b, float(k) / count)
		var hk := h * (0.86 + _hash2(int(p.x * 10.0), int(p.y * 10.0)) * 0.22)
		_log(p.x, p.y, hk, 0.23, WOOD.lerp(WOOD_DARK, _hash2(k, int(a.x)) * 0.8))
	var mid := (a + b) * 0.5 + inner * 0.26
	var along_x := absf(b.x - a.x) > absf(b.y - a.y)
	for y in [0.55, h - 0.45]:
		_box(mid.x, EDGE_Y + y, mid.y, length if along_x else 0.12, 0.16, 0.12 if along_x else length, WOOD_DARK)


func _torch(t: Array) -> void:
	var x: float = t[0]
	var z: float = t[1]
	var h: float = t[2]
	_cyl(Vector3(x, EDGE_Y + h * 0.5, z), 0.07, 0.055, h, 5, WOOD_DARK)
	_cyl(Vector3(x, EDGE_Y + h + 0.02, z), 0.1, 0.19, 0.24, 6, IRON, Basis.IDENTITY, false)
	_box(x, EDGE_Y + h * 0.35, z, 0.18, 0.18, 0.18, IRON)  # a stake collar
	var tip := Vector3(x, EDGE_Y + h + 0.1, z)
	_flame(tip, 0.17, 0.62)
	_glow.fan(tip + Vector3(0, 0.12, 0), 1.0, lin(Color(1.0, 0.56, 0.22, 0.5)), lin(Color(1.0, 0.45, 0.15, 0.0)), 14)


## Two crossed flame cones: a hot core and an outer tongue (unshaded; a gradient base -> tip in vertex colours).
func _flame(base: Vector3, r: float, h: float) -> void:
	for layer in [[r, h, Color(1.0, 0.42, 0.10), Color(1.0, 0.70, 0.25)], [r * 0.55, h * 0.7, Color(1.0, 0.78, 0.35), Color(1.0, 0.95, 0.70)]]:
		var m := CylinderMesh.new()
		m.bottom_radius = layer[0]
		m.top_radius = 0.0
		m.height = layer[1]
		m.radial_segments = 6
		m.rings = 1
		m.cap_top = false
		m.cap_bottom = false
		var arrays := m.surface_get_arrays(0)
		var lo: Color = layer[2]
		var hi: Color = layer[3]
		var hh: float = layer[1]
		_fire.add(arrays, arrays[Mesh.ARRAY_INDEX], Transform3D(Basis.IDENTITY, base + Vector3(0, hh * 0.5, 0)),
			func(p: Vector3, _c: Color) -> Color: return lin(lo.lerp(hi, clampf((p.y - base.y) / hh, 0.0, 1.0))))


func _dressing() -> void:
	# The log palisade: north (behind the throne), west and east; the front stays an open cliff.
	_palisade(Vector2(-WALL_X - 0.3, WALL_N), Vector2(WALL_X + 0.3, WALL_N), 2.5, Vector2(0, 1))
	for side in [-1.0, 1.0]:
		_palisade(Vector2(side * WALL_X, WALL_N + 0.5), Vector2(side * WALL_X, WALL_END), 2.2, Vector2(-side, 0))
		# The wall's end post at the open front: a thick lashed post with a skull.
		_cyl(Vector3(side * WALL_X, EDGE_Y + 1.15, WALL_END + 0.55), 0.32, 0.28, 2.6, 6, WOOD_DARK)
		var skull := SphereMesh.new()
		skull.radius = 0.2
		skull.height = 0.36
		skull.radial_segments = 8
		skull.rings = 4
		_prim(skull, Vector3(side * WALL_X, EDGE_Y + 2.62, WALL_END + 0.55), BONE)
	# The throne dais: two stone steps under the Warlord's seat.
	_box(0.0, EDGE_Y - 0.05, -6.15, 5.4, 0.3, 2.6, STONE)
	_box(0.0, EDGE_Y + 0.25, -6.3, 4.6, 0.22, 2.1, STONE.lightened(0.06))
	_box(0.0, EDGE_Y - 0.05, -4.75, 3.2, 0.16, 0.4, STONE.darkened(0.1))
	for t in TORCHES:
		_torch(t)
	# Skull pikes along the side walls (inside the margin, never on the board).
	for p in [[-10.0, -4.9], [10.0, -4.9], [-10.3, 2.4], [10.2, 5.4]]:
		_cyl(Vector3(p[0], EDGE_Y + 0.8, p[1]), 0.04, 0.03, 1.6, 4, WOOD_DARK)
		var skull := SphereMesh.new()
		skull.radius = 0.15
		skull.height = 0.26
		skull.radial_segments = 6
		skull.rings = 3
		_prim(skull, Vector3(p[0], EDGE_Y + 1.62, p[1]), BONE)
	# Front margin: low clutter only (the camera side): rocks, a log pile, skull heaps, a weapon heap.
	var rock := SphereMesh.new()
	rock.radius = 0.5
	rock.height = 1.0
	rock.radial_segments = 6
	rock.rings = 3
	for r in [[-6.6, 6.9, 1.0, 0.5, 0.8], [-7.3, 6.4, 0.6, 0.35, 0.6], [7.6, 6.8, 1.1, 0.55, 0.8], [3.2, 7.1, 0.7, 0.35, 0.6], [-1.4, 6.9, 0.5, 0.3, 0.5]]:
		_prim(rock, Vector3(r[0], EDGE_Y + 0.05, r[1]), Color(0.42, 0.40, 0.40), Basis.from_scale(Vector3(r[2], r[3] * 2.0, r[4])))
	for k in 3:
		_cyl(Vector3(5.0, EDGE_Y + 0.17 + 0.3 * (k / 2), 6.6 + 0.36 * float(k % 2) - 0.18 * float(k / 2)), 0.17, 0.17, 1.8, 6, WOOD.lerp(WOOD_DARK, float(k) * 0.3), Basis(Vector3.FORWARD, PI * 0.5), true)
	var heap := SphereMesh.new()
	heap.radius = 0.13
	heap.height = 0.22
	heap.radial_segments = 6
	heap.rings = 3
	for s in [[-3.6, 6.7], [-3.4, 6.9], [-3.75, 6.95], [-3.55, 6.8, 0.2], [9.2, 6.2], [9.4, 6.4], [9.1, 6.45]]:
		_prim(heap, Vector3(s[0], EDGE_Y + 0.1 + float(s[2] if s.size() > 2 else 0.0), s[1]), BONE)
	# Spears stuck in the ground by the bonfire (side margin).
	for k in 3:
		_cyl(Vector3(-10.7 + k * 0.25, EDGE_Y + 0.9, 2.0 + k * 0.2), 0.03, 0.03, 1.8, 4, WOOD_DARK, Basis(Vector3.RIGHT, 0.15 - k * 0.12))


## ---- kit (merged) ------------------------------------------------------------------------------------------------

var _kit_meshes: Dictionary = {}


func _load_kit() -> bool:
	var scene := (load(KIT_GLB) as PackedScene).instantiate()
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		_kit_meshes[str(node.name)] = (node as MeshInstance3D).mesh
	scene.free()
	for row in KIT:
		if not _kit_meshes.has(row[0]):
			printerr("orc kit has no piece ", row[0])
			return false
	return true


## The index list of LOD `lod` of a surface (0 = the full mesh): the importer's own LOD (meshes/generate_lods).
static func _indices(mesh: Mesh, surface: int, lod: int) -> PackedInt32Array:
	var full: PackedInt32Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
	if lod <= 0:
		return full
	var data: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), surface)
	var lods: Array = data.get("lods", [])
	if lods.size() < lod:
		return full
	var bytes: PackedByteArray = lods[lod - 1]["index_data"]
	var wide: bool = int(data.get("vertex_count", 0)) > 65535
	var out := PackedInt32Array()
	if wide:
		for k in range(0, bytes.size(), 4):
			out.append(bytes.decode_u32(k))
	else:
		for k in range(0, bytes.size(), 2):
			out.append(bytes.decode_u16(k))
	return out


func _kit_mesh() -> ArrayMesh:
	var stone := Acc.new()
	for row in KIT:
		var mesh: Mesh = _kit_meshes[row[0]]
		var y := EDGE_Y - 0.02
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(row[3]))).scaled(Vector3.ONE * float(row[4])), Vector3(float(row[1]), y, float(row[2])))
		if row[0] == "throne":
			xf.origin.y = EDGE_Y + 0.45  # on the dais
		var tint: Color = row[6]
		for s in mesh.get_surface_count():
			var material := mesh.surface_get_material(s)
			var is_fire := material != null and str(material.resource_name).ends_with("_fire")
			var idx := _indices(mesh, s, int(row[5]))
			if is_fire:
				_fire.add(mesh.surface_get_arrays(s), idx, xf, func(_p: Vector3, c: Color) -> Color: return c)
			else:
				stone.add(mesh.surface_get_arrays(s), idx, xf, func(p: Vector3, _c: Color) -> Color: return lin(lit(tint, p, 2.4)))
	_glow.fan(BONFIRE + Vector3(0, 0.75, 0), 1.6, lin(Color(1.0, 0.5, 0.2, 0.55)), lin(Color(1.0, 0.4, 0.12, 0.0)), 16)
	var out := ArrayMesh.new()
	var stone_material := StandardMaterial3D.new()
	stone_material.resource_name = "orc_kit"
	stone_material.albedo_texture = load(KIT_ATLAS)
	stone_material.vertex_color_use_as_albedo = true
	stone_material.vertex_color_is_srgb = false
	stone_material.roughness = 1.0
	stone_material.metallic_specular = 0.1
	stone_material.cull_mode = BaseMaterial3D.CULL_DISABLED  # (the kit's single-sheet banners and hides)
	var fire_material := StandardMaterial3D.new()
	fire_material.resource_name = "orc_fire"  # *_fire: unshaded (stage_props._is_emissive)
	fire_material.vertex_color_use_as_albedo = true
	fire_material.vertex_color_is_srgb = false
	fire_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var glow_material := StandardMaterial3D.new()
	glow_material.resource_name = "orc_glow"  # *_glow: unshaded; additive soft halo, never inked (transparent)
	glow_material.vertex_color_use_as_albedo = true
	glow_material.vertex_color_is_srgb = false
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow_material.no_depth_test = false
	for pair in [[stone, stone_material], [_fire, fire_material], [_glow, glow_material]]:
		var acc: Acc = pair[0]
		if acc.v.is_empty():
			continue
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, acc.arrays())
		out.surface_set_material(out.get_surface_count() - 1, pair[1])
	return out


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


static func light_points() -> Array:
	var out: Array = []
	for t in TORCHES:
		if t[3]:
			out.append(Vector3(t[0], EDGE_Y + float(t[2]) + 0.45, t[1]))
	out.append(BONFIRE + Vector3(0, 1.2, 0))
	out.append(Vector3(0.0, 3.2, 0.0))  # over the war ring's ember heart: lights the fight itself, warm, from above
	return out


func _map_json() -> Dictionary:
	var spawns: Array = []
	var fixture := {"melee": "goblin", "knight": "goblin_knight", "archer": "goblin_archer", "mage": "goblin_mage"}
	for s in SPOTS:
		spawns.append({"type": fixture[s[0]], "level": 1, "position": [s[1], 0.05, s[2]]})
	return {
		"version": 1, "id": ID, "name": "Orc Camp · Night Fires",
		"_design": "Orc Camp zone (level-designer 2026-11-20). Generated by tools/maps/build_orc_camp.gd (edit the script, not this file): the goblin courtyard board (same bounds, spawns, no cover) on a floating island at NIGHT. A sharpened-log palisade closes the north, east and west margins; the Orc Warlord's bone throne sits on a stone dais in the middle of the north wall between two lit torches and war banners, watchtowers stand in the back corners, totems, a caged prisoner and the bonfire on the side margins, low skull heaps, rocks and a log pile on the open front cliff. A ring of flat stones with a glowing ember heart is inlaid in the middle of the board (the war ring). Light: a dim blue moon, 4 real flickering firelights (the two throne torches, the bonfire, one high over the war ring's ember heart so the fight itself is lit), every other torch faked (unshaded flame, additive halo, warm pool baked into the vertex colours), embers drifting from the fires (client/arena_props.gd add_orc_island). Monster ids here are a goblin FIXTURE (no orc family yet): the zone's orc_waves journey will bring the real waves onto the spots in list order.",
		"modes": ["pve"], "kind": "fight", "camera_style": "arena", "atmosphere": "ink",
		"art_scene": SCENE_DIR + ID + ".tscn", "art_mood": "night",
		"bounds": {"half_width": W, "half_depth": D},
		"spawn": [-5.6, 0.05, 0.0],
		"solids": [{"center": [0, -0.2, 0], "size": [16.0, 0.4, 9.0], "material": "ink"}],
		"enemy_spawns": spawns,
		"rest_points": [],
		"player_spawns": [[-5.6, 0.05, 0.0], [-4.6, 0.05, -2.2], [-4.6, 0.05, 2.2]],
		"_arena": "Board 16 x 9 m, the goblin courtyard's (same spawns, no cover: logic/auto_pilot.gd walks straight at its target). Nothing stands on the board; the walls, throne and fires are on the island margins, the front (camera side) is an open cliff.",
		"_spots": "Spot roles in order: " + ", ".join(SPOTS.map(func(s): return str(s[0]))),
		"world_region": "orc_camp",
	}


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Use a window: the kit's LOD index lists come from the rendering server")
		quit(1)
		return
	if not _load_kit():
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MESH_DIR))
	var map := _map_json()
	var root_node := Node3D.new()
	root_node.name = ID
	root_node.set_meta("floating_island", true)  # client/arena_props.gd is_pyramid_island: the scene is the island top
	root_node.set_meta("night_camp", true)  # client/arena_props.gd is_orc_island: night sky, dark underside, embers
	var embers := PackedVector3Array()
	for f in flames():
		embers.append(f[0])
	root_node.set_meta("embers", embers)
	_dress = Acc.new()
	_fire = Acc.new()
	_glow = Acc.new()
	_dressing()
	var dress_mesh := ArrayMesh.new()
	dress_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _dress.arrays())
	var dress_material := StandardMaterial3D.new()
	dress_material.resource_name = "orc_dressing"
	dress_material.vertex_color_use_as_albedo = true
	dress_material.vertex_color_is_srgb = false
	dress_material.roughness = 0.95
	dress_material.metallic_specular = 0.1
	dress_mesh.surface_set_material(0, dress_material)
	var floor_mesh := _save_mesh(_floor_mesh(), MESH_DIR + ID + "_floor.res")
	dress_mesh = _save_mesh(dress_mesh, MESH_DIR + ID + "_dressing.res")
	var kit_mesh := _save_mesh(_kit_mesh(), MESH_DIR + ID + "_kit.res")
	if floor_mesh == null or dress_mesh == null or kit_mesh == null:
		quit(1)
		return
	var ground := _instance(root_node, "PyramidFloor", floor_mesh)  # (the island-floor node name the client and tests share)
	ground.set_meta("toon_no_outline", true)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_instance(root_node, "Dressing", dress_mesh)
	_instance(root_node, "Kit", kit_mesh)
	var lights := light_points()
	for k in lights.size():
		_marker(root_node, "light_fire%d" % k, lights[k])
	_marker(root_node, "spawn", Vector3(-5.6, 0.05, 0.0))
	for k in map.enemy_spawns.size():
		var p: Array = map.enemy_spawns[k].position
		_marker(root_node, "enemy_%d" % k, Vector3(p[0], p[1], p[2]))
	var packed := PackedScene.new()
	packed.pack(root_node)
	var scene_path := SCENE_DIR + ID + ".tscn"
	if ResourceSaver.save(packed, scene_path) != OK:
		printerr("cannot save ", scene_path)
		quit(1)
		return
	root_node.free()
	var f := FileAccess.open(MAP_DIR + ID + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(map, "\t", false))
	f.close()
	var tris := 0
	var surfaces := 0
	var per_mesh := {}
	for pair in [["floor", floor_mesh], ["dressing", dress_mesh], ["kit", kit_mesh]]:
		var t := 0
		for s in pair[1].get_surface_count():
			t += pair[1].surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
			surfaces += 1
		per_mesh[pair[0]] = t
		tris += t
	var bytes := 0
	for suffix in ["_floor.res", "_dressing.res", "_kit.res"]:
		bytes += FileAccess.get_file_as_bytes(MESH_DIR + ID + suffix).size()
	var report := {ID: {"triangles": tris, "triangles_by_mesh": per_mesh, "draw_surfaces": surfaces, "mesh_bytes": bytes,
		"scene_bytes": FileAccess.get_file_as_bytes(scene_path).size(), "lights": lights.size(), "torches": TORCHES.size(), "cover": 0}}
	var m := FileAccess.open(SCENE_DIR + "manifest.json", FileAccess.WRITE)
	m.store_string(JSON.stringify(report, "  "))
	m.close()
	print("ORC CAMP BUILT ", report)
	quit()
