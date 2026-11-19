extends SceneTree
## Look check of the mummy finale's statuses on the PLAYER cards (combat-designer 2026-11-19, Boss: 'the boss skills
## must inflict statuses on the player'): starts the real mummy_waves journey with the auto squad, skips to wave 9
## (High Wizard + Pharaoh), and saves a frame shortly after each kind of status lands on a squad card (the popup, the
## card's status VFX and the HUD chips) to build/boss_status/*.png, then prints which statuses landed and how often.
## Windowed only (not --headless):
##   godot --path . --script res://tools/shots/boss_status_shots.gd
## The squad's HP is raised x20 so the fight lasts long enough (a look check, not a balance run).

const OUT := "res://build/boss_status"
const SECONDS := 60

var _shots := {}  ## effect id -> count taken
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
	var players := {}
	for id in sim.fighters:
		var f = sim.fighters[id]
		if f.team != "enemy":
			players[id] = true
			f.stats["HP"] = float(f.stats["HP"]) * 20.0
			f.hp = f.max_hp()
	while sim._waves.size() > 1:
		sim._waves.pop_front()
	for id in sim.fighters:
		if sim.fighters[id].team == "enemy":
			sim.fighters[id].hp = 0.0
	var landed := {}  ## effect -> count on players
	var resisted := {}
	var last_move := {}  ## enemy id -> move it is doing
	var by_move := {}  ## "move: effect" -> count
	var frame := 0
	while frame < 60 * SECONDS:
		await process_frame
		frame += 1
		for event in session.events:
			var type := str(event.get("type", ""))
			if type == "attack_started" and not players.has(int(event.get("player", -1))):
				last_move[int(event["player"])] = str(event["move"])
			elif type == "effect_applied" and players.has(int(event.get("target", -1))) and not players.has(int(event.get("source", -1))):
				var effect := str(event["effect"])
				landed[effect] = int(landed.get(effect, 0)) + 1
				var key := "%s: %s" % [last_move.get(int(event.get("source", -1)), "?"), effect]
				by_move[key] = int(by_move.get(key, 0)) + 1
				if int(_shots.get(effect, 0)) + _pending.filter(func(p): return p["name"] == effect).size() < 2:
					_pending.append({"at": frame + 12, "name": effect})
			elif type == "effect_resisted" and players.has(int(event.get("target", -1))):
				resisted[str(event["effect"])] = int(resisted.get(str(event["effect"]), 0)) + 1
		for p in _pending.duplicate():
			if frame >= int(p["at"]):
				_pending.erase(p)
				var n := int(_shots.get(p["name"], 0))
				await RenderingServer.frame_post_draw
				var path := "%s/%s_%02d.png" % [OUT, p["name"], n]
				root.get_texture().get_image().save_png(path)
				_shots[p["name"]] = n + 1
				print("SHOT ", path, " frame ", frame)
	print("LANDED on squad ", landed)
	print("RESISTED by squad ", resisted)
	print("BY MOVE ", by_move)
	quit()
