extends RefCounted
## Hub combo chip (Boss 2026-11-26): the small "13 combos" chip beside the squad medallions. It must overlap nothing
## (medallions, quest side panel, hint ribbon, Alliance line, FIGHT, menu), stay on screen and open the combo board.
const F := preload("res://tests/online_fixture.gd")
const Deck := preload("res://logic/card_deck.gd")
const Profile := preload("res://logic/profile.gd")
const CardTokens := preload("res://client/card_tokens.gd")


func run(ctx) -> void:
	var tree: SceneTree = ctx
	if not GameState.ensure_profile():
		ctx.check("GameState profile available", false)
		return
	var f := F.make()
	var saved = GameState.profile
	var p = F.past_tutorial(Profile.new_player(f.rules, f.camp, F.rng(4)))
	GameState.profile = p
	# 844x390 phone runs as the expanded 1558x720 canvas (see test_hub_quest_tracker)
	for sz in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(1366, 768), Vector2(1558, 720)]:
		var root := Control.new()
		root.size = sz
		tree.root.add_child(root)
		var hub = load("res://client/card_deck_screen.gd").new()
		hub.auto_wire = false
		hub.tracker_reads_profile = true
		hub.size = sz
		root.add_child(hub)
		var deck := Deck.initial()
		var races := ["human", "elf", "orc"]
		var i := 0
		for id in deck["cards"]:
			deck["cards"][id]["race"] = races[i % 3]
			i += 1
		deck["squad"] = ["sword_shield", "greatsword", "longbow"]
		hub.show_deck(deck, null)
		await tree.process_frame
		var chip: Button = hub._combo_pill
		var r := chip.get_global_rect()
		ctx.check("%s: combo chip visible with short text '%s'" % [sz, chip.text], chip.visible and chip.text.ends_with("combo") or chip.visible and chip.text.ends_with("combos"))
		ctx.check("%s: chip on screen %s" % [sz, r], Rect2(Vector2.ZERO, sz).encloses(r))
		ctx.check("%s: chip small (h<=60, w<=200 canvas units) %s" % [sz, r.size], r.size.y <= 60.0 * hub._s + 1.0 or hub._phone)
		for n in ["_bar", "_synergy", "_fight", "_hint_strip", "_stage_strip", "_quest_tracker"]:
			var c: Control = hub.get(n)
			if c != null and c.visible:
				ctx.check("%s: chip clear of %s %s %s" % [sz, n, r, c.get_global_rect()], not r.intersects(c.get_global_rect()))
		for slot in hub._slots:
			ctx.check("%s: chip clear of a medallion" % sz, not r.intersects(slot.get_global_rect()))
		for entry in hub._menu:
			ctx.check("%s: chip clear of menu %s" % [sz, entry.service], not r.intersects(entry.get_global_rect()))
		chip.pressed.emit()
		await tree.process_frame
		ctx.check("%s: chip opens the squad combo board" % sz, hub._squad_combos != null and hub._squad_combos.visible)
		root.queue_free()
		await tree.process_frame
	GameState.profile = saved
