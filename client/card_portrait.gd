extends Control
## The live 3D window of a class card (docs/ui/class_card_ui_handoff.md §3, §13): the class's own character
## (studio05 model, the card's hair / outfit / eyes / skin / makeup) playing the class idle in a small SubViewport.
## API: set_class(id), set_look(look), set_hover(on, pointer), pulse(), set_render_mode(mode), set_framing(kind),
## set_view_material(mat), set_idle_variants(on).
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
var framing := "full"  ## "full" body, "bust" (head and shoulders: squad tray), "card" / "card_deck" (old card), "hub" (leather card window) or "stage" (character screen window)
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
## Idle variants (set_idle_variants): the class idle most of the time, now and then another idle clip of the
## class (data/classes/<id>.json "idle_variants"), cross-faded. Timings: CardTokens.PORTRAIT_IDLE_*.
var _variants_on := false
var _variant_left := 0.0  ## seconds until the next switch
var _variant_index := -1  ## index into the class's other variants on show, -1 = the class idle
var _variant_rng := RandomNumberGenerator.new()
var _variant_last := -1  ## the variant shown last time (not picked again next)
var _variant_class := ""  ## the class the cycle was started for


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


## Cycles the class's idle variants (hub cards, character screen). Off = the class idle only (reduced motion,
## mini cards, battle). Each card has its own deterministic rhythm (seeded by its class).
func set_idle_variants(on: bool) -> void:
	_variants_on = on
	_restart_variants()


## The idle clips this class cycles besides its main idle (data/classes/<id>.json "idle_variants").
func idle_variant_clips() -> Array:
	var spec := CardDeck.class_data(class_id)
	var main := str(spec.get("states", {}).get("idle", ""))
	var out := []
	for clip in spec.get("idle_variants", []):
		if str(clip) != main and not out.has(str(clip)):
			out.append(str(clip))
	return out


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
	# The card's worn gear, the same entries battle (stage_view _player_looks) and the paper doll pass: the race
	# weapon, the four armour slots (shirt, pants, armband, shoes), the off-hand shield and the refine auras.
	# Display only: read from the card's loadout. No profile -> the class weapon and the bare Studio body.
	var gear := _card_looks()
	for key in ["weapon", "offhand", "refine", "armor_styles", "hide_hair"]:
		if gear.has(key):
			looks[key] = gear[key]
	for slot_id in ItemAssets.BODY_SLOTS:
		if gear.has(slot_id):
			looks[slot_id] = gear[slot_id]
	model.equipment_rest = true
	model.dress(looks)
	if _variant_class != class_id:
		_restart_variants()
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


## Back to the class idle and a fresh wait (class change, toggled).
func _restart_variants() -> void:
	_variant_class = class_id
	_variant_rng.seed = hash("idle_variants:" + class_id)
	_variant_index = -1
	_variant_last = -1
	_variant_left = _variant_rng.randf_range(CardTokens.PORTRAIT_IDLE_GAP_MIN, CardTokens.PORTRAIT_IDLE_GAP_MAX)
	if model != null:
		model.play_idle_clip("", 0.0 if not _variants_on else CardTokens.PORTRAIT_IDLE_BLEND)


func _step_variants(delta: float) -> void:
	if not _variants_on or model == null:
		return
	_variant_left -= delta
	if _variant_left > 0.0:
		return
	var clips := idle_variant_clips()
	if _variant_index >= 0 or clips.is_empty():  # a variant ends (or there is none): back to the class idle
		_variant_index = -1
		model.play_idle_clip("", CardTokens.PORTRAIT_IDLE_BLEND)
		_variant_left = _variant_rng.randf_range(CardTokens.PORTRAIT_IDLE_GAP_MIN, CardTokens.PORTRAIT_IDLE_GAP_MAX)
		return
	var pick := _variant_rng.randi_range(0, clips.size() - 1)
	if clips.size() > 1 and pick == _variant_last:  # never the same variant twice in a row
		pick = (pick + 1 + _variant_rng.randi_range(0, clips.size() - 2)) % clips.size()
	_variant_index = pick
	_variant_last = pick
	var clip: String = clips[_variant_index]
	if not model.play_idle_clip(clip, CardTokens.PORTRAIT_IDLE_BLEND):
		_variant_index = -1
		_variant_left = CardTokens.PORTRAIT_IDLE_GAP_MIN
		return
	var length: float = model.clip_length(clip)
	_variant_left = clampf(length, CardTokens.PORTRAIT_IDLE_SHOW_MIN, CardTokens.PORTRAIT_IDLE_SHOW_MAX)


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
	if framing in ["card", "card_deck", "hub", "stage", "bust"]:
		var tops := {"card": CardTokens.PORTRAIT_FRAME_TOP, "card_deck": CardTokens.PORTRAIT_DECK_TOP, "hub": CardTokens.PORTRAIT_HUB_TOP, "stage": CardTokens.PORTRAIT_STAGE_TOP, "bust": CardTokens.PORTRAIT_BUST_TOP}
		var bottoms := {"card": CardTokens.PORTRAIT_FRAME_BOTTOM, "card_deck": CardTokens.PORTRAIT_DECK_BOTTOM, "hub": CardTokens.PORTRAIT_HUB_BOTTOM, "stage": CardTokens.PORTRAIT_STAGE_BOTTOM, "bust": CardTokens.PORTRAIT_BUST_BOTTOM}
		var f_top: float = tops[framing]
		var f_bottom: float = bottoms[framing]
		var view_height := height / maxf(f_bottom - f_top, 0.1)
		var view_top := top + f_top * view_height
		_aim(view_height, view_top - view_height * 0.5)
		return
	var framed_height := maxf(height * CardTokens.PORTRAIT_FRAME_PAD, bounds.size.x * CardTokens.PORTRAIT_FRAME_PAD / maxf(aspect, 0.1))
	_aim(framed_height, center_y)


## Camera straight on, `view_height` world units tall at the model's plane, centred on `center_y`.
func _aim(view_height: float, center_y: float) -> void:
	var distance := view_height / (2.0 * tan(deg_to_rad(_camera.fov * 0.5)))
	var target := Vector3(0.0, center_y, 0.0)
	_camera.position = target + Vector3(0.0, 0.0, distance)
	_camera.look_at(target)
	if _mode == Mode.ONCE:  # (the camera is fitted deferred, after the change's redraw: draw again with it)
		_redraw_once = true
		_update_rendering()


func _process(delta: float) -> void:
	if model == null:
		return
	_step_variants(delta)
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
