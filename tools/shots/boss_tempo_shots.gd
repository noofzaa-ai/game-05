extends SceneTree
## Boss tempo look check (combat-designer 2026-11-22, copy of warlock_vfx_shots.gd with a third of the shot times): the Orc Warlock's own VFX (tech-artist 2026-11-21, Boss: spectacular, violent L3 boss effects): starts the
## real orc_waves journey with the auto squad on the night Orc Camp, skips to the boss wave, and makes the Warlock perform
## each move in turn (cleave, skyfall, cataclysm, bulwark) while the battle camera frames the fight; saves frames of each.
## Windowed only (not --headless):
##   godot --path . --script res://tools/shots/boss_tempo_shots.gd -- [--size=844x390] [--out=res://build/boss_tempo_shots]
## Shots: <out>/<WxH>_<move>_<t>.png, t = seconds after the move starts. HP is raised on both sides (a look check, not a
## balance run); the Warlock's own AI still steers and faces it.

const MOVES := {  # boss tempo 2026-11-22: a third of the old moments (wind-up, blow, recovery)
	"orc_warlock_cleave": [0.05, 0.12, 0.17, 0.3],
	"orc_warlock_skyfall": [0.1, 0.2, 0.3, 0.36, 0.55],
	"orc_warlock_cataclysm": [0.2, 0.4, 0.55, 0.6, 0.85],
	"orc_warlock_bulwark": [0.15, 0.34, 0.6, 1.0],
}

var out := "res://build/boss_tempo_shots"
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
	gs.account_session = null  # (offline and ungated, as tools/shots/high_wizard_shots.gd does)
	var combat = load("res://logic/combat_data_loader.gd").load_default()
	var data = load("res://logic/journey_data.gd").load_by_id("orc_waves", combat.enemies.keys())
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
			if str(sim.fighters[id].enemy_type) == "orc_warlock" and sim.fighters[id].is_alive():
				boss = id
	if boss < 0:
		printerr("WARLOCK_VFX no boss")
		quit(1)
		return
	print("WARLOCK_VFX boss=", boss, " map=", current_scene.get("_map_id"))
	for i in 150:  # let it walk into the squad
		await process_frame
	var warlock = sim.fighters[boss]
	var ai = sim._ai[boss]
	for move in MOVES:
		warlock.stats["HP"] = 99999.0
		warlock.hp = warlock.max_hp()
		warlock.cooldowns.clear()
		ai.skills = [] if move == "orc_warlock_cleave" else [{"move": move, "chance": 100}]
		var started := -1.0
		var clock := 0.0
		var shots: Array = MOVES[move].duplicate()
		while not shots.is_empty() and clock < 25.0:
			await process_frame
			clock += root.get_process_delta_time()
			if started < 0.0:
				for event in session.events:
					if str(event.get("type", "")) == "attack_started" and int(event.get("player", -1)) == boss and str(event.get("move", "")) == move:
						started = clock
				continue
			if clock - started >= float(shots[0]):
				await RenderingServer.frame_post_draw
				var path := "%s/%dx%d_%s_%.2f.png" % [out, size.x, size.y, move.trim_prefix("orc_warlock_"), float(shots[0])]
				root.get_texture().get_image().save_png(path)
				print("SHOT ", path)
				shots.pop_front()
		ai.skills = []
		for i in 120:
			await process_frame
	print("WARLOCK_VFX_DONE")
	quit()
