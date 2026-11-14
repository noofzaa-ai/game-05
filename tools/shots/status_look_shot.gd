extends SceneTree
## Status look check (tech-artist 2026-11-14): the hero and a goblin with Slow + Sunder, a second goblin stunned and
## burning, the rules frozen. Saves the whole view and a crop around the hero. Needs a window (no --headless):
##   godot --path . --script res://tools/shots/status_look_shot.gd -- <out_dir> <prefix>

const Fighter := preload("res://logic/fighter.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://status_shots"
	var prefix: String = args[1] if args.size() > 1 else "shot"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	await process_frame
	var game_state = root.get_node("GameState")
	game_state.ensure_profile()
	game_state.start_stage(game_state.Mode.PVE, "sunward_valley")
	await _frames(80)
	var stage: Node = current_scene
	var sim = stage.get("_session")._sim
	var views: Dictionary = stage.get("_views")
	stage.set_physics_process(false)  # freeze the rules: the statuses below stay on
	_sim = sim
	_views = views
	var hero_id := -1
	var goblins := []
	for id in sim.fighters:
		if sim.fighters[id].team == "player" and hero_id < 0:
			hero_id = id
		elif sim.fighters[id].team == "enemy":
			goblins.append(id)
	goblins.sort()
	var hero: Fighter = sim.fighters[hero_id]
	hero.state = Fighter.State.IDLE
	hero.effects = {"slow": {"left": 300, "stacks": 1, "source": -1}, "sunder": {"left": 300, "stacks": 1, "source": -1}}
	if goblins.size() > 0:
		sim.fighters[goblins[0]].effects = {"slow": {"left": 300, "stacks": 1, "source": -1}, "sunder": {"left": 300, "stacks": 1, "source": -1}}
	if goblins.size() > 1:
		sim.fighters[goblins[1]].effects = {"stun": {"left": 300, "stacks": 1, "source": -1}, "burn": {"left": 300, "stacks": 1, "source": -1}}
	await _frames(30)
	for id in views:
		if views[id].has_method("status_looks"):
			print("status ", id, " ", sim.fighters[id].team, " ", sim.fighters[id].effects.keys(), " ", views[id].status_looks(), " at ", views[id].global_position)
	await _save(out, prefix + "_status", sim, views, hero_id)
	views[hero_id].flash()  # a hit while slowed: brief flash
	views[hero_id].show_state(sim.bodies[hero_id], hero, sim.combat)
	await _save(out, prefix + "_hitflash", sim, views, hero_id)
	await _frames(20)
	await _save(out, prefix + "_after_flash", sim, views, hero_id)
	hero.effects = {}
	hero.invulnerable_left = 600  # immune (dodge / skill i-frames): cyan feet ring, no body tint
	await _frames(20)
	await _save(out, prefix + "_immune", sim, views, hero_id)
	hero.effects = {"slow": {"left": 300, "stacks": 1, "source": -1}}
	await _frames(20)
	await _save(out, prefix + "_immune_slow", sim, views, hero_id)
	quit()


var _sim
var _views: Dictionary = {}


## Frames with the rules frozen: the views are still shown from the (hand-set) fighters each frame.
func _frames(n: int) -> void:
	for i in n:
		if _sim != null:
			for id in _views:
				_views[id].show_state(_sim.bodies[id], _sim.fighters[id], _sim.combat)
		await process_frame


func _save(out: String, name: String, sim, views: Dictionary, hero_id: int) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out.path_join(name + ".png"))
	var camera := root.get_camera_3d()
	var at := camera.unproject_position(views[hero_id].global_position + Vector3(0, 0.8, 0))
	var box := Rect2(at - Vector2(220, 260), Vector2(440, 440)).intersection(Rect2(Vector2.ZERO, Vector2(image.get_size())))
	var crop := image.get_region(Rect2i(box))
	crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_LANCZOS)
	crop.save_png(out.path_join(name + "_close.png"))
