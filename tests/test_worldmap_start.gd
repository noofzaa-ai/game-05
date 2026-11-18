extends RefCounted
## World map joined to the start flow. Boss 2026-11-17: the zone picked on the map is the zone the fight starts.
## Boss 2026-11-18: FIGHT always opens the world map and the zone's Go starts the fight (FIGHT never starts one by
## itself, X goes back to the hub); the tutorial's FIGHT step still starts directly (the spotlight only lets FIGHT
## through). Logic helper start_journey_for (OPEN zones only, goblin default), the map's Go sets the pick and starts,
## the stage strip over FIGHT follows the pick, a locked / coming-soon zone has no Go and cannot be chosen.
const Zones := preload("res://logic/world_zones.gd")
const Profile := preload("res://logic/profile.gd")
const F := preload("res://tests/online_fixture.gd")
const Deck := preload("res://logic/card_deck.gd")
const CardTokens := preload("res://client/card_tokens.gd")
const FightLoading := preload("res://client/fight_loading.gd")

const FAKE := {"zones": [
	{"id": "goblin_base", "order": 1, "journey": "goblin_waves", "name_th": "ก", "name_en": "Goblin Base", "boss_th": "ก", "boss_en": "Chief", "pos": [0.2, 0.6]},
	{"id": "zone_two", "order": 2, "journey": "mummy_waves", "name_th": "พ", "name_en": "Sand Pyramid", "boss_th": "ม", "boss_en": "Pharaoh", "pos": [0.5, 0.5]},
	{"id": "orc", "order": 3, "journey": "", "name_th": "อ", "name_en": "Orc Camp", "boss_th": "อ", "boss_en": "Warlord", "pos": [0.4, 0.3]},
]}

var _fights := 0


func run(ctx) -> void:
	var tree: SceneTree = ctx
	var f := F.make()
	var p = Profile.new_player(f.rules, f.camp, F.rng(7))
	ctx.check("new player: no pick and goblin pick start goblin_waves", Zones.start_journey_for(p, "") == "goblin_waves" and Zones.start_journey_for(p, "goblin_base") == "goblin_waves")
	ctx.check("unknown pick falls back to the first zone", Zones.start_journey_for(p, "nowhere") == "goblin_waves")
	var saved = Zones._cache
	Zones._cache = FAKE
	ctx.check("a locked zone cannot start", Zones.start_journey_for(p, "zone_two") == "")
	ctx.check("a coming-soon zone cannot start", Zones.start_journey_for(p, "orc") == "")
	p.unlocks["boss_goblin_base"] = true
	ctx.check("beating the goblin boss opens the pyramid journey", Zones.start_journey_for(p, "zone_two") == "mummy_waves")
	ctx.check("goblin stays startable", Zones.start_journey_for(p, "goblin_base") == "goblin_waves")
	ctx.check("orc (no journey) still cannot start", Zones.start_journey_for(p, "orc") == "")
	Zones._cache = saved

	# UI: FIGHT -> map -> Go
	if not GameState.ensure_profile():
		ctx.check("GameState profile available", false)
		return
	var old_zone: String = GameState.selected_zone
	GameState.selected_zone = ""
	var root := Control.new()
	root.size = Vector2(1280, 720)
	tree.root.add_child(root)
	var hub = load("res://client/card_deck_screen.gd").new()
	hub.auto_wire = false  # (fight_pressed is not wired to _start_fight: the test counts the start requests)
	hub.size = Vector2(1280, 720)
	root.add_child(hub)
	hub.fight_pressed.connect(func() -> void: _fights += 1)
	var deck := Deck.initial()
	for id in deck["cards"]:
		deck["cards"][id]["race"] = "human"
	deck["squad"] = ["sword_shield", "greatsword", "longbow"]
	hub.show_deck(deck, null)
	await tree.process_frame
	Zones._cache = FAKE
	GameState.profile.unlocks["boss_goblin_base"] = true
	ctx.check("FIGHT is enabled for a full squad", not hub._fight.disabled)
	hub._fight.pressed.emit()
	await tree.process_frame
	ctx.check("FIGHT opens the world map", hub._panels.has("map") and hub._panels["map"].visible)
	ctx.check("FIGHT alone starts no fight", _fights == 0)
	var map = hub._panels["map"]
	ctx.check("map opens on the furthest open zone (no pick yet)", map.selected == "zone_two")
	map.select_zone("orc")
	ctx.check("a coming-soon zone has no Go", not map._go.visible)
	ctx.check("a coming-soon zone cannot be chosen", not map.choose_selected() and GameState.selected_zone.is_empty())
	# X goes back to the hub without fighting
	map._close.pressed.emit()
	await tree.process_frame
	ctx.check("the map's X closes it without a fight", not map.visible and _fights == 0)
	hub._fight.pressed.emit()
	await tree.process_frame
	map.select_zone("goblin_base")
	ctx.check("an open zone has Go", map._go.visible)
	map._go.pressed.emit()
	await tree.process_frame
	ctx.check("Go sets the zone, closes the map and starts the fight once", GameState.selected_zone == "goblin_base" and not map.visible and _fights == 1)
	ctx.check("FIGHT journey follows the pick (goblin)", GameState.fight_journey() == "goblin_waves")
	var goblin_text: String = hub._stage_label.text
	ctx.check("strip shows the goblin journey name %s" % goblin_text, goblin_text == CardTokens.stage_name("goblin_waves") and not goblin_text.is_empty())
	# the map re-opens on the last picked zone
	hub._fight.pressed.emit()
	await tree.process_frame
	ctx.check("FIGHT re-opens the map on the last pick", map.visible and map.selected == "goblin_base")
	map.select_zone("zone_two")
	map._go.pressed.emit()
	await tree.process_frame
	ctx.check("picking the pyramid makes the fight start mummy_waves", GameState.fight_journey() == "mummy_waves" and _fights == 2)
	ctx.check("strip label follows the pick", hub._stage_label.text == CardTokens.stage_name("mummy_waves") and hub._stage_label.text != goblin_text)
	# the stage strip still opens the map (and only the map)
	hub._map_button.pressed.emit()
	await tree.process_frame
	ctx.check("the stage strip opens the map on the pick, no fight", map.visible and map.selected == "zone_two" and _fights == 2)
	ctx.check("the stage strip shows a tap chevron", hub._stage_chevron.visible and hub._stage_chevron.texture != null)
	map.close()
	# a locked zone: info, no Go
	GameState.profile.unlocks.erase("boss_goblin_base")
	hub.open_world_map("zone_two")
	await tree.process_frame
	ctx.check("a locked zone shows its info but no Go", map.visible and map.selected == "zone_two" and not map._go.visible and not map._info.text.is_empty())
	map.close()
	ctx.check("a stale pick that is locked again falls back to goblin", GameState.fight_journey() == "goblin_waves")
	# the start path keeps its busy guard: a second request while one is running opens nothing
	hub._busy = true
	await hub._start_fight()
	ctx.check("_start_fight refuses while busy (no loading overlay)", not FightLoading.is_open(tree))
	hub._busy = false
	# tutorial: FIGHT starts directly while the tutorial spotlights it (the overlay lets only FIGHT through)
	var fake_driver = _FakeDriver.new()
	fake_driver.step = "fight"
	hub.tutorial = fake_driver
	var before := _fights
	hub._fight.pressed.emit()
	await tree.process_frame
	ctx.check("tutorial fight step: FIGHT starts directly, no map", _fights == before + 1 and not map.visible)
	fake_driver.step = ""
	hub._fight.pressed.emit()
	await tree.process_frame
	ctx.check("after the tutorial: FIGHT opens the map again", _fights == before + 1 and map.visible)
	map.close()
	hub.tutorial = null
	fake_driver.free()
	# a squad FIGHT refuses: the map's Go refuses too (the map can be opened from the strip)
	hub._fight.disabled = true
	before = _fights
	hub.open_world_map("goblin_base")
	await tree.process_frame
	map._go.pressed.emit()
	await tree.process_frame
	ctx.check("Go with a squad FIGHT refuses starts nothing", _fights == before)
	Zones._cache = saved
	GameState.selected_zone = old_zone
	root.queue_free()
	await tree.process_frame


const _FakeDriver := preload("res://tests/fake_tutorial_driver.gd")
