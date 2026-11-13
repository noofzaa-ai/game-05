extends Node
## Draw-style PROTOTYPE (tech-artist 2026-11-13, Boss: "the fight should feel like watching a cartoon";
## ink-and-wash illustration look). Off by default: the shipped look is unchanged unless a style is chosen by
##   - the web page URL `?style=ink_a|ink_b|ink_c`,
##   - the command line `-- --style=ink_a|ink_b|ink_c` (native, tools/shots/draw_style_shots.gd),
##   - the project setting `zorx/rendering/draw_style` (not in project.godot = "").
## Styles:
##   ink_a  material level: the stage art gets client/draw_style/ink_world.gdshader (2-3 light bands, shadow
##          hatching, wash + paper grain, muted warm colour) and brush-like ink outlines; monsters get the brush
##          outline too. Characters (studio05 toon) are unchanged.
##   ink_b  screen level: the normal frame, then one full-screen pass (ink_screen.gdshader): depth-edge ink lines,
##          flat value bands, hatching in the dark, paper and warmth.
##   ink_c  A's stage materials and outlines + B's screen pass at reduced strength (lines, bands, light hatching
##          inside cast shadows; little extra grain).
## Presentation only: never touches logic/ or the fight. EXTENDING: a new style is a new entry in apply().

const InkStyle := preload("res://client/ink_style.gd")
const WORLD_SHADER := preload("res://client/draw_style/ink_world.gdshader")
const BRUSH_SHADER := preload("res://client/draw_style/ink_outline_brush.gdshader")
const SCREEN_SHADER := preload("res://client/draw_style/ink_screen.gdshader")
const STYLES := ["ink_a", "ink_b", "ink_c"]
const SETTING := "zorx/rendering/draw_style"
const STAGE_OUTLINE_WIDTH := 0.03  ## metres before the pixel limits (props are big: a thick pen)
const MONSTER_OUTLINE_WIDTH := 0.008

static var _chosen := "?"
static var _two_sided_shader: Shader
static var _world_cache: Dictionary = {}
static var _sun_direction := Vector3(0.47, 0.53, 0.70)  ## towards the stage's sun, for ink_world.gdshader hatching  ## source material -> ShaderMaterial (shared by all instances)

var _camera: Camera3D
var _screen: MeshInstance3D


## The chosen style id ("" = the normal look).
static func current() -> String:
	if _chosen != "?":
		return _chosen
	var style := str(ProjectSettings.get_setting(SETTING, ""))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--style="):
			style = arg.substr(8)
	if OS.has_feature("web"):
		var from_url = JavaScriptBridge.eval("new URLSearchParams(location.search).get('style') || ''", true)
		if from_url != null and str(from_url) != "":
			style = str(from_url)
	_chosen = style if STYLES.has(style) else ""
	return _chosen


## Applies the chosen style to a built stage (art, fighters, environment) and its camera. No-op by default.
## `fighters` = the fighter_view nodes. Called once at the end of StageView._ready.
static func apply(stage: Node3D, camera: Camera3D, fighters: Array) -> void:
	var style := current()
	if style.is_empty() or camera == null:
		return
	if style == "ink_a" or style == "ink_c":
		# The scenery that is actually drawn: the map's art scene (big stages), the arena board/camp built by
		# client/arena_props.gd (GoblinCampIsland, FloatingIsland) and plain solids; never the fighters or effects.
		_sun_direction = Vector3(0.47, 0.53, 0.70)
		for node in stage.find_children("*", "DirectionalLight3D", true, false):
			if not str(node.name).begins_with("Character"):  # the stage's sun (or moon), not the character lights
				_sun_direction = (node as Node3D).global_transform.basis.z.normalized()
				break
		for name in ["ArtScene", "GoblinCampIsland", "FloatingIsland"]:
			var root := stage.find_child(name, false, false) as Node3D
			if root != null and root.visible:
				_paint_art(root)
		for view in fighters:
			_brush_outlines(view)
		_tone_environment(stage, 0.85)
		# Monsters of later waves, and toon_style.gd re-setting outlines on its deferred pass, come after
		# this: re-brush every InkOutline that enters the tree (after toon_style's own deferred call).
		var tree := stage.get_tree()
		var watch := func(node: Node) -> void:
			if str(node.name) == "InkOutline" and node is MeshInstance3D:
				_rebrush.call_deferred(weakref(node))
		tree.node_added.connect(watch)
		stage.tree_exiting.connect(func() -> void: tree.node_added.disconnect(watch))
		for view in fighters:
			for node in view.find_children("InkOutline", "MeshInstance3D", true, false):
				_rebrush.call_deferred(weakref(node))
	if style == "ink_b" or style == "ink_c":
		var driver := new()
		driver.name = "DrawStyleScreen"
		driver._camera = camera
		driver._screen = _screen_quad(style)
		camera.add_child(driver._screen)
		stage.add_child(driver)
		driver._fit()
		if style == "ink_b":
			_tone_environment(stage, 1.0)


func _process(_delta: float) -> void:
	_fit()


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
	if style == "ink_c":
		# The stage materials already carry wash, grain and hatching on the sides away from the sun; the screen
		# pass adds what materials cannot: lines where depth jumps or bends, flatter bands, and hatching inside
		# cast shadows (lighter than in ink_b, so it does not double up).
		material.set_shader_parameter("band_mix", 0.5)
		material.set_shader_parameter("hatch_strength", 0.25)
		material.set_shader_parameter("grain_strength", 0.04)
		material.set_shader_parameter("wash_strength", 0.03)
		material.set_shader_parameter("saturation", 0.95)
		material.set_shader_parameter("warmth", Vector3(1.02, 1.0, 0.96))
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


## The monsters' ink outline (fighter_view.gd InkOutline children) becomes the thicker brush line.
static func _brush_outlines(view: Node) -> void:
	if view == null:
		return
	for node in view.find_children("InkOutline", "MeshInstance3D", true, false):
		_rebrush(weakref(node))


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
