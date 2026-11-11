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
  print("TREE LAYOUT ",area," window=",view._window.size," panel=",panel.size," body=",panel._body.size," tree=",panel._tree_view.size)
  for child in panel.get_children():print(child.get_class()," size=",child.size," min=",child.get_combined_minimum_size())
  assert(panel._tree_view.size.y>80)
  assert(panel._save.get_global_rect().end.y<=area.y)
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://build/skill-review-%d.png" % area.x)
 quit()
