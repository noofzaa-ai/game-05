extends RefCounted
## Boss 2026-11-22: "Sell all White" broke, and with it "White + Blue". Root cause: a big stash of level-1 drops
## (ids "starter-drop-drop-<seed>-<state>", logic/gear_levels.gd) made the 64-entry bulk sale command longer than the
## 4096-character profile RPC payload cap (server/names/runtime/src/security.ts + profile.ts), so the server refused it
## (invalid_payload) and nothing sold. Now one press = one command that fits (Shop.BATCH_ENTRIES_BUDGET); the label shows
## exactly that press's count and gold, and the rest sells on the next press.
const F := preload("res://tests/online_fixture.gd")
const Commands := preload("res://logic/commands.gd")
const Shop := preload("res://logic/shop.gd")
const Loot := preload("res://logic/loot.gd")
const RaceDrops := preload("res://logic/race_drops.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const PC := preload("res://client/online/profile_client.gd")
const Runner := preload("res://server/profile/runner.gd")
const CardTokens := preload("res://client/card_tokens.gd")
const RPC_CAP := 4096  # server/names/runtime/src/security.ts + profile.ts


static func _piece(rules, id: String, slot: String, tier: int, item_id: String):
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	return ItemSystem.create_item(rules, id, slot, tier, rng, "", item_id)


func _state(f: Dictionary) -> Dictionary:
	return {"profile": f.profile, "rules": f.rules, "camp": f.camp, "location": "camp", "cosmetics": f.cosmetics}


## A stash the way real play fills it: monster drops through the race + gear-level pipeline at cap 1 (level-1 drops).
static func _real_drops(f: Dictionary, count: int) -> void:
	var p = f.profile
	p.stash.capacity = maxi(p.stash.capacity, p.stash.items.size() + count)
	var rng := RandomNumberGenerator.new()
	var n := 0
	var tries := 0
	while n < count and tries < 20000:
		tries += 1
		rng.seed = hash([77, "kill-%d-3" % tries])
		var drop: Dictionary = Loot.roll(f.rules, f.loot, "brute", 15, ["greatsword", "sword_shield", "longbow", "magic"], rng, 3.0)
		for item in drop["items"]:
			if n < count:
				p.stash.items.append(RaceDrops.convert_piece(f.rules, item, [{"race": "human", "class": "greatsword"}], RaceDrops.WAVE, 5, 1))
				n += 1


static func _envelope_len(command: Dictionary) -> int:
	var pc = PC.new()
	pc.revision = 2147483646  # the longest revision number
	return JSON.stringify(pc.prepare(command)).length()


func run(ctx) -> void:
	_payload_fits(ctx)
	_labels_match(ctx)
	_never_sold(ctx)
	_server_path(ctx)
	_marking(ctx)
	await _ui(ctx, ctx)


## Every option's command fits the RPC cap with real long ids; repeated presses sell every piece of the tier.
func _payload_fits(ctx) -> void:
	for key in [["white", ["normal"]], ["blue", ["rare"]], ["both", ["normal", "rare"]]]:
		var f := F.make()
		f.profile.stash.items.clear()
		_real_drops(f, 160)
		var p = f.profile
		var expected := 0
		for item in p.stash.items:
			if key[1].has(str(f.rules.tiers[item.tier]["id"])):
				expected += 1
		var presses := 0
		var sold := 0
		var biggest := 0
		var ok := true
		while presses < 20:
			var plan: Dictionary = Shop.batch_sellable(p, f.rules, key[1])
			if plan.count == 0:
				break
			presses += 1
			var command := {"type": "shop_sell_batch", "entries": plan.entries, "expected_price": int(plan.total)}
			biggest = maxi(biggest, _envelope_len(command))
			var gold: int = p.stash.gold
			var r: Dictionary = Commands.apply(_state(f), command, F.rng())
			ok = ok and r.get("ok", false) and p.stash.gold == gold + plan.total and int(r.result.items) == plan.count
			sold += plan.count
		var left := 0
		for item in p.stash.items:
			if key[1].has(str(f.rules.tiers[item.tier]["id"])):
				left += 1
		ctx.check("bulk %s: real level-1 drop ids, every command <= %d chars (biggest %d), %d pieces sold in %d presses, none left" % [key[0], RPC_CAP, biggest, sold, presses],
			expected > 0 and biggest <= RPC_CAP and ok and sold == expected and left == 0)


## The label count/gold is exactly the sale; "more" counts what waits for the next press; only the label's tiers sell.
func _labels_match(ctx) -> void:
	var f := F.make()
	var p = f.profile
	p.stash.items.clear()
	_real_drops(f, 160)
	var white: Dictionary = Shop.batch_sellable(p, f.rules, ["normal"])
	var blue: Dictionary = Shop.batch_sellable(p, f.rules, ["rare"])
	var both: Dictionary = Shop.batch_sellable(p, f.rules, ["normal", "rare"])
	var tiers_ok := true
	for item in p.stash.items:
		var tier_id := str(f.rules.tiers[item.tier]["id"])
		tiers_ok = tiers_ok and (not white.ids.has(item.id) or tier_id == "normal") and (not blue.ids.has(item.id) or tier_id == "rare") \
			and (not both.ids.has(item.id) or tier_id in ["normal", "rare"])
	ctx.check("bulk labels: White lists only white, Blue only blue, White+Blue only white/blue (never purple/gold)", tiers_ok and white.count > 0 and blue.count > 0)
	var sum := 0
	for id in both.ids:
		for item in p.stash.items:
			if item.id == id:
				sum += Shop.item_sell_price(item, f.rules)
	ctx.check("bulk labels: total = the sum of the listed pieces' sell prices", sum == both.total and both.count == both.entries.size() and Shop.batch_fits(both.entries))
	ctx.check("bulk labels: a big White+Blue stash keeps the rest for the next press (more=%d)" % both.more, both.more > 0 and both.count + both.more == white.count + white.more + blue.count + blue.more)


## Boss pieces (whatever rolled tier, incl. the level-20 boss weapons and Warlock set), worn, vault, relic-socketed, the
## starter kit and purple/gold are never sold by any option.
func _never_sold(ctx) -> void:
	var f := F.make()
	var p = f.profile
	p.stash.items.clear()
	var keep: Array = []
	for spec in [["bw", "ring", 0, "boss_goblin_chief_ring"], ["bb", "necklace", 1, "boss_orc_warlock_necklace"], ["bwb", "back", 0, "boss_orc_warlock_back"],
			["bs", "weapon", 0, "boss_orc_warlock_sword"], ["bsh", "offhand", 1, "boss_orc_warlock_shield"], ["bst", "weapon", 1, "boss_mummy_high_wizard_staff"],
			["bcr", "weapon", 0, "boss_mummy_boss_crook"], ["purple", "shirt", 2, "armour_magic_shirt"], ["gold", "pants", 3, "armour_magic_pants"],
			["starter-kit-v3-fixture-shirt", "shirt", 0, "armour_magic_shirt"]]:
		var piece = _piece(f.rules, spec[0], spec[1], spec[2], spec[3])
		ctx.check("never sold fixture: %s made" % spec[0], piece != null)
		if piece != null:
			p.stash.items.append(piece)
			keep.append(piece.id)
	var relic = _piece(f.rules, "relicked", "shirt", 0, "armour_magic_shirt")
	relic.relic = "relic_goblin_chief"
	p.stash.items.append(relic)
	keep.append(relic.id)
	var vault = _piece(f.rules, "vaulted", "shirt", 0, "armour_magic_shirt")
	p.vault.items.append(vault)
	p.stash.items.append(_piece(f.rules, "plain-w", "shoes", 0, "armour_magic_shoes"))
	p.stash.items.append(_piece(f.rules, "plain-b", "shoes", 1, "armour_magic_shoes"))
	var worn = p.loadout_of("magic").item_at("shirt", 0)
	for tiers in [["normal"], ["rare"], ["normal", "rare"]]:
		var plan: Dictionary = Shop.batch_sellable(p, f.rules, tiers)
		var bad: Array = plan.ids.filter(func(id): return keep.has(id) or id == "vaulted" or (worn != null and id == worn.id))
		ctx.check("never sold %s: boss (any rolled tier), purple, gold, starter, relic, vault, worn excluded %s" % [tiers, bad], bad.is_empty() and plan.count >= 1)
	var plan: Dictionary = Shop.batch_sellable(p, f.rules, ["normal", "rare"])
	var r: Dictionary = Commands.apply(_state(f), {"type": "shop_sell_batch", "entries": plan.entries, "expected_price": plan.total}, F.rng())
	var still := keep.all(func(id): return p.stash.items.any(func(it): return it.id == id))
	ctx.check("never sold: after White+Blue only plain-w/plain-b left the stash; vault and worn untouched (%s, %s, left %d/%d)" % [r.get("error", ""), plan.ids, p.stash.items.size(), keep.size()],
		r.get("ok", false) and still and p.stash.items.size() == keep.size() and p.vault.items.has(vault) and (worn == null or p.loadout_of("magic").item_at("shirt", 0) == worn))


## Through the server authority (profile runner) with a full-size level-1-drop stash.
func _server_path(ctx) -> void:
	var f := F.make()
	var q = f.profile
	q.stash.items.clear()
	_real_drops(f, 160)
	var runner := Runner.new()
	var plan: Dictionary = Shop.batch_sellable(q, runner.rules, ["normal", "rare"])
	var command := {"type": "shop_sell_batch", "entries": plan.entries, "expected_price": plan.total}
	var gold_q: int = q.stash.gold
	var size_before: int = q.stash.items.size()
	var out: Dictionary = runner.execute({"v": 1, "state": {"profile": q.to_dict(), "rng_state": "77"}, "seed": "00000000000004d", "name": "Hero", "command": command})
	ctx.check("server path: White+Blue of a level-1-drop stash fits the RPC (%d chars) and the runner sells exactly the plan (%s)" % [_envelope_len(command), out.get("error", "")],
		_envelope_len(command) <= RPC_CAP and out.get("ok", false) and out.profile.stash.items.size() == size_before - plan.count and int(out.profile.stash.gold) == gold_q + plan.total)


## The Mark list stops at what one command can carry.
func _marking(ctx) -> void:
	var entries: Array = []
	for n in 200:
		entries.append({"kind": "item", "id": "starter-drop-drop-%d-%d" % [1000000000 + n, 3000000000000000000 + n]})
	ctx.check("batch_fits: 64 long ids do not fit, a few do", not Shop.batch_fits(entries.slice(0, 64)) and Shop.batch_fits(entries.slice(0, 10)))
	ctx.check("batch_fits: more than BATCH_MAX short ids never fit", not Shop.batch_fits(range(Shop.BATCH_MAX + 1).map(func(n): return {"kind": "item", "id": "d%d" % n})))
	for lang in ["en", "th"]:
		CardTokens.language = lang
		ctx.check("shop_mark_full text (%s)" % lang, CardTokens.t("shop_mark_full") != "shop_mark_full" and (CardTokens.t("shop_mark_full") % 50).contains("50"))
	CardTokens.language = "en"


## The shop panel: the White+Blue button's count is one command's worth and Mark stops at the limit.
func _ui(ctx, tree: SceneTree) -> void:
	var gs = tree.root.get_node("GameState")
	var saved = gs.profile
	gs.ensure_profile()
	var p = gs.profile
	var saved_items: Array = p.stash.items.duplicate()
	var saved_capacity: int = p.stash.capacity
	p.stash.items.clear()
	_real_drops({"profile": p, "rules": gs.item_rules, "loot": F.make().loot}, 160)
	var screen := Control.new()
	screen.size = Vector2(1280, 720)
	tree.root.add_child(screen)
	var panel = load("res://client/hub_shop_panel.gd").new()
	screen.add_child(panel)
	panel.size = Vector2(1280, 720)
	panel.select_tab("sell")
	await tree.process_frame
	var plan: Dictionary = panel.bulk_plan(p, "both")
	ctx.check("shop ui: White+Blue button shows one command's count and gold (%s)" % panel._bulk_buttons["both"].text,
		plan.count > 0 and Shop.batch_fits(plan.entries) and panel._bulk_buttons["both"].text.contains(str(plan.count)) and panel._bulk_buttons["both"].text.contains(str(plan.total)))
	for item in p.stash.items:
		panel._toggle_mark(item.id)
	ctx.check("shop ui: marking every piece stops at what one sale can carry (%d marked)" % panel.marked.size(),
		panel.marked.size() > 0 and panel.marked.size() < p.stash.items.size() and Shop.batch_fits(panel._marked_entries()))
	screen.queue_free()
	p.stash.items = saved_items
	p.stash.capacity = saved_capacity
	gs.profile = saved
	await tree.process_frame
