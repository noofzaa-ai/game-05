extends Control
## The live 3D window of a class card (docs/ui/class_card_ui_handoff.md §3, §13): the class's own character
## (studio05 model, the card's hair / outfit / eyes / skin / makeup) playing the class idle in a small SubViewport.
## API: set_class(id), set_look(look), set_hover(on, pointer), pulse(), set_render_mode(mode), set_framing(kind),
## set_view_material(mat).
## Performance (the web build has no threads): every portrait has its own tiny world and renders only while
## it is visible. Render modes: "live" every frame (the selected / focused card), "throttled" a few times a
## second (the other deck cards), "once" one redraw per change (mini cards).
## Styling values come from client/card_tokens.gd.

const CharacterModel := preload("res://client/characters/studio05_character_model.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const CardTokens := preload("res://client/card_tokens.gd")
const CardDeck := preload("res://logic/card_deck.gd")
const CharacterLight := preload("res://client/character_light.gd")
const SHADOW_SHADER := preload("res://client/card_figure_shadow.gdshader")

enum Mode { LIVE, THROTTLED, ONCE }

var viewport: SubViewport
var model  ## the studio05 character model (null if its file is missing)
var class_id := ""
var framing := "full"  ## "full" body, "bust" (head and shoulders, for mini cards), "card" / "card_deck" (old card), "hub" (leather card window) or "stage" (character screen window)
var _mode := Mode.THROTTLED
var _pivot: Node3D
var _camera: Camera3D
var _texture: TextureRect
var _look := {}
var _weapon := ""
var _clock := 0.0
var _turn := 0.0
var _turn_target := 0.0
var _redraw_once := true
var _shadow: TextureRect


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.positional_shadow_atlas_size = 0
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.size = Vector2i(CardTokens.PORTRAIT_MIN_PIXELS)
	add_child(viewport)
	_build_scene()
	_texture = TextureRect.new()
	_texture.texture = viewport.get_texture()
	_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture.stretch_mode = TextureRect.STRETCH_SCALE
	_texture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_texture)
	if _shadow != null:
		_shadow.texture = viewport.get_texture()
	resized.connect(_fit_resolution)
	visibility_changed.connect(_update_rendering)
	_fit_resolution()
	_update_rendering()
	if not class_id.is_empty():
		_dress()


func _build_scene() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = CardTokens.PORTRAIT_AMBIENT
	environment.ambient_light_energy = CardTokens.PORTRAIT_AMBIENT_ENERGY
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = CardTokens.PORTRAIT_LIGHT_ANGLE
	light.light_energy = CardTokens.PORTRAIT_LIGHT_ENERGY
	light.light_color = CardTokens.PORTRAIT_LIGHT
	viewport.add_child(light)
	CharacterLight.light_scene(viewport, environment, CardTokens.PORTRAIT_KEY_ENERGY, CardTokens.PORTRAIT_RIM_ENERGY)
	_camera = Camera3D.new()
	_camera.fov = CardTokens.PORTRAIT_FOV
	viewport.add_child(_camera)
	_pivot = Node3D.new()
	viewport.add_child(_pivot)
	var character := CharacterModel.new()
	character.ink_outline = true
	_pivot.add_child(character)
	if character.load_model():
		model = character
	else:
		character.queue_free()


# ------------------------------------------------------------------ API
## Shows this class (its animation set, weapon and shield). Call set_look() for the card's looks.
func set_class(id: String) -> void:
	class_id = id
	_weapon = str(CardDeck.class_data(id).get("weapon", ""))
	if viewport != null:
		_dress()


## `look` is CardDeck.look_of(deck, class_id): {"class", "hair", "silver", "eye_color", "skin", "makeup"}.
func set_look(look: Dictionary) -> void:
	_look = look.duplicate(true)
	if look.has("class") and str(look["class"]) != class_id:
		class_id = str(look["class"])
		_weapon = str(CardDeck.class_data(class_id).get("weapon", ""))
	if viewport != null:
		_dress()


## The pointer is over the card: the character turns a little toward it (`pointer` 0..1 across the window).
func set_hover(on: bool, pointer: Vector2 = Vector2(0.5, 0.5)) -> void:
	_turn_target = (pointer.x - 0.5) * 2.0 * CardTokens.PORTRAIT_HOVER_TURN if on else 0.0
	if on and _mode == Mode.ONCE:
		_redraw_once = true
		_update_rendering()


## A small pop of the character (used when an option changes).
func pulse() -> void:
	if _pivot == null or not is_inside_tree():
		return
	var tween := create_tween()
	tween.tween_property(_pivot, "scale", Vector3.ONE * CardTokens.PORTRAIT_PULSE_SCALE, CardTokens.PORTRAIT_PULSE_SECONDS * 0.4)
	tween.tween_property(_pivot, "scale", Vector3.ONE, CardTokens.PORTRAIT_PULSE_SECONDS * 0.6)
	_redraw_once = true
	_update_rendering()


func set_render_mode(mode: Mode) -> void:
	_mode = mode
	_redraw_once = true
	_update_rendering()


func set_framing(kind: String) -> void:
	framing = kind
	_fit_camera()


## A soft dark silhouette of the character (same render, blurred alpha) for the backdrop under it.
## The caller places it; it shares the portrait's texture, so it costs no extra 3D render.
func shadow_rect() -> TextureRect:
	if _shadow == null:
		_shadow = TextureRect.new()
		_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_shadow.stretch_mode = TextureRect.STRETCH_SCALE
		_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var shade := ShaderMaterial.new()
		shade.shader = SHADOW_SHADER
		shade.set_shader_parameter("shadow_color", CardTokens.FIGURE_SHADOW_COLOR)
		shade.set_shader_parameter("blur", CardTokens.FIGURE_SHADOW_BLUR)
		_shadow.material = shade
		if viewport != null:
			_shadow.texture = viewport.get_texture()
	return _shadow


## A canvas material for the shown render only (the hub card's perspective tilt, client/card_tilt.gdshader);
## null removes it. The portrait's own material (grey for a locked card) is left alone.
func set_view_material(mat: Material) -> void:
	if _texture != null:
		_texture.material = mat


func is_rendering() -> bool:
	return viewport != null and viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED


# ------------------------------------------------------------------ internals
func _dress() -> void:
	if model == null or class_id.is_empty():
		return
	var look := _look if not _look.is_empty() else {"class": class_id}
	var looks := {
		"class": class_id,
		"appearance": ItemAssets.card_appearance(look, ItemAssets.appearance({})),
		"weapon": {"path": "", "family": _weapon, "style": _weapon},
	}
	# The card's equipped off-hand shield and its refine aura (display only: read from the card's loadout).
	var gear := _card_looks()
	if gear.has("offhand"):
		looks["offhand"] = gear["offhand"]
		looks["refine"] = {"offhand": int(gear.get("refine", {}).get("offhand", 0)), "weapon": int(gear.get("refine", {}).get("weapon", 0))}
	model.equipment_rest = true
	model.dress(looks)
	model.set_pose("idle", 0.0, 0.0, true, Vector2(0.0, 1.0), false, "", "", _weapon)
	model.apply_pose(0.0)
	_redraw_once = true
	_fit_camera.call_deferred()
	_update_rendering()


## ItemAssets.looks() of this card's own loadout (Profile.loadout_of), {} when there is no profile.
func _card_looks() -> Dictionary:
	var state := get_node_or_null("/root/GameState")
	if state == null or state.get("profile") == null or state.get("item_rules") == null:
		return {}
	var loadout = state.profile.loadout_of(class_id) if state.profile.has_method("loadout_of") else null
	if loadout == null:
		return {}
	return ItemAssets.looks(loadout, state.item_rules.catalog, _weapon)


func _update_rendering() -> void:
	if viewport == null:
		return
	var on := is_visible_in_tree() and model != null
	set_process(on)
	if not on:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	elif _mode == Mode.LIVE:
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	else:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if _redraw_once else SubViewport.UPDATE_DISABLED


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_update_rendering()


func _fit_resolution() -> void:
	if viewport == null:
		return
	var on_screen := size * get_global_transform_with_canvas().get_scale()
	var pixels := on_screen.clamp(CardTokens.PORTRAIT_MIN_PIXELS, CardTokens.PORTRAIT_MAX_PIXELS)
	viewport.size = Vector2i(maxi(16, int(pixels.x)), maxi(16, int(pixels.y)))
	_fit_camera()
	_redraw_once = true
	_update_rendering()


func _fit_camera() -> void:
	if model == null or _camera == null or viewport == null:
		return
	var bounds: AABB = model.preview_bounds()
	var aspect := float(viewport.size.x) / maxf(float(viewport.size.y), 1.0)
	var top := bounds.position.y + bounds.size.y
	var height := bounds.size.y
	var center_y := bounds.get_center().y
	if framing in ["card", "card_deck", "hub", "stage"]:
		var tops := {"card": CardTokens.PORTRAIT_FRAME_TOP, "card_deck": CardTokens.PORTRAIT_DECK_TOP, "hub": CardTokens.PORTRAIT_HUB_TOP, "stage": CardTokens.PORTRAIT_STAGE_TOP}
		var bottoms := {"card": CardTokens.PORTRAIT_FRAME_BOTTOM, "card_deck": CardTokens.PORTRAIT_DECK_BOTTOM, "hub": CardTokens.PORTRAIT_HUB_BOTTOM, "stage": CardTokens.PORTRAIT_STAGE_BOTTOM}
		var f_top: float = tops[framing]
		var f_bottom: float = bottoms[framing]
		var view_height := height / maxf(f_bottom - f_top, 0.1)
		var view_top := top + f_top * view_height
		_aim(view_height, view_top - view_height * 0.5)
		return
	if framing == "bust":
		height = bounds.size.y * 0.42
		center_y = top - height * 0.5
	var framed_height := maxf(height * CardTokens.PORTRAIT_FRAME_PAD, bounds.size.x * CardTokens.PORTRAIT_FRAME_PAD / maxf(aspect, 0.1))
	_aim(framed_height, center_y)


## Camera straight on, `view_height` world units tall at the model's plane, centred on `center_y`.
func _aim(view_height: float, center_y: float) -> void:
	var distance := view_height / (2.0 * tan(deg_to_rad(_camera.fov * 0.5)))
	var target := Vector3(0.0, center_y, 0.0)
	_camera.position = target + Vector3(0.0, 0.0, distance)
	_camera.look_at(target)


func _process(delta: float) -> void:
	if model == null:
		return
	_turn = lerpf(_turn, _turn_target, minf(1.0, delta * 8.0))
	_pivot.rotation.y = _turn
	match _mode:
		Mode.LIVE:
			model.apply_pose(delta)
		Mode.THROTTLED:
			_clock += delta
			if _clock >= CardTokens.PORTRAIT_THROTTLE_SECONDS:
				model.apply_pose(_clock)
				_clock = 0.0
				viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		Mode.ONCE:
			if _redraw_once:
				model.apply_pose(delta)
				_redraw_once = false
				viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			elif absf(_turn - _turn_target) > 0.01:
				viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
