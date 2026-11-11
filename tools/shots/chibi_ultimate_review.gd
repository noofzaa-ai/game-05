extends SceneTree
## Local visual review through production FighterView/UltimateCamera; no saves/network or damage simulation.
const View := preload("res://client/fighter_view.gd")
const Model := preload("res://client/character_model.gd")
const Rig := preload("res://client/camera_rig.gd")
const UltCamera := preload("res://client/ultimate_camera.gd")
const Fighter := preload("res://logic/fighter.gd")
const Body := preload("res://logic/sim_body.gd")
const Rules := preload("res://logic/item_rules_loader.gd")
const CombatLoader := preload("res://logic/combat_data_loader.gd")
const Assets := preload("res://client/item_assets.gd")
const Items := preload("res://logic/item_system.gd")
const Loadout := preload("res://logic/loadout.gd")
const SHOTS := {"blade": [.90, 1.70, 1.90, 2.35], "spear": [1.40, 1.68, 2.52, 2.84], "dagger": [1.28, 1.50, 1.84, 2.20], "hammer": [.80, 2.50, 3.10, 3.45]}
func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var out := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	var video := OS.get_cmdline_user_args().has("--video")
	var rules = Rules.load_default()
	var combat = CombatLoader.load_default()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/combat/ultimates.json"))
	for style in SHOTS:
		if OS.get_cmdline_user_args().has("--dagger-only") and style != "dagger":continue
		var vp := SubViewport.new()
		vp.size = Vector2i(1100, 660)
		vp.own_world_3d = true
		vp.msaa_3d = Viewport.MSAA_4X
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var title := Label.new()
		title.position = Vector2(22, 18)
		title.add_theme_font_size_override("font_size", 24)
		vp.add_child(title)
		var stage := Node3D.new()
		vp.add_child(stage)
		var world := WorldEnvironment.new()
		world.environment = Environment.new()
		world.environment.background_mode = Environment.BG_COLOR
		world.environment.background_color = Color("263341")
		world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		world.environment.ambient_light_color = Color.WHITE
		world.environment.ambient_light_energy = .7
		stage.add_child(world)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-50, -30, 0)
		light.light_energy = 1.1
		stage.add_child(light)
		var floor := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(40, 40)
		floor.mesh = plane
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("35414a")
		floor.material_override = mat
		stage.add_child(floor)
		var loadout := Loadout.new(rules)
		var rng := RandomNumberGenerator.new()
		for id in [style + "_01", "scout_vest", "scout_breeches", "scout_bracers", "scout_boots"]:
			var item: Dictionary = rules.catalog.entry(id)
			assert(not item.is_empty(), id)
			loadout.equip(Items.create_item(rules, "review-" + id, item["slot"], 1, rng, str(item.get("weapon_type", "")), id))
		var view := View.new()
		view.model_path = Model.MODEL_PATH
		view.looks = Assets.looks(loadout, rules.catalog, style)
		view.looks["appearance"] = Assets.appearance({"face":"bored", "hair_style":"short_fringe"})
		stage.add_child(view)
		view.set_process(false)
		var rig := Rig.new()
		rig.target = view
		rig.follow_depth = true
		rig.min_x = -100
		rig.max_x = 100
		rig.min_z = -100
		rig.max_z = 100
		stage.add_child(rig)
		rig.set_process(false)
		var camera := UltCamera.new()
		camera.rig = rig
		stage.add_child(camera)
		var body := Body.new()
		var fighter := Fighter.new()
		fighter.hp = 100
		fighter.style = style
		fighter.direction = Vector2i(1, 1)
		for tick in 90:
			view.show_state(body, fighter, combat)
			view._process(1.0 / 60)
			rig._process(1.0 / 60)
		var id: String = data.defaults[style]
		var skill: Dictionary = data.skills[id]
		var cast_effect: Node3D
		var wanted: Array = SHOTS[style].duplicate()
		var frame_dir := out.path_join(style + "_frames")
		if video:DirAccess.make_dir_recursive_absolute(frame_dir)
		var end_time := float(skill.duration_s) + .4 if video else float(wanted[-1]) + .05
		for tick in range(int(end_time * 60) + 1):
			var time := tick / 60.0
			fighter.state = Fighter.State.ATTACK if time < float(skill.locomotion_resume_s) else Fighter.State.IDLE
			fighter.move_id = style + "_ultimate" if fighter.state == Fighter.State.ATTACK else ""
			fighter.move_frame = tick
			var dash: Dictionary = skill.get("dash", {})
			if not dash.is_empty():
				var progress := smoothstep(float(dash.start_time_s), float(dash.end_time_s), time)
				var forward := Vector2(fighter.direction).normalized()
				body.position = Vector3(forward.x, 0, forward.y) * float(data.body_length_m) * float(dash.distance_body_lengths) * progress
			view.show_state(body, fighter, combat)
			view._process(1.0 / 60)
			if is_instance_valid(view._skill_vfx):
				cast_effect = view._skill_vfx
				cast_effect.set_process(false)
			if is_instance_valid(cast_effect):cast_effect.show_at(time)
			camera.update(fighter, body.position, view.body_center(), view.skill_weapon_point())
			rig._process(1.0 / 60)
			title.text = "Original Chibi | %s | %.2f s" % [id, time]
			if video and tick % 2 == 0:
				await process_frame
				await RenderingServer.frame_post_draw
				vp.get_texture().get_image().save_png(frame_dir.path_join("%05d.png" % (tick / 2)))
			if not wanted.is_empty() and time + .00001 >= float(wanted[0]):
				await process_frame
				await RenderingServer.frame_post_draw
				vp.get_texture().get_image().save_png(out.path_join("%s_%.2f.png" % [style, time]))
				print("REVIEW ", style, " ", time, " camera=", rig.has_override(), " body=", body.position)
				wanted.pop_front()
		vp.queue_free()
		await process_frame
	quit()
