extends SceneTree
func _initialize():
 call_deferred("capture")
func capture():
 root.size=Vector2i(1440,960)
 root.content_scale_size=Vector2i(1440,960)
 root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
 root.content_scale_factor=1.0
 for sample in ["short","silver","center","bare"]:
  await capture_sample(sample)
 quit()
func capture_sample(sample: String):
 var board=Control.new()
 root.add_child(board)
 var hairs={"short":"hair_row2_short_fringe_01","silver":"hair_row2_silver_tousled_01","center":"hair_row4_center_part_01","bare":""}
 for index in 6:
   var row=index/3
   var col=index%3
   var container=SubViewportContainer.new()
   container.position=Vector2(col*480,row*480)
   container.size=Vector2(480,480)
   board.add_child(container)
   var vp=SubViewport.new()
   vp.size=Vector2i(480,480)
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
   model.set_appearance({"face":"res://art/characters/chibi-oval-b/face_soft_smile_01.glb","hair_style":"" if sample=="bare" else "res://art/characters/chibi-oval-b/"+hairs[sample]+".glb","skin":Color(.84,.72,.63),"hair_natural":true})
   for mi in model._body_meshes:
    if sample=="bare" and mi in model._hair_meshes:mi.visible=false
    if str(mi.name).begins_with("Body") or str(mi.name).begins_with("Hands") or str(mi.name).begins_with("Base foot"):mi.visible=false
   var cam=Camera3D.new()
   cam.projection=Camera3D.PROJECTION_ORTHOGONAL
   cam.size=.73
   vp.add_child(cam)
   var angles=[0.0,45.0,90.0,180.0,45.0,45.0]
   var a=deg_to_rad(angles[index])
   var elevation=deg_to_rad(-25.0 if index==4 else (30.0 if index==5 else 0.0))
   var target=Vector3(0,1.49,0)
   for mi in model._body_meshes:
    if str(mi.name).begins_with("Face"):
     target=mi.global_transform*mi.get_aabb().get_center()
     break
   cam.position=target+Vector3(sin(a)*cos(elevation)*2,sin(elevation)*2,cos(a)*cos(elevation)*2)
   cam.look_at(target)
   var label=Label.new()
   label.text=sample.to_upper()+" - "+["FRONT","3/4","SIDE","BACK","LOW 3/4","TOP 3/4"][index]
   label.position=Vector2(col*480+12,row*480+12)
   label.add_theme_font_size_override("font_size",20)
   board.add_child(label)
 for i in 40:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://docs/art/previews/oval_b_"+sample+"_angles.png")
 board.queue_free()
 await process_frame
