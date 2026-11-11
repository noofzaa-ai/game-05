extends Node3D
## Draws the simulation's projectiles and ground areas (logic/projectiles.gd) and plays their effects:
##   arrow       a wooden arrow turned along its flight, with a pale streak behind it
##   bolt        a glowing orb with a short tail of fading glows (magic)
##   hex_circle  a warning circle on the ground that fills up until it bursts (area_telegraph.gdshader)
## Releases, wall hits, bursts and blinks are effect keys in data/combat/vfx.json ("shot/<look>",
## "shot_end/<look>", "area_burst/<look>", "blink"), so they are prewarmed with every other effect.
## It only shows what the simulation says (positions come from the sim every physics tick).
## EXTENDING: a new projectile look is an entry in LOOKS plus a builder in _build_shot().

const Effects := preload("res://client/effects.gd")
const AREA_SHADER := preload("res://client/vfx/area_telegraph.gdshader")

## Client-side look of each kind (the rules only name the look).
const LOOKS := {
	"jade_arrow": {"color": Color("63d9b7")},
	"arrow": {"color": Color(0.95, 0.9, 0.75), "length": 0.8, "model": "res://art/monsters/goblin_archer/arrow.glb", "model_scale": 1.25},
	"bolt": {"color": Color(0.72, 0.4, 1.0), "size": 0.15},
	"hex_circle": {"color": Color(0.78, 0.36, 1.0)},
}
const TRAIL_GLOWS := 6  ## fading glows behind a magic bolt
const AREA_LIFT := 0.05  ## the circle floats this much above the ground (no flicker with the floor)

var effects: Effects  ## set by the stage: where the releases, impacts and bursts play

var _shots: Dictionary = {}  ## projectile id -> Node3D
var _areas: Dictionary = {}  ## area id -> MeshInstance3D
var _clock := 0.0
var _arrow_mesh: ArrayMesh  ## the code-built arrow, used only if the arrow model is missing
var _arrow_model_mesh: Mesh
var _arrow_model_material: Material
var _streak_mesh: ArrayMesh
var _arrow_material: StandardMaterial3D
var _streak_material: StandardMaterial3D
var _glow_material: StandardMaterial3D
var _core_material: StandardMaterial3D
var _quad: QuadMesh
var _sphere: SphereMesh


func _ready() -> void:
	_build_resources()


func _process(delta: float) -> void:
	_clock += delta
	for id in _areas:
		var material: ShaderMaterial = _areas[id].material_override
		material.set_shader_parameter("time", _clock)


## Matches the drawn projectiles and areas to the simulation's lists (call after each sim tick).
func show_state(sim) -> void:
	var seen := {}
	for shot in sim.projectiles:
		var id: int = shot["id"]
		seen[id] = true
		var node: Node3D = _shots.get(id)
		if node == null:
			node = _build_shot(str(sim.combat.projectiles[shot["def"]]["look"]))
			_shots[id] = node
		_place_shot(node, shot["pos"], shot["vel"])
	for id in _shots.keys():
		if not seen.has(id):
			_shots[id].queue_free()
			_shots.erase(id)
	var marked := {}
	for area in sim.areas:
		var id: int = area["id"]
		marked[id] = true
		var circle: MeshInstance3D = _areas.get(id)
		if circle == null:
			circle = _build_area(str(sim.combat.areas[area["def"]]["look"]), float(area["radius"]))
			circle.position = Vector3(area["pos"]) + Vector3(0.0, AREA_LIFT, 0.0)
			_areas[id] = circle
		var progress := clampf(float(area["age"]) / maxf(1.0, float(area["delay"])), 0.0, 1.0)
		circle.material_override.set_shader_parameter("progress", progress)
	for id in _areas.keys():
		if not marked.has(id):
			_areas[id].queue_free()
			_areas.erase(id)


## The effects of this tick's ranged events: the release, an impact where a shot stops, the burst
## of an area, a blink's puff at both ends.
func handle_events(events: Array, color_of: Callable) -> void:
	if effects == null:
		return
	for event in events:
		match str(event["type"]):
			"projectile_fired":
				var at: Vector3 = event["pos"]
				effects.play("shot/" + ("arrow" if str(event["look"])=="jade_arrow" else str(event["look"])), Effects.context(at, Vector3(at.x, at.y - 0.6, at.z), event["dir"], color_of.call(int(event["player"]))))
			"projectile_ended":
				if str(event["reason"]) == "blocked":
					continue  # (the block effect shows it)
				var end: Vector3 = event["pos"]
				var look: String = _look_of_shot(event)
				effects.play("shot_end/" + ("arrow" if look=="jade_arrow" else look), Effects.context(end, Vector3(end.x, maxf(0.0, end.y - 0.6), end.z), Vector2.RIGHT, LOOKS.get(look, {}).get("color", Color.WHITE)))
			"area_detonated":
				var center: Vector3 = event["pos"]
				effects.play("area_burst/" + str(event["look"]), Effects.context(center + Vector3(0.0, 0.6, 0.0), center, Vector2.RIGHT, LOOKS.get(str(event["look"]), {}).get("color", Color.WHITE), {"scale": float(event["radius"]) / 1.6}))
			"blinked":
				for spot in [event["from"], event["pos"]]:
					effects.play("blink", Effects.context(Vector3(spot) + Vector3(0.0, 0.6, 0.0), spot, Vector2.RIGHT, color_of.call(int(event["player"]))))


## Draws one of each look once under the floor while the stage loads, so their materials and the
## circle shader compile then and not at the first shot (the web build has no shader cache).
func prewarm(hidden: Vector3) -> void:
	var nodes: Array[Node3D] = []
	for look in ["arrow", "bolt"]:
		var shot := _build_shot(look)
		_place_shot(shot, hidden, Vector3(5.0, 0.0, 0.0))
		nodes.append(shot)
	nodes.append(_build_area("hex_circle", 1.0))
	nodes[-1].position = hidden
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		for node in nodes:
			if is_instance_valid(node):
				node.queue_free())


func live_count() -> int:
	return _shots.size() + _areas.size()


# --- building -------------------------------------------------------------------------------------

func _look_of_shot(event: Dictionary) -> String:
	var node: Node3D = _shots.get(int(event["shot"]))
	return str(node.get_meta("look")) if node != null else ("bolt" if "bolt" in str(event["projectile"]) else "arrow")


func _build_shot(look: String) -> Node3D:
	var root := Node3D.new()
	root.set_meta("look", look)
	add_child(root)
	if look == "jade_arrow":
		var arrow:=preload("res://client/characters/bow_visual.gd").make_arrow()
		arrow.rotation.y=PI
		root.add_child(arrow)
	elif look == "bolt":
		var core := MeshInstance3D.new()
		core.mesh = _sphere
		core.material_override = _core_material
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(core)
		var glow := MeshInstance3D.new()
		glow.mesh = _quad
		glow.material_override = _glow_material
		glow.scale = Vector3.ONE * 0.75
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(glow)
		var tail: Array = []
		for i in TRAIL_GLOWS:
			var mote := MeshInstance3D.new()
			mote.mesh = _quad
			mote.material_override = _glow_material
			mote.top_level = true
			mote.scale = Vector3.ONE * lerpf(0.55, 0.12, float(i) / float(TRAIL_GLOWS))
			mote.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mote.visible = false
			root.add_child(mote)
			tail.append(mote)
		root.set_meta("tail", tail)
		root.set_meta("history", [])
	else:
		var arrow := MeshInstance3D.new()
		arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if _arrow_model_mesh != null:
			# The artist's arrow (+Z forward, origin in the middle): turned to face -Z like the shot.
			arrow.mesh = _arrow_model_mesh
			# No material_override: the model's own surface material is the same one, and the override made the renderer log "Parameter material is null".
			arrow.rotation.y = PI
			arrow.scale = Vector3.ONE * float(LOOKS["arrow"]["model_scale"])
		else:
			arrow.mesh = _arrow_mesh
			arrow.material_override = _arrow_material
		root.add_child(arrow)
		var streak := MeshInstance3D.new()
		streak.mesh = _streak_mesh
		streak.material_override = _streak_material
		streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(streak)
	return root


## Puts a projectile at `pos`, its front (-Z) along its flight; a bolt's tail follows its path.
func _place_shot(node: Node3D, pos: Vector3, velocity: Vector3) -> void:
	node.position = pos
	if velocity.length() > 0.01:
		var up := Vector3.UP if absf(velocity.normalized().y) < 0.95 else Vector3.FORWARD
		node.basis = Basis.looking_at(velocity.normalized(), up)
	if node.has_meta("tail"):
		var history: Array = node.get_meta("history")
		history.push_front(pos)
		if history.size() > TRAIL_GLOWS + 1:
			history.resize(TRAIL_GLOWS + 1)
		var tail: Array = node.get_meta("tail")
		for i in tail.size():
			tail[i].visible = i + 1 < history.size()
			if tail[i].visible:
				tail[i].global_position = history[i + 1]


func _build_area(look: String, radius: float) -> MeshInstance3D:
	var circle := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * radius * 2.0
	circle.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = AREA_SHADER
	material.set_shader_parameter("color", LOOKS.get(look, {}).get("color", Color(0.78, 0.36, 1.0)))
	material.set_shader_parameter("progress", 0.0)
	circle.material_override = material
	circle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(circle)
	return circle


func _build_resources() -> void:
	_arrow_material = StandardMaterial3D.new()
	_arrow_material.vertex_color_use_as_albedo = true
	_arrow_material.roughness = 0.85
	_arrow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_streak_material = StandardMaterial3D.new()
	_streak_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_streak_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_streak_material.vertex_color_use_as_albedo = true
	_streak_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_streak_material.no_depth_test = false
	_core_material = StandardMaterial3D.new()
	_core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_material.albedo_color = Color(0.97, 0.88, 1.0)
	_glow_material = StandardMaterial3D.new()
	_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_glow_material.billboard_keep_scale = true
	_glow_material.albedo_color = LOOKS["bolt"]["color"]
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.35, Color(1.0, 1.0, 1.0, 0.55))
	var radial := GradientTexture2D.new()
	radial.gradient = gradient
	radial.fill = GradientTexture2D.FILL_RADIAL
	radial.fill_from = Vector2(0.5, 0.5)
	radial.fill_to = Vector2(1.0, 0.5)
	radial.width = 64
	radial.height = 64
	_glow_material.albedo_texture = radial
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE
	_sphere = SphereMesh.new()
	_sphere.radius = LOOKS["bolt"]["size"]
	_sphere.height = LOOKS["bolt"]["size"] * 2.0
	_sphere.radial_segments = 12
	_sphere.rings = 6
	_arrow_mesh = _make_arrow(float(LOOKS["arrow"]["length"]))
	var arrow_path: String = LOOKS["arrow"]["model"]
	if ResourceLoader.exists(arrow_path):
		var scene: Node = (load(arrow_path) as PackedScene).instantiate()
		var found := scene.find_children("*", "MeshInstance3D", true, false)
		if not found.is_empty():
			_arrow_model_mesh = found[0].mesh
			_arrow_model_material = found[0].get_active_material(0)
		scene.free()
	_streak_mesh = _make_streak(float(LOOKS["arrow"]["length"]) * 1.6, LOOKS["arrow"]["color"])


## A low-poly arrow along -Z (its tip at -length/2): a dark shaft, a steel head and pale fletching.
static func _make_arrow(length: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := length * 0.5
	_box(tool, Vector3(0.0, 0.0, 0.05), Vector3(0.05, 0.05, length - 0.1), Color(0.36, 0.22, 0.12))
	# The head: a flat diamond, seen well from above.
	var tip := Vector3(0.0, 0.0, -half)
	var back := Vector3(0.0, 0.0, -half + 0.13)
	var steel := Color(0.78, 0.8, 0.84)
	for wing in [Vector3(0.075, 0.0, 0.0), Vector3(0.0, 0.04, 0.0)]:
		_tri(tool, tip, back + wing, back - wing, steel)
		_tri(tool, back + wing, back + wing * 0.4 + Vector3(0.0, 0.0, 0.03), back - wing, steel)
	# Fletching: two crossed vanes at the tail.
	var vane := Color(0.85, 0.25, 0.2)
	for wing in [Vector3(0.08, 0.0, 0.0), Vector3(0.0, 0.08, 0.0)]:
		_tri(tool, Vector3(0.0, 0.0, half - 0.2), Vector3(0.0, 0.0, half) + wing, Vector3(0.0, 0.0, half) - wing, vane)
	tool.generate_normals()
	return tool.commit()


## The pale streak behind an arrow: two crossed ribbons that fade toward the back (+Z).
static func _make_streak(length: float, color: Color) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var start := 0.15
	for wing in [Vector3(0.045, 0.0, 0.0), Vector3(0.0, 0.045, 0.0)]:
		var a: Vector3 = Vector3(0.0, 0.0, start) + wing
		var b: Vector3 = Vector3(0.0, 0.0, start) - wing
		var c := Vector3(0.0, 0.0, start + length)
		tool.set_color(Color(color.r, color.g, color.b, 0.75))
		tool.add_vertex(a)
		tool.add_vertex(b)
		tool.set_color(Color(color.r, color.g, color.b, 0.0))
		tool.add_vertex(c)
	return tool.commit()


static func _tri(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	tool.set_color(color)
	tool.add_vertex(a)
	tool.add_vertex(b)
	tool.add_vertex(c)


static func _box(tool: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	var h := size * 0.5
	var c := [
		center + Vector3(-h.x, -h.y, -h.z), center + Vector3(h.x, -h.y, -h.z), center + Vector3(h.x, h.y, -h.z), center + Vector3(-h.x, h.y, -h.z),
		center + Vector3(-h.x, -h.y, h.z), center + Vector3(h.x, -h.y, h.z), center + Vector3(h.x, h.y, h.z), center + Vector3(-h.x, h.y, h.z),
	]
	for face in [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]:
		_tri(tool, c[face[0]], c[face[1]], c[face[2]], color)
		_tri(tool, c[face[0]], c[face[2]], c[face[3]], color)
