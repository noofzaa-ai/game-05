extends RefCounted
## Tests the painted "ink" look (outlines, wash ground), the skill-name banner and the damage number style.

const CharacterModel := preload("res://client/character_model.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const Hud := preload("res://client/hud.gd")
const InkStyle := preload("res://client/ink_style.gd")
const StageProps := preload("res://client/stage_props.gd")
const StageView := preload("res://client/stage_view.gd")


func _mesh_materials(node: Node, found: Array = []) -> Array:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh is PrimitiveMesh:
		found.append(((node as MeshInstance3D).mesh as PrimitiveMesh).material)
	for child in node.get_children():
		_mesh_materials(child, found)
	return found


func run(ctx) -> void:
	var outline := InkStyle.outline_material(0.02)
	ctx.check("the outline material is a shader with a width", outline is ShaderMaterial and absf(float(outline.get_shader_parameter("width")) - 0.02) < 0.0001)
	ctx.check("the same outline is reused, a different width is a different material", InkStyle.outline_material(0.02) == outline and InkStyle.outline_material(0.05) != outline)
	var ground := InkStyle.ground_material()
	ctx.check("the ground is a soft wash texture that follows the world, not the box faces", ground.albedo_texture is NoiseTexture2D and ground.uv1_triplanar)

	var props := [
		{"kind": "rock", "position": Vector3(1, 0, 1), "scale": 1.0, "yaw": 0.0, "count": 1, "radius": 0.0},
		{"kind": "plum", "position": Vector3(4, 0, 1), "scale": 1.5, "yaw": 0.0, "count": 2, "radius": 3.0},
		{"kind": "petals", "position": Vector3(0, 0, 0), "scale": 1.0, "yaw": 0.0, "count": 30, "radius": 5.0},
		{"kind": "dragon", "position": Vector3(0, 0, 0), "scale": 1.0, "yaw": 0.0, "count": 1, "radius": 0.0},
	]
	var plain := Node3D.new()
	ctx.root.add_child(plain)
	StageProps.build(plain, props)
	ctx.check("a map's props become scenery (rock + 2 plum trees + 30 petals, the unknown kind is skipped: %d)" % plain.get_child_count(), plain.get_child_count() == 33)
	var plain_materials := _mesh_materials(plain)
	ctx.check("without the ink style the scenery has no outline", plain_materials.size() > 0 and plain_materials.all(func(m): return m.next_pass == null))
	var inked := Node3D.new()
	ctx.root.add_child(inked)
	StageProps.build(inked, props, true)
	var inked_materials := _mesh_materials(inked)
	ctx.check("with the ink style every piece of scenery has the ink outline", inked_materials.size() > 0 and inked_materials.all(func(m): return m.next_pass is ShaderMaterial))
	plain.queue_free()
	inked.queue_free()
	var scratch := Node3D.new()
	StageProps.build(scratch, [])  # leaves no outline behind for later builds
	scratch.free()

	# The character model outline.
	var model := CharacterModel.new()
	model.ink_outline = true
	ctx.root.add_child(model)
	ctx.check("the model loads for the outline test", model.load_model())
	var has_outline := func(mesh) -> bool:
		var ink = model.outline_of(mesh)
		return ink != null and ink.material_override is ShaderMaterial and ink.skin == mesh.skin
	ctx.check("an ink-style model has an outline (moved by the same bones) on every part", model._meshes.size() > 0 and model._meshes.all(has_outline))
	var body: MeshInstance3D = model._meshes[0]
	var outline_shape: Mesh = model.outline_of(body).mesh
	ctx.check("the outline shape is the part's mesh with averaged normals", outline_shape != body.mesh and outline_shape.get_surface_count() == body.mesh.get_surface_count() and InkStyle.outline_mesh(body.mesh) == outline_shape)
	model.tint(Color(1, 0, 0, 0.3))
	ctx.check("a hit flash tints every part and keeps the outline", model._meshes.all(func(mesh): return mesh.material_overlay is StandardMaterial3D and has_outline.call(mesh)))
	model.tint(Color(0, 0, 0, 0))
	ctx.check("and the tint goes when the flash ends", model._meshes.all(func(mesh): return mesh.material_overlay == null and has_outline.call(mesh)))
	model.queue_free()
	var plain_model := CharacterModel.new()
	ctx.root.add_child(plain_model)
	plain_model.load_model()
	ctx.check("a model outside the ink style has no outline", plain_model._meshes.all(func(mesh): return mesh.material_overlay == null and plain_model.outline_of(mesh) == null))
	plain_model.queue_free()

	# The skill-name banner.
	var hud: CanvasLayer = Hud.new()
	ctx.root.add_child(hud)
	await ctx.process_frame
	ctx.check("the banner is hidden until a skill is used", not hud._skill_banner.visible)
	hud.show_skill_banner("Ember Slash")
	await ctx.process_frame
	ctx.check("using a skill shows its name in the banner", hud._skill_banner.visible and hud._skill_label.text == "Ember Slash")
	hud.show_skill_banner("Mountain Fall")
	ctx.check("a new skill replaces the name", hud._skill_label.text == "Mountain Fall")
	hud.queue_free()

	# Every weapon names its special skill and ultimate.
	var data = CombatDataLoader.load_default()
	var named := true
	var distinct := {}
	for weapon_id in data.weapon_ids:
		var names: Dictionary = data.weapons[weapon_id]["skill_names"]
		named = named and not str(names["special"]).is_empty() and not str(names["ultimate"]).is_empty()
		distinct[names["special"]] = true
		distinct[names["ultimate"]] = true
	ctx.check("every weapon names its special and its ultimate, all different (%d names)" % distinct.size(), named and distinct.size() == data.weapon_ids.size() * 2)

	# Damage numbers: bigger and more golden for harder hits (HP scale 100: 4 = a light hit, 50 = a huge one).
	var small := StageView.damage_style(4, false, false)
	var big := StageView.damage_style(50, false, false)
	var crit := StageView.damage_style(4, true, false)
	var blocked := StageView.damage_style(2, false, true)
	ctx.check("harder hits get bigger numbers", big["pixel_size"] > small["pixel_size"] * 1.5 and crit["pixel_size"] > small["pixel_size"])
	ctx.check("a small hit is white, a big one gold, a crit orange-red, a block blue", small["color"] == Color.WHITE and big["color"].r > 0.9 and big["color"].g > 0.7 and big["color"].b < 0.4 and crit["color"].g < 0.6 and blocked["color"].b > 0.9)
