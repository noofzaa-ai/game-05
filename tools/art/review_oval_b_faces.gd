extends SceneTree
func _initialize():
 call_deferred("capture")
func capture():
 root.size=Vector2i(1600,1200)
 root.content_scale_size=Vector2i(1600,1200)
 root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
 root.content_scale_factor=1.0
 for sample in ["front","angle"]:
  await capture_sample(sample)
 quit()
func capture_sample(sample: String):
 var board=Control.new()
 root.add_child(board)
 var faces=["face_soft_smile_01","face_smile_01","face_anime_bored_01","face_annoyed_01","face_sad_01","face_shout_01","face_playful_01","face_prankster_01","face_devious_01","face_err_01","face_vampire_01"]
 for index in faces.size():
   var row=index/4
   var col=index%4
   var container=SubViewportContainer.new()
   container.position=Vector2(col*400,row*400)
   container.size=Vector2(400,400)
   board.add_child(container)
   var vp=SubViewport.new()
   vp.size=Vector2i(400,400)
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
   assert(model.load_model("res://art/characters/chibi-oval-b/oval_b.glb"))
   model.set_process(false)
   model._turn.rotation.y=0
   model.set_appearance({"face":"res://art/characters/chibi-oval-b/"+faces[index]+".glb","hair_style":"res://art/characters/chibi-oval-b/hair_row4_center_part_01.glb","skin":Color(.84,.72,.63),"hair_natural":true})
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
   label.text=faces[index].trim_prefix("face_").trim_suffix("_01").to_upper()
   label.position=Vector2(col*400+12,row*400+12)
   label.add_theme_font_size_override("font_size",20)
   board.add_child(label)
 for i in 40:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://docs/art/previews/oval_b_faces_"+sample+".png")
 board.queue_free()
 await process_frame
