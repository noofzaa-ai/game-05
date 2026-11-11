extends SceneTree
func _initialize() -> void:call_deferred("_run")
func _run() -> void:
 var source=preload("res://data/perf/scenario.gd").new()
 var session=preload("res://client/session/local_session.gd").new(source.profile,source.rules,source.camp)
 var view=preload("res://client/skill_window.gd").new()
 root.content_scale_size=Vector2i.ZERO
 root.add_child(view);view.setup(source.profile,session)
 for area in [Vector2i(1440,810),Vector2i(844,390)]:
  root.size=area
  view._settle_layout()
  for i in range(8):await process_frame
  var panel=view._window.get_child(0).get_child(1)
  panel._page=1;panel._render()
  for i in range(8):await process_frame
  var list=panel._body.get_child(0).get_child(0).get_child(1).get_child(1)
  list.show_popup()
  for i in range(5):await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://build/skill-picker-review-%d.png" % area.x)
 quit()
