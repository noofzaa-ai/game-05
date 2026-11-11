extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var state=root.get_node("GameState");state.ensure_profile();state.profile.created=true;state.local_perf_test=true
	var hub=load("res://scenes/hub.tscn").instantiate();root.add_child(hub);current_scene=hub
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,720)
	for frame in 8:await process_frame
	var npc=hub.npc("relic_master")
	assert(npc!=null and npc._custom_visual!=null)
	hub.place_player(Vector3(-3,0,-5));hub._rig._x=-3;hub._rig._z=-5
	for frame in 8:await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png("res://build/relic-master-camp.png")
	var manager=load("res://server/rooms/manager.gd").new()
	var profile=load("res://logic/profile.gd").new_player(manager.rules,manager.camp,RandomNumberGenerator.new())
	# Disposable fixture only. No live account grants and no fabricated boss-drop evidence.
	profile.relics.owned=[{"id":"test-boss-drop","relic":"goblin_medallion"}]
	var session=load("res://client/session/local_session.gd").new(profile,manager.rules,manager.camp,manager.loot)
	for size in [Vector2i(1280,720),Vector2i(844,390)]:
		root.size=size
		for frame in 3:await process_frame
		var panel=load("res://client/relic_panel.gd").new();root.add_child(panel);panel.setup(profile,session)
		for frame in 4:await process_frame
		panel._fit()
		var slots=panel._slots.get_children()
		assert(slots.size()==3 and not slots[0].disabled and slots[1].disabled and slots[2].disabled)
		panel._list.get_child(0).pressed.emit();await process_frame
		assert(profile.relics.equipped[0]=="test-boss-drop")
		assert(panel._window.get_rect().end.x<=size.x and panel._window.get_rect().end.y<=size.y)
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png("res://build/relic-ui-%d.png"%size.x)
		panel._slots.get_child(0).pressed.emit();await process_frame
		assert(profile.relics.equipped[0]=="")
		panel.queue_free();await process_frame
	print("RELIC MASTER REVIEW PASS: actual NPC and PC/mobile3slots/1unlocked; owned equip/unequip through session; no live grants")
	quit()
