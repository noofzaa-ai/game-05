extends SceneTree
## Explicit local-stack SDK probe; config path contains only app connection data.
const Account := preload("res://client/online/online_account.gd")
const Names := preload("res://client/online/name_client.gd")
const Profiles := preload("res://client/online/profile_client.gd")
var failed := 0

func check(label: String, good: bool) -> void:
	print("PASS " if good else "FAIL ", label)
	if not good: failed += 1

func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "--config":
		printerr("usage: -- --config PRIVATE_PATH")
		quit(2)
		return
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(args[1])) != OK or not (parser.data is Dictionary):
		quit(2)
		return
	var service := Account.new()
	service.name = "NamesSdkProbe"
	root.add_child(service)
	service.store.path = args[1] + ".cache.json"
	await service.connect_account(parser.data)
	check("Godot SDK authenticates local stack", service.status == Account.Status.AUTHENTICATED)
	if service.status == Account.Status.AUTHENTICATED:
		var names := Names.new()
		var result := await names.get_name(service)
		check("name RPC reads empty record", result.ok and result.name.is_empty())
		result = await names.claim(service, "Native SDK")
		check("name RPC validates and saves through Godot worker", result.ok and result.name == "Native SDK")
		result = await names.claim(service, "New Name")
		check("name RPC maps real duplicate to safe client result", not result.ok and result.error == "name_taken")
		result = await names.get_name(service)
		check("duplicate does not change SDK account name", result.ok and result.name == "Native SDK")
		var profiles := Profiles.new()
		var snapshot := await profiles.fetch(service)
		check("profile SDK loads authoritative starter", snapshot.get("ok", false) and profiles.revision == 1 and snapshot.profile.name == "Native SDK")
		if snapshot.get("ok", false):
			var pending := profiles.prepare({"type": "unequip", "slot": "weapon", "destination": "stash"})
			var saved := await profiles.submit(service, pending)
			check("profile SDK commits shared camp command", saved.get("ok", false) and profiles.revision == 2 and saved.profile.stash.items.size() == 1)
			var retry := await profiles.submit(service, pending)
			check("profile SDK retry keeps original request ID", retry.get("ok", false) and retry.replayed and profiles.revision == 2)
			var reloaded := await profiles.fetch(service)
			check("profile SDK reload preserves saved equipment", reloaded.get("ok", false) and reloaded.profile == saved.profile)
	service.use_offline()
	service.queue_free()
	await process_frame
	print("NAME_SDK_FAILED=", failed)
	quit(1 if failed else 0)
