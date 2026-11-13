extends Node
## Client identity only. LocalSession still owns gameplay until RemoteSession integration.
signal changed

const ConnectionConfig := preload("res://client/online/connection_config.gd")
const SessionStore := preload("res://client/online/session_store.gd")
const CardTokens := preload("res://client/card_tokens.gd")
const HubLook := preload("res://client/hub_look.gd")
const HttpAdapter := preload("res://client/online/http_adapter.gd")
const Status = preload("res://client/online/account_status.gd").Status
var status := Status.OFFLINE
var reason := "not_connected"
var auth_method := ""
var session  # NakamaSession; never print it (SDK string conversion contains tokens).
var client
var store = SessionStore.new()
var _adapter
var _generation := 0
var _cache := {}
var _config := {}
var _refresh_in := 30.0
var _started := false
var _google_session := {}
var _presence_in := 0.0
var _presence_busy := false
var _badge: Label  ## the status word inside the pill
var _pill: Panel  ## a small leather pill, top centre of the hub's top bar (between the title and the gold counter)
var _dot: Panel  ## red / amber / green (the word says it too)
var _shown := ""
## Boss 2026-11-13: when the sign-in at boot fails the game opens the hub offline and the pill becomes a small
## "Offline · Reconnect" button that retries the sign-in in place (no title screen). Set by offer_reconnect().
var reconnect_offered := false
var _reconnecting := false
var _reconnect: Button  ## invisible tap area over the pill (>= the phone tap minimum), only while reconnect_offered


func _ready() -> void:
	if name == "Online":
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--net-account="):
				var suffix := arg.trim_prefix("--net-account=")
				if RegEx.create_from_string("^[a-zA-Z0-9_-]{1,32}$").search(suffix) != null:
					store.path = "user://online_debug_%s.json" % suffix
		get_node("/root/Nakama").logger._level = NakamaLogger.LOG_LEVEL.NONE
		_build_badge()


func _process(delta: float) -> void:
	if _badge != null:
		var scene := get_tree().current_scene
		# Hidden in the fight and on its summary (Boss 2026-11-11: it covered the wave banner and the boss name).
		_pill.visible = scene != null and scene.scene_file_path not in ["res://scenes/boot.tscn", "res://scenes/stage.tscn", "res://scenes/journey.tscn"]
		if _pill.visible and _hub_overlay_open(scene):
			_pill.visible = false  # a hub panel / the character screen covers the top bar: the pill would sit on its header
		_reconnect.visible = _pill.visible and reconnect_offered
		_pill.self_modulate = CardTokens.HUB_HOVER if _reconnect.visible and not _reconnect.disabled and (_reconnect.is_hovered() or _reconnect.has_focus()) else Color.WHITE
		var key := "%s|%s|%s" % [pill_text(), get_viewport().get_visible_rect().size, _reconnect.disabled]
		if _pill.visible and key != _shown:
			_shown = key
			_layout_pill()
	if status != Status.AUTHENTICATED:
		return
	_presence_in -= delta
	if _presence_in <= 0.0 and not _presence_busy:
		_presence_in = 25.0
		_presence()
	_refresh_in -= delta
	if _refresh_in <= 0.0:
		_refresh_in = 30.0
		# Periodic bounded verification also detects a dropped network while menus/gameplay continue.
		connect_account(_config)


func status_text() -> String:
	match status:
		Status.CONNECTING:
			return HubLook.t("online_connecting")
		Status.AUTHENTICATED:
			return HubLook.t("online_online")
	return HubLook.t("online_offline")


## The pill's words: the status, or "Offline · Reconnect" / "Offline · Sign in" while a retry is offered.
func pill_text() -> String:
	if reconnect_offered and status != Status.AUTHENTICATED:
		if _reconnecting or status == Status.CONNECTING:
			return HubLook.t("online_connecting")
		return HubLook.t("online_sign_in" if needs_website_sign_in() else "online_reconnect")
	return status_text()


## True when only the website can give a new session (the page's sign-in token is gone or refused).
func needs_website_sign_in() -> bool:
	return OS.has_feature("web") and reason == "google_login_required"


## The boot sign-in failed: play offline on the hub and offer a retry (pack_loader.gd). `why` is kept for the log.
func offer_reconnect(why: String) -> void:
	if status == Status.AUTHENTICATED:
		use_offline()  # signed in, but the account profile did not load: the hub runs on the local profile
		if why == "":
			why = "account_profile_unavailable"
	if why != "":
		reason = why
	reconnect_offered = true
	print("online account: offline on the hub, reconnect offered (", reason, ")")
	changed.emit()


## The Reconnect button: sign in again and load the account profile; on success the hub reopens with it.
## Stays on the hub either way (Boss 2026-11-13). With no page session left, it goes to the website sign-in.
func reconnect() -> void:
	if _reconnecting or status == Status.CONNECTING:
		return
	if needs_website_sign_in():
		JavaScriptBridge.eval("window.zorxAutoEnter = false; location.replace('https://zorx.daiyooo.com/?play=1');", true)
		return
	var game_state = get_node_or_null("/root/GameState")
	if game_state == null:
		return
	_reconnecting = true
	_shown = ""
	changed.emit()
	var ok: bool = await game_state.connect_account_profile()
	_reconnecting = false
	if not ok:
		offer_reconnect("")
		return
	reconnect_offered = false
	_shown = ""
	changed.emit()
	var scene := get_tree().current_scene
	if scene != null and scene.scene_file_path == game_state.CARD_DECK_SCENE:
		get_tree().change_scene_to_file(game_state.CARD_DECK_SCENE)  # rebuild the hub on the account profile


func begin() -> void:
	if not _started:
		_started = true
		connect_account()


func use_offline() -> void:
	_generation += 1
	if _adapter != null:
		_adapter.cancel_all()
	session = null
	status = Status.OFFLINE
	reason = "chosen_offline"
	changed.emit()


func _set_offline(why: String, generation: int) -> void:
	if generation != _generation:
		return
	session = null
	status = Status.OFFLINE
	reason = why
	print("online account: offline (", why, ")")
	changed.emit()


func _make_client(config: Dictionary):
	if _adapter != null:
		_adapter.cancel_all()
		_adapter.queue_free()
	_adapter = HttpAdapter.new()
	_adapter.timeout = 10
	_adapter.logger._level = NakamaLogger.LOG_LEVEL.NONE
	add_child(_adapter)
	return NakamaClient.new(_adapter, str(config.client_key), str(config.scheme), str(config.host), int(config.port), 10)


func _unauthorized(result) -> bool:
	return result != null and result.is_exception() and result.get_exception().status_code == 401


func connect_account(config: Dictionary = {}) -> void:
	if status == Status.CONNECTING:
		return
	_config = ConnectionConfig.load_default() if config.is_empty() else config.duplicate()
	_generation += 1
	var generation := _generation
	if not ConnectionConfig.valid(_config):
		_set_offline("not_configured", generation)
		return
	status = Status.CONNECTING
	reason = ""
	changed.emit()
	var google_required := OS.has_feature("web")
	if google_required and _google_session.is_empty():
		var raw = JavaScriptBridge.eval("JSON.stringify(window.zorxGoogleSession || null)", true)
		var decoded = JSON.parse_string(str(raw))
		if not decoded is Dictionary or not decoded.has_all(["token", "refresh_token", "user_id", "api_origin"]):
			_set_offline("google_login_required", generation)
			return
		if str(decoded.api_origin) != ConnectionConfig.scope(_config).trim_suffix(":443"):
			_set_offline("google_backend_mismatch", generation)
			return
		_google_session = decoded
		JavaScriptBridge.eval("window.zorxGoogleSession = null", true)
	if google_required:
		# Keep the legacy device account cache intact. Never merge inventories by email/name.
		store.path = "user://online_google_%s.json" % str(_google_session.user_id).sha256_text().substr(0, 24)
	_cache = store.load_state(ConnectionConfig.scope(_config))
	if not store.problem.is_empty():
		_set_offline(store.problem, generation)
		return  # Never silently replace an unreadable/different backend identity.
	if _cache.is_empty():
		_cache = {"version": 1, "scope": ConnectionConfig.scope(_config), "device": SessionStore.new_device(), "registered": false, "user_id": "", "token": "", "refresh_token": ""}
		if not store.save_state(_cache):
			_set_offline("cache_write_failed", generation)
			return
	if google_required and not _google_session.get("consumed", false):
		_cache.merge({"token": _google_session.token, "refresh_token": _google_session.refresh_token, "user_id": _google_session.user_id}, true)
		_google_session["consumed"] = true
	client = _make_client(_config)
	var candidate
	var source := "device"
	var token := str(_cache.get("token", ""))
	if not token.is_empty():
		source = "restored"
		candidate = NakamaSession.new(token, false, str(_cache.get("refresh_token", "")))
		if candidate.would_expire_in(90):
			if not candidate.refresh_token.is_empty() and not candidate.is_refresh_expired():
				source = "refresh"
				candidate = await client.session_refresh_async(candidate)
				if generation != _generation:
					return
				if candidate.is_exception():
					if not _unauthorized(candidate):
						_set_offline("refresh_unavailable", generation)
						return
					candidate = null
			else:
				candidate = null
	if candidate != null and (not candidate.valid or candidate.user_id.is_empty()):
		_set_offline("invalid_session", generation)
		return
	if candidate != null:
		var restored_account = await client.get_account_async(candidate)
		if generation != _generation:
			return
		if restored_account.is_exception():
			if not _unauthorized(restored_account):
				_set_offline("account_unavailable", generation)
				return
			candidate = null
		elif restored_account.user == null or restored_account.user.id != candidate.user_id:
			_set_offline("account_mismatch", generation)
			return
	if candidate == null:
		if google_required:
			_set_offline("google_login_required", generation)
			return
		source = "device"
		candidate = await client.authenticate_device_async(str(_cache.device), null, not bool(_cache.get("registered", false)))
		if generation != _generation:
			return
		if candidate.is_exception() or not candidate.valid or candidate.user_id.is_empty():
			_set_offline("authentication_unavailable", generation)
			return
		var account = await client.get_account_async(candidate)
		if generation != _generation:
			return
		if account.is_exception() or account.user == null or account.user.id != candidate.user_id:
			_set_offline("account_unavailable", generation)
			return
	if not str(_cache.get("user_id", "")).is_empty() and _cache.user_id != candidate.user_id:
		_set_offline("account_mismatch", generation)
		return
	_cache.merge({"registered": true, "user_id": candidate.user_id, "token": candidate.token, "refresh_token": candidate.refresh_token}, true)
	if not store.save_state(_cache):
		_set_offline("cache_write_failed", generation)
		return
	session = candidate
	status = Status.AUTHENTICATED
	reason = ""
	_refresh_in = 30.0
	auth_method = "google" if google_required else source
	print("online account: authenticated (", source, ")")
	changed.emit()


## The account status as a small leather pill with a coloured dot and one word (Offline / Connecting... / Online), in
## the hub look (Boss 2026-11-12). It sits top centre, inside the hub's top bar: left of it is the "MY CARDS" title,
## right of it the gold counter and the Account / Settings buttons, so it covers neither. Hidden in the fight.
func _build_badge() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	_pill = Panel.new()
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_pill)
	_dot = Panel.new()
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.add_child(_dot)
	_badge = Label.new()
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pill.add_child(_badge)
	_reconnect = Button.new()
	_reconnect.name = "Reconnect"
	_reconnect.flat = true
	_reconnect.visible = false
	_reconnect.focus_mode = Control.FOCUS_ALL
	_reconnect.pressed.connect(reconnect)
	layer.add_child(_reconnect)
	_layout_pill()


## True while the hub shows a service panel or the card character screen over its top bar (read only).
static func _hub_overlay_open(scene: Node) -> bool:
	var panels = scene.get("_panels")
	if panels is Dictionary:
		for panel in panels.values():
			if panel is CanvasItem and panel.visible:
				return true
	var character = scene.get("_character")
	return character is CanvasItem and character.is_visible_in_tree()


func _layout_pill() -> void:
	var screen := get_viewport().get_visible_rect().size
	var s := CardTokens.scale_for(screen)
	_badge.text = pill_text()
	CardTokens.style_text(_badge, CardTokens.FONT_ONLINE, CardTokens.HUB_CREAM, s, CardTokens.OUTLINE_HUB, "medium", CardTokens.HUB_OUTLINE)
	var h := CardTokens.ONLINE_PILL_H * s
	var pad := CardTokens.ONLINE_PILL_PAD * s
	var dot := CardTokens.ONLINE_DOT * s
	var text_w := _badge.get_minimum_size().x
	_pill.size = Vector2(pad * 2.5 + dot + text_w, h)
	_pill.position = Vector2((screen.x - _pill.size.x) * 0.5, (CardTokens.HUB_TITLE_Y * s) - h * 0.5)
	CardTokens.panel(_pill, HubLook.leather(s, CardTokens.ONLINE_PILL_H * 0.5, 2.0))
	_dot.size = Vector2(dot, dot)
	_dot.position = Vector2(pad, (h - dot) * 0.5)
	var connecting := status == Status.CONNECTING or _reconnecting
	var colour: Color = CardTokens.ONLINE_ON if status == Status.AUTHENTICATED else (CardTokens.ONLINE_WAIT if connecting else CardTokens.ONLINE_OFF)
	CardTokens.panel(_dot, CardTokens.flat(colour, CardTokens.HUB_LEATHER_EDGE, 2.0, CardTokens.ONLINE_DOT * 0.5, s))
	_badge.position = Vector2(pad * 1.5 + dot, 0.0)
	_badge.size = Vector2(text_w, h)
	# The Reconnect tap area: the pill, grown to the phone tap minimum (it stays a small pill to look at).
	var phone := CardTokens.is_phone(screen)
	var tap := Vector2(maxf(_pill.size.x, CardTokens.tap(0.0, phone) * s), maxf(h, CardTokens.tap(CardTokens.ONLINE_PILL_H, phone) * s))
	_reconnect.size = tap
	_reconnect.position = _pill.position + (_pill.size - tap) * 0.5
	_reconnect.disabled = connecting
	_reconnect.tooltip_text = HubLook.t("online_reconnect_hint")
	CardTokens.bare_button(_reconnect, s, CardTokens.ONLINE_PILL_H * 0.5)


func _presence() -> void:
	if client == null or session == null: return
	_presence_busy = true
	await client.rpc_async(session, "zorx_social_v1", JSON.stringify({"v": 1, "op": "presence"}))
	_presence_busy = false


## Explicit account switch: discard this account's credentials before leaving the game.
func logout_to_website() -> void:
	use_offline()
	_started = false
	_google_session.clear()
	_cache.clear()
	auth_method = ""
	if FileAccess.file_exists(store.path):
		DirAccess.remove_absolute(store.path)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.zorxGoogleSession = null; window.zorxAutoEnter = false; location.replace('https://zorx.daiyooo.com/?logout=1');", true)
