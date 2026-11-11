extends SceneTree
func _initialize():
 call_deferred("capture")
func capture():
 root.size=Vector2i(1600,1280)
 root.content_scale_size=Vector2i(1600,1280)
 root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
 root.content_scale_factor=1.0
 for sample in ["front","angle"]:
  await capture_sample(sample)
 quit()
func capture_sample(sample: String):
 var board=Control.new()
 root.add_child(board)
 var hats=[{"path": "res://art/items/clothing/clothing_aegis_helmet_01.glb", "hide": true, "name": "aegis_helmet"}, {"path": "res://art/items/clothing/clothing_sentinel_helmet_01.glb", "hide": true, "name": "sentinel_helmet"}]
 for index in hats.size():
   var row=index/5
   var col=index%5
   var container=SubViewportContainer.new()
   container.position=Vector2(col*320,row*320)
   container.size=Vector2(320,320)
   board.add_child(container)
   var vp=SubViewport.new()
   vp.size=Vector2i(320,320)
   vp.own_world_3d=true
   vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
   container.add_child(vp)
   var env=WorldEnvironment.new()
   var e=Environment.new()
   e.background_mode=Environment.BG_COLOR
   e.background_color=Color("46545b")
   e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
   e.ambient_light_color=Color.WHITE
   e.ambient_light_energy=.5
   e.tonemap_mode=Environment.TONE_MAPPER_FILMIC
   env.environment=e
   vp.add_child(env)
   var light=DirectionalLight3D.new()
   light.rotation_degrees=Vector3(-30,-30,0)
   light.light_energy=.7
   vp.add_child(light)
   var model=load("res://client/character_model.gd").new()
   vp.add_child(model)
   assert(model.load_model("res://art/characters/chibi-studio/chibi_base_animated.glb"))
   model.set_process(false)
   model._turn.rotation.y=0
   model.dress({"hat":hats[index]["path"],"hide_hair":hats[index]["hide"],"appearance":{"face":"res://art/items/faces/face_soft_smile_01.glb","hair_style":"res://art/items/hair/hair_row4_center_part_01.glb","skin":Color(.84,.72,.63),"hair_natural":true}})
   for mi in model._body_meshes:
    if str(mi.name).begins_with("Body") or str(mi.name).begins_with("Hands") or str(mi.name).begins_with("Base foot"):mi.visible=false
   var cam=Camera3D.new()
   cam.projection=Camera3D.PROJECTION_ORTHOGONAL
   cam.size=.73
   vp.add_child(cam)
   var a=deg_to_rad(0.0 if sample=="front" else 45.0)
   var elevation=0.0
   var target=Vector3(0,1.49,0)
   for mi in model._body_meshes:
    if str(mi.name).begins_with("Face"):
     target=mi.global_transform*mi.get_aabb().get_center()
     break
   cam.position=target+Vector3(sin(a)*cos(elevation)*2,sin(elevation)*2,cos(a)*cos(elevation)*2)
   cam.look_at(target)
   var label=Label.new()
   label.text=hats[index]["name"]
   label.position=Vector2(col*320+12,row*320+12)
   label.add_theme_font_size_override("font_size",13)
   board.add_child(label)
 for i in 40:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://docs/art/previews/oval_b_hats_"+sample+".png")
 board.queue_free()
 await process_frame
