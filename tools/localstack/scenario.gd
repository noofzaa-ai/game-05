extends SceneTree
## Jump straight to a game state on the LOCAL online stack (tools/localstack/up.py), no playing to get there:
## a fresh device account signs in, tools/localstack/fixture.py puts it into fixtures/<name>.json, the game re-reads
## its profile from the server and opens the screen asked for. Then it stays open (play/click by hand), or takes a
## screenshot and quits.
##   godot --path . --script res://tools/localstack/scenario.gd -- --fixture unlock_ceremony [--open hub|map|character:<class>|storage|shop|blacksmith|tailor|quests|fight|fight_button|go|go_pyramid|go_orc|map_orc|quest] [--shots PREFIX --mid 5] [--size 1280x720] [--shot OUT.png] [--wait 2] [--lang th|en] [--journey mummy_waves]
## The local client key is read from build/localstack/state.json (throwaway, local only).

var fixture := "new_player"
var open := "hub"
var size := Vector2i(1280, 720)
var shot := ""
var wait_s := 2.0
var journey := ""  ## --journey <id>: after the fixture, play that wave journey on the LOCAL session (offline, fresh starter profile): the online rooms only run goblin_waves
var shots := ""  ## --shots <prefix>: with go_orc, follow the ONLINE fight and save <prefix>_w1.png, _w<mid>.png and _boss.png (wave 1, a middle wave, the boss wave)
var mid_wave := 5


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size() - 1:
		match args[i]:
			"--fixture": fixture = args[i + 1]
			"--open": open = args[i + 1]
			"--size": size = Vector2i(int(args[i + 1].split("x")[0]), int(args[i + 1].split("x")[1]))
			"--shot": shot = args[i + 1]
			"--wait": wait_s = float(args[i + 1])
			"--journey": journey = args[i + 1]
			"--shots": shots = args[i + 1]
			"--mid": mid_wave = int(args[i + 1])
			"--lang": load("res://client/card_tokens.gd").language = args[i + 1]
	root.size = size
	DisplayServer.window_set_size(size)
	var state = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://build/localstack/state.json")))
	if not state is Dictionary:
		return fail("no build/localstack/state.json: run python tools/localstack/up.py first")
	var online = root.get_node("Online")
	online.store.path = "user://scenario_%d.json" % Time.get_ticks_usec()
	await online.connect_account({"version": 1, "enabled": true, "scheme": "http", "host": "127.0.0.1", "port": 7350, "client_key": str(state.server_key)})
	if online.status != online.Status.AUTHENTICATED:
		return fail("sign-in failed: %s" % online.reason)
	var gs = root.get_node("GameState")
	if not await gs.connect_account_profile():
		return fail("profile load failed: %s" % gs.online_error)
	var out: Array = []
	var code := OS.execute("python", [ProjectSettings.globalize_path("res://tools/localstack/fixture.py"), "apply", online.session.user_id, fixture], out, true)
	print("".join(out))
	if code != 0:
		return fail("fixture %s failed" % fixture)
	await gs.account_session.refresh_account()
	gs.profile = gs.account_session.profile
	if not journey.is_empty():  # dev: e.g. the Sand Pyramid (still "coming soon" on the map) on the local session
		gs.account_session = null
		gs.session = null
		gs.profile = null
		gs.ensure_profile()
		if not gs.start_journey(journey):
			return fail("start_journey %s failed" % journey)
		await create_timer(wait_s).timeout
		print("SCENARIO_READY journey=%s (local session)" % journey)
		if not shot.is_empty():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(shot)
			quit()
		return
	change_scene_to_file(gs.CARD_DECK_SCENE)
	await create_timer(1.5).timeout
	var hub = current_scene
	match open.split(":")[0]:
		"map": hub.open_world_map()
		"character": hub.open_character(open.split(":")[1] if open.contains(":") else "sword_shield")
		"storage", "shop", "blacksmith", "tailor", "quests": hub.open_service(open)
		"fight": hub._start_fight()  # (dev: the start path itself, no map)
		"fight_button": hub._fight.pressed.emit()  # Boss 2026-11-18: FIGHT opens the world map
		"go":  # FIGHT, then the picked zone's Go on the map (starts the fight)
			hub._fight.pressed.emit()
			await create_timer(1.0).timeout
			if hub._panels.has("map") and hub._panels["map"].visible:
				hub._panels["map"]._go.pressed.emit()
		"go_pyramid":  # FIGHT -> map -> select the Sand Pyramid -> Go (the ONLINE room path; needs the card level 15 + goblin boss fixture)
			hub._fight.pressed.emit()
			await create_timer(1.0).timeout
			if hub._panels.has("map") and hub._panels["map"].visible:
				hub._panels["map"].select_zone("pyramid")
				await create_timer(0.5).timeout
				print("PYRAMID state go_visible=%s" % hub._panels["map"]._go.visible)
				hub._panels["map"]._go.pressed.emit()
		"map_orc":  # FIGHT -> map -> select the Orc Camp (no Go): prints the zone's state, Go and the info text
			hub._fight.pressed.emit()
			await create_timer(1.0).timeout
			if hub._panels.has("map") and hub._panels["map"].visible:
				hub._panels["map"].select_zone("orc_camp")
				await create_timer(0.5).timeout
				print("ORC state=%s go_visible=%s info=[%s]" % [load("res://logic/world_zones.gd").state(gs.profile, "orc_camp"), hub._panels["map"]._go.visible, str(hub._panels["map"]._info.text).replace("\n", " | ")])
		"go_orc":  # FIGHT -> map -> select the Orc Camp -> Go (the ONLINE room path; needs orc_zone_open / orc_zone_strong)
			hub._fight.pressed.emit()
			await create_timer(1.0).timeout
			if hub._panels.has("map") and hub._panels["map"].visible:
				hub._panels["map"].select_zone("orc_camp")
				await create_timer(0.5).timeout
				print("ORC state=%s go_visible=%s" % [load("res://logic/world_zones.gd").state(gs.profile, "orc_camp"), hub._panels["map"]._go.visible])
				hub._panels["map"]._go.pressed.emit()
			if not shots.is_empty():
				await _wave_shots(gs)
				return
		"go_goblin":  # FIGHT -> map -> select the Goblin Base -> Go (the default zone, online room path)
			hub._fight.pressed.emit()
			await create_timer(1.0).timeout
			if hub._panels.has("map") and hub._panels["map"].visible:
				hub._panels["map"].select_zone("goblin_base")
				await create_timer(0.5).timeout
				hub._panels["map"]._go.pressed.emit()
		"forge_pyramid":  # dev: a crafted request for the pyramid, skipping the client's own zone check (the server must refuse a locked profile)
			gs._start_solo.call_deferred("", "mummy_waves")
			for i in 20:
				await create_timer(1.0).timeout
				if gs.remote_session != null and gs.remote_session._terminal: break
			print("FORGE online_error=[%s] remote=%s err=%s" % [gs.online_error, gs.remote_session != null, str(gs.remote_session.error) if gs.remote_session != null else ""])
		"quest": hub._quest_tracker.pressed.emit()  # the hub quest tracker: the map on the quest's zone
	await create_timer(wait_s).timeout
	print("SCENARIO_READY fixture=%s open=%s tutorial=%s" % [fixture, open, gs.profile.tutorial])
	if not shot.is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(shot)
		print("shot ", shot)
		quit()


## Follows the ONLINE room (gs.remote_session.server_state meta: journey content, map, wave) and saves a shot at wave 1,
## at --mid, and at the boss wave (the last). Prints what the server says at each shot (map, wave, enemy types).
func _wave_shots(gs) -> void:
	var want := {1: "w1", mid_wave: "w%d" % mid_wave}
	var taken := {}
	var total := 9
	for i in 900:  # up to 15 minutes
		await create_timer(1.0).timeout
		var rs = gs.remote_session
		if rs == null:
			if i > 30: return fail("no online room (remote_session null) error=[%s]" % gs.online_error)
			continue
		var meta: Dictionary = rs.server_state.get("meta", {})
		if meta.is_empty(): continue
		total = int(meta.get("stage_count", total))
		var wave := int(meta.get("wave", meta.get("stage", 0)))
		want[total] = "boss"
		var enemies := {}
		for fid in rs.fighters:
			var f = rs.fighters[fid]
			if f.team == "enemy" and f.is_alive(): enemies[str(f.enemy_type)] = true
		if i % 10 == 0:
			print("ONLINE t=%ds content=%s map=%s wave=%d/%d state=%s status=%s enemies=%s" % [i, meta.get("content_name"), meta.get("map"), wave, total, meta.get("state"), meta.get("status"), enemies.keys()])
		if want.has(wave) and not taken.has(wave) and not enemies.is_empty():
			await create_timer(2.5).timeout  # let the wave walk in
			await RenderingServer.frame_post_draw
			var path := "%s_%s.png" % [shots, want[wave]]
			root.get_texture().get_image().save_png(path)
			print("SHOT %s content=%s map=%s wave=%d/%d enemies=%s" % [path, meta.get("content_name"), meta.get("map"), wave, total, enemies.keys()])
			taken[wave] = true
		if taken.size() >= 3 or str(meta.get("status", "")) == "finished":
			break
	print("SCENARIO_DONE shots=%d" % taken.size())
	quit(0 if taken.size() >= 3 else 1)


func fail(why: String) -> void:
	printerr("SCENARIO_FAILED ", why)
	quit(1)
