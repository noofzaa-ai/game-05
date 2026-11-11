extends SceneTree
func _initialize()->void:call_deferred("_run")
func _run()->void:
	root.content_scale_size=Vector2i.ZERO
	# Actual camp art behind the panel, not a generated mockup backdrop.
	var backdrop=Node3D.new();root.add_child(backdrop)
	var camp=load("res://art/maps/camp_hub/camp_hub.glb").instantiate();backdrop.add_child(camp)
	var environment=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("283b38");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_energy=.8;backdrop.add_child(environment)
	var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-40,-35,0);sun.light_color=Color("ffdfa4");sun.light_energy=1.2;backdrop.add_child(sun)
	var camera=Camera3D.new();backdrop.add_child(camera);camera.position=Vector3(8,10,14);camera.look_at(Vector3(0,0,0));camera.current=true
	var manager=load("res://server/rooms/manager.gd").new()
	var profile=load("res://logic/profile.gd").new_player(manager.rules,manager.camp,RandomNumberGenerator.new())
	# Disposable fixture only. No live account grants and no fabricated boss-drop evidence.
	profile.relics.owned=[{"id":"test-boss-drop","relic":"goblin_medallion"},{"id":"test-lantern","relic":"goblin_lantern"}]
	var session=load("res://client/session/local_session.gd").new(profile,manager.rules,manager.camp,manager.loot)
	for size in [Vector2i(1280,720),Vector2i(844,390),Vector2i(667,375)]:
		root.size=size
		for frame in 3:await process_frame
		var panel=load("res://client/relic_panel.gd").new();root.add_child(panel);panel.setup(profile,session)
		for frame in 4:await process_frame
		panel._fit()
		var slots=panel._slots.get_children()
		assert(slots.size()==3 and not slots[0].disabled and slots[1].disabled and slots[2].disabled)
		assert(panel._list.get_child_count()==2)
		var before=profile.relics.equipped.duplicate()
		panel._list.get_child(0).pressed.emit();await process_frame
		assert(profile.relics.equipped==before) # Selecting only previews.
		assert(panel._preview.texture!=null)
		panel._action.pressed.emit();await process_frame
		assert(profile.relics.equipped[0]=="test-boss-drop")
		for frame in 4:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/relic-original-spec-%d.png"%size.x)
		assert(panel._slots.get_child(1).disabled and panel._slots.get_child(2).disabled)
		panel._list.get_child(1).pressed.emit();await process_frame
		assert(profile.relics.equipped[0]=="test-boss-drop")
		assert(panel._preview.texture==load("res://art/relics/goblin/icons/goblin_lantern.png"))
		panel._action.pressed.emit();await process_frame
		assert(profile.relics.equipped[0]=="test-lantern")
		var bounds=Rect2(Vector2.ZERO,Vector2(size))
		assert(bounds.encloses(panel._window.get_global_rect()))
		assert(bounds.encloses(panel._action.get_global_rect()))
		assert(bounds.encloses(panel._close_button.get_global_rect()))
		assert(panel._action.size.y>=48)
		assert(panel._close_button.size.x>=48 and panel._close_button.size.y>=48)
		assert(absf(panel._close_button.size.x-panel._close_button.size.y)<1)
		for slot in panel._slots.get_children():assert(absf(slot.size.x-slot.size.y)<2)
		var card=panel._list.get_child(0)
		assert(card.size.x/card.size.y>1.45 and card.size.x/card.size.y<1.65)
		assert(panel._window.get_node("Showcase").position.x<panel._slots.position.x)
		assert(panel._window.get_theme_stylebox("panel").get("base") is StyleBoxFlat)
		for frame in 3:await process_frame
		await RenderingServer.frame_post_draw
		assert(panel._showcase._viewport.render_target_update_mode in [SubViewport.UPDATE_ONCE,SubViewport.UPDATE_DISABLED])
		var metrics={"screen":str(size),"window":str(panel._window.size),"showcase":str(panel._window.get_node("Showcase").size),"slot":str(panel._slots.get_child(0).size),"item_card":str(card.size),"detail":str(panel._window.get_node("Detail").size),"primary_button":str(panel._action.size),"close":str(panel._close_button.size),"theme":"original InkUi window/panel/button/close"}
		var report=FileAccess.open("res://build/relic-frame-metrics-%d.json"%size.x,FileAccess.WRITE);report.store_string(JSON.stringify(metrics,"  "));report.close()

		await RenderingServer.frame_post_draw

		panel._action.pressed.emit();await process_frame
		assert(profile.relics.equipped[0]=="")
		# Future collections remain swipeable without moving the action below the screen.
		for index in 60:profile.relics.owned.append({"id":"extra-%d"%index,"relic":"goblin_medallion"})
		panel._render()
		for frame in 3:await process_frame
		assert(panel._scroll.get_v_scroll_bar().max_value>panel._scroll.size.y)
		var drag=InputEventScreenTouch.new();drag.index=3;drag.position=panel._scroll.global_position+Vector2(30,60);drag.pressed=true;panel._scroll._input(drag)
		var move=InputEventScreenDrag.new();move.index=3;move.position=drag.position-Vector2(0,60);panel._scroll._input(move)
		drag.pressed=false;drag.position=move.position;panel._scroll._input(drag)
		assert(panel._scroll.scroll_vertical>0 and profile.relics.equipped[0]=="")
		profile.relics.owned.resize(2)
		panel.queue_free();await process_frame
	print("RELIC MASTER REVIEW PASS: icon grid/large preview; selection no mutation; equip/swap/unequip authority; 3 landscape sizes, actions/close in bounds; no live grants")
	quit()
