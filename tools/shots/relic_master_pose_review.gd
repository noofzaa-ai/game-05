extends SceneTree
func _initialize():call_deferred("run")
func run():
 root.size=Vector2i(1280,720);root.content_scale_size=Vector2i.ZERO;root.scaling_3d_scale=1
 var stage=Node3D.new();root.add_child(stage)
 var env=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("23373c");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_energy=.9;stage.add_child(env)
 var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-35,-25,0);stage.add_child(sun)
 var camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3.4;camera.position=Vector3(0,1.4,6);stage.add_child(camera);camera.look_at(Vector3(0,1.0,0));camera.current=true
 var original=load("res://art/npcs/relic_master/relic_master.glb").instantiate();stage.add_child(original);original.position.x=-.9
 var npc=load("res://client/hub_npc.gd").new();npc.role="relic_master";stage.add_child(npc);npc.position.x=.9;npc.set_process(false)
 for overlay in npc._overlays:overlay.visible=false
 if npc._bubble!=null:npc._bubble.visible=false
 var original_skeleton=npc._find_skeleton(original);var fixed=npc._skeleton;var head=fixed.find_bone("Head");var tip=fixed.find_bone("Head_end")
 assert(original_skeleton.get_bone_count()==fixed.get_bone_count())
 for i in fixed.get_bone_count():
  assert(original_skeleton.get_bone_rest(i)==fixed.get_bone_rest(i))
  if i!=head:assert(original_skeleton.get_bone_pose(i).is_equal_approx(fixed.get_bone_pose(i)))
 var neutral=fixed.get_bone_pose_rotation(head)
 assert(load("res://client/relic_master_pose.gd").apply(npc._custom_visual,fixed))
 assert(neutral.is_equal_approx(fixed.get_bone_pose_rotation(head)))
 # Idle always returns around the corrected baseline; never repeatedly adds the neutral correction.
 for time in [0.0,.5,1.0,2.0,5.0,20.0,100.0]:
  npc._time=time;npc._animate_role_idle()
  var up=(fixed.global_basis*(fixed.get_bone_global_pose(tip).origin-fixed.get_bone_global_pose(head).origin)).normalized()
  assert(up.dot(Vector3.UP)>.99)
  for bone in ["LeftFoot","RightFoot"]:
   var i=fixed.find_bone(bone);assert(original_skeleton.get_bone_global_pose(i).is_equal_approx(fixed.get_bone_global_pose(i)))
 npc._time=0;npc._animate_role_idle()
 for i in 2:
  var label=Label3D.new();label.text="Before" if i==0 else "After";label.font_size=42;label.position=Vector3(-.9 if i==0 else .9,2.13,0);stage.add_child(label)
 for angle in [0,-45,-90]:
  original.rotation_degrees.y=angle;npc.face(Vector2(sin(deg_to_rad(angle)),cos(deg_to_rad(angle))))
  for frame in 5:await process_frame
  await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://build/relic-master-upright-%d.png"%absi(angle))
 print("RELIC MASTER POSTURE PASS: donor rest/rig unchanged, Head pose only, upright through idle, planted feet unchanged, idempotent, 3views")
 quit()
