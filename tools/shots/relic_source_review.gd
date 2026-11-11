extends SceneTree
func _initialize()->void:call_deferred("_run")
func _run()->void:
 root.size=Vector2i(1600,900)
 var doc:=GLTFDocument.new();var state:=GLTFState.new();assert(doc.append_from_file("res://art_source/relics/relic_native.glb",state)==OK)
 var source:Node3D=doc.generate_scene(state);root.add_child(source);source.scale=Vector3.ONE*10
 var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("384651");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.8;root.add_child(env)
 var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-40,-20,0);light.light_energy=1.2;root.add_child(light)
 var camera:=Camera3D.new();root.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=12;camera.current=true
 for angle in ['front','back','top']:
  camera.position=Vector3(0,2,12) if angle=='front' else Vector3(0,2,-12) if angle=='back' else Vector3(0,14,.01);camera.look_at(Vector3(0,1.7,0))
  for i in range(4):await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://build/relic-source-"+angle+".png")
 print("RELIC SOURCE REVIEW COMPLETE");quit()
