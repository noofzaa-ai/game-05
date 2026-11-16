extends SceneTree
## Online tutorial walk against the LOCAL stack (build/localstack/up.py). Fresh device account each run.
## Real hub scene, real AccountSession → Nakama → profile worker. Clicks the real target control at each step.
## godot --path . --script res://tools/localstack/walk.gd -- --key KEY --size 1920x1080 --out DIR

const Tutorial := preload("res://logic/tutorial.gd")
var Driver
var out_dir := "user://walk"
var log_lines: PackedStringArray = []
var fails := 0


func say(s: String) -> void:
	print(s)
	log_lines.append(s)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	Driver = load("res://client/tutorial_driver.gd")
	var key := ""
	var size := Vector2i(1920, 1080)
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--key": key = args[i + 1]
		if args[i] == "--size": size = Vector2i(int(args[i + 1].split("x")[0]), int(args[i + 1].split("x")[1]))
		if args[i] == "--out": out_dir = args[i + 1]
		if args[i] == "--fps": Engine.max_fps = int(args[i + 1])
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = size
	DisplayServer.window_set_size(size)
	var online = root.get_node("Online")
	online.store.path = "user://walk_%d.json" % Time.get_ticks_usec()
	await online.connect_account({"version": 1, "enabled": true, "scheme": "http", "host": "127.0.0.1", "port": 7350, "client_key": key})
	say("auth status=%s reason=%s" % [online.status, online.reason])
	if online.status != online.Status.AUTHENTICATED:
		return finish()
	var gs = root.get_node("GameState")
	var ok: bool = await gs.connect_account_profile()
	say("profile ok=%s err=%s step=%s" % [ok, gs.online_error, gs.profile.tutorial if ok else "-"])
	if not ok:
		return finish()
	change_scene_to_file(gs.CARD_DECK_SCENE)
	await wait(1.5)
	var n := 0
	var last := ""
	var same := 0
	while n < 60:
		n += 1
		var hub = current_scene
		var step := str(gs.profile.tutorial.get("step", ""))
		if hub == null or not hub.has_method("tutorial_show_hub"):
			say("[%02d] scene=%s step=%s (not the hub)" % [n, current_scene.scene_file_path if current_scene else "null", step])
			if current_scene and (current_scene.scene_file_path.ends_with("stage.tscn") or current_scene.scene_file_path.ends_with("journey.tscn")):
				await shot("%02d_battle_%s" % [n, step])
				await battle(step)
				continue
			await wait(1.0)
			continue
		var driver = hub.tutorial
		var shown: String = driver.step if driver != null else "<no driver>"
		await shot("%02d_%s" % [n, step])
		if step == "done" or step == Tutorial.DONE:
			say("[%02d] DONE" % n)
			break
		if step == last:
			same += 1
		else:
			same = 0
		last = step
		if same >= 3:
			fail("[%02d] STUCK at step=%s (driver shows %s, overlay=%s fallback=%s)" % [n, step, shown, driver.overlay.visible if driver else "-", driver._fallback if driver else "-"])
			break
		var data := Tutorial.step_data(step)
		var target := str(data.get("target", ""))
		var ov = driver.overlay
		var next_btn: Button = ov._next
		say("[%02d] server step=%s driver=%s target=%s next_visible=%s hole=%s" % [n, step, shown, target, next_btn.visible and ov.visible, ov.hole])
		if shown != step:
			fail("    client shows %s but server is at %s" % [shown, step])
		if not ov.next_pressed.is_connected(_on_next_seen):
			ov.next_pressed.connect(_on_next_seen)
			hub.tutorial_event.connect(func(e): say("    event %s" % e))
		say("    driver busy=%s session=%s remote=%s" % [driver._busy, gs.session, gs.session.has_method("is_remote")])
		if next_btn.visible and ov.visible and next_btn.is_visible_in_tree():
			await click(next_btn.get_global_rect().get_center())
		elif not target.is_empty():
			var node: Control = Driver.find_target(hub, target)
			if node == null:
				fail("    target %s not found on screen" % target)
				await wait(2.5)
				continue
			var r := node.get_global_rect()
			if not ov.hole.encloses(r.grow(-1)):
				fail("    cut-out %s does not cover target %s" % [ov.hole, r])
			await click(r.get_center())
		else:
			fail("    no target and no Next button")
		await wait(2.0)
	finish()


func _on_next_seen() -> void:
	say("    next_pressed fired")


func battle(step: String) -> void:
	# battle_tip: tap a card name (the squad strip) or wait 8 s; then let the fight finish quickly.
	await wait(3.0)
	var names = Driver.find_target(root, "SquadNames")
	say("    battle: SquadNames %s" % ("found" if names else "missing"))
	await shot("battle_tip_%s" % step)
	if names:
		await click(names.get_global_rect().get_center())
	await wait(10.0)
	var start_scene: String = current_scene.scene_file_path if current_scene else ""
	var t := 0.0
	var seen := {}
	while current_scene and current_scene.scene_file_path == start_scene and t < 1200.0:
		await wait(5.0)
		t += 5.0
		if int(t) % 60 == 0:
			await shot("battle_t%04d" % int(t))
		# press any visible result button that returns to camp
		for b in current_scene.find_children("*", "Button", true, false):
			if b.is_visible_in_tree() and not seen.has(str(b.text)):
				seen[str(b.text)] = true
				say("    battle button visible: '%s' (t=%d)" % [b.text, t])
		for b in current_scene.find_children("*", "Button", true, false):
			if b.is_visible_in_tree() and not b.disabled and (str(b.text).to_lower().contains("cards") or str(b.text).contains("การ์ด") or str(b.text).to_lower().contains("camp") or str(b.text).contains("กลับ") or str(b.text).to_lower().contains("continue") or str(b.text).to_lower().contains("hub")):
				Engine.time_scale = 1.0
				await shot("battle_result")
				say("    result button: %s" % b.text)
				b.pressed.emit()
				await wait(2.0)
				break
	Engine.time_scale = 1.0
	await wait(2.0)


func click(at: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		root.push_input(e, true)
		await process_frame


func wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))


func fail(s: String) -> void:
	fails += 1
	say("FAIL " + s)


func finish() -> void:
	say("WALK_FAILS=%d" % fails)
	var f := FileAccess.open(out_dir.path_join("walk.log"), FileAccess.WRITE)
	f.store_string("\n".join(log_lines))
	f.close()
	quit(1 if fails else 0)
