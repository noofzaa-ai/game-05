extends SceneTree
## Native-only smoke fixture, excluded from run_all. Launch with -- --coop-debug=2.
## Saves evidence under ignored build/mobile-validation; enemy cleanup below is visual setup only.
var failures := 0
func check(label, good):
 print("NATIVE ","PASS " if good else "FAIL ",label)
 if not good: failures += 1
func frames(count):
 for i in count: await process_frame
func _initialize():
 await process_frame
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/mobile-validation"))
 root.size=Vector2i(1100,650)
 var game=root.get_node("GameState")
 game.ensure_profile()
 game.profile.created=true
 game.profile.name="CoopTester"
 game.start_journey("ink_road",77)
 await frames(45)
 var stage=current_scene
 var session=stage._session
 check("two players render in real stage",session.is_coop() and stage._views.has(1) and stage._views.has(2))
 var start:Vector3=session.bodies[2].position
 Input.action_press("p2_right")
 await frames(30)
 Input.action_release("p2_right")
 check("secondary keyboard moves only P2",session.bodies[2].position.x > start.x+.2)
 # Clear active enemies as a native visual fixture only; real combat completion is tested by bots.
 for id in session.fighters:
  if session.fighters[id].team=="enemy":
   session.fighters[id].state=preload("res://logic/fighter.gd").State.DEAD
   session.fighters[id].hp=0
 session.bodies[1].position=Vector3(0,0,0)
 session.bodies[2].position=Vector3(1.1,0,0)
 await frames(6)
 var event={"type":"killed","target":1,"by":100}
 session.fighters[1].hp=0
 preload("res://logic/coop.gd").down(session._sim,1,event)
 await frames(20)
 check("P1 downed keeps stage running",not session.local_defeated() and session.fighters[1].revive_progress>0)
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://build/mobile-validation/m2-downed.png")
 await frames(160)
 check("P2 standing nearby revives P1",session.fighters[1].is_alive())
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://build/mobile-validation/m2-revived.png")
 root.get_node("Audio").release_all()
 await create_timer(.3).timeout
 print("NATIVE failures=",failures)
 quit(failures)
