extends SceneTree
## Native import keeps the donor geometry/rig; source FBX is never modified.
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var source := ProjectSettings.globalize_path("res://../../assets/relic_master.fbx").simplify_path()
	var document = ClassDB.instantiate("FBXDocument")
	var state = ClassDB.instantiate("FBXState")
	assert(document.append_from_file(source,state)==OK)
	var node: Node3D = document.generate_scene(state)
	var bounds := AABB(); var first := true; var triangles := 0
	var meshes := []
	for mesh in node.find_children("*","MeshInstance3D",true,false):
		var transform: Transform3D = mesh.transform
		var parent = mesh.get_parent()
		while parent != node:
			transform=parent.transform*transform; parent=parent.get_parent()
		var box: AABB = transform*mesh.get_aabb()
		bounds=box if first else bounds.merge(box);first=false
		for surface in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			triangles+=(arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX]!=null else arrays[Mesh.ARRAY_VERTEX].size())/3
		meshes.append(str(mesh.name))
	assert(not first and bounds.size.y>0.01)
	var scale_factor := 1.8/bounds.size.y
	var wrapper := Node3D.new();wrapper.name="RelicMaster";wrapper.add_child(node)
	node.scale=Vector3.ONE*scale_factor
	node.position=-Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)*scale_factor
	var exporter := GLTFDocument.new();var output := GLTFState.new()
	assert(exporter.append_from_scene(wrapper,output)==OK)
	DirAccess.make_dir_recursive_absolute("res://art/npcs/relic_master")
	assert(exporter.write_to_filesystem(output,"res://art/npcs/relic_master/relic_master.glb")==OK)
	var report := {"source":source,"triangles":triangles,"meshes":meshes,"source_size":bounds.size,"game_size":bounds.size*scale_factor,"height_m":1.8,"foot_y":0,"converter":"Godot "+Engine.get_version_info().string+" native FBXDocument"}
	var file := FileAccess.open("res://art/npcs/relic_master/asset.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("RELIC MASTER IMPORT ",JSON.stringify(report))
	wrapper.free();quit()
