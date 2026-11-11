extends Node3D
## The TREASURE CHEST of a journey treasure stage (Boss 2026-10-13): after the gold portal is taken a
## chest drops in at a clear spot with a puff of dust, glowing gold. Walking up to it offers "E  open"
## (stage_view.gd shows the prompt, a button on a phone); opening swings the lid up, a gold burst
## rises from it, and `opened` fires: the stage then asks the journey for the piece (Journey.open_treasure)
## and raises the next portals. Only drawing and timing live here; the rules stay in logic/journey.gd.
##
## Model: art/props/treasure_chest/treasure_chest.glb (level-designer) with a child node `lid` whose
## origin is the hinge (it opens by turning around its local X) and an empty `loot_point`. Until that
## file exists a simple box with a lid is built here with the same names, so the code path is the same.
## Which way the lid turns is read from the model: the turn that lifts the lid's middle upward.
## Cheap for the web / GL Compatibility: unshaded additive glow, CPU particles, no lights.

signal landed  ## the chest has dropped in (the stage puts dust there)
signal opened  ## the lid is open and the burst is out: show the reward now

const ExitPortal := preload("res://client/exit_portal.gd")
const StageProps := preload("res://client/stage_props.gd")

const MODEL_PATH := "res://art/props/treasure_chest/treasure_chest.glb"
const GOLD := Color(1.0, 0.80, 0.28)
const OPEN_RADIUS := 1.7  ## standing this close (feet to the chest's centre, ground plane) offers "E open"
const DROP_HEIGHT := 3.2  ## it falls from this high
const DROP_SECONDS := 0.45
const LID_SECONDS := 0.42
const LID_ANGLE := 105.0  ## degrees the lid opens
const MODEL_LENGTH := 1.0  ## a model is scaled so its longest side on the ground is about this

var lid: Node3D  ## turns around its local X to open
var loot_point: Node3D  ## where the reward bursts from
var is_open := false
var is_ready := false  ## it has landed (it can only be opened after that)
var lid_sign := -1.0  ## which way around X opens the lid (from the model)
var from_model := false  ## the level-designer's model was used (false: the box built here)

var _model: Node3D
var _halo: MeshInstance3D
var _sparkle: CPUParticles3D
var _burst: CPUParticles3D
var _clock := 0.0


func _ready() -> void:
	name = "TreasureChest"
	_model = _load_model()
	from_model = _model != null
	if _model == null:
		_model = _build_box()
	add_child(_model)
	lid = _model.find_child("lid", true, false) as Node3D
	loot_point = _model.find_child("loot_point", true, false) as Node3D
	if loot_point == null:
		loot_point = Node3D.new()
		loot_point.name = "loot_point"
		loot_point.position = Vector3(0.0, 0.55, 0.0)
		_model.add_child(loot_point)
	lid_sign = opening_sign(lid)
	_build_glow()


## Drops the chest in from above (with a small bounce); `landed` fires as it touches the ground.
func drop_in() -> void:
	_model.position.y = DROP_HEIGHT
	var tween := create_tween()
	tween.tween_property(_model, "position:y", 0.0, DROP_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(_on_landed)
	tween.tween_property(_model, "position:y", 0.12, 0.09).set_ease(Tween.EASE_OUT)
	tween.tween_property(_model, "position:y", 0.0, 0.09).set_ease(Tween.EASE_IN)


## True while a point (feet position) is close enough to open the chest.
func in_reach(at: Vector3) -> bool:
	return is_ready and not is_open and Vector2(at.x - global_position.x, at.z - global_position.z).length() <= OPEN_RADIUS


## Opens the chest (once): the lid swings up, then the gold burst and `opened`. Returns false if it was
## already open or has not landed yet.
func open() -> bool:
	if is_open or not is_ready:
		return false
	is_open = true
	var tween := create_tween()
	if lid != null:
		var target := lid.rotation.x + lid_sign * deg_to_rad(LID_ANGLE)
		tween.tween_property(lid, "rotation:x", target, LID_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		tween.tween_interval(LID_SECONDS)
	tween.tween_callback(_on_opened)
	return true


## The world spot the reward bursts from (above the open chest).
func loot_position() -> Vector3:
	return loot_point.global_position if loot_point != null and loot_point.is_inside_tree() else global_position + Vector3(0.0, 0.6, 0.0)


## Which way a turn around local X lifts the lid: its geometry's middle (in the lid's own space, the
## hinge at the origin) must go up. A lid behind its hinge (-Z) opens with +X, one in front with -X.
static func opening_sign(lid_node: Node3D) -> float:
	if lid_node == null:
		return -1.0
	var bounds := _bounds_in(lid_node, lid_node)
	if bounds.size == Vector3.ZERO:
		return -1.0
	var middle := bounds.get_center()
	# turning by a: y' = y cos a - z sin a; for a small a the lift is -z * a (plus the y term, ~0).
	return -1.0 if middle.z >= 0.0 else 1.0


func _process(delta: float) -> void:
	_clock += delta
	if _halo != null:
		var pulse := 0.42 + 0.12 * sin(_clock * 3.0) + (0.25 if is_open else 0.0)
		(_halo.material_override as StandardMaterial3D).albedo_color = Color(GOLD.r, GOLD.g, GOLD.b, pulse)


func _on_landed() -> void:
	is_ready = true
	landed.emit()


func _on_opened() -> void:
	if _burst != null:
		_burst.global_position = loot_position()
		_burst.restart()
		_burst.emitting = true
	if _sparkle != null:
		_sparkle.initial_velocity_max = 1.6  # (the motes rise livelier from the open chest)
	opened.emit()


func _load_model() -> Node3D:
	if not ResourceLoader.exists(MODEL_PATH):
		return null
	var scene := load(MODEL_PATH) as PackedScene
	if scene == null:
		return null
	var root := scene.instantiate() as Node3D
	if root == null:
		return null
	if root.find_child("lid", true, false) == null:
		push_warning("treasure_chest.glb has no 'lid' node: using the built-in chest")
		root.free()
		return null
	StageProps.use_vertex_colors(root)  # (the model is vertex-painted, like the stage art)
	var bounds := _bounds_in(root, root)
	var longest := maxf(bounds.size.x, bounds.size.z)
	var holder := Node3D.new()
	holder.name = "Chest"
	if longest > 0.05 and (longest < MODEL_LENGTH * 0.5 or longest > MODEL_LENGTH * 2.0):
		root.scale = Vector3.ONE * (MODEL_LENGTH / longest)  # (only a model far off the expected size)
	holder.add_child(root)
	return holder


## A plain wooden chest with gold bands, front toward +Z (the camera), the lid hinged at the back.
func _build_box() -> Node3D:
	var holder := Node3D.new()
	holder.name = "Chest"
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.26, 0.12)
	var band := StandardMaterial3D.new()
	band.albedo_color = Color(0.95, 0.72, 0.25)
	band.metallic = 0.6
	band.roughness = 0.35
	band.emission_enabled = true
	band.emission = Color(0.55, 0.38, 0.08)
	var size := Vector3(1.0, 0.5, 0.64)
	holder.add_child(_box_mesh(size, Vector3(0.0, size.y * 0.5, 0.0), wood))
	for x in [-0.36, 0.36]:
		holder.add_child(_box_mesh(Vector3(0.08, size.y + 0.01, size.z + 0.02), Vector3(x, size.y * 0.5, 0.0), band))
	var lid_node := Node3D.new()
	lid_node.name = "lid"
	lid_node.position = Vector3(0.0, size.y, -size.z * 0.5)  # (the hinge: the top back edge)
	holder.add_child(lid_node)
	lid_node.add_child(_box_mesh(Vector3(size.x + 0.04, 0.2, size.z + 0.04), Vector3(0.0, 0.1, size.z * 0.5), wood))
	for x in [-0.36, 0.36]:
		lid_node.add_child(_box_mesh(Vector3(0.08, 0.21, size.z + 0.06), Vector3(x, 0.1, size.z * 0.5), band))
	lid_node.add_child(_box_mesh(Vector3(0.16, 0.18, 0.05), Vector3(0.0, 0.0, size.z + 0.03), band))  # (the lock)
	var point := Node3D.new()
	point.name = "loot_point"
	point.position = Vector3(0.0, size.y + 0.1, 0.0)
	holder.add_child(point)
	return holder


static func _box_mesh(size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	return node


## A gold glow on the ground, motes rising from the chest, and the burst (fired when it opens).
func _build_glow() -> void:
	_halo = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * 2.6
	_halo.mesh = plane
	var halo_material := ExitPortal._additive(Color(GOLD.r, GOLD.g, GOLD.b, 0.45))
	halo_material.albedo_texture = ExitPortal._radial_texture(0.85)
	_halo.material_override = halo_material
	_halo.position.y = 0.03
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_halo)
	_sparkle = _motes(10, 1.8, 0.10, Vector2(0.4, 0.9), 0.45)
	_sparkle.preprocess = 1.8
	add_child(_sparkle)
	_burst = _motes(32, 1.1, 0.2, Vector2(3.0, 6.0), 0.15)
	_burst.one_shot = true
	_burst.explosiveness = 0.92
	_burst.spread = 38.0
	_burst.gravity = Vector3(0.0, -5.0, 0.0)
	_burst.emitting = false
	add_child(_burst)


func _motes(amount: int, lifetime: float, size: float, speed: Vector2, radius: float) -> CPUParticles3D:
	var motes := CPUParticles3D.new()
	motes.amount = amount
	motes.lifetime = lifetime
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	motes.emission_sphere_radius = radius
	motes.direction = Vector3.UP
	motes.spread = 14.0
	motes.gravity = Vector3.ZERO
	motes.initial_velocity_min = speed.x
	motes.initial_velocity_max = speed.y
	motes.scale_amount_min = 0.7
	motes.scale_amount_max = 1.4
	motes.position.y = 0.5
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
	fade.set_color(1, Color(1.0, 0.7, 0.2, 0.0))
	motes.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	var material := ExitPortal._additive(GOLD.lerp(Color.WHITE, 0.35))
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = ExitPortal._radial_texture(1.0)
	quad.material = material
	motes.mesh = quad
	return motes


## The box around every mesh under `node`, in `space`'s coordinates.
static func _bounds_in(node: Node, space: Node3D) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		stack.append_array(current.get_children())
		var mesh_node := current as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var to_space := _relative(mesh_node, space)
		var box: AABB = to_space * mesh_node.mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


## The transform from `node` to `space` (node must be under space), without needing the scene tree.
static func _relative(node: Node3D, space: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != space:
		if current is Node3D:
			xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform
