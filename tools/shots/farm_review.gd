extends SceneTree
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var source=preload("res://data/perf/scenario.gd").new()
 source.profile.camp_level=2
 var panel=preload("res://client/farm_panel.gd").new();root.add_child(panel)
 var session=preload("res://client/session/local_session.gd").new(source.profile,source.rules,source.camp)
 root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(844,390)
 panel.setup(source.profile,session,0)
 for i in range(5):await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://build/farm-review.png")
 print("FARM UI RENDERED")
 quit()
