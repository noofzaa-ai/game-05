extends SceneTree
const Loader=preload("res://logic/map_loader.gd")
const Journey=preload("res://logic/journey_data.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
 var data=Journey.load_by_id("ink_road")
 assert(data.is_valid())
 assert(data.boss_map=="goblin_base_chief" and data.camp_map=="goblin_base_rest")
 var pairs={"goblin_arena_a":"goblin_base_gate","goblin_arena_b":"goblin_base_courtyard","goblin_arena_c":"goblin_base_quarry","brush_ring":"goblin_base_chief","goblin_rest_camp":"goblin_base_rest"}
 for old in pairs:
  var a=Loader.load_by_id(old);var b=Loader.load_by_id(pairs[old]);assert(b.is_valid(),str(b.errors))
  assert(a.solids==b.solids and a.enemy_spawns==b.enemy_spawns and a.spawn==b.spawn and a.exit_portals==b.exit_portals)
  assert(b.art_scene.begins_with("res://art/maps/goblin_base/"));assert(ResourceLoader.exists(b.art_scene))
  for enemy in b.enemy_spawns:assert(str(enemy.type).begins_with("goblin"))
  # Reachability includes full character footprint; inspect all targets on a .5m grid.
  var reached={};var queue=[Vector2i(roundi(b.spawn.x*2),roundi(b.spawn.z*2))];reached[queue[0]]=true
  while not queue.is_empty():
   var cell:Vector2i=queue.pop_front()
   for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
    var next:Vector2i=cell+offset
    if reached.has(next):continue
    var p=Vector3(next.x*.5,.05,next.y*.5)
    if absf(p.x)>b.half_width-.4 or absf(p.z)>b.half_depth-.4:continue
    var body=AABB(p-Vector3(.4,0,.4),Vector3(.8,1.8,.8));var blocked=false
    for solid in b.solids:
     if solid.box.end.y>.06 and solid.box.intersects(body):blocked=true;break
    if not blocked:reached[next]=true;queue.append(next)
  for portal in b.exit_portals:assert(reached.has(Vector2i(roundi(portal.x*2),roundi(portal.z*2))),pairs[old]+" portal unreachable")
 for size in [Vector2i(1440,810),Vector2i(844,390)]:
  root.size=size;root.content_scale_size=Vector2i.ZERO
  var ui=load("res://client/world_map_screen.gd").new();root.add_child(ui)
  for i in range(3):await process_frame
  assert(ui.destinations()[0].id=="ink_road")
  assert(Rect2(Vector2.ZERO,Vector2(size)).encloses(ui.enter_button.get_global_rect()))
  assert(Rect2(Vector2.ZERO,Vector2(size)).encloses(ui._goblin.get_global_rect()))
  ui._world_mode("farm")
  assert(ui.destinations().size()==3)
  for destination in ui.destinations():assert(str(destination.id).begins_with("goblin_base_"))
  ui.free()
 print("GOBLIN REGION PASS: 5 maps, preserved combat/spawns, full-footprint exit paths, Goblin-only destinations, PC/mobile landscape buttons")
 quit()
