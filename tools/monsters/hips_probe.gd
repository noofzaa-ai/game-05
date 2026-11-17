extends SceneTree
func _init() -> void:
	var root := (load("res://art/characters/studio05/split/body_longbow.glb") as PackedScene).instantiate()
	var p: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
	for c in ["lb_run_forward", "lb_idle_01", "lb_draw_arrow", "lb_aim_recoil", "lb_react_small_from_front", "lb_death_forward_01"]:
		var a: Animation = p.get_animation(c)
		for t in a.get_track_count():
			if a.track_get_type(t) == Animation.TYPE_POSITION_3D:
				var n := a.track_get_key_count(t)
				print(c, " hips keys=", n, " first=", a.track_get_key_value(t, 0), " mid=", a.position_track_interpolate(t, a.length * 0.5), " last=", a.track_get_key_value(t, n - 1))
	quit()
