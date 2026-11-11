extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	print("COMPANION REVIEW START")
	Engine.max_fps = 60
	OS.low_processor_usage_mode = false
	var state = root.get_node("GameState")
	state.ensure_profile(); state.profile.created = true; state.local_perf_test = true
	var hub = load("res://scenes/hub.tscn").instantiate()
	print("COMPANION HUB INSTANTIATED")
	root.add_child(hub); current_scene = hub
	print("COMPANION HUB READY")
	root.content_scale_size = Vector2i.ZERO
	for frame in 3: await process_frame
	assert(is_instance_valid(hub._adventurer) and hub._adventurer.model != null)
	hub.place_player(Vector3(-2.0,0,-17.0))
	for frame in 3: await physics_frame
	assert(not hub._adventurer.button.visible) # No companion-only proximity invite button.
	for size in [Vector2i(1280,720),Vector2i(844,390)]:
		root.size = size
		for frame in 3: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/companion-camp-%d.png"%size.x)
		assert(hub._adventurer.button.get_rect().end.y <= size.y)
	var before: String = JSON.stringify(state.profile.to_dict())
	var invitations=hub.get_meta("character_invitation")
	var camera=root.get_camera_3d()
	var screen=camera.unproject_position(hub._adventurer.body.position+Vector3.UP*0.8)
	invitations._select(screen)
	await process_frame
	assert(invitations.has_open_panel() and hub.has_open_panel() and not hub.can_walk())
	var buttons=invitations.popup.find_children("*","Button",true,false)
	assert(buttons.size()==2 and buttons[0].text=="ชวนออกเดินทาง")
	buttons[0].pressed.emit()
	await process_frame
	assert(hub._adventurer.panel.invite_target.begins_with("companion:"))
	hub._adventurer.panel.queue_free()
	await process_frame
	# Human presence selects the exact same menu and passes target+match to normal invite flow.
	var plaza=load("res://client/online/plaza_client.gd").new();plaza.hub=hub;hub.add_child(plaza);plaza.set_process(false)
	plaza.match_id="fixture-plaza"
	var uid="11111111-1111-1111-1111-111111111111"
	plaza.actors[uid]={"model":hub._adventurer.model,"target":hub._adventurer.body.position,"style":"blade"}
	plaza.descriptions[uid]={"name":"เพื่อนทดสอบ"}
	hub._adventurer.offer_ready=false
	invitations._select(screen)
	await process_frame
	assert(invitations.has_open_panel())
	buttons=invitations.popup.find_children("*","Button",true,false)
	assert(buttons[0].text=="ชวนออกเดินทาง")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shared-character-invite.png")
	buttons[0].pressed.emit();await process_frame
	assert(hub._adventurer.panel.invite_target==uid and hub._adventurer.panel.invite_match=="fixture-plaza")
	hub._adventurer.panel.queue_free();await process_frame
	invitations._show_invite({"id":"test-notification","name":"เพื่อนทดสอบ","room":"a".repeat(32),"invite":"b".repeat(32)},null)
	buttons=invitations.popup.find_children("*","Button",true,false)
	assert(buttons[0].text=="ยอมรับ" and buttons[1].text=="ปฏิเสธ")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shared-character-confirm.png")
	buttons[0].pressed.emit();await process_frame
	assert(hub._adventurer.panel.incoming_invite.id=="test-notification")
	plaza.actors.clear()
	assert(JSON.stringify(state.profile.to_dict()) == before)
	print("COMPANION CAMP PASS: main model, shared character-select invite menu; mobile bounds, modal input, unchanged human profile")
	quit()
