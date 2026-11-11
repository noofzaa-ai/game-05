extends RefCounted
## The walkable camp hub (client/hub.gd, art from tools/blender/build_camp_hub.py): the scenery's spots
## and colliders, its budget, walking and colliding, reaching every NPC, talking (the prompt and what
## each person opens), the campfire and the warp gate.

const HubWorld := preload("res://client/hub_world.gd")
const SimBody := preload("res://logic/sim_body.gd")

const SCENE := "res://art/maps/camp_hub/camp_hub.glb"
const SPOTS := ["spawn", "campfire", "warp_gate", "npc_blacksmith", "npc_merchant", "npc_tailor", "npc_storage", "npc_quest"]
const MAX_TRIS := 40000
const MAX_MATERIALS := 4


func run(ctx) -> void:
	ctx.check("the camp hub scenery exists", ResourceLoader.exists(SCENE))
	if not ResourceLoader.exists(SCENE):
		return
	_check_budget(ctx)
	var world := HubWorld.new()
	ctx.root.add_child(world)
	_check_layout(ctx, world)
	world.queue_free()
	await _check_hub(ctx)


func _check_budget(ctx) -> void:
	var scene: Node = load(SCENE).instantiate()
	var tris := 0
	var materials := {}
	var meshes := 0
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		meshes += 1
		for i in mesh.get_surface_count():
			materials[mesh.surface_get_material(i)] = true
			var arrays := mesh.surface_get_arrays(i)
			var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			tris += (index.size() if index.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	scene.free()
	ctx.check("the camp is within the web budget (%d tris <= %d)" % [tris, MAX_TRIS], tris > 1000 and tris <= MAX_TRIS)
	ctx.check("the camp's static meshes are merged per material (%d meshes, %d materials)" % [meshes, materials.size()], meshes <= MAX_MATERIALS and materials.size() <= MAX_MATERIALS)


## Every spot is marked, on open ground inside the clearing, and the player can walk to it.
func _check_layout(ctx, world) -> void:
	var missing: Array = []
	for name in SPOTS:
		if not world.spots.has(name):
			missing.append(name)
	ctx.check("the camp marks every gameplay spot (missing: %s)" % [missing], missing.is_empty())
	ctx.check("the camp has colliders and a walkable rectangle", world.solids.size() >= 10 and world.half_extents.x > 6.0 and world.half_extents.y > 6.0)
	var inside: Array = []
	for name in SPOTS:
		var at: Vector3 = world.spot(name)
		if name != "campfire" and _blocked(world, at):
			inside.append(name)
	ctx.check("no spot is inside a collider or outside the clearing (bad: %s)" % [inside], inside.is_empty())

	# Flood-fill the walkable floor from the spawn on a 0.25 m grid with the player's box.
	var step := 0.25
	var start: Vector3 = world.spot("spawn")
	var seen := {Vector2i(roundi(start.x / step), roundi(start.z / step)): true}
	var queue: Array[Vector2i] = [seen.keys()[0]]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + offset
			if seen.has(next):
				continue
			if _blocked(world, Vector3(next.x * step, 0.0, next.y * step)):
				continue
			seen[next] = true
			queue.append(next)
	var unreachable: Array = []
	for name in SPOTS:
		var reach := 2.3 if name.begins_with("npc_") else (2.7 if name == "campfire" else 0.5)
		var at: Vector3 = world.spot(name)
		var found := false
		for cell in seen:
			if Vector2(cell.x * step - at.x, cell.y * step - at.z).length() <= reach:
				found = true
				break
		if not found:
			unreachable.append(name)
	ctx.check("the player can walk from the spawn to every NPC, the fire and the gate (not: %s)" % [unreachable], unreachable.is_empty())
	ctx.check("the clearing is a good size (%d walkable cells)" % seen.size(), seen.size() > 4000)


func _blocked(world, at: Vector3) -> bool:
	if absf(at.x) > world.half_extents.x or absf(at.z) > world.half_extents.y:
		return true
	var body := AABB(at + Vector3(-SimBody.HALF_WIDTH, 0.0, -SimBody.HALF_DEPTH), Vector3(SimBody.HALF_WIDTH * 2.0, SimBody.HEIGHT, SimBody.HALF_DEPTH * 2.0))
	for solid in world.solids:
		if body.intersects(solid):
			return true
	return false


func _frames(ctx, count: int) -> void:
	for i in count:
		await ctx.physics_frame


func _check_hub(ctx) -> void:
	var game_state: Node = ctx.root.get_node_or_null("GameState")
	var hub: Node = load("res://scenes/hub.tscn").instantiate()
	ctx.root.add_child(hub)
	await _frames(ctx, 2)
	if hub._creator != null:
		hub._creator.name_field.text = "Tester"
		hub._creator.start_button.pressed.emit()
		await _frames(ctx, 1)
	ctx.check("the hub shows the player in their looks and 5 camp people", hub._character != null and hub.npcs.size() == 5)
	ctx.check("the hub starts walkable with its menu closed", hub.can_walk() and not hub._menu_panel.visible)

	var spawn: Vector3 = hub.world.spot("spawn")
	hub.place_player(spawn)
	Input.action_press("move_up")
	await _frames(ctx, 30)
	Input.action_release("move_up")
	ctx.check("holding up walks the player north (away from the camera)", hub.player_position().z < spawn.z - 0.8)
	Input.action_press("move_right")
	await _frames(ctx, 20)
	Input.action_release("move_right")
	ctx.check("holding right walks the player east", hub.player_position().x > spawn.x + 0.5)

	# The campfire's stones stop the player; the fire's own prompt opens the camp.
	var fire: Vector3 = hub.world.spot("campfire")
	hub.place_player(fire + Vector3(0.0, 0.0, 3.0))
	Input.action_press("move_up")
	await _frames(ctx, 90)
	Input.action_release("move_up")
	ctx.check("the player cannot walk into the campfire", hub.player_position().z > fire.z + 1.0)
	await _frames(ctx, 1)
	ctx.check("by the fire the prompt offers the camp", hub.near_target().get("kind", "") == "fire" and hub._prompt.visible)
	hub.interact()
	await _frames(ctx, 1)
	ctx.check("the campfire opens the camp screens (and the player stops)", hub._camp_screen != null and not hub.can_walk())
	if hub._camp_screen != null:
		hub._camp_screen._close()
		await _frames(ctx, 1)

	# Each camp person: the prompt names them; talking does their thing.
	var expected := {"blacksmith": 2, "tailor": 1, "storage": 0}
	for role in ["blacksmith", "tailor", "storage", "merchant", "quest"]:
		var person = hub.npc(role)
		ctx.check("%s stands in the camp" % role, person != null)
		if person == null:
			continue
		hub.place_player(_stand_by(hub, person.position))
		await _frames(ctx, 1)
		var near: Dictionary = hub.near_target()
		ctx.check("next to the %s the prompt says talk to them" % role, near.get("kind", "") == "npc" and hub.npcs[near["index"]] == person and hub._prompt.visible and person.display_name in hub._prompt.text)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_E
		key.pressed = true
		hub._unhandled_key_input(key)
		await _frames(ctx, 1)
		if expected.has(role):
			ctx.check("E with the %s opens the camp on its tab" % role, hub._camp_screen != null and hub._camp_screen._tabs.current_tab == expected[role])
			if hub._camp_screen != null:
				hub._camp_screen._close()
				await _frames(ctx, 1)
		else:
			ctx.check("the %s says it is coming soon (no screen opens)" % role, person.is_saying() and hub._camp_screen == null and "soon" in person._say.text)

	# The warp gate: stepping into its ring opens the gate screen (or the old menu) once.
	var gate: Vector3 = hub.world.spot("warp_gate")
	hub.place_player(gate + Vector3(0.0, 0.0, 3.0))
	await _frames(ctx, 2)
	ctx.check("outside the ring nothing opens", hub.can_walk())
	hub.place_player(gate)
	await _frames(ctx, 2)
	var opened: bool = hub._warp_screen != null or (hub._menu_panel.visible and hub._main_menu.visible)
	ctx.check("walking into the warp gate opens the stage choice", opened and not hub.can_walk())
	if hub._warp_screen != null:
		hub._warp_screen.queue_free()
		hub._warp_screen = null
	hub.close_menu()
	await _frames(ctx, 3)
	ctx.check("standing on in the ring does not reopen it at once", hub.can_walk())
	hub.place_player(gate + Vector3(0.0, 0.0, 3.0))
	await _frames(ctx, 2)
	hub.place_player(gate)
	await _frames(ctx, 2)
	ctx.check("leaving and coming back opens it again", hub._warp_screen != null or hub._menu_panel.visible)
	if hub._warp_screen != null:
		hub._warp_screen.queue_free()
		hub._warp_screen = null
	hub.close_menu()

	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	hub._unhandled_key_input(esc)
	ctx.check("Esc opens the hub menu with every old action", hub._menu_panel.visible and not hub.can_walk())
	hub._unhandled_key_input(esc)
	ctx.check("and Esc closes it again", not hub._menu_panel.visible and hub.can_walk())
	ctx.check("the profile survived the walk", game_state == null or game_state.profile != null)
	hub.queue_free()
	await _frames(ctx, 2)


## A free spot next to `at` (south, east, west or north of it), on the walkable floor.
func _stand_by(hub, at: Vector3) -> Vector3:
	for offset in [Vector3(0.0, 0.0, 1.4), Vector3(1.4, 0.0, 0.0), Vector3(-1.4, 0.0, 0.0), Vector3(0.0, 0.0, -1.4), Vector3(0.0, 0.0, 1.9), Vector3(1.0, 0.0, 1.5), Vector3(-1.0, 0.0, 1.5)]:
		if not _blocked(hub.world, at + offset):
			return at + offset
	return at
