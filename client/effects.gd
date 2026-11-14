extends Node3D
## Draws combat effects from data/combat/vfx.json (read by client/vfx/vfx_library.gd): brush-stroke
## trails, impact sprites, ground marks and particle bursts, all with the shaders in client/vfx/, plus
## screen shake, zoom punches and screen flashes. The stage says WHICH action happened and where;
## the data says what it looks like. No art files, few draw calls (a burst is one mesh).
## Nodes are pooled and every changing value is a shader uniform, so nothing compiles mid-fight
## once `prewarm` has drawn every action (the web build has no shader cache).
## EXTENDING: a new look is a data edit in vfx.json; a new layer type is a builder here.

signal screen_flash(color: Color, seconds: float)

const VfxLibrary := preload("res://client/vfx/vfx_library.gd")
const TRAIL_SHADER := preload("res://client/vfx/vfx_trail.gdshader")
const SPRITE_SHADER := preload("res://client/vfx/vfx_sprite.gdshader")
const GROUND_SHADER := preload("res://client/vfx/vfx_ground.gdshader")
const BURST_SHADER := preload("res://client/vfx/vfx_burst.gdshader")
const InkVfx := preload("res://client/vfx/ink_vfx.gd")
const CHEST_HEIGHT := 1.1
const GROUND_LIFT := 0.04  ## ground marks sit this far above the feet so they do not flicker with the floor
const POOL_LIMIT := 48  ## spare nodes kept per layer type
## Sprites and bursts at a body (the hit point, the chest) are drawn this many meters toward the
## camera so the body they burst from does not hide them. Ground-level ones (anchor feet) are not.
const CAMERA_PULL := 0.8

## Set by the stage so hits can shake the screen and punch the zoom.
var rig: Node
## The look of every action. Set by the stage; loaded from the default file when left empty.
var library
## The action keys `prewarm` played (tests check it covers the whole library).
var prewarmed_keys: Array[String] = []

var _live: Array[Dictionary] = []  ## effects playing now
var _pool: Dictionary = {}  ## layer type -> Array of spare MeshInstance3D
var _trail_meshes: Dictionary = {}  ## layer text -> ArrayMesh
var _quad: QuadMesh  ## centered unit quad
var _tall_quad: QuadMesh  ## unit quad standing on its bottom edge (beams, afterimages)
var _burst_mesh: ArrayMesh
var _drawn := 0.0  ## 1 = ink-wash look on every effect material (client/vfx/ink_vfx.gd, graphics setting drawn_style)


func _ready() -> void:
	if library == null:
		library = VfxLibrary.load_default()
	_quad = QuadMesh.new()
	_tall_quad = QuadMesh.new()
	_tall_quad.center_offset = Vector3(0.0, 0.5, 0.0)
	_burst_mesh = _build_burst_mesh()
	_drawn = InkVfx.strength()
	if _drawn > 0.0:
		# The stage builds its monster wind-up warnings (attack_telegraph.gdshader) itself: each is drawn in ink too.
		var tree := get_tree()
		var watch := func(node: Node) -> void: if node is MeshInstance3D: InkVfx.mark.call_deferred(weakref(node))
		tree.node_added.connect(watch)
		tree_exiting.connect(func() -> void: tree.node_added.disconnect(watch))


## Builds the context for `play`. `at` = the action's point (where a blow lands), `feet` = the
## fighter's position on the ground, `facing` = the way the action points (x, z), `color` = what
## 'weapon' means for this action. Optional: hitbox (point), scale (hit strength), follow (a node
## the afterimages trace).
static func context(at: Vector3, feet: Vector3, facing: Vector2, color: Color, extra: Dictionary = {}) -> Dictionary:
	var ctx := {"at": at, "feet": feet, "facing": facing.normalized() if facing.length() > 0.001 else Vector2.RIGHT, "color": color, "scale": 1.0}
	ctx.merge(extra, true)
	if not ctx.has("hitbox"):
		ctx["hitbox"] = at
	if not ctx.has("end"):  # (the far end of a beam; prewarm and single-point actions get a spot 2 m ahead)
		ctx["end"] = at + Vector3(ctx["facing"].x, 0.0, ctx["facing"].y) * 2.0
	ctx["chest"] = feet + Vector3(0.0, CHEST_HEIGHT, 0.0)
	return ctx


## Plays every layer of an action key (nothing if the key is unknown). Returns true if it existed.
func play(key: String, ctx: Dictionary) -> bool:
	if not preload("res://client/graphics_options.gd").enabled("combat_vfx"): return false
	if library == null or not library.has(key):
		return false
	for layer in library.layers(key):
		_play_layer(layer, ctx, false)
	return true


## Plays every action once at `hidden` (a spot under the floor) so the renderer compiles the effect
## shaders and builds every trail mesh while the stage loads. Call before `rig` is set and before
## anything listens to `screen_flash`.
func prewarm(hidden: Vector3) -> void:
	prewarmed_keys.clear()
	if library == null:
		return
	var ctx := context(hidden, hidden, Vector2.RIGHT, Color.WHITE, {"follow": null})
	for key in library.actions:
		for layer in library.layers(key):
			_play_layer(layer, ctx, true)
		prewarmed_keys.append(key)


## How many effect nodes are playing now (tests, the performance overlay).
func live_count() -> int:
	return _live.size()


func _process(delta: float) -> void:
	if not preload("res://client/graphics_options.gd").enabled("combat_vfx"):
		for fx in _live: _release(fx)
		_live.clear()
		return
	var i := _live.size() - 1
	while i >= 0:
		var fx: Dictionary = _live[i]
		fx["age"] += delta
		if fx["age"] >= 0.0:
			if not fx["shown"]:
				_start(fx)
			var p := clampf(float(fx["age"]) / float(fx["seconds"]), 0.0, 1.0)
			_animate(fx, p)
			if p >= 1.0:
				_release(fx)
				_live.remove_at(i)
		i -= 1


# --- layers --------------------------------------------------------------------------------------

func _play_layer(layer: Dictionary, ctx: Dictionary, instant: bool) -> void:
	var delay := 0.0 if instant else float(layer.get("delay", 0.0))
	var strength := float(ctx.get("scale", 1.0)) if bool(layer.get("scale", false)) else 1.0
	match str(layer["type"]):
		"trail":
			_trail(layer, ctx, delay)
		"sprite":
			_sprite(layer, ctx, delay, strength)
		"ground":
			_ground(layer, ctx, delay, strength)
		"burst":
			_burst(layer, ctx, delay, strength)
		"ghosts":
			_ghosts(layer, ctx, delay, instant)
		"shake":
			_later(delay, func() -> void:
				if rig != null:
					rig.shake(float(layer.get("strength", 0.02)) * strength, float(layer.get("seconds", 0.1))))
		"punch":
			_later(delay, func() -> void:
				if rig != null:
					rig.punch(float(layer.get("degrees", 3.0)) * minf(strength, 1.5)))
		"flash":
			var color: Color = library.color_of(layer.get("color", [1, 1, 1, 0.4]), ctx["color"])
			_later(delay, func() -> void: screen_flash.emit(color, float(layer.get("seconds", 0.2))))


func _trail(layer: Dictionary, ctx: Dictionary, delay: float) -> void:
	var node := _take("trail", TRAIL_SHADER)
	node.mesh = _trail_mesh(layer)
	var origin := _point(layer, ctx, "feet")
	node.position = Vector3(origin.x, ctx["feet"].y + (origin.y - _anchor(layer, ctx, "feet").y), origin.z)
	node.rotation = Vector3(0.0, _yaw(ctx["facing"]) + deg_to_rad(float(layer.get("yaw", 0.0))), 0.0)
	node.scale = Vector3.ONE
	var mat: ShaderMaterial = node.material_override
	_common_uniforms(mat, layer, ctx, 0.6)
	mat.set_shader_parameter("sweep", float(layer.get("sweep", 0.5)))
	mat.set_shader_parameter("tail", float(layer.get("tail", 0.7)))
	_add(node, layer, delay, {})


func _sprite(layer: Dictionary, ctx: Dictionary, delay: float, strength: float) -> void:
	var node := _take("sprite", SPRITE_SHADER)
	var mode := str(layer["mode"])
	var link := bool(layer.get("link", false))  # stretched from the action's point to ctx "end" (a lightning arc)
	var tall := not link and (layer.has("height") or mode in ["beam", "ghost"])
	node.mesh = _tall_quad if tall else _quad
	var billboard := "axis" if link else str(layer.get("billboard", "y" if tall else "camera"))
	node.position = _point(layer, ctx, "at")
	node.rotation = Vector3(-PI * 0.5, 0.0, 0.0) if billboard == "ground" else Vector3.ZERO
	var link_length := 0.0
	if link:
		var from := node.position
		var to: Vector3 = ctx["end"]
		link_length = maxf(from.distance_to(to), 0.05)
		node.position = (from + to) * 0.5
		var along := (to - from) / link_length if from.distance_to(to) > 0.001 else Vector3.UP
		node.quaternion = Quaternion(Vector3.UP, along) if along.dot(Vector3.UP) > -0.999 else Quaternion(Vector3.RIGHT, PI)
	var mat: ShaderMaterial = node.material_override
	_common_uniforms(mat, layer, ctx, 0.0)
	mat.set_shader_parameter("mode", VfxLibrary.SPRITE_MODES.find(mode))
	mat.set_shader_parameter("billboard", VfxLibrary.BILLBOARDS.find(billboard))
	mat.set_shader_parameter("spikes", float(layer.get("spikes", 10.0)))
	mat.set_shader_parameter("pull", CAMERA_PULL if billboard == "camera" and _at_body(layer, "at") else 0.0)
	var size := _size(layer, strength)
	var height := link_length if link else float(layer.get("height", 0.0)) * (strength if bool(layer.get("scale", false)) else 1.0)
	_add(node, layer, delay, {"size": size, "height": height, "spin": deg_to_rad(float(layer.get("spin", 0.0)))})


func _ground(layer: Dictionary, ctx: Dictionary, delay: float, strength: float) -> void:
	var node := _take("ground", GROUND_SHADER)
	node.mesh = _quad
	var spot := _point(layer, ctx, "at")
	node.position = Vector3(spot.x, ctx["feet"].y + GROUND_LIFT, spot.z)
	node.rotation = Vector3(-PI * 0.5, randf() * TAU, 0.0)
	var mat: ShaderMaterial = node.material_override
	_common_uniforms(mat, layer, ctx, 0.5)
	mat.set_shader_parameter("mode", VfxLibrary.GROUND_MODES.find(str(layer["mode"])))
	_add(node, layer, delay, {"size": _size(layer, strength), "spin": deg_to_rad(float(layer.get("spin", 0.0)))})


func _burst(layer: Dictionary, ctx: Dictionary, delay: float, strength: float) -> void:
	var node := _take("burst", BURST_SHADER)
	node.mesh = _burst_mesh
	node.position = _point(layer, ctx, "at")
	node.rotation = Vector3.ZERO
	node.scale = Vector3.ONE
	var mat: ShaderMaterial = node.material_override
	_common_uniforms(mat, layer, ctx, 0.0)
	var dir_name := str(layer.get("dir", "up"))
	var facing: Vector2 = ctx["facing"]
	var lift := deg_to_rad(float(layer.get("lift", 0.0)))
	var direction := Vector3.UP
	match dir_name:
		"down":
			direction = Vector3.DOWN
		"forward":
			direction = Vector3(facing.x * cos(lift), sin(lift), facing.y * cos(lift))
		"back":
			direction = Vector3(-facing.x * cos(lift), sin(lift), -facing.y * cos(lift))
	var spread := PI if dir_name == "none" else deg_to_rad(float(layer.get("spread", 45.0)))
	mat.set_shader_parameter("style", VfxLibrary.BURST_STYLES.find(str(layer["style"])))
	mat.set_shader_parameter("direction", direction)
	mat.set_shader_parameter("spread", spread)
	mat.set_shader_parameter("speed", float(layer.get("speed", 4.0)) * sqrt(strength))
	mat.set_shader_parameter("gravity", float(layer.get("gravity", 9.0)))
	mat.set_shader_parameter("drag", float(layer.get("drag", 2.0)))
	mat.set_shader_parameter("size", float(layer.get("size", 0.12)) * sqrt(strength))
	mat.set_shader_parameter("count", float(mini(VfxLibrary.MAX_BURST, int(round(float(layer.get("count", 12)) * strength)))))
	mat.set_shader_parameter("streak", float(layer.get("streak", 0.05)))
	mat.set_shader_parameter("seconds", float(layer["seconds"]))
	mat.set_shader_parameter("pull", CAMERA_PULL if _at_body(layer, "at") else 0.0)
	_add(node, layer, delay, {})


## Afterimages left along a moving fighter: each appears where the fighter is at its moment.
func _ghosts(layer: Dictionary, ctx: Dictionary, delay: float, instant: bool) -> void:
	var count := int(layer.get("count", 4))
	var interval := float(layer.get("interval", 0.05))
	for i in count:
		var node := _take("sprite", SPRITE_SHADER)
		node.mesh = _tall_quad
		node.position = ctx["feet"]
		node.rotation = Vector3.ZERO
		var mat: ShaderMaterial = node.material_override
		_common_uniforms(mat, layer, ctx, 0.5)
		mat.set_shader_parameter("mode", VfxLibrary.SPRITE_MODES.find("ghost"))
		mat.set_shader_parameter("billboard", 2)
		mat.set_shader_parameter("pull", 0.0)
		mat.set_shader_parameter("opacity", float(layer.get("opacity", 1.0)) * lerpf(0.9, 0.45, float(i) / maxf(1.0, float(count - 1))))
		var width := float(layer.get("size", 1.0))
		_add(node, layer, delay + (0.0 if instant else interval * float(i)), {"size": Vector2(width, width), "height": float(layer.get("height", 1.9)), "follow": ctx.get("follow")})


# --- playing -------------------------------------------------------------------------------------

func _add(node: MeshInstance3D, layer: Dictionary, delay: float, extra: Dictionary) -> void:
	var fx := {"node": node, "type": node.get_meta("vfx_type"), "age": -delay, "seconds": maxf(float(layer.get("seconds", 0.3)), 0.01), "shown": false}
	fx.merge(extra)
	node.visible = false
	(node.material_override as ShaderMaterial).set_shader_parameter("progress", 0.0)
	_live.append(fx)
	if delay <= 0.0:
		_start(fx)
		_animate(fx, 0.0)


func _start(fx: Dictionary) -> void:
	fx["shown"] = true
	var follow = fx.get("follow")
	if follow != null and is_instance_valid(follow):
		fx["node"].global_position = (follow as Node3D).global_position
	fx["node"].visible = true


func _animate(fx: Dictionary, p: float) -> void:
	var node: MeshInstance3D = fx["node"]
	var mat: ShaderMaterial = node.material_override
	mat.set_shader_parameter("progress", p)
	if fx.has("size"):
		var size: Vector2 = fx["size"]
		var s := lerpf(size.x, size.y, 1.0 - pow(1.0 - p, 3.0))
		var height := float(fx.get("height", 0.0))
		node.scale = Vector3(s, height if height > 0.0 else s, 1.0)
	if float(fx.get("spin", 0.0)) != 0.0:
		mat.set_shader_parameter("spin", float(fx["spin"]) * p * float(fx["seconds"]))


func _take(type: String, shader: Shader) -> MeshInstance3D:
	var spare: Array = _pool.get(type, [])
	if not spare.is_empty():
		return spare.pop_back()
	var node := MeshInstance3D.new()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("drawn", _drawn)
	node.material_override = mat
	node.set_meta("vfx_type", type)
	if type == "burst":
		node.custom_aabb = AABB(Vector3(-12.0, -12.0, -12.0), Vector3(24.0, 24.0, 24.0))  # (the shader moves the sparks)
	elif type == "sprite":
		node.extra_cull_margin = 4.0  # (billboards turn after culling)
	add_child(node)
	return node


func _release(fx: Dictionary) -> void:
	var node: MeshInstance3D = fx["node"]
	node.visible = false
	var spare: Array = _pool.get(fx["type"], [])
	if spare.size() >= POOL_LIMIT:
		node.queue_free()
		return
	spare.append(node)
	_pool[fx["type"]] = spare


func _later(delay: float, action: Callable) -> void:
	if delay <= 0.0 or not is_inside_tree():
		action.call()
	else:
		get_tree().create_timer(delay).timeout.connect(action)


func _common_uniforms(mat: ShaderMaterial, layer: Dictionary, ctx: Dictionary, default_ink: float) -> void:
	mat.set_shader_parameter("color", library.color_of(layer.get("color", "white"), ctx["color"]))
	mat.set_shader_parameter("ink_color", library.palette["ink"])
	mat.set_shader_parameter("ink", float(layer.get("ink", default_ink)))
	mat.set_shader_parameter("opacity", float(layer.get("opacity", 1.0)))
	mat.set_shader_parameter("seed", randf() * 10.0)
	mat.set_shader_parameter("spin", 0.0)


func _size(layer: Dictionary, strength: float) -> Vector2:
	var raw = layer.get("size", [1.0, 1.0])
	var grow := sqrt(strength)  # (a hit twice as hard reads bigger without filling the screen)
	if typeof(raw) == TYPE_ARRAY:
		return Vector2(float(raw[0]), float(raw[1])) * grow
	return Vector2(float(raw), float(raw)) * grow


static func _at_body(layer: Dictionary, default_anchor: String) -> bool:
	return str(layer.get("anchor", default_anchor)) != "feet"


func _anchor(layer: Dictionary, ctx: Dictionary, default_anchor: String) -> Vector3:
	return ctx[str(layer.get("anchor", default_anchor))]


## The anchor plus `offset` = [forward, up, side] (side = the facing's right).
func _point(layer: Dictionary, ctx: Dictionary, default_anchor: String) -> Vector3:
	var base := _anchor(layer, ctx, default_anchor)
	var raw = layer.get("offset")
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() < 3:
		return base
	var facing: Vector2 = ctx["facing"]
	var forward := Vector3(facing.x, 0.0, facing.y)
	var right := Vector3(-facing.y, 0.0, facing.x)
	return base + forward * float(raw[0]) + Vector3.UP * float(raw[1]) + right * float(raw[2])


## Turn about the up axis that points local +x along `facing` (x, z).
static func _yaw(facing: Vector2) -> float:
	return atan2(-facing.y, facing.x)


# --- meshes --------------------------------------------------------------------------------------

## A brush-stroke ribbon in the fighter's space (+x = facing, heights from the feet). UV.x runs
## from the start of the stroke to its end (the shader moves the head along it), UV.y across.
func _trail_mesh(layer: Dictionary) -> ArrayMesh:
	var key := str([layer.get("shape"), layer.get("radius"), layer.get("width"), layer.get("from"), layer.get("to"), layer.get("rise"), layer.get("tilt"), layer.get("lanes"), layer.get("lane_gap")])
	if _trail_meshes.has(key):
		return _trail_meshes[key]
	var shape := str(layer.get("shape", "arc"))
	var radius := float(layer.get("radius", 1.5))
	var width := float(layer.get("width", 0.5))
	var from := float(layer.get("from", 75.0))
	var to := float(layer.get("to", -75.0))
	var rise: Array = layer.get("rise", [1.0, 1.0])
	var tilt := deg_to_rad(float(layer.get("tilt", 0.0)))
	var lanes := maxi(1, int(layer.get("lanes", 1)))
	var lane_gap := float(layer.get("lane_gap", 0.4))
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for lane in lanes:
		var side := (float(lane) - float(lanes - 1) * 0.5) * lane_gap
		var segments := 6 if shape == "thrust" else clampi(int(absf(to - from) / 7.0), 10, 52)
		var first := vertices.size()
		for i in segments + 1:
			var t := float(i) / float(segments)
			var h := lerpf(float(rise[0]), float(rise[1]), t)
			var outer: Vector3
			var inner: Vector3
			if shape == "thrust":
				var x := lerpf(from, to, t)
				var w := width * (0.35 + 0.65 * t) * 0.5
				outer = Vector3(x, h, side - w)
				inner = Vector3(x, h, side + w)
			else:
				var angle := deg_to_rad(lerpf(from, to, t))
				var w := width * (0.4 + 0.6 * t)
				outer = _tilted(Vector3(cos(angle) * radius, 0.0, -sin(angle) * radius), tilt) + Vector3(0.0, h, 0.0)
				inner = _tilted(Vector3(cos(angle) * (radius - w), 0.0, -sin(angle) * (radius - w)), tilt) + Vector3(0.0, h, 0.0)
				outer.z += side
				inner.z += side
			vertices.append(outer)
			vertices.append(inner)
			uvs.append(Vector2(t, 0.0))
			uvs.append(Vector2(t, 1.0))
		for i in segments:
			var base := first + i * 2
			indices.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_trail_meshes[key] = mesh
	return mesh


## Rolls a point of the stroke plane about the facing axis (+x) by `tilt` radians.
static func _tilted(p: Vector3, tilt: float) -> Vector3:
	return Vector3(p.x, p.y * cos(tilt) - p.z * sin(tilt), p.y * sin(tilt) + p.z * cos(tilt))


## Up to 32 quads in one mesh; each carries its index (COLOR.r) and random numbers (UV2, COLOR.gb).
static func _build_burst_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for i in VfxLibrary.MAX_BURST:
		var random := Vector2(rng.randf(), rng.randf())
		var color := Color(float(i) / 255.0, rng.randf(), rng.randf(), 1.0)
		var base := vertices.size()
		for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
			vertices.append(Vector3.ZERO)
			uvs.append(corner)
			uv2s.append(random)
			colors.append(color)
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
