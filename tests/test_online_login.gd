extends RefCounted
const Store := preload("res://client/online/session_store.gd")
const Config := preload("res://client/online/connection_config.gd")
const Account := preload("res://client/online/online_account.gd")

class FakeClient:
	extends RefCounted
	var auth_count := 0
	var refresh_count := 0
	var account_count := 0
	var rejected := false
	var delay := false
	var tree: SceneTree
	var create_flags := []
	var refreshed
	var login_session

	func authenticate_device_async(_device, _username, create):
		auth_count += 1
		create_flags.append(create)
		if delay:
			await tree.process_frame
		return login_session

	func get_account_async(session):
		account_count += 1
		if delay:
			await tree.process_frame
		return NakamaAsyncResult.new(NakamaException.new("redacted", 503)) if rejected else FakeAccount.new(session.user_id)

	func session_refresh_async(_session):
		refresh_count += 1
		return refreshed

class FakeAccount:
	extends RefCounted
	var user := {}
	func _init(uid):
		user = {"id": uid}
	func is_exception():
		return false

class TestAccount:
	extends "res://client/online/online_account.gd"
	var fake
	func _make_client(_config):
		return fake


static func jwt(uid: String, expiration: int) -> String:
	return "header." + Marshalls.utf8_to_base64(JSON.stringify({"uid": uid, "exp": expiration})).replace("+", "-").replace("/", "_").replace("=", "") + ".signature"


func run(ctx) -> void:
	var splitter = load("res://tools/web/pck_split.gd")
	ctx.check("Web packaging refuses development caches and backend sources", not splitter.safe_export_path("res://build/private-cache.json") and not splitter.safe_export_path("res://server/secrets.json") and not splitter.safe_export_path("res://pipeline/private.json"))
	ctx.check("Web packaging retains runtime SDK and public config", splitter.safe_export_path("res://data/online.local.json") and splitter.safe_export_path("res://addons/com.heroiclabs.nakama/LICENSE"))
	var config := {"version": 1, "enabled": true, "host": "api.example.com", "port": 443, "scheme": "https", "client_key": "public-app-key"}
	ctx.check("public HTTPS connection settings validate", Config.valid(config))
	var invalid := config.duplicate()
	invalid.host = "name@example.com/path"
	ctx.check("config rejects credentials and path injection", not Config.valid(invalid))
	invalid = config.duplicate()
	invalid.client_key = ""
	ctx.check("missing application key leaves offline", not Config.valid(invalid))
	invalid = config.duplicate()
	invalid.scheme = "http"
	invalid.host = "100.1.2.3"
	ctx.check("plaintext auth cannot target an arbitrary public host", not Config.valid(invalid))
	ctx.check("invalid JWT payload types cannot reach SDK parser", Store.jwt_payload("header." + Marshalls.utf8_to_base64('{"exp":{},"uid":"x"}') + ".signature").is_empty())
	ctx.check("device identifiers use fresh cryptographic randomness", Store.new_device() != Store.new_device() and Store.new_device().length() == 69)
	ctx.check("malformed token is discarded before SDK parsing", Store.jwt_payload("not-a-jwt").is_empty())
	var service := TestAccount.new()
	service.name = "TestOnline"
	service.store.path = "user://online_login_test_%s.json" % Store.new_device()
	ctx.root.add_child(service)
	var fake := FakeClient.new()
	fake.tree = ctx
	var now := int(Time.get_unix_time_from_system())
	fake.login_session = NakamaSession.new(jwt("test-user", now + 3600), false, jwt("test-user", now + 7200))
	fake.refreshed = fake.login_session
	service.fake = fake
	await service.connect_account(config)
	ctx.check("device authentication verifies account before authenticated state", service.status == Account.Status.AUTHENTICATED and fake.account_count == 1)
	ctx.check("first device login may create one account", fake.create_flags == [true])
	var first := service.store.load_state(Config.scope(config))
	ctx.check("session cache persists device identity and refresh token", first.get("registered", false) and not first.get("refresh_token", "").is_empty())
	await service.connect_account(config)
	ctx.check("valid restored session is checked by server without new login", fake.auth_count == 1 and fake.account_count == 2)
	first.token = jwt("test-user", now - 5)
	service.store.save_state(first)
	await service.connect_account(config)
	ctx.check("expired access token refreshes with SDK", fake.refresh_count == 1 and service.status == Account.Status.AUTHENTICATED)
	first.token = jwt("test-user", now - 5)
	service.store.save_state(first)
	fake.refreshed = NakamaSession.new(null, false, null, NakamaException.new("redacted", 401))
	await service.connect_account(config)
	ctx.check("rejected refresh reauthenticates same registered device without recreation", fake.auth_count == 2 and fake.create_flags == [true, false] and service.status == Account.Status.AUTHENTICATED)
	fake.rejected = true
	await service.connect_account(config)
	ctx.check("network/server failure falls back offline without new account", service.status == Account.Status.OFFLINE and fake.auth_count == 2)
	ctx.check("offline status warns about no cloud save", "ต้องต่ออินเทอร์เน็ต" in service.status_text())
	fake.rejected = false
	first.token = ""
	first.refresh_token = ""
	service.store.save_state(first)
	fake.delay = true
	service.connect_account(config)
	ctx.check("inflight login displays connecting state", service.status == Account.Status.CONNECTING)
	service.use_offline()
	await ctx.process_frame
	await ctx.process_frame
	ctx.check("late login result cannot override explicit offline choice", service.status == Account.Status.OFFLINE and service.session == null)
	fake.delay = false
	first.scope = "https://different.example:443"
	service.store.save_state(first)
	await service.connect_account(config)
	ctx.check("backend scope mismatch refuses silent identity replacement", service.reason == "cache_scope_or_format" and service.status == Account.Status.OFFLINE)
	var file := FileAccess.open(service.store.path, FileAccess.WRITE)
	file.store_string("broken cache")
	file.close()
	await service.connect_account(config)
	ctx.check("corrupt cache does not create another account", service.reason == "cache_invalid" and fake.auth_count == 3)
	DirAccess.remove_absolute(service.store.path)
	service.queue_free()
	await ctx.process_frame
	var idle := Account.new()
	ctx.check("title still provides Start while disconnected", idle.status == Account.Status.OFFLINE)
	idle.free()
