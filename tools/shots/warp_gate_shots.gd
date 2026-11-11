extends SceneTree
## Saves pictures of the Warp Gate window (client/warp_gate_screen.gd), each tab, on a desktop window
## (1600x900), a phone in landscape (932x430) and a phone held upright (430x932), over a dark
## stand-in for the camp. Needs a window (run WITHOUT --headless):
##   godot --path . --script res://tools/shots/warp_gate_shots.gd -- <out_dir>
## (default out_dir: art_source/preview/warp_gate). Nothing is started: Enter is never pressed.

const WarpGateScreen := preload("res://client/warp_gate_screen.gd")
const InkUi := preload("res://client/ink_ui.gd")
const SIZES := {"desktop": Vector2i(1600, 900), "phone_landscape": Vector2i(932, 430), "portrait": Vector2i(430, 932)}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if not args.is_empty() else ProjectSettings.globalize_path("res://art_source/preview/warp_gate")
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame  # (the autoloads start first)
	var back := ColorRect.new()  # (a stand-in for the night camp behind the window)
	back.color = InkUi.DOLL_SHADE
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(back)
	var gate := WarpGateScreen.new()
	gate.density_override = 1.0  # (the window's real pixels are the target size, also on a Retina Mac)
	gate.starter = RefCounted.new()  # (never asked: nothing is entered)
	root.add_child(gate)
	for size_name in SIZES:
		root.size = SIZES[size_name]
		await _settle(10)
		gate._fit()
		for kind in WarpGateScreen.TABS:
			gate.show_tab(kind)
			gate._focus_start()
			await _save(out.path_join("warp_gate_%s_%s.png" % [size_name, kind]))
		gate.show_tab("farm")
		if gate.rows.size() > 2:
			gate.rows[2].grab_focus()
			await _save(out.path_join("warp_gate_%s_farm_third.png" % size_name))
	quit()


func _settle(frames: int) -> void:
	for frame in frames:
		await process_frame


func _save(file: String) -> void:
	await _settle(20)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)
	print("saved ", file)
