extends RefCounted
## Hub quest tracker (Boss 2026-11-18, client/hub_quest_tracker.gd): the next zone's unlock quest on the hub. Content
## from data/world/zone_quests.json (th + en, live progress), shown only after the tutorial while a zone with a quest
## is LOCKED, updated with the profile (card level, boss flag), placed clear of the tray / FIGHT / stage strip at
## 1280x720 and the 844x390 phone canvas, and a tap opens the world map on the quest's zone.
const Tracker := preload("res://client/hub_quest_tracker.gd")
const Zones := preload("res://logic/world_zones.gd")
const ZoneQuests := preload("res://logic/zone_quests.gd")
const Profile := preload("res://logic/profile.gd")
const F := preload("res://tests/online_fixture.gd")
const Deck := preload("res://logic/card_deck.gd")
const CardTokens := preload("res://client/card_tokens.gd")


func _levels(p, lv: int) -> void:
	for id in p.card_deck["cards"]:
		p.card_deck["cards"][id]["progress"] = {"level": lv, "xp": 0}


func run(ctx) -> void:
	var tree: SceneTree = ctx
	var f := F.make()
	var lang := CardTokens.language
	# --- visibility rules (pure)
	var fresh = Profile.new_player(f.rules, f.camp, F.rng(3))
	ctx.check("tracker hidden while the tutorial runs", Tracker.tracked_zone(fresh) == "")
	ctx.check("tracker hidden without a profile", Tracker.tracked_zone(null) == "")
	var p = F.past_tutorial(Profile.new_player(f.rules, f.camp, F.rng(4)))
	_levels(p, 5)
	ctx.check("after the tutorial: the pyramid quest is tracked", Tracker.tracked_zone(p) == "pyramid")
	p.unlocks["boss_goblin_base"] = true
	ctx.check("half done: still tracked", Tracker.tracked_zone(p) == "pyramid")
	_levels(p, 15)
	ctx.check("quest done (zone OPEN): hidden", Zones.state(p, "pyramid") == Zones.OPEN and Tracker.tracked_zone(p) == "")
	# --- content th / en from the data
	_levels(p, 7)
	var q := ZoneQuests.quest("pyramid")
	CardTokens.language = "en"
	var en := Tracker.lines_for(p, "pyramid")
	ctx.check("en: title has the quest and zone names %s" % [en], en.size() == 3 and str(q.name_en) in str(en[0]) and "Sand Pyramid" in str(en[0]))
	ctx.check("en: boss step ticked %s" % en[1], str(en[1]).begins_with("[x] ") and "Goblin Chief" in str(en[1]))
	ctx.check("en: level step open with live progress %s" % en[2], str(en[2]).begins_with("[ ] ") and "Lv 7/15" in str(en[2]))
	CardTokens.language = "th"
	var th := Tracker.lines_for(p, "pyramid")
	ctx.check("th: title in Thai %s" % [th], th.size() == 3 and str(q.name_th) in str(th[0]) and "พีระมิดทราย" in str(th[0]))
	ctx.check("th: level step with progress", "7/15" in str(th[2]) and str(th[2]).begins_with("[ ] "))
	CardTokens.language = "en"
	# --- the hub: placement, live update, tap
	if not GameState.ensure_profile():
		ctx.check("GameState profile available", false)
		return
	var saved_profile = GameState.profile
	GameState.profile = p
	var old_zone: String = GameState.selected_zone
	GameState.selected_zone = ""
	for sz in [Vector2(1280, 720), Vector2(1558, 720)]:  # desktop; 844x390 landscape phone as the expanded canvas
		var root := Control.new()
		root.size = sz
		tree.root.add_child(root)
		var hub = load("res://client/card_deck_screen.gd").new()
		hub.auto_wire = false
		hub.tracker_reads_profile = true
		hub.size = sz
		root.add_child(hub)
		var deck := Deck.initial()
		for id in deck["cards"]:
			deck["cards"][id]["race"] = "human"
		deck["squad"] = ["sword_shield", "greatsword", "longbow"]
		hub.show_deck(deck, null)
		await tree.process_frame
		var t: Tracker = hub._quest_tracker
		var r: Rect2 = t.get_global_rect()
		ctx.check("%s: tracker shown for the pending quest" % sz, t.visible and t.zone_id == "pyramid")
		ctx.check("%s: tracker inside the screen %s" % [sz, r], Rect2(Vector2.ZERO, sz).encloses(r))
		for n in ["_bar", "_synergy", "_fight", "_stage_strip", "_map_button", "_hint_strip"]:
			var other: Rect2 = hub.get(n).get_global_rect()
			ctx.check("%s: tracker clear of %s" % [sz, n], not r.intersects(other))
		for entry in hub._menu:
			ctx.check("%s: tracker clear of the menu %s" % [sz, entry.service], not r.intersects(entry.get_global_rect()))
		var labels: Array = [t._title]
		labels.append_array(t._lines.filter(func(l): return l.visible))
		var inside := true
		for l in labels:
			if not Rect2(Vector2.ZERO, t.size).grow(1.0).encloses(Rect2(l.position, l.size)):
				inside = false
		ctx.check("%s: every quest line fits inside the tracker %s %s" % [sz, t.size, labels.map(func(l): return Rect2(l.position, l.size))], inside and labels.size() == 3)
		ctx.check("%s: level line reads Lv 7/15" % sz, "Lv 7/15" in str(t._lines[1].text))
		# live update: a card levels up, the profile syncs
		_levels(p, 9)
		hub.show_deck(deck, null)
		ctx.check("%s: level-up updates the line" % sz, "Lv 9/15" in str(t._lines[1].text))
		# quest done: the next sync hides it
		_levels(p, 15)
		hub.show_deck(deck, null)
		ctx.check("%s: quest done hides the tracker" % sz, not t.visible)
		_levels(p, 7)
		hub.show_deck(deck, null)
		ctx.check("%s: back to pending shows it again" % sz, t.visible)
		# tap: the world map on the quest's zone (locked: info + quest lines, no Go)
		t.pressed.emit()
		await tree.process_frame
		var map = hub._panels.get("map")
		ctx.check("%s: tap opens the map on the pyramid" % sz, map != null and map.visible and map.selected == "pyramid" and not map._go.visible and "Lv 7/15" in str(map._info.text))
		map.close()
		await tree.process_frame
		ctx.check("%s: closing the map keeps the hub pick unchanged" % sz, GameState.selected_zone == "")
		root.queue_free()
		await tree.process_frame
	# tutorial profile on the hub: hidden
	GameState.profile = fresh
	var root2 := Control.new()
	root2.size = Vector2(1280, 720)
	tree.root.add_child(root2)
	var hub2 = load("res://client/card_deck_screen.gd").new()
	hub2.auto_wire = false
	hub2.tracker_reads_profile = true
	hub2.size = Vector2(1280, 720)
	root2.add_child(hub2)
	hub2.show_deck(Deck.initial(), null)
	await tree.process_frame
	ctx.check("hub during the tutorial: no tracker", not hub2._quest_tracker.visible)
	root2.queue_free()
	await tree.process_frame
	GameState.profile = saved_profile
	GameState.selected_zone = old_zone
	CardTokens.language = lang
