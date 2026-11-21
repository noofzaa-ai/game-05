extends RefCounted
## Quests panel (Boss 2026-11-18, client/hub_quests_panel.gd): the side menu's Quests entry lists every zone unlock
## quest (data/world/zone_quests.json) with its description, steps + live progress, the zone it opens and its state;
## a done quest stays listed; a tap opens the world map on that zone; during the tutorial it stays "coming soon".
const QuestsPanel := preload("res://client/hub_quests_panel.gd")
const Profile := preload("res://logic/profile.gd")
const F := preload("res://tests/online_fixture.gd")
const Deck := preload("res://logic/card_deck.gd")
const CardTokens := preload("res://client/card_tokens.gd")
const ZoneQuests := preload("res://logic/zone_quests.gd")


func _levels(p, lv: int) -> void:
	for id in p.card_deck["cards"]:
		p.card_deck["cards"][id]["progress"] = {"level": lv, "xp": 0}


func _texts(row: Control) -> String:
	var out: Array = []
	for c in row.get_children():
		if c is Label and c.visible:
			out.append(c.text)
	return "\n".join(out)


func run(ctx) -> void:
	var tree: SceneTree = ctx
	var f := F.make()
	var lang := CardTokens.language
	var p = F.past_tutorial(Profile.new_player(f.rules, f.camp, F.rng(11)))
	_levels(p, 5)
	p.unlocks["boss_goblin_base"] = true
	var q := ZoneQuests.quest("pyramid")
	# pure lines
	CardTokens.language = "en"
	var en := QuestsPanel.row_lines(p, "pyramid")
	ctx.check("en: name, desc, opens, pending", en.name == str(q.name_en) and en.desc == str(q.desc_en) and "Sand Pyramid" in en.opens and en.state == "In progress" and not en.done)
	ctx.check("en: steps with ticks and live progress %s" % [en.steps], en.steps.size() == 2 and str(en.steps[0].text).begins_with("[x] ") and "Lv 5/15" in str(en.steps[1].text) and str(en.steps[1].text).begins_with("[ ] "))
	CardTokens.language = "th"
	var th := QuestsPanel.row_lines(p, "pyramid")
	ctx.check("th: Thai name, desc, opens", th.name == str(q.name_th) and th.desc == str(q.desc_th) and "พีระมิดทราย" in th.opens and th.state == "กำลังทำ")
	CardTokens.language = "en"
	_levels(p, 15)
	var done := QuestsPanel.row_lines(p, "pyramid")
	ctx.check("done quest: state Done, every step ticked", done.done and done.state == "Done" and done.steps.all(func(s): return str(s.text).begins_with("[x] ")))
	_levels(p, 5)
	# the hub: the menu entry opens the real panel
	if not GameState.ensure_profile():
		ctx.check("GameState profile", false)
		return
	var saved = GameState.profile
	GameState.profile = p
	for sz in [Vector2(1280, 720), Vector2(1558, 720)]:
		var root := Control.new()
		root.size = sz
		tree.root.add_child(root)
		var hub = load("res://client/card_deck_screen.gd").new()
		hub.auto_wire = false
		hub.tracker_reads_profile = true
		hub.size = sz
		root.add_child(hub)
		hub.show_deck(Deck.initial(), null)
		await tree.process_frame
		hub.open_service("quests")
		await tree.process_frame
		var panel = hub._panels.get("quests")
		ctx.check("%s: Quests opens the quests panel, not 'coming soon'" % sz, panel != null and panel.visible and not hub._service_layer.visible)
		var row: Control = panel.row_of("pyramid") if panel != null else null
		ctx.check("%s: the pyramid quest is listed" % sz, row != null and row.visible and row.size.y > 0.0)
		if row == null:
			root.queue_free()
			continue
		var text := _texts(row)
		ctx.check("%s: row shows name, desc, steps, opens %s" % [sz, text], str(q.name_en) in text and str(q.desc_en) in text and "Lv 5/15" in text and "Opens: Sand Pyramid" in text and "In progress" in text)
		var inside := true
		for c in row.get_children():
			if c is Control and c.visible and not Rect2(Vector2.ZERO, row.size).grow(1.0).encloses(Rect2(c.position, c.size)):
				inside = false
		ctx.check("%s: every line inside its row" % sz, inside)
		ctx.check("%s: the list fits inside the panel body" % sz, Rect2(Vector2.ZERO, panel.body.size).grow(1.0).encloses(Rect2(panel._scroll.position, panel._scroll.size)))
		# live: done stays listed
		_levels(p, 15)
		panel.refresh()
		ctx.check("%s: a done quest stays listed as Done" % sz, row.visible and "Done" in _texts(row))
		_levels(p, 5)
		panel.refresh()
		# tap: the map on that zone, the quests panel closes
		row.pressed.emit()
		await tree.process_frame
		var map = hub._panels.get("map")
		ctx.check("%s: tapping the quest opens the map on the pyramid" % sz, map != null and map.visible and map.selected == "pyramid" and not panel.visible)
		map.close()
		root.queue_free()
		await tree.process_frame
	await _pages(ctx, tree, f, p)
	# tutorial: still the "coming soon" panel
	GameState.profile = Profile.new_player(f.rules, f.camp, F.rng(12))
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
	hub2.open_service("quests")
	ctx.check("during the tutorial Quests keeps the 'coming soon' panel", hub2._service_layer.visible and not hub2._panels.has("quests"))
	root2.queue_free()
	await tree.process_frame
	# no quest data at all: the empty line
	var saved_q = ZoneQuests._cache
	ZoneQuests._cache = {"quests": {}}
	GameState.profile = p
	var root3 := Control.new()
	root3.size = Vector2(1280, 720)
	tree.root.add_child(root3)
	var panel3 = QuestsPanel.new()
	root3.add_child(panel3)
	panel3.open()
	await tree.process_frame
	ctx.check("no quests: the empty line shows", panel3._empty.visible and panel3._empty.text == CardTokens.t("quest_none") and panel3._rows.is_empty())
	ZoneQuests._cache = saved_q
	root3.queue_free()
	await tree.process_frame
	GameState.profile = saved
	CardTokens.language = lang


## Boss 2026-11-21: Main / Daily pages. Main = the chain (orc camp locked until the pyramid quest is done); Daily =
## progress, reward and a Claim that sends daily_claim (here through the real Commands.apply) and redraws.
func _pages(ctx, tree: SceneTree, f, p) -> void:
	var Daily = load("res://logic/daily_quests.gd")
	var Commands = load("res://logic/commands.gd")
	var now := 1795262400
	_levels(p, 5)
	p.daily = {}
	Daily.record_run(p, now, 9, true)
	for sz in [Vector2(1280, 720), Vector2(1558, 720)]:
		var root := Control.new()
		root.size = sz
		tree.root.add_child(root)
		var panel = QuestsPanel.new()
		panel.now_override = now
		panel.send = func(req: Dictionary) -> Dictionary: return Commands.apply({"now": now, "profile": p, "rules": f.rules, "camp": f.camp, "location": "camp"}, req, F.rng(2))
		root.add_child(panel)
		panel.size = sz
		panel.open()
		await tree.process_frame
		var orc: Control = panel.row_of("orc_camp")
		ctx.check("%s: main page lists the orc camp quest as locked after the pyramid one" % sz, orc != null and orc.visible and "Locked" in _texts(orc) and "Into the Sand" in _texts(orc) and panel.row_of("pyramid").position.y < orc.position.y)
		ctx.check("%s: tabs are tap-sized and inside the body" % sz, panel._tabs.size() == 2 and panel._tabs[0].size.y >= CardTokens.SVC_ROW_H * panel.s - 0.5 and Rect2(Vector2.ZERO, panel.body.size).encloses(panel._tabs[1].get_rect()))
		panel._tabs[1].pressed.emit()
		await tree.process_frame
		ctx.check("%s: the Daily tab shows the daily list, hides the main list" % sz, panel.page == "daily" and panel._daily_scroll.visible and not panel._scroll.visible and panel._reset.visible and "Resets in" in panel._reset.text)
		var boss: Control = panel.daily_row_of("daily_boss")
		var fights: Control = panel.daily_row_of("daily_fights")
		var claim: Button = boss.get_node("Claim")
		ctx.check("%s: boss daily done -> Claim enabled; fights 1/3 -> Not done" % sz, not claim.disabled and claim.text == "Claim" and fights.get_node("Claim").disabled and "1/3" in _texts(fights))
		var inside := true
		for row in [boss, fights]:
			for c in row.get_children():
				if c is Control and c.visible and not Rect2(Vector2.ZERO, row.size).grow(1.0).encloses(Rect2(c.position, c.size)):
					inside = false
		ctx.check("%s: daily lines and button inside their rows" % sz, inside)
		var gold: int = p.stash.gold
		claim.pressed.emit()
		await tree.process_frame
		await tree.process_frame
		ctx.check("%s: Claim pays the gold and the button turns to Claimed" % sz, p.stash.gold == gold + 500 and claim.disabled and claim.text == "Claimed")
		p.daily = {}
		Daily.record_run(p, now, 9, true)
		root.queue_free()
		await tree.process_frame
