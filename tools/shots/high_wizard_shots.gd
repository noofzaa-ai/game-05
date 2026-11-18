extends SceneTree
## Look check of the mummy finale (combat-designer 2026-11-18): starts the real mummy_waves journey with the auto
## squad, skips to wave 9 (the Mummy High Wizard + Mummy Pharaoh pair), and saves frames of the arrival (summoning
## circles) and of each High Wizard skill (golden bolt, curse circle, starfall marks, sandstorm) to build/high_wizard/*.png.
## Windowed only (not --headless):
##   godot --path . --script res://tools/shots/high_wizard_shots.gd
## The squad's HP is raised x20 so the fight lasts long enough to see every skill (a look check, not a balance run).

const OUT := "res://build/high_wizard"
const WANT := {"arrival": 2, "mummy_hw_bolt": 3, "mummy_hw_curse": 3, "mummy_hw_starfall": 3, "mummy_hw_sandstorm": 3}

var _shots := {}  ## name -> count taken
var _pending: Array = []  ## {at: frame, name}


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var size := Vector2i(1280, 720)
	DisplayServer.window_set_size(size)
	root.size = size
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var game_state = root.get_node("GameState")
	game_state.ensure_profile()
	game_state.auto_battle = true
	# A look check: start the pyramid journey offline and ungated (GameState.start_journey refuses a locked zone and
	# an online account only hosts goblin_waves), the same steps it takes otherwise.
	game_state.account_session = null
	var combat = load("res://logic/combat_data_loader.gd").load_default()
	var data = load("res://logic/journey_data.gd").load_by_id("mummy_waves", combat.enemies.keys())
	game_state.run_loot = {"items": [], "gold": 0, "materials": {}, "wave": 1}
	game_state.mode = game_state.Mode.PVE
	var squad_cards: Array = game_state.squad_looks().slice(0, game_state.squad_size).map(func(slot): return str(slot.get("class", "")))
	var fight_session = game_state.get_session()
	fight_session.squad_classes = squad_cards
	fight_session.start_journey(data, combat.weapon_ids, 7, {}, squad_cards)
	game_state.journey = game_state.session.journey
	game_state.enter_journey_choice(0)
	for i in 90:
		await process_frame
	var session = game_state.session
	var sim = session._sim
	for id in sim.fighters:
		var f = sim.fighters[id]
		if f.team != "enemy":
			f.stats["HP"] = float(f.stats["HP"]) * 20.0
			f.hp = f.max_hp()
	while sim._waves.size() > 1:
		sim._waves.pop_front()
	for id in sim.fighters:
		if sim.fighters[id].team == "enemy":
			sim.fighters[id].hp = 0.0
	var frame := 0
	var arrived := -1
	while frame < 60 * 70:
		await process_frame
		frame += 1
		for event in session.events:
			var type := str(event.get("type", ""))
			if type == "wave_arrived" and arrived < 0:
				arrived = frame
				_pending.append({"at": frame + 2, "name": "arrival"})
				_pending.append({"at": frame + 55, "name": "arrival"})
			elif type == "attack_started" and WANT.has(str(event.get("move", ""))):
				var move := str(event["move"])
				var startup: int = {"mummy_hw_bolt": 40, "mummy_hw_curse": 72, "mummy_hw_starfall": 96, "mummy_hw_sandstorm": 70}[move]
				if int(_shots.get(move, 0)) + _pending.filter(func(p): return p["name"] == move).size() < WANT[move]:
					_pending.append({"at": frame + int(startup * 0.6), "name": move})
					_pending.append({"at": frame + startup + 25, "name": move})
					_pending.append({"at": frame + startup + 60, "name": move})
		for p in _pending.duplicate():
			if frame >= int(p["at"]):
				_pending.erase(p)
				var n := int(_shots.get(p["name"], 0))
				await RenderingServer.frame_post_draw
				var path := "%s/%s_%02d.png" % [OUT, p["name"], n]
				root.get_texture().get_image().save_png(path)
				_shots[p["name"]] = n + 1
				print("SHOT ", path, " frame ", frame)
		if WANT.keys().all(func(k): return int(_shots.get(k, 0)) >= WANT[k]) and _pending.is_empty():
			break
	print("HIGH_WIZARD_SHOTS ", _shots)
	quit()
