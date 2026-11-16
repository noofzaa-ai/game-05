extends SceneTree
## Mid-tier race armour review shots (2026-11-16): the hub card portrait, each race in starter vs mid, front/side/back.
## Run windowed: godot --path . --script res://tools/shots/mid_armor_shots.gd   Output: build/mid/shot_<race>_<starter|mid>_<view>.png
const Portrait := preload("res://client/card_portrait.gd")
const RACES := ["human", "viking", "elf", "runeborn"]
const SLOTS := ["shirt", "pants", "armband", "shoes"]


func _initialize() -> void:
	call_deferred("run")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/mid/"))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(Vector2i(1280, 800))
	var holder := Control.new()
	root.add_child(holder)
	var portrait: Control = Portrait.new()
	portrait.size = Vector2(300, 450)
	holder.add_child(portrait)
	await _frames(2)
	portrait.viewport.size = Vector2i(300, 450)
	portrait.set_framing("hub")
	portrait.set_render_mode(Portrait.Mode.ONCE)
	portrait.set_class("greatsword")
	await _frames(2)
	for race in RACES:
		for tier in ["starter", "mid"]:
			var looks := {}
			for slot in SLOTS:
				looks[slot] = "res://art/armor/race_shared/%s_%s%s.glb" % [race, slot, "_mid" if tier == "mid" else ""]
			portrait.model.dress(looks)
			portrait._fit_camera()
			for view in {"front": 0.0, "side": PI * 0.5, "back": PI}:
				var a: float = {"front": 0.0, "side": PI * 0.5, "back": PI}[view]
				portrait._pivot.rotation.y = a
				portrait._turn = a
				portrait._turn_target = a
				portrait.model.apply_pose(0.0)
				portrait.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
				await _frames(3)
				await RenderingServer.frame_post_draw
				portrait.viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://build/mid/shot_%s_%s_%s.png" % [race, tier, view]))
	print("MID_SHOTS DONE")
	quit()
