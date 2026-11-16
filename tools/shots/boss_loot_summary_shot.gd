extends SceneTree
## Screenshot of the wave summary with boss loot (design/gdd/boss-loot.md; ui-programmer 2026-11-16), offline:
## a WON Goblin Chief run with 1 coin, a set piece and the Relic in journey.boss_loot.
##   godot --path . --script res://tools/shots/boss_loot_summary_shot.gd -- --size 1280x720 --shot OUT.png

func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var size := Vector2i(1280, 720)
	var shot := ""
	var args := OS.get_cmdline_user_args()
	for i in args.size() - 1:
		match args[i]:
			"--size": size = Vector2i(int(args[i + 1].split("x")[0]), int(args[i + 1].split("x")[1]))
			"--shot": shot = args[i + 1]
	root.size = size
	DisplayServer.window_set_size(size)
	var gs = root.get_node("GameState")
	gs.item_rules = gs.ItemRulesLoader.load_default()
	gs.camp_data = gs.CampDataLoader.load_default(gs.item_rules.tiers.size())
	var Journey = load("res://logic/journey.gd")
	var j = Journey.new()
	var data = load("res://logic/journey_data.gd").new()
	data.wave_mode = true
	data.display_name = "Goblin Base"
	data.stage_count = 9
	j.data = data
	j.state = Journey.WON
	var piece = load("res://logic/item.gd").new()
	piece.id = "shot-piece"
	piece.item_id = "boss_goblin_chief_ring"
	piece.slot = "ring"
	piece.tier = 2
	j.boss_loot = {"1": {"zone": "goblin_base", "coin": "coin_goblin_chief", "coins": 1, "items": [piece], "relics": {"relic_goblin_chief": 1}, "first_kill": true}}
	gs.journey = j
	gs.run_loot = {"items": [], "gold": 120, "materials": {"ore": 2}, "wave": 9}
	change_scene_to_file(gs.JOURNEY_SCENE)
	await create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	if not shot.is_empty():
		root.get_texture().get_image().save_png(shot)
		print("shot ", shot)
	quit()
