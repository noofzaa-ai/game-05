extends Node3D
## Supplied 150cm NPC, in-place animation and a bounded shop-front patrol.
const InkUi := preload("res://client/ink_ui.gd")
@export_enum("refine", "upgrade") var workshop_type := "refine"
@export var patrol_half_width := 0.9
@export var patrol_speed := 0.33
var role := ""
var display_name := ""
var _rng := RandomNumberGenerator.new()
var _target_x := 0.0
var _walk_left := 0.0
var _label: Label3D
var _home := Vector3.ZERO
var _direction := 1.0
var _wait := 1.2
var _talking := false
var _visual: Node3D
var _player: AnimationPlayer
var _idle := ""
var _walk := ""

func _ready() -> void:
	_home = position
	_rng.randomize()
	_wait = _rng.randf_range(0.3, 5.0)
	_direction = -1.0 if _rng.randf() < 0.5 else 1.0
	_target_x = _home.x
	role = "bs_" + workshop_type
	display_name = "Refine" if workshop_type == "refine" else "Upgrade"
	var packed := load("res://art/npcs/workshops/bs_%s.glb" % workshop_type) as PackedScene
	if packed == null: return
	_visual = packed.instantiate() as Node3D
	add_child(_visual)
	_player = _visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _player != null:
		for clip in _player.get_animation_list():
			if str(clip).ends_with("Idle"): _idle = str(clip)
			if str(clip).ends_with("Walk"): _walk = str(clip)
			_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_play(false)
	var label := Label3D.new()
	label.text = display_name
	_label = label
	label.position.y = 1.68
	label.font = InkUi.display_font()
	label.font_size = 40
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = InkUi.GOLD
	add_child(label)

func set_talking(value: bool) -> void:
	_talking = value
	if value: _play(false)

func face(direction: Vector2) -> void:
	if _visual != null: _visual.rotation.y = atan2(direction.x, direction.y)

func set_screen_scale(_factor: float) -> void:
	pass

func _physics_process(delta: float) -> void:
	if _visual == null or _talking: return
	if _wait > 0.0:
		_wait -= delta
		_play(false)
		if _wait <= 0.0:
			_target_x = _home.x + _rng.randf_range(-patrol_half_width, patrol_half_width)
			if absf(_target_x - position.x) < 0.3:
				_target_x = _home.x + patrol_half_width * (-1.0 if position.x > _home.x else 1.0)
			_walk_left = _rng.randf_range(1.1, 4.8)
			patrol_speed = _rng.randf_range(0.25, 0.40)
		return
	_direction = signf(_target_x - position.x)
	position.x = move_toward(position.x, _target_x, patrol_speed * delta)
	position.z = _home.z
	_visual.rotation.y = lerp_angle(_visual.rotation.y, PI * 0.5 * _direction, minf(delta * 5.0, 1.0))
	_play(true)
	_walk_left -= delta
	if absf(position.x - _target_x) < 0.01 or _walk_left <= 0.0:
		_wait = _rng.randf_range(1.0, 5.5)

func _play(walking: bool) -> void:
	if _player == null: return
	var clip := _walk if walking else _idle
	if clip != "" and _player.current_animation != clip: _player.play(clip, 0.2)
