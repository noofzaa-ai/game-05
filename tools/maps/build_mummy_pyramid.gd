extends SceneTree
## Builds the Mummy Pyramid stages (level-designer 2026-11-17, Boss: the mummies live ONLY in this zone and the maps
## are finished to the goblin camp's level): data/maps/mummy_pyramid_*.json + art/maps/mummy_pyramid/*.tscn.
##   godot --headless --path . --script res://tools/maps/build_mummy_pyramid.gd
## The fight boards are the goblin boards: 16 x 9 m (camera_style arena), squad on the left, monsters on the right.
## client/stage_view.gd + client/arena_props.gd hide every MultiMeshInstance3D of a non-goblin art scene and lay the
## tile island under it, so this scene draws everything with three plain meshes saved next to it
## (art/maps/mummy_pyramid/meshes/<id>_*.res, binary, in the 'stages' battle pack; the .tscn stays a few KB):
##   PyramidFloor  the painted floor: board + raised terrace + dunes + cliff skirt, two surfaces (the painted
##                 slab tile and the painted sand of art/maps/mummy_tomb/painted, tinted by vertex colour),
##                 flat: toon_no_outline, so the drawn style gives it no ink hull;
##   Dressing      the architecture built here (pylons, pyramids, walls, columns, alcoves, cover blocks),
##                 one vertex-coloured surface;
##   Kit           the Boss-delivered tomb kit (art/props/mummy_tomb, 11 props) re-placed and MERGED into one stone
##                 surface (the kit atlas, recoloured per piece by vertex colour) + one unshaded flame surface.
## So a map is 5 surfaces (+2 ink hulls under the drawn style), a goblin camp is ~15 MultiMeshes (+ hulls).
## Lights: 2-4 light_* empties per map (client/stage_props.gd makes unshadowed omni lights of them).
## Cover: every obstacle solid of the map JSON is enclosed (x1.03) by its Dressing block, built from the same list.

const KIT_DIR := "res://art/props/mummy_tomb/meshes/"
const KIT_ALBEDO := "res://art/props/mummy_tomb/mummy_kit_albedo.png"
const SLAB_TEX := "res://art/maps/mummy_tomb/painted/floor_tile.png"
const SAND_TEX := "res://art/maps/mummy_tomb/painted/sand.png"
const SCENE_DIR := "res://art/maps/mummy_pyramid/"
const MESH_DIR := "res://art/maps/mummy_pyramid/meshes/"
const MAP_DIR := "res://data/maps/"
const COMBAT := "res://data/combat/combat.json"
const W := 8.0
const D := 4.5
const BOARD_Y := 0.02  ## the board's painted floor (just over the client's tile island, top y 0)
const EDGE_Y := 0.14  ## the terrace around the board: covers the client's stone rim (top y 0.13)
const COVER_PAD := 1.03  ## a cover block's dressing encloses its collider box by this much (goblin dressing rule)

## sRGB palette (vertex colours are written linear: stage_props turns vertex_color_is_srgb off)
## (muted: the warm sun, the braziers and the drawn style's warmth push every sand tone towards orange)
const SAND := Color(0.76, 0.68, 0.54)
const SAND_DARK := Color(0.63, 0.55, 0.43)
const STONE := Color(0.76, 0.71, 0.62)
const STONE_DARK := Color(0.52, 0.47, 0.41)
const BASALT := Color(0.40, 0.37, 0.35)
const TEAL := Color(0.22, 0.52, 0.50)
const TEAL_DARK := Color(0.15, 0.36, 0.36)
const GOLD := Color(0.84, 0.66, 0.32)
const GOLD_DIM := Color(0.66, 0.53, 0.32)  ## big gold surfaces (full GOLD reads as flat yellow there)
const LAPIS := Color(0.18, 0.28, 0.52)
const RED_OCHRE := Color(0.58, 0.27, 0.18)
const DOOR := Color(0.20, 0.15, 0.12)
const WHITE := Color(1, 1, 1)


## ---- the three maps --------------------------------------------------------------------------------------------
## (The auto-battler plays ONE fight on one board from mummy_waves arena_maps: no boss arena, no rest camp. The
## throne-room and oasis-camp variants were removed 2026-11-18, Boss.)
## spots: [role, x, z] in placement order (the journey puts its monsters on the spots in list order: melee first,
##        then knights, then the ranged ones furthest right behind the cover). role -> fixture type in _fixture_type.
## cover: [x, z, size_x, height, size_z, style] obstacle solids (style picks the dressing).
## kit: [name, x, z, yaw, scale, y, tint(optional Color), x_rot(optional)]
## lights: [kind, x, y, z]  kind = light_fire (warm, strong) or light_lantern (soft)

const FIGHT_SPOTS: Array = [
	["melee", 2.4, -3.0], ["melee", 2.4, -1.0], ["melee", 2.4, 1.0], ["melee", 2.4, 3.0],
	["knight", 3.8, -2.0], ["knight", 3.8, 2.0], ["archer", 7.0, -2.9], ["mage", 7.0, 2.9]]


## The three wave-mode boards (data/journeys/mummy_waves.json arena_maps) are floating islands made like the goblin
## camp island (client/arena_props.gd build_camp, Boss 2026-11-17): the island top is the board plus the goblin margins
## (ISLAND_W x ISLAND_D, the same numbers as arena_props MARGIN_X / MARGIN_Z), a wall on the north, east and west margin
## with an entrance in the north wall, corner "towers", banners, statues and braziers along the walls, low clutter on
## the margins only, an open cliff in front (the camera side). The fascia is the floor mesh's masonry skirt; the rock
## underside and the clouds come from client/arena_props.gd add_pyramid_island (the goblin island's underside).
const ISLAND_W := W + 3.6  ## = arena_props.MARGIN_X
const ISLAND_D := D + 3.4  ## = arena_props.MARGIN_Z
const WALL_N := -ISLAND_D + 0.6  ## north wall line (the goblin palisade's line)
const WALL_X := ISLAND_W - 0.6  ## side wall lines
const WALL_END := ISLAND_D - 1.5  ## side walls stop here; a corner pier stands beyond (open front)


static func layouts() -> Dictionary:
	var gate := {
		"name": "Pyramid · Desert Gate", "mood": "camp", "spots": FIGHT_SPOTS, "seed": 1, "back": -9.5, "island": true,
		"design": "Desert entrance on a floating island: the board is drifted sand crossed by a paved causeway (west-east, the line of the fight) with a spur north to the pylon gate in the island's weathered sandstone enclosure wall (north, east, west; the front is an open cliff). Two small pyramids stand in the back corners, obelisks and Anubis statues flank the gate, banners hang on the walls, dunes drift against them, scrub, urns and fallen stones on the margins. Cover: two toppled sandstone blocks shield the archer and the mage (far right).",
		"cover": [[5.9, -2.9, 1.0, 1.5, 1.0, "block"], [5.9, 2.9, 1.0, 1.5, 1.0, "block"]],
		"kit": [
			["brazier", -1.5, -5.4, 0, 1.2, EDGE_Y], ["brazier", 1.5, -5.4, 0, 1.2, EDGE_Y],
			["obelisk", -5.5, -5.8, 0, 1.15, EDGE_Y], ["obelisk", 5.5, -5.8, 0, 1.15, EDGE_Y],
			["anubis_urn", -7.4, -5.75, 0, 1.45, EDGE_Y + 0.42], ["anubis_urn", 7.4, -5.75, 0, 1.45, EDGE_Y + 0.42],
			["brazier", -9.5, -0.6, 0, 1.1, EDGE_Y], ["brazier", 9.5, -0.6, 0, 1.1, EDGE_Y],
			["torch", -10.3, -3.6, 0, 0.85, EDGE_Y], ["torch", 10.3, 2.4, 0, 0.85, EDGE_Y],
			["urn", -9.4, 2.6, 30, 1.2, EDGE_Y], ["urn", -9.9, 3.4, -10, 0.9, EDGE_Y], ["urn", 9.2, -3.4, 50, 1.1, EDGE_Y],
			["chest", 9.5, 4.3, -100, 0.9, EDGE_Y],
			["urn", -6.4, 6.2, 0, 1.1, EDGE_Y], ["urn", -5.7, 6.9, 40, 0.8, EDGE_Y], ["chest", 5.8, 6.5, 20, 0.85, EDGE_Y],
			["pillar", -2.4, 6.6, 80, 0.42, EDGE_Y, STONE, 90.0], ["obelisk", 2.6, 6.9, 95, 0.75, EDGE_Y, WHITE, 90.0],
		],
		"lights": [["light_fire", -1.5, 1.6, -5.4], ["light_fire", 1.5, 1.6, -5.4], ["light_lantern", -9.5, 1.6, -0.6], ["light_lantern", 9.5, 1.6, -0.6]],
	}
	var hall := {
		"name": "Pyramid · Hall of Pillars", "mood": "night", "spots": FIGHT_SPOTS, "seed": 2, "back": -9.0, "island": true,
		"design": "Pillared hall on a floating island: a dark stone hall wall (north, east, west; open cliff in front) with a colonnade and architrave along the back, a gold-framed doorway between the middle columns, side colonnades with Anubis statues, square pylon towers in the back corners, lapis and teal banners, torches and braziers; a fallen column and drums lie on the front margin. The board is dark polished slabs framed by a teal-and-gold inlay with a red-ochre runner down the middle. Cover: two broken column stumps on the monster side.",
		"cover": [[5.9, -2.9, 0.9, 1.6, 0.9, "stump"], [5.9, 2.9, 0.9, 1.6, 0.9, "stump"]],
		"kit": [
			["pillar", -7.5, -5.6, 0, 1.0, EDGE_Y, STONE], ["pillar", -4.5, -5.6, 0, 1.0, EDGE_Y, STONE], ["pillar", -1.6, -5.6, 0, 1.0, EDGE_Y, STONE],
			["pillar", 1.6, -5.6, 0, 1.0, EDGE_Y, STONE], ["pillar", 4.5, -5.6, 0, 1.0, EDGE_Y, STONE], ["pillar", 7.5, -5.6, 0, 1.0, EDGE_Y, STONE],
			["pillar", -9.7, -2.6, 90, 1.0, EDGE_Y, STONE], ["pillar", -9.7, 1.0, 90, 1.0, EDGE_Y, STONE], ["pillar", -9.7, 4.6, 90, 1.0, EDGE_Y, STONE],
			["pillar", 9.7, -2.6, 90, 1.0, EDGE_Y, STONE], ["pillar", 9.7, 1.0, 90, 1.0, EDGE_Y, STONE], ["pillar", 9.7, 4.6, 90, 1.0, EDGE_Y, STONE],
			["torch", -3.05, -6.2, 0, 1.0, EDGE_Y], ["torch", 3.05, -6.2, 0, 1.0, EDGE_Y],
			["brazier", -9.7, -0.8, 0, 1.0, EDGE_Y], ["brazier", 9.7, -0.8, 0, 1.0, EDGE_Y],
			["anubis_urn", -10.0, 2.8, 90, 1.4, EDGE_Y + 0.36], ["anubis_urn", 10.0, 2.8, -90, 1.4, EDGE_Y + 0.36],
			["pillar", -4.6, 6.7, 90, 0.6, EDGE_Y, STONE, 90.0],
			["urn", -9.0, 6.0, 20, 1.0, EDGE_Y], ["urn", 9.2, 6.2, -40, 1.1, EDGE_Y], ["chest", 7.2, 6.6, -15, 0.85, EDGE_Y],
			["anubis_urn", 1.2, 6.8, 120, 0.9, EDGE_Y, WHITE, 90.0],
		],
		"lights": [["light_fire", -3.05, 2.3, -6.2], ["light_fire", 3.05, 2.3, -6.2], ["light_lantern", -9.7, 1.4, -0.8], ["light_lantern", 9.7, 1.4, -0.8]],
	}
	var sanctum := {
		"name": "Pyramid · Coffin Sanctum", "mood": "night", "spots": FIGHT_SPOTS, "seed": 3, "back": -9.0, "island": true,
		"design": "Inner coffin chamber on a floating island: a basalt wall (north, east, west; open cliff in front) with deep alcoves where painted coffins stand, a sarcophagus on its altar between two Anubis jars under a gold sun disc in the middle of the north wall, tall gold-tipped obelisks in the back corners, more coffins along the side walls, braziers and banners; the tomb's treasure (chests, gold, urns, a fallen lid) on the front margin. A gold sun ring is inlaid in the middle of the board. Cover: two closed stone sarcophagi on the monster side.",
		"cover": [[5.6, -2.9, 1.6, 1.5, 0.9, "sarcophagus"], [5.6, 2.9, 1.6, 1.5, 0.9, "sarcophagus"]],
		"kit": [
			["coffin", -8.4, -6.35, 0, 1.0, EDGE_Y], ["coffin", -6.4, -6.35, 0, 1.0, EDGE_Y], ["coffin", -4.4, -6.35, 0, 1.0, EDGE_Y],
			["coffin", 4.4, -6.35, 0, 1.0, EDGE_Y], ["coffin", 6.4, -6.35, 0, 1.0, EDGE_Y], ["coffin", 8.4, -6.35, 0, 1.0, EDGE_Y],
			["altar", 0.0, -5.85, 0, 1.5, EDGE_Y + 0.3], ["coffin", 0.0, -5.85, 90, 0.9, EDGE_Y + 1.95, WHITE, -90.0],
			["anubis_urn", -2.1, -5.4, 10, 1.1, EDGE_Y + 0.3], ["anubis_urn", 2.1, -5.4, -10, 1.1, EDGE_Y + 0.3],
			["coffin", -10.35, -3.4, 90, 0.95, EDGE_Y], ["coffin", 10.35, -3.4, -90, 0.95, EDGE_Y],
			["coffin", -10.35, 3.0, 90, 0.95, EDGE_Y], ["coffin", 10.35, 3.0, -90, 0.95, EDGE_Y],
			["brazier", -9.4, -0.2, 0, 1.1, EDGE_Y], ["brazier", 9.4, -0.2, 0, 1.1, EDGE_Y],
			["chest", -6.0, 6.5, 15, 0.9, EDGE_Y], ["chest", 6.3, 6.6, -20, 0.9, EDGE_Y],
			["urn", -8.8, 6.1, 0, 1.1, EDGE_Y], ["urn", 8.9, 6.0, 30, 1.0, EDGE_Y], ["urn", -4.6, 6.9, 0, 0.8, EDGE_Y],
			["coffin", 0.4, 6.75, 90, 0.75, EDGE_Y, WHITE, -90.0],
		],
		"lights": [["light_fire", -9.4, 1.5, -0.2], ["light_fire", 9.4, 1.5, -0.2], ["light_lantern", -2.6, 2.4, -5.6], ["light_lantern", 2.6, 2.4, -5.6]],
	}
	return {"mummy_pyramid_gate": gate, "mummy_pyramid_hall": hall, "mummy_pyramid_sanctum": sanctum}


## ---- mesh accumulation --------------------------------------------------------------------------------------------

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
			normal = (b - a).cross(cc - a) if (b - a).length() > 0.000001 else (cc - a).cross(d - a)
		normal = normal.normalized()
		for k in 4:
			v.append([a, b, cc, d][k])
			n.append(normal)
			uv.append(uvs[k])
			c.append(color)
		# normal = (b - a) x (d - a); Godot's front faces wind clockwise seen from the front
		i.append_array([base, base + 3, base + 2, base, base + 2, base + 1])

	## A flat polygon ring (r0 = 0: a disc) lying at height y, uv = world xz / 4 (the slab tile's scale).
	func ring(cx: float, cz: float, y: float, r0: float, r1: float, color: Color, segments: int = 48, from_angle: float = 0.0, to_angle: float = TAU) -> void:
		for k in segments:
			var a0 := lerpf(from_angle, to_angle, float(k) / segments)
			var a1 := lerpf(from_angle, to_angle, float(k + 1) / segments)
			var p := [Vector3(cx + cos(a0) * r0, y, cz + sin(a0) * r0), Vector3(cx + cos(a1) * r0, y, cz + sin(a1) * r0),
				Vector3(cx + cos(a1) * r1, y, cz + sin(a1) * r1), Vector3(cx + cos(a0) * r1, y, cz + sin(a0) * r1)]
			var uvs := p.map(func(q): return Vector2(q.x + 1.0, q.z) / 4.0)
			# (p1 - p0) runs around, (p3 - p0) outward: their cross product points up
			quad(p[0], p[1], p[2], p[3], color, uvs)

	## Appends surface `surface` of `mesh` moved by `xf`, every vertex coloured `color`.
	func mesh(m: Mesh, surface: int, xf: Transform3D, color: Color) -> void:
		var arrays := m.surface_get_arrays(surface)
		var base := v.size()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs = arrays[Mesh.ARRAY_TEX_UV]
		var normal_basis := xf.basis.inverse().transposed()
		for k in verts.size():
			v.append(xf * verts[k])
			n.append((normal_basis * norms[k]).normalized())
			uv.append(uvs[k] if uvs != null else Vector2.ZERO)
			c.append(color)
		var idx = arrays[Mesh.ARRAY_INDEX]
		if idx == null or (idx as PackedInt32Array).is_empty():
			for k in verts.size():
				i.append(base + k)
		else:
			# (a mirrored transform would flip the winding: the builder never mirrors)
			for k in (idx as PackedInt32Array):
				i.append(base + k)

	func arrays() -> Array:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = n
		a[Mesh.ARRAY_TEX_UV] = uv
		a[Mesh.ARRAY_COLOR] = c
		a[Mesh.ARRAY_INDEX] = i
		return a

	func tris() -> int:
		return i.size() / 3


static func lin(color: Color) -> Color:
	return color.srgb_to_linear()


var kit_meshes: Dictionary = {}
var combat_ids: Array = []


func _initialize() -> void:
	call_deferred("run")


func _load_kit() -> bool:
	for kit_name in ["coffin", "torch", "pillar", "anubis_urn", "brazier", "altar", "stairs", "chest", "obelisk", "wall_panel", "urn"]:
		var path: String = KIT_DIR + kit_name + ".res"
		if not ResourceLoader.exists(path):
			printerr("missing kit mesh ", path)
			return false
		kit_meshes[kit_name] = load(path)
	return true


## ---- the floor ----------------------------------------------------------------------------------------------------

## Terrace extents around the board.
func _extents(id: String, layout: Dictionary) -> Rect2:
	if layout.get("island", false):  # the goblin island's top: board + margins
		return Rect2(-ISLAND_W, -ISLAND_D, ISLAND_W * 2.0, ISLAND_D * 2.0)
	return Rect2(-12.5, float(layout.back), 25.0, 6.0 - float(layout.back))


func _board(layout: Dictionary) -> Vector2:
	return Vector2(W, D)


static func _hash2(a: int, b: int, seed_value: int) -> float:
	var h := (a * 73856093) ^ (b * 19349663) ^ (seed_value * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return float(absi(h) % 1000) / 1000.0


## The slab tone of the 2 m slab holding (x, z): -1..1
static func _slab_tone(x: float, z: float, seed_value: int) -> float:
	return _hash2(int(floor((x + 1.0) / 2.0)), int(floor(z / 2.0)), seed_value) * 2.0 - 1.0


## [surface ("slab" or "sand"), sRGB colour] of the floor cell centred at (x, z).
func _paint(id: String, layout: Dictionary, x: float, z: float) -> Array:
	var board := _board(layout)
	var inside: bool = absf(x) < board.x and absf(z) < board.y
	var edge: float = minf(board.x - absf(x), board.y - absf(z))  # > 0 inside the board
	var seed_value := int(layout.seed)
	var tone := _slab_tone(x, z, seed_value)
	var ripple := sin(x * 0.9 + sin(z * 0.7) * 1.6) * 0.5 + sin(z * 1.3 - x * 0.4) * 0.5
	match id:
		"mummy_pyramid_gate":
			var causeway: bool = absf(z) < 1.75 and absf(x) < 13.0 or (absf(x) < 1.6 and z < 0.0)
			if inside:
				if causeway:
					if absf(z) > 1.5 and absf(x) > 1.6 or (absf(x) > 1.35 and absf(x) < 1.6 and z < -1.75):
						return ["slab", STONE.lerp(STONE_DARK, 0.55)]  # the causeway's kerb stones
					return ["slab", STONE.lerp(STONE_DARK, 0.18 + tone * 0.12)]
				return ["sand", SAND.lerp(SAND_DARK, 0.25 + ripple * 0.25)]
			if edge > -0.25:
				return ["slab", TEAL]  # the board's teal kerb
			if absf(x) < 4.5 and z < -4.8 and z > -9.0:
				return ["slab", STONE.lerp(STONE_DARK, 0.25 + tone * 0.12)]  # forecourt before the pylon gate
			return ["sand", SAND.lerp(SAND_DARK, 0.15 + ripple * 0.2)]
		"mummy_pyramid_hall":
			if inside:
				if edge < 0.25:
					return ["slab", TEAL]
				if edge < 0.5:
					return ["slab", GOLD]
				if absf(z) < 0.75:
					return ["slab", RED_OCHRE.lerp(STONE_DARK, 0.25)]
				if absf(z) < 1.0:
					return ["slab", GOLD.lerp(STONE_DARK, 0.3)]
				return ["slab", STONE_DARK.lerp(STONE, 0.28 + tone * 0.14)]
			return ["slab", STONE_DARK.lerp(BASALT, 0.45 + tone * 0.1)]
		"mummy_pyramid_sanctum":
			if inside:  # (the sun ring in the middle is an overlay polygon: _inlays)
				if edge < 0.25:
					return ["slab", TEAL]
				return ["slab", STONE.lerp(STONE_DARK, 0.42 + tone * 0.14)]
			return ["slab", STONE_DARK.lerp(BASALT, 0.3 + tone * 0.1)]
		_:
			return ["slab", STONE]


## Round inlays laid as polygons 1.2 cm over the board (smooth edges: the 0.25 m cells would stair-step them).
const INLAY_Y := BOARD_Y + 0.012


func _inlays(id: String, slab: Acc) -> void:
	match id:
		"mummy_pyramid_sanctum":  # a gold sun ring with twelve teal-gold rays and a gold heart
			slab.ring(0.0, 0.0, INLAY_Y, 0.001, 2.05, lin(TEAL_DARK.lerp(STONE_DARK, 0.45)), 48)
			slab.ring(0.0, 0.0, INLAY_Y + 0.002, 2.05, 2.35, lin(GOLD), 64)
			for k in 12:
				var a := TAU * float(k) / 12.0
				slab.ring(0.0, 0.0, INLAY_Y + 0.002, 0.75, 1.85, lin(GOLD.lerp(TEAL, 0.35)), 1, a - 0.07, a + 0.07)
			slab.ring(0.0, 0.0, INLAY_Y + 0.004, 0.001, 0.55, lin(GOLD), 32)


## Height of the terrace (outside the board) at (x, z): the terrace level plus dunes on the desert gate.
func _terrain_y(id: String, layout: Dictionary, x: float, z: float) -> float:
	var board := _board(layout)
	var out: float = maxf(absf(x) - board.x, absf(z) - board.y)
	if out <= 0.0:
		return BOARD_Y
	var y := EDGE_Y
	if id == "mummy_pyramid_gate":
		var rise := smoothstep(1.2, 3.5, out)
		if id == "mummy_pyramid_gate" and absf(x) < 4.5 and z < -4.6:
			rise = 0.0  # the paved forecourt stays flat
		if id == "mummy_pyramid_gate" and absf(z) < 1.8:
			rise *= 0.25  # the causeway runs on
		if layout.get("island", false) and z > board.y:
			rise *= 0.45  # (island) the sand drifts against the walls; the open front stays low
		if layout.get("island", false) and absf(x) < 4.5 and z < -board.y:
			rise = 0.0  # (island) the forecourt before the gate
		var dune := 0.55 + 0.45 * sin(x * 0.55 + 1.3) * sin(z * 0.8 - 0.4)
		y += rise * dune * 0.75
	return y


## Grid lines from a0 to a1: 0.5 m steps up to b0, 0.25 m steps from b0 to b1, 0.5 m steps to a1 (each run ends exactly).
static func _breaks(a0: float, b0: float, b1: float, a1: float) -> Array:
	var out: Array = [a0]
	for run in [[b0, 0.5], [b1, 0.25], [a1, 0.5]]:
		var start: float = out[-1]
		var end: float = run[0]
		var count := maxi(1, int(round((end - start) / float(run[1]))))
		for k in count:
			out.append(lerpf(start, end, float(k + 1) / count))
	return out


func _floor_mesh(id: String, layout: Dictionary) -> ArrayMesh:
	var slab := Acc.new()
	var sand := Acc.new()
	var area := _extents(id, layout)
	var board := _board(layout)
	# Cells: 0.25 m across the board (crisp inlays), 0.5 m on the terrace; the grid lines land on the board's edges.
	var xs := _breaks(area.position.x, -board.x, board.x, area.end.x)
	var zs := _breaks(area.position.y, -board.y, board.y, area.end.y)
	for j in zs.size() - 1:
		var z: float = zs[j]
		var sz: float = zs[j + 1] - z
		for k in xs.size() - 1:
			var x: float = xs[k]
			var step: float = xs[k + 1] - x
			var cx := x + step * 0.5
			var cz := z + sz * 0.5
			var painted := _paint(id, layout, cx, cz)
			var color := lin(painted[1])
			var inside: bool = absf(cx) < board.x and absf(cz) < board.y
			var corners := [Vector2(x, z), Vector2(x + step, z), Vector2(x + step, z + sz), Vector2(x, z + sz)]
			var p := []
			for corner in corners:
				var y := BOARD_Y if inside else _terrain_y(id, layout, corner.x, corner.y)
				if not inside:
					y = maxf(y, EDGE_Y)
				p.append(Vector3(corner.x, y, corner.y))
			var acc: Acc = slab if painted[0] == "slab" else sand
			var metres := 4.0 if painted[0] == "slab" else 5.0
			var uvs := corners.map(func(q): return Vector2(q.x + 1.0, q.y) / metres)
			# (x, z) -> (x+step, z) -> (x+step, z+sz) -> (x, z+sz): counter-clockwise seen from above = up-facing
			acc.quad(p[0], p[3], p[2], p[1], color, [uvs[0], uvs[3], uvs[2], uvs[1]])
	_inlays(id, slab)
	# The step from the board up to the terrace: gold trim faces facing into the board.
	var trim := lin(GOLD.lerp(STONE_DARK, 0.25))
	var bx := board.x
	var bz := board.y
	var faces := [
		[Vector3(bx, 0, -bz), Vector3(-bx, 0, -bz)],  # north edge, faces south (+z)
		[Vector3(-bx, 0, bz), Vector3(bx, 0, bz)],  # south edge, faces north
		[Vector3(-bx, 0, -bz), Vector3(-bx, 0, bz)],  # west edge, faces east
		[Vector3(bx, 0, bz), Vector3(bx, 0, -bz)],  # east edge, faces west
	]
	for f in faces:
		var a: Vector3 = f[0]
		var b: Vector3 = f[1]
		var length := a.distance_to(b)
		slab.quad(a + Vector3(0, EDGE_Y, 0), b + Vector3(0, EDGE_Y, 0), b + Vector3(0, BOARD_Y, 0), a + Vector3(0, BOARD_Y, 0), trim,
			[Vector2(0, 0), Vector2(length / 4.0, 0), Vector2(length / 4.0, 0.03), Vector2(0, 0.03)])
	# The island's cliff skirt: the terrace's outer edge drops 1.3 m (sand surface, darker).
	var skirt := lin(SAND_DARK.lerp(STONE_DARK, 0.5))
	var x0 := area.position.x
	var x1 := area.end.x
	var z0 := area.position.y
	var z1 := area.end.y
	var ring := [[Vector3(x0, 0, z1), Vector3(x1, 0, z1)], [Vector3(x1, 0, z1), Vector3(x1, 0, z0)], [Vector3(x1, 0, z0), Vector3(x0, 0, z0)], [Vector3(x0, 0, z0), Vector3(x0, 0, z1)]]
	for f in ring:
		var a: Vector3 = f[0]
		var b: Vector3 = f[1]
		var segments := int(ceil(a.distance_to(b) / 0.5))
		for s in segments:
			var p0: Vector3 = a.lerp(b, float(s) / segments)
			var p1: Vector3 = a.lerp(b, float(s + 1) / segments)
			var y0 := maxf(_terrain_y(id, layout, p0.x, p0.z), EDGE_Y)
			var y1 := maxf(_terrain_y(id, layout, p1.x, p1.z), EDGE_Y)
			var top0 := Vector3(p0.x, y0, p0.z)
			var top1 := Vector3(p1.x, y1, p1.z)
			# outward facing: going counter-clockwise around the rect seen from above, outward is to the right
			if layout.get("island", false):
				# The island's fascia (the goblin island's soil band): a dressed-stone course with a dark joint under
				# the terrace, then rough sandstone down to where client/arena_props.gd's rock underside starts.
				var course := lin(STONE.lerp(SAND_DARK, 0.35) if id == "mummy_pyramid_gate" else STONE_DARK.lerp(STONE, 0.15))
				var joint := lin(STONE_DARK.lerp(BASALT, 0.5))
				var rough := lin(SAND_DARK.lerp(Color(0.42, 0.34, 0.28), 0.55))
				var bands := [[top0.y, top1.y, -0.32, course], [-0.32, -0.32, -0.4, joint], [-0.4, -0.4, -1.0, rough]]
				for band in bands:
					sand.quad(Vector3(p0.x, band[0], p0.z), Vector3(p0.x, band[2], p0.z), Vector3(p1.x, band[2], p1.z), Vector3(p1.x, band[1], p1.z), band[3],
						[Vector2(s * 0.125, band[0] * 0.25), Vector2(s * 0.125, band[2] * 0.25), Vector2((s + 1) * 0.125, band[2] * 0.25), Vector2((s + 1) * 0.125, band[1] * 0.25)])
				continue
			sand.quad(top0, Vector3(p0.x, -1.3, p0.z), Vector3(p1.x, -1.3, p1.z), top1, skirt,
				[Vector2(s * 0.1, 0), Vector2(s * 0.1, 0.3), Vector2((s + 1) * 0.1, 0.3), Vector2((s + 1) * 0.1, 0)])
	var mesh := ArrayMesh.new()
	for pair in [[slab, SLAB_TEX, "mummy_floor_slab"], [sand, SAND_TEX, "mummy_floor_sand"]]:
		var acc: Acc = pair[0]
		if acc.v.is_empty():
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, acc.arrays())
		var material := StandardMaterial3D.new()
		material.resource_name = pair[2]
		material.albedo_texture = load(pair[1])
		material.vertex_color_use_as_albedo = true
		material.vertex_color_is_srgb = false
		material.roughness = 1.0
		material.metallic_specular = 0.05
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh


## ---- the dressing (architecture built from primitives, one vertex-coloured surface) ------------------------------

var _dress: Acc


func _prim(m: PrimitiveMesh, at: Vector3, color: Color, basis: Basis = Basis.IDENTITY) -> void:
	_dress.mesh(m, 0, Transform3D(basis, at), lin(color))


## A box standing on y0 (bottom) centred at (x, z).
func _box(x: float, y0: float, z: float, sx: float, sy: float, sz: float, color: Color, yaw_degrees: float = 0.0) -> void:
	var m := BoxMesh.new()
	m.size = Vector3(sx, sy, sz)
	_prim(m, Vector3(x, y0 + sy * 0.5, z), color, Basis(Vector3.UP, deg_to_rad(yaw_degrees)))


## A disc (a flat cylinder) facing +z (south) or +x (east), centred at `at`.
func _disc(at: Vector3, radius: float, depth: float, color: Color, facing_east: bool = false) -> void:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = depth
	m.radial_segments = 16
	m.rings = 1
	var basis := Basis(Vector3.RIGHT, PI * 0.5) if not facing_east else Basis(Vector3.FORWARD, PI * 0.5)
	_prim(m, at, color, basis)


## A tapered block (a pylon / obelisk body): a cylinder with 4 sides, rotated 45 degrees so its faces are axis-aligned.
func _pylon(x: float, y0: float, z: float, bottom: float, top: float, height: float, color: Color, depth_ratio: float = 1.0) -> void:
	var m := CylinderMesh.new()
	m.bottom_radius = bottom * 0.7071
	m.top_radius = top * 0.7071
	m.height = height
	m.radial_segments = 4
	m.rings = 1
	var basis := Basis(Vector3.UP, PI * 0.25).scaled(Vector3(1.0, 1.0, 1.0))
	basis = Basis.from_scale(Vector3(1.0, 1.0, depth_ratio)) * basis
	_prim(m, Vector3(x, y0 + height * 0.5, z), color, basis)


## The obstacle's dressing: it encloses the collider box (x COVER_PAD), so the stage's plain collider box never shows.
func _cover(c: Array) -> void:
	var x: float = c[0]
	var z: float = c[1]
	var sx: float = float(c[2]) * COVER_PAD
	var h: float = float(c[3]) * 1.01
	var sz: float = float(c[4]) * COVER_PAD
	match str(c[5]):
		"block":  # a toppled sandstone block with a teal hieroglyph band
			_box(x, 0.0, z, sx, h, sz, STONE.lerp(SAND_DARK, 0.3))
			_box(x, h * 0.55, z, sx + 0.04, 0.22, sz + 0.04, TEAL)
			_box(x + sx * 0.18, h, z - sz * 0.1, sx * 0.5, 0.12, sz * 0.55, STONE)
		"stump":  # a broken column: square base, drum, a gold-banded capital fragment
			_box(x, 0.0, z, sx, 0.3, sz, STONE_DARK)
			_box(x, 0.3, z, sx * 0.98, h - 0.3, sz * 0.98, STONE.lerp(STONE_DARK, 0.2))
			_box(x, h - 0.35, z, sx + 0.06, 0.12, sz + 0.06, GOLD)
			_box(x, h - 0.2, z, sx * 0.9, 0.2, sz * 0.9, TEAL_DARK)
		"sarcophagus":  # a closed stone sarcophagus: body, gold rim, teal lid
			_box(x, 0.0, z, sx, h - 0.25, sz, STONE.lerp(STONE_DARK, 0.25))
			_box(x, h - 0.32, z, sx + 0.06, 0.08, sz + 0.06, GOLD)
			_box(x, h - 0.25, z, sx, 0.25, sz, TEAL_DARK)
			_box(x, h - 0.02, z, sx * 0.7, 0.06, sz * 0.4, GOLD)
		_:
			push_error("unknown cover style " + str(c[5]))


func _dressing(id: String, layout: Dictionary) -> void:
	for c in layout.cover:
		_cover(c)
	var y := EDGE_Y
	match id:
		"mummy_pyramid_gate":
			# The island's enclosure: a weathered sandstone wall north, east and west, crenellated, broken heights on
			# the sides, half buried in the drifts; the front stays an open cliff (the camera side).
			var sandstone := STONE.lerp(SAND, 0.35)
			var coping := STONE.lerp(SAND_DARK, 0.2)
			for side in [-1.0, 1.0]:
				_wall_x(side * 4.3, side * (WALL_X + 0.4), WALL_N, 2.3, 0.8, sandstone, coping, "crenel")
				_wall_z(side * WALL_X, WALL_N + 0.4, WALL_END, 1.6, 0.7, sandstone, coping, "ruin", 1 if side > 0 else 0)
				_pier(side * WALL_X, WALL_END + 0.5, 0.95, 2.1, sandstone, GOLD_DIM)
			# The pylon gateway in the north wall: two tapered towers, the lintel, the dark door with a gold sun disc.
			for side in [-1.0, 1.0]:
				_pylon(side * 3.0, y, -7.0, 2.6, 2.0, 4.4, STONE.lerp(SAND, 0.3), 0.6)
				_box(side * 3.0, y + 3.3, -6.55, 2.2, 0.28, 0.12, TEAL)
				_box(side * 3.0, y + 3.65, -6.55, 2.1, 0.12, 0.1, GOLD)
			_box(0.0, y + 3.0, -7.0, 3.6, 0.8, 1.3, STONE)
			_box(0.0, y + 3.35, -6.32, 3.7, 0.18, 0.1, TEAL)
			_box(0.0, y, -7.0, 2.6, 3.0, 0.5, DOOR)
			_disc(Vector3(0.0, y + 3.4, -6.26), 0.42, 0.06, GOLD)
			# Two small pyramids with gold capstones in the back corners (the goblin island's corner towers).
			for side in [-1.0, 1.0]:
				_pylon(side * 9.7, y, -6.0, 2.9, 0.0, 2.6, SAND.lerp(STONE, 0.45))
				_pylon(side * 9.7, y + 2.15, -6.0, 0.5, 0.0, 0.45, GOLD)
				_box(side * 7.4, y, -5.75, 0.8, 0.42, 0.8, STONE.lerp(SAND_DARK, 0.2))  # the Anubis statues' plinths
				_box(side * 7.4, y + 0.3, -5.75, 0.84, 0.06, 0.84, TEAL)
			# Banners: on the north wall beside the gate, on the side walls.
			for bx in [-6.6, 6.6]:
				_banner(Vector3(bx, y + 0.35, WALL_N + 0.42), false, RED_OCHRE)
			for side in [-1.0, 1.0]:
				_banner(Vector3(side * (WALL_X - 0.37), y + 0.2, -2.6), true, TEAL, -side, 1.15)
			# Front margin: fallen blocks, a broken capstone, two palms at the cliff corners, scrub tufts.
			for b in [[-8.6, 6.3, 0.9, 0.55, 0.7, 20.0], [-9.3, 7.0, 0.6, 0.4, 0.6, -15.0], [8.1, 6.9, 0.8, 0.5, 0.8, 35.0], [-0.6, 6.9, 0.7, 0.35, 0.5, 10.0]]:
				_box(b[0], _terrain_y(id, layout, b[0], b[1]) - 0.08, b[1], b[2], b[3], b[4], STONE.lerp(SAND, 0.25), b[5])
			for p in [[-10.9, 6.9, 0.25], [10.7, 5.6, -0.3]]:
				_palm(p[0], p[1], p[2], _terrain_y(id, layout, p[0], p[1]))
			_scrub(id, layout, 18)
		"mummy_pyramid_hall":
			# The hall wall (north, high) with an architrave over the colonnade and a gold-framed doorway, lower side
			# walls with a frieze, square pylon towers in the back corners; the front stays an open cliff.
			var wall_col := STONE_DARK.lerp(STONE, 0.25)
			_wall_x(-WALL_X - 0.4, WALL_X + 0.4, WALL_N, 4.4, 0.8, wall_col, STONE.lerp(STONE_DARK, 0.15), "plain")
			_box(0.0, y + 3.6, -5.6, 17.0, 0.55, 1.3, STONE.lerp(STONE_DARK, 0.15))
			_box(0.0, y + 3.72, -4.93, 17.0, 0.18, 0.06, TEAL)
			_box(0.0, y + 3.95, -4.93, 17.0, 0.06, 0.06, GOLD)
			_box(0.0, y + 1.0, WALL_N + 0.42, 21.0, 0.5, 0.06, TEAL_DARK)
			_box(0.0, y + 1.55, WALL_N + 0.42, 21.0, 0.08, 0.06, GOLD)
			# The doorway between the middle columns: a deep dark recess in a gold frame.
			_box(0.0, y, WALL_N + 0.45, 2.3, 3.0, 0.12, GOLD_DIM)
			_box(0.0, y, WALL_N + 0.5, 1.9, 2.8, 0.06, DOOR)
			_box(0.0, y + 3.0, WALL_N + 0.5, 2.6, 0.25, 0.14, TEAL)
			for side in [-1.0, 1.0]:
				_wall_z(side * WALL_X, WALL_N + 0.4, WALL_END, 2.6, 0.7, STONE_DARK.lerp(STONE, 0.2), STONE.lerp(STONE_DARK, 0.3), "plain")
				var inner: float = side * (WALL_X - 0.37)
				_box(inner, y + 1.0, (WALL_N + WALL_END) * 0.5, 0.06, 0.4, WALL_END - WALL_N - 0.4, TEAL_DARK)
				_box(inner, y + 1.45, (WALL_N + WALL_END) * 0.5, 0.06, 0.07, WALL_END - WALL_N - 0.4, GOLD)
				_pier(side * WALL_X, WALL_END + 0.5, 0.95, 3.0, STONE_DARK.lerp(STONE, 0.3), GOLD_DIM)
				# The corner pylon tower: tapered, a teal band and a gold cap.
				_pylon(side * 10.6, y, -6.6, 1.9, 1.5, 4.9, STONE_DARK.lerp(STONE, 0.35))
				_box(side * 10.6, y + 3.6, -6.6, 1.75, 0.3, 1.75, TEAL)
				_box(side * 10.6, y + 4.9, -6.6, 1.7, 0.2, 1.7, GOLD_DIM)
				_box(side * 10.0, y, -2.8 + 0.0, 0.8, 0.36, 0.8, BASALT)  # the Anubis statues' plinths
				_box(side * 10.0, y + 0.3, -2.8 + 0.0, 0.84, 0.06, 0.84, GOLD)
			for bx in [-6.0, 6.0]:
				_banner(Vector3(bx, y + 1.0, WALL_N + 0.45), false, LAPIS)
			for side in [-1.0, 1.0]:
				_banner(Vector3(side * (WALL_X - 0.37), y + 0.4, -4.4), true, LAPIS, -side)
			# Front margin: column drums and a broken capital beside the fallen column (kit), scattered slabs.
			for b in [[-2.7, 6.5, 0.8, 0.5, 0.8, 0.0], [-7.6, 6.9, 0.75, 0.45, 0.75, 25.0], [4.4, 6.8, 0.9, 0.3, 0.9, 15.0]]:
				_box(b[0], y, b[1], b[2], b[3], b[4], STONE.lerp(STONE_DARK, 0.3), b[5])
			_box(-2.7, y + 0.5, 6.5, 0.84, 0.08, 0.84, GOLD_DIM)
		"mummy_pyramid_sanctum":
			# The coffin wall (north): deep alcoves between piers, a gold frieze, a gold sun disc over the altar;
			# basalt side walls, gold-tipped obelisks in the back corners; the front stays an open cliff.
			var basalt := STONE_DARK.lerp(BASALT, 0.2)
			_wall_x(-WALL_X - 0.4, WALL_X + 0.4, WALL_N, 4.4, 0.8, basalt, STONE.lerp(STONE_DARK, 0.2), "plain")
			for k in 7:
				var px := -9.4 + float(k) * 2.0
				if absf(px) < 3.5:
					continue
				_box(px, y, -6.7, 0.45, 3.4, 0.8, STONE_DARK.lerp(STONE, 0.3))
			_box(0.0, y + 3.4, -6.7, 21.0, 0.35, 0.9, STONE.lerp(STONE_DARK, 0.2))
			_box(0.0, y + 3.5, -6.23, 21.0, 0.14, 0.05, GOLD)
			# The sarcophagus dais, a gold sun disc over it.
			_box(0.0, y, -5.85, 4.6, 0.3, 2.3, BASALT)
			_box(0.0, y + 0.3, -5.85, 4.0, 0.06, 1.9, GOLD)
			_disc(Vector3(0.0, y + 3.0, WALL_N + 0.45), 0.9, 0.08, GOLD)
			_disc(Vector3(0.0, y + 3.0, WALL_N + 0.5), 0.55, 0.08, TEAL)
			for side in [-1.0, 1.0]:
				_wall_z(side * WALL_X, WALL_N + 0.4, WALL_END, 3.0, 0.8, basalt, STONE_DARK.lerp(STONE, 0.3), "plain")
				_pier(side * WALL_X, WALL_END + 0.5, 1.0, 3.4, BASALT, GOLD)
				# The corner obelisks: tall, a teal band, a gold tip.
				_pylon(side * 10.4, y, -6.2, 1.2, 0.75, 5.2, STONE_DARK.lerp(STONE, 0.4))
				_pylon(side * 10.4, y + 5.2, -6.2, 0.75, 0.0, 0.6, GOLD)
				_box(side * 10.4, y + 3.4, -6.2, 0.98, 0.22, 0.98, TEAL)
				_banner(Vector3(side * (WALL_X - 0.42), y + 0.6, 0.6), true, TEAL, -side)
			# Front margin: the tomb's treasure (gold heaps beside the chests), a fallen lid.
			for g in [[-5.2, 6.4, 0.5], [-5.6, 6.9, 0.35], [7.2, 6.3, 0.45], [5.4, 7.1, 0.3]]:
				var heap := SphereMesh.new()
				heap.radius = g[2]
				heap.height = g[2] * 0.7
				heap.radial_segments = 10
				heap.rings = 4
				_prim(heap, Vector3(g[0], y, g[1]), GOLD)


## ---- island enclosure pieces (the goblin island's palisade / towers / banners, in stone) ----------------------

## A wall along x from x0 to x1 at z, standing on the terrace: ~2 m sections, a pier at each joint, a coping on top.
## style "crenel": merlons on the coping; "ruin": broken section heights; "plain": none.
func _wall_x(x0: float, x1: float, z: float, h: float, t: float, body: Color, coping: Color, style: String, seed_value: int = 0) -> void:
	_wall_run(Vector2(minf(x0, x1), z), Vector2(maxf(x0, x1), z), h, t, body, coping, style, seed_value)


func _wall_z(x: float, z0: float, z1: float, h: float, t: float, body: Color, coping: Color, style: String, seed_value: int = 0) -> void:
	_wall_run(Vector2(x, minf(z0, z1)), Vector2(x, maxf(z0, z1)), h, t, body, coping, style, seed_value)


func _wall_run(a: Vector2, b: Vector2, h: float, t: float, body: Color, coping: Color, style: String, seed_value: int) -> void:
	var along_x := absf(b.x - a.x) > absf(b.y - a.y)
	var length := a.distance_to(b)
	var count := maxi(1, int(round(length / 2.0)))
	var step := length / count
	var y := EDGE_Y
	for k in count:
		var c := a.lerp(b, (float(k) + 0.5) / count)
		var hk := h
		if style == "ruin":
			hk = h * [1.0, 0.7, 0.9, 0.55, 0.85, 1.0, 0.65][(k + seed_value * 3) % 7]
		var sx := step if along_x else t
		var sz := t if along_x else step
		_box(c.x, y - 0.3, c.y, sx, hk + 0.3, sz, body.lerp(STONE_DARK, 0.06 * float(k % 2)))
		_box(c.x, y + hk, c.y, sx + (0.0 if along_x else 0.1), 0.14, sz + (0.1 if along_x else 0.0), coping)
		if style == "crenel":
			for m in [-0.25, 0.25]:
				var o := Vector2(m * step, 0.0) if along_x else Vector2(0.0, m * step)
				_box(c.x + o.x, y + hk + 0.14, c.y + o.y, (0.5 if along_x else t * 0.8), 0.3, (t * 0.8 if along_x else 0.5), coping)
	for k in count + 1:
		var p := a.lerp(b, float(k) / count)
		var hk2 := h + 0.25
		if style == "ruin":
			hk2 = h * [1.1, 0.8, 1.0, 0.7, 0.95, 1.1, 0.75][(k + seed_value * 3) % 7] + 0.2
		_box(p.x, y - 0.3, p.y, t + 0.2, hk2 + 0.3, t + 0.2, body.lerp(STONE_DARK, 0.2))


## A free-standing pier ending a side wall at the open front (the goblin island's front corner pieces).
func _pier(x: float, z: float, width: float, h: float, body: Color, cap: Color) -> void:
	_pylon(x, EDGE_Y - 0.3, z, width, width * 0.8, h + 0.3, body)
	_box(x, EDGE_Y + h, z, width * 0.9, 0.16, width * 0.9, cap)


## A hanging banner on a wall face: cloth, gold top rod and hem, a gold sun emblem. `on_side`: on a side wall (the cloth
## lies in the yz plane, `facing` = +1 east / -1 west), else on the north wall facing south.
func _banner(top_left: Vector3, on_side: bool, cloth: Color, facing: float = 1.0, h: float = 2.0) -> void:
	var w := 0.95
	var c := top_left
	if on_side:
		_box(c.x, c.y, c.z, 0.05, h, w, cloth)
		_box(c.x + facing * 0.03, c.y + h - 0.08, c.z, 0.06, 0.1, w + 0.2, GOLD)
		_box(c.x + facing * 0.03, c.y, c.z, 0.06, 0.12, w, GOLD)
		_disc(Vector3(c.x + facing * 0.04, c.y + h * 0.62, c.z), 0.24, 0.03, GOLD, true)
	else:
		_box(c.x, c.y, c.z, w, h, 0.05, cloth)
		_box(c.x, c.y + h - 0.08, c.z + 0.03, w + 0.2, 0.1, 0.06, GOLD)
		_box(c.x, c.y, c.z + 0.03, w, 0.12, 0.06, GOLD)
		_disc(Vector3(c.x, c.y + h * 0.62, c.z + 0.04), 0.24, 0.03, GOLD)


## A date palm (a leaning trunk of stacked drums, a crown of drooping fronds), standing at ground height y.
func _palm(x: float, z: float, lean: float, y: float) -> void:
	var top := Vector3(x, y, z)
	var dir := Vector3(sin(lean) * 0.35, 1.0, 0.0).normalized()
	for k in 6:
		var drum := CylinderMesh.new()
		drum.top_radius = 0.13 - k * 0.008
		drum.bottom_radius = 0.17 - k * 0.008
		drum.height = 0.5
		drum.radial_segments = 6
		drum.rings = 1
		var basis := Basis(Vector3.FORWARD, -lean * 0.35)
		_prim(drum, top + dir * 0.25, Color(0.45, 0.33, 0.22).lerp(Color(0.36, 0.26, 0.17), float(k % 2)), basis)
		top += dir * 0.48
	for k in 7:
		var a := TAU * float(k) / 7.0
		var frond := BoxMesh.new()
		frond.size = Vector3(1.5, 0.05, 0.36)
		var basis := Basis(Vector3.UP, a) * Basis(Vector3.FORWARD, deg_to_rad(-28.0))
		_prim(frond, top + Basis(Vector3.UP, a) * Vector3(0.65, -0.18, 0.0), Color(0.36, 0.52, 0.28).lerp(Color(0.26, 0.42, 0.24), float(k % 2)), basis)


## Dry desert scrub tufts (small low cones) scattered on the margin only, never on the board.
func _scrub(id: String, layout: Dictionary, count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var placed := 0
	while placed < count:
		var x := rng.randf_range(-ISLAND_W + 0.5, ISLAND_W - 0.5)
		var z := rng.randf_range(-3.5, ISLAND_D - 0.5)
		if absf(x) < W + 0.6 and absf(z) < D + 0.6:
			continue
		if absf(x) > WALL_X - 0.8 and z < WALL_END + 1.0:
			continue
		var tuft := CylinderMesh.new()
		tuft.top_radius = 0.0
		tuft.bottom_radius = 0.22 + rng.randf() * 0.12
		tuft.height = 0.3 + rng.randf() * 0.2
		tuft.radial_segments = 5
		tuft.rings = 1
		_prim(tuft, Vector3(x, _terrain_y(id, layout, x, z) + tuft.height * 0.4, z), Color(0.50, 0.52, 0.30).lerp(Color(0.62, 0.56, 0.34), rng.randf()))
		placed += 1


## ---- the kit (merged) ---------------------------------------------------------------------------------------------

func _kit_mesh(layout: Dictionary) -> ArrayMesh:
	var stone := Acc.new()
	var fire := Acc.new()
	var per_map := lin(Color(0.93, 0.88, 0.80)) if str(layout.mood) == "night" else lin(Color(1.0, 0.95, 0.88))
	for row in layout.kit:
		var kit_name: String = row[0]
		var mesh: Mesh = kit_meshes[kit_name]
		var basis := Basis(Vector3.UP, deg_to_rad(float(row[3])))
		if row.size() > 7:
			basis = basis * Basis(Vector3.RIGHT, deg_to_rad(float(row[7])))
		basis = basis.scaled(Vector3.ONE * float(row[4]))
		var ground_y := float(row[5])
		if layout.get("island", false) and is_equal_approx(ground_y, EDGE_Y):
			ground_y = _terrain_y(str(layout.get("id", "")), layout, float(row[1]), float(row[2])) - 0.04  # stands on the dune
		row = row.duplicate()
		row[5] = ground_y
		var xf := Transform3D(basis, Vector3(float(row[1]), float(row[5]), float(row[2])))
		if row.size() > 7:
			# a piece laid down: lift it so its lowest point rests on y
			var box := xf * mesh.get_aabb()
			xf.origin.y += float(row[5]) - box.position.y
			box = xf * mesh.get_aabb()
			xf.origin.x += float(row[1]) - box.get_center().x
			xf.origin.z += float(row[2]) - box.get_center().z
		var tint: Color = lin(row[6]) * per_map if row.size() > 6 else per_map
		for s in mesh.get_surface_count():
			var material := mesh.surface_get_material(s)
			var is_fire := material != null and str(material.resource_name).ends_with("_fire")
			(fire if is_fire else stone).mesh(mesh, s, xf, WHITE if is_fire else tint)
	var out := ArrayMesh.new()
	var stone_material := StandardMaterial3D.new()
	stone_material.resource_name = "mummy_stone"
	stone_material.albedo_texture = load(KIT_ALBEDO)
	stone_material.vertex_color_use_as_albedo = true
	stone_material.vertex_color_is_srgb = false
	stone_material.roughness = 0.95
	stone_material.metallic_specular = 0.1
	var fire_material := StandardMaterial3D.new()
	fire_material.resource_name = "mummy_fire"  # *_fire: shown unshaded (stage_props._is_emissive)
	fire_material.albedo_color = Color(1.0, 0.62, 0.22)
	fire_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for pair in [[stone, stone_material], [fire, fire_material]]:
		var acc: Acc = pair[0]
		if acc.v.is_empty():
			continue
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, acc.arrays())
		out.surface_set_material(out.get_surface_count() - 1, pair[1])
	return out


## ---- the scene ---------------------------------------------------------------------------------------------------

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


func _build_scene(id: String, layout: Dictionary, map: Dictionary) -> Dictionary:
	var root_node := Node3D.new()
	root_node.name = id
	if layout.get("island", false):
		root_node.set_meta("floating_island", true)  # client/arena_props.gd is_pyramid_island: the goblin-style island
	var floor_mesh := _save_mesh(_floor_mesh(id, layout), MESH_DIR + id + "_floor.res")
	_dress = Acc.new()
	_dressing(id, layout)
	var dress_mesh := ArrayMesh.new()
	dress_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _dress.arrays())
	var dress_material := StandardMaterial3D.new()
	dress_material.resource_name = "mummy_dressing"
	dress_material.vertex_color_use_as_albedo = true
	dress_material.vertex_color_is_srgb = false
	dress_material.roughness = 0.92
	dress_material.metallic_specular = 0.15
	dress_mesh.surface_set_material(0, dress_material)
	dress_mesh = _save_mesh(dress_mesh, MESH_DIR + id + "_dressing.res")
	var kit_mesh := _save_mesh(_kit_mesh(layout), MESH_DIR + id + "_kit.res")
	if floor_mesh == null or dress_mesh == null or kit_mesh == null:
		return {}
	var ground := _instance(root_node, "PyramidFloor", floor_mesh)
	ground.set_meta("toon_no_outline", true)  # flat: the drawn style gives it no ink hull (a second whole-floor draw)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_instance(root_node, "Dressing", dress_mesh)
	_instance(root_node, "Kit", kit_mesh)
	var index := {}
	for light in layout.lights:
		var kind: String = light[0]
		var marker := Node3D.new()
		marker.name = "%s%d" % [kind, int(index.get(kind, 0))]
		index[kind] = int(index.get(kind, 0)) + 1
		marker.position = Vector3(float(light[1]), float(light[2]), float(light[3]))
		root_node.add_child(marker)
		marker.owner = root_node
	# Semantic markers from the same gameplay data (as the goblin builder): spawn, enemy_N, cover_N.
	var points := [["spawn", map.spawn]]
	for k in map.enemy_spawns.size():
		points.append(["enemy_%d" % k, map.enemy_spawns[k].position])
	for p in points:
		var marker := Node3D.new()
		marker.name = p[0]
		marker.position = Vector3(float(p[1][0]), float(p[1][1]), float(p[1][2]))
		root_node.add_child(marker)
		marker.owner = root_node
	var tris := 0
	var surfaces := 0
	for mesh in [floor_mesh, dress_mesh, kit_mesh]:
		for s in mesh.get_surface_count():
			tris += mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
			surfaces += 1
	var bytes := 0
	for suffix in ["_floor.res", "_dressing.res", "_kit.res"]:
		bytes += FileAccess.get_file_as_bytes(MESH_DIR + id + suffix).size()
	return {"root": root_node, "triangles": tris, "draw_surfaces": surfaces, "mesh_bytes": bytes, "lights": layout.lights.size()}


## The monster type a spot holds in this map's fixture (the journey brings the real waves): the four pyramid fight
## types, each only once it exists in the combat data (else the nearest existing one).
func _fixture_type(role: String) -> String:
	var wanted: Array = {"melee": ["mummy"], "knight": ["mummy_knight", "mummy"], "archer": ["mummy_archer"],
		"mage": ["mummy_mage", "mummy_archer"]}[role]
	for t in wanted:
		if combat_ids.has(t):
			return t
	return str(wanted[-1])


func _map_json(id: String, layout: Dictionary) -> Dictionary:
	var d := {
		"version": 1, "id": id, "name": layout.name,
		"_design": "Mummy Pyramid zone (level-designer 2026-11-17; Boss: mummies live ONLY here; finished to the goblin camp's level 2026-11-17). Generated by tools/maps/build_mummy_pyramid.gd (edit the script, not this file): " + str(layout.design) + " Monster ids/levels here are a fixture: the real waves come from data/journeys/mummy_waves.json and take the spots in list order (melee, knights, then the ranged ones).",
		"modes": ["pve"],
	}
	d["kind"] = "fight"
	d["camera_style"] = "arena"
	d["atmosphere"] = "ink"
	d["art_scene"] = SCENE_DIR + id + ".tscn"
	d["art_mood"] = layout.mood
	d["bounds"] = {"half_width": W, "half_depth": D}
	d["spawn"] = [-5.6, 0.05, 0.0]
	var solids: Array = [{"center": [0, -0.2, 0], "size": [16.0, 0.4, 9.0], "material": "ink"}]
	for c in layout.cover:
		solids.append({"center": [c[0], float(c[3]) * 0.5, c[1]], "size": [c[2], c[3], c[4]], "material": "stone"})
	d["solids"] = solids
	var spawns: Array = []
	for s in layout.spots:
		spawns.append({"type": _fixture_type(str(s[0])), "level": 1, "position": [s[1], 0.05, s[2]]})
	d["enemy_spawns"] = spawns
	d["rest_points"] = []
	d["player_spawns"] = [[-5.6, 0.05, 0.0], [-4.6, 0.05, -2.2], [-4.6, 0.05, 2.2]]
	d["_arena"] = "Board 16 x 9 m like the goblin boards. Cover: %d low blocks (1.5-1.6 m: too high to jump on, low enough to see over) on the monster side; they stop projectiles both ways (logic/projectiles.gd) and the ranged monsters step aside for a clear line (logic/enemy_ai.gd). The middle and the squad's half stay open (logic/auto_pilot.gd walks straight at its target)." % layout.cover.size()
	d["_spots"] = "Spot roles in order: " + ", ".join(layout.spots.map(func(s): return str(s[0])))
	d["world_region"] = "pyramid"
	return d


func run() -> void:
	if not _load_kit():
		quit(1)
		return
	var combat = JSON.parse_string(FileAccess.get_file_as_string(COMBAT))
	if combat is Dictionary and combat.get("enemies") is Dictionary:
		combat_ids = combat.enemies.keys()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MESH_DIR))
	var all := layouts()
	var report := {}
	var only := OS.get_cmdline_user_args()
	for id in all:
		if not only.is_empty() and not only.has(id):
			continue
		var layout: Dictionary = all[id]
		layout["id"] = id
		var map := _map_json(id, layout)
		var built := _build_scene(id, layout, map)
		if built.is_empty():
			quit(1)
			return
		var packed := PackedScene.new()
		packed.pack(built.root)
		var scene_path: String = SCENE_DIR + id + ".tscn"
		if ResourceSaver.save(packed, scene_path) != OK:
			printerr("cannot save ", scene_path)
			quit(1)
			return
		built.root.free()
		var f := FileAccess.open(MAP_DIR + id + ".json", FileAccess.WRITE)
		f.store_string(JSON.stringify(map, "\t", false))
		f.close()
		report[id] = {"triangles": built.triangles, "draw_surfaces": built.draw_surfaces, "mesh_bytes": built.mesh_bytes,
			"scene_bytes": FileAccess.get_file_as_bytes(scene_path).size(), "lights": built.lights, "cover": layout.cover.size()}
		print("built ", id, " ", report[id])
	var manifest_path := SCENE_DIR + "manifest.json"
	var manifest: Dictionary = {}
	if FileAccess.file_exists(manifest_path):
		var old = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if old is Dictionary:
			manifest = old
	manifest.merge(report, true)
	for old_id in manifest.keys():
		if not all.has(old_id):
			manifest.erase(old_id)  # a removed map (2026-11-18: the pharaoh and rest variants) leaves the budget list
	var m := FileAccess.open(manifest_path, FileAccess.WRITE)
	m.store_string(JSON.stringify(manifest, "  "))
	m.close()
	print("MUMMY PYRAMID BUILT")
	quit()
