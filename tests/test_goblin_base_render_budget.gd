extends RefCounted
## Render budget of the generated goblin_base stages (tools/maps/build_goblin_base.gd, Boss PC web lag 2026-11-09):
## - every obstacle solid is enclosed by its crate/stone/log dressing, so StageView builds no collider boxes there
##   (client/goblin_ground.gd): a solid without dressing would become an invisible wall;
## - the flat Ground carries no ink outline pass (a second whole-floor draw, baked into the scene by the builder);
## - the palisade's back row and side pieces are separate MultiMeshes, so the back row culls from the south half;
## - the scene's own triangle/surface count stays inside the budget in docs/tech/performance_budget.md.

const MapLoader := preload("res://logic/map_loader.gd")
const GoblinGround := preload("res://client/goblin_ground.gd")
const MAPS := ["goblin_base_gate", "goblin_base_courtyard", "goblin_base_quarry", "goblin_base_chief", "goblin_base_rest"]
const DRESSING := ["goblin_crate", "goblin_stoneblock", "goblin_logwall"]
const MAX_SCENE_TRIS := 60000
const MAX_SCENE_SURFACES := 16


func run(ctx) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art/maps/goblin_base/manifest.json"))
	for id in MAPS:
		var map := MapLoader.load_by_id(id)
		ctx.check("%s: dressed map, StageView builds no collider boxes" % id, GoblinGround.dressed(map))
		var scene := (load(map.art_scene) as PackedScene).instantiate()
		var dressed := 0
		for name in DRESSING:
			var node := scene.get_node_or_null(name) as MultiMeshInstance3D
			if node != null: dressed += node.multimesh.instance_count
		ctx.check("%s: every obstacle solid has dressing, or (arena board) none are left (its scene props inside the board are cleared at load, client/arena_props.gd)" % id, (map.camera_style == "arena" and map.solids.size() == 1) or dressed == map.solids.size() - 1)
		var ground := scene.get_node_or_null("Ground") as MeshInstance3D
		var outlined := ground == null
		if ground != null:
			for surface in ground.mesh.get_surface_count():
				var material := ground.get_active_material(surface)
				if material != null and (material.next_pass != null or material.has_meta("graphics_outline_pass")): outlined = true
		ctx.check("%s: the flat Ground has no ink outline pass" % id, not outlined and ground.get_meta("toon_no_outline", false))
		ctx.check("%s: palisade back row and sides are separate MultiMeshes" % id, scene.get_node_or_null("palisade") != null and scene.get_node_or_null("palisade_sides") != null)
		var row: Dictionary = manifest.get(id, {})
		ctx.check("%s: scene budget %s tris / %s surfaces (max %d / %d)" % [id, row.get("triangles_instanced"), row.get("draw_surfaces"), MAX_SCENE_TRIS, MAX_SCENE_SURFACES], int(row.get("triangles_instanced", 1e9)) <= MAX_SCENE_TRIS and int(row.get("draw_surfaces", 99)) <= MAX_SCENE_SURFACES)
		scene.free()
