extends SceneTree
func _initialize()->void:call_deferred("_run")
func _run()->void:
 root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1600,1000);root.scaling_3d_scale=1.0;root.msaa_3d=Viewport.MSAA_4X
 var source=preload("res://data/perf/scenario.gd").new()
 var game=root.get_node("GameState");game.profile=source.profile
 var scene:=Node3D.new();root.add_child(scene)
 var env:=WorldEnvironment.new();var settings:=Environment.new();settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("142029");settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_color=Color.WHITE;settings.ambient_light_energy=.7;env.environment=settings;scene.add_child(env)
 var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-30,0);light.light_energy=1.2;scene.add_child(light)
 var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=14;scene.add_child(camera);camera.position=Vector3(6,10,21);camera.look_at(Vector3(6,0,4));camera.current=true
 var world=load("res://client/hub_world.gd").new()
 world._base_half_extents=Vector2(.001,10)
 var holder:=Node3D.new();scene.add_child(holder);world._farm_extension=holder
 var crops=preload("res://logic/farm.gd").config().crops
 var ids:=["carrot","potato","herb"]
 var titles:=["CARROT","POTATO","HERB"]
 var names:=["SOWN","SPROUT","GROWING","READY"]
 for row in range(3):
  for stage in range(4):
   var at:=Vector3(stage*3.5,0,row*3.4)
   var age:=int(float(crops[ids[row]].seconds)*[.05,.3,.6,1.0][stage])
   source.profile.farm={"plots":{"0":{"crop":ids[row],"planted_at":int(Time.get_unix_time_from_system())-age}}}
   world._farm_growth_key="";world._update_farm_plants()
   var plants=world._farm_plants.duplicate();holder.add_child(plants);plants.position=at-world.farm_plot_position(0)
   world._farm_box(at+Vector3(0,.04,0),Vector3(2.6,.12,2.6),Color("503c2b"))
   for rid in range(4):world._farm_box(at+Vector3(0,.12,-.85+rid*.55),Vector3(2.2,.08,.16),Color("705039"))
   var label:=Label3D.new();label.text=titles[row]+" / "+names[stage];label.font_size=30;label.pixel_size=.009;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.no_depth_test=true;label.position=at+Vector3(0,0,1.9);holder.add_child(label)
 world._farm_plants.queue_free()
 var layer:=CanvasLayer.new();root.add_child(layer)
 var title:=Label.new();title.text="IN-GAME CROP SPRITES · ROOT-ANCHORED · 3 GROWTH STAGES";title.position=Vector2(100,35);title.add_theme_font_size_override("font_size",28);layer.add_child(title)
 for i in range(8):await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://build/farm-crops-sprites-review.png")
 world.free();print("CROP REVIEW SAVED");quit()
