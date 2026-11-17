extends RefCounted
## World map joined to the start flow (Boss 2026-11-17): the zone picked on the map is the zone FIGHT starts.
## Logic helper start_journey_for (OPEN zones only, goblin default), the map's Go sets the pick, the stage strip
## over FIGHT follows it, a locked / coming-soon zone cannot be chosen.
const Zones := preload("res://logic/world_zones.gd")
const Profile := preload("res://logic/profile.gd")
const F := preload("res://tests/online_fixture.gd")
const Deck := preload("res://logic/card_deck.gd")
const CardTokens := preload("res://client/card_tokens.gd")

const FAKE := {"zones": [
	{"id": "goblin_base", "order": 1, "journey": "goblin_waves", "name_th": "ก", "name_en": "Goblin Base", "boss_th": "ก", "boss_en": "Chief", "pos": [0.2, 0.6]},
	{"id": "zone_two", "order": 2, "journey": "mummy_waves", "name_th": "พ", "name_en": "Sand Pyramid", "boss_th": "ม", "boss_en": "Pharaoh", "pos": [0.5, 0.5]},
	{"id": "orc", "order": 3, "journey": "", "name_th": "อ", "name_en": "Orc Camp", "boss_th": "อ", "boss_en": "Warlord", "pos": [0.4, 0.3]},
]}


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

	# UI: the map's Go sets the pick; the strip updates; a locked zone cannot be chosen
	if not GameState.ensure_profile():
		ctx.check("GameState profile available", false)
		return
	var old_zone: String = GameState.selected_zone
	GameState.selected_zone = ""
	var root := Control.new()
	root.size = Vector2(1280, 720)
	tree.root.add_child(root)
	var hub = load("res://client/card_deck_screen.gd").new()
	hub.auto_wire = false
	hub.size = Vector2(1280, 720)
	root.add_child(hub)
	var deck := Deck.initial()
	for id in deck["cards"]:
		deck["cards"][id]["race"] = "human"
	deck["squad"] = ["sword_shield", "greatsword", "longbow"]
	hub.show_deck(deck, null)
	await tree.process_frame
	Zones._cache = FAKE
	GameState.profile.unlocks["boss_goblin_base"] = true
	hub.open_world_map()
	await tree.process_frame
	var map = hub._panels["map"]
	ctx.check("map opens on the furthest open zone", map.selected == "zone_two")
	map.select_zone("orc")
	ctx.check("a coming-soon zone cannot be chosen", not map.choose_selected() and GameState.selected_zone.is_empty())
	map.select_zone("goblin_base")
	map._go.pressed.emit()
	await tree.process_frame
	ctx.check("Go sets the zone and closes", GameState.selected_zone == "goblin_base" and not map.visible)
	ctx.check("FIGHT journey follows the pick (goblin)", GameState.fight_journey() == "goblin_waves")
	var goblin_text: String = hub._stage_label.text
	ctx.check("strip shows the goblin journey name %s" % goblin_text, goblin_text == CardTokens.stage_name("goblin_waves") and not goblin_text.is_empty())
	hub.open_world_map()
	await tree.process_frame
	map.select_zone("zone_two")
	map._go.pressed.emit()
	await tree.process_frame
	ctx.check("picking the pyramid makes FIGHT start mummy_waves", GameState.fight_journey() == "mummy_waves")
	ctx.check("strip label follows the pick", hub._stage_label.text == CardTokens.stage_name("mummy_waves") and hub._stage_label.text != goblin_text)
	# a pick that is no longer open (profile reset) falls back to goblin
	GameState.profile.unlocks.erase("boss_goblin_base")
	ctx.check("a stale pick that is locked again falls back to goblin", GameState.fight_journey() == "goblin_waves")
	Zones._cache = saved
	GameState.selected_zone = old_zone
	root.queue_free()
	await tree.process_frame
