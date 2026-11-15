extends SceneTree
## Promo video capture (Boss 2026-11-15): renders the real game windowed and saves every frame of a few shots as
## JPG, at a fixed 60 fps clock (run with --fixed-fps 60 so game time is exact however slow the saving is).
## tools/promo/compose.py then crops, captions and encodes the vertical 1080x1920 clips.
## Capture only: nothing here changes logic/, client/ or data/; the profile is a local throwaway (never saved).
##
##   godot --path . --fixed-fps 60 --script res://tools/promo/promo_capture.gd -- --style=on --promo=card
##   ... --promo=battle      (portrait battle: overview, zoom to a fighter's face, the boss wave)
##   ... --promo=hub         (landscape hub 2880x1620: squad picks + Alliance, character, skills, Tailor, FIGHT)
##   ... --promo=hairs       (probe: the Tailor portrait in every hair, one PNG each, to pick the clip's last look)
##   ... --promo=tailor      (landscape Tailor 2880x1620: hair, hair colour, eyes, makeup, hair taps; then the portrait card close-up)
##   ... --promo=stills_hub / stills_battle   (landscape PNG stills 2880x1620 for social posts: <run>/stills/*.png)
## ZORX_PROMO_FRAMES = output folder (default %TEMP%/zorx_promo_frames). Each run writes <run>/manifest.json.

const CardDeck := preload("res://logic/card_deck.gd")
const Options := preload("res://client/graphics_options.gd")
const ItemAssets := preload("res://client/item_assets.gd")
const RACES := {"sword_shield": "human", "greatsword": "viking", "longbow": "elf", "magic": "runeborn"}
const SQUAD := ["greatsword", "sword_shield", "longbow"]  ## three different races (the Alliance line); the hero card first = fighter 1, the one the zoom closes on
const HERO := "greatsword"  ## the hero card (its class idle keeps facing the camera; sword_shield idle turns its back)
const PROFILE_SEED := 7  ## the card looks (hair colours, eyes) come from this
const JOURNEY_SEED := 99
const JPG_QUALITY := 0.93

var _out := ""
var _run := ""
var _manifest := {"shots": {}}
var _shot := ""
var _shot_frames := 0
var _last_info := {}
var _touches: Array = []  ## [shot frame, x, y, state] state: 1 down, 0 move, -1 up


func _initialize() -> void:
	call_deferred("run")


func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
	return fallback


func run() -> void:
	seed(4242)
	_run = _arg("promo", "card")
	var base := OS.get_environment("ZORX_PROMO_FRAMES")
	if base.is_empty():
		base = OS.get_environment("TEMP").path_join("zorx_promo_frames")
	_out = base.path_join(_run)
	DirAccess.make_dir_recursive_absolute(_out)
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	var rng := RandomNumberGenerator.new()
	rng.seed = PROFILE_SEED
	gs.session.create_profile(rng, true)
	gs.profile = gs.session.profile
	# A returning player: tutorial finished, Magic / Runeborn unlocked (profile data only, the rules are untouched).
	gs.profile.tutorial = load("res://logic/profile.gd").done_tutorial()
	gs.profile.unlocks[load("res://logic/unlocks.gd").flag()] = true
	var deck: Dictionary = gs.profile.card_deck
	# The tutorial work in progress starts cards raceless: give every card its race (all four on screen).
	for id in RACES:
		CardDeck.set_race(deck, id, RACES[id])
	gs.profile.stash.gold = 2450
	# The hero card: a swept-back hair that shows the face, ears and race marks (race heads read at a glance).
	deck["cards"][HERO]["hair"] = "f"
	deck["cards"][HERO]["hair_color"] = "#c4693a"
	match _run:
		"card":
			await _card_run(gs)
		"battle":
			await _battle_run(gs)
		"hub":
			await _hub_run(gs)
		"hairs":
			await _hairs_run(gs)
		"tailor":
			await _tailor_run(gs)
		"stills_hub":
			await _stills_hub_run(gs)
		"stills_card":
			await _stills_card_run(gs)
		"stills_face":
			await _stills_face_run(gs)
		"stills_battle":
			await _stills_battle_run(gs)
	var f := FileAccess.open(_out.path_join("manifest.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(_manifest, " "))
	f.close()
	print("PROMO done ", _run, " -> ", _out)
	quit()


func _window(size: Vector2i) -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(size)
	root.size = size


# ------------------------------------------------------------------ frame capture
func _begin(shot: String, extra: Dictionary = {}) -> void:
	_shot = shot
	_shot_frames = 0
	_touches = []
	DirAccess.make_dir_recursive_absolute(_out.path_join(shot))
	var info := {"size": [root.size.x, root.size.y], "frames": 0, "events": {}}
	info.merge(extra)
	_manifest["shots"][shot] = info


## Draws one frame and saves it (the next game frame starts after this returns).
func _grab() -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(_out.path_join(_shot).path_join("%05d.jpg" % _shot_frames), JPG_QUALITY)
	_shot_frames += 1
	_manifest["shots"][_shot]["frames"] = _shot_frames


func _end() -> void:
	_manifest["shots"][_shot]["touches"] = _touches
	print("PROMO shot ", _shot, " frames=", _shot_frames)


func _mark(event: String) -> void:
	_manifest["shots"][_shot]["events"][event] = _shot_frames


func _rect(control: Control) -> Array:
	var r := control.get_global_rect()
	return [r.position.x, r.position.y, r.size.x, r.size.y]


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


## A real touch through Input (the game sees InputEventScreenTouch / ScreenDrag, plus the emulated mouse).
func _touch(at: Vector2, state: int) -> void:
	if state == 0:
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = at
		Input.parse_input_event(drag)
	else:
		var t := InputEventScreenTouch.new()
		t.index = 0
		t.position = at
		t.pressed = state == 1
		Input.parse_input_event(t)
	_touches.append([_shot_frames, at.x, at.y, state])


func _tap(at: Vector2) -> void:
	_touch(at, 1)
	await _grab()
	await _grab()
	_touch(at, -1)


# ------------------------------------------------------------------ card close-up (portrait)
func _hero_card(gs, class_id: String, width: float, centre_y: float) -> Array:
	var size := Vector2(root.size)
	var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
	screen.auto_wire = false
	root.add_child(screen)
	current_scene = screen
	screen.size = size
	screen.show_deck(gs.profile.card_deck, ItemAssets.cosmetics())
	screen._layout()
	await _wait(10)
	for child in screen._deck_layer.get_children():
		child.visible = false  # only the hub's painted sky and this one card
	if screen._online_button != null:
		screen._online_button.modulate.a = 0.0  # (the deck refresh sets it visible again)
		for c in screen._online_button.get_children():
			c.visible = false
	var online := root.get_node_or_null("Online")
	if online != null and online.get("_pill") != null:
		online.set_process(false)  # (the Offline status pill of the top bar)
		online._pill.visible = false
	var card: Control = screen._cards[class_id]
	card.reparent(screen)
	card.focus_mode = Control.FOCUS_NONE  # (a touch would show the keyboard focus ring)
	card.portrait.set_idle_variants(false)  # the class idle only: the face stays toward the camera
	card.layout(width, screen._s * width / 369.0, false)
	card.base_position = Vector2((size.x - width) * 0.5, centre_y - card.size.y * 0.5)
	card.position = card.base_position
	await _wait(4)
	_sharpen(card)
	await _wait(30)
	return [screen, card]


## The card portrait renders at most 440x620 px (CardTokens.PORTRAIT_MAX_PIXELS, a web budget). For a 1080-wide
## close-up the capture renders it at its on-screen size instead (sharper, same framing).
func _sharpen(card: Control) -> void:
	var portrait = card.portrait if card.get("portrait") != null else card.get("_portrait")
	var px: Vector2 = portrait.size * portrait.get_global_transform_with_canvas().get_scale()
	portrait.viewport.size = Vector2i(int(px.x), int(px.y))
	portrait._fit_camera()


func _card_run(gs) -> void:
	_window(Vector2i(1080, 1920))
	var made: Array = await _hero_card(gs, HERO, 760.0, 940.0)
	var screen: Control = made[0]
	var card: Control = made[1]
	var r: Rect2 = card.get_global_rect()
	# ---- tilt: three finger gestures (down, drag across, up), each with the sheen sweep
	_begin("tilt", {"card": _rect(card)})
	for i in 40:
		await _grab()
	var c := r.get_center()
	var gestures := [
		[c + Vector2(-0.10, -0.05) * r.size, c + Vector2(0.48, -0.30) * r.size, c + Vector2(-0.45, 0.25) * r.size],
		[c + Vector2(0.05, 0.30) * r.size, c + Vector2(-0.42, -0.42) * r.size, c + Vector2(0.45, 0.40) * r.size],
		[c + Vector2(0.30, 0.10) * r.size, c + Vector2(0.48, 0.45) * r.size, c + Vector2(-0.48, -0.45) * r.size],
	]
	for g in gestures:
		_mark("gesture_%d" % gestures.find(g))
		_touch(g[0], 1)
		await _grab()
		var path: Array = [g[0], g[1], g[2], g[0].lerp(c, 0.6)]
		for leg in 3:
			var steps := 26 if leg < 2 else 14
			for s in steps:
				var t := float(s + 1) / float(steps)
				t = t * t * (3.0 - 2.0 * t)
				_touch(path[leg].lerp(path[leg + 1], t), 0)
				await _grab()
		_touch(path[3], -1)
		for i in 34:
			await _grab()
	for i in 20:
		await _grab()
	_end()
	# ---- race switch: the same card, Human -> Viking -> Elf -> Runeborn, a slow sway (finger held, no marker)
	_begin("races", {"card": _rect(card)})
	var deck: Dictionary = gs.profile.card_deck
	var order := ["human", "viking", "elf", "runeborn"]
	CardDeck.set_race(deck, HERO, "human")
	screen.show_deck(deck, ItemAssets.cosmetics())
	_sharpen(card)
	await _wait(20)
	var per := 132  # frames per race
	var total := per * order.size() + 30
	for f in total:
		var k := f / per
		if f % per == 0 and k < order.size():
			_mark("race_" + order[k])
			if k > 0:
				CardDeck.set_race(deck, HERO, order[k])
				screen.show_deck(deck, ItemAssets.cosmetics())
				_sharpen(card)
		var t := float(f) / 60.0
		card._touch_down = true
		# a slow sway, and a quick flick at each switch (the sheen sweeps across as the new head appears)
		var since := float(f % per) / 60.0
		var flick := 1.0 - smoothstep(0.0, 0.7, since) if k > 0 and k < order.size() else 0.0
		card._pointer = Vector2(sin(t * 1.1) * 0.35 + flick * 0.9, cos(t * 0.9) * 0.25 - flick * 0.5).clamp(Vector2(-1, -1), Vector2(1, 1))
		await _grab()
	card._touch_down = false
	_end()


# ------------------------------------------------------------------ battle (portrait)
func _stage():
	var st = current_scene
	if st != null and st.get("_rig") != null:
		return st
	for n in root.find_children("*", "", true, false):  # (a journey may hold the stage under its own scene)
		if n.get("_rig") != null and n.get("_session") != null:
			return n
	return null


func _frame_camera() -> void:
	var st = _stage()
	if st != null and st._rig._camera != null:
		st._rig._camera.keep_aspect = Camera3D.KEEP_WIDTH  # portrait capture: keep the board's width in frame


func _battle_frame() -> void:
	_frame_camera()
	await _grab()


func _sim_info() -> Dictionary:
	var st = _stage()
	if st == null or st._session.get("_sim") == null:
		return {}
	var sim = st._session._sim
	var heroes := 0
	var enemies := 0
	for id in sim.fighters:
		if sim.fighters[id].is_alive():
			if sim.fighters[id].team == "enemy":
				enemies += 1
			else:
				heroes += 1
	var chief := -1
	for id in sim.fighters:
		if sim.fighters[id].is_alive() and str(sim.fighters[id].enemy_type).contains("chief"):
			chief = int(id)
	return {"heroes": heroes, "enemies": enemies, "wave": sim._waves_released + 1, "boss": maxi(int(st._boss_id), chief)}


func _battle_run(gs) -> void:
	_window(Vector2i(1080, 1920))
	Options._load_once()
	Options._values["render_scale"] = 1.0  # the full 1080x1920 (the ink pass is kept on by --style=on)
	Options.revision += 1
	CardDeck.set_squad(gs.profile.card_deck, SQUAD)
	gs.start_journey(gs.DEFAULT_JOURNEY, JOURNEY_SEED)
	var guard := 0
	while _stage() == null or not _stage()._scene_presented:
		await process_frame
		guard += 1
		if guard > 1200:
			push_error("PROMO stage never presented")
			return
	for i in 20:
		_frame_camera()
		await process_frame
	var rig = _stage()._rig
	# ---- overview, then a smooth zoom to the face of fighter 1 (the Sword & Shield card), then a slow orbit
	_begin("fight")
	for i in 150:
		await _battle_frame()
	_mark("zoom_start")
	var zoom_frames := 100
	for i in zoom_frames:
		rig._orbit(Vector2.ZERO, pow(0.88, 15.0 / float(zoom_frames)))
		await _battle_frame()
	_mark("zoomed")
	for i in 540:
		rig._orbit(Vector2(0.35, 0.0))
		await _battle_frame()
	_end()
	print("PROMO after fight ", _sim_info())
	# ---- fast-forward (no drawing) to the boss wave, back to the game's own auto framing
	rig.chosen = rig.ARENA_VIEW.duplicate(true)
	RenderingServer.render_loop_enabled = false
	var ff := 0
	while true:
		await process_frame
		ff += 1
		var info: Dictionary = _sim_info()
		if info.is_empty():
			print("PROMO ff lost stage at ", ff, " scene=", current_scene.name if current_scene != null else "none", " journey_over=", root.get_node("GameState").journey.is_over() if root.get_node("GameState").journey != null else "-", " last=", _last_info)
		if info.is_empty() or ff > 60 * 400:
			break
		if int(info["wave"]) >= 12 and int(info["boss"]) >= 0:
			break
		if int(info["heroes"]) == 0:
			break
		_last_info = info
		if ff % 600 == 0:
			print("PROMO ff ", ff / 60, " s ", info)
	RenderingServer.render_loop_enabled = true
	print("PROMO boss reached after ", ff / 60, " s ", _sim_info())
	_begin("boss", {"info": _sim_info()})
	var st = _stage()
	var boss_view = st._views.get(int(st._boss_id))
	for i in 60:
		await _battle_frame()
	_mark("zoom_start")
	for i in 90:
		if boss_view != null and is_instance_valid(boss_view):
			rig.target = boss_view  # the camera closes on the Goblin Chief (the stage re-aims it every physics tick)
		rig._orbit(Vector2.ZERO, pow(0.88, 11.0 / 90.0))
		await _battle_frame()
	_mark("zoomed")
	for i in 420:
		if boss_view != null and is_instance_valid(boss_view):
			rig.target = boss_view
		rig._orbit(Vector2(-0.3, 0.0))
		await _battle_frame()
	_end()
	print("PROMO after boss ", _sim_info())


# ------------------------------------------------------------------ the hub (landscape, cropped later)
func _hub_run(gs) -> void:
	var size := Vector2i(2880, 1620)  # exactly 1.5x the hub's 1920x1080 reference layout
	_window(size)
	var progress = load("res://logic/card_progress.gd")
	var need := 0
	for level in range(1, 17):
		need += progress.xp_req(level)
	progress.grant(gs.profile.card_deck, "sword_shield", need)  # a grown card for the skill tree shot
	gs.profile.card_deck["squad"] = []
	var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
	root.add_child(screen)  # auto_wire: the real hub wiring (squad commands, FIGHT)
	current_scene = screen
	screen.size = Vector2(size)
	await _wait(2)
	# ---- the hub, squad picks by touch on the cards' bottom plates, the Alliance line
	_begin("hub")
	var rects := {}
	for i in 50:
		await _grab()
	for id in SQUAD:
		var card: Control = screen._cards[id]
		rects[id] = _rect(card)
		_mark("tap_" + id)
		await _tap(card.squad_button.get_global_rect().get_center())
		for i in 46:
			await _grab()
	for i in 150:
		await _grab()
	for id in screen._cards:
		rects[id] = _rect(screen._cards[id])
	rects["synergy"] = _rect(screen._synergy)
	rects["tray"] = _rect(screen._bar)
	rects["fight"] = _rect(screen._fight)
	rects["menu"] = _rect(screen._menu[0])
	_manifest["shots"]["hub"]["rects"] = rects
	_end()
	# ---- the card's character screen: equipment, then the skill tree
	screen.open_character("sword_shield")
	var ch = screen._character
	await _wait(30)
	ch.select_slot("weapon:0")
	await _wait(10)
	_begin("character")
	for i in 150:
		await _grab()
	_end()
	ch.select_tab("skills")
	var tab = ch._skills
	var data = load("res://logic/skill_tree_data.gd").load_default()
	var class_nodes: Array = data.class_nodes("sword_shield")
	for n in class_nodes.filter(func(x): return int(x["tier"]) == 1).slice(0, 3):
		tab.learn(str(n["id"]))
	var fork: Array = class_nodes.filter(func(x): return int(x["tier"]) == 2)
	if not fork.is_empty():
		tab.select(str(fork[0]["id"]))
	await _wait(10)
	_begin("skills")
	for i in 150:
		await _grab()
	_end()
	ch.select_tab("equipment")
	ch.close()
	await _wait(10)
	screen.open_service("tailor")
	await _wait(30)
	_begin("tailor")
	for i in 140:
		await _grab()
	_end()
	screen._panels["tailor"].close()
	await _wait(10)
	# ---- FIGHT: the loading bar (the stage itself is captured by the battle run)
	_begin("fight", {"fight": _rect(screen._fight)})
	for i in 20:
		await _grab()
	_mark("tap")
	await _tap(screen._fight.get_global_rect().get_center())
	for i in 150:
		await _grab()
		if get_root().get_node_or_null("FightLoading") == null and i > 20:
			break
	_end()



# ------------------------------------------------------------------ Tailor (clip 5) and stills
const BIG := Vector2i(3840, 2160)  ## 2x the 1920x1080 reference layout (sharp Tailor face crops; stills downscaled to 1920x1080)


## The hub as the game shows it (real wiring), at the current window size.
func _open_hub(gs) -> Control:
	var screen: Control = load("res://scenes/card_deck_screen.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	screen.size = Vector2(root.size)
	await _wait(4)
	return screen


## The Tailor's option button whose label contains `name` (the chosen one starts with a check mark).
func _tailor_option(tailor, name: String) -> Button:
	for b in tailor._flow.find_children("*", "Button", true, false):
		if (b as Button).text.replace("\n", " ").contains(name):
			return b
	push_error("PROMO no Tailor option " + name)
	return null


func _tap_control(c: Control) -> void:
	if c == null:
		return
	await _tap(c.get_global_rect().get_center())


func _hold(frames: int) -> void:
	for i in frames:
		await _grab()


static func ease_t(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


## Probe: the Great Sword in each hair (the Tailor's own portrait), to find the long twin-bun style.
func _hairs_run(gs) -> void:
	_window(Vector2i(1920, 1080))
	var screen := await _open_hub(gs)
	screen.open_tailor(HERO)
	await _wait(30)
	var tailor = screen._panels["tailor"]
	var deck: Dictionary = gs.profile.card_deck
	for hair in CardDeck.hair_options(HERO):
		deck["cards"][HERO]["hair"] = str(hair)
		tailor.refresh()
		await _wait(30)
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		var r: Rect2 = tailor._window.get_global_rect()
		img.get_region(Rect2i(r)).save_png(_out.path_join("hair_%s.png" % hair))
		print("PROMO hair ", hair)


func _tailor_run(gs) -> void:
	_window(BIG)
	gs.profile.card_deck["squad"] = SQUAD.duplicate()
	var screen := await _open_hub(gs)
	await _wait(20)
	screen.open_service("tailor")  # (the squad's first card: the Great Sword)
	await _wait(40)
	var tailor = screen._panels["tailor"]
	_sharpen(tailor)
	await _wait(10)
	var final_hair := _arg("final_hair", "c")
	_begin("tailor", {"window": _rect(tailor._window)})
	_manifest["shots"]["tailor"]["flow"] = _rect(tailor._scroll)
	_manifest["shots"]["tailor"]["cats"] = _rect(tailor._cat_row)
	await _hold(40)
	# 1. hair style
	_mark("hair_style")
	await _tap_control(_tailor_option(tailor, "Hair A"))
	_sharpen(tailor)
	await _hold(70)
	# 2. hair colour: a drag round the colour wheel's hue ring (the character previews live), then Apply
	_mark("hair_color")
	var picker: ColorPicker = tailor._hair_picker
	var pr: Rect2 = picker.get_global_rect()
	var wheel_c := pr.position + Vector2(pr.size.x * 0.5, pr.size.x * 0.5)
	var radius := pr.size.x * 0.45
	_manifest["shots"]["tailor"]["wheel"] = [pr.position.x, pr.position.y, pr.size.x, pr.size.y]
	var a0 := 0.8
	var a1 := -0.45
	_touch(wheel_c + Vector2.from_angle(a0) * radius, 1)
	await _grab()
	for s in 40:
		var t := ease_t(float(s + 1) / 40.0)
		var ang := lerpf(a0, a1, t)
		_touch(wheel_c + Vector2.from_angle(ang) * radius, 0)
		var hue := fposmod(ang / TAU, 1.0)
		if s % 2 == 0:  # (the wheel's own colour_changed path: the character previews live)
			picker.color = Color.from_hsv(hue, 0.5, 0.95)
			picker.color_changed.emit(picker.color)
		await _grab()
	_touch(wheel_c + Vector2.from_angle(a1) * radius, -1)
	await _hold(16)
	print("PROMO picker colour ", picker.color.to_html(false))
	_mark("hair_apply")
	await _tap_control(_tailor_option(tailor, "Apply"))
	await _hold(50)
	# 3. eyes: an iris style (it brings its own colour)
	_mark("eyes_tab")
	await _tap_control(tailor._cats["eyes"])
	await _hold(24)
	_mark("eyes")
	await _tap_control(_tailor_option(tailor, "Solar Flame"))
	_sharpen(tailor)
	await _hold(70)
	# 4. eye makeup
	_mark("makeup_tab")
	await _tap_control(tailor._cats["makeup"])
	await _hold(24)
	_mark("makeup")
	var now := str(gs.profile.card_deck["cards"][HERO].get("makeup", "none"))
	await _tap_control(_tailor_option(tailor, "Anime Soft" if now != "anime_soft" else "Sharp Wing"))
	await _hold(70)
	# 5. back to the hair: the long twin-bun style last
	_mark("final_tab")
	await _tap_control(tailor._cats["hair"])
	await _hold(24)
	_mark("final_hair")
	await _tap_control(_tailor_option(tailor, "Hair " + final_hair.to_upper()))
	_sharpen(tailor)
	await _hold(120)
	_end()
	print("PROMO look ", CardDeck.look_of(gs.profile.card_deck, HERO))
	tailor.close()
	await _wait(10)
	screen.queue_free()
	await _wait(4)
	# ---- the card itself (the hub card, portrait close-up), wearing the new look
	_window(Vector2i(1080, 1920))
	var made: Array = await _hero_card(gs, HERO, 760.0, 940.0)
	var card: Control = made[1]
	_begin("card", {"card": _rect(card)})
	for f in 240:
		var t := float(f) / 60.0
		card._touch_down = true
		var flick := 1.0 - smoothstep(0.0, 0.8, t)
		card._pointer = Vector2(sin(t * 1.1) * 0.3 + flick * 0.9, cos(t * 0.9) * 0.2 - flick * 0.5).clamp(Vector2(-1, -1), Vector2(1, 1))
		await _grab()
	_end()


# ------------------------------------------------------------------ stills (landscape PNG)
func _still(name: String) -> void:
	await RenderingServer.frame_post_draw
	var dir := _out.path_join("stills")
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("PROMO still ", name)


func _stills_hub_run(gs) -> void:
	_window(BIG)
	var progress = load("res://logic/card_progress.gd")
	var need := 0
	for level in range(1, 17):
		need += progress.xp_req(level)
	progress.grant(gs.profile.card_deck, "sword_shield", need)
	gs.profile.card_deck["squad"] = SQUAD.duplicate()
	var screen := await _open_hub(gs)
	await _wait(30)
	_hide_pill()
	await _wait(60)
	await _still("01_hub")
	# 3. the character screen (gear)
	screen.open_character("sword_shield")
	var ch = screen._character
	await _wait(30)
	ch.select_slot("weapon:0")
	await _wait(40)
	await _still("03_character_gear")
	# 4. the skill tree
	ch.select_tab("skills")
	var tab = ch._skills
	var data = load("res://logic/skill_tree_data.gd").load_default()
	var class_nodes: Array = data.class_nodes("sword_shield")
	for n in class_nodes.filter(func(x): return int(x["tier"]) == 1).slice(0, 3):
		tab.learn(str(n["id"]))
	var fork: Array = class_nodes.filter(func(x): return int(x["tier"]) == 2)
	if not fork.is_empty():
		tab.select(str(fork[0]["id"]))
	await _wait(40)
	await _still("04_skill_tree")
	ch.select_tab("equipment")
	await _wait(10)
	# 6. the race picker
	ch.open_race_picker()
	await _wait(60)
	await _still("06_race_picker")
	ch._race_picker.visible = false
	await _wait(10)
	ch.close()
	await _wait(20)
	# 5. the Tailor
	screen.open_service("tailor")
	await _wait(60)
	await _still("05_tailor")
	screen._panels["tailor"].close()
	await _wait(20)
	# 10. the unlock ceremony, around the seal break (glow 0.8 s, then the crack 0.6 s)
	var driver = screen.tutorial
	if driver != null:
		gs.profile.tutorial["step"] = "unlock_ceremony"
		gs.profile.tutorial["unlock_seen"] = false
		driver.refresh()
		for f in 150:
			await process_frame
			if f in [50, 60, 68, 76, 84, 92, 140]:
				await _still("10_unlock_ceremony_f%03d" % f)
		if driver._ceremony != null:
			driver._ceremony.queue_free()
			driver._ceremony = null
		gs.profile.tutorial = load("res://logic/profile.gd").done_tutorial()
		driver.refresh()
	else:
		push_error("PROMO no tutorial driver")
	await _wait(30)
	# 2. one card close-up with the tilt sheen: the hub card, pointer held at an angle
	var card: Control = screen._cards[HERO]
	card._touch_down = true
	for k in 3:
		for i in 40:
			card._pointer = Vector2(0.75 - k * 0.35, -0.45 + k * 0.2)
			await process_frame
		await _still("02_card_tilt_%d" % k)
	card._touch_down = false
	_manifest["card_rect"] = _rect(card)
	await _wait(30)
	# 11. FIGHT: the loading screen
	screen._fight.emit_signal("pressed")
	for f in 40:
		await process_frame
		if f in [8, 11, 14, 17, 20]:
			await _still("11_fight_loading_f%02d" % f)


func _stills_battle_run(gs) -> void:
	_window(Vector2i(int(_arg("w", "1920")), int(_arg("h", "1080"))))  # (the battle HUD has fixed pixel sizes: capture at the post size)
	Options._load_once()
	Options._values["render_scale"] = 1.0
	Options.revision += 1
	CardDeck.set_squad(gs.profile.card_deck, SQUAD)
	gs.start_journey(gs.DEFAULT_JOURNEY, JOURNEY_SEED)
	var guard := 0
	while _stage() == null or not _stage()._scene_presented:
		await process_frame
		guard += 1
		if guard > 1200:
			push_error("PROMO stage never presented")
			return
	var rig = _stage()._rig
	var zoom := float(_arg("zoom", "8"))
	# 7. overview mid-wave: a few candidates
	for f in 360:
		await process_frame
		if f >= 150 and f % 40 == 0:
			await _still("07_battle_overview_f%03d" % f)
	# 8. close-up on a hero's face (gentler than the portrait clip: landscape shows more height)
	for i in 100:
		rig._orbit(Vector2.ZERO, pow(0.88, zoom / 100.0))
		await process_frame
	for f in 330:
		rig._orbit(Vector2(0.35, 0.0))
		await process_frame
		if f % 15 == 0:
			await _still("08_battle_closeup_f%03d" % f)
	# 9. fast-forward to the boss wave (Goblin Chief); the stage may reload between waves, so wait it out
	rig.chosen = rig.ARENA_VIEW.duplicate(true)
	RenderingServer.render_loop_enabled = false
	var ff := 0
	var lost := 0
	while ff < 60 * 400:
		await process_frame
		ff += 1
		var info: Dictionary = _sim_info()
		if info.is_empty():
			lost += 1
			if lost > 600:
				var jj = root.get_node("GameState").journey
				print("PROMO ff lost stage at ", ff, " scene=", current_scene.name if current_scene != null else "none", " last=", _last_info, " journey_state=", jj.state if jj != null else "-", " ", jj.to_dict() if jj != null and jj.has_method("to_dict") else "")
				break
			continue
		lost = 0
		_last_info = info
		if int(info["heroes"]) == 0:
			print("PROMO heroes down ", info)
			break
		if int(info["boss"]) >= 0:
			break
		if ff % 1200 == 0:
			print("PROMO ff ", ff / 60, " s ", info)
	RenderingServer.render_loop_enabled = true
	print("PROMO boss ", _sim_info())
	var st = _stage()
	if st == null:
		return
	rig = st._rig
	var boss_view = st._views.get(int(_sim_info().get("boss", -1)))
	for f in 420:
		if boss_view != null and is_instance_valid(boss_view) and f >= 60:
			rig.target = boss_view
			if f < 150:
				rig._orbit(Vector2.ZERO, pow(0.88, 7.0 / 90.0))
			else:
				rig._orbit(Vector2(-0.25, 0.0))
		await process_frame
		if f % 30 == 0:
			await _still("09_boss_f%03d" % f)


## The top bar's Offline status pill (a capture has no server): hidden in the stills.
func _hide_pill() -> void:
	var online := root.get_node_or_null("Online")
	if online != null and online.get("_pill") != null:
		online.set_process(false)
		online._pill.visible = false


## 2. one card close-up with the tilt sheen (landscape, the card over the hub's painted sky)
func _stills_card_run(gs) -> void:
	_window(BIG)
	var made: Array = await _hero_card(gs, HERO, 1180.0, 1080.0)
	var card: Control = made[1]
	_manifest["card_rect"] = _rect(card)
	card._touch_down = true
	var poses := [Vector2(0.8, -0.5), Vector2(0.5, -0.3), Vector2(-0.6, -0.4), Vector2(0.2, 0.5)]
	for k in poses.size():
		for i in 50:
			card._pointer = poses[k]
			await process_frame
		await _still("02_card_tilt_%d" % k)

## 8. a hero's face: the zoomed battle camera orbiting full circle (stills every 12 frames; pick one facing us)
func _stills_face_run(gs) -> void:
	_window(Vector2i(1920, 1080))
	Options._load_once()
	Options._values["render_scale"] = 1.0
	Options.revision += 1
	CardDeck.set_squad(gs.profile.card_deck, SQUAD)
	gs.start_journey(gs.DEFAULT_JOURNEY, JOURNEY_SEED)
	while _stage() == null or not _stage()._scene_presented:
		await process_frame
	var rig = _stage()._rig
	for f in 200:
		await process_frame
	var zoom := float(_arg("zoom", "13"))
	for i in 60:
		rig._orbit(Vector2.ZERO, pow(0.88, zoom / 60.0))
		await process_frame
	var speed := float(_arg("orbit", "1.5"))
	for f in 720:
		rig._orbit(Vector2(speed, 0.0))
		await process_frame
		if f % 12 == 0:
			await _still("08_face_f%03d" % f)