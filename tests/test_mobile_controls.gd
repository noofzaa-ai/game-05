extends RefCounted
const Mobile := preload("res://client/mobile_controls.gd")
const SimInput := preload("res://logic/sim_input.gd")

func run(ctx) -> void:
	ctx.check("Retina canvas uses CSS-sized touch targets", is_equal_approx(Mobile.screen_units_for(720, 1170, 3), 720.0 / 390.0))
	ctx.check("portrait needs rotation", Mobile.needs_rotation(Vector2(720, 1280)))
	ctx.check("landscape permits play", not Mobile.needs_rotation(Vector2(1280, 720)))
	ctx.check("square does not gate unnecessarily", not Mobile.needs_rotation(Vector2(720, 720)))
	var mobile := Mobile.new()
	mobile._combat = true
	mobile.vector = Vector2(.4, -.7)
	mobile._held = {2: "guard", 3: "light"}
	mobile._running = true
	mobile._taps = {"light": true, "jump": true, "ultimate": true}
	var first := SimInput.new()
	mobile.merge(first)
	ctx.check("touch walking preserves direction", first.move == Vector2(.4, -.7))
	ctx.check("run and guard hold together", first.run and first.guard)
	# merge() converts a queued ultimate tap into skill_slot once skill_build is enabled (see
	# client/mobile_controls.gd), so .ultimate itself is no longer set at this layer.
	if preload("res://logic/skill_build.gd").enabled():
		ctx.check("simultaneous attack and ultimate", first.light and first.skill_slot == 1)
	else:
		ctx.check("simultaneous attack and ultimate", first.light and first.ultimate)
	var second := SimInput.new()
	mobile.merge(second)
	ctx.check("one-shot attacks not repeated while held", not second.light and not second.jump and not second.ultimate)
	ctx.check("hold actions survive ticks", second.run and second.guard)
	mobile.release()
	ctx.check("release clears every finger and queued tap", mobile.vector == Vector2.ZERO and mobile._held.is_empty() and mobile._taps.is_empty())
	var keyboard := SimInput.new()
	keyboard.move = Vector2.LEFT
	keyboard.light = true
	mobile.merge(keyboard)
	ctx.check("touch release preserves desktop input", keyboard.move == Vector2.LEFT and keyboard.light)
	mobile._combat = false
	mobile._taps = {"heavy": true}
	var menu := SimInput.new()
	mobile.merge(menu)
	ctx.check("menu never injects combat", not menu.heavy)
	mobile.free()
	# Exercise live lifecycle, resize and pause ownership without loading art.
	var tree = Engine.get_main_loop()
	var live := Mobile.new()
	live.force_mobile = true
	tree.root.add_child(live)
	ctx.check("touch overlay builds action regions", live._buttons.size() == 6)
	ctx.check("rotation gate sits above creator, menus and FPS", live._gate.get_parent() == live._gate_layer and live._gate_layer.layer > 100)
	var original_size: Vector2 = live._size
	var aligned := true
	for screen_size in [Vector2(844, 390), Vector2(1280, 720), Vector2(2160, 1080)]:
		live._size = screen_size
		live._layout()
		aligned = aligned and is_equal_approx(live._stick.size.x, screen_size.x * .45)
		live._back.show()
		var menus := Rect2(live._back.position, live._back.size)
		aligned = aligned and not live.movement_zone_contains(menus.get_center())
	ctx.check("floating zone covers left area and excludes menus", aligned)
	for phone in [Vector2(667, 375), Vector2(844, 390), Vector2(932, 430)]:
		live._size = phone
		live._layout()
		var fits := true
		var large := true
		for action in Mobile.ACTIONS:
			fits = fits and Rect2(Vector2.ZERO, phone).encloses(live._buttons[action])
			large = large and live._buttons[action].size.x / live._screen_unit() >= 44.0
		ctx.check("large combat hit regions fit %s" % phone, fits and large)
	var atlas: Image = Mobile.CombatArt.UiArt.texture("guard").atlas.get_image()
	ctx.check("new atlas backdrop is transparent", atlas.get_pixel(700,700).a < .01)
	ctx.check("new atlas button interior stays opaque", atlas.get_pixel(235,747).a > .95)
	ctx.check("combat medallion art is cached", Mobile.CombatArt.texture("guard") == Mobile.CombatArt.texture("guard"))
	live._size = original_size
	live._layout()
	ctx.check("attack is the largest thumb target", live._buttons["light"].size.x > live._buttons["ultimate"].size.x)
	ctx.check("skills arc up from attack", live._buttons["ultimate"].get_center().y < live._buttons["special"].get_center().y and live._buttons["special"].get_center().y < live._buttons["light"].get_center().y)
	ctx.check("run button removed", not live._buttons.has("run"))
	var main_rect: Rect2 = live._buttons["light"]
	ctx.check("attack anchors at lower right", main_rect.get_center().x>live._size.x*.75 and main_rect.get_center().y>live._size.y*.7)
	ctx.check("heavy sits above-left of attack", live._buttons["heavy"].get_center().x<main_rect.get_center().x and live._buttons["heavy"].get_center().y<main_rect.get_center().y)
	ctx.check("four skill circles stay on outer arc", range(4).all(func(i): return live.skill_button_rect(i).get_center().distance_to(main_rect.get_center())>live._buttons["heavy"].get_center().distance_to(main_rect.get_center())))
	ctx.check("supplied button PNGs load", Mobile.ACTIONS.all(func(a): return Mobile.CombatArt.texture(a) != null))
	ctx.check("art rectangle compensates source transparent margins", Mobile.CombatArt.texture_rect("heavy", Vector2.ONE * 100).size.x > 100)

	ctx.check("round buttons reject bounding-square corners", not live.hit_action("light", live._buttons["light"].position))
	var spaced := true
	for a in Mobile.ACTIONS:
		for b in Mobile.ACTIONS:
			if a == b or not live._buttons[a].has_area() or not live._buttons[b].has_area():
				continue
			spaced = spaced and live._buttons[a].get_center().distance_to(live._buttons[b].get_center()) > (live._buttons[a].size.x + live._buttons[b].size.x) * .5
	ctx.check("radial touch circles do not overlap", spaced)
	live._held = {2: "guard"}
	live._finger = 1
	live.vector = Vector2.ONE
	live.release()
	ctx.check("live focus/resize cleanup releases stick and guard", live._finger == -1 and live._held.is_empty() and live.vector == Vector2.ZERO)
	live._combat = true
	var stick_press := InputEventScreenTouch.new()
	stick_press.index = 3
	stick_press.pressed = true
	stick_press.position = Vector2(live._size.x * .25, live._size.y * .7)
	live._input(stick_press)
	ctx.check("joystick starts at touch origin", live._origin == stick_press.position)
	var drag := InputEventScreenDrag.new()
	drag.index = 3
	drag.position = live._origin + Vector2(live._reach * .4, 0)
	live._input(drag)
	var walking := SimInput.new()
	live.merge(walking)
	ctx.check("short drag walks without run", walking.move.x > 0 and not walking.run)
	drag.position = live._origin + Vector2(live._reach * 1.2, 0)
	live._input(drag)
	ctx.check("ordinary full drag stays normal speed", not live._running and live.vector.is_equal_approx(Vector2.RIGHT))
	drag.position = live._origin + Vector2(live._reach * 1.5, 0)
	live._input(drag)
	ctx.check("sprint requires extended drag", live._running)
	drag.position = live._origin + Vector2(live._reach * 1.3, 0)
	live._input(drag)
	ctx.check("sprint has a stable return band", live._running)
	drag.position = live._origin + Vector2(live._reach * 1.24, 0)
	live._input(drag)
	ctx.check("pulling inside return threshold stops sprint", not live._running)
	drag.position = live._origin + Vector2(1000, 0)
	live._input(drag)
	var running := SimInput.new()
	live.merge(running)
	ctx.check("long drag runs at full speed", live.vector.is_equal_approx(Vector2.RIGHT) and running.run)
	drag.position = live._origin + Vector2(live._reach * .5, 0)
	live._input(drag)
	ctx.check("pulling back returns to walking", not live._running)
	stick_press.pressed = false
	live._input(stick_press)
	ctx.check("lifting stick finger stops walking", live.vector == Vector2.ZERO)
	var run_press := InputEventScreenTouch.new()
	run_press.index = 4
	run_press.pressed = true
	run_press.position = Vector2(live._size.x * .2, live._size.y * .8)
	live._input(run_press)
	var guard_press := InputEventScreenTouch.new()
	guard_press.index = 5
	guard_press.pressed = true
	guard_press.position = live._buttons["guard"].get_center()
	live._input(guard_press)
	ctx.check("walking and guard touches hold independently", live._held.size() == 1 and live._finger == 4)
	run_press.pressed = false
	live._input(run_press)
	ctx.check("lifting movement finger preserves guard finger", live._held.size() == 1 and live._held.values().has("guard"))
	guard_press.canceled = true
	live._input(guard_press)
	ctx.check("cancelled touch releases hold", live._held.is_empty())
	live.release()
	var saved_size: Vector2i = tree.root.size
	var saved_pause: bool = tree.paused
	tree.paused = false
	tree.root.size = Vector2i(500, 900)
	live._update_context()
	ctx.check("portrait gate pauses the scene tree", tree.paused and live._gate.visible)
	tree.root.size = Vector2i(1280, 720)
	live._update_context()
	ctx.check("return landscape resumes owned pause", not tree.paused and not live._gate.visible)
	tree.paused = true
	tree.root.size = Vector2i(500, 900)
	live._update_context()
	tree.root.size = Vector2i(1280, 720)
	live._update_context()
	ctx.check("rotation preserves a preexisting pause", tree.paused)
	tree.root.size = saved_size
	tree.paused = saved_pause
	live.queue_free()
	await tree.process_frame
