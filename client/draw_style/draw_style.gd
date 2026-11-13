extends Node
## Drawn ("ink-and-wash") battle look. Boss 2026-11-13: "the fight should feel like watching a cartoon"; after
## trying the three prototypes on a phone Boss picked ink_c, which is now the default (docs/tech/draw_style.md).
## Two parts:
##   materials  the stage scenery gets client/draw_style/ink_world.gdshader (2-3 light bands, hatching on faces turned
##              from the sun, a soft watercolour wash, subtle paper grain, muted warm colour) and brush-like ink
##              outlines (ink_outline_brush.gdshader); the monsters' ink outline becomes the brush line. Cost ~0 ms.
##   screen     one full-screen pass (ink_screen.gdshader): depth ink lines, softened value bands, light hatching
##              inside cast shadows. It reads a copy of the screen and depth, which costs 1-3 ms on WebGL2 at render
##              scale 0.5 but 6-20 ms at 1.0, so it runs only at scale 0.5 and switches itself off for the rest of the
##              session when the battle runs below SLOW_FPS (a slow device). HP bars, numbers and VFX draw after it.
## The graphics setting `drawn_style` (client/graphics_options.gd): "on" = materials + screen pass, "lite" = materials
## only, "off" = the old look. Debug overrides: web URL `?style=` / native `-- --style=` with on|lite|off, or the
## prototype ids ink_a (= lite), ink_b (screen only), ink_c (= on). Presentation only: never touches logic/.

const InkStyle := preload("res://client/ink_style.gd")
const Options := preload("res://client/graphics_options.gd")
const WORLD_SHADER := preload("res://client/draw_style/ink_world.gdshader")
const BRUSH_SHADER := preload("res://client/draw_style/ink_outline_brush.gdshader")
const SCREEN_SHADER := preload("res://client/draw_style/ink_screen.gdshader")
const MODES := ["off", "lite", "on", "ink_b"]
const ALIASES := {"ink_a": "lite", "ink_c": "on"}
const DRAWN_KEYS := ["drawn_off", "drawn_lite", "drawn_on"]  ## panel words, in the order of Options.DRAWN_STYLES
const SCREEN_SCALE := 0.5  ## the only render scale the screen pass runs at (the shipped default)
const SLOW_FPS := 27.0  ## below this for SLOW_WINDOWS windows in a row: the screen pass goes off for the session
const SLOW_WINDOW := 2.0  ## seconds per measuring window
const SLOW_WINDOWS := 2
const SLOW_WARMUP := 3.0  ## seconds after the stage opens before measuring (loading hitches are not "slow")
const STAGE_OUTLINE_WIDTH := 0.03  ## metres before the pixel limits (props are big: a thick pen)
const MONSTER_OUTLINE_WIDTH := 0.008
const ENV_SATURATION := 0.95  ## the stage keeps its greens and warm browns (0.85 read grey on the goblin camp)

static var _override := "?"  ## from the URL / command line, "" = none (read once)
static var slow_device := false  ## set by the guard; kept until the game restarts
static var _two_sided_shader: Shader
static var _world_cache: Dictionary = {}  ## source material -> ShaderMaterial (shared by all instances)
static var _sun_direction := Vector3(0.47, 0.53, 0.70)  ## towards the stage's sun, for ink_world.gdshader hatching

var _camera: Camera3D
var _screen: MeshInstance3D
var _revision := -1
var _age := 0.0
var _window_time := 0.0
var _window_frames := 0
var _slow_windows := 0


## Words of the graphics panel's "Drawn style" control, Thai first and English second (the same layout and language
## switch as client/card_tokens.gd STRINGS, which is not touched here).
const STRINGS := {
	"drawn_style": ["ลายเส้นวาดมือ", "Drawn style"],
	"drawn_on": ["เต็ม", "On"],
	"drawn_lite": ["เบา", "Lite"],
	"drawn_off": ["ปิด", "Off"],
	"drawn_hint": ["เต็ม: เส้นหมึกทั้งจอที่ 50% เท่านั้น เครื่องช้าจะลดเป็นเบาเอง", "On: full-screen ink at 50% only; slow devices drop to Lite"],
}


static func t(key: String) -> String:
	var entry: Array = STRINGS.get(key, [key, key])
	return str(entry[0 if preload("res://client/card_tokens.gd").language == "th" else 1])


## The graphics panel's "Drawn style" control (client/graphics_panel.gd adds it under its other settings): a title,
## three choice buttons On / Lite / Off in one group, and a one-line hint. Uses the panel's theme (no overrides).
static func settings_control() -> VBoxContainer:
	var holder := VBoxContainer.new()
	var title := Label.new()
	title.text = t("drawn_style")
	holder.add_child(title)
	var row := HBoxContainer.new()
	var group := ButtonGroup.new()
	var current := str(Options.value("drawn_style"))
	for index in [2, 1, 0]:  # On, Lite, Off
		var choice: String = Options.DRAWN_STYLES[index]
		var button := Button.new()
		button.name = "Drawn_" + choice
		button.text = t(DRAWN_KEYS[index])
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = choice == current
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func(): Options.set_value("drawn_style", choice))
		row.add_child(button)
	holder.add_child(row)
	var hint := Label.new()
	hint.text = t("drawn_hint")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(260, 0)
	holder.add_child(hint)
	return holder


## The look for this battle: "off", "lite", "on" (or "ink_b", the screen-only prototype).
static func mode() -> String:
	if _override == "?":
		_override = ""
		var wanted := ""
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--style="):
				wanted = arg.substr(8)
		if OS.has_feature("web"):
			var from_url = JavaScriptBridge.eval("new URLSearchParams(location.search).get('style') || ''", true)
			if from_url != null and str(from_url) != "":
				wanted = str(from_url)
		wanted = str(ALIASES.get(wanted, wanted))
		if MODES.has(wanted):
			_override = wanted
	if not _override.is_empty():
		return _override
	var chosen := str(Options.value("drawn_style"))
	return chosen if MODES.has(chosen) else "on"


## True when the screen pass may run now (mode "on"/"ink_b", render scale 0.5, the device not found slow).
## A debug override (URL / command line) keeps it on at any scale, for measuring.
static func screen_allowed() -> bool:
	var m := mode()
	if m != "on" and m != "ink_b":
		return false
	if not _override.is_empty():
		return true
	return is_equal_approx(float(Options.value("render_scale")), SCREEN_SCALE) and not slow_device


## Applies the look to a built stage (art, fighters, environment) and its camera. Called once at the end of
## StageView._ready. The materials stay for the battle; the screen pass follows the settings live.
static func apply(stage: Node3D, camera: Camera3D, fighters: Array) -> void:
	var m := mode()
	if m == "off" or camera == null:
		return
	if m == "lite" or m == "on":
		_sun_direction = Vector3(0.47, 0.53, 0.70)
		for node in stage.find_children("*", "DirectionalLight3D", true, false):
			if not str(node.name).begins_with("Character"):  # the stage's sun (or moon), not the character lights
				_sun_direction = (node as Node3D).global_transform.basis.z.normalized()
				break
		# The scenery that is actually drawn: the map's art scene (big stages), the arena board/camp built by
		# client/arena_props.gd (GoblinCampIsland, FloatingIsland); never the fighters or effects.
		for root_name in ["ArtScene", "GoblinCampIsland", "FloatingIsland"]:
			var root := stage.find_child(root_name, false, false) as Node3D
			if root != null and root.visible:
				_paint_art(root)
		_tone_environment(stage, ENV_SATURATION)
	# Monster outlines become the brush line and HP bars move after the screen pass in the draw order (_keep_clean).
	# Later waves arrive after this: every new node is checked once, deferred past fighter_view's own setup.
	var tree := stage.get_tree()
	var watch := func(node: Node) -> void:
		_check_node.call_deferred(weakref(node), m)
	tree.node_added.connect(watch)
	stage.tree_exiting.connect(func() -> void: tree.node_added.disconnect(watch))
	for view in fighters:
		if view == null:
			continue
		for node in view.find_children("*", "GeometryInstance3D", true, false):
			_check_node.call_deferred(weakref(node), m)
	if m == "on" or m == "ink_b":
		var driver := new()
		driver.name = "DrawStyleScreen"
		driver._camera = camera
		driver._screen = _screen_quad(m)
		camera.add_child(driver._screen)
		stage.add_child(driver)
		driver._fit()
		driver._screen.visible = screen_allowed()
		if m == "ink_b":
			_tone_environment(stage, 1.0)


## A node that entered during the battle: a monster's InkOutline gets the brush, a bar quad joins the clean layer.
static func _check_node(reference: WeakRef, m: String) -> void:
	var node := reference.get_ref() as GeometryInstance3D
	if node == null:
		return
	if (m == "lite" or m == "on") and str(node.name) == "InkOutline" and node is MeshInstance3D:
		_rebrush(reference)
	if m == "on" or m == "ink_b":
		_keep_clean(node)


## HP bars (fighter_view.gd: unshaded, billboard, no depth test) are opaque, so they would be drawn before the screen
## pass and get its lines, bands and grain. As alpha-blended materials (alpha stays 1, so they look the same) they
## are drawn after it, by their own render priority, and stay clean. Numbers, labels and VFX are transparent already.
static func _keep_clean(node: GeometryInstance3D) -> void:
	var material := node.material_override as BaseMaterial3D
	if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return
	if material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and material.no_depth_test and material.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func _process(delta: float) -> void:
	_fit()
	if _revision != Options.revision:  # the graphics settings changed (render scale, drawn style)
		_revision = Options.revision
		_screen.visible = screen_allowed()
	_watch_speed(delta)


## The slow-device guard: after the warm-up, if SLOW_WINDOWS windows in a row average under SLOW_FPS while the
## screen pass is drawn, it goes off for the rest of the session (the materials stay).
func _watch_speed(delta: float) -> void:
	_age += delta
	if _age < SLOW_WARMUP or _screen == null or not _screen.visible or not _override.is_empty():
		return
	_window_time += delta
	_window_frames += 1
	if _window_time < SLOW_WINDOW:
		return
	var fps := float(_window_frames) / _window_time
	_window_time = 0.0
	_window_frames = 0
	_slow_windows = _slow_windows + 1 if fps < SLOW_FPS else 0
	if _slow_windows >= SLOW_WINDOWS:
		slow_device = true
		_screen.visible = false
		print("draw_style: %.1f fps with the screen pass: it is off for this session (materials stay)" % fps)


## Keeps the screen quad just in front of the camera and covering its whole view (fov and aspect change).
func _fit() -> void:
	if _camera == null or _screen == null:
		return
	var distance := _camera.near * 1.5
	var size := _camera.get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	var height := 2.0 * distance * tan(deg_to_rad(_camera.fov) * 0.5) * 1.1
	(_screen.mesh as QuadMesh).size = Vector2(height * aspect, height)
	_screen.position = Vector3(0.0, 0.0, -distance)


static func _screen_quad(style: String) -> MeshInstance3D:
	var material := ShaderMaterial.new()
	material.shader = SCREEN_SHADER
	material.render_priority = Material.RENDER_PRIORITY_MIN  # first transparent draw: VFX/bars/numbers stay clean
	if style == "on":
		# The stage materials already carry wash, grain and hatching on the sides away from the sun; the screen
		# pass adds what materials cannot: lines where depth jumps or bends, softened bands, and light hatching
		# inside cast shadows. Grain and wash stay low so the ground does not look like dirty paint.
		material.set_shader_parameter("band_mix", 0.35)
		material.set_shader_parameter("hatch_strength", 0.22)
		material.set_shader_parameter("grain_strength", 0.025)
		material.set_shader_parameter("wash_strength", 0.0)
		material.set_shader_parameter("saturation", 1.0)
		material.set_shader_parameter("warmth", Vector3(1.02, 1.0, 0.97))
		material.set_shader_parameter("paper_mix", 0.04)
	var quad := MeshInstance3D.new()
	quad.name = "InkScreenPass"
	quad.mesh = QuadMesh.new()
	quad.material_override = material
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.extra_cull_margin = 16384.0
	quad.set_meta("toon_prepared", true)  # (client/toon_style.gd: leave it alone)
	return quad


## Every lit map material becomes the ink-and-wash material; closed solids get a brush outline copy.
static func _paint_art(art: Node3D) -> void:
	for node in art.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if not geometry.is_visible_in_tree():
			continue  # (arena_props hides the big-stage kit it copies from)
		var mesh: Mesh = null
		if geometry is MeshInstance3D:
			mesh = (geometry as MeshInstance3D).mesh
		elif geometry is MultiMeshInstance3D and (geometry as MultiMeshInstance3D).multimesh != null:
			mesh = (geometry as MultiMeshInstance3D).multimesh.mesh
		if mesh == null:
			continue
		geometry.set_meta("toon_prepared", true)  # (client/toon_style.gd would otherwise re-material it)
		var two_sided := false
		var flat: bool = bool(geometry.get_meta("toon_no_outline", false)) or str(geometry.name) == "Ground"
		for surface in mesh.get_surface_count():
			var source := mesh.surface_get_material(surface) as BaseMaterial3D
			if geometry is MeshInstance3D and (geometry as MeshInstance3D).get_surface_override_material(surface) is BaseMaterial3D:
				source = (geometry as MeshInstance3D).get_surface_override_material(surface)
			if source == null or source.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			two_sided = two_sided or source.cull_mode == BaseMaterial3D.CULL_DISABLED and not str(source.resource_name).begins_with("Relic")
			var painted := _world_material(source)
			if geometry is MeshInstance3D:
				(geometry as MeshInstance3D).set_surface_override_material(surface, painted)
			else:
				geometry.material_override = painted  # (multimeshes here have one surface)
		# Thin cards (grass, ferns) and the flat ground get no hull: it would be a dark smear.
		if flat or two_sided:
			continue
		var outline: GeometryInstance3D
		if geometry is MeshInstance3D:
			var copy := MeshInstance3D.new()
			copy.mesh = InkStyle.outline_mesh(mesh)
			outline = copy
		else:
			var copy := MultiMeshInstance3D.new()
			var multimesh := (geometry as MultiMeshInstance3D).multimesh.duplicate() as MultiMesh
			multimesh.mesh = InkStyle.outline_mesh(mesh)
			copy.multimesh = multimesh
			outline = copy
		outline.name = "InkBrush"
		outline.material_override = _stage_brush()
		outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		outline.set_meta("toon_prepared", true)
		geometry.add_child(outline)


static func _world_material(source: BaseMaterial3D) -> ShaderMaterial:
	if _world_cache.has(source):
		return _world_cache[source]
	var two_sided := source.cull_mode == BaseMaterial3D.CULL_DISABLED
	var material := ShaderMaterial.new()
	material.shader = _two_sided() if two_sided else WORLD_SHADER
	material.set_shader_parameter("albedo", source.albedo_color)
	material.set_shader_parameter("use_texture", source.albedo_texture != null)
	if source.albedo_texture != null:
		material.set_shader_parameter("albedo_tex", source.albedo_texture)
	material.set_shader_parameter("use_vertex_color", source.vertex_color_use_as_albedo)
	material.set_shader_parameter("two_sided", two_sided)
	material.set_shader_parameter("sun_direction", _sun_direction)
	_world_cache[source] = material
	return material


static func _two_sided() -> Shader:
	if _two_sided_shader == null:
		_two_sided_shader = Shader.new()
		_two_sided_shader.code = WORLD_SHADER.code.replace("cull_back", "cull_disabled")
	return _two_sided_shader


static var _stage_brush_material: ShaderMaterial


## The scenery's pen: at least 1.5 px and up to 4.5 px, so fences, huts and stones read as inked at the
## board camera's distance (the characters' lines stay thin).
static func _stage_brush() -> ShaderMaterial:
	if _stage_brush_material == null:
		_stage_brush_material = _brush(STAGE_OUTLINE_WIDTH)
		_stage_brush_material.set_shader_parameter("min_pixels", 1.5)
		_stage_brush_material.set_shader_parameter("max_pixels", 4.5)
	return _stage_brush_material


static func _brush(width: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = BRUSH_SHADER
	material.set_shader_parameter("width", width)
	return material


static var _brush_monster: ShaderMaterial


static func _rebrush(reference: WeakRef) -> void:
	var node := reference.get_ref() as MeshInstance3D
	if node == null:
		return
	if _brush_monster == null:
		_brush_monster = _brush(MONSTER_OUTLINE_WIDTH)
	node.material_override = _brush_monster


## Slightly muted colour in the environment's own adjustment (no extra pass).
static func _tone_environment(stage: Node, saturation_scale: float) -> void:
	for node in stage.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (node as WorldEnvironment).environment
		if env != null:
			env.adjustment_enabled = true
			env.adjustment_saturation *= saturation_scale
