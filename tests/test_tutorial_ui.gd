extends RefCounted
## New-player tutorial client (design/gdd/tutorial.md 7): acceptance 7 (every step target resolves to a visible node
## in the hub, character, picker or battle scene, headless) and 8 (an overlay tap outside the cut-out is blocked,
## a tap inside reaches the button underneath). Plus the overlay fallback, done_on matching and the locked visuals.
const Tutorial := preload("res://logic/tutorial.gd")
const Overlay := preload("res://client/tutorial_overlay.gd")
const Driver := preload("res://client/tutorial_driver.gd")
const Deck := preload("res://logic/card_deck.gd")


func run(ctx) -> void:
	var tree: SceneTree = ctx
	var root := Control.new()
	root.size = Vector2(1920, 1080)
	tree.root.add_child(root)
	await _overlay_taps(ctx, tree, root)
	await _targets(ctx, tree, root)
	_matching(ctx)
	root.queue_free()
	await tree.process_frame


## AC 8: tap outside = blocked + pulse, tap inside = the button gets it.
func _overlay_taps(ctx, tree: SceneTree, root: Control) -> void:
	# a SubViewport: input coordinates 1:1 with its controls (the test window itself is stretched)
	var vp := SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	vp.handle_input_locally = true
	vp.gui_disable_input = false
	root.add_child(vp)
	var host := Control.new()
	host.size = Vector2(1920, 1080)
	vp.add_child(host)
	var button := Button.new()
	button.position = Vector2(800, 500)
	button.size = Vector2(200, 80)
	host.add_child(button)
	var outside_button := Button.new()
	outside_button.position = Vector2(100, 100)
	outside_button.size = Vector2(200, 80)
	host.add_child(outside_button)
	var hits := {"in": 0, "out": 0, "blocked": 0}
	button.pressed.connect(func() -> void: hits["in"] += 1)
	outside_button.pressed.connect(func() -> void: hits["out"] += 1)
	await tree.process_frame
	# Arrange check: without the overlay the click harness reaches both buttons (so the asserts below mean something)
	_click(vp, Vector2(200, 140))
	_click(vp, Vector2(900, 540))
	await tree.process_frame
	ctx.check("AC8 harness: clicks reach both buttons without an overlay", hits["out"] == 1 and hits["in"] == 1)
	hits["in"] = 0
	hits["out"] = 0
	var overlay := Overlay.new()
	host.add_child(overlay)
	overlay.size = Vector2(1920, 1080)
	overlay.show_step("test", false)
	overlay.set_hole(button.get_global_rect())
	overlay.blocked_tap.connect(func() -> void: hits["blocked"] += 1)
	await tree.process_frame
	ctx.check("AC8 the cut-out is the target rect + 8 px", overlay.hole == button.get_global_rect().grow(8.0))
	_click(vp, Vector2(200, 140))
	await tree.process_frame
	ctx.check("AC8 a tap outside the cut-out does not reach the button under it", hits["out"] == 0)
	ctx.check("AC8 a tap outside pulses the cut-out", hits["blocked"] >= 1 and overlay._pulse > 0.0)
	_click(vp, Vector2(900, 540))
	await tree.process_frame
	ctx.check("AC8 a tap inside the cut-out reaches the button", hits["in"] == 1)
	overlay.set_hole(Rect2())
	ctx.check("text mode (no target) blocks the whole screen", overlay._has_point(Vector2(900, 540)))
	vp.queue_free()
	await tree.process_frame


func _click(vp: Viewport, at: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		vp.push_input(e, true)


## AC 7: every step's target (and the lost-tip FightButton) resolves in a real headless scene.
func _targets(ctx, tree: SceneTree, root: Control) -> void:
	var hub = load("res://client/card_deck_screen.gd").new()
	hub.auto_wire = false
	hub.size = Vector2(1920, 1080)
	root.add_child(hub)
	var deck := Deck.initial()
	for id in ["sword_shield", "greatsword", "longbow", "magic"]:
		deck["cards"][id]["race"] = "human"
	hub.show_deck(deck, null)
	await tree.process_frame
	var screens := {}
	screens["hub"] = hub
	hub.open_character("sword_shield")
	await tree.process_frame
	screens["character"] = hub._character
	var picker = hub._character._race_picker
	picker.size = Vector2(1920, 1080)
	picker.open("sword_shield", deck)
	await tree.process_frame
	screens["race_picker"] = picker
	var panel := preload("res://client/squad_panel.gd").new()
	root.add_child(panel)
	await tree.process_frame
	screens["battle"] = panel
	var missing: Array = []
	for step in Tutorial.steps():
		var target := str(step.get("target", ""))
		if target.is_empty():
			continue
		var scope: Node = screens.get(str(step["screen"]))
		var found: Node = scope.find_child(target, true, false) if scope != null else null
		if found == null:
			missing.append("%s:%s" % [step["id"], target])
	ctx.check("AC7 every step target resolves to a node (missing: %s)" % [missing], missing.is_empty())
	ctx.check("AC7 the picker target resolves visible", Driver.find_target(picker, "Race_human") != null)
	ctx.check("AC7 the character RaceButton resolves visible", Driver.find_target(hub._character, "RaceButton") != null)
	picker.close()
	hub._character.close()
	await tree.process_frame
	ctx.check("AC7 the hub card resolves visible", Driver.find_target(hub, "Card_sword_shield") != null)
	ctx.check("AC7 FightButton resolves visible", Driver.find_target(hub, "FightButton") != null)
	# locked visuals (tutorial.md 5)
	hub.locked_classes = ["magic"]
	hub.show_deck(deck, null)
	await tree.process_frame
	var magic: Control = hub.find_child("Card_magic", true, false)
	ctx.check("locked Magic card shows the padlock medallion", magic != null and magic.find_child("LockMark", true, false) != null)
	ctx.check("locked Magic card shows the wave-12 label", magic != null and str(magic._name.text) == Overlay.word("locked_wave"))
	var raceless := Deck.initial()
	hub.locked_classes = ["magic"]
	hub.show_deck(raceless, null)
	await tree.process_frame
	var ss: Control = hub.find_child("Card_sword_shield", true, false)
	ctx.check("a raceless card shows the '?' medallion", ss != null and ss.find_child("RacelessMark", true, false) != null)
	ctx.check("FIGHT disabled while fewer than 3 cards have a race", hub._fight.disabled)
	hub._toggle_squad("sword_shield")
	ctx.check("a raceless card cannot join the squad", hub._squad().is_empty())
	picker.locked_races = ["runeborn"]
	picker.open("sword_shield", deck)
	var chosen := []
	picker.race_chosen.connect(func(r) -> void: chosen.append(r))
	picker._on_tile("runeborn")
	ctx.check("a locked Runeborn tile chooses nothing", chosen.is_empty())
	ctx.check("a locked Runeborn tile shows the padlock", picker.find_child("Race_runeborn", true, false).find_child("LockMark", true, false) != null)
	panel.queue_free()
	hub.queue_free()
	await tree.process_frame


func _matching(ctx) -> void:
	ctx.check("done_on matches event + params", Driver.matches({"event": "card_race_ok", "class": "longbow", "race": "elf"}, {"event": "card_race_ok", "class": "longbow", "race": "elf"}))
	ctx.check("done_on refuses a wrong param", not Driver.matches({"event": "card_race_ok", "class": "longbow", "race": "elf"}, {"event": "card_race_ok", "class": "longbow", "race": "human"}))
	ctx.check("FIGHT counts for battle_loaded", Driver.matches({"event": "battle_loaded"}, {"event": "fight_pressed"}))
	ctx.check("timeout_s is not a param", Driver.matches({"event": "card_name_tap", "timeout_s": 8}, {"event": "card_name_tap"}))
