extends SceneTree
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var source=preload("res://data/perf/scenario.gd").new();source.profile.camp_level=2;root.get_node("GameState").profile=source.profile
 root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,720)
 var world=load("res://client/hub_world.gd").new();root.add_child(world)
 world.environment.ambient_light_energy=.9;world.environment.fog_enabled=false
 var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-30,0);light.light_energy=1.6;root.add_child(light)
 var model:Node3D=load("res://art/props/farm_house/farm_house.glb").instantiate();root.add_child(model)
 model.position=Vector3(24,0,-3.3);model.rotation.y=-PI/2
 # Review-only additional clearing keeps complete pine components together.
 for child in world.get_children():
  if child is Node3D and "camp_hub/" in child.scene_file_path:child.hide()
 var scenery:Node3D=load("res://ex/farm_house_preview/camp_review.glb").instantiate();root.add_child(scenery)
 for mesh in scenery.find_children("*","MeshInstance3D",true,false):world._prepare_mesh(mesh)
 for name in ["FarmBoundaryTrees","TrainingBoundaryTrees","FarmHousePreviewTrees"]:
  var trees=scenery.find_child(name,true,false)
  if trees!=null:trees.hide()
 var path:=MeshInstance3D.new();var path_mesh:=BoxMesh.new();path_mesh.size=Vector3(3.2,.025,1.2);path.mesh=path_mesh;path.position=Vector3(21.4,.015,-3.3)
 var path_material:=StandardMaterial3D.new();path_material.albedo_color=Color("8b7955");path.material_override=path_material;root.add_child(path)
 var camera:=Camera3D.new();root.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.current=true
 camera.size=21;camera.position=Vector3(28,24,16);camera.look_at(Vector3(17,0,-3.3))
 for i in range(8):await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://build/farm-house-placement-preview.png")
 camera.size=8;camera.position=Vector3(18,8,3);camera.look_at(model.position+Vector3(0,1,0))
 for i in range(6):await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://build/farm-house-close-preview.png")
 print("FARM HOUSE PREVIEW: existing four farm plots + native imported FBX to right, x24 z-3.3, west-facing, review only")
 quit()
