extends SceneTree
## PREVIEW ONLY (Boss review 2026-10-12). Renders our current chibi beside two tuning options, so the
## PO/Boss can judge before anyone touches a shipped file. Nothing here changes client/ or any asset:
## it loads the normal model and, for the option copies, pushes per-bone SCALE at runtime (no bone is
## renamed or added; the skeleton and rest pose are untouched). Needs a window (no --headless):
##   godot --path . --script res://tools/shots/character_review_options.gd -- <out_dir>
##
## Option A (camera only): same model, but the FIGHT camera is pulled in to the reference's framing so
##   the face and hair read at battle size. (No model change at all.)
## Option B (per-bone scale): longer lower legs, bigger feet/boots, slightly smaller head and hands,
##   to read as the reference's "cool young adult" with chunky boots. Applied to a copy at runtime.

const CharacterModel := preload("res://client/character_model.gd")
const CharacterLight := preload("res://client/character_light.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Loadout := preload("res://logic/loadout.gd")

const STYLES := ["fists", "blade", "dagger", "spear", "hammer"]
const FULL_SET := ["shinigami_f_head", "shinigami_f_shirt", "shinigami_f_arms", "shinigami_f_pants", "shinigami_f_shoes", "blade_01"]
const FACE := "res://art/items/faces/face_smile_01.glb"
const HAIR := "res://art/items/hair/hair_ref10_03.glb"  ## Wavy Fringe Bob, closest to the reference
const SKIN := Color("#f0cdb0")
const HAIR_COLOR := Color("#d98f8a")

## Option B bone scales (name -> scale). Lengthen the shins a touch, make feet chunkier, shrink the
## head and hands a little. These sit as pose scales on a runtime copy only.
const B_SCALE := {
	"LeftLowerLeg": Vector3(1.0, 1.22, 1.0), "RightLowerLeg": Vector3(1.0, 1.22, 1.0),
	"LeftUpperLeg": Vector3(1.0, 1.10, 1.0), "RightUpperLeg": Vector3(1.0, 1.10, 1.0),
	"LeftFoot": Vector3(1.25, 1.15, 1.30), "RightFoot": Vector3(1.25, 1.15, 1.30),
	"Head": Vector3(0.90, 0.90, 0.90),
	"LeftHand": Vector3(0.85, 0.85, 0.85), "RightHand": Vector3(0.85, 0.85, 0.85),
}


func _initialize() -> void:
	var out_dir: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://character_review/options"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var rules := ItemRulesLoader.load_default()
	var rng := RandomNumberGenerator.new()
	await process_frame

	# Paper-doll side-by-side: current | option B.
	var doll_vp := _make_viewport(Vector2i(1200, 950))
	var doll_cam := Camera3D.new()
	doll_cam.fov = 30.0
	doll_vp.add_child(doll_cam)
	doll_cam.look_at_from_position(Vector3(0.0, 1.0, 5.4), Vector3(0.0, 0.9, 0.0))
	var current := _dressed(doll_vp, rules, rng, false)
	current.position.x = -1.3
	var option_b := _dressed(doll_vp, rules, rng, true)
	option_b.position.x = 1.3
	for frame in 30:
		current.apply_pose(1.0 / 60.0)
		option_b.apply_pose(1.0 / 60.0)
		await process_frame
	await RenderingServer.frame_post_draw
	doll_vp.get_texture().get_image().save_png(out_dir.path_join("doll_current_vs_optionB.png"))

	# Fight-size readability: the game's current "High" framing vs Option A's tighter framing, on the
	# CURRENT model (so this row shows the camera change alone), plus Option B at the tighter framing.
	var fight_vp := _make_viewport(Vector2i(1200, 760))
	var fight_cam := Camera3D.new()
	fight_vp.add_child(fight_cam)
	# three subjects across the frame: current@High, current@tight, optionB@tight
	var subjects := [
		[_dressed(fight_vp, rules, rng, false), "current @ High (now)", -3.4, false],
		[_dressed(fight_vp, rules, rng, false), "current @ tight (Opt A)", 0.0, true],
		[_dressed(fight_vp, rules, rng, true), "Opt B @ tight", 3.4, true],
	]
	# We cannot change fov per subject in one shot, so render three separate fight PNGs instead.
	for subject in subjects:
		subject[0].get_parent().remove_child(subject[0])
	var labels := ["fight_current_high", "fight_current_tight_optA", "fight_optB_tight"]
	for index in subjects.size():
		var vp := _make_viewport(Vector2i(900, 760))
		var cam := Camera3D.new()
		cam.fov = 55.0
		vp.add_child(cam)
		if subjects[index][3]:  # tight framing (Option A): closer, lower, less sky
			cam.look_at_from_position(Vector3(0.0, 3.1, 4.6), Vector3(0.0, 1.0, 0.0))
		else:  # the current "High" preset
			cam.look_at_from_position(Vector3(0.0, 7.0, 7.0), Vector3(0.0, 0.5, 0.0))
		var m: CharacterModel = subjects[index][0]
		vp.add_child(m)
		for frame in 20:
			m.apply_pose(1.0 / 60.0)
			await process_frame
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(out_dir.path_join(labels[index] + ".png"))
	quit()


func _dressed(parent: Node, rules: RefCounted, rng: RandomNumberGenerator, option_b: bool) -> CharacterModel:
	var model := CharacterModel.new()
	model.ink_outline = true
	parent.add_child(model)
	model.load_model()
	var loadout := Loadout.new(rules)
	for item_id in FULL_SET:
		var base: Dictionary = rules.catalog.entry(item_id)
		loadout.equip(ItemSystem.create_item(rules, item_id, base["slot"], 0, rng, "", item_id))
	var style := loadout.weapon_style(STYLES)
	var looks := ItemAssets.looks(loadout, rules.catalog, style)
	looks["appearance"] = {"skin": SKIN, "hair": HAIR_COLOR, "face": FACE, "hair_style": HAIR}
	model.dress(looks)
	model.set_pose("idle", 0.0, 0.0, true, Vector2(0.4, 0.9), false, "", "", style)
	for frame in 6:
		model.apply_pose(1.0 / 60.0)
	if option_b:
		_apply_scale(model)
	return model


## Push the Option-B scales onto the skeleton's bone POSE scale (not the rest): a non-destructive
## runtime tweak, reapplied after each pose because apply_pose rewrites rotations (scale survives).
func _apply_scale(model: CharacterModel) -> void:
	var skel: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	for bone in B_SCALE:
		var i := skel.find_bone(bone)
		if i >= 0:
			skel.set_bone_pose_scale(i, B_SCALE[bone])


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
