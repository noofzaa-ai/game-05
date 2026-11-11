extends "res://client/session/local_session.gd"
## Camp read views backed exclusively by authenticated server RPCs.
signal ownership_changed
signal command_completed(id: int, result: Dictionary)
var account
var api = preload("res://client/online/profile_client.gd").new()
var _busy := false
var _request_id := 0

func is_remote() -> bool: return true

func refresh_account() -> Dictionary:
	var result: Dictionary = await api.fetch(account)
	if result.get("ok", false):
		if not preload("res://logic/item_rules_loader.gd").apply_tuning(result.get("equipment_tuning"), rules):
			return {"ok": false, "error": "not_configured"}
		var decoded = Profile.from_dict(result.profile, rules, camp)
		if decoded == null: return {"ok": false, "error": "invalid_profile"}
		if profile == null: profile = decoded
		else:
			for field in ["card_gear", "card_fashion", "stash", "vault", "camp_level", "facility_levels","farm", "appearance", "name", "created", "beta_kit_version", "diamonds", "mall_owned", "bonus_stash_slots", "armor_migration_version", "relics", "card_deck"]:
				profile.set(field, decoded.get(field))
		ownership_changed.emit()
	return result

func command(request: Dictionary) -> Dictionary:
	if _busy: return {"ok": false, "error": "busy"}
	if account == null or account.status != account.Status.AUTHENTICATED:
		return {"ok": false, "error": "not_online"}
	_busy = true
	_request_id += 1
	_execute.call_deferred(_request_id, request.duplicate(true))
	return {"ok": false, "pending": true, "id": _request_id, "error": "pending"}

func _execute(id: int, request: Dictionary) -> void:
	var result: Dictionary
	if request.get("type") == "set_name":
		# The creator has already reserved the name through NameClient.
		result = await refresh_account()
	else:
		result = await api.submit(account, api.prepare(request))
		# Refetch after rejection/timeout too; never guess whether a write committed.
		var fresh: Dictionary = await refresh_account()
		if not fresh.get("ok", false): result = fresh
	_busy = false
	command_completed.emit(id, result)

func start_journey(_data, _weapons: Array, _seed_value: int, _party_profiles: Dictionary = {}) -> void:
	push_error("Account sessions require an authoritative room")
