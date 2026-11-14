extends CanvasLayer
## The FIGHT loading screen (Boss 2026-11-14: replaces the spinning card summon). A full-screen overlay in the carved
## hub look (dimmed night backdrop, carved wood board, parchment title ribbon, ink-pill bar with a gold-leaf fill, the
## same bar as the web loading page) that lives on /root so it stays up across the change to the battle scene.
##
## Steps, one bar:
##   1. packs   (split web build only) the background battle-pack download (client/pack_fetcher.gd), if not in yet
##   2. loading the battle scene and its heavy resources (squad bodies/outfits/hair, the squad's class-skill VFX,
##              the journey's monster models and animations): threaded on desktop (ResourceLoader.load_threaded_*),
##              one resource per frame on the single-threaded web build so the bar keeps painting
##   3. build   GameState.start_journey() (unchanged); the overlay stays up until the stage has drawn its first
##              frames (stage_view._scene_presented), then fades out
##   connecting (online) the room is being opened / joined; an indeterminate bar until the stage is presented
## Display only: game rules and the journey itself stay in GameState / logic/.

const CardTokens := preload("res://client/card_tokens.gd")
const CarvedLook := preload("res://client/carved_look.gd")
const CarvedStrip := preload("res://client/carved_strip.gd")
const PackFetcher := preload("res://client/pack_fetcher.gd")
const CharacterModel := preload("res://client/characters/studio05_character_model.gd")
const ClassSkillVfx := preload("res://client/skills/class_skill_vfx.gd")
const SkillData := preload("res://logic/class_skills/skill_data.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const JourneyData := preload("res://logic/journey_data.gd")
const MapLoader := preload("res://logic/map_loader.gd")
const StatusVfx := preload("res://client/status_vfx.gd")

const NODE_NAME := "FightLoading"
const LAYER := 100  ## over the stage's own HUD and loading label (layer 30)

signal failed(message: String)  ## the fight did not start (the hub shows `message` when it is not empty)
signal closed

enum Step { PACKS, LOADING, BUILD, CONNECTING, DONE }

var reduced_motion := false
var step := Step.PACKS
var progress := 0.0  ## 0..1, never goes back
var _paths: Array[String] = []
var _requested: Dictionary = {}  ## path -> true (threaded requests in flight)
var _hold: Array = []  ## the loaded resources, kept until the stage is up (so stage_view's load() hits the cache)
var _threaded := true
var _pack_share := 0.0  ## the part of the bar the pack download takes (0 when the packs were already in)
var _hub: Node  ## the scene FIGHT was pressed on: a different current scene means the change happened
var _build_frames := 0
var _connect_left := 0.0
var _stripe := 0.0
var _pack_failed := false
var _s := 1.0

var _root: Control
var _back: TextureRect
var _shade: ColorRect
var _board: Panel
var _ribbon: CarvedStrip
var _title: Label
var _groove: CarvedStrip
var _fill: FillBar
var _caption: Label


## Opens the overlay on /root (or returns the one already open).
static func open(tree: SceneTree, motion_reduced: bool = false) -> CanvasLayer:
	var found := tree.root.get_node_or_null(NODE_NAME) as CanvasLayer
	if found != null:
		return found
	var overlay: CanvasLayer = (load("res://client/fight_loading.gd") as GDScript).new()
	overlay.name = NODE_NAME
	overlay.reduced_motion = motion_reduced
	tree.root.add_child(overlay)
	return overlay


static func is_open(tree: SceneTree) -> bool:
	return tree != null and tree.root.get_node_or_null(NODE_NAME) != null


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_threaded = not OS.has_feature("web")  # the web export has no threads (export_presets thread_support=false)
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()
	if not reduced_motion:
		_root.modulate.a = 0.0
		create_tween().tween_property(_root, "modulate:a", 1.0, CardTokens.FADE_SECONDS)


## FIGHT: packs -> resources -> GameState.start_journey() -> the stage's first frames.
func start_fight() -> void:
	_hub = get_tree().current_scene
	if GameState.account_session != null:
		_paths = []  # online: the room decides the map; the stage loads what it needs
	else:
		_paths = battle_paths()
	if not PackFetcher.battle_ready(get_tree()):
		_pack_share = 0.5
		var node := get_tree().root.get_node_or_null(PackFetcher.BATTLE_NODE)
		if node != null and node.state == node.State.FAILED:
			node.retry()
		_set_step(Step.PACKS)
	else:
		_begin_loading()


## Online room join (client/online/room_panel.gd): no local loading, just "Connecting…" until the stage is up.
func start_connecting() -> void:
	_hub = get_tree().current_scene
	_set_step(Step.CONNECTING)


## The resources the first battle frame needs (every path exists). Squad looks from GameState, monsters from the
## journey data (and its fight maps' art), skill VFX from the class skill table, every status loop.
static func battle_paths() -> Array[String]:
	var paths: Array[String] = ["res://scenes/stage.tscn"]
	var skills = SkillData.load_default()
	if GameState.ensure_profile():
		for look in GameState.squad_looks().slice(0, GameState.squad_size):
			var cls := str(look.get("class", ""))
			for p in [CharacterModel.body_path(cls), CharacterModel.gear_path(cls), CharacterModel.hair_path(cls, str(look.get("hair", "")))]:
				_add_path(paths, str(p))
			if bool(look.get("silver", false)):
				_add_path(paths, CharacterModel.silver_path())
			for id in skills.class_skills(cls):
				_add_path(paths, ClassSkillVfx.scene_path(str(skills.skill(str(id)).get("vfx", ClassSkillVfx.PREFIX + str(id)))))
	for dir in DirAccess.get_directories_at(StatusVfx.ROOT):  # status loops (fighter_view prewarms them all)
		_add_path(paths, StatusVfx.scene_path(dir))
	var combat = CombatDataLoader.load_default()
	var journey_id: String = GameState.WAVE_JOURNEY if GameState.auto_battle else GameState.DEFAULT_JOURNEY
	var data = JourneyData.load_by_id(journey_id, combat.enemies.keys())
	for map_id in data.combat_maps:  # the first fight is on one of these (the art scene of each map)
		_add_path(paths, str(MapLoader.load_by_id(str(map_id)).art_scene))
	var types := {}
	for stage in data.stages:
		for fight in [stage, stage.get("challenge", {})]:
			for enemy in fight.get("enemies", []):
				types[str(enemy.get("type", ""))] = true
	for type in types:
		var definition: Dictionary = combat.enemies.get(type, {})
		_add_path(paths, str(definition.get("model", "")))
		_add_path(paths, str(definition.get("animations", "")))
	return paths


static func _add_path(paths: Array[String], path: String) -> void:
	if not path.is_empty() and not paths.has(path) and ResourceLoader.exists(path):
		paths.append(path)


# ------------------------------------------------------------------ steps
func _set_step(next: Step) -> void:
	step = next
	_fill.indeterminate = next == Step.CONNECTING
	_refresh_text()


func _begin_loading() -> void:
	_set_step(Step.LOADING)
	if _threaded:
		for path in _paths:
			if ResourceLoader.load_threaded_request(path, "", false) == OK:
				_requested[path] = true
			else:
				push_warning("fight loading: threaded request refused for " + path)
	else:
		_load_one_per_frame()


## Web (no threads): plain loads, one per drawn frame, so the bar repaints between them.
func _load_one_per_frame() -> void:
	var total := maxi(_paths.size(), 1)
	var done := 0
	for path in _paths:
		await _next_drawn_frame()
		if not is_inside_tree():
			return
		var res := load(path)
		if res != null:
			_hold.append(res)
		done += 1
		_advance(_pack_share + (0.9 - _pack_share) * float(done) / float(total))
	_paths.clear()
	_begin_build()


func _begin_build() -> void:
	_set_step(Step.BUILD)
	_advance(0.9)
	# Paint the 90% state before the blocking frame of the scene change (stage_view._ready).
	await _next_drawn_frame()
	await _next_drawn_frame()
	if not is_inside_tree():
		return
	if not GameState.start_journey():
		_fail(CardTokens.t("change_failed"))
		return
	if GameState.account_session != null:
		_connect_left = CardTokens.FIGHT_LOAD_CONNECT_SECONDS
		_set_step(Step.CONNECTING)


func _process(delta: float) -> void:
	match step:
		Step.PACKS:
			_poll_packs()
		Step.LOADING:
			if _threaded:
				_poll_threaded()
		Step.BUILD, Step.CONNECTING:
			_poll_stage(delta)
	if _fill.indeterminate and not reduced_motion:
		_stripe = fmod(_stripe + delta * CardTokens.FIGHT_LOAD_STRIPE_SPEED, 1.0)
		_fill.stripe = _stripe
		_fill.queue_redraw()


func _poll_packs() -> void:
	var node := get_tree().root.get_node_or_null(PackFetcher.BATTLE_NODE)
	var was_failed := _pack_failed
	_pack_failed = node != null and node.state == node.State.FAILED
	if _pack_failed != was_failed:
		_refresh_text()
	_advance(_pack_share * PackFetcher.battle_fraction(get_tree()))
	if PackFetcher.battle_ready(get_tree()):
		_paths = battle_paths()  # (now mounted: the battle files exist)
		_begin_loading()


func _poll_threaded() -> void:
	var sum := 0.0
	var waiting := false
	for path in _paths:
		if not _requested.has(path):
			sum += 1.0
			continue
		var p: Array = []
		var status := ResourceLoader.load_threaded_get_status(path, p)
		match status:
			ResourceLoader.THREAD_LOAD_LOADED:
				_hold.append(ResourceLoader.load_threaded_get(path))
				_requested.erase(path)
				sum += 1.0
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				sum += float(p[0]) if not p.is_empty() else 0.0
				waiting = true
			_:
				push_warning("fight loading: could not load " + path)
				_requested.erase(path)
				sum += 1.0
	_advance(_pack_share + (0.9 - _pack_share) * sum / float(maxi(_paths.size(), 1)))
	if not waiting and _requested.is_empty():
		_paths.clear()
		_begin_build()


## After start_journey: done when the stage has drawn its first frames, or when another scene (route screen, error)
## took over. Online: fails when the room could not be opened.
func _poll_stage(delta: float) -> void:
	var scene := get_tree().current_scene
	var changed := scene != null and scene != _hub
	if step == Step.CONNECTING:
		_connect_left -= delta
		if not changed and GameState.remote_session == null and not bool(GameState.get("_solo_connecting")) and _connect_left < CardTokens.FIGHT_LOAD_CONNECT_SECONDS - 0.5:
			_fail(GameState.online_error)
			return
		if _connect_left <= 0.0 and not changed:
			_fail(GameState.online_error if not GameState.online_error.is_empty() else CardTokens.t("fight_load_failed"))
			return
	if not changed:
		return
	if step == Step.CONNECTING:
		_set_step(Step.BUILD)
	_build_frames += 1
	_advance(minf(0.98, progress + CardTokens.FIGHT_LOAD_BUILD_CREEP))
	var presented := "_scene_presented" in scene and bool(scene.get("_scene_presented"))
	if presented or not "_scene_presented" in scene or _build_frames > CardTokens.FIGHT_LOAD_BUILD_FRAMES:
		_finish()


func _finish() -> void:
	step = Step.DONE
	_advance(1.0)
	_hold.clear()
	if reduced_motion:
		_close()
		return
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, CardTokens.FADE_SECONDS)
	tween.tween_callback(_close)


func _fail(message: String) -> void:
	step = Step.DONE
	for path in _requested:
		ResourceLoader.load_threaded_get(path)  # (finish the in-flight requests so they are not left dangling)
	_requested.clear()
	_hold.clear()
	failed.emit(message)
	_close()


func _close() -> void:
	closed.emit()
	queue_free()


## Esc / gamepad B / back: give up before the scene change (the pack download keeps going in the background).
func _unhandled_input(event: InputEvent) -> void:
	if (step == Step.PACKS or step == Step.LOADING) and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_fail("")


func _on_tap(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	var touch := event as InputEventScreenTouch
	if (button != null and button.pressed) or (touch != null and touch.pressed):
		if step == Step.PACKS and _pack_failed:
			var node := get_tree().root.get_node_or_null(PackFetcher.BATTLE_NODE)
			if node != null:
				node.retry()


func _advance(value: float) -> void:
	var v := clampf(value, 0.0, 1.0)
	if v <= progress and step != Step.CONNECTING:
		return
	progress = maxf(progress, v)
	_fill.fraction = progress
	_fill.queue_redraw()
	_refresh_text()


func _next_drawn_frame() -> void:
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw


# ------------------------------------------------------------------ look
func _refresh_text() -> void:
	if _title == null:
		return
	var title := CardTokens.t("fight_connecting") if step == Step.CONNECTING else CardTokens.t("fight_loading_bar") % int(round(progress * 100.0))
	var caption: String
	match step:
		Step.PACKS:
			caption = CardTokens.t("fight_load_failed") if _pack_failed else CardTokens.t("fight_step_download")
		Step.CONNECTING:
			caption = CardTokens.t("fight_step_room")
		_:
			caption = CardTokens.t("fight_step_battle")
	var refit := title != _title.text or caption != _caption.text
	_title.text = title
	_caption.text = caption
	if refit:
		_fit_text()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # the hub underneath takes no clicks while loading
	_root.gui_input.connect(_on_tap)
	add_child(_root)
	_back = CardTokens.carved_rect(CardTokens.CARVED_BG)
	_back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_back.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_back)
	_shade = ColorRect.new()
	_shade.color = CarvedLook.SHADE
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_shade)
	_board = Panel.new()
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_board)
	_groove = CarvedStrip.new(CardTokens.CARVED_PILL, CardTokens.CARVED_PILL_CAP)
	_board.add_child(_groove)
	_fill = FillBar.new()
	_groove.add_child(_fill)
	_caption = CardTokens.hub_label("", CardTokens.FIGHT_LOAD_FONT_CAPTION, CardTokens.HUB_CREAM, 1.0, 0, "medium")
	_board.add_child(_caption)
	_ribbon = CarvedStrip.new(CardTokens.CARVED_TITLE, CarvedLook.TITLE_CAP)
	_root.add_child(_ribbon)
	_title = CardTokens.hub_label("", CardTokens.FIGHT_LOAD_FONT_TITLE, CardTokens.HUB_INK, 1.0)
	_ribbon.add_child(_title)
	_refresh_text()


func _layout() -> void:
	if _root == null:
		return
	var screen := get_viewport().get_visible_rect().size
	_root.size = screen
	_s = CardTokens.scale_for(screen)
	var board_size := Vector2(minf(CardTokens.FIGHT_LOAD_BOARD.x * _s, screen.x * 0.9), CardTokens.FIGHT_LOAD_BOARD.y * _s)
	_board.size = board_size
	_board.position = (screen - board_size) * 0.5 + Vector2(0.0, CardTokens.FIGHT_LOAD_RIBBON.y * _s * 0.25)
	CarvedLook.clear(_board)
	CarvedLook.skin_of(_board).set_nine(CarvedLook.WOOD, CarvedLook.WOOD_MARGIN, CardTokens.FIGHT_LOAD_BOARD_K * _s)
	var ribbon := Vector2(minf(CardTokens.FIGHT_LOAD_RIBBON.x * _s, screen.x * 0.8), CardTokens.FIGHT_LOAD_RIBBON.y * _s)
	_ribbon.size = ribbon
	_ribbon.position = Vector2((screen.x - ribbon.x) * 0.5, _board.position.y - ribbon.y * CardTokens.FIGHT_LOAD_RIBBON_OVER)
	var text := CardTokens.CARVED_TITLE_TEXT
	_title.size = Vector2(ribbon.x * text.size.x, ribbon.y * text.size.y)
	_title.position = Vector2(ribbon.x * text.position.x, ribbon.y * text.position.y)
	var bar := Vector2(board_size.x - CardTokens.FIGHT_LOAD_BAR_PAD * 2.0 * _s, CardTokens.FIGHT_LOAD_BAR_H * _s)
	_groove.size = bar
	_groove.position = Vector2(CardTokens.FIGHT_LOAD_BAR_PAD * _s, board_size.y * CardTokens.FIGHT_LOAD_BAR_Y - bar.y * 0.5)
	var inset := Vector2(bar.y * CardTokens.FIGHT_LOAD_FILL_INSET.x, bar.y * CardTokens.FIGHT_LOAD_FILL_INSET.y)
	_fill.position = inset
	_fill.size = bar - inset * 2.0
	_caption.size = Vector2(bar.x, CardTokens.FIGHT_LOAD_FONT_CAPTION * 1.6 * _s)
	_caption.position = Vector2(_groove.position.x, _groove.position.y + bar.y + CardTokens.FIGHT_LOAD_CAPTION_GAP * _s)
	_fit_text()


func _fit_text() -> void:
	if _title.size.x > 0.0:
		CardTokens.hub_fit(_title, _title.text, CardTokens.FIGHT_LOAD_FONT_TITLE, _title.size.x, CardTokens.HUB_INK, _s)
	if _caption.size.x > 0.0:
		CardTokens.hub_fit(_caption, _caption.text, CardTokens.FIGHT_LOAD_FONT_CAPTION, _caption.size.x, CardTokens.HUB_CREAM, _s, 0, "medium")


## The gold-leaf fill inside the ink-pill groove (play_template.html #gate progress): a light-to-deep gold wash with
## a dark lower edge and a light upper line. Indeterminate (connecting): moving gold stripes instead.
class FillBar extends Control:
	var fraction := 0.0
	var indeterminate := false
	var stripe := 0.0
	var _wash: GradientTexture2D

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		gradient.colors = PackedColorArray([CardTokens.FIGHT_LOAD_GOLD_TOP, CardTokens.FIGHT_LOAD_GOLD_MID, CardTokens.FIGHT_LOAD_GOLD_LOW])
		_wash = GradientTexture2D.new()
		_wash.gradient = gradient
		_wash.fill_from = Vector2(0.0, 0.0)
		_wash.fill_to = Vector2(0.0, 1.0)
		_wash.width = 4
		_wash.height = 64

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		if indeterminate:
			var step_w := size.y * 1.2
			var x := -step_w * 2.0 + stripe * step_w * 2.0
			while x < size.x:
				var a := maxf(x, 0.0)
				var b := minf(x + step_w, size.x)
				if b > a:
					draw_texture_rect(_wash, Rect2(a, 0.0, b - a, size.y), false, CardTokens.FIGHT_LOAD_STRIPE)
				x += step_w * 2.0
			return
		var w := size.x * clampf(fraction, 0.0, 1.0)
		if w <= 0.0:
			return
		draw_texture_rect(_wash, Rect2(0.0, 0.0, w, size.y), false)
		var line := maxf(1.0, size.y * 0.08)
		draw_rect(Rect2(0.0, size.y - line, w, line), CardTokens.FIGHT_LOAD_GOLD_EDGE)
		draw_rect(Rect2(0.0, 0.0, w, maxf(1.0, line * 0.5)), CardTokens.FIGHT_LOAD_GOLD_SHINE)
