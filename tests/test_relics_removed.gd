extends RefCounted
## The Relic system is gone (Boss 2026-11-14, docs/po_defaults.md). Checks that nothing of it is left in the
## rules, the wire or the hub, and that saves written before the removal (with "relics" / "relic_loot") still load.
const F := preload("res://tests/online_fixture.gd")
const Commands := preload("res://logic/commands.gd")
const Wire := preload("res://logic/net_wire.gd")
const CardTokens := preload("res://client/card_tokens.gd")


func run(ctx) -> void:
	_gone(ctx)
	_old_profile(ctx)
	_old_run(ctx)


func _gone(ctx) -> void:
	for path in ["res://logic/relics.gd", "res://logic/relic_effects.gd", "res://data/relics/catalog.json", "res://client/relic_orbit.gd"]:
		ctx.check("relics removed: %s is gone" % path, not FileAccess.file_exists(path))
	ctx.check("relics removed: the fighter wire row has no relic_state", not Wire.FIGHTER_FIELDS.has("relic_state"))
	ctx.check("relics removed: the effect relic_goblin_poison is gone", not F.Combat.load_default().effects.has("relic_goblin_poison"))
	var ids: Array = CardTokens.HUB_SERVICES.map(func(entry): return str(entry["id"]))
	ctx.check("relics removed: the hub menu has 5 entries without relics %s" % [ids], ids.size() == 5 and not ids.has("relics"))
	var f := F.make()
	var result: Dictionary = Commands.apply(f, {"type": "relic_equip", "relic": "x", "slot": 0}, F.rng())
	ctx.check("relics removed: relic_equip is an unknown command", not result.get("ok", false) and str(result.get("error", "")) == "unknown_command")
	ctx.check("relics removed: a new save has no relics field", not f["profile"].to_dict().has("relics"))


func _old_profile(ctx) -> void:
	var f := F.make()
	var saved: Dictionary = f["profile"].to_dict()
	var shapes := {
		"empty": {"v": 1, "owned": [], "equipped": ["", "", ""]},
		"owned and worn": {"v": 1, "owned": [{"id": "relic-1-2", "relic": "goblin_medallion"}], "equipped": ["relic-1-2", "", ""]},
		"malformed": {"v": 9, "owned": "nope"},
		"null": null,
	}
	for name in shapes:
		var old := saved.duplicate(true)
		old["relics"] = shapes[name]
		var loaded = F.Profile.from_dict(old, f["rules"], f["camp"])
		ctx.check("relics removed: an old save with %s relics still loads" % name, loaded != null and loaded.name == f["profile"].name)
		if loaded != null:
			ctx.check("relics removed: re-saving drops the old relics field (%s)" % name, not loaded.to_dict().has("relics"))


func _old_run(ctx) -> void:
	var f := F.make()
	var saved: Dictionary = f["run"].to_dict()
	saved["relic_loot"] = [{"id": "relic-1-2", "relic": "goblin_lantern"}]
	var trip = F.Run.from_dict(saved, f["rules"], f["camp"])
	ctx.check("relics removed: an old run with relic_loot still loads", trip != null)
	if trip != null:
		ctx.check("relics removed: a re-saved run has no relic_loot", not trip.to_dict().has("relic_loot"))
	var drop: Dictionary = trip.loot_into_bag({"gold": 3, "materials": {}, "items": [], "relics": [{"id": "r", "relic": "goblin_lantern"}]}) if trip != null else {}
	ctx.check("relics removed: a drop that still names relics is ignored", not drop.has("relics") and int(drop.get("gold", 0)) == 3)
