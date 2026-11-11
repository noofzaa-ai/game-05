extends Node
## Applies once when settings change / scene nodes arrive; no scene scan per frame.
const Options := preload("res://client/graphics_options.gd")
var _revision := -1
var _lights: Array[WeakRef] = []
var _environments: Array[WeakRef] = []

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
	var aa := int(Options.value("antialiasing"))
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED if aa == 0 else (Viewport.MSAA_2X if aa == 2 else Viewport.MSAA_4X)
	_lights = _lights.filter(func(ref: WeakRef): return is_instance_valid(ref.get_ref()))
	_environments = _environments.filter(func(ref: WeakRef): return is_instance_valid(ref.get_ref()))
	for ref in _lights: _apply_light(ref.get_ref())
	for ref in _environments: _apply_environment(ref.get_ref())

func _apply_light(light: Light3D) -> void:
	light.shadow_enabled = bool(light.get_meta("graphics_base_shadow")) and Options.enabled("shadows")
	# Keep sun/character key lights so low settings remain readable.
	if light is OmniLight3D or light is SpotLight3D:
		light.light_cull_mask = int(light.get_meta("graphics_base_cull")) if Options.enabled("decorative_lights") else 0

func _apply_environment(env: Environment) -> void:
	env.fog_enabled = bool(env.get_meta("graphics_base_fog")) and Options.enabled("fog")
	env.glow_enabled = bool(env.get_meta("graphics_base_glow")) and Options.enabled("glow")
