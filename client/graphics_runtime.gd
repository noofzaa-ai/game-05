extends Node
## Applies once when settings change / scene nodes arrive; no scene scan per frame.
## Reads the APPLIED values (graphics_options.gd effective/enabled): phone defaults, the player's choices and the
## slow-device cuts (shadows, MSAA) all arrive through Options.revision.
const Options := preload("res://client/graphics_options.gd")
var _revision := -1
var _lights: Array[WeakRef] = []
var _environments: Array[WeakRef] = []
var _applied_cap := -1  ## the Engine.max_fps this node last set (-1: none yet)

func _ready() -> void:
	Options.snapshot()
	get_tree().node_added.connect(_added)
	_scan(get_tree().root)
	_apply_all()

func _added(node: Node) -> void:
	if node is Light3D or node is WorldEnvironment:
		_register.call_deferred(weakref(node))

func _scan(node: Node) -> void:
	if node is Light3D or node is WorldEnvironment: _register(weakref(node))
	for child in node.get_children(): _scan(child)

func _register(reference: WeakRef) -> void:
	var node = reference.get_ref()
	if not is_instance_valid(node): return
	if node is Light3D and not node.has_meta("graphics_base_shadow"):
		node.set_meta("graphics_base_shadow", node.shadow_enabled)
		node.set_meta("graphics_base_cull", node.light_cull_mask)
		_lights.append(reference)
		_apply_light(node)
	elif node is WorldEnvironment and node.environment != null:
		var env: Environment = node.environment
		if not env.has_meta("graphics_base_fog"):
			env.set_meta("graphics_base_fog", env.fog_enabled)
			env.set_meta("graphics_base_glow", env.glow_enabled)
			_environments.append(weakref(env))
		_apply_environment(env)

func _process(_delta: float) -> void:
	if _revision != Options.revision: _apply_all()

func _apply_all() -> void:
	_revision = Options.revision
	get_viewport().scaling_3d_scale = float(Options.value("render_scale"))
	var aa := int(Options.effective("antialiasing"))  # (a slow device drops it unless the player picked it)
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED if aa == 0 else (Viewport.MSAA_2X if aa == 2 else Viewport.MSAA_4X)
	_apply_frame_cap(int(Options.effective("frame_cap")))
	_lights = _lights.filter(func(ref: WeakRef): return is_instance_valid(ref.get_ref()))
	_environments = _environments.filter(func(ref: WeakRef): return is_instance_valid(ref.get_ref()))
	for ref in _lights: _apply_light(ref.get_ref())
	for ref in _environments: _apply_environment(ref.get_ref())

## The render frame cap (graphics_options.gd frame_cap: 30 on a phone, 0 = unlimited). Only the drawing slows down:
## physics (60 Hz, up to 8 steps a frame) and netfox (its own 60 Hz clock, up to 8 ticks a frame) catch up, so the
## fight's rules, the input ticks and the network rate are the same at any cap. A cap set by someone else (a perf tool
## or walk.gd --fps) is left alone.
func _apply_frame_cap(cap: int) -> void:
	if _applied_cap >= 0 and Engine.max_fps != _applied_cap:
		return  # someone else set Engine.max_fps after us: theirs wins
	if _applied_cap < 0 and Engine.max_fps != 0:
		return  # already set before this node started (command line / tool)
	Engine.max_fps = maxi(0, cap)
	_applied_cap = Engine.max_fps

func _apply_light(light: Light3D) -> void:
	light.shadow_enabled = bool(light.get_meta("graphics_base_shadow")) and Options.enabled("shadows")
	# Keep sun/character key lights so low settings remain readable.
	if light is OmniLight3D or light is SpotLight3D:
		light.light_cull_mask = int(light.get_meta("graphics_base_cull")) if Options.enabled("decorative_lights") else 0

func _apply_environment(env: Environment) -> void:
	env.fog_enabled = bool(env.get_meta("graphics_base_fog")) and Options.enabled("fog")
	env.glow_enabled = bool(env.get_meta("graphics_base_glow")) and Options.enabled("glow")
