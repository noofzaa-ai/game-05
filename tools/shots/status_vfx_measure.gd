extends SceneTree
## Measures each status look: meshes in the asset and meshes drawn per frame after slimming (max over the loop).
##   godot --headless --path . --script res://tools/shots/status_vfx_measure.gd
const StatusVfx := preload("res://client/status_vfx.gd")

func _initialize() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	await process_frame
	for look in ["stun", "sleep", "shock", "burn", "poison", "bleed", "slow", "sunder", "debuff", "regen", "buff"]:
		if StatusVfx.scene_path(look) == "":
			print("%-7s missing" % look)
			continue
		var raw: Node3D = load(StatusVfx.scene_path(look)).instantiate()
		raw.set("autoplay", false)
		var total := raw.find_children("*", "GeometryInstance3D", true, false).size()
		raw.free()
		var host := StatusVfx.new()
		root.add_child(host)
		host.show_effects([look] if look != "debuff" and look != "buff" else ["x"], {"x": {"kind": "buff" if look == "buff" else "debuff"}}, true)
		var peak := 0
		var tris := 0
		for i in 90:
			await process_frame
			peak = maxi(peak, host.visible_draws())
		print("%-7s meshes=%4d  drawn_peak=%3d  shown=%s" % [look, total, peak, host.shown()])
		host.queue_free()
	quit()
