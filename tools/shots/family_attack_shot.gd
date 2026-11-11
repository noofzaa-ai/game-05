extends SceneTree
## Every goblin variant attacking with its own clips, seen through the real game camera (camera 8,
## following the player) on the Practice Field. One variant at a time faces a player who stands still
## (made unkillable); the rules run, and the first time each of its moves reaches a phase the frame is
## saved whole and as a close crop around the monster and the player:
##   <move>_windup   two thirds into the wind-up      <move>_strike   the strike (a shot: 4 frames after the release)
## A move the AI does not pick within the time limit (the mage's blink needs the player close) is
## posed by hand with the rules frozen instead (the file name ends in _posed).
## Needs a window (run WITHOUT --headless):
##   godot --path . --script res://tools/shots/family_attack_shot.gd -- <out_dir>

const Fighter := preload("res://logic/fighter.gd")

const VARIANTS := [
	["goblin_archer", Vector3(0.0, 0.05, -2.0)],
	["goblin_mage", Vector3(0.0, 0.05, -2.0)],
	["goblin_knight", Vector3(0.0, 0.05, 1.0)],
	["goblin_chief", Vector3(0.0, 0.05, 1.0)],
]
const MONSTER_ID := 100
const TIME_LIMIT := 60 * 30


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://family_attack_shots"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1600, 900)
	await process_frame
	var game_state = root.get_node("GameState")
	game_state.ensure_profile()
	for variant in VARIANTS:
		game_state.start_stage(game_state.Mode.PVE, "practice_field")
		await _frames(10)
		var stage: Node = current_scene
		var sim = stage.get("_session")._sim
		sim.fighters[1].stats["HP"] = 1000000.0
		sim.fighters[1].hp = 1000000.0
		var kind: String = variant[0]
		sim.add_enemy(MONSTER_ID, sim.bodies[1].position + variant[1] - Vector3(0.0, 0.0, 4.0), kind)
		stage.get("_views")[MONSTER_ID] = _view(stage, sim.combat.enemies[kind])
		await _capture(out, kind, stage, sim)
	quit()


func _view(stage: Node, definition: Dictionary) -> Node3D:
	var view := Node3D.new()
	view.set_script(load("res://client/fighter_view.gd"))
	view.base_color = definition["color"]
	view.show_health_bar = true
	view.ink_outline = true
	view.monster_model_path = definition["model"]
	view.monster_model_height = definition["model_height"]
	view.monster_animations_path = definition["animations"]
	view.monster_clips = definition["clips"]
	view.monster_tint = definition["model_tint"]
	view.monster_standin_clips = definition["standin_clips"]
	view.monster_nock_mesh = definition["nock_mesh"]
	stage.add_child(view)
	return view


func _capture(out: String, kind: String, stage: Node, sim) -> void:
	var definition: Dictionary = sim.combat.enemies[kind]
	var wanted := {}
	for move_id in definition["clips"]:
		wanted[move_id + "_windup"] = false
		wanted[move_id + "_strike"] = false
	var monster: Fighter = sim.fighters[MONSTER_ID]
	for frame in TIME_LIMIT:
		await process_frame
		if monster.state != Fighter.State.ATTACK or not definition["clips"].has(monster.move_id):
			continue
		if not sim.areas.is_empty() or sim.fighters[1].state != Fighter.State.IDLE:
			continue  # a clean frame: no hex circle or hit reaction from the move before
		var move: Dictionary = sim.combat.moves[monster.move_id]
		var phase := ""
		if monster.move_frame >= float(move["startup"]) * 0.66 and monster.move_frame < float(move["startup"]):
			phase = "_windup"
		elif monster.move_frame >= _strike_frame(move):
			phase = "_strike"
		if phase != "" and not wanted.get(monster.move_id + phase, true):
			wanted[monster.move_id + phase] = true
			await _save(out, monster.move_id + phase, sim)
		if not wanted.values().has(false):
			break
	# Moves the AI never picked: posed by hand with the rules frozen.
	for key in wanted:
		if wanted[key]:
			continue
		var move_id: String = key.rsplit("_", true, 1)[0]
		var move: Dictionary = sim.combat.moves[move_id]
		stage.set_physics_process(false)
		monster.state = Fighter.State.ATTACK
		monster.move_id = move_id
		var target := float(move["startup"]) * 0.66 if key.ends_with("_windup") else _strike_frame(move)
		for i in 6:
			monster.move_frame = target
			stage.get("_views")[MONSTER_ID].show_state(sim.bodies[MONSTER_ID], monster, sim.combat)
			await process_frame
		await _save(out, key + "_posed", sim)
		stage.set_physics_process(true)
	print(kind, " captured ", wanted)


## The strike: a melee move one frame into its hit; a firing move a few frames after the release, so
## the arrow or bolt is out of the hand.
func _strike_frame(move: Dictionary) -> float:
	var fires: bool = not move["spawns"].is_empty() and move["spawns"][0].has("projectile")
	return float(move["spawns"][0]["frame"]) + 4.0 if fires else float(move["startup"]) + 1.0


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(out: String, name: String, sim) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out.path_join(name + ".png"))
	var camera := root.get_camera_3d()
	var points: Array = [sim.bodies[1].position, sim.bodies[MONSTER_ID].position, sim.bodies[MONSTER_ID].position + Vector3.UP * 2.0]
	for shot in sim.projectiles:
		points.append(shot["pos"])
	var box := Rect2(camera.unproject_position(points[0]), Vector2.ZERO)
	for point in points:
		box = box.expand(camera.unproject_position(point))
	box = box.grow(120).intersection(Rect2(Vector2.ZERO, Vector2(image.get_size())))
	var crop := image.get_region(Rect2i(box))
	if crop.get_width() < 800:
		crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_LANCZOS)
	crop.save_png(out.path_join(name + "_close.png"))
