extends SceneTree
## Renders the camp's Look tab (face / skin / hair color) with a few picks made, to a PNG.
## Needs a window (run WITHOUT --headless):
##   godot --path . --script res://tools/shots/look_shot.gd -- <out.png> [width height]

const CampDataLoader := preload("res://logic/camp_data_loader.gd")
const CombatDataLoader := preload("res://logic/combat_data_loader.gd")
const ItemRulesLoader := preload("res://logic/item_rules_loader.gd")
const Profile := preload("res://logic/profile.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if not args.is_empty() else "user://look.png"
	root.size = Vector2i(int(args[1]), int(args[2])) if args.size() >= 3 else Vector2i(1600, 900)
	var rules := ItemRulesLoader.load_default()
	var camp := CampDataLoader.load_default(rules.tiers.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var profile = Profile.new_player(rules, camp, rng)
	await process_frame  # (the autoloads the screen uses start first)
	var screen: CanvasLayer = load("res://client/camp_screen.gd").new()
	root.add_child(screen)
	screen.setup(profile, camp, rules, CombatDataLoader.load_default())
	screen._tabs.current_tab = 1
	for pick in [["face", "playful"], ["hair_style", "ref10_10"], ["skin", "tan"], ["hair_color", "natural"]]:
		for frame in 3:  # (one pick per frame, as a player's clicks come)
			await process_frame
		screen.look.pick(pick[0], pick[1])
	for frame in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	quit()
