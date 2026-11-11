extends SceneTree
## Explicit live staging probe, NOT included in run_all. No token/account IDs in output.
## godot --headless --path . --script res://tests/online_live_probe.gd
const Account := preload("res://client/online/online_account.gd")
const Config := preload("res://client/online/connection_config.gd")
var failed := 0

func check(label: String, good: bool) -> void:
	print("PASS " if good else "FAIL ", label)
	if not good:
		failed += 1

func _initialize() -> void:
	await process_frame
	var service := Account.new()
	service.name = "LiveProbe"
	root.add_child(service)
	service.store.path = "user://online_sdk_probe_v1.json"
	var args := OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "--cache":
		service.store.path = args[1]
	elif not args.is_empty():
		printerr("usage: -- [--cache PATH] (private probe cache, not your player cache)")
		quit(2)
		return
	var config := Config.load_default()
	await service.connect_account(config)
	check("SDK HTTPS device login / server account validation", service.status == Account.Status.AUTHENTICATED)
	if service.status == Account.Status.AUTHENTICATED:
		var uid: String = service.session.user_id
		service.use_offline()
		await service.connect_account(config)
		check("cached session restores same account", service.status == Account.Status.AUTHENTICATED and service.session.user_id == uid and service.auth_method == "restored")
		var cache: Dictionary = service.store.load_state(Config.scope(config))
		# Only access token is replaced with an expired fixture. Refresh token is real.
		cache.token = "header." + Marshalls.utf8_to_base64(JSON.stringify({"uid": uid, "exp": int(Time.get_unix_time_from_system()) - 5})).replace("+", "-").replace("/", "_").replace("=", "") + ".signature"
		service.store.save_state(cache)
		service.use_offline()
		await service.connect_account(config)
		check("real refresh token renews expired access session", service.status == Account.Status.AUTHENTICATED and service.session.user_id == uid and service.auth_method == "refresh")
		if service.status == Account.Status.AUTHENTICATED:
			var sdk = root.get_node("Nakama")
			sdk.logger._level = NakamaLogger.LOG_LEVEL.NONE
			var socket = sdk.create_socket_from(service.client)
			var result = await socket.connect_async(service.session, false, 6)
			check("SDK authenticated WSS upgrade", not result.is_exception() and socket.is_connected_to_host())
			socket.close()
			await create_timer(.3).timeout
	service.use_offline()
	service.queue_free()
	await process_frame
	print("LIVE_FAILED=", failed)
	quit(1 if failed else 0)
