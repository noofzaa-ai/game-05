extends RefCounted
## 2026-11-17 Boss screenshots: (1) a greyed Equip (level gate) must say why, a weapon cannot be taken off but swapped,
## (2) bulk sale by rarity in the shop's Sell tab (logic/shop.gd batch_sellable + shop_sell_batch).
const F := preload("res://tests/online_fixture.gd")
const Commands := preload("res://logic/commands.gd")
const Shop := preload("res://logic/shop.gd")
const Profile := preload("res://logic/profile.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const CardTokens := preload("res://client/card_tokens.gd")
const Runner := preload("res://server/profile/runner.gd")
const RELIC := "relic_goblin_chief"


static func _piece(f: Dictionary, id: String, slot: String, tier: int, item_id: String = ""):
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var catalog_id := item_id if not item_id.is_empty() else ("armour_magic_" + slot if slot != "weapon" else "race_runeborn_magic_weapon")
	return ItemSystem.create_item(f.rules, id, slot, tier, rng, "", catalog_id)


func run(ctx) -> void:
	_equip_reason(ctx)
	_swap_weapon(ctx)
	_batch_sellable(ctx)
	_batch_commands(ctx)
	_strings(ctx)
	await _shop_ui(ctx, ctx)


func _state(f: Dictionary) -> Dictionary:
	return {"profile": f.profile, "rules": f.rules, "camp": f.camp, "location": "camp", "cosmetics": f.cosmetics}


func _equip_reason(ctx) -> void:
	var f := F.make()
	var p = f.profile
	var blade = _piece(f, "gs-lvl15", "weapon", 2, "race_runeborn_greatsword_weapon")
	p.stash.add_item(blade)
	var problem: String = p.wear_problem("greatsword", blade, f.rules)
	ctx.check("equip reason: a low greatsword card gets level_too_low for a level-15 weapon (%s)" % problem, problem == "level_too_low")
	CardTokens.language = "en"
	var text := CardTokens.equip_block_text(problem, 15, 1)
	ctx.check("equip reason (en): names the needed and current level: %s" % text, text.contains("15") and text.contains("(now 1)"))
	CardTokens.language = "th"
	var thai := CardTokens.equip_block_text(problem, 15, 1)
	ctx.check("equip reason (th): translated, with both numbers", thai.contains("15") and thai != text)
	CardTokens.language = "en"
	ctx.check("equip reason: a wearable piece has no reason", CardTokens.equip_block_text("", 1, 1).is_empty() and CardTokens.equip_block("")["key"] == "")
	ctx.check("equip reason: other problems use their err_ text", CardTokens.equip_block("wrong_armour_class")["key"] == "err_wrong_armour_class" and CardTokens.equip_block_text("wrong_weapon_family") == CardTokens.t("err_wrong_weapon_family"))
	ctx.check("unequip state: the weapon slot is blocked, armour is not", CardTokens.unequip_blocked("weapon") and not CardTokens.unequip_blocked("shirt") and Profile.unequip_problem("weapon") == "weapon_required" and Profile.unequip_problem("ring").is_empty())
	var note := CardTokens.t("unequip_weapon_note")
	ctx.check("unequip state: the reason text exists (en)", note != "unequip_weapon_note" and note.contains("replace"))
	CardTokens.language = "th"
	ctx.check("unequip state: Thai reason differs", CardTokens.t("unequip_weapon_note") != note)
	CardTokens.language = "en"
	# Grandfathered: a worn piece above the card's level stays worn; only wearing checks the level.
	var worn_piece = _piece(f, "worn-l15", "weapon", 0, "race_viking_greatsword_weapon")
	p.card_deck["cards"]["greatsword"]["progress"] = {"level": 15, "xp": 0}
	p.loadout_of("greatsword").equip(worn_piece)
	p.card_deck["cards"]["greatsword"]["progress"] = {"level": 3, "xp": 0}
	var r: Dictionary = Commands.apply(_state(f), {"type": "equip", "item": "gs-lvl15", "source": "stash", "card": "greatsword"}, F.rng())
	ctx.check("grandfather: the worn level-15 weapon stays on a level-3 card, the new level-15 one is refused with level_too_low", p.loadout_of("greatsword").item_at("weapon", 0) == worn_piece and r.get("error", "") == "level_too_low")


func _swap_weapon(ctx) -> void:
	var f := F.make()
	var p = f.profile
	p.card_deck["cards"]["magic"]["progress"] = {"level": 15, "xp": 0}
	var old = p.loadout_of("magic").item_at("weapon", 0)
	var spare = _piece(f, "magic-spare", "weapon", 1)
	p.stash.add_item(spare)
	var r: Dictionary = Commands.apply(_state(f), {"type": "equip", "item": "magic-spare", "source": "stash", "card": "magic"}, F.rng())
	ctx.check("swap: equipping a weapon replaces the worn one in one command (%s)" % [r.get("error", "")], r.get("ok", false) and p.loadout_of("magic").item_at("weapon", 0) == spare and p.stash.items.has(old) and not p.stash.items.has(spare))
	r = Commands.apply(_state(f), {"type": "unequip", "slot": "weapon", "destination": "stash", "card": "magic"}, F.rng())
	ctx.check("swap: unequip of the weapon is refused (weapon_required) and the weapon stays", r.get("error", "") == "weapon_required" and p.loadout_of("magic").item_at("weapon", 0) == spare)
	r = Commands.apply(_state(f), {"type": "unequip", "slot": "shirt", "destination": "stash", "card": "magic"}, F.rng())
	ctx.check("swap: armour can be unequipped", r.get("ok", false) and p.loadout_of("magic").item_at("shirt", 0) == null)


func _batch_sellable(ctx) -> void:
	var f := F.make()
	var p = f.profile
	p.stash.items.clear()
	var empty: Dictionary = Shop.batch_sellable(p, f.rules, ["normal"])
	ctx.check("batch_sellable: an empty stash sells nothing", empty.count == 0 and empty.total == 0 and empty.entries.is_empty())
	var white1 = _piece(f, "w1", "shirt", 0)
	var white2 = _piece(f, "w2", "pants", 0)
	var blue = _piece(f, "b1", "shoes", 1)
	var purple = _piece(f, "p1", "shirt", 2)
	var relic_white = _piece(f, "rw", "shirt", 0)
	relic_white.relic = RELIC
	var boss = _piece(f, "boss1", "ring", 0, "boss_goblin_chief_ring")
	var starter = _piece(f, "starter-keep", "shirt", 0)
	for item in [white1, white2, blue, purple, relic_white, boss, starter]:
		p.stash.items.append(item)
	var white: Dictionary = Shop.batch_sellable(p, f.rules, ["normal"])
	ctx.check("batch_sellable: white only = the two plain white pieces (%s)" % [white.ids], white.ids == ["w1", "w2"] and white.total == 2 * Shop.item_sell_price(white1, f.rules))
	var blues: Dictionary = Shop.batch_sellable(p, f.rules, ["rare"])
	ctx.check("batch_sellable: blue only = the blue piece", blues.ids == ["b1"] and blues.total == Shop.item_sell_price(blue, f.rules))
	var both: Dictionary = Shop.batch_sellable(p, f.rules, ["normal", "rare"])
	ctx.check("batch_sellable: white + blue lists both, total is the sum", both.count == 3 and both.total == white.total + blues.total)
	ctx.check("batch_sellable: purple, relic-socketed, boss and starter pieces are never listed", not both.ids.has("p1") and not both.ids.has("rw") and not both.ids.has("boss1") and not both.ids.has("starter-keep"))
	var worn = p.loadout_of("magic").item_at("shirt", 0)
	ctx.check("batch_sellable: a worn piece is never listed", worn != null and not both.ids.has(worn.id) and not p.stash.items.has(worn))
	ctx.check("batch_sellable: the entries are shop_sell_batch entries", both.entries[0] == {"kind": "item", "id": "w1"})
	ctx.check("batch_sellable: an unknown tier id lists nothing", Shop.batch_sellable(p, f.rules, ["mythic"]).count == 0)


func _batch_commands(ctx) -> void:
	var f := F.make()
	var p = f.profile
	p.stash.items.clear()
	for n in 3:
		p.stash.items.append(_piece(f, "w%d" % n, "shirt", 0))
	p.stash.items.append(_piece(f, "b0", "pants", 1))
	p.stash.items.append(_piece(f, "e0", "shoes", 2))
	var plan: Dictionary = Shop.batch_sellable(p, f.rules, ["normal", "rare"])
	var gold_before: int = p.stash.gold
	var stale: Dictionary = Commands.apply(_state(f), {"type": "shop_sell_batch", "entries": plan.entries, "expected_price": plan.total + 1}, F.rng())
	ctx.check("batch command: a wrong expected_price is refused and nothing is sold", not stale.get("ok", false) and p.stash.items.size() == 5 and p.stash.gold == gold_before)
	var r: Dictionary = Commands.apply(_state(f), {"type": "shop_sell_batch", "entries": plan.entries, "expected_price": plan.total}, F.rng())
	ctx.check("batch command (offline): sells exactly the listed pieces and pays the total", r.get("ok", false) and p.stash.items.size() == 1 and p.stash.items[0].id == "e0" and p.stash.gold == gold_before + plan.total)
	# profile-runner path (server authority)
	var g := F.make()
	var q = g.profile
	q.stash.items.clear()
	for n in 2:
		q.stash.items.append(_piece(g, "rw%d" % n, "shirt", 0))
	q.stash.items.append(_piece(g, "rp", "shirt", 2))
	var runner := Runner.new()
	var served: Dictionary = Shop.batch_sellable(q, runner.rules, ["normal", "rare"])
	var gold_q: int = q.stash.gold
	var request := {"v": 1, "state": {"profile": q.to_dict(), "rng_state": "77"}, "seed": "00000000000004d", "name": "Hero", "command": {"type": "shop_sell_batch", "entries": served.entries, "expected_price": served.total}}
	var out: Dictionary = runner.execute(request)
	ctx.check("batch command (profile runner): ok, only the epic piece is left, gold paid (%s)" % [out.get("error", out.get("reason", ""))], out.get("ok", false) and out.profile.stash.items.size() == 1 and out.profile.stash.items[0].id == "rp" and int(out.profile.stash.gold) == gold_q + served.total)


func _strings(ctx) -> void:
	for lang in ["en", "th"]:
		CardTokens.language = lang
		var ok := true
		for key in ["shop_bulk_white", "shop_bulk_blue", "shop_bulk_both", "shop_bulk_line", "shop_bulk_sure", "shop_bulk_none", "shop_bulk_sold", "shop_bulk_hint"]:
			ok = ok and CardTokens.t(key) != key
		ctx.check("bulk sell strings exist (%s)" % lang, ok)
	CardTokens.language = "en"
	ctx.check("bulk sell result toast (en)", CardTokens.t("shop_bulk_sold") % [3, 300] == "Sold 3 items for 300 gold")


func _shop_ui(ctx, tree: SceneTree) -> void:
	var gs = tree.root.get_node("GameState")
	var saved = gs.profile
	gs.ensure_profile()
	var p = gs.profile
	p.stash.items.clear()
	var rules = gs.item_rules
	var screen := Control.new()
	screen.size = Vector2(1280, 720)
	tree.root.add_child(screen)
	var panel = load("res://client/hub_shop_panel.gd").new()
	screen.add_child(panel)
	panel.size = Vector2(1280, 720)
	panel.select_tab("sell")
	await tree.process_frame
	ctx.check("shop ui: with nothing sellable all three bulk buttons are disabled", panel._bulk_buttons.values().all(func(b): return b.disabled))
	var f := {"rules": rules}
	p.stash.items.append(_piece(f, "ui-w", "shirt", 0))
	p.stash.items.append(_piece(f, "ui-b", "pants", 1))
	panel.refresh()
	var white: Dictionary = panel.bulk_plan(p, "white")
	ctx.check("shop ui: white button shows 1 item and its gold", white.count == 1 and not panel._bulk_buttons["white"].disabled and panel._bulk_buttons["white"].text.contains(str(white.total)))
	ctx.check("shop ui: the both button counts 2 items", panel.bulk_plan(p, "both").count == 2)
	panel._bulk_pressed("white")
	ctx.check("shop ui: the first press only arms the confirm (nothing sold)", panel.bulk_pending == "white" and p.stash.items.size() == 2 and panel._bulk_buttons["white"].text == CardTokens.t("shop_bulk_sure") % [1, white.total])
	panel.select_item("ui-b")
	ctx.check("shop ui: tapping a piece cancels the confirm", panel.bulk_pending == "")
	screen.queue_free()
	gs.profile = saved
	await tree.process_frame
