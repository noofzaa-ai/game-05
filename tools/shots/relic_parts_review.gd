extends SceneTree
func _initialize()->void:call_deferred("_run")
func _run()->void:
 root.size=Vector2i(1792,1024)
 var doc:=GLTFDocument.new();var state:=GLTFState.new();assert(doc.append_from_file("res://art_source/relics/review_parts.glb",state)==OK)
 var kit:Node3D=doc.generate_scene(state);root.add_child(kit)
 for i in range(28):
  var child=kit.find_child("Part%02d"%i,true,false);child.position=Vector3((i%7)*1.65,(3-i/7)*1.6,0)
  var label:=Label3D.new();label.text="PART %02d"%i;label.font_size=32;label.pixel_size=.006;label.position=child.position+Vector3(0,-.14,.2);kit.add_child(label)
 var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("35444c");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.8;root.add_child(env)
 var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-30,-20,0);light.light_energy=1.2;root.add_child(light)
 var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(4.95,2.85,20);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=11.5;camera.current=true
 for i in range(8):await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://build/relic-components-review.png");print("RELIC COMPONENT REVIEW COMPLETE");quit()
