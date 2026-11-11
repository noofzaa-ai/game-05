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
  panel._page=1;panel.draft.skills[0]={"skill":"fireball","shape":"wide","effect":"ignite"};panel._active_slot=0;panel._render()
  for i in range(8):await process_frame
  var list=panel._body.get_child(0).get_child(0).get_child(6)
  assert(list is Button and list.icon!=null)
  var row=panel._body.get_child(0).get_child(0).get_child(1)
  assert(row.get_child(2).icon!=null and row.get_child(3).icon!=null)
  list.pressed.emit()
  for i in range(5):await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://build/gem-picker-review-%d.png" % area.x)
  panel._close_gem_picker()
 quit()
