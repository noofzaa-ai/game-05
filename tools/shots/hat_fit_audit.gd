extends SceneTree
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var source=preload("res://data/perf/scenario.gd").new()
 root.size=Vector2i(480,560)
 root.content_scale_size=Vector2i.ZERO
 var doll=preload("res://client/paper_doll.gd").new();root.add_child(doll);doll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var hats=["fantasy_01","fantasy_02","fantasy_04","fantasy_06","fantasy_09","black","moon_witch","pumpkin_night","little_ghost"]
 for hat in hats:
  doll.dress(source.profile.loadout,"blade",source.rules.catalog,{"fashion":"red","fashion_display":"on","fashion_hat":hat,"hair_style":"red"})
  for i in range(4):await process_frame
  for angle in [0.0,1.2]:
   doll._turn=angle;doll._dragging=true
   for i in range(3):await process_frame
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png("res://build/hat-audit-%s-%d.png"%[hat,int(angle*10)])
 quit()
