extends SceneTree
## Race heads in battle: the real wave journey with the squad's cards set to different races (the card's race is
## read through CardDeck.look_of in stage_view), one wide frame and a close camera on each player fighter (front and
## 3/4). Run windowed: godot --path . --script res://tools/shots/race_heads_battle.gd
## RACES=elf,viking,runeborn (default) sets the squad's races in order.
## Output: art_source/codex_review/race_heads_2026-11-14/battle_*.png

const OUT := "res://art_source/codex_review/race_heads_2026-11-14/"


func _initialize() -> void:
	call_deferred("run")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func run() -> void:
	var size := Vector2i(1280, 720)
	DisplayServer.window_set_size(size)
	root.size = size
	await process_frame
	var gs = root.get_node("GameState")
	gs.ensure_profile()
	var env := OS.get_environment("RACES")
	var races: PackedStringArray = (env if not env.is_empty() else "elf,viking,runeborn").split(",")
	var deck: Dictionary = gs.profile.card_deck
	var squad: Array = deck.get("squad", [])
	for i in squad.size():
		deck["cards"][str(squad[i])]["race"] = races[i % races.size()]
	var tag := "_".join(races)
	gs.start_journey()
	await _frames(240)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "battle_%s_wide.png" % tag))
	var scene = current_scene
	var views: Dictionary = scene.get("_views") if scene != null else {}
	var cam := Camera3D.new()
	cam.process_mode = Node.PROCESS_MODE_ALWAYS
	cam.fov = 30.0
	scene.add_child(cam)
	var shot := 0
	for id in views.keys():
		var view = views[id]
		var model = view.get("_model")
		if model == null or not model.has_method("race_look_id"):
			continue
		print("fighter ", id, " race=", model.race_look_id(), " head=", model.shown_head().name if model.shown_head() != null else "-")
		paused = true  # hold the fight still while the close shots render
		var skeleton: Skeleton3D = model.get("_skeleton")
		var head_bone := skeleton.find_bone("mixamorig_Head")
		var head_pose: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(head_bone)
		var forward: Vector3 = skeleton.global_transform.basis.z  # GLB +Z = the character's face
		forward.y = 0.0
		forward = forward.normalized()
		var head: Vector3 = head_pose.origin + Vector3(0.0, 0.0, 0.0)
		for view_name in ["front", "q34"]:
			var dir := forward if view_name == "front" else forward.rotated(Vector3.UP, deg_to_rad(40.0))
			cam.global_position = head + dir * 2.4 + Vector3(0.0, 0.15, 0.0)
			cam.look_at(head, Vector3.UP)
			cam.make_current()
			await _frames(4)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "battle_%s_%d_%s_%s.png" % [tag, shot, model.race_look_id(), view_name]))
		paused = false
		shot += 1
	print("RACE_HEADS_BATTLE DONE")
	quit()
