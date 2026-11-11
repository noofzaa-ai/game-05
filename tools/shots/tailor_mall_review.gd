extends SceneTree
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var source=preload("res://data/perf/scenario.gd").new()
 var session=preload("res://client/session/local_session.gd").new(source.profile,source.rules,source.camp)
 root.content_scale_size=Vector2i.ZERO
 var bg:=ColorRect.new();bg.color=Color("09151a");bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(bg)
 var panel=preload("res://client/look_panel.gd").new();root.add_child(panel)
 panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 panel.setup(source.profile,source.rules,source.sim.combat,session)
 for area in [Vector2i(1440,810),Vector2i(844,390)]:
  root.size=area;panel.set_mode("compact")
  for page in ["face","hair","fashion"]:
   panel.show_tab(page)
   for i in range(10):await process_frame
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png("res://build/tailor-%s-%d.png" % [page,area.x])
 panel.show_tab("fashion");panel._show_mall_category("fashion_hat")
 panel._mall_pick("fashion_hat","black")
 for i in range(10):await process_frame
 assert(panel._buy.get_global_rect().end.y<=390)
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://build/mall-preview-844.png")
 panel._buy_pressed()
 for i in range(6):await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://build/mall-confirm-844.png")
 panel._cancel_purchase()
 quit()
