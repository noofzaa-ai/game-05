extends SceneTree
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var state=root.get_node("GameState");state.ensure_profile();state.profile.created=true
 var hub=load("res://scenes/hub.tscn").instantiate();root.add_child(hub);current_scene=hub
 for i in range(12):await process_frame
 var button:Button=hub.get("_skill_button")
 assert(button!=null and button.has_meta("skill_icon_ready"))
 assert(button.get_node("SkillMenuArt").texture.get_size()==Vector2(192,192))
 assert(button.pressed.get_connections().size()>0,"Keep original Skill action")
 for size in [Vector2i(1280,720),Vector2i(844,390)]:
  root.content_scale_size=Vector2i.ZERO;root.size=size;hub.shortcut_css_override=Vector2(size)
  hub._fit_menu()
  for i in range(4):await process_frame
  assert(button.size.x>=60 and button.size.y>=60)
  assert(button.get_global_rect().end.y<=root.size.y)
  if DisplayServer.get_name()!="headless":
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png("/tmp/zorx-skill-icon-release/skill-menu-%d.png"%size.x)
 button.pressed.emit()
 for i in range(4):await process_frame
 assert(is_instance_valid(hub.get("_camp_screen")),"Skill button must open camp Skill screen")
 print("SHIPPED SKILL ICON PASS: 192px alpha texture, original 60px hitbox/signal, PC/mobile landscape, Skill opens")
 quit()
