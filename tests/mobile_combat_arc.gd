extends SceneTree
const Layout=preload("res://client/mobile_combat_layout.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 for size in [Vector2(568,320),Vector2(667,375),Vector2(844,390),Vector2(1280,720),Vector2(2160,1080)]:
  for density in [1.0,2.0]:
   # density here tests the same CSS layout at 1x/2x rendering resolution.
   var pixels=size*density;var unit=density*minf(1,minf(size.y/370,size.x/820))
   var regions=Layout.regions(pixels,unit,44*density);var circles=[]
   for action in ["light","heavy","guard","dodge"]:circles.append(regions[action])
   circles.append_array(regions.skills)
   var center:Vector2=regions.light.get_center()
   for skill in regions.skills:
    for action in ["heavy","dodge","guard"]:
     assert(skill.get_center().distance_to(center)>regions[action].get_center().distance_to(center),"All four skills must occupy the outer ring")
   var cluster:Rect2=regions.light
   for circle in circles:cluster=cluster.merge(circle)
   assert(cluster.size.x<=184*density and cluster.size.y<=185*density,"Cluster must remain compact")
   for i in circles.size():
    var a:Rect2=circles[i]
    assert(Rect2(Vector2.ZERO,pixels).encloses(a))
    assert(a.size.x>=44*density-.01)
    for j in range(i+1,circles.size()):
     var b:Rect2=circles[j];assert(a.get_center().distance_to(b.get_center())>(a.size.x+b.size.x)*.5,"Touch circles overlap")
 var controls=root.get_node("GameState").mobile_controls
 controls.force_mobile=true;controls.set_process(false);controls._size=Vector2(844,390);controls._layout();controls.enabled=true;controls._combat=true
 var hud=load("res://client/skills/skill_hud.gd").new();root.add_child(hud);hud._fit()
 for i in range(4):
  assert(hud._buttons[i].position==controls.skill_button_rect(i).position)
  assert(hud._buttons[i].size==controls.skill_button_rect(i).size)
  assert(not hud._buttons[i]._has_point(Vector2.ZERO))
  assert(hud._buttons[i]._has_point(hud._buttons[i].size*.5))
  controls.queue_skill(i)
  var input=load("res://logic/sim_input.gd").new();controls.merge(input);assert(input.skill_slot==i)
 controls.release();controls._taps.light=true
 var attack=load("res://logic/sim_input.gd").new();controls.merge(attack);assert(attack.light)
 hud.free();controls.set_process(true)
 print("MOBILE ARC PASS: 5 landscape sizes x 2 densities, eight separate circles, min44CSS targets, shared HUD/input geometry, slots0-3 and attack unchanged")
 quit()
