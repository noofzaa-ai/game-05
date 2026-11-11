extends Node
## Global 3D presentation. Runs when a mesh enters the scene, never every frame.
## Godot equivalent of OutlineEffect: a culled expanded silhouette pass.
const InkStyle := preload("res://client/ink_style.gd")
const Options := preload("res://client/graphics_options.gd")
var _outline_enabled := true

const MAIN_WIDTH := 0.005
const HAIR_WIDTH := 0.002
const FINE_HAIR_WIDTH := 0.0015

func _ready() -> void:
	_outline_enabled=Options.enabled("outline")
	get_tree().node_added.connect(_node_added)
	_visit(get_tree().root)

func _visit(node: Node) -> void:
	_node_added(node)
	for child in node.get_children():
		_visit(child)

func _node_added(node: Node) -> void:
	if node is MeshInstance3D:
		_prepare.call_deferred(weakref(node))

func _prepare(reference: WeakRef) -> void:
	var mesh := reference.get_ref() as MeshInstance3D
	if mesh == null or mesh.mesh == null:
		return
	if mesh.has_meta("toon_prepared"):
		_apply_outline(mesh)
		return
	if str(mesh.name) in ["InkOutline", "RefineAura"]:
		_apply_outline(mesh)
		return
	mesh.set_meta("toon_prepared", true)
	var outlined := not bool(mesh.get_meta("toon_no_outline", false))  # (e.g. a flat ground: see goblin_ground.gd)
	var width := outline_width(mesh)
	var existing := mesh.get_node_or_null("InkOutline") as MeshInstance3D
	if existing != null:
		existing.material_override = InkStyle.outline_material(width)
	for surface in mesh.mesh.get_surface_count():
		var source := mesh.get_active_material(surface) as BaseMaterial3D
		# Keep shader-driven fire, smoke, particles, UI planes and VFX on their original rendering path.
		if source == null or source.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
			continue
		var material := source.duplicate() as BaseMaterial3D
		material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		material.specular_mode = BaseMaterial3D.SPECULAR_TOON
		if outlined and existing == null and source.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			material.next_pass = InkStyle.outline_material(width)
		mesh.set_surface_override_material(surface, material)
	if mesh.material_override is BaseMaterial3D:
		var source := mesh.material_override as BaseMaterial3D
		if source.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
			var material := source.duplicate() as BaseMaterial3D
			material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
			material.specular_mode = BaseMaterial3D.SPECULAR_TOON
			if outlined and existing == null and source.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				material.next_pass = InkStyle.outline_material(width)
			mesh.material_override = material

	_apply_outline(mesh)
	if existing != null: _apply_outline(existing)

func _process(_delta: float) -> void:
	var enabled := Options.enabled("outline")
	if enabled == _outline_enabled: return
	_outline_enabled=enabled
	_apply_outline_tree(get_tree().root)

func _apply_outline_tree(node: Node) -> void:
	if node is MeshInstance3D: _apply_outline(node)
	for child in node.get_children(): _apply_outline_tree(child)

func _apply_outline(mesh: MeshInstance3D) -> void:
	if str(mesh.name)=="InkOutline":
		mesh.visible=_outline_enabled and bool(mesh.get_meta("outline_allowed",true))
		return
	if mesh.mesh == null: return
	_apply_material_outline(mesh.material_override)
	_apply_material_outline(mesh.material_overlay)
	for surface in mesh.mesh.get_surface_count():
		_apply_material_outline(mesh.get_active_material(surface))

func _apply_material_outline(material: Material, depth: int = 0) -> void:
	if material == null or depth > 8: return
	var next := material.next_pass
	if next is ShaderMaterial and next.shader==InkStyle.OUTLINE_SHADER:
		material.set_meta("graphics_outline_pass",next)
		if not _outline_enabled: material.next_pass=null
	elif _outline_enabled and material.has_meta("graphics_outline_pass") and next==null:
		material.next_pass=material.get_meta("graphics_outline_pass")
	else:
		_apply_material_outline(next,depth+1)

static func outline_width(mesh: MeshInstance3D) -> float:
	if mesh.has_meta("toon_outline_width"):
		return clampf(float(mesh.get_meta("toon_outline_width")), 0.0, MAIN_WIDTH)
	var name_lower := str(mesh.name).to_lower()
	if name_lower.contains("fringe") or name_lower.contains("strand") or name_lower.contains("lock"):
		return FINE_HAIR_WIDTH
	if name_lower.contains("hair") or not str(mesh.get_meta("extras", {}).get("studio_hair_style", "")).is_empty():
		return HAIR_WIDTH
	return MAIN_WIDTH
