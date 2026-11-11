extends RefCounted
## Tests the menu flow end to end: campfire -> pick mode -> pick stage -> play -> back to the campfire.

const ItemAssets := preload("res://client/item_assets.gd")


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text and node.is_inside_tree():
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _frames(ctx, count: int) -> void:
	for i in count:
		await ctx.process_frame


func run(ctx) -> void:
	var game_state: Node = ctx.root.get_node_or_null("GameState")
	ctx.check("GameState autoload exists", game_state != null)
	if game_state == null:
		return

	var hub: Node = load("res://scenes/hub.tscn").instantiate()
	ctx.root.add_child(hub)
	ctx.current_scene = hub
	await _frames(ctx, 1)

	var pve := _find_button(hub, "PvE  -  Farm")
	var pvp := _find_button(hub, "PvP")
	ctx.check("hub has PvE and PvP buttons", pve != null and pvp != null)
	ctx.check("a new player meets the character creator first", game_state.profile != null and (game_state.profile.created or hub._creator != null))
	if hub._creator != null:
		hub._creator.name_field.text = "Tester"
		hub._creator.start_button.pressed.emit()
		await _frames(ctx, 1)
	ctx.check("once made, the creator is gone", game_state.profile.created and hub._creator == null)
	ctx.check("New v1 stands by the fire with legacy face geometry deferred", hub._character != null and hub._character._new_v1_base and hub._character.face_path().is_empty())
	var customize := _find_button(hub, "Customize  -  Face, Hair, Skin")
	ctx.check("Customize is open now", customize != null and not customize.disabled)
	customize.pressed.emit()
	await _frames(ctx, 1)
	ctx.check("and opens the camp on the Look tab", hub._camp_screen != null and hub._camp_screen._tabs.get_current_tab_control() == hub._camp_screen.look)
	hub._camp_screen._close()
	await _frames(ctx, 1)

	hub.open_menu()  # (the walkable camp keeps the old menu behind its Menu button / the warp gate)
	pvp.pressed.emit()
	await _frames(ctx, 1)
	ctx.check("PvP menu opens with Back and no stages", _find_button(hub, "Back") != null and _find_button(hub, "Sunward Valley (test stage)") == null)
	_find_button(hub, "Back").pressed.emit()
	await _frames(ctx, 1)
	ctx.check("Back returns to the main menu", _find_button(hub, "PvE  -  Farm").is_visible_in_tree())

	_find_button(hub, "PvE  -  Farm").pressed.emit()
	await _frames(ctx, 1)
	var stage_button := _find_button(hub, "Sunward Valley (test stage)")
	ctx.check("PvE menu lists the stage from map data", stage_button != null)
	stage_button.pressed.emit()
	await _frames(ctx, 40)  # let the stage load and the simulation run for a while

	var stage: Node = ctx.current_scene
	ctx.check("stage scene loaded", stage != null and stage.scene_file_path == "res://scenes/stage.tscn")
	ctx.check("mode is PvE", game_state.mode == game_state.Mode.PVE)
	var sim = stage.get("_session")
	ctx.check("the simulation is running", sim != null and sim.tick_count > 10)
	var mobile = game_state.mobile_controls
	var forced: bool = mobile.force_mobile
	mobile.force_mobile = true
	mobile._update_context()
	ctx.check("mobile controls recognize the Session-driven stage", mobile._combat and mobile._root.visible)
	mobile.force_mobile = forced
	mobile._update_context()

	ctx.check("the player has landed on the floor", sim != null and sim.bodies[1].grounded)
	var rig = stage.get("_rig")
	ctx.check("PvE enables special cameras", rig != null and rig.special_enabled)
	ctx.check("the stage spawned the player and 7 monsters", sim != null and sim.fighters.size() == 8 and sim.living_enemy_count() == 7)
	ctx.check("every fighter has a view", stage.get("_views").size() == 8)
	ctx.check("the player is drawn with the character model, enemies with capsules", stage.get("_views")[1]._model != null and stage.get("_views")[100]._model == null)
	ctx.check("the player's stats come from the demo gear", sim != null and sim.fighters[1].stats["ATK"] > 100.0)
	ctx.check("the HUD and the effects exist", stage.get("_hud") != null and stage.get("_effects") != null)
	stage.get("_hud").flash_stamina()
	ctx.check("the HUD can warn about missing stamina", stage.get("_hud")._warning_left > 0.0)
	ctx.check("enemies show a floating health bar, the player does not", stage.get("_views")[100]._bar_fill != null and stage.get("_views")[1]._bar_fill == null)

	# Press the light attack button for real: the key must travel through the input reader into the sim.
	Input.action_press("light")
	var attacked := false
	for i in 120:
		await ctx.process_frame
		if sim.fighters[1].state == sim.fighters[1].State.ATTACK:
			attacked = true
			break
	Input.action_release("light")
	ctx.check("pressing the light attack button makes the player attack", attacked)

	# Dodge and guard through the real keys, too.
	var player_fighter = sim.fighters[1]
	for i in 200:  # wait until the attack is over
		if player_fighter.state == player_fighter.State.IDLE:
			break
		await ctx.process_frame
	Input.action_press("dodge")
	var dodged := false
	for i in 120:
		await ctx.process_frame
		if player_fighter.state == player_fighter.State.DODGE:
			dodged = true
			break
	Input.action_release("dodge")
	ctx.check("pressing the dodge key makes the player slide", dodged)
	for i in 200:
		if player_fighter.state == player_fighter.State.IDLE:
			break
		await ctx.process_frame
	var guarding := false
	for attempt in 3:  # (real monsters may knock the player about, so a try can land in the middle of a hit)
		for i in 200:
			if player_fighter.state == player_fighter.State.IDLE:
				break
			await ctx.process_frame
		Input.action_press("guard")
		for i in 60:
			await ctx.process_frame
			if player_fighter.state == player_fighter.State.GUARD:
				guarding = true
				break
		Input.action_release("guard")
		if guarding:
			break
	ctx.check("holding the guard key makes the player guard", guarding)

	# Let the enemies walk over and fight for a couple of real seconds; nothing must crash.
	await ctx.create_timer(3.0).timeout
	ctx.check("the fight keeps running without errors", sim.tick_count > 100)
	ctx.check("the enemies reached and hurt the player", sim.fighters[1].hp < sim.fighters[1].max_hp())

	game_state.go_hub()
	await _frames(ctx, 3)
	ctx.check("back at the campfire", ctx.current_scene != null and ctx.current_scene.scene_file_path == "res://scenes/hub.tscn")

	# PvP rules on the same stage: special cameras must be off.
	game_state.start_stage(game_state.Mode.PVP, "sunward_valley")
	await _frames(ctx, 5)
	var pvp_rig = ctx.current_scene.get("_rig")
	ctx.check("PvP disables special cameras", pvp_rig != null and not pvp_rig.special_enabled)
	game_state.go_hub()
	await _frames(ctx, 3)
