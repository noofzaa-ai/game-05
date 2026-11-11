extends SceneTree
## Captures OUR current player character as the player sees it, for the proportion/face/hair review
## the Boss asked for (2026-10-12). Needs a window (run WITHOUT --headless):
##   godot --path . --script res://tools/shots/character_review_shot.gd -- <out_dir>
##
## It renders, per look:
##   - the camp paper-doll camera (fov 26, close) at front / three-quarter / side
##   - the fight camera (the "High" preset: raised 3/4, offset (0,7,7), look_y 0.5, fov 55)
## for two dress states (a bare/basic body and a full set) and the default face Smile with the
## Original Bob hair plus three other styles close to the reference's salmon layered bob.
## Read-only: it does not touch client/ or any shipped asset; it only reads models and renders.

const CharacterModel := preload("res://client/character_model.gd")
const CharacterLight := preload("res://client/character_light.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Loadout := preload("res://logic/loadout.gd")
const SimBody := preload("res://logic/sim_body.gd")

const STYLES := ["fists", "blade", "dagger", "spear", "hammer"]
## A full set the model team fits to the chibi (same one the stance shots use, a blade in hand).
const FULL_SET := ["shinigami_f_head", "shinigami_f_shirt", "shinigami_f_arms", "shinigami_f_pants", "shinigami_f_shoes", "blade_01"]
## The default face and the four hair styles to show (ids from data/cosmetics/hair_styles.json ->
## asset path). "" = the body's own Original Bob.
const FACE := "res://art/items/faces/face_smile_01.glb"
const HAIR := [
	["original", ""],
	["wavy_fringe_bob", "res://art/items/hair/hair_ref10_03.glb"],
	["layered_shag", "res://art/items/hair/hair_ref10_09.glb"],
	["side_sweep", "res://art/items/hair/hair_row4_side_sweep_01.glb"],
]
const SKIN := Color("#f0cdb0")
const HAIR_COLOR := Color("#d98f8a")  ## a salmon-pink, close to the reference


func _initialize() -> void:
	var out_dir: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://character_review"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var rules := ItemRulesLoader.load_default()
	var rng := RandomNumberGenerator.new()
	await process_frame

	# Two viewports share one world look: a tall paper-doll one and a wide fight one.
	var doll_vp := _make_viewport(Vector2i(700, 950))
	var fight_vp := _make_viewport(Vector2i(1100, 760))

	# Paper-doll camera (as client/paper_doll.gd), rotated around the model for front/3-4/side.
	var doll_cam := Camera3D.new()
	doll_cam.fov = 26.0
	doll_vp.add_child(doll_cam)
	# Fight camera (camera_rig.gd "High" preset): raised three-quarter.
	var fight_cam := Camera3D.new()
	fight_cam.fov = 55.0
	fight_vp.add_child(fight_cam)
	fight_cam.look_at_from_position(Vector3(0.0, 7.0, 7.0), Vector3(0.0, 0.5, 0.0))

	for dress_state in ["bare", "full_set"]:
		for hair in HAIR:
			var model := CharacterModel.new()
			model.ink_outline = true
			doll_vp.add_child(model)
			model.load_model()
			var appearance := {
				"skin": SKIN, "hair": HAIR_COLOR, "face": FACE, "hair_style": hair[1],
			}
			if dress_state == "full_set":
				var loadout := Loadout.new(rules)
				for item_id in FULL_SET:
					var base: Dictionary = rules.catalog.entry(item_id)
					loadout.equip(ItemSystem.create_item(rules, item_id, base["slot"], 0, rng, "", item_id))
				var style := loadout.weapon_style(STYLES)
				var looks := ItemAssets.looks(loadout, rules.catalog, style)
				looks["appearance"] = appearance
				model.dress(looks)
				model.set_pose("idle", 0.0, 0.0, true, Vector2(0.4, 0.9), false, "", "", style)
			else:
				model.set_appearance(appearance)
				model.set_pose("idle", 0.0, 0.0, true, Vector2(0.0, 1.0), false)
			for frame in 24:
				model.apply_pose(1.0 / 60.0)
			await process_frame

			var tag := "%s_%s" % [dress_state, hair[0]]
			# Paper-doll angles: front (facing camera), three-quarter, side.
			for angle in [["front", Vector3(0.0, 1.05, 4.6), 0.0], ["threequarter", Vector3(3.1, 1.05, 3.4), 0.0], ["side", Vector3(4.6, 1.05, 0.0), 0.0]]:
				doll_cam.position = angle[1]
				doll_cam.look_at(Vector3(0.0, 0.9, 0.0))
				for frame in 2:
					model.apply_pose(1.0 / 60.0)
					await process_frame
				await RenderingServer.frame_post_draw
				doll_vp.get_texture().get_image().save_png(out_dir.path_join("doll_%s_%s.png" % [tag, angle[0]]))

			# Fight camera: move the model under the raised 3/4 camera; one shot.
			model.reparent(fight_vp)
			for frame in 4:
				model.apply_pose(1.0 / 60.0)
				await process_frame
			await RenderingServer.frame_post_draw
			fight_vp.get_texture().get_image().save_png(out_dir.path_join("fight_%s.png" % tag))
			model.queue_free()
			await process_frame
	quit()


func _make_viewport(size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.16, 0.17, 0.19)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.78, 0.76, 0.72)
	environment.ambient_light_energy = 0.8
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, 25.0, 0.0)
	light.light_energy = 1.0
	viewport.add_child(light)
	CharacterLight.light_scene(viewport, environment, 0.3, 1.0)
	return viewport
