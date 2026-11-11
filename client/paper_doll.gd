extends Control
## The live "paper-doll" on the gear screen: the player's own 3D character (character_model.gd)
## standing idle and wearing what is equipped, rendered by a small SubViewport into this control.
## Drag across it (mouse or finger) to turn the character around.
## Performance (the web build has no threads): the SubViewport has its own tiny world, renders at
## the control's real on-screen size capped at MAX_PIXELS, and renders ONLY while this control is
## visible on screen (another tab, or a closed screen, costs nothing).
## EXTENDING: armor pieces and the glow of high-tier gear plug into dress(): it already gets the whole
## loadout; today it only shows the weapon because there are no armor models yet.

const CharacterModel := preload("res://client/characters/studio05_character_model.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const InkUi := preload("res://client/ink_ui.gd")
const CharacterLight := preload("res://client/character_light.gd")

const MAX_PIXELS := Vector2(360.0, 520.0)  ## the most the doll is ever rendered at
const MIN_PIXELS := Vector2(96.0, 128.0)
const TURN_PER_PIXEL := 0.012  ## radians the doll turns per menu unit dragged
const SETTLE_RATE := 1.6  ## how fast it turns back to face the viewer after a drag

var viewport: SubViewport
var model  ## the CharacterModel (null if the model file is missing)
var _pivot: Node3D
var _camera: Camera3D
var _ground := Vector3.ZERO
var _texture: TextureRect
var _turn := 0.0
var _dragging := false
var _style := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X  # smooth edges: without it the outfits look jagged
	viewport.positional_shadow_atlas_size = 0
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.size = Vector2i(MIN_PIXELS)
	add_child(viewport)
	_build_scene()
	_texture = TextureRect.new()
	_texture.texture = viewport.get_texture()
	_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_texture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_texture)
	resized.connect(_fit_resolution)
	visibility_changed.connect(_update_rendering)
	_fit_resolution()
	_update_rendering()


func _build_scene() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.78, 0.74, 0.68)
	environment.ambient_light_energy = 0.75
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, 30.0, 0.0)
	light.light_energy = 1.1
	light.light_color = Color(1.0, 0.95, 0.86)
	viewport.add_child(light)
	CharacterLight.light_scene(viewport, environment, 0.25, 1.0)
	var camera := Camera3D.new()
	_camera = camera
	camera.fov = 26.0
	camera.position = Vector3(0.0, 1.05, 4.6)
	camera.rotation_degrees.x = -4.0
	viewport.add_child(camera)
	_pivot = Node3D.new()
	viewport.add_child(_pivot)
	var character := CharacterModel.new()
	character.ink_outline = true
	_pivot.add_child(character)
	if character.load_model():
		model = character
		model.set_pose("idle", 0.0, 0.0, true, Vector2(0.0, 1.0), false)
	else:
		character.queue_free()


## Shows what `loadout` wears. `style` is the weapon's combat style (its stand-in model is
## art/weapons/<style>.glb); `catalog` (ItemCatalog) finds the worn items' own models. `appearance` is
## the player's own looks (Profile.appearance).
## EXTENDING: the glow of high tiers goes here.
func dress(loadout, style: String, catalog = null, appearance: Dictionary = {}) -> void:
	_style = style
	if model != null:
		model.equipment_rest = true
		model.set_pose("idle", 0.0, 0.0, true, Vector2(0.0, 1.0), false, "", "", style)  # UI uses the native {weapon}_idle clip
		# Submit one complete appearance: equipment dressing must not reset the selected fashion.
		var looks: Dictionary = ItemAssets.looks(loadout, catalog, style) if catalog != null else {"weapon": {"style": style, "family": style, "path": ""}}
		looks["appearance"] = ItemAssets.appearance(appearance)
		model.dress(looks)
		_fit_camera.call_deferred()


## True while the doll is being rendered (for tests and the performance budget).
func is_rendering() -> bool:
	return viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED


func _update_rendering() -> void:
	if viewport == null:
		return
	var on := is_visible_in_tree()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	set_process(on)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_update_rendering()


## Renders at the control's real size on screen (it may be scaled), never above MAX_PIXELS.
func _fit_resolution() -> void:
	if viewport == null:
		return
	var on_screen := size * get_global_transform_with_canvas().get_scale()
	var pixels := on_screen.clamp(MIN_PIXELS, MAX_PIXELS)
	# keep the control's shape so the picture is not stretched
	var aspect := size.x / maxf(size.y, 1.0)
	if pixels.x / pixels.y > aspect:
		pixels.x = pixels.y * aspect
	else:
		pixels.y = pixels.x / maxf(aspect, 0.01)
	viewport.size = Vector2i(maxi(16, int(pixels.x)), maxi(16, int(pixels.y)))
	_fit_camera()


func _fit_camera() -> void:
	if model == null or _camera == null or viewport == null: return
	var bounds: AABB = model.preview_bounds()
	var aspect := float(viewport.size.x) / maxf(float(viewport.size.y), 1.0)
	var framed_height := maxf(bounds.size.y * 1.18, bounds.size.x * 1.12 / maxf(aspect, 0.1))
	var distance := framed_height / (2.0 * tan(deg_to_rad(_camera.fov * 0.5)))
	var target := Vector3(0, bounds.get_center().y, 0)
	_camera.position = target + Vector3(0, distance * 0.04, distance)
	_camera.look_at(target)
	_ground = Vector3(0, bounds.position.y, 0)
	queue_redraw()


func _process(delta: float) -> void:
	if model == null:
		return
	if not _dragging:
		_turn = lerp_angle(_turn, 0.0, minf(1.0, SETTLE_RATE * delta * 0.5))
	_pivot.rotation.y = _turn
	model.apply_pose(delta)


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = button.pressed
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		_turn += motion.relative.x * TURN_PER_PIXEL
		accept_event()


func _draw() -> void:
	# An ink-wash backdrop: a pale disc fading out and a brushed ground ring under the feet.
	var center := Vector2(size.x * 0.5, size.y * 0.47)
	for i in 6:
		var t := float(i) / 5.0
		draw_circle(center, size.x * (0.48 - t * 0.3), Color(InkUi.DOLL_SHADE, 0.06 + t * 0.05))
	var feet := Vector2(size.x * 0.5, size.y * 0.9)
	if _camera != null and viewport != null:
		feet = _camera.unproject_position(_ground) / Vector2(viewport.size) * size
	draw_set_transform(feet, 0.0, Vector2(1.0, 0.28))
	draw_arc(Vector2.ZERO, size.x * 0.3, 0.0, TAU, 40, Color(InkUi.INK, 0.8), 6.0, true)
	draw_arc(Vector2.ZERO, size.x * 0.3, 0.3, TAU - 0.6, 40, Color(InkUi.SEAL, 0.55), 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
