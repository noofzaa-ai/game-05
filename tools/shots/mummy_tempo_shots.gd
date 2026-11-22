extends SceneTree
## Mummy Pharaoh tempo look check (combat-designer 2026-11-22, Boss: both wave-9 bosses ~3x faster; copy of
## boss_tempo_shots.gd): starts the real mummy_waves journey with the auto squad, skips to the boss-pair wave, removes the
## High Wizard so the frames show the Pharaoh alone, and makes it perform the combo and the nova in turn at the battle
## camera; saves frames through each move. Windowed only (not --headless):
##   godot --path . --script res://tools/shots/mummy_tempo_shots.gd -- [--size=1280x720] [--out=res://build/mummy_tempo_shots]
## Shots: <out>/<WxH>_<move>_f<NN>.png, NN = the move frame (tick, 60 per s) it was taken at. HP raised on both sides (a look check only).

const MOVES := {  # move frames (ticks): combo 5/2/9 (16 ticks, 0.27 s), nova 20/2/13 (35 ticks, 0.58 s)
	"mummy_boss_combo": [1, 3, 5, 7, 9, 12, 15],
	"mummy_boss_nova": [4, 10, 16, 20, 22, 27, 33],
}

var out := "res://build/mummy_tempo_shots"
var size := Vector2i(1280, 720)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		elif a.begins_with("--size="): size = Vector2i(int(a.substr(7).split("x")[0]), int(a.substr(7).split("x")[1]))
	DisplayServer.window_set_size(size)
	root.size = size
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	gs.auto_battle = true
	gs.account_session = null
	var combat = load("res://logic/combat_data_loader.gd").load_default()
	var data = load("res://logic/journey_data.gd").load_by_id("mummy_waves", combat.enemies.keys())
	gs.run_loot = {"items": [], "gold": 0, "materials": {}, "wave": 1}
	gs.mode = gs.Mode.PVE
	var cards: Array = gs.squad_looks().slice(0, gs.squad_size).map(func(slot): return str(slot.get("class", "")))
	var fight = gs.get_session()
	fight.squad_classes = cards
	fight.start_journey(data, combat.weapon_ids, 7, {}, cards)
	gs.journey = gs.session.journey
	gs.enter_journey_choice(0)
	for i in 90:
		await process_frame
	var session = gs.session
	var sim = session._sim
	while sim._waves.size() > 1:
		sim._waves.pop_front()
	for id in sim.fighters:
		var f = sim.fighters[id]
		if f.team == "enemy":
			f.hp = 0.0
		else:
			f.stats["HP"] = float(f.stats["HP"]) * 40.0
			f.hp = f.max_hp()
	var boss := -1
	var waited := 0
	while boss < 0 and waited < 60 * 20:
		await process_frame
		waited += 1
		for id in sim.fighters:
			if str(sim.fighters[id].enemy_type) == "mummy_boss" and sim.fighters[id].is_alive():
				boss = id
	if boss < 0:
		printerr("MUMMY_TEMPO no boss")
		quit(1)
		return
	print("MUMMY_TEMPO boss=", boss, " map=", current_scene.get("_map_id"))
	for i in 150:  # let it walk into the squad; the wizard and escorts leave the frame
		for id in sim.fighters:
			var f = sim.fighters[id]
			if f.team == "enemy" and id != boss and f.is_alive():
				f.hp = 0.0
		await process_frame
	var pharaoh = sim.fighters[boss]
	var ai = sim._ai[boss]
	for move in MOVES:
		pharaoh.stats["HP"] = 99999.0
		pharaoh.hp = pharaoh.max_hp()
		pharaoh.cooldowns.clear()
		ai.skill_chance = 100 if move == "mummy_boss_nova" else 0
		var clock := 0.0
		var shots: Array = MOVES[move].duplicate()
		while not shots.is_empty() and clock < 25.0:
			await process_frame
			clock += root.get_process_delta_time()
			for id in sim.fighters:
				if sim.fighters[id].team != "enemy":
					sim.fighters[id].hp = sim.fighters[id].max_hp()
			if str(pharaoh.move_id) != move or pharaoh.move_frame < float(shots[0]):
				continue
			if true:
				await RenderingServer.frame_post_draw
				var path := "%s/%dx%d_%s_f%02d.png" % [out, size.x, size.y, move.trim_prefix("mummy_boss_"), int(shots[0])]
				root.get_texture().get_image().save_png(path)
				print("SHOT ", path, " frame=", pharaoh.move_frame, " move=", pharaoh.move_id)
				shots.pop_front()
		ai.skill_chance = 0
		for i in 120:
			await process_frame
	print("MUMMY_TEMPO_DONE")
	quit()
