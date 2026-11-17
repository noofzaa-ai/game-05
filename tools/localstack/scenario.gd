extends SceneTree
## Jump straight to a game state on the LOCAL online stack (tools/localstack/up.py), no playing to get there:
## a fresh device account signs in, tools/localstack/fixture.py puts it into fixtures/<name>.json, the game re-reads
## its profile from the server and opens the screen asked for. Then it stays open (play/click by hand), or takes a
## screenshot and quits.
##   godot --path . --script res://tools/localstack/scenario.gd -- --fixture unlock_ceremony [--open hub|map|character:<class>|storage|shop|blacksmith|tailor|fight] [--size 1280x720] [--shot OUT.png] [--wait 2] [--lang th|en] [--journey mummy_waves]
## The local client key is read from build/localstack/state.json (throwaway, local only).

var fixture := "new_player"
var open := "hub"
var size := Vector2i(1280, 720)
var shot := ""
var wait_s := 2.0
var journey := ""  ## --journey <id>: after the fixture, play that wave journey on the LOCAL session (offline, fresh starter profile): the online rooms only run goblin_waves


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
		"storage", "shop", "blacksmith", "tailor": hub.open_service(open)
		"fight": hub._start_fight()
	await create_timer(wait_s).timeout
	print("SCENARIO_READY fixture=%s open=%s tutorial=%s" % [fixture, open, gs.profile.tutorial])
	if not shot.is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(shot)
		print("shot ", shot)
		quit()


func fail(why: String) -> void:
	printerr("SCENARIO_FAILED ", why)
	quit(1)
