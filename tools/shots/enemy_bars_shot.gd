extends SceneTree
## Visual check of the data-driven enemy health bars (data/ui/enemy_bars.json). For each goblin map
## it starts the stage, lets the monsters close in so the floating bars face the camera, drops a few
## of them to low HP (the warning crosses the bar to its rust colour and pulses), and saves the whole
## view plus a close crop around the monsters. The boss map (brush_ring) also shows the Goblin Chief
## with the HUD boss bar styled to the goblin look.
## Maps: sunward_valley (bright golden ground), ink_garden + shrine_wall (ink), brush_ring (boss).
## Sizes: desktop 1600x900 and phone 900x1950 (portrait) so the bars are checked small too.
## Needs a window (run WITHOUT --headless):
##   godot --path . --script res://tools/shots/enemy_bars_shot.gd -- <out_dir>

const Fighter := preload("res://logic/fighter.gd")

const SHOTS := [
	{"map": "sunward_valley", "wait": 70},
	{"map": "ink_garden", "wait": 90},
	{"map": "shrine_wall", "wait": 120},
	{"map": "brush_ring", "wait": 90},
]
const SIZES := [{"name": "desktop", "size": Vector2i(1600, 900)}, {"name": "phone", "size": Vector2i(900, 1950)}]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://enemy_bar_shots"
	DirAccess.make_dir_recursive_absolute(out)
	for size in SIZES:
		root.size = size["size"]
		await process_frame
		var game_state = root.get_node("GameState")
		game_state.ensure_profile()
		for shot in SHOTS:
			game_state.start_stage(game_state.Mode.PVE, shot["map"])
			await _frames(shot["wait"])  # the monsters close in, so their bars face the camera
			var stage: Node = current_scene
			var sim = stage.get("_session")._sim
			var views: Dictionary = stage.get("_views")
			var monsters := _monsters(sim)
			# Hurt a couple of monsters so the low-HP warning (rust pulse) shows on the bars.
			for i in mini(2, monsters.size()):
				var hurt: Fighter = sim.fighters[monsters[i]]
				hurt.hp = hurt.max_hp() * (0.55 if i == 0 else 0.18)
			await _frames(10)
			var tag := "%s_%s" % [shot["map"], size["name"]]
			await _save(out, tag, sim, views, monsters)
	quit()


func _monsters(sim) -> Array:
	var ids := []
	for id in sim.fighters:
		if sim.fighters[id].team == "enemy":
			ids.append(id)
	ids.sort()
	return ids


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## The whole view and a crop around the monsters (and the player) at twice the size.
func _save(out: String, name: String, sim, views: Dictionary, monsters: Array) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out.path_join(name + ".png"))
	var camera := root.get_camera_3d()
	var box := Rect2(camera.unproject_position(sim.bodies[1].position), Vector2.ZERO)
	for id in monsters:
		if views.has(id) and not camera.is_position_behind(views[id].global_position):
			box = box.expand(camera.unproject_position(views[id].global_position))
	box = box.grow(160).intersection(Rect2(Vector2.ZERO, Vector2(image.get_size())))
	if box.size.x < 10.0 or box.size.y < 10.0:
		return
	var crop := image.get_region(Rect2i(box))
	if crop.get_width() < 900:
		crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_LANCZOS)
	crop.save_png(out.path_join(name + "_close.png"))
