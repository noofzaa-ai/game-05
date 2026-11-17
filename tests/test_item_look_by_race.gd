extends RefCounted
## Boss 2026-11-17: item icons and the card's look were mixed up. Level-1 starter pieces (instance ids "starter-...") and level-15
## pieces use different models, so their icons differ, and equipping a piece changes the outfit on the card. Checked for every
## race x class x slot (shirt, pants, armband, shoes, weapon, Sword & Shield off-hand), then at the UI call sites that show icons
## or dress a model: each must use the race of the card that wears / shows the piece (logic/card_deck.gd gear_race), the same
## icon hub_item_cell.gd shows for that item + race.
const ItemAssets := preload("res://client/item_assets.gd")
const ItemSystem := preload("res://logic/item_system.gd")
const Deck := preload("res://logic/card_deck.gd")
const F := preload("res://tests/online_fixture.gd")
const RACES := ["human", "viking", "elf", "runeborn"]
const CLASSES := ["sword_shield", "greatsword", "longbow", "magic"]
const ARMOUR := ["shirt", "pants", "armband", "shoes"]
const SHARED := "res://art/armor/race_shared/"


class _Loadout:
	var items := {}
	func item_at(slot: String, _index: int = 0):
		return items.get(slot)


static func _piece(rules, id: String, slot: String, item_id: String):
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	return ItemSystem.create_item(rules, id, slot, 0, rng, str(rules.catalog.entry(item_id).get("weapon_type", "")), item_id)


## slot -> catalog id of the pieces a card of race x class wears.
static func _ids(catalog, race: String, cls: String) -> Dictionary:
	var ids := {"weapon": catalog.race_piece(race, cls, "weapon")}
	for slot in ARMOUR:
		ids[slot] = catalog.race_piece(race, cls, slot)
	if cls == "sword_shield":
		ids["offhand"] = catalog.race_shield(race)
	return ids


static func _path(tex: Texture2D) -> String:
	return tex.resource_path if tex != null else "<null>"


func run(ctx) -> void:
	var rules = preload("res://logic/item_rules_loader.gd").load_default()
	_matrix(ctx, rules)
	await _call_sites(ctx, ctx, rules)


# ------------------------------------------------------------------ 1. icons and looks, every race x class x slot x level
func _matrix(ctx, rules) -> void:
	var catalog = rules.catalog
	for race in RACES:
		for cls in CLASSES:
			var ids := _ids(catalog, race, cls)
			var icon_bad: Array = []
			var starter := _Loadout.new()
			var lv15 := _Loadout.new()
			for slot in ids:
				var id := str(ids[slot])
				if id.is_empty():
					icon_bad.append("%s: no catalog piece" % slot)
					continue
				var s = _piece(rules, "starter-kit-v3-%s-%s" % [cls, slot], slot, id)
				var l = _piece(rules, "drop-%s-%s-%s" % [race, cls, slot], slot, id)
				starter.items[slot] = s
				lv15.items[slot] = l
				var si := ItemAssets.icon(s, catalog, race)
				var li := ItemAssets.icon(l, catalog, race)
				var race_mark := ("icon-%s_" % race) if slot in ARMOUR else ("race_%s/" % race)
				if si == null or li == null:
					icon_bad.append("%s: null icon (L1 %s, L15 %s)" % [slot, _path(si), _path(li)])
				elif si.resource_path == li.resource_path:
					icon_bad.append("%s: L1 and L15 share %s" % [slot, si.resource_path])
				elif si.resource_path.contains("_lv15") or not li.resource_path.contains("_lv15"):
					icon_bad.append("%s: wrong level file (L1 %s, L15 %s)" % [slot, si.resource_path, li.resource_path])
				elif not si.resource_path.contains(race_mark) or not li.resource_path.contains(race_mark):
					icon_bad.append("%s: not the %s icon (L1 %s, L15 %s)" % [slot, race, si.resource_path, li.resource_path])
			ctx.check("item look %s %s: icons resolve, L1 != L15, both of the card's race %s" % [race, cls, icon_bad], icon_bad.is_empty())
			var style := str(catalog.entry(str(ids["weapon"])).get("weapon_type", ""))
			var a: Dictionary = ItemAssets.looks(starter, catalog, style, race)
			var b: Dictionary = ItemAssets.looks(lv15, catalog, style, race)
			var look_bad: Array = []
			for slot in ARMOUR:
				if a[slot] != SHARED + "%s_%s.glb" % [race, slot]:
					look_bad.append("L1 %s=%s" % [slot, a[slot]])
				if b[slot] != SHARED + "%s_%s_lv15.glb" % [race, slot]:
					look_bad.append("L15 %s=%s" % [slot, b[slot]])
			if a["weapon"]["path"] != "res://art/weapons/race_%s/%s.glb" % [race, cls]:
				look_bad.append("L1 weapon=%s" % a["weapon"]["path"])
			if b["weapon"]["path"] != "res://art/weapons/race_%s/%s_lv15.glb" % [race, cls]:
				look_bad.append("L15 weapon=%s" % b["weapon"]["path"])
			if cls == "sword_shield":
				if a["offhand"].get("path", "") != "res://art/weapons/race_%s/shield.glb" % race:
					look_bad.append("L1 offhand=%s" % a["offhand"].get("path", ""))
				if b["offhand"].get("path", "") != "res://art/weapons/race_%s/shield_lv15.glb" % race:
					look_bad.append("L15 offhand=%s" % b["offhand"].get("path", ""))
			ctx.check("item look %s %s: looks() gives the starter files at L1 and the _lv15 files at L15 %s" % [race, cls, look_bad], look_bad.is_empty())
			# equipping one different piece changes the looks (only that slot)
			var changed := true
			for slot in ids:
				var mixed := _Loadout.new()
				mixed.items = starter.items.duplicate()
				mixed.items[slot] = lv15.items[slot]
				var m: Dictionary = ItemAssets.looks(mixed, catalog, style, race)
				var key: String = slot
				var before = a[key]["path"] if key in ["weapon", "offhand"] else a[key]
				var after = m[key]["path"] if key in ["weapon", "offhand"] else m[key]
				changed = changed and m != a and before != after
			ctx.check("item look %s %s: equipping a different piece in any slot changes the looks" % [race, cls], changed)


# ------------------------------------------------------------------ 2. the UI call sites
func _call_sites(ctx, tree: SceneTree, rules) -> void:
	var catalog = rules.catalog
	var gs = tree.root.get_node("GameState")
	var saved_profile = gs.profile
	gs.ensure_profile()
	var f := F.make()
	var p = f.profile
	# The lead card (Sword & Shield) is an ELF here: a site that forgets the race shows the default (human) look.
	Deck.set_race(p.card_deck, "sword_shield", "elf")
	for card in CLASSES:
		p.card_deck["cards"][card][preload("res://logic/card_progress.gd").PROGRESS] = {"level": 15, "xp": 0}
	gs.profile = p
	var lead_race := Deck.gear_race(p.card_deck, p.lead_card())
	ctx.check("call sites: the lead card is an elf for these checks", lead_race == "elf")
	var shirt15 = _piece(rules, "drop-site-shirt", "shirt", "armour_sword_shield_shirt")
	var shirt1 = p.loadout.item_at("shirt", 0)
	ctx.check("call sites: the lead card starts in a starter shirt", shirt1 != null and str(shirt1.id).begins_with("starter-"))

	# helper every fixed site uses
	ctx.check("call sites: ItemAssets.card_race() is the lead card's gear race (elf), or a named card's race",
		ItemAssets.card_race(p) == "elf" and ItemAssets.card_race(p, "greatsword") == Deck.gear_race(p.card_deck, "greatsword") and ItemAssets.card_race(null).is_empty())

	# hub_item_cell: the reference (an explicit race wins over the lead card's)
	var cell = preload("res://client/hub_item_cell.gd").new()
	tree.root.add_child(cell)  # (it reads /root/GameState for the lead card)
	cell.setup()
	cell.show_item(shirt15, rules, "")
	ctx.check("hub_item_cell: no card set -> the lead card's race (%s)" % _path(cell.icon_tex), cell.icon_tex == ItemAssets.icon(shirt15, catalog, "elf"))
	cell.card_race = "runeborn"
	cell.show_item(shirt15, rules, "")
	ctx.check("hub_item_cell: card_race set -> that card's race (%s)" % _path(cell.icon_tex), cell.icon_tex == ItemAssets.icon(shirt15, catalog, "runeborn"))
	cell.free()

	# gear_panel.gd (camp / bag screen, the lead card): slot icons and the paper doll
	var gp = preload("res://client/gear_panel.gd").new()
	gp.size = Vector2(1280, 720)
	tree.root.add_child(gp)
	gp.setup(p, null, gs.item_rules, f.camp, f.combat, null)
	await tree.process_frame
	var slot_icon_ok := true
	var report: Array = []
	for key in gp.slot_cells:
		var c = gp.slot_cells[key]
		var item = p.loadout.item_at(c.slot_id, c.slot_index)
		if item == null:
			continue
		var want := ItemAssets.icon(item, catalog, "elf")
		if c.icon_texture != want:
			slot_icon_ok = false
			report.append("%s %s!=%s" % [key, _path(c.icon_texture), _path(want)])
	ctx.check("gear_panel: worn slot icons use the lead card's race like hub_item_cell %s" % [report], slot_icon_ok)
	var doll_armor: Dictionary = gp.doll.model._armor_wanted if gp.doll != null and gp.doll.model != null else {}
	ctx.check("paper_doll (gear_panel): the doll wears the elf starter shirt (%s)" % doll_armor.get("shirt", ""), doll_armor.get("shirt", "") == SHARED + "elf_shirt.glb")
	gp.queue_free()

	# hub_shop_panel.gd: an item offer tile's icon (the bought piece is not a starter piece)
	var screen := Control.new()
	screen.size = Vector2(1280, 720)
	tree.root.add_child(screen)
	var shop = load("res://client/hub_shop_panel.gd").new()
	screen.add_child(shop)
	shop.size = Vector2(1280, 720)
	await tree.process_frame
	var tile: Button = shop._offer_tile({"sku": "item:armour_sword_shield_shirt", "id": "armour_sword_shield_shirt", "kind": "item", "name": "Shirt", "price": 1, "slot": "shirt"}, p)
	var tile_icon: Texture2D = null
	for child in tile.get_children():
		if child is TextureRect and (child as TextureRect).texture != null:
			tile_icon = (child as TextureRect).texture
			break
	ctx.check("hub_shop_panel: an offer tile shows the same icon as hub_item_cell for the lead card (%s)" % _path(tile_icon), tile_icon == ItemAssets.icon(shirt15, catalog, "elf"))
	tile.free()
	screen.queue_free()

	# card_character_screen.gd (card screen): slot icons of the VIEWED card, and the portrait after equipping
	var hub = load("res://client/card_deck_screen.gd").new()
	hub.auto_wire = false
	hub.size = Vector2(1920, 1080)
	tree.root.add_child(hub)
	hub.show_deck(p.card_deck, ItemAssets.cosmetics())
	await tree.process_frame
	for card in CLASSES:
		hub.open_character(card)
		await tree.process_frame
		var ch = hub._character
		var race := Deck.gear_race(p.card_deck, card)
		var bad: Array = []
		for key in ch._slots:
			var c = ch._slots[key]
			var item = p.loadout_of(card).item_at(c.slot_id, c.index)
			if item != null and c.icon_tex != ItemAssets.icon(item, catalog, race):
				bad.append("%s %s" % [key, _path(c.icon_tex)])
		ctx.check("card_character_screen %s (%s): paper-doll slot icons are of the viewed card's race %s" % [card, race, bad], bad.is_empty())
		ch.close()
		hub._mode = "deck"
	# equip level-15 pieces on the Great Sword card (viking): the portrait must change at once
	var card := "greatsword"
	var race := Deck.gear_race(p.card_deck, card)
	hub.open_character(card)
	await tree.process_frame
	var ch = hub._character
	var model = ch._portrait.model
	ctx.check("card portrait %s: starts in the %s starter shirt (%s)" % [card, race, model._armor_wanted.get("shirt", "") if model != null else "no model"],
		model != null and model._armor_wanted.get("shirt", "") == SHARED + "%s_shirt.glb" % race)
	var gs_shirt = _piece(rules, "drop-gs-shirt", "shirt", "armour_greatsword_shirt")
	var gs_weapon = _piece(rules, "drop-gs-weapon", "weapon", "race_%s_greatsword_weapon" % race)
	p.stash.items.append(gs_shirt)
	p.stash.items.append(gs_weapon)
	ch.refresh()
	var stash_cell_ok := false
	for c in ch._store_cells:
		if c.item == gs_shirt:
			stash_cell_ok = c.icon_tex == ItemAssets.icon(gs_shirt, catalog, race)
	ctx.check("card_character_screen storage: a L15 shirt shows the viewed card's (%s) L15 icon" % race, stash_cell_ok)
	await ch._equip(gs_shirt.id, "shirt")
	await ch._equip(gs_weapon.id, "weapon")
	await tree.process_frame
	ctx.check("card portrait %s: equip succeeded (shirt + weapon worn)" % card, p.loadout_of(card).item_at("shirt", 0) == gs_shirt and p.loadout_of(card).item_at("weapon", 0) == gs_weapon)
	ctx.check("card portrait %s: after equipping, the portrait wears the %s L15 shirt (%s)" % [card, race, model._armor_wanted.get("shirt", "")],
		model._armor_wanted.get("shirt", "") == SHARED + "%s_shirt_lv15.glb" % race)
	ctx.check("card portrait %s: after equipping, the portrait holds the L15 weapon (%s)" % [card, model._race_weapon_wanted],
		model._race_weapon_wanted == "res://art/weapons/race_%s/greatsword_lv15.glb" % race)
	hub.queue_free()
	await tree.process_frame

	# stage_view.gd loot popups / battle looks need a running stage: not built here.
	# The loot popups and stage looks now go through ItemAssets.card_race (checked above); the plaza payload carries no card deck.
	gs.profile = saved_profile
