extends Node3D
## Isolated art review, not the live camp or its unlock logic.
const Workshop := preload("res://client/workshop.gd")
var _shops: Node3D
var _level := 1

func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("182b31")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("c4d0dd")
	env.environment.ambient_light_energy = 0.65
	add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52, -25, 0)
	light.light_energy = 1.2
	add_child(light)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("243c3e")
	ground.material_override = material
	ground.position.y = -0.04
	add_child(ground)
	var camera := Camera3D.new()
	camera.position = Vector3(7, 9, 13)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10.8
	add_child(camera)
	camera.look_at(Vector3(0, 0.7, 0.3))
	camera.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	var row := HBoxContainer.new()
	row.position = Vector2(24, 24)
	row.add_theme_constant_override("separation", 12)
	layer.add_child(row)
	for level in [1, 2, 3]:
		var button := Button.new()
		button.text = "Workshop Lv.%d" % level
		button.custom_minimum_size = Vector2(170, 48)
		button.pressed.connect(show_level.bind(level))
		row.add_child(button)
	show_level(1)

func show_level(level: int) -> void:
	_level = clampi(level, 1, 3)
	if _shops != null:
		remove_child(_shops)
		_shops.queue_free()
	_shops = Node3D.new()
	add_child(_shops)
	for kind in ["refine", "upgrade"]:
		var shop := Workshop.new()
		shop.workshop_type = kind
		shop.visual_level = _level
		shop.position.x = -3.1 if kind == "refine" else 3.1
		_shops.add_child(shop)
