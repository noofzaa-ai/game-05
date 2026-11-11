extends SceneTree
func _initialize()->void:call_deferred("_run")
func settle()->void:
 for i in range(8):await process_frame
func touch(at: Vector2,pressed: bool,canceled: bool=false)->void:
 var event:=InputEventScreenTouch.new();event.index=0;event.position=at;event.pressed=pressed;event.canceled=canceled;root.push_input(event);await process_frame
func swipe(scroll: ScrollContainer)->void:
 var rect:=scroll.get_global_rect()
 var from:=Vector2(rect.position.x+100,rect.end.y-25)
 await touch(from,true)
 for step in range(1,7):
  var event:=InputEventScreenDrag.new();event.index=0;event.position=from-Vector2(0,step*20);event.relative=Vector2(0,-20);root.push_input(event);await process_frame
 await touch(from-Vector2(0,120),false)
func _run()->void:
 root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(844,390)
 var source=preload("res://data/perf/scenario.gd").new()
 var session=preload("res://client/session/local_session.gd").new(source.profile,source.rules,source.camp)
 var window=preload("res://client/skill_window.gd").new();root.add_child(window);window.setup(source.profile,session);await settle()
 var panel=window._window.get_child(0).get_child(1)
 panel._page=1;panel.draft.skills[0]={"skill":"fireball","shape":"wide","effect":"ignite"};panel._render();await settle()
 var scroll: ScrollContainer=panel._body.get_child(0)
 var draft: Dictionary=panel.draft.duplicate(true)
 await swipe(scroll)
 assert(scroll.scroll_vertical>40,"Body must swipe over buttons")
 assert(panel.draft==draft,"Swiping must not change build")
 await swipe(scroll);await swipe(scroll)
 var entries=scroll.get_child(0)
 var shape: Button=entries.get_child(6)
 assert(scroll.get_global_rect().has_point(shape.get_global_rect().get_center()),"Shape picker must be reachable")
 await touch(shape.get_global_rect().get_center(),true);await touch(shape.get_global_rect().get_center(),false);await settle()
 assert(is_instance_valid(panel._gem_picker),"Touch tap opens picker")
 var list: ScrollContainer=panel._gem_list
 await swipe(list)
 assert(list.scroll_vertical>40,"Gem list must swipe")
 assert(panel.draft==draft,"Swiping Gem list must not select an item")
 for i in range(6):await swipe(list)
 var last: Button=list.get_child(0).get_child(list.get_child(0).get_child_count()-1)
 assert(last.get_meta("gem_id")=="longer")
 assert(list.get_global_rect().has_point(last.get_global_rect().get_center()),"Last Gem must be reachable")
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://build/gem-touch-scroll-844.png")
 assert(last.disabled,"Longer is incompatible with fireball")
 await touch(last.get_global_rect().get_center(),true);await touch(last.get_global_rect().get_center(),false);await settle()
 assert(panel.draft==draft and is_instance_valid(panel._gem_picker),"Disabled Gem must not select")
 var allowed: Button=list.get_child(0).get_child(list.get_child(0).get_child_count()-2)
 assert(not allowed.disabled and allowed.get_meta("gem_id")=="quickcd")
 await touch(allowed.get_global_rect().get_center(),true);await touch(allowed.get_global_rect().get_center(),false);await settle()
 assert(panel.draft.skills[0].shape=="quickcd","Release tap selects compatible Gem at bottom")
 assert(not is_instance_valid(panel._gem_picker))
 assert(panel._body.get_child(0).scroll_vertical>40,"Re-render preserves body scroll")
 assert(panel._save.get_global_rect().end.y<=390,"Save remains on screen")
 var effect: Button=panel._body.get_child(0).get_child(0).get_child(7)
 await touch(effect.get_global_rect().get_center(),true);await touch(effect.get_global_rect().get_center(),false);await settle()
 list=panel._gem_list
 var point:=list.get_global_rect().get_center()
 var motion:=InputEventMouseMotion.new();motion.position=point;root.push_input(motion);await process_frame
 var wheel:=InputEventMouseButton.new();wheel.position=point;wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.pressed=true;root.push_input(wheel);await process_frame
 assert(list.scroll_vertical>0,"PC mouse wheel remains supported")
 for i in range(4):await swipe(list)
 var leech: Button=list.get_child(0).get_child(6)
 assert(leech.get_meta("gem_id")=="leech" and not leech.disabled)
 await touch(leech.get_global_rect().get_center(),true);await touch(leech.get_global_rect().get_center(),false,true);await settle()
 assert(panel.draft.skills[0].effect=="ignite","Canceled tap must not select")
 await touch(leech.get_global_rect().get_center(),true);await touch(leech.get_global_rect().get_center(),false);await settle()
 assert(panel.draft.skills[0].effect=="leech")
 print("GEM TOUCH PASS: mobile844x390 ScreenTouch/ScreenDrag, body+shape/effect scroll, no selection on swipe/cancel, disabled Gem protection, bottom Gem selectable, body scroll retained, save visible, PC mouse wheel")
 quit()
