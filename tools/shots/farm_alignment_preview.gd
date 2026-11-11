extends SceneTree
func _initialize()->void:call_deferred("_run")
func label_at(parent,text:String,at:Vector3,color:Color)->void:
 var label:=Label3D.new();label.text=text;label.position=at;label.font_size=42;label.pixel_size=.012;label.modulate=color;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.no_depth_test=true;parent.add_child(label)
func _run()->void:
 var source=preload("res://data/perf/scenario.gd").new();source.profile.camp_level=2;root.get_node("GameState").profile=source.profile
 root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1200,720)
 var world=load("res://client/hub_world.gd").new();root.add_child(world)
 world._farm_extension.hide()
 # Review the additional northern clearing required by the proposed row.
 for mesh in world.find_children("camp_paint","MeshInstance3D",true,false):
  var surface=mesh.mesh.surface_get_arrays(0)
  var points:PackedVector3Array=surface[Mesh.ARRAY_VERTEX]
  var indices:PackedInt32Array=surface[Mesh.ARRAY_INDEX]
  var kept:=PackedInt32Array()
  for i in range(0,indices.size(),3):
   var center:Vector3=(points[indices[i]]+points[indices[i+1]]+points[indices[i+2]])/3
   if center.x>10 and center.x<24 and center.z> -12 and center.z< -2 and center.y>.8:continue
   kept.append_array(indices.slice(i,i+3))
  surface[Mesh.ARRAY_INDEX]=kept
  var cleared:=ArrayMesh.new();cleared.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,surface);cleared.surface_set_material(0,mesh.mesh.surface_get_material(0));mesh.mesh=cleared
 world.environment.ambient_light_energy=1
 var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-65,-20,0);light.light_energy=1.4;root.add_child(light)
 # Review-only layout. Rows align with each workshop's world Z; no live layout changed.
 var preview:=Node3D.new();root.add_child(preview)
 var farm:=Node3D.new();preview.add_child(farm);world._farm_extension=farm
 for index in range(4):
  var x:=14.5+float(index%2)*3.5
  var z:float=-6.2 if index<2 else -.4
  world._farm_box(Vector3(x,.82,z),Vector3(2.6,.12,2.6),Color("503c2b"))
  for row in range(4):world._farm_box(Vector3(x,.9,z-.85+row*.55),Vector3(2.2,.08,.16),Color("705039"))
  label_at(preview,"แปลง %d"%[index+1],Vector3(x,1.15,z),Color("ffdc82"))
 for z in [-6.2,-.4]:
  world._farm_box(Vector3(11,.84,z),Vector3(4.3,.04,.35),Color("c8ad68"))
 label_at(preview,"REFINE",Vector3(8,2.7,-6.2),Color("a9dcff"))
 label_at(preview,"UPGRADE",Vector3(8,2.7,-.4),Color("a9dcff"))
 var camera:=Camera3D.new();root.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=22
 camera.position=Vector3(14,30,16);camera.look_at(Vector3(12,0,-2.8));camera.current=true
 for i in range(10):await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://build/farm-alignment-preview.png")
 quit()
