extends SceneTree
## Boss loot UI walk on the LOCAL online stack (design/gdd/boss-loot.md; ui-programmer 2026-11-16): the boss_farmer
## fixture, then the real panels press their own buttons against the local server and screenshots land in OUT_DIR.
##   godot --path . --script res://tools/localstack/boss_loot_drive.gd -- --size 1280x720 --out DIR [--step shop|storage|character]
## Prints DRIVE_USER <user_id> so `python tools/localstack/fixture.py show <uid>` can confirm the profile.

var size := Vector2i(1280, 720)
var out := ""
var step := "shop"
var gs
var hub


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size() - 1:
		match args[i]:
			"--size": size = Vector2i(int(args[i + 1].split("x")[0]), int(args[i + 1].split("x")[1]))
			"--out": out = args[i + 1]
			"--step": step = args[i + 1]
	root.size = size
	DisplayServer.window_set_size(size)
	var state = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://build/localstack/state.json")))
	var online = root.get_node("Online")
	online.store.path = "user://drive_%d.json" % Time.get_ticks_usec()
	await online.connect_account({"version": 1, "enabled": true, "scheme": "http", "host": "127.0.0.1", "port": 7350, "client_key": str(state.server_key)})
	gs = root.get_node("GameState")
	if not await gs.connect_account_profile():
		return fail("profile load failed")
	var log: Array = []
	OS.execute("python", [ProjectSettings.globalize_path("res://tools/localstack/fixture.py"), "apply", online.session.user_id, "boss_farmer"], log, true)
	print("DRIVE_USER ", online.session.user_id)
	await gs.account_session.refresh_account()
	gs.profile = gs.account_session.profile
	change_scene_to_file(gs.CARD_DECK_SCENE)
	await create_timer(1.5).timeout
	hub = current_scene
	var tag := "%dx%d" % [size.x, size.y]
	match step:
		"shop":
			hub.open_service("shop")
			await create_timer(1.0).timeout
			var shop = hub._panels["shop"]
			shop.select_item("boss:boss_goblin_chief_ring")
			await shot("shop_selected_" + tag)
			await press(shop._details, "Buy")
			await create_timer(1.5).timeout
			await shot("shop_bought_" + tag)
			print("DRIVE coins after buy: ", gs.profile.stash.material_count("coin_goblin_chief"))
			shop.select_item("boss:boss_goblin_chief_back")  # 100 coins left: the shortfall line
			await shot("shop_short_" + tag)
		"storage":
			hub.open_service("storage")
			await create_timer(1.0).timeout
			var storage = hub._panels["storage"]
			storage.select_item(_first_boss_piece())
			await shot("storage_empty_socket_" + tag)
			await press(storage._details, "Socket")
			await create_timer(1.5).timeout
			await shot("storage_socketed_" + tag)
			print("DRIVE relic after socket: ", gs.profile.stash.material_count("relic_goblin_chief"), " item relic: ", _item(storage.selected).relic)
			await press(storage._details, "Remove")
			await create_timer(1.5).timeout
			await shot("storage_unsocketed_" + tag)
			print("DRIVE relic after unsocket: ", gs.profile.stash.material_count("relic_goblin_chief"), " item relic: '", _item(storage.selected).relic, "'")
		"character":
			hub.open_character("greatsword")
			await create_timer(1.0).timeout
			var ch = hub._character
			ch.select_stash_item(_first_boss_piece())
			await create_timer(0.3).timeout
			await press(ch._detail, "Socket")
			await create_timer(1.5).timeout
			await shot("character_socketed_" + tag)
			print("DRIVE relic after socket (character): ", gs.profile.stash.material_count("relic_goblin_chief"))
			ch.select_slot("weapon:0")
			await shot("character_weapon_" + tag)
	quit()


func _first_boss_piece() -> String:
	for item in gs.profile.stash.items:
		if str(item.item_id).begins_with("boss_"):
			return item.id
	return ""


func _item(id: String):
	for item in gs.profile.stash.items:
		if item.id == id:
			return item
	return null


## Presses the details action whose label starts with `prefix` (the real button, its own pressed signal).
func press(details, prefix: String) -> void:
	for b in details.actions.get_children():
		var full := str(b.get_meta("full_text", b.text))
		if full.begins_with(prefix):
			print("DRIVE press '", full, "' disabled=", b.disabled)
			if not b.disabled:
				b.pressed.emit()
			await create_timer(0.2).timeout
			return
	print("DRIVE no button ", prefix)


func shot(name: String) -> void:
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var path := out.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("shot ", path)


func fail(why: String) -> void:
	printerr("DRIVE_FAILED ", why)
	quit(1)
